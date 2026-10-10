"""Windows IPA preparation, signing and installation. No Apple account storage."""
import argparse
import asyncio
import datetime as dt
import fnmatch
import json
import os
import plistlib
from pathlib import Path, PurePosixPath
import stat
import subprocess
import sys
import tempfile
import zipfile

if sys.platform == 'win32':
    asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())
    for stream in (sys.stdout, sys.stderr):
        if stream is not None and hasattr(stream, 'reconfigure'):
            stream.reconfigure(encoding='utf-8', errors='replace')


class InstallError(Exception):
    def __init__(self, code, message):
        self.code = code
        super().__init__(message)


def run(command, timeout=120, cwd=None):
    try:
        result = subprocess.run(command, capture_output=True, timeout=timeout, cwd=cwd,
                                env={**os.environ, 'PYTHONIOENCODING': 'utf-8'})
    except FileNotFoundError:
        raise InstallError('DEPENDENCY_MISSING', '缺少依赖工具，请检查安装路径。')
    except subprocess.TimeoutExpired:
        raise InstallError('TIMEOUT', '操作超时，请解锁手机、确认信任并重试。')
    if result.returncode:
        # Raw tool output can contain pairing keys, account names and local paths.
        raise InstallError('TOOL_FAILED', '外部工具执行失败，请检查驱动、设备信任和签名材料。')
    return result.stdout


def pmd(*args, timeout=120):
    prefix = [sys.executable, '--pmd'] if getattr(sys, 'frozen', False) else [sys.executable, '-m', 'pymobiledevice3']
    return run([*prefix, *args], timeout=timeout)


def devices():
    data = json.loads(pmd('usbmux', 'list', timeout=15))
    return [{'udid': d['Identifier'], 'name': d.get('DeviceName', 'iPhone'),
             'ios': d.get('ProductVersion'), 'connection': d.get('ConnectionType')}
            for d in data]


def require_device(udid):
    if not any(d['udid'] == udid for d in devices()):
        raise InstallError('DEVICE_NOT_FOUND', '未发现指定手机，请解锁后重新连接数据线。')


def unpack(ipa, directory):
    with zipfile.ZipFile(ipa) as archive:
        seen = set()
        total = 0
        for member in archive.infolist():
            path = PurePosixPath(member.filename)
            total += member.file_size
            key = member.filename.casefold()
            if (path.is_absolute() or '..' in path.parts or '\\' in member.filename
                    or ':' in member.filename or key in seen
                    or stat.S_ISLNK(member.external_attr >> 16) or total > 2_000_000_000):
                raise InstallError('INVALID_IPA', 'IPA 包含不安全或过大的文件。')
            seen.add(key)
        archive.extractall(directory)
    apps = list((directory / 'Payload').glob('*.app'))
    if len(apps) != 1 or not (apps[0] / 'Info.plist').is_file():
        raise InstallError('INVALID_IPA', 'IPA 必须包含一个主应用。')
    if list(apps[0].glob('PlugIns/*.appex')) or (apps[0] / 'Watch').exists():
        raise InstallError('EXTENSIONS_UNSUPPORTED', '此版本仅支持无扩展的 LocationMocker IPA。')
    return apps[0]


def pack(directory, destination):
    with zipfile.ZipFile(destination, 'w', zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(directory.rglob('*')):
            if path.is_file():
                archive.write(path, path.relative_to(directory).as_posix())


def profile_data(raw, openssl='openssl'):
    # Verify CMS integrity, without treating local CA trust as Apple trust.
    return plistlib.loads(cms_decode(raw, openssl))


def cms_decode(raw, openssl):
    try:
        result = subprocess.run([openssl, 'cms', '-verify', '-noverify', '-inform', 'DER'],
                                input=raw, capture_output=True, timeout=15)
    except FileNotFoundError:
        raise InstallError('DEPENDENCY_MISSING', '需要 OpenSSL 才能读取描述文件。')
    except subprocess.TimeoutExpired:
        raise InstallError('TIMEOUT', '读取描述文件超时。')
    if result.returncode:
        raise InstallError('INVALID_PROFILE', '描述文件 CMS 签名校验失败。')
    return result.stdout


def validate_profile(profile, udid, bundle, certificate=None):
    expiry = profile['ExpirationDate'].replace(tzinfo=dt.timezone.utc)
    if expiry <= dt.datetime.now(dt.timezone.utc):
        raise InstallError('PROFILE_EXPIRED', '描述文件已过期，请从开发者账户获取新文件。')
    if udid not in profile.get('ProvisionedDevices', []):
        raise InstallError('DEVICE_NOT_REGISTERED', '此手机未包含在描述文件中。')
    application = profile.get('Entitlements', {}).get('application-identifier', '')
    prefix, _, pattern = application.partition('.')
    if prefix not in profile.get('ApplicationIdentifierPrefix', []) or not fnmatch.fnmatchcase(bundle, pattern):
        raise InstallError('BUNDLE_MISMATCH', '描述文件与应用标识不匹配。')
    if certificate is not None and certificate not in profile.get('DeveloperCertificates', []):
        raise InstallError('CERTIFICATE_MISMATCH', '证书不属于此描述文件。')
    return {'expires': expiry.isoformat(), 'days_remaining': (expiry - dt.datetime.now(dt.timezone.utc)).days}


async def make_pairing(udid, output):
    from pymobiledevice3.lockdown import create_using_usbmux
    from pymobiledevice3.remote.tunnel_service import RemotePairingLockdownService
    from pymobiledevice3.exceptions import RemotePairingCompletedError
    lockdown = await create_using_usbmux(serial=udid)
    service = None
    try:
        service = await RemotePairingLockdownService.create(lockdown)
        try:
            await service.connect(autopair=True)
        except RemotePairingCompletedError:
            pass
        record = service.pair_record
        if not record or not all(k in record for k in ('private_key', 'public_key')):
            raise InstallError('PAIRING_FAILED', '无法生成手机专属配对文件。')
        output.write_bytes(plistlib.dumps({'identifier': service.identifier,
                                         'private_key': record['private_key'],
                                         'public_key': record['public_key']}))
    finally:
        if service is not None:
            await service.close()
        await lockdown.close()


def prepare(args):
    require_device(args.udid)
    output = Path(args.output).resolve()
    if output.exists():
        raise InstallError('OUTPUT_EXISTS', '目标文件已存在，请选择新路径。')
    with tempfile.TemporaryDirectory(prefix='locationmocker-') as temporary:
        directory = Path(temporary) / 'package'
        app = unpack(Path(args.ipa), directory)
        asyncio.run(asyncio.wait_for(make_pairing(args.udid, app / 'rp_pairing_file.plist'), timeout=90))
        # An IPA modified after signing cannot be installed until signed again.
        pack(directory, output)
    return {'output': str(output), 'requires_signing': True}


def sign_install(args, password=None):
    from cryptography.hazmat.primitives.serialization import pkcs12, Encoding, PrivateFormat, NoEncryption
    import getpass
    require_device(args.udid)
    profile = profile_data(Path(args.profile).read_bytes(), args.openssl)
    if password is None:
        password = getpass.getpass('P12 密码（留空表示无密码）: ')
    key, cert, chain = pkcs12.load_key_and_certificates(Path(args.p12).read_bytes(), password.encode() or None)
    if key is None or cert is None:
        raise InstallError('INVALID_CERTIFICATE', 'P12 必须包含证书及其私钥。')
    now = dt.datetime.now(dt.timezone.utc)
    if not cert.not_valid_before_utc <= now < cert.not_valid_after_utc:
        raise InstallError('CERTIFICATE_EXPIRED', '证书尚未生效或已经过期。')
    with tempfile.TemporaryDirectory(prefix='locationmocker-') as temporary:
        work = Path(temporary)
        app = unpack(Path(args.ipa), work / 'package')
        info = plistlib.loads((app / 'Info.plist').read_bytes())
        bundle = info['CFBundleIdentifier']
        status = validate_profile(profile, args.udid, bundle, cert.public_bytes(Encoding.DER))
        asyncio.run(asyncio.wait_for(make_pairing(args.udid, app / 'rp_pairing_file.plist'), timeout=90))
        pem = work / 'key.pem'
        pem.write_bytes(key.private_bytes(Encoding.PEM, PrivateFormat.PKCS8, NoEncryption()))
        pem.chmod(0o600)
        certificates = work / 'certificate.pem'
        certificates.write_bytes(cert.public_bytes(Encoding.PEM) + b''.join(c.public_bytes(Encoding.PEM) for c in chain or []))
        signed = work / 'signed.ipa'
        run([args.zsign, '-f', '-k', str(pem), '-c', str(certificates), '-m', str(Path(args.profile).resolve()),
             '-o', str(signed), str(app)], timeout=300, cwd=work)
        # Require the signed output to preserve the exact profile and pairing resource.
        with zipfile.ZipFile(signed) as archive:
            root = next(n.rsplit('/', 1)[0] for n in archive.namelist() if n.count('/') == 2 and n.endswith('/Info.plist'))
            if archive.read(root + '/embedded.mobileprovision') != Path(args.profile).read_bytes():
                raise InstallError('SIGNING_FAILED', '签名产物的描述文件不匹配。')
            if archive.read(root + '/rp_pairing_file.plist') != (app / 'rp_pairing_file.plist').read_bytes():
                raise InstallError('SIGNING_FAILED', '签名产物丢失了设备配对文件。')
        pmd('apps', 'install', '--udid', args.udid, str(signed), timeout=300)
        metadata = json.loads(pmd('apps', 'query', '--udid', args.udid, bundle))
        if bundle not in metadata:
            raise InstallError('INSTALL_FAILED', '安装后无法查询到应用。')
    return {'installed': True, 'bundle': bundle, **status}


def status(args):
    with zipfile.ZipFile(args.ipa) as archive:
        roots = [n.rsplit('/', 1)[0] for n in archive.namelist() if n.startswith('Payload/') and n.count('/') == 2 and n.endswith('/Info.plist')]
        if len(roots) != 1:
            raise InstallError('INVALID_IPA', 'IPA 主应用不唯一。')
        bundle = plistlib.loads(archive.read(roots[0] + '/Info.plist'))['CFBundleIdentifier']
        profile = profile_data(archive.read(roots[0] + '/embedded.mobileprovision'), args.openssl)
    return {'bundle': bundle, **validate_profile(profile, args.udid, bundle)}


def main(argv=None):
    parser = argparse.ArgumentParser(description='LocationMocker Windows 安装与续签')
    parser.add_argument('--json', action='store_true')
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('devices')
    for name in ('prepare', 'install', 'renew', 'status'):
        command = commands.add_parser(name)
        command.add_argument('--udid', required=True)
        command.add_argument('--ipa', required=True)
        if name == 'prepare':
            command.add_argument('--output', required=True)
        else:
            command.add_argument('--openssl', default='openssl')
        if name in ('install', 'renew'):
            command.add_argument('--p12', required=True)
            command.add_argument('--profile', required=True)
            command.add_argument('--zsign', default='zsign')
    args = parser.parse_args(argv)
    try:
        result = devices() if args.command == 'devices' else prepare(args) if args.command == 'prepare' else status(args) if args.command == 'status' else sign_install(args)
        print(json.dumps({'ok': True, 'result': result}, ensure_ascii=False))
        return 0
    except InstallError as error:
        print(json.dumps({'ok': False, 'code': error.code, 'message': str(error)}, ensure_ascii=False))
    except Exception:
        print(json.dumps({'ok': False, 'code': 'OPERATION_FAILED', 'message': '操作失败，请检查输入文件、驱动及设备信任状态。'}, ensure_ascii=False))
    return 1


if __name__ == '__main__':
    sys.exit(main())

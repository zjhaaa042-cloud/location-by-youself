"""Read-only local prerequisite report; never signs or changes a device."""
import importlib.metadata
import json
from pathlib import Path
import sys


def main():
    report = {'python': sys.version.split()[0], 'dependencies': {},
              'free_sign_helper': (Path(__file__).parent / 'free-sign' / 'target' /
                                   'release' / 'locationmocker-free-sign.exe').is_file()}
    for package in ('pymobiledevice3', 'cryptography'):
        try:
            report['dependencies'][package] = importlib.metadata.version(package)
        except importlib.metadata.PackageNotFoundError:
            report['dependencies'][package] = 'MISSING'
    if report['dependencies']['pymobiledevice3'] != 'MISSING':
        import installer
        try:
            # Only expose a count: UDIDs need not be written to a report.
            report['connected_devices'] = len(installer.devices())
        except installer.InstallError as error:
            report['device_check'] = {'code': error.code, 'message': str(error)}
        except Exception:
            report['device_check'] = 'Unavailable; check Apple driver and device trust.'
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

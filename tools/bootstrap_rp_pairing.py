#!/usr/bin/env python3
"""Create the device-specific Ed25519 record used by LocationMocker.

The output contains a private key. Keep it local and never commit or share it.
Requires pymobiledevice3 9.x and an iPhone already trusted by this Mac.
"""

import argparse
import asyncio
import plistlib
import shutil
import sys
import tempfile
from pathlib import Path

from pymobiledevice3.exceptions import RemotePairingCompletedError
from pymobiledevice3.lockdown import create_using_usbmux
from pymobiledevice3.remote.tunnel_service import RemotePairingLockdownService


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--udid", required=True, help="iPhone UDID shown by Xcode/devicectl")
    parser.add_argument(
        "--lockdown-record",
        required=True,
        type=Path,
        help="Record produced by `pymobiledevice3 lockdown save-pair-record`",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("LocationMocker/LocationMocker/Resources/Debug/rp_pairing_file.plist"),
        help="Destination bundled into the development build",
    )
    return parser.parse_args()


async def run(args: argparse.Namespace) -> int:
    if not args.lockdown_record.is_file():
        print(f"Lockdown record not found: {args.lockdown_record}", file=sys.stderr)
        return 2

    with tempfile.TemporaryDirectory() as temporary_directory:
        records_dir = Path(temporary_directory)
        shutil.copy(args.lockdown_record, records_dir / f"{args.udid}.mobiledevicepairing")

        lockdown = await create_using_usbmux(
            serial=args.udid,
            autopair=False,
            pairing_records_cache_folder=records_dir,
        )
        print(f"[bootstrap] lockdown connected: iOS {lockdown.product_version}")

        service = await RemotePairingLockdownService.create(lockdown)
        try:
            await service.connect(autopair=True)
            print("[bootstrap] existing remote-pairing identity verified")
        except RemotePairingCompletedError:
            print("[bootstrap] promptless SRP pair-setup completed")

        record = service.pair_record
        if not record or "public_key" not in record or "private_key" not in record:
            print("Remote-pairing record was not generated", file=sys.stderr)
            return 3

        output = {
            "identifier": service.identifier,
            "public_key": record["public_key"],
            "private_key": record["private_key"],
        }
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_bytes(plistlib.dumps(output))
        args.output.chmod(0o600)
        print(f"[bootstrap] wrote {args.output} (mode 0600; never commit this file)")
        return 0


def main() -> int:
    return asyncio.run(run(parse_args()))


if __name__ == "__main__":
    raise SystemExit(main())

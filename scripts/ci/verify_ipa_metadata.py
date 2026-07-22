#!/usr/bin/env python3
import argparse
import json
import plistlib
import re
import sys
import zipfile
from pathlib import Path


APP_INFO_PATTERN = re.compile(r"^Payload/[^/]+\.app/Info\.plist$")


class VerificationError(RuntimeError):
    pass


def read_application_info(ipa: Path) -> dict[str, object]:
    if not ipa.is_file():
        raise VerificationError(f"IPA does not exist: {ipa}")

    try:
        with zipfile.ZipFile(ipa) as archive:
            candidates = [name for name in archive.namelist() if APP_INFO_PATTERN.fullmatch(name)]
            if len(candidates) != 1:
                raise VerificationError(
                    "expected exactly one Payload/*.app/Info.plist, "
                    f"found {len(candidates)}"
                )
            return plistlib.loads(archive.read(candidates[0]))
    except (zipfile.BadZipFile, plistlib.InvalidFileException) as error:
        raise VerificationError(f"invalid IPA metadata: {error}") from error


def verify(
    ipa: Path,
    *,
    bundle_id: str,
    version: str,
    build_number: str,
) -> dict[str, str]:
    info = read_application_info(ipa)
    expected = {
        "CFBundleIdentifier": bundle_id,
        "CFBundleShortVersionString": version,
        "CFBundleVersion": build_number,
    }
    mismatches = [
        f"{key}: expected {expected_value!r}, found {info.get(key)!r}"
        for key, expected_value in expected.items()
        if str(info.get(key)) != expected_value
    ]
    if mismatches:
        raise VerificationError("; ".join(mismatches))

    return {
        "ipa": str(ipa.resolve()),
        "bundle_id": bundle_id,
        "version": version,
        "build_number": build_number,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Verify SideStore IPA identity metadata.")
    parser.add_argument("--ipa", required=True, type=Path)
    parser.add_argument("--bundle-id", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build-number", required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        result = verify(
            args.ipa,
            bundle_id=args.bundle_id,
            version=args.version,
            build_number=args.build_number,
        )
    except VerificationError as error:
        print(f"IPA verification failed: {error}", file=sys.stderr)
        return 1

    print(json.dumps(result, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

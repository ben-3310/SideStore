#!/usr/bin/env python3
"""Собирает и запускает Debug SideStore на подключённом физическом iPhone."""

from __future__ import annotations

import re
import argparse
import json
import shutil
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Sequence


ROOT = Path(__file__).resolve().parents[2]


@dataclass(frozen=True)
class Device:
    identifier: str
    name: str
    model: str
    os_version: str
    developer_mode: str
    pairing_state: str
    transport: str


class DeviceSelectionError(RuntimeError):
    """Raised when the connected-device preflight is not unambiguous."""


_UUID_RE = re.compile(
    r"(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b"
)
_IOS_UDID_RE = re.compile(r"(?i)\b[0-9a-f]{8}-[0-9a-f]{16}\b")
_CERTIFICATE_SHA_RE = re.compile(r"(?i)\b[0-9a-f]{40}\b")
_TEAM_ID_RE = re.compile(r"\b(?=[A-Z0-9]{10}\b)(?=[A-Z0-9]*[A-Z])[A-Z0-9]{10}\b")
_SIGNING_DETAIL_RE = re.compile(
    r"(?im)^(\s*(?:Signing Identity|Provisioning Profile):\s*).*$"
)


def _nested(record: dict[str, Any], *path: str) -> Any:
    value: Any = record
    for key in path:
        if not isinstance(value, dict):
            return None
        value = value.get(key)
    return value


def select_device(payload: dict[str, Any]) -> Device:
    records = _nested(payload, "result", "devices")
    if not isinstance(records, list):
        raise DeviceSelectionError("devicectl returned no device inventory")

    eligible: list[Device] = []
    for record in records:
        if not isinstance(record, dict):
            continue
        identifier = record.get("identifier")
        name = _nested(record, "deviceProperties", "name")
        model = _nested(record, "hardwareProperties", "marketingName")
        platform = _nested(record, "hardwareProperties", "platform")
        os_version = _nested(record, "deviceProperties", "osVersionNumber")
        developer_mode = _nested(record, "deviceProperties", "developerModeStatus")
        pairing_state = _nested(record, "connectionProperties", "pairingState")
        transport = _nested(record, "connectionProperties", "transportType")
        if not all(isinstance(value, str) for value in (identifier, name, model, os_version, developer_mode, pairing_state, transport)):
            continue
        if (
            platform == "iOS"
            and model == "iPhone 13"
            and os_version == "27.0"
            and developer_mode == "enabled"
            and pairing_state == "paired"
            and transport == "wired"
        ):
            eligible.append(Device(identifier, name, model, os_version, developer_mode, pairing_state, transport))

    if len(eligible) != 1:
        raise DeviceSelectionError(f"expected exactly one eligible iPhone 13, found {len(eligible)}")
    return eligible[0]


def redact_output(text: str, device_identifier: str) -> str:
    if device_identifier:
        text = text.replace(device_identifier, "<redacted-device>")
    text = _UUID_RE.sub("<redacted-device>", text)
    text = _IOS_UDID_RE.sub("<redacted-device>", text)
    text = _CERTIFICATE_SHA_RE.sub("<redacted-certificate>", text)
    text = _TEAM_ID_RE.sub("<redacted-team>", text)
    return _SIGNING_DETAIL_RE.sub(r"\1<redacted-signing-detail>", text)


def _destination(device_identifier: str) -> str:
    return f"platform=iOS,id={device_identifier}"


def build_build_for_testing_command(
    device_identifier: str,
    derived_data: Path,
    allow_provisioning_updates: bool = False,
    development_team: str | None = None,
) -> list[str]:
    command = [
        "xcodebuild",
        "build-for-testing",
        "-project",
        "AltStore.xcodeproj",
        "-scheme",
        "SideStore",
        "-configuration",
        "Debug",
        "-sdk",
        "iphoneos",
        "-destination",
        _destination(device_identifier),
        "-derivedDataPath",
        str(derived_data),
    ]
    if development_team:
        command.append(f"DEVELOPMENT_TEAM={development_team}")
    if allow_provisioning_updates:
        command.append("-allowProvisioningUpdates")
    return command


def build_test_without_building_command(
    device_identifier: str,
    derived_data: Path,
    result_bundle: Path,
    allow_provisioning_updates: bool = False,
    development_team: str | None = None,
) -> list[str]:
    command = [
        "xcodebuild",
        "test-without-building",
        "-project",
        "AltStore.xcodeproj",
        "-scheme",
        "SideStore",
        "-configuration",
        "Debug",
        "-sdk",
        "iphoneos",
        "-destination",
        _destination(device_identifier),
        "-derivedDataPath",
        str(derived_data),
        "-resultBundlePath",
        str(result_bundle),
        "-only-testing:UITests/UITestsLaunchTests/testLaunch",
    ]
    if development_team:
        command.append(f"DEVELOPMENT_TEAM={development_team}")
    if allow_provisioning_updates:
        command.append("-allowProvisioningUpdates")
    return command


def build_install_command(device_identifier: str, app_path: Path) -> list[str]:
    return [
        "xcrun",
        "devicectl",
        "device",
        "install",
        "app",
        "--device",
        device_identifier,
        str(app_path),
    ]


def build_launch_command(device_identifier: str, bundle_identifier: str) -> list[str]:
    return [
        "xcrun",
        "devicectl",
        "device",
        "process",
        "launch",
        "--device",
        device_identifier,
        "--terminate-existing",
        bundle_identifier,
    ]


def build_codesign_verify_command(app_path: Path) -> list[str]:
    return ["codesign", "--verify", "--deep", "--strict", str(app_path)]


def build_xcresult_summary_command(result_bundle: Path) -> list[str]:
    return [
        "xcrun",
        "xcresulttool",
        "get",
        "test-results",
        "summary",
        "--path",
        str(result_bundle),
        "--compact",
    ]


def build_process_info_command(device_identifier: str, output_path: Path) -> list[str]:
    return [
        "xcrun",
        "devicectl",
        "device",
        "info",
        "processes",
        "--device",
        device_identifier,
        "--json-output",
        str(output_path),
    ]


def parse_test_summary(summary: dict[str, Any]) -> None:
    expected = {
        "totalTestCount": 1,
        "passedTests": 1,
        "failedTests": 0,
        "skippedTests": 0,
        "result": "Passed",
    }
    if any(summary.get(key) != value for key, value in expected.items()):
        raise RuntimeError(
            "XCTest launch smoke did not produce exactly one passing, non-skipped test"
        )


def reset_build_outputs(derived_data: Path, result_bundle: Path) -> None:
    """Удаляет только локальные артефакты этого device-flow перед чистой подписью."""
    shutil.rmtree(derived_data, ignore_errors=True)
    shutil.rmtree(result_bundle, ignore_errors=True)


def run_checked(
    args: Sequence[str],
    *,
    cwd: Path = ROOT,
    redact_id: str | None = None,
    stream_output: bool = True,
) -> str:
    """Run one external tool and stream only redacted output."""
    process = subprocess.Popen(
        list(args),
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )
    output: list[str] = []
    assert process.stdout is not None
    for line in process.stdout:
        safe_line = redact_output(line, redact_id or "")
        output.append(line)
        if stream_output:
            print(safe_line, end="", file=sys.stderr, flush=True)
    process.stdout.close()
    return_code = process.wait()
    if return_code != 0:
        raise RuntimeError(f"{args[0]} failed with exit code {return_code}")
    return "".join(output)


def list_devices_json(*, cwd: Path = ROOT) -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="sidestore-device-") as temp_dir:
        output_path = Path(temp_dir) / "devices.json"
        run_checked(
            ["xcrun", "devicectl", "list", "devices", "--json-output", str(output_path)],
            cwd=cwd,
        )
        return json.loads(output_path.read_text(encoding="utf-8"))


def resolve_debug_bundle_id(repo_root: Path, development_team: str | None = None) -> str:
    command = [
        "xcodebuild",
        "-showBuildSettings",
        "-project",
        "AltStore.xcodeproj",
        "-scheme",
        "SideStore",
        "-configuration",
        "Debug",
    ]
    if development_team:
        command.append(f"DEVELOPMENT_TEAM={development_team}")
    output = run_checked(command, cwd=repo_root, stream_output=False)
    for line in output.splitlines():
        key, separator, value = line.partition("=")
        if separator and key.strip() == "PRODUCT_BUNDLE_IDENTIFIER":
            return value.strip()
    raise RuntimeError("xcodebuild did not report PRODUCT_BUNDLE_IDENTIFIER")


def contains_running_app(
    value: Any,
    bundle_identifier: str,
    executable_name: str,
) -> bool:
    if isinstance(value, dict):
        return any(
            contains_running_app(child, bundle_identifier, executable_name)
            for child in value.values()
        )
    if isinstance(value, list):
        return any(
            contains_running_app(child, bundle_identifier, executable_name)
            for child in value
        )
    if value == bundle_identifier:
        return True
    return isinstance(value, str) and value.endswith(
        f"/{executable_name}.app/{executable_name}"
    )


def _process_is_running(device_identifier: str, bundle_identifier: str, *, cwd: Path) -> bool:
    with tempfile.TemporaryDirectory(prefix="sidestore-process-") as temp_dir:
        output_path = Path(temp_dir) / "processes.json"
        run_checked(
            build_process_info_command(device_identifier, output_path),
            cwd=cwd,
            redact_id=device_identifier,
            stream_output=False,
        )
        return contains_running_app(
            json.loads(output_path.read_text(encoding="utf-8")),
            bundle_identifier,
            "SideStore",
        )


def run_device_flow(
    repo_root: Path,
    allow_provisioning_updates: bool = False,
    development_team: str | None = None,
) -> None:
    device = select_device(list_devices_json(cwd=repo_root))
    derived_data = repo_root / "build/device/DerivedData"
    result_bundle = repo_root / "build/device/SideStore-Device.xcresult"
    app_path = derived_data / "Build/Products/Debug-iphoneos/SideStore.app"
    bundle_identifier = resolve_debug_bundle_id(repo_root, development_team)
    derived_data.parent.mkdir(parents=True, exist_ok=True)
    reset_build_outputs(derived_data, result_bundle)

    run_checked(
        build_build_for_testing_command(
            device.identifier,
            derived_data,
            allow_provisioning_updates,
            development_team,
        ),
        cwd=repo_root,
        redact_id=device.identifier,
    )
    if not app_path.is_dir():
        raise RuntimeError("xcodebuild completed without producing SideStore.app")
    run_checked(build_codesign_verify_command(app_path), cwd=repo_root, redact_id=device.identifier)

    run_checked(
        build_test_without_building_command(
            device.identifier,
            derived_data,
            result_bundle,
            allow_provisioning_updates,
            development_team,
        ),
        cwd=repo_root,
        redact_id=device.identifier,
    )
    summary_output = run_checked(
        build_xcresult_summary_command(result_bundle),
        cwd=repo_root,
        redact_id=device.identifier,
    )
    parse_test_summary(json.loads(summary_output))

    run_checked(
        build_install_command(device.identifier, app_path),
        cwd=repo_root,
        redact_id=device.identifier,
    )
    run_checked(
        build_launch_command(device.identifier, bundle_identifier),
        cwd=repo_root,
        redact_id=device.identifier,
    )
    time.sleep(3)
    if not _process_is_running(device.identifier, bundle_identifier, cwd=repo_root):
        raise RuntimeError("SideStore did not remain running after launch")
    print(f"Physical device smoke passed: {device.model} / iOS {device.os_version}")


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--allow-provisioning-updates",
        action="store_true",
        help="allow Xcode to refresh existing provisioning profiles",
    )
    parser.add_argument(
        "--development-team",
        help="override the project team with a locally installed development team",
    )
    parser.add_argument("--repo-root", type=Path, default=ROOT)
    args = parser.parse_args(argv)
    try:
        run_device_flow(
            args.repo_root.resolve(),
            args.allow_provisioning_updates,
            args.development_team,
        )
    except (DeviceSelectionError, RuntimeError, OSError, json.JSONDecodeError) as error:
        print(f"Physical device flow failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

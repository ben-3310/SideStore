from pathlib import Path
from contextlib import redirect_stderr
import io
import json
import sys
import tempfile
import unittest

from scripts.device.run_on_iphone import (
    DeviceSelectionError,
    build_build_for_testing_command,
    build_codesign_verify_command,
    build_install_command,
    build_launch_command,
    build_process_info_command,
    build_test_without_building_command,
    build_xcresult_summary_command,
    contains_running_app,
    parse_test_summary,
    reset_build_outputs,
    redact_output,
    run_checked,
    select_device,
)


def valid_device(identifier):
    return {
        "identifier": identifier,
        "deviceProperties": {
            "name": "13",
            "osVersionNumber": "27.0",
            "developerModeStatus": "enabled",
        },
        "hardwareProperties": {
            "marketingName": "iPhone 13",
            "productType": "iPhone14,5",
            "platform": "iOS",
        },
        "connectionProperties": {
            "pairingState": "paired",
            "transportType": "wired",
        },
    }


def simulator_device():
    record = valid_device("simulator")
    record["hardwareProperties"]["platform"] = "iOS Simulator"
    return record


def wrong_os_device():
    record = valid_device("wrong-os")
    record["deviceProperties"]["osVersionNumber"] = "26.5"
    return record


def unpaired_device():
    record = valid_device("unpaired")
    record["connectionProperties"]["pairingState"] = "unpaired"
    return record


def no_developer_mode_device():
    record = valid_device("developer-mode-off")
    record["deviceProperties"]["developerModeStatus"] = "disabled"
    return record


class DeviceSelectionTests(unittest.TestCase):
    def test_selects_one_paired_developer_mode_iphone_13_on_ios_27(self):
        device = select_device({"result": {"devices": [valid_device("device-1")]}})
        self.assertEqual(device.identifier, "device-1")

    def test_rejects_zero_or_multiple_matching_devices(self):
        with self.assertRaises(DeviceSelectionError):
            select_device({"result": {"devices": []}})
        with self.assertRaises(DeviceSelectionError):
            select_device({"result": {"devices": [valid_device("a"), valid_device("b")]}})

    def test_rejects_simulator_wrong_os_unpaired_or_disabled_developer_mode(self):
        for record in (simulator_device(), wrong_os_device(), unpaired_device(), no_developer_mode_device()):
            with self.subTest(record=record):
                with self.assertRaises(DeviceSelectionError):
                    select_device({"result": {"devices": [record]}})


class CommandTests(unittest.TestCase):
    def test_device_build_and_test_commands_use_exact_destination_and_signing(self):
        build = build_build_for_testing_command("device-1", Path("build/device/DerivedData"))
        test = build_test_without_building_command(
            "device-1",
            Path("build/device/DerivedData"),
            Path("build/device/SideStore-Device.xcresult"),
            development_team="ABC123DE45",
        )
        self.assertNotIn("platform=iOS Simulator", build)
        self.assertIn("platform=iOS,id=device-1", build)
        self.assertNotIn("CODE_SIGNING_ALLOWED=NO", build)
        self.assertIn("DEVELOPMENT_TEAM=ABC123DE45", test)
        self.assertEqual(
            test[test.index("-derivedDataPath") + 1],
            "build/device/DerivedData",
        )
        self.assertIn("-only-testing:UITests/UITestsLaunchTests/testLaunch", test)

    def test_install_and_launch_commands_are_argument_lists(self):
        install = build_install_command(
            "device-1",
            Path("build/device/DerivedData/Build/Products/Debug-iphoneos/SideStore.app"),
        )
        launch = build_launch_command("device-1", "com.SideStore.SideStore.S32Z3HMYVQ")
        self.assertEqual(install[:5], ["xcrun", "devicectl", "device", "install", "app"])
        self.assertEqual(launch[:5], ["xcrun", "devicectl", "device", "process", "launch"])
        self.assertNotIsInstance(install, str)
        self.assertNotIsInstance(launch, str)


class ReportingTests(unittest.TestCase):
    def test_detects_ios_27_process_by_executable_path(self):
        payload = {
            "result": {
                "runningProcesses": [
                    {
                        "executable": "file:///private/var/containers/Bundle/Application/<redacted>/SideStore.app/SideStore",
                        "processIdentifier": 123,
                    }
                ]
            }
        }
        self.assertTrue(
            contains_running_app(payload, "com.example.SideStore", "SideStore")
        )

    def test_redacts_device_identifier_and_uuid_like_values(self):
        output = redact_output("device-1 01234567-89ab-cdef-0123-456789abcdef", "device-1")
        self.assertNotIn("device-1", output)
        self.assertNotIn("01234567-89ab-cdef-0123-456789abcdef", output)

    def test_redacts_signing_team_certificate_and_profile_details(self):
        output = redact_output(
            "DEVELOPMENT_TEAM = ABC123DE45\n"
            "Signing Identity: Apple Development: Local User (ABC123DE45)\n"
            "Provisioning Profile: iOS Team Provisioning Profile: private.bundle\n"
            "--sign 0123456789abcdef0123456789abcdef01234567\n",
            "",
        )
        for secret in (
            "ABC123DE45",
            "Local User",
            "private.bundle",
            "0123456789abcdef0123456789abcdef01234567",
        ):
            self.assertNotIn(secret, output)

    def test_redaction_preserves_numeric_json_and_masks_ios_device_udid(self):
        output = redact_output(
            '{"finishTime":1753176896.595,"deviceId":"00000000-0000000000000000"}',
            "",
        )
        self.assertEqual(json.loads(output)["finishTime"], 1753176896.595)
        self.assertNotIn("00000000-0000000000000000", output)

    def test_accepts_exactly_one_passed_test(self):
        parse_test_summary(
            {
                "totalTestCount": 1,
                "passedTests": 1,
                "failedTests": 0,
                "skippedTests": 0,
                "result": "Passed",
            }
        )

    def test_rejects_failed_skipped_or_wrong_count(self):
        for summary in (
            {"totalTestCount": 0, "failedTests": 0, "skippedTests": 0},
            {"totalTestCount": 1, "failedTests": 1, "skippedTests": 0},
            {"totalTestCount": 1, "failedTests": 0, "skippedTests": 1},
            {
                "totalTestCount": 1,
                "passedTests": 0,
                "failedTests": 0,
                "skippedTests": 0,
                "result": "Passed",
            },
            {
                "totalTestCount": 1,
                "passedTests": 1,
                "failedTests": 0,
                "skippedTests": 0,
                "result": "Failed",
            },
        ):
            with self.subTest(summary=summary):
                with self.assertRaises(RuntimeError):
                    parse_test_summary(summary)


class OrchestrationCommandTests(unittest.TestCase):
    def test_run_checked_can_capture_without_streaming_inventory(self):
        stderr = io.StringIO()
        with redirect_stderr(stderr):
            output = run_checked(
                [sys.executable, "-c", "print('captured')"],
                stream_output=False,
            )
        self.assertEqual(output, "captured\n")
        self.assertEqual(stderr.getvalue(), "")

    def test_reset_build_outputs_removes_stale_signed_products_and_results(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            derived_data = root / "DerivedData"
            result_bundle = root / "SideStore-Device.xcresult"
            (derived_data / "Build/Products").mkdir(parents=True)
            (derived_data / "Build/Products/stale").write_text("stale")
            result_bundle.mkdir()

            reset_build_outputs(derived_data, result_bundle)

            self.assertFalse(derived_data.exists())
            self.assertFalse(result_bundle.exists())

    def test_codesign_and_xcresult_commands_are_argument_lists(self):
        codesign = build_codesign_verify_command(Path("build/device/SideStore.app"))
        summary = build_xcresult_summary_command(Path("build/device/SideStore-Device.xcresult"))
        self.assertEqual(codesign[:4], ["codesign", "--verify", "--deep", "--strict"])
        self.assertEqual(
            summary[:5],
            ["xcrun", "xcresulttool", "get", "test-results", "summary"],
        )
        self.assertIn("--compact", summary)

    def test_process_info_command_uses_exact_device(self):
        command = build_process_info_command("device-1", Path("build/device/processes.json"))
        self.assertEqual(command[:5], ["xcrun", "devicectl", "device", "info", "processes"])
        self.assertIn("device-1", command)
        self.assertNotIn("-allowProvisioningDeviceRegistration", command)

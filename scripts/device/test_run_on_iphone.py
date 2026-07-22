from pathlib import Path
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
    parse_test_summary,
    redact_output,
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
        test = build_test_without_building_command("device-1", Path("build/device/SideStore-Device.xcresult"))
        self.assertNotIn("platform=iOS Simulator", build)
        self.assertIn("platform=iOS,id=device-1", build)
        self.assertNotIn("CODE_SIGNING_ALLOWED=NO", build)
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
    def test_redacts_device_identifier_and_uuid_like_values(self):
        output = redact_output("device-1 01234567-89ab-cdef-0123-456789abcdef", "device-1")
        self.assertNotIn("device-1", output)
        self.assertNotIn("01234567-89ab-cdef-0123-456789abcdef", output)

    def test_accepts_exactly_one_passed_test(self):
        parse_test_summary({"totalTestCount": 1, "failedTests": 0, "skippedTests": 0})

    def test_rejects_failed_skipped_or_wrong_count(self):
        for summary in (
            {"totalTestCount": 0, "failedTests": 0, "skippedTests": 0},
            {"totalTestCount": 1, "failedTests": 1, "skippedTests": 0},
            {"totalTestCount": 1, "failedTests": 0, "skippedTests": 1},
        ):
            with self.subTest(summary=summary):
                with self.assertRaises(RuntimeError):
                    parse_test_summary(summary)


class OrchestrationCommandTests(unittest.TestCase):
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

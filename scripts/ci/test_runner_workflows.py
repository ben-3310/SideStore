import unittest
from pathlib import Path
import re


REPO_ROOT = Path(__file__).resolve().parents[2]


def runs_on_value(workflow_name: str) -> str:
    workflow = REPO_ROOT / ".github" / "workflows" / workflow_name
    values = [
        line.split("runs-on:", 1)[1].strip()
        for line in workflow.read_text().splitlines()
        if line.strip().startswith("runs-on:")
    ]
    if len(values) != 1:
        raise AssertionError(f"expected one runs-on value in {workflow_name}: {values}")
    return values[0]


def workflow_text(workflow_name: str) -> str:
    workflow = REPO_ROOT / ".github" / "workflows" / workflow_name
    return workflow.read_text()


class RunnerWorkflowTests(unittest.TestCase):
    def test_trusted_release_workflows_use_sidestore_runner(self) -> None:
        expected = "[self-hosted, macOS, ARM64, sidestore, xcode-26-6]"

        self.assertEqual(runs_on_value("nightly.yml"), expected)
        self.assertEqual(runs_on_value("stable.yml"), expected)

    def test_untrusted_workflows_stay_on_github_hosted_runners(self) -> None:
        self.assertEqual(runs_on_value("pr.yml"), "macos-26")
        self.assertEqual(runs_on_value("alpha.yml"), "macos-26")

    def test_ios27_compatibility_workflow_is_trusted_and_pinned(self) -> None:
        text = workflow_text("ios27-compatibility.yml")

        self.assertEqual(
            runs_on_value("ios27-compatibility.yml"),
            "[self-hosted, macOS, ARM64, sidestore, xcode-27-0, ios-27]",
        )
        self.assertNotIn("pull_request:", text)
        self.assertIn("permissions:\n  contents: read", text)
        self.assertIn('SIMULATOR_OS: "27.0"', text)
        self.assertIn('SIMULATOR_MODEL: "iPhone 13"', text)
        self.assertIn(
            'SIMULATOR_DEVICE: "SideStore-CI-${{ github.run_id }}-${{ github.run_attempt }}"',
            text,
        )
        self.assertIn("xcodebuild -version | grep -Fx 'Xcode 27.0'", text)
        self.assertIn('grep -F "iOS 27.0 (27.0', text)
        self.assertIn(
            'device_type = "com.apple.CoreSimulator.SimDeviceType.iPhone-13"',
            text,
        )
        self.assertIn("python3 scripts/ci/workflow.py build", text)
        self.assertIn("python3 scripts/ci/workflow.py tests-build", text)
        self.assertIn(
            'python3 scripts/ci/workflow.py tests-run "$SIMULATOR_DEVICE"',
            text,
        )
        self.assertIn(
            'runtime_id = "com.apple.CoreSimulator.SimRuntime.iOS-27-0"',
            text,
        )
        self.assertIn(
            'echo "IOS27_SIMULATOR_UDID=$udid" >> "$GITHUB_ENV"',
            text,
        )
        self.assertIn(
            'echo "SIMULATOR_DESTINATION=platform=iOS Simulator,id=$udid" >> "$GITHUB_ENV"',
            text,
        )
        self.assertIn("xcrun simctl boot \"$IOS27_SIMULATOR_UDID\"", text)
        self.assertIn("xcrun simctl bootstatus \"$IOS27_SIMULATOR_UDID\" -b", text)
        self.assertIn("path: build/tests/test-results.xcresult", text)
        self.assertIn("if: always()", text)
        self.assertIn("xcrun simctl shutdown \"$IOS27_SIMULATOR_UDID\"", text)
        self.assertIn("xcrun simctl delete \"$IOS27_SIMULATOR_UDID\"", text)
        self.assertIn(
            "actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1",
            text,
        )
        self.assertIn(
            "actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02 # v4.6.2",
            text,
        )
        for action in re.findall(r"uses:\s+([^\s#]+)", text):
            with self.subTest(action=action):
                self.assertRegex(action, r"^[^@]+@[0-9a-f]{40}$")
        self.assertNotIn("upload-release", text)
        self.assertNotIn("CROSS_REPO_PUSH_KEY", text)

    def test_trusted_release_workflows_select_installed_xcode(self) -> None:
        hosted_setup = (
            "- name: Setup Xcode (GitHub-hosted)",
            "uses: maxim-lobanov/setup-xcode@v1.6.0",
            'xcode-version: "26.6"',
        )
        self_hosted_preflight = (
            "- name: Verify Xcode (self-hosted)",
            "xcodebuild -version | grep -Fx 'Xcode 26.6'",
        )

        for workflow_name in ("nightly.yml", "stable.yml"):
            text = workflow_text(workflow_name)
            xcode_steps = text[
                text.index("- name: Setup Xcode (GitHub-hosted)"):
                text.index("- name: Restore Cache (exact)")
            ]
            with self.subTest(workflow=workflow_name):
                for fragment in hosted_setup + self_hosted_preflight:
                    self.assertIn(fragment, xcode_steps)
                self.assertIn("runner.environment == 'github-hosted'", xcode_steps)
                self.assertIn("runner.environment == 'self-hosted'", xcode_steps)

    def test_trusted_release_workflows_do_not_mutate_shared_homebrew(self) -> None:
        required_fragments = (
            "- name: Install build dependencies",
            "runner.environment == 'github-hosted'",
            "run: brew install ldid xcbeautify wget",
            "- name: Verify build dependencies",
            "runner.environment == 'self-hosted'",
            "command -v ldid",
            "command -v xcbeautify",
            "command -v wget",
        )

        for workflow_name in ("nightly.yml", "stable.yml"):
            text = workflow_text(workflow_name)
            with self.subTest(workflow=workflow_name):
                for fragment in required_fragments:
                    self.assertIn(fragment, text)

    def test_simulator_destination_can_be_pinned_by_runner(self) -> None:
        makefile = (REPO_ROOT / "Makefile").read_text()

        self.assertIn("SIMULATOR_DEVICE ?= iPhone 17 Pro", makefile)
        self.assertIn("SIMULATOR_OS ?= latest", makefile)
        self.assertIn(
            "SIMULATOR_DESTINATION ?= platform=iOS Simulator,name=$(SIMULATOR_DEVICE),OS=$(SIMULATOR_OS)",
            makefile,
        )
        self.assertNotIn("OS=26.0", makefile)
        self.assertNotIn("OS=latest", makefile)
        self.assertEqual(makefile.count("-destination '$(SIMULATOR_DESTINATION)'"), 3)


if __name__ == "__main__":
    unittest.main()

import importlib.util
import json
import subprocess
import unittest
from pathlib import Path
from unittest.mock import patch


REPO_ROOT = Path(__file__).resolve().parents[2]
WORKFLOW_PATH = REPO_ROOT / "scripts" / "ci" / "workflow.py"


def load_workflow_module():
    spec = importlib.util.spec_from_file_location("sidestore_ci_workflow", WORKFLOW_PATH)
    if spec is None or spec.loader is None:
        raise AssertionError(f"unable to load {WORKFLOW_PATH}")

    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class WorkflowPipelineTests(unittest.TestCase):
    def setUp(self) -> None:
        self.workflow = load_workflow_module()

    def test_build_verifies_dependencies_before_make(self) -> None:
        with (
            patch.object(self.workflow, "verify_dependencies") as verify,
            patch.object(self.workflow, "run"),
        ):
            self.workflow.build()

        self.assertEqual(verify.call_args.args, (self.workflow.ROOT,))

    def test_tests_build_verifies_dependencies_before_make(self) -> None:
        with (
            patch.object(self.workflow, "verify_dependencies") as verify,
            patch.object(self.workflow, "run"),
        ):
            self.workflow.tests_build()

        self.assertEqual(verify.call_args.args, (self.workflow.ROOT,))

    def test_tests_build_propagates_pipeline_failures(self) -> None:
        with patch.object(self.workflow, "run") as run:
            self.workflow.tests_build()

        build_command = next(
            call.args[0]
            for call in run.call_args_list
            if "make -B build-tests" in call.args[0]
        )
        self.assertTrue(build_command.startswith("set -o pipefail && "))

    def test_archive_packaging_propagates_pipeline_failures(self) -> None:
        with patch.object(self.workflow, "run") as run:
            self.workflow.build()

        packaging_commands = [
            call.args[0]
            for call in run.call_args_list
            if "make fakesign" in call.args[0] or "make ipa" in call.args[0]
        ]
        self.assertEqual(len(packaging_commands), 2)
        for command in packaging_commands:
            with self.subTest(command=command):
                self.assertTrue(command.startswith("set -o pipefail && "))

    def test_pipefail_rejects_failure_before_tee(self) -> None:
        with self.assertRaises(subprocess.CalledProcessError):
            self.workflow.run("set -o pipefail && false | true")

    def test_tests_run_propagates_pipeline_failures(self) -> None:
        with (
            patch.object(self.workflow, "is_sim_booted", return_value=True),
            patch.object(self.workflow, "run") as run,
        ):
            self.workflow.tests_run("SideStore-CI-test")

        test_command = next(
            call.args[0]
            for call in run.call_args_list
            if "make run-tests" in call.args[0]
        )
        self.assertTrue(test_command.startswith("set -o pipefail && "))

    def test_simulator_boot_check_matches_exact_udid(self) -> None:
        simulator_udid = "3CF1D2BE-6147-4A62-88DB-1D6997B38884"
        completed = subprocess.CompletedProcess(
            args=[],
            returncode=0,
            stdout=json.dumps(
                {
                    "devices": {
                        "com.apple.CoreSimulator.SimRuntime.iOS-27-0": [
                            {
                                "name": "SideStore-CI-test",
                                "udid": simulator_udid,
                                "state": "Booted",
                                "isAvailable": True,
                            }
                        ]
                    }
                }
            ),
        )

        with patch.object(self.workflow.subprocess, "run", return_value=completed):
            self.assertTrue(self.workflow.is_sim_booted(simulator_udid))
            self.assertTrue(self.workflow.is_sim_booted("SideStore-CI-test"))

    def test_simulator_boot_check_rejects_other_udid(self) -> None:
        completed = subprocess.CompletedProcess(
            args=[],
            returncode=0,
            stdout=json.dumps(
                {
                    "devices": {
                        "com.apple.CoreSimulator.SimRuntime.iOS-27-0": [
                            {
                                "name": "SideStore-CI-test",
                                "udid": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
                                "state": "Booted",
                                "isAvailable": True,
                            }
                        ]
                    }
                }
            ),
        )

        with patch.object(self.workflow.subprocess, "run", return_value=completed):
            self.assertFalse(
                self.workflow.is_sim_booted(
                    "3CF1D2BE-6147-4A62-88DB-1D6997B38884"
                )
            )


if __name__ == "__main__":
    unittest.main()

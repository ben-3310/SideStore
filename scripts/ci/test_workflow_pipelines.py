import importlib.util
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

    def test_tests_build_propagates_pipeline_failures(self) -> None:
        with patch.object(self.workflow, "run") as run:
            self.workflow.tests_build()

        build_command = next(
            call.args[0]
            for call in run.call_args_list
            if "make -B build-tests" in call.args[0]
        )
        self.assertTrue(build_command.startswith("set -o pipefail && "))

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


if __name__ == "__main__":
    unittest.main()

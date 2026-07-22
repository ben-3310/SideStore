import unittest
from pathlib import Path


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

    def test_trusted_release_workflows_select_installed_xcode(self) -> None:
        for workflow_name in ("nightly.yml", "stable.yml"):
            with self.subTest(workflow=workflow_name):
                self.assertIn('xcode-version: "26.6"', workflow_text(workflow_name))

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

    def test_simulator_destination_uses_installed_runtime(self) -> None:
        makefile = (REPO_ROOT / "Makefile").read_text()

        self.assertNotIn("OS=26.0", makefile)
        self.assertEqual(makefile.count("OS=latest"), 3)


if __name__ == "__main__":
    unittest.main()

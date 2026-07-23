import json
import os
import plistlib
import subprocess
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
WORKFLOW_PATH = REPO_ROOT / ".asc" / "workflow.json"
EXPORT_OPTIONS_PATH = REPO_ROOT / ".asc" / "ExportOptions.plist"


class ASCWorkflowTests(unittest.TestCase):
    def load_workflow(self) -> dict[str, object]:
        return json.loads(WORKFLOW_PATH.read_text(encoding="utf-8"))

    def test_internal_testflight_contract(self) -> None:
        document = self.load_workflow()
        self.assertEqual(document["env"]["APP_ID"], "6793432450")
        self.assertEqual(
            document["env"]["BUNDLE_ID"],
            "com.SideStore.benStore.972MD5K36E",
        )
        self.assertEqual(document["env"]["TESTFLIGHT_GROUP"], "Internal Testers")
        self.assertEqual(document["env"]["ASC_PROFILE"], "asc Developer 2")
        self.assertEqual(document["env"]["ASC_STRICT_AUTH"], "true")

        workflow = document["workflows"]["testflight_internal"]
        steps = {step["name"]: step["run"] for step in workflow["steps"]}
        self.assertEqual(
            list(steps),
            [
                "validate_version",
                "resolve_next_build",
                "archive",
                "export",
                "verify_ipa",
                "publish",
            ],
        )
        self.assertIn("MARKETING_VERSION=$VERSION", steps["archive"])
        self.assertIn("CURRENT_PROJECT_VERSION=${steps.resolve_next_build.BUILD_NUMBER}", steps["archive"])
        self.assertIn("scripts/ci/verify_ipa_metadata.py", steps["verify_ipa"])
        self.assertIn("asc publish testflight", steps["publish"])
        self.assertIn("--group \"$TESTFLIGHT_GROUP\"", steps["publish"])
        self.assertIn("--wait", steps["publish"])

        serialized = json.dumps(document)
        self.assertNotIn("--submit", serialized)
        self.assertNotIn("--confirm", serialized)

    def test_version_validation_rejects_unsafe_input_and_quotes_archive_flag(self) -> None:
        workflow = self.load_workflow()["workflows"]["testflight_internal"]
        steps = {step["name"]: step["run"] for step in workflow["steps"]}

        for version in ("1.0", "1.0.0"):
            result = subprocess.run(
                ["/bin/sh", "-c", steps["validate_version"]],
                capture_output=True,
                env={**os.environ, "VERSION": version},
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)

        unsafe_result = subprocess.run(
            ["/bin/sh", "-c", steps["validate_version"]],
            capture_output=True,
            env={**os.environ, "VERSION": "1.0 unsafe"},
            text=True,
        )
        self.assertNotEqual(unsafe_result.returncode, 0)

        self.assertIn(
            '--xcodebuild-flag="MARKETING_VERSION=$VERSION"',
            steps["archive"],
        )
        self.assertNotIn(
            "--xcodebuild-flag=MARKETING_VERSION=$VERSION",
            steps["archive"],
        )

    def test_export_options_use_automatic_app_store_connect_signing(self) -> None:
        with EXPORT_OPTIONS_PATH.open("rb") as file:
            options = plistlib.load(file)
        self.assertEqual(options["method"], "app-store-connect")
        self.assertEqual(options["destination"], "export")
        self.assertEqual(options["signingStyle"], "automatic")
        self.assertEqual(options["teamID"], "972MD5K36E")

    def test_local_state_is_ignored_but_project_files_are_trackable(self) -> None:
        gitignore = (REPO_ROOT / ".gitignore").read_text(encoding="utf-8")
        self.assertIn(".asc/config.json", gitignore)
        self.assertIn(".asc/artifacts/", gitignore)
        self.assertIn(".asc/runs/", gitignore)
        self.assertIn("!ASC.md", gitignore)


if __name__ == "__main__":
    unittest.main()

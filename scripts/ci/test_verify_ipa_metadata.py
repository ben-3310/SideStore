import json
import plistlib
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "ci" / "verify_ipa_metadata.py"


class VerifyIPAMetadataTests(unittest.TestCase):
    def make_ipa(
        self,
        directory: Path,
        *,
        bundle_id: str = "com.SideStore.benStore.972MD5K36E",
        version: str = "1.0",
        build_number: str = "1",
    ) -> Path:
        ipa = directory / "SideStore.ipa"
        info = {
            "CFBundleIdentifier": bundle_id,
            "CFBundleShortVersionString": version,
            "CFBundleVersion": build_number,
        }
        with zipfile.ZipFile(ipa, "w") as archive:
            archive.writestr(
                "Payload/benStore.app/Info.plist",
                plistlib.dumps(info),
            )
        return ipa

    def run_verifier(self, ipa: Path, **overrides: str) -> subprocess.CompletedProcess[str]:
        command = [
            sys.executable,
            str(SCRIPT),
            "--ipa",
            str(ipa),
            "--bundle-id",
            overrides.get("bundle_id", "com.SideStore.benStore.972MD5K36E"),
            "--version",
            overrides.get("version", "1.0"),
            "--build-number",
            overrides.get("build_number", "1"),
        ]
        return subprocess.run(command, text=True, capture_output=True, check=False)

    def test_accepts_matching_ipa(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            ipa = self.make_ipa(Path(temporary_directory))
            result = self.run_verifier(ipa)

        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["bundle_id"], "com.SideStore.benStore.972MD5K36E")
        self.assertEqual(payload["version"], "1.0")
        self.assertEqual(payload["build_number"], "1")

    def test_rejects_bundle_id_mismatch(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            ipa = self.make_ipa(Path(temporary_directory), bundle_id="com.example.wrong")
            result = self.run_verifier(ipa)

        self.assertEqual(result.returncode, 1)
        self.assertIn("CFBundleIdentifier", result.stderr)
        self.assertIn("com.example.wrong", result.stderr)

    def test_rejects_missing_application_info_plist(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            ipa = Path(temporary_directory) / "Empty.ipa"
            with zipfile.ZipFile(ipa, "w") as archive:
                archive.writestr("README.txt", "not an app")
            result = self.run_verifier(ipa)

        self.assertEqual(result.returncode, 1)
        self.assertIn("Payload/*.app/Info.plist", result.stderr)


if __name__ == "__main__":
    unittest.main()

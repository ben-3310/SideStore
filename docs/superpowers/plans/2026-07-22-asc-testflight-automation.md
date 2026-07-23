# SideStore asc TestFlight Automation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Налаштувати безпечний і повторюваний локальний workflow `Xcode → archive → IPA → TestFlight Internal Testers` через `asc` для SideStore.

**Architecture:** Version-controlled `.asc/workflow.json` оркеструє build number resolution, archive, export, локальну перевірку IPA та TestFlight upload. Окремий Python-скрипт перевіряє метадані IPA без зовнішніх залежностей; credentials зберігаються в macOS Keychain, а repo-local config містить лише несекретні defaults.

**Tech Stack:** asc 3.1.1, Xcode/xcodebuild, JSON workflow, plist, Python 3 standard library, unittest, macOS Keychain.

## Global Constraints

- App Store Connect app ID: `6793432450`.
- Bundle ID: `com.SideStore.benStore.972MD5K36E`.
- Xcode project: `AltStore.xcodeproj`.
- Release scheme: `SideStore - Release`.
- Auth profile: `asc Developer 2`.
- TestFlight group: internal group `Internal Testers`.
- Workflow must never use `--submit --confirm` or create an App Store Review submission.
- Preserve every unrelated staged, modified, and untracked user file.
- Do not modify or traverse the protected `Dependencies` symlink.
- Do not commit `.asc/config.json`, private-key paths, issuer IDs, key IDs, or private-key material.
- Commit only task-owned paths with `git commit --only` because the index already contains unrelated staged files.

---

### Task 1: IPA metadata verifier

**Files:**
- Create: `scripts/ci/verify_ipa_metadata.py`
- Create: `scripts/ci/test_verify_ipa_metadata.py`

**Interfaces:**
- Consumes: IPA path, expected bundle ID, expected marketing version, expected build number.
- Produces: JSON object `{"bundle_id": str, "version": str, "build_number": str, "ipa": str}` on stdout; exit code `1` with a precise stderr message on mismatch.

- [ ] **Step 1: Write the failing verifier tests**

Create `scripts/ci/test_verify_ipa_metadata.py` with:

```python
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
```

- [ ] **Step 2: Run the tests and verify the intended failure**

Run:

```bash
rtk python3 scripts/ci/test_verify_ipa_metadata.py
```

Expected: `FAILED` because `scripts/ci/verify_ipa_metadata.py` does not exist.

- [ ] **Step 3: Implement the verifier**

Create `scripts/ci/verify_ipa_metadata.py` with:

```python
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
```

- [ ] **Step 4: Run the verifier tests**

Run:

```bash
rtk python3 scripts/ci/test_verify_ipa_metadata.py
```

Expected: `Ran 3 tests` and `OK`.

- [ ] **Step 5: Commit only the verifier paths**

```bash
rtk git add scripts/ci/verify_ipa_metadata.py scripts/ci/test_verify_ipa_metadata.py
rtk git commit --only -m "test: verify TestFlight IPA metadata" -- scripts/ci/verify_ipa_metadata.py scripts/ci/test_verify_ipa_metadata.py
```

Expected: one commit containing exactly two files; unrelated staged files remain staged.

---

### Task 2: Version-controlled asc workflow

**Files:**
- Create: `.asc/workflow.json`
- Track: `.asc/ExportOptions.plist`
- Track/update: `ASC.md`
- Modify: `.gitignore`
- Create: `scripts/ci/test_asc_workflow.py`

**Interfaces:**
- Consumes: runtime workflow parameter `VERSION`; App Store Connect app `6793432450`; Xcode project and scheme from global constraints.
- Produces: `.asc/artifacts/SideStore-$VERSION-$BUILD_NUMBER.xcarchive`, matching `.ipa`, and a processed TestFlight build assigned to `Internal Testers`.
- Consumes from Task 1: `scripts/ci/verify_ipa_metadata.py --ipa PATH --bundle-id ID --version VERSION --build-number NUMBER`.

- [ ] **Step 1: Write the failing workflow contract tests**

Create `scripts/ci/test_asc_workflow.py` with:

```python
import json
import plistlib
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
```

- [ ] **Step 2: Run the workflow tests and verify they fail**

Run:

```bash
rtk python3 scripts/ci/test_asc_workflow.py
```

Expected: `FAILED` because `.asc/workflow.json` and required ignore rules do not exist yet.

- [ ] **Step 3: Create `.asc/workflow.json`**

Use this exact JSON:

```json
{
  "env": {
    "APP_ID": "6793432450",
    "BUNDLE_ID": "com.SideStore.benStore.972MD5K36E",
    "PROJECT_PATH": "AltStore.xcodeproj",
    "SCHEME": "SideStore - Release",
    "CONFIGURATION": "Release",
    "TESTFLIGHT_GROUP": "Internal Testers",
    "ASC_PROFILE": "asc Developer 2",
    "ASC_STRICT_AUTH": "true",
    "VERSION": ""
  },
  "before_all": "asc auth status --validate --output json >/dev/null && asc apps view --id \"$APP_ID\" --output json >/dev/null",
  "workflows": {
    "testflight_internal": {
      "description": "Archive benStore, export an IPA, and distribute it to the internal TestFlight group.",
      "steps": [
        {
          "name": "validate_version",
          "run": "test -n \"$VERSION\" || { echo \"VERSION is required\" >&2; exit 2; }"
        },
        {
          "name": "resolve_next_build",
          "run": "asc builds next-build-number --app \"$APP_ID\" --version \"$VERSION\" --platform IOS --initial-build-number 1 --output json",
          "outputs": {
            "BUILD_NUMBER": "$.nextBuildNumber"
          }
        },
        {
          "name": "archive",
          "run": "asc xcode archive --project \"$PROJECT_PATH\" --scheme \"$SCHEME\" --configuration \"$CONFIGURATION\" --archive-path \".asc/artifacts/SideStore-$VERSION-${steps.resolve_next_build.BUILD_NUMBER}.xcarchive\" --clean --overwrite --xcodebuild-flag=-destination --xcodebuild-flag=generic/platform=iOS --xcodebuild-flag=-allowProvisioningUpdates --xcodebuild-flag=MARKETING_VERSION=$VERSION --xcodebuild-flag=CURRENT_PROJECT_VERSION=${steps.resolve_next_build.BUILD_NUMBER} --output json"
        },
        {
          "name": "export",
          "run": "asc xcode export --archive-path \".asc/artifacts/SideStore-$VERSION-${steps.resolve_next_build.BUILD_NUMBER}.xcarchive\" --export-options .asc/ExportOptions.plist --ipa-path \".asc/artifacts/SideStore-$VERSION-${steps.resolve_next_build.BUILD_NUMBER}.ipa\" --overwrite --timeout 10m --xcodebuild-flag=-allowProvisioningUpdates --output json"
        },
        {
          "name": "verify_ipa",
          "run": "python3 scripts/ci/verify_ipa_metadata.py --ipa \".asc/artifacts/SideStore-$VERSION-${steps.resolve_next_build.BUILD_NUMBER}.ipa\" --bundle-id \"$BUNDLE_ID\" --version \"$VERSION\" --build-number \"${steps.resolve_next_build.BUILD_NUMBER}\""
        },
        {
          "name": "publish",
          "run": "asc publish testflight --app \"$APP_ID\" --ipa \".asc/artifacts/SideStore-$VERSION-${steps.resolve_next_build.BUILD_NUMBER}.ipa\" --group \"$TESTFLIGHT_GROUP\" --wait --poll-interval 10s --timeout 45m --output json",
          "outputs": {
            "BUILD_ID": "$.buildId",
            "BUILD_NUMBER": "$.buildNumber"
          }
        }
      ]
    }
  }
}
```

- [ ] **Step 4: Update ignore boundaries and regenerate `ASC.md`**

Append these exact rules after the existing asc rules in `.gitignore`:

```gitignore
.asc/artifacts/
.asc/runs/
!ASC.md
```

Regenerate the local reference without touching `AGENTS.md` or `CLAUDE.md`:

```bash
rtk asc init --force --link=false
```

Expected: `ASC.md` is refreshed; `AGENTS.md` and `CLAUDE.md` remain byte-for-byte unchanged by this command.

- [ ] **Step 5: Run static tests and asc schema validation**

Run:

```bash
rtk python3 scripts/ci/test_asc_workflow.py
rtk asc workflow validate --file .asc/workflow.json --pretty
rtk asc workflow list --file .asc/workflow.json --pretty
```

Expected: `Ran 3 tests` and `OK`; workflow validation reports success; list contains `testflight_internal`.

- [ ] **Step 6: Commit only version-controlled workflow files**

```bash
rtk git add .gitignore .asc/workflow.json .asc/ExportOptions.plist ASC.md scripts/ci/test_asc_workflow.py
rtk git commit --only -m "feat: automate internal TestFlight delivery" -- .gitignore .asc/workflow.json .asc/ExportOptions.plist ASC.md scripts/ci/test_asc_workflow.py
```

Expected: one commit with exactly five paths; `.asc/config.json`, `.asc/artifacts`, `.asc/runs`, `fastlane/`, and unrelated user paths remain outside the commit.

---

### Task 3: Secure auth and create the internal group

**Files:**
- Modify locally only: `.asc/config.json` (git-ignored; remove credential fields, retain app defaults)
- External state: macOS Keychain entry `asc Developer 2`
- External state: App Store Connect internal TestFlight group `Internal Testers`

**Interfaces:**
- Produces: a validated Keychain-backed auth profile selected through `ASC_PROFILE=asc Developer 2`.
- Produces: exactly one internal TestFlight group named `Internal Testers` for app `6793432450`.

- [ ] **Step 1: Capture existing credential fields without printing them**

In one private shell session, read `default_key_name`, `key_id`, `issuer_id`, and `private_key_path` from `.asc/config.json` into task-specific shell variables. Do not echo these variables and do not write them to repo files or logs.

```bash
ASC_SETUP_PROFILE_NAME="$(rtk jq -er '.default_key_name' .asc/config.json)"
ASC_SETUP_KEY_ID="$(rtk jq -er '.key_id' .asc/config.json)"
ASC_SETUP_ISSUER_ID="$(rtk jq -er '.issuer_id' .asc/config.json)"
ASC_SETUP_PRIVATE_KEY_PATH="$(rtk jq -er '.private_key_path' .asc/config.json)"
```

Expected: all four commands exit `0`; the values remain only in the current shell process.

- [ ] **Step 2: Store the credential in macOS Keychain**

Run `asc auth login` without `--bypass-keychain` or `--local`, using the captured values:

```bash
rtk asc auth login --name "$ASC_SETUP_PROFILE_NAME" --key-id "$ASC_SETUP_KEY_ID" --issuer-id "$ASC_SETUP_ISSUER_ID" --private-key "$ASC_SETUP_PRIVATE_KEY_PATH" --network
```

Expected: successful network validation and storage in System Keychain.

- [ ] **Step 3: Mechanically sanitize repo-local config**

Rewrite `.asc/config.json` with `jq`, deleting only credential-bearing fields:

```jq
del(.key_id, .issuer_id, .private_key_path, .default_key_name, .keys)
```

Use these exact commands to write through a private temporary directory and atomically replace the config:

```bash
ASC_SETUP_TMP_DIR="$(rtk mktemp -d)"
rtk jq 'del(.key_id, .issuer_id, .private_key_path, .default_key_name, .keys)' .asc/config.json > "$ASC_SETUP_TMP_DIR/config.json"
rtk chmod 600 "$ASC_SETUP_TMP_DIR/config.json"
rtk mv "$ASC_SETUP_TMP_DIR/config.json" .asc/config.json
rtk rmdir "$ASC_SETUP_TMP_DIR"
unset ASC_SETUP_PROFILE_NAME ASC_SETUP_KEY_ID ASC_SETUP_ISSUER_ID ASC_SETUP_PRIVATE_KEY_PATH ASC_SETUP_TMP_DIR
```

Expected: `.asc/config.json` retains `app_id: 6793432450` and tuning defaults, but contains no key ID, issuer ID, private-key path, or named key list.

- [ ] **Step 4: Verify Keychain-backed auth**

Run:

```bash
rtk asc auth status --validate --output json
rtk asc auth doctor --output json
rtk asc account status --app "6793432450" --output json
```

Expected: profile `asc Developer 2` reports `storedIn: keychain` and `validation: works`; auth doctor has no config-backed credential warning; API access is `ok`.

- [ ] **Step 5: Create the internal TestFlight group**

Resolve the exact-match count:

```bash
ASC_SETUP_GROUP_COUNT="$(rtk asc testflight groups list --app "6793432450" --internal --paginate --output json | rtk jq '[.data[]? | select(.attributes.name == "Internal Testers")] | length')"
```

Create the group only when the count is zero, and fail rather than guessing when duplicates exist:

```bash
if [ "$ASC_SETUP_GROUP_COUNT" -eq 0 ]; then
  rtk asc testflight groups create --app "6793432450" --name "Internal Testers" --internal --output json
elif [ "$ASC_SETUP_GROUP_COUNT" -ne 1 ]; then
  echo "expected zero or one Internal Testers group, found $ASC_SETUP_GROUP_COUNT" >&2
  exit 1
fi
unset ASC_SETUP_GROUP_COUNT
```

Expected: exactly one internal group named `Internal Testers`. Do not create testers or external groups.

---

### Task 4: Full pre-upload verification

**Files:**
- Read: `.asc/workflow.json`
- Read: `.asc/ExportOptions.plist`
- Read/write ignored artifacts: `.asc/artifacts/`

**Interfaces:**
- Consumes: Tasks 1–3 outputs.
- Produces: validated workflow plan and a locally built IPA whose identity matches app `6793432450`.

- [ ] **Step 1: Run all local tests**

```bash
rtk python3 scripts/ci/test_verify_ipa_metadata.py
rtk python3 scripts/ci/test_asc_workflow.py
```

Expected: both suites report `OK`.

- [ ] **Step 2: Validate and preview the workflow**

```bash
rtk asc workflow validate --file .asc/workflow.json --pretty
rtk asc workflow run --file .asc/workflow.json --dry-run --pretty testflight_internal VERSION:1.0
```

Expected: validation succeeds; dry-run contains six steps and no App Store or external beta submission command.

- [ ] **Step 3: Run archive, export, and metadata verification without upload**

Resolve the build number into a task-local variable:

```bash
ASC_SETUP_BUILD_NUMBER="$(rtk asc builds next-build-number --app "6793432450" --version "1.0" --platform IOS --initial-build-number 1 --output json | rtk jq -er '.nextBuildNumber')"
```

Run the exact pre-upload commands and stop before `asc publish testflight`:

```bash
rtk asc xcode archive --project "AltStore.xcodeproj" --scheme "SideStore - Release" --configuration "Release" --archive-path ".asc/artifacts/SideStore-1.0-$ASC_SETUP_BUILD_NUMBER.xcarchive" --clean --overwrite --xcodebuild-flag=-destination --xcodebuild-flag=generic/platform=iOS --xcodebuild-flag=-allowProvisioningUpdates --xcodebuild-flag=MARKETING_VERSION=1.0 --xcodebuild-flag=CURRENT_PROJECT_VERSION="$ASC_SETUP_BUILD_NUMBER" --output json
rtk asc xcode export --archive-path ".asc/artifacts/SideStore-1.0-$ASC_SETUP_BUILD_NUMBER.xcarchive" --export-options .asc/ExportOptions.plist --ipa-path ".asc/artifacts/SideStore-1.0-$ASC_SETUP_BUILD_NUMBER.ipa" --overwrite --timeout 10m --xcodebuild-flag=-allowProvisioningUpdates --output json
rtk python3 scripts/ci/verify_ipa_metadata.py --ipa ".asc/artifacts/SideStore-1.0-$ASC_SETUP_BUILD_NUMBER.ipa" --bundle-id "com.SideStore.benStore.972MD5K36E" --version "1.0" --build-number "$ASC_SETUP_BUILD_NUMBER"
```

Expected: `.asc/artifacts/SideStore-1.0-$ASC_SETUP_BUILD_NUMBER.ipa` exists and the verifier prints bundle ID `com.SideStore.benStore.972MD5K36E`, version `1.0`, and the resolved build number.

- [ ] **Step 4: Confirm no remote build was created by preflight**

```bash
rtk asc builds list --app "6793432450" --version "1.0" --paginate --output json
```

Expected before Task 5: no build with the newly resolved build number exists.

Unset the task-local variable:

```bash
unset ASC_SETUP_BUILD_NUMBER
```

---

### Task 5: Upload and verify the internal TestFlight build

**Files:**
- Write ignored run state: `.asc/runs/`
- Write ignored artifacts: `.asc/artifacts/`
- No version-controlled source changes expected.

**Interfaces:**
- Consumes: validated `testflight_internal` workflow and internal group from Tasks 2–4.
- Produces: processed TestFlight build for version `1.0`, assigned to `Internal Testers`, without App Store submission.

- [ ] **Step 1: Execute the real workflow**

```bash
rtk asc workflow run --file .asc/workflow.json --pretty testflight_internal VERSION:1.0
```

Expected: archive and export succeed, the build uploads, processing reaches a valid state, and the publish result includes a build ID and build number.

- [ ] **Step 2: Verify the uploaded build**

```bash
rtk asc builds list --app "6793432450" --version "1.0" --sort=-uploadedDate --limit 1 --output json
```

Expected: latest build has the workflow's build number, `processingState: VALID`, and `expired: false`.

- [ ] **Step 3: Verify group assignment**

Resolve the exact `Internal Testers` group ID:

```bash
ASC_SETUP_GROUP_ID="$(rtk asc testflight groups list --app "6793432450" --internal --paginate --output json | rtk jq -er '[.data[]? | select(.attributes.name == "Internal Testers")] | if length == 1 then .[0].id else error("expected exactly one Internal Testers group") end')"
```

Then run:

```bash
rtk asc testflight groups links view --group-id "$ASC_SETUP_GROUP_ID" --type builds --paginate --output json
unset ASC_SETUP_GROUP_ID
```

Expected: the relationship data contains the uploaded build ID.

- [ ] **Step 4: Verify that no submission was created**

```bash
rtk asc status --app "6793432450" --output json
```

Expected: `submission.inFlight` is `false`; App Store version remains `PREPARE_FOR_SUBMISSION`.

- [ ] **Step 5: Final repository integrity check**

```bash
rtk git status --short --branch
rtk git show --stat --oneline HEAD
```

Expected: task commits contain only the declared files; all pre-existing unrelated staged, modified, and untracked files remain present; `.asc/config.json`, artifacts, and run state are ignored.

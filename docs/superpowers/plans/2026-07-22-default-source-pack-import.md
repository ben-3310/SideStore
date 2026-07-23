# Default Source Pack Import Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Встроить snapshot пользовательского pack из RepoInstaller в app bundle и автоматически добавить его sources при запуске приложения до сборки IPA.

**Architecture:** `AltStore/Resources/DefaultSources.json` становится committed source of truth для IPA. `DefaultSourcePackImporter` живёт в app target, запускается из `AppDelegate` после успешного `DatabaseManager.shared.start`, использует существующий `AppManager.shared.fetchSource`, сохраняет fetched source context и не вызывает UI-only confirmation flow.

**Tech Stack:** Swift, UIKit app target, AltStoreCore/Core Data, `AppManager.fetchSource`, Python `unittest` static/contract tests, existing `rtk` command wrapper.

## Global Constraints

- Все shell-команды должны начинаться с `rtk`; для неподдержанных команд использовать `rtk proxy`.
- `Dependencies` является защищённой symlink-зоной; не трогать её, кроме разрешённых `ls -ld Dependencies` и `readlink Dependencies`, если это действительно нужно.
- Существующий untracked `fastlane/` не добавлять и не менять.
- `.asc/config.json`, `.asc/artifacts/`, `.asc/runs/` и secret-bearing local state не добавлять в commit.
- Источник данных: `/Users/ben/Library/Mobile Documents/iCloud~is~workflow~my~workflows/Documents/RepoInstaller/Settings/pack.json`, который сейчас указывает на `RepoInstaller/Packs/default.json`.
- Bundled resource должен быть committed snapshot, а не runtime-ссылкой на iCloud-файл.
- Bundled resource должен иметь `version == 1`, `name == "Default"` и ровно 81 URL в `repos`; ожидаемая пара с/без завершающего `/` для `pokemmo.com/altstore` даёт 80 уникальных normalized source IDs и не должна импортироваться дважды.
- Importer запускается после успешного `DatabaseManager.shared.start` и не блокирует запуск UI.
- Importer не использует `AppManager.add(_:presentingViewController:)`, потому что этот flow требует ручной confirmation.
- Перед fetch importer вычисляет `Source.sourceID(from:)` и пропускает уже существующие sources.
- Marker последней обработанной версии хранится в `UserDefaults.shared`; после полного прохода marker обновляется даже при ошибках отдельных URL.
- Ошибки отдельных URL логируются через `debugLog`, но не crash’ят приложение и не прерывают весь import.

---

### Task 1: Bundled Default Source Pack Importer

**Files:**
- Create: `AltStore/Resources/DefaultSources.json`
- Create: `AltStore/Managing Apps/DefaultSourcePackImporter.swift`
- Modify: `AltStore/AppDelegate.swift`
- Create: `scripts/ci/test_default_source_pack.py`

**Interfaces:**
- Consumes: `AppManager.shared.fetchSource(sourceURL:managedObjectContext:) async throws -> Source`
- Consumes: `DatabaseManager.shared.persistentContainer.newBackgroundContext()`
- Consumes: `Source.sourceID(from:)` and `Source.fetchRequest()`
- Produces: `DefaultSourcePackImporter.shared.importIfNeeded() async`
- Produces: `UserDefaults.shared` marker key `io.sidestore.defaultSourcePack.processedVersion`
- Produces: bundled resource `DefaultSources.json` available via `Bundle.main.url(forResource: "DefaultSources", withExtension: "json")`

- [ ] **Step 1: Write the failing source-pack contract test**

Create `scripts/ci/test_default_source_pack.py` with:

```python
import json
import re
import unittest
from pathlib import Path
from urllib.parse import urlparse


REPO_ROOT = Path(__file__).resolve().parents[2]
RESOURCE_PATH = REPO_ROOT / "AltStore" / "Resources" / "DefaultSources.json"
IMPORTER_PATH = REPO_ROOT / "AltStore" / "Managing Apps" / "DefaultSourcePackImporter.swift"
APP_DELEGATE_PATH = REPO_ROOT / "AltStore" / "AppDelegate.swift"


def normalized_source_id(raw_url: str) -> str:
    parsed = urlparse(raw_url)
    if not parsed.scheme and not parsed.netloc:
        parsed = urlparse("https://" + raw_url)

    host = parsed.hostname
    if host is None:
        raise AssertionError(f"missing host for {raw_url!r}")

    normalized = host.lower()
    if normalized.startswith("www."):
        normalized = normalized[4:]

    port = parsed.port
    if port is not None and port not in (80, 443):
        normalized += f":{port}"

    path = re.sub(r"/+", "/", parsed.path)
    normalized += path

    if normalized.endswith("/"):
        normalized = normalized[:-1]

    return normalized


class DefaultSourcePackTests(unittest.TestCase):
    def load_resource(self) -> dict[str, object]:
        return json.loads(RESOURCE_PATH.read_text(encoding="utf-8"))

    def test_default_sources_resource_is_committed_snapshot(self) -> None:
        pack = self.load_resource()

        self.assertEqual(pack["version"], 1)
        self.assertEqual(pack["name"], "Default")

        repos = pack["repos"]
        self.assertIsInstance(repos, list)
        self.assertEqual(len(repos), 81)
        self.assertTrue(all(isinstance(url, str) for url in repos))

        schemes = {urlparse(url).scheme for url in repos}
        self.assertTrue(schemes <= {"http", "https"})

        normalized = [normalized_source_id(url) for url in repos]
        self.assertEqual(len(set(normalized)), 80)
        duplicates = {source_id for source_id in normalized if normalized.count(source_id) > 1}
        self.assertEqual(duplicates, {"pokemmo.com/altstore"})
        self.assertEqual(
            [url for url in repos if normalized_source_id(url) == "pokemmo.com/altstore"],
            ["https://pokemmo.com/altstore/", "https://pokemmo.com/altstore"],
        )

        serialized = json.dumps(pack)
        self.assertNotIn("Mobile Documents", serialized)
        self.assertNotIn("RepoInstaller", serialized)

    def test_importer_uses_bundle_snapshot_and_existing_fetch_flow(self) -> None:
        source = IMPORTER_PATH.read_text(encoding="utf-8")

        self.assertIn('Bundle.main.url(forResource: "DefaultSources", withExtension: "json")', source)
        self.assertIn("io.sidestore.defaultSourcePack.processedVersion", source)
        self.assertIn("UserDefaults.shared", source)
        self.assertIn("Source.sourceID(from: sourceURL)", source)
        self.assertIn("Source.fetchRequest()", source)
        self.assertIn("AppManager.shared.fetchSource(sourceURL: sourceURL, managedObjectContext: context)", source)
        self.assertIn("try context.save()", source)
        self.assertIn("AppManager.didAddSourceNotification", source)
        self.assertIn("debugLog", source)

        self.assertNotIn("AppManager.shared.add", source)
        self.assertNotIn("presentingViewController", source)
        self.assertNotIn("Mobile Documents", source)
        self.assertNotIn("RepoInstaller", source)

    def test_app_delegate_runs_import_after_database_start(self) -> None:
        source = APP_DELEGATE_PATH.read_text(encoding="utf-8")

        start_index = source.index("DatabaseManager.shared.start")
        importer_index = source.index("DefaultSourcePackImporter.shared.importIfNeeded()")
        self.assertGreater(importer_index, start_index)
        self.assertIn("Task", source[start_index:importer_index + 120])


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the source-pack test to verify RED**

Run:

```bash
rtk python3 scripts/ci/test_default_source_pack.py
```

Expected: `FAILED` because `AltStore/Resources/DefaultSources.json` and `DefaultSourcePackImporter.swift` do not exist yet.

- [ ] **Step 3: Create the bundled resource from the approved pack**

Read the selected pack path:

```bash
rtk proxy jq -r '.file' '/Users/ben/Library/Mobile Documents/iCloud~is~workflow~my~workflows/Documents/RepoInstaller/Settings/pack.json'
```

Expected: `default.json`.

Inspect the repo list:

```bash
rtk proxy jq '.repos | length' '/Users/ben/Library/Mobile Documents/iCloud~is~workflow~my~workflows/Documents/RepoInstaller/Packs/default.json'
```

Expected: `81`.

Create `AltStore/Resources/DefaultSources.json` with `apply_patch`. The file must contain exactly these top-level fields:

```json
{
  "version": 1,
  "name": "Default",
  "repos": []
}
```

Populate `repos` with the exact 81 strings, preserving order, from:

```bash
rtk proxy jq -r '.repos[]' '/Users/ben/Library/Mobile Documents/iCloud~is~workflow~my~workflows/Documents/RepoInstaller/Packs/default.json'
```

Do not include `creator`, `description`, `note`, iCloud paths, or any generated timestamp.

- [ ] **Step 4: Run the source-pack test to verify resource-only progress**

Run:

```bash
rtk python3 scripts/ci/test_default_source_pack.py
```

Expected: still `FAILED`, but only because `DefaultSourcePackImporter.swift` and the `AppDelegate` hook are missing.

- [ ] **Step 5: Add `DefaultSourcePackImporter.swift`**

Create `AltStore/Managing Apps/DefaultSourcePackImporter.swift` with:

```swift
//
//  DefaultSourcePackImporter.swift
//  AltStore
//

import Foundation
import CoreData
import AltStoreCore

final class DefaultSourcePackImporter
{
    static let shared = DefaultSourcePackImporter()

    private static let processedVersionKey = "io.sidestore.defaultSourcePack.processedVersion"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = UserDefaults.shared)
    {
        self.userDefaults = userDefaults
    }

    func importIfNeeded() async
    {
        do
        {
            let pack = try self.loadPack()
            let processedVersion = self.userDefaults.integer(forKey: Self.processedVersionKey)
            guard processedVersion < pack.version else {
                debugLog("[DefaultSourcePackImporter] Default source pack \(pack.version) already processed.")
                return
            }

            let summary = await self.importSources(from: pack)
            self.userDefaults.set(pack.version, forKey: Self.processedVersionKey)

            debugLog("[DefaultSourcePackImporter] Processed default source pack \(pack.version): added \(summary.added), skipped \(summary.skipped), failed \(summary.failed).")
        }
        catch
        {
            debugLog("[DefaultSourcePackImporter] Failed to load bundled default sources: \(error.localizedDescription)")
        }
    }

    private func loadPack() throws -> DefaultSourcePack
    {
        guard let url = Bundle.main.url(forResource: "DefaultSources", withExtension: "json")
        else { throw URLError(.fileDoesNotExist) }

        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(DefaultSourcePack.self, from: data)
    }

    private func importSources(from pack: DefaultSourcePack) async -> ImportSummary
    {
        var summary = ImportSummary()
        var seenSourceIDs = Set<String>()

        for sourceURL in pack.repos
        {
            do
            {
                let sourceID = try Source.sourceID(from: sourceURL)
                guard seenSourceIDs.insert(sourceID).inserted else {
                    summary.skipped += 1
                    continue
                }

                if try await self.sourceExists(sourceID: sourceID)
                {
                    summary.skipped += 1
                    continue
                }

                try await self.importSource(sourceURL: sourceURL)
                summary.added += 1
            }
            catch
            {
                summary.failed += 1
                debugLog("[DefaultSourcePackImporter] Failed to import \(sourceURL.absoluteString): \(error.localizedDescription)")
            }
        }

        return summary
    }

    private func sourceExists(sourceID: String) async throws -> Bool
    {
        let context = DatabaseManager.shared.persistentContainer.newBackgroundContext()

        return try await context.performAsync {
            let fetchRequest = Source.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "%K == %@", #keyPath(Source.identifier), sourceID)

            return try context.count(for: fetchRequest) > 0
        }
    }

    private func importSource(sourceURL: URL) async throws
    {
        let context = DatabaseManager.shared.persistentContainer.newBackgroundContext()
        let source = try await AppManager.shared.fetchSource(sourceURL: sourceURL, managedObjectContext: context)

        try await context.performAsync {
            try context.save()
        }

        NotificationCenter.default.post(name: AppManager.didAddSourceNotification, object: source)
    }
}

private struct DefaultSourcePack: Decodable
{
    let version: Int
    let name: String
    let repos: [URL]
}

private struct ImportSummary
{
    var added = 0
    var skipped = 0
    var failed = 0
}
```

- [ ] **Step 6: Hook importer after database startup**

Modify the success branch in `AltStore/AppDelegate.swift` inside `DatabaseManager.shared.start { ... }` so it becomes:

```swift
            else
            {
                debugLog("Started DatabaseManager.")

                Task {
                    await DefaultSourcePackImporter.shared.importIfNeeded()
                }
            }
```

Do not run importer before the database start completion. Do not call importer from background fetch, intents, previews, or extensions.

- [ ] **Step 7: Run targeted tests to verify GREEN**

Run:

```bash
rtk python3 scripts/ci/test_default_source_pack.py
rtk python3 scripts/ci/test_verify_ipa_metadata.py
rtk python3 scripts/ci/test_asc_workflow.py
```

Expected:

- `test_default_source_pack.py`: `Ran 3 tests` and `OK`;
- `test_verify_ipa_metadata.py`: `Ran 3 tests` and `OK`;
- `test_asc_workflow.py`: `Ran 4 tests` and `OK`.

- [ ] **Step 8: Optional compile validation if fast enough**

Run a no-upload compile/build validation only if it does not require changing signing state:

```bash
rtk proxy xcodebuild -project AltStore.xcodeproj -scheme "SideStore - Release" -configuration Release -showBuildSettings
```

Expected: command completes and confirms the scheme/build settings are readable. Full archive/export stays in the later IPA task.

- [ ] **Step 9: Commit only source-pack files**

Run:

```bash
rtk git add AltStore/Resources/DefaultSources.json 'AltStore/Managing Apps/DefaultSourcePackImporter.swift' AltStore/AppDelegate.swift scripts/ci/test_default_source_pack.py
rtk git commit --only -m "feat: import bundled default sources" -- AltStore/Resources/DefaultSources.json 'AltStore/Managing Apps/DefaultSourcePackImporter.swift' AltStore/AppDelegate.swift scripts/ci/test_default_source_pack.py
```

Expected: one commit with exactly four files. `fastlane/`, `.asc/config.json`, `.asc/artifacts/`, `.asc/runs/`, `Dependencies`, and unrelated files remain outside the commit.

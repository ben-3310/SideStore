import json
import re
import unittest
from collections import Counter
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
        duplicates = [source_id for source_id, count in Counter(normalized).items() if count > 1]
        self.assertEqual(duplicates, ["pokemmo.com/altstore"])
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
        self.assertIn("seenSourceIDs.insert(sourceID).inserted", source)

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

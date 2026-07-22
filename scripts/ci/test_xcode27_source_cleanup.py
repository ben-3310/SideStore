import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]


def source_text(relative_path: str) -> str:
    return (REPO_ROOT / relative_path).read_text(encoding="utf-8")


class AltSignCleanupTests(unittest.TestCase):
    def test_dump_macho_info_is_not_in_a_private_extension(self) -> None:
        application = source_text(
            "Dependencies/AltSign/Sources/Model/ALTApplication.swift"
        )
        self.assertIn(
            "\n\nextension ALTApplication {\n    @objc\n    public func dumpMachOInfo()",
            application,
        )

    def test_certificate_logging_uses_non_optional_name(self) -> None:
        operations = source_text(
            "Dependencies/AltSign/Sources/ALTAppleAPI+Operations.swift"
        )

        self.assertIn('"\\($0.name) (\\($0.identifier ?? "nil"))"', operations)
        self.assertIn('certificate.name) (ID: \\(certificate.identifier ?? "nil")', operations)
        self.assertNotIn('$0.name ?? "nil"', operations)
        self.assertNotIn('certificate.name ?? "nil"', operations)

    def test_decrypt_does_not_create_unused_combined_ciphertext(self) -> None:
        bridge = source_text("Dependencies/AltSign/SwiftBridge/CoreCryptoBridge.swift")

        self.assertNotIn("let combined = ciphertext + tag", bridge)


class OpenSSLModernizationTests(unittest.TestCase):
    def test_csr_generation_uses_evp_keygen_without_legacy_rsa_symbols(self) -> None:
        certificates_manager = source_text(
            "Dependencies/AltSign/SwiftBridge/CertificatesManager.swift"
        )

        for symbol in (
            "EVP_PKEY_CTX_new_id",
            "EVP_PKEY_keygen_init",
            "EVP_PKEY_keygen",
        ):
            with self.subTest(symbol=symbol):
                self.assertIn(symbol, certificates_manager)

        for symbol in (
            "RSA_new",
            "RSA_free",
            "RSA_generate_key_ex",
            "EVP_PKEY_set1_RSA",
        ):
            with self.subTest(symbol=symbol):
                self.assertNotIn(symbol, certificates_manager)


class RoxasModernizationTests(unittest.TestCase):
    def test_sendable_declarations_are_unannotated_baseline(self) -> None:
        declarations = {
            "AltStoreCore/Extensions/JSONDecoder+Properties.swift": "public final class JSONDecoder: Foundation.JSONDecoder",
            "AltStoreCore/Model/DatabaseManager/DatabaseManager.swift": "fileprivate class PersistentContainer: RSTPersistentContainer",
            "AltStoreCore/Roxas/RSTOperation.swift": "open class RSTOperation: Operation",
            "AltStoreCore/Roxas/RSTBlockOperation.swift": "open class RSTBlockOperation: RSTOperation",
            "AltStoreCore/Roxas/RSTLoadOperation.swift": "open class RSTLoadOperation: RSTOperation",
            "AltStoreCore/Roxas/RSTOperationQueue.swift": "open class RSTOperationQueue: OperationQueue",
            "AltStoreCore/Roxas/RSTPersistentContainer.swift": "public class RSTPersistentContainer: NSPersistentContainer",
            "Shared/Errors/ALTWrappedError.swift": "public class ALTWrappedError: NSError",
        }

        block_operation = source_text("AltStoreCore/Roxas/RSTBlockOperation.swift")
        self.assertIn("open class RSTAsyncBlockOperation: RSTBlockOperation", block_operation)

        for relative_path, declaration in declarations.items():
            with self.subTest(source=relative_path):
                self.assertIn(declaration, source_text(relative_path))

    def test_specialized_data_sources_use_redundant_view_casts_baseline(self) -> None:
        data_sources = (
            "AltStoreCore/Roxas/RSTArrayDataSource.swift",
            "AltStoreCore/Roxas/RSTCompositeDataSource.swift",
            "AltStoreCore/Roxas/RSTFetchedResultsDataSource.swift",
        )

        for relative_path in data_sources:
            with self.subTest(source=relative_path):
                text = source_text(relative_path)
                self.assertTrue(
                    "self.contentView as? UICollectionView" in text
                    or "self.contentView as? UITableView" in text
                )

    def test_fetched_results_checks_window_twice_baseline(self) -> None:
        fetched_results = source_text(
            "AltStoreCore/Roxas/RSTFetchedResultsDataSource.swift"
        )

        self.assertIn("if let window = contentView?.window, window != nil", fetched_results)

    def test_uikit_and_foundation_warning_patterns_exist_baseline(self) -> None:
        merge_policy = source_text(
            "AltStoreCore/Roxas/RSTRelationshipPreservingMergePolicy.swift"
        )
        toast = source_text("AltStoreCore/Roxas/RSTToastView.swift")
        activity = source_text("AltStoreCore/Roxas/UIKit+ActivityIndicating.swift")
        associated_keys = source_text(
            "AltStoreCore/Roxas/UICollectionView+CellContent.swift"
        )
        errors = source_text("Shared/Extensions/NSError+AltStore.swift")
        os_version = source_text(
            "Shared/Extensions/OperatingSystemVersion+Comparable.swift"
        )

        self.assertIn("NSConstraintConflict.cacheSnapshots(for: conflicts)", merge_policy)
        self.assertIn("UIActivityIndicatorView(style: .white)", toast)
        self.assertIn("isNetworkActivityIndicatorVisible", activity)
        self.assertIn('static var nestedUpdatesCounter = "rst_nestedUpdatesCounter"', associated_keys)
        self.assertIn('static var operations = "rst_operations"', associated_keys)
        self.assertIn("a.key as? String ?? \"\"", errors)
        self.assertIn("b.key as? String ?? \"\"", errors)
        self.assertIn("extension OperatingSystemVersion: Comparable", os_version)


if __name__ == "__main__":
    unittest.main()

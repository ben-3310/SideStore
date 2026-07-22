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
    def test_inherited_sendable_conformances_are_restatement_explicit(self) -> None:
        declarations = {
            "AltStoreCore/Extensions/JSONDecoder+Properties.swift": "public final class JSONDecoder: Foundation.JSONDecoder, @unchecked Sendable",
            "AltStoreCore/Model/DatabaseManager/DatabaseManager.swift": "fileprivate class PersistentContainer: RSTPersistentContainer, @unchecked Sendable",
            "AltStoreCore/Roxas/RSTOperation.swift": "open class RSTOperation: Operation, @unchecked Sendable",
            "AltStoreCore/Roxas/RSTBlockOperation.swift": "open class RSTBlockOperation: RSTOperation, @unchecked Sendable",
            "AltStoreCore/Roxas/RSTLoadOperation.swift": "open class RSTLoadOperation: RSTOperation, @unchecked Sendable",
            "AltStoreCore/Roxas/RSTOperationQueue.swift": "open class RSTOperationQueue: OperationQueue, @unchecked Sendable",
            "AltStoreCore/Roxas/RSTPersistentContainer.swift": "public class RSTPersistentContainer: NSPersistentContainer, @unchecked Sendable",
            "Shared/Errors/ALTWrappedError.swift": "public class ALTWrappedError: NSError, @unchecked Sendable",
        }

        block_operation = source_text("AltStoreCore/Roxas/RSTBlockOperation.swift")
        self.assertIn(
            "open class RSTAsyncBlockOperation: RSTBlockOperation, @unchecked Sendable",
            block_operation,
        )

        for relative_path, declaration in declarations.items():
            with self.subTest(source=relative_path):
                self.assertIn(declaration, source_text(relative_path))

    def test_specialized_data_sources_use_their_concrete_content_view_types(self) -> None:
        data_sources = (
            "AltStoreCore/Roxas/RSTArrayDataSource.swift",
            "AltStoreCore/Roxas/RSTCompositeDataSource.swift",
            "AltStoreCore/Roxas/RSTFetchedResultsDataSource.swift",
        )

        for relative_path in data_sources:
            with self.subTest(source=relative_path):
                text = source_text(relative_path)
                self.assertNotIn(
                    "if let collectionView = self.contentView as? UICollectionView,",
                    text,
                )
                self.assertNotIn(
                    "if let tableView = self.contentView as? UITableView,",
                    text,
                )
                self.assertIn("if let collectionView = self.contentView,", text)
                self.assertIn("if let tableView = self.contentView,", text)

    def test_fetched_results_checks_window_without_rebinding_nonoptional_value(self) -> None:
        fetched_results = source_text(
            "AltStoreCore/Roxas/RSTFetchedResultsDataSource.swift"
        )

        self.assertNotIn(
            "if let window = contentView?.window, window != nil", fetched_results
        )
        self.assertEqual(fetched_results.count("if contentView?.window != nil"), 2)

    def test_constraint_snapshot_cache_result_is_explicitly_discarded(self) -> None:
        merge_policy = source_text(
            "AltStoreCore/Roxas/RSTRelationshipPreservingMergePolicy.swift"
        )

        self.assertIn("_ = NSConstraintConflict.cacheSnapshots(for: conflicts)", merge_policy)

    def test_toast_uses_modern_spinner_style_with_original_white_color(self) -> None:
        toast = source_text("AltStoreCore/Roxas/RSTToastView.swift")

        self.assertIn(
            "@objc public let activityIndicatorView = UIActivityIndicatorView(style: .medium)",
            toast,
        )
        self.assertIn("activityIndicatorView.color = .white", toast)
        self.assertNotIn("UIActivityIndicatorView(style: .white)", toast)

    def test_application_activity_indicating_api_is_preserved_as_noop(self) -> None:
        activity = source_text("AltStoreCore/Roxas/UIKit+ActivityIndicating.swift")

        self.assertIn("func startIndicatingActivity() {}", activity)
        self.assertIn("func stopIndicatingActivity() {}", activity)
        self.assertNotIn("isNetworkActivityIndicatorVisible", activity)

    def test_collection_view_associated_objects_use_stable_byte_addresses(self) -> None:
        associated_keys = source_text(
            "AltStoreCore/Roxas/UICollectionView+CellContent.swift"
        )

        self.assertIn(
            "nonisolated(unsafe) static var nestedUpdatesCounter: UInt8 = 0",
            associated_keys,
        )
        self.assertIn(
            "nonisolated(unsafe) static var operations: UInt8 = 0",
            associated_keys,
        )
        self.assertNotIn('static var nestedUpdatesCounter = "', associated_keys)
        self.assertNotIn('static var operations = "', associated_keys)

    def test_error_key_order_uses_string_keys_without_redundant_casts(self) -> None:
        errors = source_text("Shared/Extensions/NSError+AltStore.swift")

        self.assertIn("let indexA = preferredKeyOrder.firstIndex(of: a.key)", errors)
        self.assertIn("let indexB = preferredKeyOrder.firstIndex(of: b.key)", errors)
        self.assertNotIn('a.key as? String ?? ""', errors)
        self.assertNotIn('b.key as? String ?? ""', errors)

    def test_operating_system_version_marks_imported_retroactive_conformance(self) -> None:
        os_version = source_text(
            "Shared/Extensions/OperatingSystemVersion+Comparable.swift"
        )

        self.assertIn(
            "extension OperatingSystemVersion: @retroactive Comparable", os_version
        )


if __name__ == "__main__":
    unittest.main()

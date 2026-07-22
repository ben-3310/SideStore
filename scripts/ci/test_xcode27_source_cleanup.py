import re
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Optional


REPO_ROOT = Path(__file__).resolve().parents[2]


def source_text(relative_path: str) -> str:
    return (REPO_ROOT / relative_path).read_text(encoding="utf-8")


def pbx_object(project: str, object_id: str) -> str:
    match = re.search(
        rf"^\t\t{re.escape(object_id)} .*? = \{{.*?^\t\t\}};$",
        project,
        flags=re.MULTILINE | re.DOTALL,
    )
    if match is None:
        raise AssertionError(f"PBX object {object_id} not found")
    return match.group(0)


def storyboard_element(relative_path: str, object_id: str) -> Optional[ET.Element]:
    root = ET.parse(REPO_ROOT / relative_path).getroot()
    return next(
        (element for element in root.iter() if element.get("id") == object_id),
        None,
    )


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


class QuickStartSafetyTests(unittest.TestCase):
    def test_error_codes_are_sendable(self) -> None:
        localized_error = source_text("Shared/Errors/ALTLocalizedError.swift")

        self.assertIn(
            "public protocol ALTErrorCode: RawRepresentable, Sendable where RawValue == Int",
            localized_error,
        )

    def test_widget_configuration_intent_declares_both_availability_domains(self) -> None:
        intent = source_text("AltWidget/Intents/ViewAppIntent.swift")

        self.assertIn(
            "@available(iOS 17, *)\n"
            "@available(iOSApplicationExtension 17, *)\n"
            "struct SelectAppIntent: WidgetConfigurationIntent",
            intent,
        )

    def test_widget_timeline_entries_are_immutable(self) -> None:
        provider = source_text("AltWidget/Providers/AppsTimelineProvider.swift")

        self.assertIn("let entries = self.makeEntries(for: apps, in: context)", provider)
        self.assertNotIn("var entries = self.makeEntries(for: apps, in: context)", provider)

    def test_flattened_quick_start_artifacts_are_not_xcode_project_references(self) -> None:
        project = source_text("AltStore.xcodeproj/project.pbxproj")

        self.assertNotIn("UsersbenRepoSideStore", project)
        self.assertNotIn("UsersbenLibraryMobile Documents", project)

    def test_deployment_target_remains_ios_15(self) -> None:
        project = source_text("AltStore.xcodeproj/project.pbxproj")

        for configuration_id in ("A85A51462F4B4532002E2E11", "A85A51472F4B4532002E2E11"):
            with self.subTest(configuration=configuration_id):
                configuration = pbx_object(project, configuration_id)
                self.assertIn("IPHONEOS_DEPLOYMENT_TARGET = 15.0;", configuration)
                self.assertNotIn("IPHONEOS_DEPLOYMENT_TARGET = 17.0;", configuration)
                self.assertNotIn("IPHONEOS_DEPLOYMENT_TARGET = 18.6;", configuration)

    def test_altstore_core_disables_eager_linking(self) -> None:
        configuration = source_text("xcconfigs/AltStoreCore.xcconfig")

        self.assertIn("EAGER_LINKING = NO", configuration)

    def test_xcode_build_phases_have_intentional_dependency_behavior(self) -> None:
        project = source_text("AltStore.xcodeproj/project.pbxproj")
        sidebackup_phase = pbx_object(project, "A8E00D3F2D0C9C6D000DD2C7")

        self.assertNotIn("A8D768282F52F0D4002356C4", project)
        self.assertIn("alwaysOutOfDate = 1;", sidebackup_phase)
        self.assertIn(
            '"$(PROJECT_DIR)/AltStore/Resources/SideBackup.ipa",',
            sidebackup_phase,
        )


class Xcode27ListedWarningsTests(unittest.TestCase):
    def test_project_records_xcode_27_upgrade(self) -> None:
        project = source_text("AltStore.xcodeproj/project.pbxproj")

        self.assertIn("LastUpgradeCheck = 2700;", project)

    def test_sidestore_has_no_obsolete_minimuxer_library_search_path(self) -> None:
        project = source_text("AltStore.xcodeproj/project.pbxproj")
        obsolete_path = (
            '"$(PROJECT_DIR)/Dependencies/minimuxer/Sources/RustBridge/lib"'
        )

        for configuration_id in (
            "BFD2477F2284B9A700981D42",
            "BFD247802284B9A700981D42",
        ):
            with self.subTest(configuration=configuration_id):
                self.assertNotIn(
                    obsolete_path,
                    pbx_object(project, configuration_id),
                )

    def test_sidestore_marks_embedded_openssl_as_runtime_needed(self) -> None:
        project = source_text("AltStore.xcodeproj/project.pbxproj")
        side_store_target = pbx_object(project, "BFD247692284B9A500981D42")
        frameworks_phase = pbx_object(project, "BFD247672284B9A500981D42")
        embed_frameworks_phase = pbx_object(project, "BF088D2B2501A087008082D9")

        self.assertIn("A823DC542FF0D82100AD4DAF", frameworks_phase)
        self.assertNotIn("A823DC542FF0D82100AD4DAF", embed_frameworks_phase)
        self.assertIn("A823DC532FF0D82100AD4DAF", side_store_target)
        self.assertIn("A823DC532FF0D82100AD4DAF", project)
        self.assertIn("A82526E72FF0E1C000FB2EDD", project)
        self.assertIn("A82526E62FF0E1C000FB2EDD", project)

        for configuration_id in (
            "BFD2477F2284B9A700981D42",
            "BFD247802284B9A700981D42",
        ):
            with self.subTest(configuration=configuration_id):
                configuration = pbx_object(project, configuration_id)
                self.assertIn('"-needed_framework",', configuration)
                self.assertIn("OpenSSL,", configuration)

    def test_em_proxy_swift_only_suppresses_empty_object_warnings(self) -> None:
        project = source_text("AltStore.xcodeproj/project.pbxproj")

        for configuration_id in (
            "A85A51462F4B4532002E2E11",
            "A85A51472F4B4532002E2E11",
        ):
            with self.subTest(configuration=configuration_id):
                configuration = pbx_object(project, configuration_id)
                self.assertIn(
                    'OTHER_LIBTOOLFLAGS = "-no_warning_for_no_symbols";',
                    configuration,
                )

    def test_storyboards_use_supported_xcode_27_values(self) -> None:
        settings = source_text("AltStore/Settings/Settings.storyboard")

        self.assertIn('image="apple.terminal"', settings)
        self.assertNotIn('image="terminal"', settings)
        self.assertIsNone(
            storyboard_element(
                "AltStore/Sources/Sources.storyboard",
                "W0l-zW-MjJ",
            )
        )

        navigation_item = storyboard_element(
            "AltStore/Base.lproj/Main.storyboard",
            "FLf-DS-F77",
        )
        self.assertIsNotNone(navigation_item)
        self.assertNotIn("style", navigation_item.attrib)


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

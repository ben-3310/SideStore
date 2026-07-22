import json
import re
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
PROJECT_FILE = REPO_ROOT / "AltStore.xcodeproj" / "project.pbxproj"
PROJECT_TEXT = PROJECT_FILE.read_text()

TEST_TARGETS = {
    "A8E2DB202D684CBD009E5D31": "UITests",
    "A81A8CC42D68BA610086C96F": "DataStructureTests",
}


def native_target_ids() -> set[str]:
    pattern = re.compile(
        r"^\s*([A-F0-9]{24}) /\* .* \*/ = \{\n"
        r"\s*isa = PBXNativeTarget;",
        re.MULTILINE,
    )
    return set(pattern.findall(PROJECT_TEXT))


class XcodeTestTargetTests(unittest.TestCase):
    def test_xctest_native_targets_and_products_exist(self) -> None:
        targets = native_target_ids()

        for target_id, target_name in TEST_TARGETS.items():
            with self.subTest(target=target_name):
                self.assertIn(target_id, targets)
                self.assertRegex(
                    PROJECT_TEXT,
                    rf"(?s){target_id} /\* {target_name} \*/ = \{{.*?"
                    rf"productType = \"com\.apple\.product-type\.bundle\."
                    rf"(?:ui-testing|unit-test)\";",
                )

        self.assertIn("DataStructureTests.xctest", PROJECT_TEXT)
        self.assertIn("UITests.xctest", PROJECT_TEXT)

    def test_xctest_targets_have_build_graph_entries(self) -> None:
        required_ids = (
            "A81A8CC12D68BA610086C96F",  # DataStructureTests Sources
            "A81A8CC22D68BA610086C96F",  # DataStructureTests Frameworks
            "A81A8CC32D68BA610086C96F",  # DataStructureTests Resources
            "A81A8CC92D68BA610086C96F",  # DataStructureTests configs
            "A8E2DB1D2D684CBD009E5D31",  # UITests Sources
            "A8E2DB1E2D684CBD009E5D31",  # UITests Frameworks
            "A8E2DB1F2D684CBD009E5D31",  # UITests Resources
            "A8E2DB292D684CBD009E5D31",  # UITests configs
            "A8E2DB282D684CBD009E5D31",  # UITests app dependency
        )

        for object_id in required_ids:
            with self.subTest(object_id=object_id):
                self.assertIn(object_id, PROJECT_TEXT)

        self.assertRegex(
            PROJECT_TEXT,
            r"(?s)A8E2DB282D684CBD009E5D31 /\* PBXTargetDependency \*/ = \{.*?"
            r"target = BFD247692284B9A500981D42 /\* SideStore \*/;",
        )

    def test_schemes_and_test_plans_reference_existing_targets(self) -> None:
        targets = native_target_ids()
        plans = (
            REPO_ROOT / "SideStore" / "Tests" / "SideStoreTests.xctestplan",
            REPO_ROOT / "SideStore" / "Tests" / "DataStructureTests.xctestplan",
        )

        for plan_path in plans:
            plan = json.loads(plan_path.read_text())
            for test_target in plan["testTargets"]:
                target = test_target["target"]
                with self.subTest(plan=plan_path.name, target=target["name"]):
                    self.assertIn(target["identifier"], targets)

        schemes = (
            REPO_ROOT
            / "AltStore.xcodeproj"
            / "xcshareddata"
            / "xcschemes"
            / "SideStore.xcscheme",
            REPO_ROOT
            / "AltStore.xcodeproj"
            / "xcshareddata"
            / "xcschemes"
            / "DataStructuresTests.xcscheme",
        )
        for scheme_path in schemes:
            scheme_text = scheme_path.read_text()
            blueprint_ids = re.findall(r'BlueprintIdentifier = "([A-F0-9]{24})"', scheme_text)
            test_blueprints = set(blueprint_ids) & set(TEST_TARGETS)
            with self.subTest(scheme=scheme_path.name):
                self.assertTrue(test_blueprints)
                self.assertTrue(test_blueprints <= targets)

    def test_test_target_xcconfigs_define_unique_bundle_ids(self) -> None:
        expected = {
            "UITests.xcconfig": ".UITests",
            "DataStructureTests.xcconfig": ".DataStructureTests",
        }

        for filename, suffix in expected.items():
            config_path = REPO_ROOT / "xcconfigs" / filename
            with self.subTest(config=filename):
                self.assertTrue(config_path.is_file())
                config = config_path.read_text()
                self.assertIn('#include "../Build.xcconfig"', config)
                self.assertIn(
                    f"PRODUCT_BUNDLE_IDENTIFIER = $(PRODUCT_BUNDLE_IDENTIFIER){suffix}",
                    config,
                )


if __name__ == "__main__":
    unittest.main()

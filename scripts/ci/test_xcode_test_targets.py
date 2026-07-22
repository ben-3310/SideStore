import json
import re
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
PROJECT_FILE = REPO_ROOT / "AltStore.xcodeproj" / "project.pbxproj"
PROJECT_TEXT = PROJECT_FILE.read_text()

TEST_TARGETS = {
    "A8E2DB202D684CBD009E5D31": "UITests",
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

        self.assertIn("UITests.xctest", PROJECT_TEXT)

    def test_xctest_targets_have_build_graph_entries(self) -> None:
        required_ids = (
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
            "UITests.xcconfig": "$(MAIN_BUNDLE_IDENTIFIER).UITests",
        }

        for filename, bundle_id in expected.items():
            config_path = REPO_ROOT / "xcconfigs" / filename
            with self.subTest(config=filename):
                self.assertTrue(config_path.is_file())
                config = config_path.read_text()
                self.assertIn('#include "../Build.xcconfig"', config)
                self.assertIn(
                    f"PRODUCT_BUNDLE_IDENTIFIER = {bundle_id}",
                    config,
                )

    def test_ci_plan_runs_only_deterministic_launch_smoke(self) -> None:
        plan_path = REPO_ROOT / "SideStore" / "Tests" / "SideStoreTests.xctestplan"
        plan = json.loads(plan_path.read_text())
        ui_target = next(
            item
            for item in plan["testTargets"]
            if item["target"]["identifier"] == "A8E2DB202D684CBD009E5D31"
        )
        skipped = set(ui_target["skippedTests"])
        network_tests = {
            "UITests/testBulkAddInputSources()",
            "UITests/testBulkAddRecommendedSources()",
            "UITests/testRepeatabilityForStagingInputSources()",
            "UITests/testRepeatabilityForStagingRecommendedSources()",
        }

        self.assertTrue(network_tests <= skipped)
        self.assertNotIn("UITestsLaunchTests", skipped)
        self.assertNotIn("UITestsLaunchTests/testLaunch()", skipped)

        launch_tests = (
            REPO_ROOT
            / "SideStore"
            / "Tests"
            / "UITests"
            / "UITestsLaunchTests.swift"
        ).read_text()
        self.assertIn("func testLaunch() throws", launch_tests)
        self.assertIn("app.wait(for: .runningForeground, timeout: 15)", launch_tests)
        self.assertRegex(
            launch_tests,
            r"runsForEachTargetApplicationUIConfiguration:\s+Bool\s+\{\s+false\s+\}",
        )

        scheme = (
            REPO_ROOT
            / "AltStore.xcodeproj"
            / "xcshareddata"
            / "xcschemes"
            / "SideStore.xcscheme"
        ).read_text()
        self.assertNotIn("UITests/testExample()", scheme)


if __name__ == "__main__":
    unittest.main()

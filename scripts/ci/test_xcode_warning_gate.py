import unittest

from scripts.ci.xcode_warning_gate import unexpected_warnings


class WarningGateTests(unittest.TestCase):
    def test_allows_only_zipfoundation_manifest_warning(self) -> None:
        allowed = (
            "/tmp/DerivedData/SourcePackages/checkouts/ZIPFoundation/"
            "Package@swift-5.9.swift:23:61: warning: 'v4' is deprecated: "
            "watchOS 9.0 is the oldest supported version"
        )

        self.assertEqual(unexpected_warnings(allowed), [])

    def test_rejects_first_party_and_other_dependency_warnings(self) -> None:
        log = "\n".join(
            [
                "/repo/AltStoreCore/Foo.swift:1:1: warning: broken",
                "/tmp/ZIPFoundation/Foo.swift:1:1: warning: new warning",
            ]
        )

        self.assertEqual(len(unexpected_warnings(log)), 2)


if __name__ == "__main__":
    unittest.main()

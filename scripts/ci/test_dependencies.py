from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from scripts.ci.dependencies import DependencyLayoutError, verify_dependencies


REQUIRED_DEPENDENCIES = ("AltSign", "em_proxy", "minimuxer")


def make_dependencies(path: Path, omit: str | None = None) -> Path:
    path.mkdir()
    for name in REQUIRED_DEPENDENCIES:
        if name != omit:
            (path / name).mkdir()
    return path


def make_root_with_dependencies(tmpdir: Path, omit: str | None = None) -> Path:
    root = tmpdir / "SideStore"
    root.mkdir()
    make_dependencies(root / "Dependencies", omit)
    return root


def make_dependencies_file(tmpdir: Path) -> Path:
    root = tmpdir / "SideStore"
    root.mkdir()
    (root / "Dependencies").touch()
    return root


def make_broken_dependencies_symlink(tmpdir: Path) -> Path:
    root = tmpdir / "SideStore"
    root.mkdir()
    (root / "Dependencies").symlink_to(tmpdir / "missing", target_is_directory=True)
    return root


class DependencyLayoutTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = TemporaryDirectory()
        self.tmpdir = Path(self.temporary_directory.name)

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def test_accepts_directory_from_recursive_checkout(self) -> None:
        verify_dependencies(make_root_with_dependencies(self.tmpdir))

    def test_accepts_relative_symlink_to_external_directory(self) -> None:
        make_dependencies(self.tmpdir / "SideStore_Dependencies")
        root = self.tmpdir / "SideStore"
        root.mkdir()
        (root / "Dependencies").symlink_to(Path("../SideStore_Dependencies"), target_is_directory=True)

        verify_dependencies(root)

    def test_rejects_absolute_symlink_to_external_directory(self) -> None:
        external = make_dependencies(self.tmpdir / "SideStore_Dependencies")
        root = self.tmpdir / "SideStore"
        root.mkdir()
        (root / "Dependencies").symlink_to(external, target_is_directory=True)

        with self.assertRaisesRegex(DependencyLayoutError, "must target"):
            verify_dependencies(root)

    def test_rejects_symlink_to_another_relative_directory(self) -> None:
        make_dependencies(self.tmpdir / "Other_Dependencies")
        root = self.tmpdir / "SideStore"
        root.mkdir()
        (root / "Dependencies").symlink_to(Path("../Other_Dependencies"), target_is_directory=True)

        with self.assertRaisesRegex(DependencyLayoutError, "must target"):
            verify_dependencies(root)

    def test_rejects_missing_dependencies_path(self) -> None:
        with self.assertRaisesRegex(DependencyLayoutError, "missing Dependencies"):
            verify_dependencies(self.tmpdir)

    def test_rejects_regular_file_and_broken_symlink(self) -> None:
        for setup in (make_dependencies_file, make_broken_dependencies_symlink):
            with self.subTest(setup=setup.__name__), self.assertRaises(DependencyLayoutError):
                case_directory = self.tmpdir / setup.__name__
                case_directory.mkdir()
                verify_dependencies(setup(case_directory))

    def test_rejects_missing_required_child(self) -> None:
        root = make_root_with_dependencies(self.tmpdir, omit="minimuxer")

        with self.assertRaisesRegex(DependencyLayoutError, "minimuxer"):
            verify_dependencies(root)


if __name__ == "__main__":
    unittest.main()

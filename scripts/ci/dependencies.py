#!/usr/bin/env python3
"""Verify that the repository's build dependencies are available."""

import argparse
from pathlib import Path


REQUIRED_DEPENDENCIES = ("AltSign", "em_proxy", "minimuxer")


class DependencyLayoutError(RuntimeError):
    """Raised when the Dependencies layout cannot be used for a build."""


def verify_dependencies(root: Path) -> None:
    """Ensure ``root/Dependencies`` provides the required source directories."""
    dependencies = root / "Dependencies"
    if dependencies.is_symlink() and dependencies.readlink().is_absolute():
        raise DependencyLayoutError("Dependencies symlink must use a relative target")
    if not dependencies.exists():
        raise DependencyLayoutError(
            "missing Dependencies; initialise submodules or create the relative link"
        )
    if not dependencies.is_dir():
        raise DependencyLayoutError("Dependencies must be a directory or a symlink to one")
    for name in REQUIRED_DEPENDENCIES:
        if not (dependencies / name).is_dir():
            raise DependencyLayoutError(f"missing required dependency: Dependencies/{name}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parents[2],
        help="repository root (defaults to the repository containing this script)",
    )
    arguments = parser.parse_args()

    try:
        verify_dependencies(arguments.root)
    except DependencyLayoutError as error:
        print(error)
        return 1

    print(f"Dependencies verified at {arguments.root.joinpath('Dependencies').resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

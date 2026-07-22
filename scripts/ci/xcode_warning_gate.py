#!/usr/bin/env python3
import re
import sys
from pathlib import Path


ZIPFOUNDATION_MANIFEST_WARNING = re.compile(
    r"SourcePackages/checkouts/ZIPFoundation/Package@swift-5\.9\.swift:"
    r"\d+:\d+: warning: 'v4' is deprecated: watchOS 9\.0 is the oldest supported version$"
)


def unexpected_warnings(log: str) -> list[str]:
    warnings = [line.strip() for line in log.splitlines() if "warning:" in line]
    return [
        line
        for line in warnings
        if not ZIPFOUNDATION_MANIFEST_WARNING.search(line)
    ]


def main() -> int:
    log_path = Path(sys.argv[1])
    warnings = unexpected_warnings(log_path.read_text(encoding="utf-8"))
    if warnings:
        print("\n".join(warnings))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

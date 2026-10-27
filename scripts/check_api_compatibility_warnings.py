#!/usr/bin/env python3
"""Fail a full build when the SDK reports new API-version compatibility warnings.

The baseline records existing diagnostics, not confirmed-safe calls. Counts are
retained per file and API so a second unsafe use cannot hide behind an old one.
"""

import argparse
import collections
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ANSI = re.compile(r"\x1b\[[0-9;]*m")
DIAGNOSTIC = re.compile(
    r"File: ([^\r\n]*?):(\d+):(\d+)\s+"
    r"The '([^']+)' API is supported since SDK version ([0-9.]+)\. "
    r"However, the current compatible SDK version is ([0-9.]+(?:\([0-9]+\))?)\."
)
COMPILE = re.compile(r"Finished :entry:default@CompileArkTS\.\.\.")


def check(log_path: Path, baseline_path: Path) -> int:
    text = ANSI.sub("", log_path.read_text(encoding="utf-8", errors="replace"))
    if not COMPILE.search(text) or "BUILD SUCCESSFUL" not in text:
        print("API compatibility gate requires a successful, non-cached entry ArkTS compilation.", file=sys.stderr)
        return 2

    matches = list(DIAGNOSTIC.finditer(text))
    if text.count("API is supported since SDK version") != len(matches):
        print("Unrecognized SDK compatibility diagnostic; review the build log.", file=sys.stderr)
        return 2
    actual = collections.Counter()
    for match in matches:
        try:
            path = Path(match.group(1)).resolve().relative_to(ROOT).as_posix()
        except ValueError:
            print(f"Compatibility warning outside the project: {match.group(1)}", file=sys.stderr)
            return 2
        actual[(path, match.group(4), match.group(5), match.group(6))] += 1

    data = json.loads(baseline_path.read_text(encoding="utf-8"))
    if data.get("schema") != 1 or not isinstance(data.get("warnings"), list):
        print("Invalid API compatibility baseline.", file=sys.stderr)
        return 2
    allowed = collections.Counter()
    for item in data["warnings"]:
        key = (item["file"], item["api"], item["since"], item["compatible"])
        if key in allowed or not isinstance(item["count"], int) or item["count"] < 1:
            print(f"Invalid or duplicate baseline entry: {key}", file=sys.stderr)
            return 2
        allowed[key] = item["count"]

    if allowed and not actual:
        print("No API compatibility diagnostics found while baseline is nonempty; verify SDK diagnostics are enabled.",
              file=sys.stderr)
        return 2

    added = actual - allowed
    if added:
        print("New API compatibility warnings detected:", file=sys.stderr)
        for (path, api, since, compatible), count in sorted(added.items()):
            print(f"  {path}: {api} since {since}, compatible {compatible}: +{count}", file=sys.stderr)
        return 1
    print(f"API compatibility gate passed; {sum(actual.values())} existing warnings remain for review.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    parser.add_argument("--baseline", type=Path, default=ROOT / "scripts/api_compatibility_warnings.json")
    args = parser.parse_args()
    try:
        return check(args.log, args.baseline)
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"API compatibility gate failed: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())

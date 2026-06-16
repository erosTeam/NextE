#!/usr/bin/env python3
"""
i18n parity & duplicate checker (ported from V2Next).

For every resource qualifier under entry/src/main/resources/<locale>/element/string.json
(plus base), verify:
  - no duplicate string names within a file
  - every locale defines exactly the same key set as `base` (no missing / extra keys)

Run: python3 scripts/check_i18n_duplicates.py
Exit 1 on any violation.
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "entry" / "src" / "main" / "resources"

def load_names(p: Path):
    names = []
    dups = []
    data = json.loads(p.read_text(encoding="utf-8"))
    for item in data.get("string", []):
        n = item["name"]
        if n in names:
            dups.append(n)
        names.append(n)
    return names, dups

def main() -> int:
    errors = []
    locales = {}
    for d in sorted(RES.glob("*/element/string.json")):
        locale = d.parent.parent.name
        names, dups = load_names(d)
        if dups:
            errors.append(f"{locale}: duplicate keys {sorted(set(dups))}")
        locales[locale] = set(names)

    if "base" not in locales:
        errors.append("missing base/element/string.json")
    else:
        base = locales["base"]
        for locale, keys in locales.items():
            if locale == "base":
                continue
            missing = base - keys
            extra = keys - base
            if missing:
                errors.append(f"{locale}: missing keys {sorted(missing)}")
            if extra:
                errors.append(f"{locale}: extra keys not in base {sorted(extra)}")

    if errors:
        print("✗ i18n parity: " + str(len(errors)) + " issue(s)")
        for e in errors:
            print("  " + e)
        return 1
    print("✓ i18n parity: " + str(len(locales)) + " locales, identical key sets, no duplicates")
    return 0

if __name__ == "__main__":
    sys.exit(main())

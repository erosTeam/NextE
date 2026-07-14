#!/usr/bin/env python3
"""Disable restricted clipboard auto-detection in the public unsigned CI artifact."""

from __future__ import annotations

import argparse
from pathlib import Path


PERMISSION_BLOCK = ''',
      {
        "name": "ohos.permission.READ_PASTEBOARD",
        "reason": "$string:perm_read_pasteboard_reason",
        "usedScene": {
          "abilities": ["EntryAbility"],
          "when": "inuse"
        }
      }'''


def prepare(root: Path) -> None:
    flag = root / "shared/src/main/ets/services/ClipboardLinkBuildFlag.ets"
    flag_text = flag.read_text(encoding="utf-8")
    enabled = "CLIPBOARD_LINK_BUILD_ENABLED: boolean = true"
    disabled = "CLIPBOARD_LINK_BUILD_ENABLED: boolean = false"
    if flag_text.count(enabled) != 1:
        raise SystemExit("clipboard build flag does not contain exactly one enabled declaration")
    flag.write_text(flag_text.replace(enabled, disabled, 1), encoding="utf-8")

    module = root / "entry/src/main/module.json5"
    module_text = module.read_text(encoding="utf-8")
    if module_text.count(PERMISSION_BLOCK) != 1:
        raise SystemExit("READ_PASTEBOARD permission block was not found exactly once")
    module_text = module_text.replace(PERMISSION_BLOCK, "", 1)
    if "ohos.permission.READ_PASTEBOARD" in module_text:
        raise SystemExit("READ_PASTEBOARD remains in public module.json5")
    module.write_text(module_text, encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path.cwd())
    args = parser.parse_args()
    prepare(args.root.resolve())


if __name__ == "__main__":
    main()

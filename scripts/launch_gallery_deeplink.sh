#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-127.0.0.1:5555}"
URL="${2:-https://e-hentai.org/g/3998992/f5b5c954d2/}"
BUNDLE="${BUNDLE:-com.erosteam.nexte}"
ABILITY="${ABILITY:-EntryAbility}"
HDC="${HDC:-/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc}"

"$HDC" -t "$TARGET" shell aa force-stop "$BUNDLE"
"$HDC" -t "$TARGET" shell aa start -b "$BUNDLE" -a "$ABILITY" -U "$URL"

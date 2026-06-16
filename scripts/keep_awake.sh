#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HDC=${HDC:-/home/gamer/devtool/ohos/command-line-tools/sdk/default/openharmony/toolchains/hdc}

if [ -f "$ROOT/scripts/dev.env" ]; then
  # shellcheck disable=SC1091
  source "$ROOT/scripts/dev.env"
fi

SCREEN_OFF_TIMEOUT_MS=${SCREEN_OFF_TIMEOUT_MS:-13600000}

target_args=()
if [ "${1:-}" = "-t" ] && [ -n "${2:-}" ]; then
  target_args=(-t "$2")
elif [ -n "${HDC_TARGET:-}" ]; then
  target_args=(-t "$HDC_TARGET")
fi

"$HDC" "${target_args[@]}" shell "power-shell wakeup"
"$HDC" "${target_args[@]}" shell "power-shell timeout -o $SCREEN_OFF_TIMEOUT_MS"

#!/usr/bin/env bash
set -euo pipefail

repo="$(git rev-parse --show-toplevel)"
cd "$repo"

if [[ "$(uname -s)" == "Darwin" ]]; then
  DEVECO_STUDIO_APP="${DEVECO_STUDIO_APP:-/Applications/DevEco-Studio.app}"
  DEVECO_CONTENTS="$DEVECO_STUDIO_APP/Contents"
  DEVECO_JBR="$DEVECO_CONTENTS/jbr/Contents/Home"
  if [[ -d "$DEVECO_JBR" ]]; then
    export JAVA_HOME="${JAVA_HOME:-$DEVECO_JBR}"
    export PATH="$DEVECO_JBR/bin:$PATH"
  fi
  for dir in \
    "$DEVECO_CONTENTS/tools/ohpm/bin" \
    "$DEVECO_CONTENTS/tools/hvigor/bin" \
    "$DEVECO_CONTENTS/sdk/default/openharmony/toolchains"; do
    if [[ -d "$dir" ]]; then
      export PATH="$dir:$PATH"
    fi
  done
fi

if ! command -v hvigorw >/dev/null 2>&1; then
  echo "ERROR: hvigorw not found in PATH. Install DevEco command-line tools or set PATH first." >&2
  exit 127
fi

if ! grep -q '"signingConfigs"' build-profile.json5; then
  echo "ERROR: build-profile.json5 has no signingConfigs." >&2
  echo "Prepare ignored build-profile.local.json5, then run scripts/setup-local-build-profile.sh before signed builds." >&2
  exit 2
fi

cloud_flag_file="shared/src/main/ets/sync/HuaweiCloudSyncBuildFlag.ets"
cloud_flag_backup=""
if [[ "${NEXTE_HUAWEI_CLOUD_SYNC:-1}" == "0" ]]; then
  cloud_flag_backup="$(mktemp)"
  cp "$cloud_flag_file" "$cloud_flag_backup"
  restore_cloud_flag() {
    if [[ -n "$cloud_flag_backup" && -f "$cloud_flag_backup" ]]; then
      cp "$cloud_flag_backup" "$cloud_flag_file"
      rm -f "$cloud_flag_backup"
    fi
  }
  trap restore_cloud_flag EXIT
  python3 - "$cloud_flag_file" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding='utf-8')
next_text = re.sub(
    r'HUAWEI_CLOUD_SYNC_BUILD_ENABLED: boolean = true',
    'HUAWEI_CLOUD_SYNC_BUILD_ENABLED: boolean = false',
    text,
    count=1,
)
if next_text == text:
    raise SystemExit('ERROR: Huawei Cloud sync build flag pattern not found')
path.write_text(next_text, encoding='utf-8')
PY
fi

hvigorw assembleHap --mode module -p product=default -p buildMode=debug --no-daemon

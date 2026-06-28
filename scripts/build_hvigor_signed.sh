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
safe_flag_file="shared/src/main/ets/safe/SafeModeBuildFlag.ets"
app_flag_file="AppScope/app.json5"
cloud_flag_backup=""
safe_flag_backup=""
app_flag_backup=""
restore_build_flags() {
  if [[ -n "$cloud_flag_backup" && -f "$cloud_flag_backup" ]]; then
    cp "$cloud_flag_backup" "$cloud_flag_file"
    rm -f "$cloud_flag_backup"
  fi
  if [[ -n "$safe_flag_backup" && -f "$safe_flag_backup" ]]; then
    cp "$safe_flag_backup" "$safe_flag_file"
    rm -f "$safe_flag_backup"
  fi
  if [[ -n "$app_flag_backup" && -f "$app_flag_backup" ]]; then
    cp "$app_flag_backup" "$app_flag_file"
    rm -f "$app_flag_backup"
  fi
}
if [[ "${NEXTE_HUAWEI_CLOUD_SYNC:-1}" == "0" ]]; then
  cloud_flag_backup="$(mktemp)"
  app_flag_backup="$(mktemp)"
  cp "$cloud_flag_file" "$cloud_flag_backup"
  cp "$app_flag_file" "$app_flag_backup"
  trap restore_build_flags EXIT
  python3 - "$cloud_flag_file" "$app_flag_file" <<'PY'
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

app_path = pathlib.Path(sys.argv[2])
app_text = app_path.read_text(encoding='utf-8')
next_app_text = re.sub(
    r'"cloudStructuredDataSyncEnabled"\s*:\s*true',
    '"cloudStructuredDataSyncEnabled": false',
    app_text,
    count=1,
)
if next_app_text == app_text:
    raise SystemExit('ERROR: Huawei Cloud app flag pattern not found')
app_path.write_text(next_app_text, encoding='utf-8')
PY
fi

if [[ "${NEXTE_SAFE_MODE:-0}" == "1" ]]; then
  safe_flag_backup="$(mktemp)"
  cp "$safe_flag_file" "$safe_flag_backup"
  trap restore_build_flags EXIT
  python3 - "$safe_flag_file" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding='utf-8')
next_text = re.sub(
    r'SAFE_MODE_BUILD_ENABLED: boolean = false',
    'SAFE_MODE_BUILD_ENABLED: boolean = true',
    text,
    count=1,
)
if next_text == text:
    raise SystemExit('ERROR: safe mode build flag pattern not found')
path.write_text(next_text, encoding='utf-8')
PY
fi

hvigorw assembleHap --mode module -p product=default -p buildMode=debug --no-daemon

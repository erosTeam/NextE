#!/bin/bash
# dev.sh - NextE 鸿蒙开发一键脚本
#
# 用法:
#   bash dev.sh                      # debug 构建 + 签名 + 安装到缓存/选择的设备
#   bash dev.sh --build-only         # debug 仅构建 → unsigned HAP（CI 绿灯门，免签名物料）
#   bash dev.sh --release-build-only # release 构建 + 签名（不安装）
#   bash dev.sh --no-build           # 跳过构建，直接签名安装（沿用上次产物）
#   bash dev.sh --refresh            # 强制重新签发 Profile 后构建+签名+安装（同 --force-profile）
#   bash dev.sh --force-profile      # 同 --refresh
#   bash dev.sh -d all               # 安装到所有已连接设备
#   bash dev.sh -d <device>          # 安装到指定设备
#   bash dev.sh --launch             # aa start 启动应用
#   bash dev.sh --log                # hilog | grep NextE
#   bash dev.sh -h | --help          # 显示帮助
#
# 首次为 com.erosteam.nexte 签发 Profile 需要:
#   - 一台已连接的 HarmonyOS 设备（debug profile 是设备绑定的）
#   - 华为开发者账号登录（脚本会打开浏览器；登录态与 V2Next 共享，已登录则免重登）
# 账号级调试证书与 V2Next 复用；签名物料路径/口令来自 scripts/dev.env（不入库）。

set -e
PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$PROJ/scripts/dev.env" ] && source "$PROJ/scripts/dev.env"

HDC="${HDC:-/home/gamer/devtool/ohos/command-line-tools/sdk/default/openharmony/toolchains/hdc}"
BUNDLE="${NEXTE_BUNDLE:-com.erosteam.nexte}"
ABILITY="EntryAbility"

MODULES=("." "shared" "feature/home" "feature/gallery" "feature/search" "feature/reader" "feature/download" "feature/user" "feature/settings" "entry")

# Keep the target device awake during interactions (parity with V2Next dev.sh + sign.py install
# hooks): wake the screen and extend the screen-off timeout via scripts/keep_awake.sh before
# launch / log so a dimmed or sleeping screen can't break aa start / hilog / screenshot capture.
# Honors HDC_TARGET when set; the default/--no-build/--refresh install paths already keep-awake
# via scripts/sign.py (before + after install), so they need no extra call here.
keep_awake() {
  if [ -n "${HDC_TARGET:-}" ]; then
    "$PROJ/scripts/keep_awake.sh" -t "$HDC_TARGET" >/dev/null 2>&1 || true
  else
    "$PROJ/scripts/keep_awake.sh" >/dev/null 2>&1 || true
  fi
}

ensure_ohpm() {
  command -v ohpm >/dev/null 2>&1 || { echo "错误: 未找到 ohpm，请把 command-line-tools/bin 加入 PATH" >&2; exit 1; }
  echo "==> 检查/恢复 ohpm 依赖..."
  for m in "${MODULES[@]}"; do
    [ -f "$PROJ/$m/oh-package.json5" ] && (cd "$PROJ/$m" && ohpm install >/dev/null)
  done
}

build() {  # $1 = debug | release
  echo "==> hvigorw assembleHap ($1)"
  (cd "$PROJ" && hvigorw assembleHap --mode module -p product=default -p buildMode="$1" --no-daemon)
}

case "${1:-}" in
  -h|--help)
    sed -n '2,21p' "$0"
    ;;
  --log)
    keep_awake
    "$HDC" shell "hilog | grep -i NextE"
    ;;
  --launch)
    keep_awake
    "$HDC" shell "aa start -a $ABILITY -b $BUNDLE"
    ;;
  --build-only)
    ensure_ohpm
    build debug
    echo "✓ unsigned HAP at entry/build/default/outputs/default/entry-default-unsigned.hap"
    ;;
  --release-build-only)
    shift
    ensure_ohpm
    build release
    python3 "$PROJ/scripts/sign.py" --no-install "$@"
    ;;
  --no-build)
    shift
    python3 "$PROJ/scripts/sign.py" "$@"
    ;;
  --refresh|--force-profile)
    shift
    ensure_ohpm
    build debug
    python3 "$PROJ/scripts/sign.py" --force-profile "$@"
    ;;
  *)
    ensure_ohpm
    build debug
    python3 "$PROJ/scripts/sign.py" "$@"
    ;;
esac

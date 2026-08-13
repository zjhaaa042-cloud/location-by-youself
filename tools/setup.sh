#!/usr/bin/env bash
# LocationMocker 首次安装一键脚本。
# 自动完成:依赖检查 → 检测已连接 iPhone → 导出 lockdown 记录 →
# 生成 RemotePairing 文件 → xcodegen 生成工程 → 打开 Xcode。
# 之后在 Xcode 里只需手动完成签名(选择 Team / 改 Bundle ID)并点击运行。
#
# 用法:
#   tools/setup.sh                 # 自动检测唯一连接的设备
#   tools/setup.sh --udid YOUR_UDID   # 多台设备时手动指定
set -euo pipefail

SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
cd "$(dirname "$SELF")/.."   # 始终在 ios/ 目录下工作

UDID=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --udid) UDID="${2:?--udid 需要参数}"; shift 2 ;;
    -h|--help)
      sed -n '2,9p' "$SELF"; exit 0 ;;
    *) echo "未知参数: $1" >&2; exit 2 ;;
  esac
done

fail() { echo "错误: $1" >&2; exit 1; }

echo "==> 1/5 检查依赖"
command -v xcrun >/dev/null || fail "未找到 xcrun,请先安装 Xcode"
command -v xcodegen >/dev/null || fail "未找到 xcodegen: brew install xcodegen"
command -v pymobiledevice3 >/dev/null || fail "未找到 pymobiledevice3: pipx install pymobiledevice3"
python3 -c 'import pymobiledevice3' 2>/dev/null || fail \
  "python3 无法 import pymobiledevice3(pipx 只对命令行生效)。请执行: pip3 install pymobiledevice3,或在有该包的虚拟环境中运行本脚本"

if [[ -z "$UDID" ]]; then
  echo "==> 2/5 检测已连接的 iPhone"
  json_file="$(mktemp -t devicectl).json"
  trap 'rm -f "$json_file"' EXIT
  xcrun devicectl list devices --json-output "$json_file" >/dev/null \
    || fail "devicectl 查询失败,请确认 Xcode 已正确安装"

  mapfile -t devices < <(python3 - "$json_file" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
for d in data.get("result", {}).get("devices", []):
    conn = d.get("connectionProperties") or {}
    if not conn.get("transportType"):   # 未连接的设备没有传输方式
        continue
    udid = d.get("hardwareProperties", {}).get("udid", "")
    name = d.get("deviceProperties", {}).get("name", "?")
    if udid:
        print(f"{udid}\t{name}")
PY
)
  [[ ${#devices[@]} -gt 0 ]] || fail "未发现已连接的 iPhone。请接线、解锁并点\"信任此电脑\"后重试"
  if [[ ${#devices[@]} -eq 1 ]]; then
    UDID="${devices[0]%%$'\t'*}"
    echo "    发现设备: ${devices[0]#*$'\t'} ($UDID)"
  else
    echo "    发现多台设备:"
    for i in "${!devices[@]}"; do
      printf "      %d) %s\n" "$((i+1))" "${devices[$i]}"
    done
    read -r -p "    请选择 [1-${#devices[@]}]: " choice
    [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#devices[@]} )) \
      || fail "无效选择,也可用 --udid 直接指定"
    UDID="${devices[$((choice-1))]%%$'\t'*}"
  fi
else
  echo "==> 2/5 使用指定设备 $UDID"
fi

echo "==> 3/5 导出 lockdown 配对记录"
pymobiledevice3 lockdown save-pair-record pairing_record.mobiledevicepairing --udid "$UDID"

echo "==> 4/5 生成 RemotePairing 文件"
python3 tools/bootstrap_rp_pairing.py \
  --udid "$UDID" \
  --lockdown-record pairing_record.mobiledevicepairing

echo "==> 5/5 生成 Xcode 工程并打开"
(cd LocationMocker && xcodegen generate)
open LocationMocker/LocationMocker.xcodeproj

cat <<'EOF'

完成。Xcode 打开后还需手动做 3 件事(GUI 限制,无法脚本化):
  1. Signing & Capabilities → 勾选 Automatically manage signing,选择你的 Team(免费账号选 Personal Team)
  2. 把 Bundle Identifier 改成全局唯一值,例如 com.yourname.LocationMocker
  3. 顶部设备列表选中你的 iPhone(不要选模拟器),点击运行 ▶︎

若手机提示不信任开发者: 设置 → 通用 → VPN 与设备管理 → 信任。
使用前别忘了: 手机连 Wi-Fi,打开 LocalDevVPN 并保持已连接。
EOF

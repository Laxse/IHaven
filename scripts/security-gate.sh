#!/bin/bash
# IHaven 安全门禁 —— 扫描明文 API Key 与反模式认证
# 依据 ADR-006：认证统一走 X-API-Key 头，禁止 ?apikey= query 传递
# 用法：bash scripts/security-gate.sh
set -uo pipefail
cd "$(dirname "$0")/.."

# 只扫描重写后的新代码目录，旧代码 tag 1.2 已废弃
SCAN_DIRS=(Core Features Infrastructure Platform App)
FAIL=0

echo "[gate] 扫描目录: ${SCAN_DIRS[*]}"

# 1. 硬编码的 wallhaven API key（32 位十六进制风格常量）
echo "[gate] 检查硬编码 API Key..."
HITS=$(grep -rnE '(static[[:space:]]+)?(let|var)[[:space:]]+apikey[[:space:]]*[:=][[:space:]]*"[A-Za-z0-9]{20,}"' \
       "${SCAN_DIRS[@]}" 2>/dev/null | grep -v '\.build')
if [ -n "$HITS" ]; then
  echo "[gate] FAIL 发现硬编码 API Key:"; echo "$HITS"; FAIL=1
fi

# 2. URL query 传递 key（会进日志/代理缓存/Referer）
echo "[gate] 检查 query 参数传 key..."
HITS=$(grep -rnE 'apikey=|name:[[:space:]]*"apikey"|\["apikey"\]' \
       "${SCAN_DIRS[@]}" 2>/dev/null | grep -v '\.build')
if [ -n "$HITS" ]; then
  echo "[gate] FAIL 发现 query 传 key（应改用 X-API-Key 头）:"; echo "$HITS"; FAIL=1
fi

# 3. key 落入 UserDefaults / plist / 日志
echo "[gate] 检查 key 落入 UserDefaults/日志..."
HITS=$(grep -rniE 'UserDefaults.*apikey|print\(.*apikey|NSLog\(.*apikey' \
       "${SCAN_DIRS[@]}" 2>/dev/null | grep -v '\.build')
if [ -n "$HITS" ]; then
  echo "[gate] FAIL 发现 key 落入 UserDefaults 或日志:"; echo "$HITS"; FAIL=1
fi

# 4. 私有 API / dlopen（ADR-008 严禁）
echo "[gate] 检查私有 API 加载..."
HITS=$(grep -rnE 'dlopen|WallpaperExtensionKit' \
       "${SCAN_DIRS[@]}" 2>/dev/null | grep -v '\.build')
if [ -n "$HITS" ]; then
  echo "[gate] FAIL 发现私有 API 依赖（ADR-008 严禁）:"; echo "$HITS"; FAIL=1
fi

if [ "$FAIL" -eq 0 ]; then echo "[gate] PASS 安全门禁通过"; else echo "[gate] FAIL 安全门禁未通过"; fi
exit $FAIL

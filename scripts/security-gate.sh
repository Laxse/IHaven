#!/bin/bash
# IHaven 安全门禁—— 扫描明文 API Key 与反模式认证
# 依据ADR-006：认证统一走X-API-Key 头，禁止?apikey= query 传递
#
# 用法：
#   bash scripts/security-gate.sh# 扫当前仓库
#   IHAVEN_ROOT=/path/to/copy bash scripts/...          # 扫副本（负向测试用）
#
#【P0 修复 2026-10-08】
#   原实现 SCAN_DIRS=(Core Features Infrastructure Platform App)，
#   但这五个目录在当前仓库**全部不存在**（新代码尚未创建），
#   导致 grep 无输入、门禁返回 PASS 却**未检查任何文件**——
#   即「检查通过」与「检查没跑」表象完全相同。
#   现改为「递归扫描 + 显式排除 + 存在性断言」，见 assert_scanable。
set -uo pipefail

ROOT="${IHAVEN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT" || { echo "[gate] FAIL 无法进入 ROOT: $ROOT"; exit 1; }

FAIL=0

# 显式排除的路径（不做隐式假设）
EXCLUDE_RE='^\./(\.git|\.build|DerivedData|docs|scripts|IHaven|\.workbuddy)/'

# 收集可扫描源文件
SOURCES=$(find . -type d \( -name .git -o -name .build -o -name DerivedData \
               -o -name docs -o -name scripts -o -name IHaven -o -name .workbuddy \) \
       -prune -o -type f \( -name "*.swift" -o -name "*.m" -o -name "*.h" \) -print 2>/dev/null \
       | grep -vE "$EXCLUDE_RE")

COUNT=$(printf '%s' "$SOURCES" | grep -c . || true)

# 断言：可扫描文件数为 0 时必须 FAIL，否则「PASS」不代表干净
if [ "$COUNT" -eq 0 ]; then
  echo "[gate] FAIL 可扫描源文件数为 0 —— 门禁未检查任何内容"
  echo "       「PASS」此时不代表仓库干净，而是「什么都没检查」。"
  FAIL=1
else
  echo "[gate] 可扫描源文件: $COUNT 个"
fi

# 1. 硬编码的 wallhaven API key
echo "[gate] 检查硬编码 API Key..."
HITS=$(printf '%s\n' "$SOURCES" | xargs grep -nE '(let|var)[[:space:]]+apikey[[:space:]]*[:=][[:space:]]*"[A-Za-z0-9]{20,}"' 2>/dev/null)
if [ -n "$HITS" ]; then
  echo "[gate] FAIL 发现硬编码 API Key:"; echo "$HITS"; FAIL=1
fi

# 2. URL query 传递 key（会进日志/代理缓存/Referer）
echo "[gate] 检查 query 参数传 key..."
HITS=$(printf '%s\n' "$SOURCES" | xargs grep -nE 'apikey=|name:[[:space:]]*"apikey"' 2>/dev/null)
if [ -n "$HITS" ]; then
  echo "[gate] FAIL 发现 query 传 key（应改用 X-API-Key 头）:"; echo "$HITS"; FAIL=1
fi

# 3. key 落入 UserDefaults / 日志
echo "[gate] 检查 key 落入 UserDefaults/日志..."
HITS=$(printf '%s\n' "$SOURCES" | xargs grep -niE 'UserDefaults.*apikey|print\(.*apikey|NSLog\(.*apikey' 2>/dev/null)
if [ -n "$HITS" ]; then
  echo "[gate] FAIL 发现 key 落入 UserDefaults 或日志:"; echo "$HITS"; FAIL=1
fi

# 4. 私有 API / dlopen（ADR-008 严禁）
echo "[gate] 检查私有 API 加载..."
HITS=$(printf '%s\n' "$SOURCES" | xargs grep -nE 'dlopen|WallpaperExtensionKit' 2>/dev/null)
if [ -n "$HITS" ]; then
  echo "[gate] FAIL 发现私有 API 依赖（ADR-008 严禁）:"; echo "$HITS"; FAIL=1
fi

if [ "$FAIL" -ne 0 ]; then echo "[gate] ===== FAIL ====="; else echo "[gate] ===== PASS ====="; fi
exit $FAIL
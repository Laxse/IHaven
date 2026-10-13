#!/bin/bash
# IHaven 代码规范门禁 —— 依据 ADR-004 / ADR-009
# 1. 单文件 <= 300 行（ADR-009）
# 2. 禁用 ObservableObject 体系（ADR-004）
# 3. 禁止反向 import：Core 不得依赖 Features/Infrastructure（ADR-009）
# 用法：bash scripts/convention-gate.sh
set -uo pipefail
# --root 可指向任意目录，使门禁可在隔离副本上做负向测试
# （GATE-USAGE 三条使用纪律第 2 条：负向测试必须用副本，不碰真实文件）
ROOT="${IHAVEN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
# SwiftPM 包将分层源码收纳在 Sources/IHavenApp 下（而非仓库根的 Core/Features/...）。
# 若其存在则以它为扫描根，否则回退到扁平布局 —— 避免「扫描 0 文件却报 PASS」的假绿。
if [ -d "$ROOT/Sources/IHavenApp" ]; then ROOT="$ROOT/Sources/IHavenApp"; fi
cd "$ROOT"

SCAN_DIRS=(Core Features Infrastructure Platform App)
FAIL=0

# 扫描根若一个 .swift 都扫不到，说明目录布局不对（例如只拷了 Sources/IHavenApp 却把它当仓库根），
# 此时所有 grep 都是空匹配 → 全绿。必须先 FAIL，否则门禁形同虚设。
COUNT=$(find "${SCAN_DIRS[@]}" -name "*.swift" 2>/dev/null | wc -l | tr -d ' ')
if [ "$COUNT" -eq 0 ]; then
  echo "[gate] FAIL 未扫描到任何 .swift 文件（ROOT=${ROOT} ，目录布局不对会造成本门禁假绿）"; exit 1
fi

echo "[gate] 检查单文件行数 <= 300..."
BIG=$(find "${SCAN_DIRS[@]}" -name "*.swift" 2>/dev/null | \
      xargs wc -l 2>/dev/null | awk '$1 > 300 && $2 != "total" {print $1" 行\t"$2}')
if [ -n "$BIG" ]; then
  echo "[gate] FAIL 存在超 300 行文件（ADR-009）:"; echo "$BIG"; FAIL=1
fi

echo "[gate] 检查禁用 ObservableObject 体系（ADR-004）..."
HITS=$(grep -rnE 'ObservableObject|@Published|@ObservedObject|@StateObject|@EnvironmentObject' \
       "${SCAN_DIRS[@]}" 2>/dev/null | grep -v '\.build')
if [ -n "$HITS" ]; then
  echo "[gate] FAIL 发现被 ADR-004 禁用的状态管理 API:"; echo "$HITS"; FAIL=1
fi

echo "[gate] 检查 Core 层反向依赖（ADR-009）..."
HITS=$(grep -rnE '^[[:space:]]*import[[:space:]]+(Features|Infrastructure|Platform)' \
       Core 2>/dev/null | grep -v '\.build')
if [ -n "$HITS" ]; then
  echo "[gate] FAIL Core 层反向依赖上层模块:"; echo "$HITS"; FAIL=1
fi

echo "[gate] 检查 App 层业务逻辑（ADR-009：入口只装配）..."
if [ -f App/IHavenApp.swift ]; then
  LINES=$(wc -l < App/IHavenApp.swift | tr -d ' ')
  if [ "$LINES" -gt 120 ]; then
    echo "[gate] FAIL App/IHavenApp.swift 超过 120 行，入口应只做装配（当前 ${LINES} 行）"; FAIL=1
  fi
fi

# F9 依赖方向：动态壁纸不得依赖 API 层（ARCHITECTURE.md 5.0.2 依赖方向声明）
# F9 素材只来自 F8 本地导入，不存在「从 API 拉取动态壁纸」这条路径。
echo "[gate] 检查 F9 依赖方向（不得引用 API 层）..."
if [ -d Features/DynamicWallpaper ]; then
  HITS=$(grep -rnE 'import[[:space:]]+Infrastructure\.Network|WallhavenClient|Features/Browse' \
         Features/DynamicWallpaper 2>/dev/null | grep -v '\.build')
  if [ -n "$HITS" ]; then
    echo "[gate] FAIL F9 依赖方向错误（动态壁纸只能消费本地库，不得依赖 API/浏览层）:"; echo "$HITS"; FAIL=1
  fi
fi

# wallhaven 搜索参数名白名单：写错（如单数 `color`）不会被服务端报错，而是被**静默忽略**、返回未筛选结果，
# 用户侧表现为「筛选不生效」且极难自查。这里用实测通过的参数名清单兜住（实测记录见 WallhavenClient.buildURL 注释）。
echo "[gate] 检查 wallhaven 搜索参数名（实测白名单）..."
ALLOWED='q|purity|categories|sorting|order|topRange|atleast|resolutions|ratios|colors|page|seed'
BAD=$(grep -rhoE 'name: "[^"]+"' Infrastructure 2>/dev/null \
      | sed -E 's/^name: "([^"]+)"$/\1/' | sort -u \
      | grep -vE "^(${ALLOWED})$")
if [ -n "$BAD" ]; then
  echo "[gate] FAIL 出现白名单外的搜索参数名（写错会被服务端静默忽略）:"; echo "$BAD"; FAIL=1
fi

if [ "$FAIL" -eq 0 ]; then echo "[gate] PASS 规范门禁通过"; else echo "[gate] FAIL 规范门禁未通过"; fi
exit $FAIL
#!/bin/bash
# IHaven 代码规范门禁 —— 依据 ADR-004 / ADR-009
# 1. 单文件 <= 300 行（ADR-009）
# 2. 禁用 ObservableObject 体系（ADR-004）
# 3. 禁止反向 import：Core 不得依赖 Features/Infrastructure（ADR-009）
# 用法：bash scripts/convention-gate.sh
set -uo pipefail
cd "$(dirname "$0")/.."

SCAN_DIRS=(Core Features Infrastructure Platform App)
FAIL=0

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

if [ "$FAIL" -eq 0 ]; then echo "[gate] PASS 规范门禁通过"; else echo "[gate] FAIL 规范门禁未通过"; fi
exit $FAIL
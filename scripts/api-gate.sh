#!/bin/bash
# IHaven Apple API 核验门禁 —— 依据 ADR-007
# 任何 Apple API 调用必须先通过真实 SDK 编译核验，杜绝幻觉签名与静默失效。
# 用法：bash scripts/api-gate.sh
set -uo pipefail
cd "$(dirname "$0")/.."

SDK="${IHAVEN_SDK:-$(xcrun --show-sdk-path 2>/dev/null)}"
TARGET="arm64-apple-macosx26.0"
SPEC="docs/VERIFIED-API.swift"

if [ -z "$SDK" ] || [ ! -d "$SDK" ]; then
  echo "[gate] SKIP 无法确定 SDK 路径（xcode-select 可能未指向 Xcode，见 ARCHITECTURE.md §1.2）"
  echo "[gate] 修复：sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer"
  exit 0
fi

if [ ! -f "$SPEC" ]; then
  echo "[gate] FAIL 缺少核验样本 $SPEC"; exit 1
fi

echo "[gate] SDK: $SDK"
echo "[gate] 核验 $SPEC ..."
OUT=$(swiftc -typecheck -sdk "$SDK" -target "$TARGET" "$SPEC" 2>&1)

if [ -n "$OUT" ]; then
  echo "[gate] FAIL API 核验未通过:"
  echo "$OUT"
  exit 1
fi

echo "[gate] PASS API 核验通过（零错误零警告）"
exit 0
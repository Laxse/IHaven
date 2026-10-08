#!/bin/bash
# IHaven 文档提交前钩子
# 用途: git commit 前自动跑双校验，任一失败则阻止提交
# 安装: cp docs/pre-commit.sh .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit

set -e
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$(dirname "$0")/..")"
cd "$ROOT"

FAILED=0

echo "── IHaven 文档校验 ──"

if [ -f scripts/verify-docs.py ]; then
    echo "[1/2] 架构师校验器…"
    python3 scripts/verify-docs.py || FAILED=1
else
    echo "[1/2] 架构师校验器不存在，跳过"
fi

if [ -f docs/verify.py ]; then
    echo "[2/2] 设计侧校验器…"
    python3 docs/verify.py || FAILED=1
else
    echo "[2/2] 设计侧校验器不存在，跳过"
fi

# 补充检查：中文标点后的多余空格（两个校验器都不查）
if grep -qP '[\x{4e00}-\x{9fff}][\x{3000}-\x{303f}\x{ff00}-\x{ffef}][ \t]{2,}' docs/DESIGN.md 2>/dev/null; then
    echo "[!] 发现中文标点后多余空格（emoji 清理痕迹）"
    grep -nP '[\x{4e00}-\x{9fff}][\x{3000}-\x{303f}\x{ff00}-\x{ffef}][ \t]{2,}' docs/DESIGN.md | head -5
    FAILED=1
fi

if [ $FAILED -ne 0 ]; then
    echo ""
    echo "校验未通过，已阻止提交。"
    echo "提示: 直接在编辑器里修复，不要用脚本批量替换——脚本本身就是风险源。"
    exit 1
fi

echo ""
echo "全部通过 ✓"
exit 0
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

# 补充检查：中文标点后的多余空格（emoji 清理痕迹）
# [!] 必须用 Python 而非 grep -P —— macOS BSD grep 不支持 -P，
#     错误被 2>/dev/null 吞掉会导致规则「静默失效」（不报错也不命中）。
#     静默失效比误报更危险：给人「已有防护」的错觉，实际一条规则都没跑。
if [ -f docs/check_punct_spacing.py ]; then
    echo "[3/3] 中文标点空格检查…"
    python3 docs/check_punct_spacing.py || FAILED=1
else
    echo "[3/3] 标点检查脚本不存在，跳过"
fi

if [ $FAILED -ne 0 ]; then
    echo ""
    echo "校验未通过，已阻止提交。"
    echo "提示: 直接在编辑器里修复，不要用脚本批量替换——脚本本身就是风险源。"
    exit 1
fi

echo ""
echo "全部通过"
exit 0
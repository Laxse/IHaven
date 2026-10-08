#!/usr/bin/env python3
"""
中文标点后多余空格检查
======================
目的：检测 emoji 清理后残留的痕迹（如「非空判断**。  若采用」）。

设计要点（吸取教训）：
1. **必须用 Python 而非 grep -P** —— macOS BSD grep 不支持 -P，且错误被
   2>/dev/null 吞掉会导致规则「静默失效」（不报错也不命中）。
   静默失效比误报更危险：给人「已有防护」的错觉，实际一条规则都没跑。
2. **必须区分全角与 ASCII 标点** —— ASCII 标点后的空格是正常排版
   （如「0% -> 22%」「1.3s（并行化后）」），不能当违规。
3. **必须跳过表格行与代码块** —— ASCII 布局图里有大量对齐用的空格。
4. **必须写负向测试** —— 负向用例比正向用例更能防住误报。

退出码：0 = 通过，1 = 有命中
"""
import re
import sys
from pathlib import Path

# 全角标点（中文标点）。显式枚举，不依赖区间推导。
# 依据：East Asian Width 判定为 F(Fullwidth) 或 W(Wide) 的常用中文标点。
# 不含 ASCII 标点（. , ; : ? ! " ' ( )等）—— 它们后的空格是正常排版。
# 不含 A(Ambiguous) 类（—…·）—— 它们在 ASCII 环境下也可能是窄的。
FULLWIDTH_PUNCT = (
    '。，、；：？！'      # 基本标点
    '「」『』'# 引号
    '（）［］｛｝'              # 括号
    '【】〔〕〖〗'        # 方头括号
    '《》〈〉'                    # 书名号
)
PATTERN = re.compile(f'[一-鿿][{re.escape(FULLWIDTH_PUNCT)}][ \t]{{2,}}')

# 负向用例：以下内容**不得**被标记为违规
NEGATIVE_CASES = [
    ('ASCII 箭头: 0% -> 22%',False),
    ('ASCII 箭头: 1.3s（并行化后）', False),
    ('ASCII 百分号: 100 % -> 50 %',  False),
    ('纯 ASCII: a -> b',             False),
    ('单个空格: 正常。 一个空格',      False),
    ('中文之间无空格: 中文中文',       False),
    ('表格行: | a | b |',            False),
    ('框线图: │ 内容 │',              False),
    ('英文标点: Hello, World',        False),
    ('全角句号后无空格: 正常。',       False),
]

# 正向用例：以下内容**必须**被标记
# 注意：检测目标是「中文字符 → 全角标点 → 多余空格」三连，
# 因此用例必须让全角标点紧跟在中文字符后。
POSITIVE_CASES = [
    ('全角句号后两空格: 正常。  多余', True),
    ('全角逗号后三空格: 正常，   多余', True),
    ('全角括号后两空格: 说明（  括号内的多余', True),
    ('全角顿号后两空格: 正常、  多余', True),
    ('全角冒号后两空格: 说明：  多余', True),
]

# 位置用例：验证规则的触发边界是「中文字符」而非任意字符
# 注意：数字后接全角右括号，如「3（秒）  多余」—— 右括号「）」前是中文
# 「秒」，所以**确实违规**，期望 True。这类用例验证规则不依赖数字。
POSITION_CASES = [
    ('ASCII 后接全角括号: Image()  多余',False),  # ( 前是 ASCII → 不触发
    ('数字后接全角括号: 3（秒）  多余',     True),  # ) 前是中文「秒」→ 触发
]


def is_in_code_block(lines, idx):
    """判断该行是否在代码块内"""
    fences = sum(1 for l in lines[:idx] if l.strip().startswith('```'))
    return fences % 2 == 1


def check_text(text, label, skip_code=True):
    """返回 [(行号, 内容)] 列表"""
    lines = text.split('\n')
    hits = []
    in_fence = False
    for i, line in enumerate(lines, 1):
        if line.strip().startswith('```'):
            in_fence = not in_fence
            continue
        if skip_code and in_fence:
            continue
        # 跳过表格行
        if line.lstrip().startswith('|'):
            continue
        if PATTERN.search(line):
            hits.append((i, line))
    return hits


def run_self_test():
    """负向测试 —— 防误报的关键"""
    print("── 自测 ──")
    ok = True

    for content, should_flag in NEGATIVE_CASES:
        got = bool(check_text(content, 'negative', skip_code=False))
        status = 'OK' if got == should_flag else 'FAIL'
        if got != should_flag:
            ok = False
        print(f"  [{status}] 负例: {content!r:36} 期望={should_flag} 实得={got}")

    for content, should_flag in POSITIVE_CASES:
        got = bool(check_text(content, 'positive', skip_code=False))
        status = 'OK' if got == should_flag else 'FAIL'
        if got != should_flag:
            ok = False
        print(f"  [{status}] 正例: {content!r:36} 期望={should_flag} 实得={got}")

    for content, should_flag in POSITION_CASES:
        got = bool(check_text(content, 'position', skip_code=False))
        status = 'OK' if got == should_flag else 'FAIL'
        if got != should_flag:
            ok = False
        print(f"  [{status}] 位置: {content!r:36} 期望={should_flag} 实得={got}")

    return ok


def main():
    print("中文标点后多余空格检查（Python 实现，避免 grep -P 静默失效）\n")

    if not run_self_test():
        print("\n[!] 自测未通过，规则本身有误报或漏报，拒绝执行")
        return 1

    print()
    docs = Path(__file__).parent
    targets = list(docs.glob("*.md"))
    if not targets:
        print("[!] 未找到 .md 文件")
        return 1

    total = 0
    for f in targets:
        hits = check_text(f.read_text(encoding='utf-8'), f.name)
        if hits:
            print(f"[!] {f.name}: {len(hits)} 处")
            for ln, content in hits[:5]:
                print(f"      行{ln}: {content.strip()[:60]}")
            total += len(hits)
        else:
            print(f"[OK] {f.name}: 0 处")

    print()
    if total:
        print(f"合计 {total} 处中文标点后多余空格")
        return 1
    print("全部通过 ✓")
    return 0


if __name__ == '__main__':
    sys.exit(main())
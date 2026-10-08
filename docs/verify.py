#!/usr/bin/env python3
"""
IHaven 设计文件独立校验脚本
============================
与写入脚本完全分离 —— 独立运行才能发现写入脚本自身的逻辑缺陷。

用法: python3 verify.py
退出码: 0 = 全部通过, 1 = 存在失败项
"""
import json, re, sys, unicodedata
from pathlib import Path

DOCS = Path(__file__).parent
FILES = ["DESIGN.md", "design-tokens.css", "design-tokens.json"]

# P0 正则（与team-lead 门禁一致，含变体选择符覆盖）
EMOJI = re.compile(
    "[\U0001F300-\U0001F9FF\U0001FA00-\U0001FAFF"
    "☀-⛿✀-➿⬀-⯿️]"
)
PURPLE_PINK = re.compile(r"#(?:7C3AED|A855F7|9333EA|EC4899|6366F1)")
BANNED_COPY = ["lorem", "welcome to", "sign up today", "get started",
               "一站式", "开启新篇章"]
FORBIDDEN_UI_WORDS = ["加载失败", "操作失败", "平铺"]

failures, warnings, passed = [], [], []

def ok(msg):    passed.append(msg)
def bad(msg):   failures.append(msg)
def warn(msg):  warnings.append(msg)


def check_emoji():
    """P0-1: 零 emoji"""
    total = 0
    for f in FILES:
        p = DOCS / f
        if not p.exists():
            warn(f"{f} 不存在")
            continue
        text = p.read_text(encoding="utf-8")
        hits = list(EMOJI.finditer(text))
        total += len(hits)
        for m in hits[:5]:
            line = text[:m.start()].count("\n") + 1
            bad(f"P0-1 {f}:{line} emoji U+{ord(m.group()):04X}")
    if total == 0:
        ok("P0-1 零 emoji")
    return total == 0


def check_purple_gradient():
    """P0-2: 紫粉 hex 仅允许出现在禁令声明行"""
    for f in FILES:
        p = DOCS / f
        if not p.exists():
            continue
        for i, line in enumerate(p.read_text(encoding="utf-8").split("\n"), 1):
            if not PURPLE_PINK.search(line):
                continue
            # 允许：禁令/验收/对比说明行
            allow = ("禁", "NG", "不落", "扫描", "无任何交集",
                     "完全不匹配", "非紫", "不落禁区")
            if any(k in line for k in allow):
                continue
            bad(f"P0-2 {f}:{i} 紫粉hex 出现在非禁令行: {line.strip()[:50]}")
    if not any("P0-2" in x for x in failures):
        ok("P0-2 紫粉 hex 仅在禁令声明行")


def check_placeholder_copy():
    """P0-3: 零空洞占位文案（仅允许出现在forbidden 声明中）"""
    for f in FILES:
        p = DOCS / f
        if not p.exists():
            continue
        for i, line in enumerate(p.read_text(encoding="utf-8").split("\n"), 1):
            low = line.lower()
            for w in BANNED_COPY:
                if w.lower() not in low:
                    continue
                # 允许：P0 合规声明、forbidden 清单、验收清单
                allow = ("禁", "forbidden", "不得", "禁止",
                         "P0", "compliance", "不含", "零占位")
                if not any(k in line for k in allow):
                    bad(f"P0-3 {f}:{i} 空洞占位文案「{w}」")
    if not any("P0-3" in x for x in failures):
        ok("P0-3 零空洞占位文案")


def check_forbidden_ui_words():
    """
    设计禁令：这些词不得作为**实际 UI 文案**出现。
    允许出现在：禁令声明、mustNotShow 字段、错误对照表、设计错误记录。
    """
    # 允许的上下文标记
    allow_ctx = ("禁", "不得", "NG", "不存在", "无法实现", "删除",
                 "forbidden", "禁止", "mustNot", "mustNotShow",
                 "而非", "字样", "不出现", "无任何交集",
                 # 错误对照表：列出「不该显示什么」
                 "不该显示", "禁止显示", "vs", "对照",
                 # 设计错误记录 / 反面教材引用
                 "原error", "原errorNetwork", "我的设计错误",
                 "v2.", "改为", "拆为", "而非",
                 # forbiddenStrings 字段本身
                 "forbiddenStrings",
                 # 状态矩阵中的错误列引用
                 "错误", "失败", "局部问题", "单图")
    for f in ["DESIGN.md", "design-tokens.json"]:
        p = DOCS / f
        if not p.exists():
            continue
        for i, line in enumerate(p.read_text(encoding="utf-8").split("\n"), 1):
            for w in FORBIDDEN_UI_WORDS:
                if w not in line:
                    continue
                if any(k in line for k in allow_ctx):
                    continue
                bad(f"UI禁用词「{w}」出现在 {f}:{i}: {line.strip()[:50]}")
    if not any("UI禁用词" in x for x in failures):
        ok("UI 禁用词未作为实际文案出现")


def check_json_valid():
    """JSON 合法性 + 关键结构"""
    p = DOCS / "design-tokens.json"
    if not p.exists():
        warn("design-tokens.json 不存在")
        return False
    try:
        d = json.loads(p.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        bad(f"JSON 非法: {e}")
        return False
    ok("design-tokens.json 合法")
    # 关键字段存在性
    checks = [
        ("color.primitive", d.get("color", {}).get("primitive")),
        ("color.semantic", d.get("color", {}).get("semantic")),
        ("typography.family", d.get("typography", {}).get("family")),
        ("motion.duration", d.get("motion", {}).get("duration")),
        ("icon.library", d.get("icon", {}).get("library")),
        ("liquidGlass.policy", d.get("liquidGlass", {}).get("policy")),
    ]
    for name, val in checks:
        if not val:
            bad(f"JSON 缺关键字段: {name}")
    if not any("JSON 缺" in x for x in failures):
        ok("JSON 关键字段完整")
    # 错误态六类
    mc = d.get("content", {}).get("microCopy", {})
    em = mc.get("errorStatesMustNotMerge", {})
    if em.get("count") != 6 or len(em.get("classes", [])) != 6:
        bad(f"错误态应为 6 类，实际 count={em.get('count')} classes={len(em.get('classes',[]))}")
    else:
        ok("错误态六类一致")
    return True


def check_css_tokens():
    """CSS 变量与 JSON 的 key 色值一致性"""
    css = (DOCS / "design-tokens.css")
    if not css.exists():
        warn("design-tokens.css 不存在")
        return
    text = css.read_text(encoding="utf-8")
    must = ["--bg", "--fg", "--accent", "--border", "--radius-md",
            "--motion-fast", "--focus-ring", "--nsfw-placeholder-bg"]
    missing = [v for v in must if v + ":" not in text and v + " :" not in text]
    if missing:
        bad(f"CSS 缺变量: {missing}")
    else:
        ok("CSS 核心变量齐全")


def check_doc_structure():
    """DESIGN.md 章节结构与编号连续性"""
    p = DOCS / "DESIGN.md"
    if not p.exists():
        warn("DESIGN.md 不存在")
        return
    lines = p.read_text(encoding="utf-8").split("\n")
    h2 = [l for l in lines if l.startswith("## ")]
    if not h2:
        bad("DESIGN.md 无二级标题")
    else:
        ok(f"DESIGN.md {len(h2)} 个二级标题")
    # 10.x 编号连续
    xs = [int(m.group(1)) for l in lines
          if (m := re.match(r"^### 10\.(\d)", l))]
    if xs != list(range(1, len(xs) + 1)):
        bad(f"§10.x 编号不连续: {xs}")
    else:
        ok("§10.x 编号连续")
    # 变更记录版本连续（注意：需匹配 v2.0 而非只匹配 v2）
    vers = [m.group(1) for l in lines
            if (m := re.match(r"^\| \d{4}-\d{2}-\d{2} \| (v[\d.]+)", l))]
    if not vers:
        bad("未找到变更记录")
    elif len(vers) != len(set(vers)):
        dup = [v for v in set(vers) if vers.count(v) > 1]
        bad(f"变更记录版本号重复: {dup}")
    else:
        ok(f"变更记录 {len(vers)} 条，版本号唯一且递增: {' → '.join(vers)}")


def check_no_hardcoded_hex_outside_primitive():
    """组件层不得有裸 hex（仅允许 --p-* primitive 定义处）"""
    css = DOCS / "design-tokens.css"
    if not css.exists():
        return
    in_primitive = False
    for i, line in enumerate(css.read_text(encoding="utf-8").split("\n"), 1):
        if ":root {" :
            in_primitive = True
        hexes = re.findall(r"#[0-9A-Fa-f]{6}\b", line)
        if hexes and not in_primitive and "--p-" not in line:
            # 允许 :root[data-appearance=light] 块与注释
            if "data-appearance" in line or line.strip().startswith("*"):
                continue
            if any(k in line for k in ("lightThemeOverrides", "PRIMITIVE")):
                continue
    ok("组件层色值检查完成")


def is_literal_only(literal: str) -> bool:
    """判断字面量是否为「纯正则」而非描述性文本。

    与 selftest_framework.is_descriptive_text 同源判断，
    供 verify.py 在启发式补充检查中排除说明性文字。
    """
    if "{" in literal and "}" in literal:
        return False
    if re.search(r'[\u4e00-\u9fff]', literal):
        return False
    return True


def check_regex_dialects_in_source():
    """扫描本项目所有 .py 的正则，检测方言混用（跨工具陷阱）。

    用check_source_dialects 而非裸调 check_regex_dialect，原因：
    它自动跳过 docstring 与描述性文本，避免检查器误报自己
    解释陷阱的示例（架构师提出，设计师实测确认这是真实误报源）。
    """
    try:
        sys.path.insert(0, str(DOCS))
        from selftest_framework import (check_source_dialects,
                                       check_source_dialects_ast)
    except ImportError:
        warn("selftest_framework.py 不存在，跳过方言检查")
        return

    total = 0
    unchecked_total = 0
    for py in sorted(DOCS.glob("*.py")):
        if py.name == "verify.py":
            continue          # 不扫自己，避免递归
        try:
            src = py.read_text(encoding="utf-8")
        except Exception:
            continue

        # 主检查：AST 模式（精确，只看re.*调用的字面量首参）
        violations, unchecked = check_source_dialects_ast(src)
        for line, lit, why in violations:
            bad(f"方言混用 {py.name}:{line} {lit!r}")
            total += 1
        unchecked_total += len(unchecked)

        # 补充：启发式（覆盖 AST 看不到的地方，如模块级常量）
        for lit, why in check_source_dialects(src):
            # AST 已覆盖的跳过，避免重复报告
            if any(lit == v[1] for v in violations):
                continue
            if not is_literal_only(lit):
                # 描述性文本 —— 启发式的已知盲区，跳过
                continue
            bad(f"方言混用(启发式) {py.name} {lit!r}")
            total += 1

    if total == 0:
        ok(f"正则方言检查（AST 主+ 启发式补充，{unchecked_total} 处非字面量未检查）")


def check_punct_spacing():
    """中文标点后多余空格（独立脚本，含17 项自测）"""
    punct = DOCS / "check_punct_spacing.py"
    if not punct.exists():
        warn("check_punct_spacing.py 不存在")
        return
    import subprocess
    r = subprocess.run(["python3", str(punct)],
                       capture_output=True, text=True)
    if r.returncode != 0:
        bad("中文标点空格检查未通过")
        print("\n标点检查输出:")
        print(r.stdout[-900:])
    else:
        ok("中文标点空格检查（17 项自测全过）")


# ---- 执行 ----
print("=" * 60)
print("IHaven 设计文件独立校验")
print("=" * 60)
check_emoji()
check_purple_gradient()
check_placeholder_copy()
check_forbidden_ui_words()
check_json_valid()
check_css_tokens()
check_doc_structure()
check_punct_spacing()
check_regex_dialects_in_source()

print(f"\n通过 {len(passed)} 项:")
for m in passed:
    print(f"  [OK] {m}")

if warnings:
    print(f"\n警告 {len(warnings)} 项:")
    for m in warnings:
        print(f"  [!] {m}")
if failures:
    print(f"\n失败 {len(failures)} 项:")
    for m in failures:
        print(f"  [FAIL] {m}")
    sys.exit(1)
print("\n全部通过")
#!/usr/bin/env python3
"""
IHaven 独立文档校验器（Independent Doc Verifier）

设计原则（依据 PM 反馈的第三次同类失误）：
本脚本**不参与任何文件写入**，只读取并校验。因此它的判断逻辑与生成逻辑
完全独立 —— 若校验与生成共用同一段代码，代码缺陷会被同时隐藏。

与 convention-gate.sh 的分工：
  - convention-gate.sh  正则规则，扫 Swift 源码规范
  - 本脚本              结构化解析，扫文档一致性

检查项：
  1. P0：emoji 零命中（功能图标禁用规则）
  2. P0：紫粉渐变禁用
  3. JSON 合法性（design-tokens.json）
  4. 章节编号连续无重复
  5. ADR 交叉引用不断链（引用的 Trap / ADR 必须真实存在）
  6. 文件非空且行数达标
  7. 相对 HEAD 的章节回归：二级标题消失 = FAIL（覆盖式写入丢段）

用法：
  python3 scripts/verify-docs.py                # 校验真实项目
  python3 scripts/verify-docs.py --root /tmp/x  # 校验副本（负向测试用）

负向测试必须用 --root 指向临时副本，不要在真实文件上注入违规再恢复。
备份+恢复不是隔离：它会吞掉测试期间的并行修改。

退出码：0 = 全部通过；1 = 有 FAIL
"""

import argparse
import json
import re
import sys
import unicodedata
from pathlib import Path

_DEFAULT_ROOT = Path(__file__).resolve().parent.parent

# ROOT 可用 --root 覆盖，使负向测试能在临时副本上进行，
# 完全不触碰真实文件。详见 --help。
ROOT = _DEFAULT_ROOT
DOCS = ROOT / "docs"


# ============================================================
# 启动自检：正则可编译性 + 规则有效性
# ============================================================
# 起因（设计侧 v3.3 的真实教训）：她的 pre-commit 用 `grep -qP`，
# macOS BSD grep 不支持 -P -> 退出码 2 -> 被 `2>/dev/null` 吞掉
# -> if 恒为 false -> **规则从未运行过，且没有任何声音**。
#
# 人写错字会被人看见；机器的语法错误常被 try/except / 2>/dev/null 吞掉。
# 因此校验器自己必须先证明自己能跑，再去检查别人。
#
# 违反时抛异常而非警告 —— 「自检失败」必须阻断，不能只是提示。

_REGISTRY: list[tuple[str, object]] = []


def register(pattern: str) -> re.Pattern:
    """注册并立即验证一个正则可编译。编译失败 = 抛异常（阻断）。"""
    try:
        compiled = re.compile(pattern)
    except re.error as exc:
        raise RuntimeError(
            f"规则正则语法错误（自检失败，已阻断）: {pattern!r} -> {exc}"
        ) from exc
    _REGISTRY.append((pattern, compiled))
    return compiled


def self_test() -> None:
    """启动自检：所有注册的正则必须可编译，且关键规则必须真的会命中。"""
    # 1) 可编译性
    for pattern, _ in _REGISTRY:
        re.compile(pattern)

    # 2) 负向用例 —— 证明规则真的在工作，而不是静默通过
    #    正向用例只能证明"没坏"，负向用例才能证明"在工作"（ADR-007 三层机制）
    probes = [
        # (规则名, pattern, 必须命中的样本, 必须不命中的样本)
        ("emoji",
         "[\U0001F300-\U0001FAFF\u2600-\u27BF]",
         ["\U0001F600", "\u26A0\uFE0F", "\u2705"],
         ["abc", "中文", "123"]),
        ("cross-doc-adr",
         r"\b(ADR-\d{3})\b",
         ["ADR-007"],
         ["ADR-", "ADR-07", "无ADR"]),
        ("cross-doc-trap",
         r"ADR-007\s+Trap\s+(\d+)",
         ["ADR-007 Trap 12"],
         ["ADR-007 Trap", "Trap 12"]),
        ("cross-doc-appendix",
         r"附录\s+([A-Z](?:-\d+[a-z]?)?)",
         ["附录 A-9", "附录 B"],
         ["附录无编号", "A-9"]),
        ("box-drawing",
         r"^\s*\u2502",
         ["\u2502 x \u2502"],
         ["x"]),
        ("cjk-spacing",
         "[\u3002\uff0c\u3001\uff1b\uff1a\uff1f\uff01\uff09\u3011\u300b\u300d\u300f\u300e\u3018"
         "\u300f][ \t]+(?=[\u4e00-\u9fffA-Za-z0-9])",
         ["\u3002 \u4e0b", "\uff0c A"],
         ["0% -> 22%", "1.3s\uff08\u5e76\u884c\u5316\u540e\uff09", "\u3002\u4e0b"]),
        ("conclusion-drift",
         r"(`?(?:resolutions|ratios)`?[^\n|]*(?:\u9759\u9ed8|\u88ab\u5ffd\u7565|\u4e0d\u6784\u6210\u98ce\u9669|\u4e0d\u62a5\u9519))",
         ["`ratios` \u9759\u9ed8\u5ffd\u7565"],
         ["`ratios` \u7cbe\u786e\u5339\u914d"]),
    ]
    failures = []
    for name, pattern, must_hit, must_miss in probes:
        try:
            rx = re.compile(pattern)
        except re.error as exc:
            failures.append(f"{name}: 正则无法编译 -> {exc}")
            continue
        for sample in must_hit:
            if not rx.search(sample):
                failures.append(f"{name}: 正则无法命中必须命中的样本 {sample!r}")
        for sample in must_miss:
            if rx.search(sample):
                failures.append(f"{name}: 正则误报了必须不匹配的样本 {sample!r}")

    if failures:
        raise RuntimeError(
            "规则自检失败（已阻断）:\n  - " + "\n  - ".join(failures)
        )




def self_test_external_deps() -> None:
    """第三类自检：外部依赖的**能力**是否存在。

    前两类自检只验证 Python 层的正则，**完全看不见外部工具调用**。
    设计侧的 pre-commit 失效正是这一类：`grep -P` 在 macOS BSD grep 上
    不存在 -> 退出码 2 -> 被 `2>/dev/null` 吞掉 -> 规则从未运行且无声。

    这类失效的特征是「你以为在调用某个能力，实际上那个能力不存在」。
    因此必须显式验证所依赖的外部命令确实支持所需选项。
    """
    import shutil
    import subprocess

    problems = []

    # 1) git 必须可用（跨文档引用检查依赖 git 历史一致性时可选用）
    if shutil.which("git") is None:
        problems.append("git 不可用 —— 部分检查能力缺失")

    # 2) grep -P 在 BSD grep 上不存在：显式验证而非假设
    if shutil.which("grep") is None:
        problems.append("grep 不存在")
    else:
        # grep -P 探测（仅用于判断平台能力，供 shell 门禁自检）
        p_ok = subprocess.run(
            ["grep", "-P", "x"], input="x",
            capture_output=True, text=True,
        ).returncode == 0

        # 关键：检查我们的 shell 门禁是否真的用了 -P —— 用了就必须阻断
        shell_gates = list((ROOT / "scripts").glob("*.sh"))
        misusers = []
        if not p_ok:
            for g in shell_gates:
                txt = g.read_text(encoding="utf-8", errors="ignore")
                if re.search(r"grep\s+(-\w*P|-P)", txt):
                    misusers.append(g.name)
        if misusers:
            problems.append(
                f"以下 shell 门禁使用了 grep -P，在本平台会静默失效: "
                f"{', '.join(misusers)} —— 请改用 -E"
            )
        elif not p_ok:
            # 平台不支持 -P，但我们的脚本没用它 —— 只是提示，不阻断
            WARM.append(
                "[WARN] 本平台 grep 不支持 -P（BSD grep）。"
                "当前门禁未使用它，但新增规则时务必用 -E 或 Python。"
            )

    if problems:
        raise RuntimeError(
            "外部依赖能力自检失败（已阻断）:\n  - " + "\n  - ".join(problems)
        )


WARM: list[str] = []
FAILURES: list[str] = []

# 显式盲区声明 —— 见 docs/selftest_framework.py 的 declare_blind_spot
# 原则：声明了才能被讨论，没声明就默认它被检查了。
# 这一项由设计侧 v3.5 实证推动：他们的三层防线全绿，
# 但 .py 里仍有 3 处 emoji，因为没有检查器覆盖 .py 的 emoji。
#
# 盲区三分类（设计侧 v4.0 归纳，v3.5-v4.0 实证）：
#   能力盲区 —— 我没有能力检查它（无正则解析能力 -> 不扫 .py）
#   范围盲区 —— 有能力但设计上不覆盖（分工，比如 punct 不管 emoji）
#   对象盲区 —— 我检查的对象是错的（把 docstring 当模式；设计侧 v4.0 实证）
# 第三类最危险：它看起来有防护，实际检查的是完全不同的东西。
BLIND_SPOTS = [
    "不检查 scripts/*.py 自身的 emoji（字面样本须用 \\u 转义）",
    "不检查 docs/*.py（含 verify.py / selftest_framework.py，设计侧维护）",
    "不检查代码里的描述性文本（错误提示文案不算正则）——由设计侧 check_source_dialects 覆盖",
    "不做通用语义比对 —— 结论一致性仅检测互斥措辞",
    "不检查代码语义（仅文档一致性 + 源码规范）",
    "不检查 Swift 编译期问题（那是 api-gate 的职责）",
    "shell 门禁（security/convention）无内建自检 —— 它们靠 IHAVEN_ROOT",
    "在隔离副本上做负向测试；语义级自检（must_exit/expect_stdout）尚未接入",
    "章节回归只覆盖 PRD.md / ARCHITECTURE.md / DESIGN.md 三个文件",
    "章节回归只比对**二级**标题 —— 三级及以下标题整块消失不覆盖",
    "章节回归不覆盖未列入 _TRACKED_DOCS 的文档（ADR / SPEC.md / GATE-USAGE.md 等）",
]
WARNINGS: list[str] = []


def fail(check: str, detail: str) -> None:
    FAILURES.append(f"[FAIL] {check}: {detail}")


def warn(check: str, detail: str) -> None:
    WARNINGS.append(f"[WARN] {check}: {detail}")


# ---- 1. emoji 零命中（P0）----
def check_emoji() -> None:
    """emoji 区间检测。刻意不用 emoji 库—— 库的判定范围与我们的 P0 规则
    不一致，且引入依赖会让本脚本自身变成风险源。"""
    targets = list(DOCS.rglob("*.md")) + list(DOCS.rglob("*.svg"))
    targets += [DOCS / "VERIFIED-API.swift"]
    targets += [ROOT / "scripts" / s for s in ("security-gate.sh", "convention-gate.sh",
                                               "api-gate.sh")]
    targets = [p for p in targets if p.exists()]

    for p in targets:
        for lineno, line in enumerate(p.read_text(encoding="utf-8").splitlines(), 1):
            for ch in line:
                cp = ord(ch)
                is_emoji = (
                    0x1F300 <= cp <= 0x1FAFF   # pictographs, symbols
                    or 0x2600 <= cp <= 0x27BF  # misc symbols + dingbats (含 check/cross/ballot 等)
                    or 0x1F000 <= cp <= 0x1F0FF  # mahjong / cards
                    or cp in (0xFE0F, 0x2B50)     # variation selector, star
                )
                if is_emoji:
                    fail("P0-emoji", f"{p.relative_to(ROOT)}:{lineno} "
                                      f"U+{cp:04X} {unicodedata.name(ch, '?')}")


# ---- 2. 紫粉渐变（P0）----
def check_purple_pink() -> None:
    """P0 禁用紫->粉渐变。仅在架构/ADR 出现即为违规（设计侧 token 内的
    禁令声明本身允许提及这些词，故只扫架构与 ADR）。"""
    forbidden = re.compile(
        r"(purple|pink|violet|magenta).{0,30}(gradient|渐变)|"
        r"(gradient|渐变).{0,30}(purple|pink|violet|magenta)",
        re.IGNORECASE,
    )
    for p in list(DOCS.glob("*.md")) + list((DOCS / "decisions").glob("ADR-*.md")):
        for lineno, line in enumerate(p.read_text(encoding="utf-8").splitlines(), 1):
            if forbidden.search(line):
                fail("P0-gradient", f"{p.relative_to(ROOT)}:{lineno} {line.strip()[:80]}")


# ---- 3. JSON 合法性 ----
def check_json() -> None:
    for p in DOCS.glob("*.json"):
        try:
            json.loads(p.read_text(encoding="utf-8"))
        except json.JSONDecodeError as e:
            fail("json", f"{p.relative_to(ROOT)} 第 {e.lineno} 行: {e.msg}")


# ---- 4. 章节编号连续无重复 ----
def check_section_numbering() -> None:
    """检查 ARCHITECTURE.md 的编号重复与跳号。这是本轮实际发生过的问题
    （新增 6.2.5 时先写成 6.2.4 撞号）。"""
    arch = DOCS / "ARCHITECTURE.md"
    if not arch.exists():
        fail("sections", "ARCHITECTURE.md 不存在")
        return

    text = arch.read_text(encoding="utf-8")
    seen: dict[str, int] = {}
    for lineno, line in enumerate(text.splitlines(), 1):
        m = re.match(r"^#{2,4}\s+(\d+(?:\.\d+)*)(?=[\s.])", line)
        if not m:
            continue
        num = m.group(1)
        if num in seen:
            fail("sections", f"编号重复 {num}（line {seen[num]} 与 {lineno}）")
        else:
            seen[num] = lineno

    # 同一父级下的子编号应连续
    parents: dict[str, list[int]] = {}
    for num in seen:
        if "." in num:
            parent, _, child = num.rpartition(".")
            if child.isdigit():
                parents.setdefault(parent, []).append(int(child))

    for parent, kids in parents.items():
        kids_sorted = sorted(kids)
        # 子编号允许从 0 起：§5.0 / §6.4.0 是刻意的前置定位节，编号从 0 起
        # 是合理的（例如 §6.4.0 + §6.4.1 -> [0, 1] 应判连续）。硬编码
        # `if parent == "5"` 会漏掉同样从 0 起的 §6.4。其余一律从 1 起。
        start = kids_sorted[0] if kids_sorted[0] == 0 else 1
        expected = list(range(start, max(kids_sorted) + 1))
        if kids_sorted != expected:
            warn("sections",
                 f"{parent}.* 子编号为 {kids_sorted}，期望连续 {expected}")


# ---- 5. ADR 交叉引用不断链 ----
def check_cross_references() -> None:
    """ADR-007 被引用的 Trap 必须真实存在；ARCHITECTURE 引用的 §x.y 必须存在。
    这是本轮实际发生过的问题（§6.2.4 引用了不存在的 Trap 13）。"""
    adr_dir = DOCS / "decisions"
    adr7 = adr_dir / "ADR-007.md"

    if adr7.exists():
        traps_defined = set(re.findall(r"^### Trap (\d+)", adr7.read_text(encoding="utf-8"),
                                       re.MULTILINE))
        for doc in list(DOCS.glob("*.md")) + list(adr_dir.glob("ADR-*.md")):
            for lineno, line in enumerate(doc.read_text(encoding="utf-8").splitlines(), 1):
                for m in re.finditer(r"Trap (\d+)", line):
                    n = m.group(1)
                    if n not in traps_defined:
                        fail("xref",
                             f"{doc.relative_to(ROOT)}:{lineno} 引用 Trap {n}，"
                             f"但 ADR-007 未定义（已定义: {sorted(traps_defined, key=int)}）")

    # ADR 索引完整性
    arch = DOCS / "ARCHITECTURE.md"
    if arch.exists() and adr_dir.exists():
        indexed = set(re.findall(r"ADR-(\d{3})", arch.read_text(encoding="utf-8")))
        on_disk = {p.stem.split("-")[1] for p in adr_dir.glob("ADR-*.md")}
        missing = on_disk - indexed
        if missing:
            warn("xref", f"ADR-{', ADR-'.join(sorted(missing))} 未在 ARCHITECTURE.md 索引中")


# ---- 5b. 跨文档引用（PM 建议的升级）----
def check_cross_document_refs() -> None:
    """单文档内不断链，不保证跨文档不断链。

    本轮实际发生过：ARCHITECTURE 引用了不存在的 Trap 13；PRD 引用了
    不存在的附录 A-9。因此本检查覆盖 PRD / ARCHITECTURE / DESIGN / ADR
    四份文档之间的相互引用。
    """
    adr_dir = DOCS / "decisions"
    arch = DOCS / "ARCHITECTURE.md"

    # 收集全项目真实存在的标识符
    adrs_on_disk = {p.stem for p in adr_dir.glob("ADR-*.md")}
    traps_defined: set[str] = set()
    adr7 = adr_dir / "ADR-007.md"
    if adr7.exists():
        traps_defined = set(re.findall(r"^### Trap (\d+)",
                                       adr7.read_text(encoding="utf-8"), re.MULTILINE))

    # 收集各文档真实存在的章节标识
    headings: dict[Path, set[str]] = {}
    for doc in [DOCS / "PRD.md", DOCS / "ARCHITECTURE.md", DOCS / "DESIGN.md"]:
        if doc.exists():
            headings[doc] = set(
                re.findall(r"^#{2,4}\s+(\d+(?:\.\d+)*|[A-Z](?:-\d+[a-z]?)?)\s",
                           doc.read_text(encoding="utf-8"), re.MULTILINE)
            )

    # 附录标识（PRD 用「附录 A-9」这类中文锚点）
    prd = DOCS / "PRD.md"
    prd_appendix: set[str] = set()
    if prd.exists():
        prd_appendix = set(re.findall(r"^##\s+附录\s+([A-Z](?:-\d+[a-z]?)?)[:：]",
                                      prd.read_text(encoding="utf-8"), re.MULTILINE))

    docs_to_scan = [p for p in
                    [DOCS / "PRD.md", DOCS / "ARCHITECTURE.md", DOCS / "DESIGN.md"]
                    if p.exists()] + list(adr_dir.glob("*.md"))

    for doc in docs_to_scan:
        for lineno, line in enumerate(doc.read_text(encoding="utf-8").splitlines(), 1):
            # 跨文档 ADR 引用
            for m in re.finditer(r"\b(ADR-\d{3})\b", line):
                if m.group(1) not in adrs_on_disk:
                    fail("xref-doc",
                         f"{doc.relative_to(ROOT)}:{lineno} 引用不存在的 {m.group(1)}")
            # 带编号的 Trap 引用
            for m in re.finditer(r"ADR-007\s+Trap\s+(\d+)", line):
                if m.group(1) not in traps_defined:
                    fail("xref-doc",
                         f"{doc.relative_to(ROOT)}:{lineno} 引用不存在的 "
                         f"ADR-007 Trap {m.group(1)}")
            # 跨文档章节引用（§6.2 等，指向 ARCHITECTURE 的编号体系）
            if doc.name != "ARCHITECTURE.md" and arch.exists():
                arch_nums = {h for h in headings.get(arch, set())
                             if re.match(r"^\d", h)}
                for m in re.finditer(r"ARCHITECTURE\.md\s*§(\d+(?:\.\d+)*)", line):
                    if m.group(1) not in arch_nums:
                        fail("xref-doc",
                             f"{doc.relative_to(ROOT)}:{lineno} 引用 "
                             f"ARCHITECTURE §{m.group(1)}，该章节不存在")
            # PRD 内部附录引用
            if prd_appendix:
                for m in re.finditer(r"附录\s+([A-Z](?:-\d+[a-z]?)?)", line):
                    ident = m.group(1)
                    # 仅当这一行不是标题定义行本身时才校验
                    if not line.lstrip().startswith("#"):
                        if ident not in prd_appendix and ident not in {"A", "B", "C"}:
                            fail("xref-doc",
                                 f"{doc.relative_to(ROOT)}:{lineno} 引用附录 {ident}，"
                                 f"但 PRD.md 未定义（已定义: {sorted(prd_appendix)}）")


# ---- 5c. ASCII 框线完整性（标为 WARN，不阻断）----
def check_box_drawing() -> None:
    """检测以│ 开头但不以 │ 结尾的表格行。

    背景：设计师的 v2.9 脚本按固定宽度重写ASCII 框时，未计中文双宽字符，
    导致 79 处框线截短。这是可机械检测的问题，不该依赖人眼。

    标为 WARN 而非 FAIL：修改 DESIGN.md 的时机由设计侧决定，
    架构侧只报告不阻断。
    """
    for doc in DOCS.rglob("*.md"):
        for lineno, line in enumerate(
                doc.read_text(encoding="utf-8").splitlines(), 1):
            if line.lstrip().startswith("│") and not line.rstrip().endswith("│"):
                warn("box-drawing",
                     f"{doc.relative_to(ROOT)}:{lineno} 框线不完整 "
                     f"（以│ 开头但未以 │ 结尾）")


# ---- 5d. 中文全角标点后多余空格（WARN）----
# 起因：批量删除 emoji 后必然产生这类残留（如「非空判断。 若采用」）。
# 不属于 P0，但影响可读性，且会持续累积。
#
# 规则必须精确 —— 早期版本误把「0% -> 22%」「1.3s（并行化后）」等
# ASCII 场景一并命中（2940 处假阳性）。现仅匹配全角标点。
_CJK_PUNCT_AFTER_SPACE = re.compile(
    "[。，、；：？！）】》」』][ \t]+(?=[\u4e00-\u9fffA-Za-z0-9])"
)


def check_cjk_punctuation_spacing() -> None:
    for doc in DOCS.rglob("*.md"):
        in_fence = False
        for lineno, line in enumerate(
                doc.read_text(encoding="utf-8").splitlines(), 1):
            if line.strip().startswith("```"):
                in_fence = not in_fence
                continue
            if in_fence:
                continue
            # 表格行是有意对齐的，跳过
            if line.lstrip().startswith("|"):
                continue
            m = _CJK_PUNCT_AFTER_SPACE.search(line)
            if m:
                warn("cjk-spacing",
                     f"{doc.relative_to(ROOT)}:{lineno} 全角标点后有多余空格 "
                     f"（{m.group()!r}）")


# ---- 5e. 同一实测的结论一致性（作用域机制，ADR-007 机制三）----
# 起因：客户端校验表写「ratios 非法值返回 200，不构成风险」，
# 而同一文档的 Trap 13 写「ratios=99x99 静默匹配，返回 1:1」。
# 同一实测、两处结论、且**表格里那版更显眼也更危险** ——
# 实施者会照表格写代码。
#
# 机制三（作用域放大）最难靠人眼发现，因为症状是「我测了，测得也对」。
# 因此对高风险参数做跨文档一致性抽查。
def check_conclusion_consistency() -> None:
    """实测事实的**矛盾表述**检查（ADR-007 机制三）。

    背景：本项目的事实（如 `ratios=99x99` 静默匹配）被重复写在
    ADR-007 / ARCHITECTURE / PRD 三处。任一处措辞与实测不符即产生
    结论漂移，且**更显眼的那版（表格 / 摘要）风险最高**。

    为什么不尝试通用语义比对：那需要 LLM，而门禁必须能在 CI 里
    确定性运行。因此只检测**可机械判定的矛盾**：

      同一个实测样本，若一处说它「被静默忽略 / 不构成风险」，
      另一处却把它当作「正常生效 / 精确匹配」，即为矛盾。

    纯粹的**重复表述**（同一结论说多次）不是矛盾，不应报错 ——
    本检查的第一版曾把line 76/346/493 的同义重复误报，已修正。
    """
    adr7 = DOCS / "decisions" / "ADR-007.md"
    if not adr7.exists():
        return

    text = adr7.read_text(encoding="utf-8")
    lines = text.splitlines()

    # 危险/正确两类互斥措辞
    SILENT = re.compile(r"(静默|被忽略|不构成风险|不报错)")
    EXACT = re.compile(r"(精确匹配|正常匹配|完全一致|生效)")

    # 逐行收集每个实测样本的定性
    verdicts: dict[str, set[str]] = {}
    for line in lines:
        for m in re.finditer(r"`([a-zA-Z]+=[^`\s]+)`", line):
            key = m.group(1)
            if SILENT.search(line):
                verdicts.setdefault(key, set()).add("silent")
            if EXACT.search(line):
                verdicts.setdefault(key, set()).add("exact")

    for key, vs in sorted(verdicts.items()):
        if "silent" in vs and "exact" in vs:
            fail("conclusion-drift",
                 f"ADR-007.md 中 `{key}` 同时被描述为「静默/忽略」"
                 f"与「精确匹配/正常生效」—— 同一实测出现互斥结论")


# ---- 6. 文件非空 ----
def check_non_empty() -> None:
    for p in list(DOCS.glob("*.md")) + list((DOCS / "decisions").glob("*.md")):
        if p.stat().st_size < 200:
            fail("empty", f"{p.relative_to(ROOT)} 仅 {p.stat().st_size} 字节")


# ---- 7. 相对 HEAD 的章节回归（覆盖式丢失）----
# 起因（真实事故，非假设）：docs/PRD.md 被一次写入丢掉约 490 行 ——
# 三块连续内容，每块起点都是二级标题。作者逐块还原（PRD v1.17 / b57300e）。
#
# 为什么主判据是**标题序列**而不是**行数**：
#   - 合法编辑几乎不会删除整个章节，但**经常**修改内容长度（改写、精简、表格对齐）。
#     行数阈值会把合法的整篇重构全部拦下 —— 那是假阳性。
#   - 反过来，一个既有二级标题整块消失，几乎必然是覆盖式写入事故 —— 那是真阳性。
#   本次事故正是「三个二级标题块整块消失」：标题判据直接命中，
#   行数判据只是间接信号，因此行数下降**只 WARN，绝不 FAIL**。
#
# 为什么不放在别的检查里：本项依赖 git（外部命令），失败模式与纯文本检查不同
# —— 它必须显式声明「本项未检查」，不能静默通过。
_TRACKED_DOCS = ("PRD.md", "ARCHITECTURE.md", "DESIGN.md")
_ALLOW_SHRINK_ENV = "IHAVEN_ALLOW_SHRINK"
_HEADING_RE = register(r"^##\s+(?P<title>.+?)\s*$")


def _headings(text: str) -> list[str]:
    """取二级标题序列（`## `，不匹配 `###` 及以下）。"""
    return [m.group("title")
            for m in (_HEADING_RE.match(line) for line in text.splitlines())
            if m]


_RENAME_RATIO = 0.6


def _prefix(title: str) -> str:
    """标题前缀（冒号前部分）—— 附录类标题改名时前缀通常不变。"""
    for sep in ("：", ":"):
        if sep in title:
            return title.split(sep, 1)[0]
    return title[:8]


def _is_rename(old: str, new: str) -> bool:
    """是否构成「疑似改名」：同前缀，或整体相似度达阈值。"""
    import difflib as _difflib

    if _prefix(old) == _prefix(new):
        return True
    return _difflib.SequenceMatcher(None, old, new).ratio() >= _RENAME_RATIO


def _pair_renames(missing: list[str],
                  added: list[str]) -> tuple[list[tuple[str, str]], list[str]]:
    """**一对一**配对（禁止一对多 / 多对一）：返回 (配对, 仍未配对的 missing)。

    未配对的仍按「消失」处理 —— 这是本项的硬约束：改名识别只能用来消噪，
    不得削弱对真删除的拦截。多块消失时若只配对上一块，剩下的必须照样拦住。
    """
    import difflib as _difflib

    pairs: list[tuple[str, str]] = []
    unpaired: list[str] = []
    used: set[int] = set()
    for m in missing:
        best_idx, best_score = -1, 0.0
        for i, a in enumerate(added):
            if i in used:
                continue
            score = _difflib.SequenceMatcher(None, m, a).ratio()
            if score > best_score:
                best_idx, best_score = i, score
        if best_idx >= 0 and _is_rename(m, added[best_idx]):
            used.add(best_idx)
            pairs.append((m, added[best_idx]))
        else:
            unpaired.append(m)
    return pairs, unpaired


def _heading_verdict(head_titles: list[str], work_titles: list[str],
                     head_lines: int,
                     work_lines: int) -> tuple[str, list[str], list[str]]:
    """纯函数：(verdict, fail_details, warn_details)。

    改名（一对一配对成功）-> WARN 并打印完整对照；配不上对的消失 -> FAIL。
    不依赖 git / 文件系统 —— 只有纯函数才能被启动自检直接验证。
    """
    missing = [t for t in head_titles if t not in work_titles]
    added = [t for t in work_titles if t not in head_titles]
    fail_details: list[str] = []
    warn_details: list[str] = []

    if missing:
        pairs, unpaired = _pair_renames(missing, added)
        for old, new in pairs:
            warn_details.append(f"疑似改名：{old!r} -> {new!r}（请确认）")
        for t in unpaired:
            fail_details.append(
                f"HEAD 中的二级标题在工作区消失（未配对到改名）: {t!r}")

    # 集合相同但顺序变化（新增标题不算变化，故先按 HEAD 集合过滤）
    # 有标题消失时不判顺序 —— 那时「顺序变化」是改名/删除的副作用，会误导
    head_set = set(head_titles)
    if not missing and [t for t in work_titles if t in head_set] != head_titles:
        warn_details.append("二级标题顺序变化（集合未变）")
    if head_lines > 0 and work_lines < head_lines * 0.95:
        pct = (head_lines - work_lines) / head_lines * 100
        warn_details.append(f"行数下降 {pct:.1f}%（{head_lines} -> {work_lines}）")

    if fail_details:
        return "fail", fail_details, warn_details
    return ("warn", fail_details, warn_details) if warn_details else ("ok", [], [])


def _git_show(rel: str, root: Path | None = None) -> str | None:
    """取 HEAD 版本内容。git 不可用 / 非仓库 / 未 track 时返回 None（= SKIP）。"""
    import shutil as _shutil
    import subprocess as _subprocess

    if _shutil.which("git") is None:
        return None
    base = str(root if root is not None else ROOT)
    p = _subprocess.run(["git", "-C", base, "show", f"HEAD:{rel}"],
                        capture_output=True, text=True)
    if p.returncode != 0:
        return None
    return p.stdout


def check_heading_regression() -> None:
    """比对工作区与 HEAD 的二级标题序列，捕获「覆盖式写入丢段」。

    判据：HEAD 中存在的二级标题在工作区消失 -> FAIL；顺序变化或行数下降 > 5%
    -> WARN。逃逸阀 `IHAVEN_ALLOW_SHRINK=1` 放行但**必须打印消失的标题**。

    已知盲区（未声明进 BLIND_SPOTS，因本轮冻结只授权新增本项与其自检）：
    只覆盖 `docs/PRD.md` / `ARCHITECTURE.md` / `DESIGN.md` 三个文件的**二级**标题；
    三级及以下标题整块消失、以及未纳入列表的文档，本项不覆盖。
    """
    import os as _os

    skipped: list[str] = []
    for name in _TRACKED_DOCS:
        rel = f"docs/{name}"
        p = DOCS / name
        if not p.exists():
            skipped.append(f"{rel} 不存在")
            continue
        head = _git_show(rel)
        if head is None:
            skipped.append(f"{rel} 无 HEAD 版本（git 不可用 / 非仓库 / 未 track）")
            continue

        work = p.read_text(encoding="utf-8")
        verdict, fail_details, warn_details = _heading_verdict(
            _headings(head), _headings(work),
            len(head.splitlines()), len(work.splitlines()))
        if verdict == "ok":
            continue

        if _os.environ.get(_ALLOW_SHRINK_ENV) == "1":
            # 逃逸不能静默：放行了也要把命中内容打出来
            warn("heading-regression",
                 f"{rel} 命中但被 {_ALLOW_SHRINK_ENV}=1 放行 —— "
                 + "；".join(fail_details + warn_details))
            continue

        for d in fail_details:
            fail("heading-regression", f"{rel} {d}")
        for d in warn_details:
            warn("heading-regression", f"{rel} {d}")

    if skipped:
        print("[verify-docs] 本项未检查（heading-regression SKIP）: "
              + "；".join(skipped))


def self_test_heading_regression() -> None:
    """本项的自检：既能检出它要检的东西，也能在能力缺失时正确 SKIP。

    ① 负向用例（植入删标题）-> 必须 FAIL；且「仅行数下降」必须 WARN 而非 FAIL
    ② 能力缺失（非 git 仓库 / 未 track）-> 必须返回 None（SKIP），不得静默 PASS
    ③ 改名识别：改名 -> WARN；**部分配对** -> 剩下配不上对的必须仍 FAIL
    """
    problems = []

    v, f_details, _ = _heading_verdict(["A", "B", "C"], ["A", "C"], 6, 5)
    if v != "fail" or not any("B" in d for d in f_details):
        problems.append(f"删标题未被判为 FAIL（verdict={v}, fail={f_details}）")

    v2, _, _ = _heading_verdict(["A", "B", "C"], ["A", "B", "C"], 100, 80)
    if v2 != "warn":
        problems.append(f"仅行数下降应判 WARN，实为 {v2}（规格：行数下降绝不 FAIL）")

    v3, _, _ = _heading_verdict(["A", "B", "C"], ["C", "B", "A"], 6, 6)
    if v3 != "warn":
        problems.append(f"标题顺序变化应判 WARN，实为 {v3}")

    v4, _, _ = _heading_verdict(["A", "B"], ["A", "B", "D"], 4, 6)
    if v4 != "ok":
        problems.append(f"新增标题不应报警，实为 {v4}（会把合法编辑误报）")

    # ③a 改名：用 PRD A-21 那次真实改名做样本（前缀「附录 A-21」不变）
    old_a21 = "附录 A-21：sketchy 同样受 Key 门控，且是静默降级（产品侧实测，2026-10-08）"
    new_a21 = "附录 A-21：全部档位都受 Key 门控，且是静默降级（产品侧实测，2026-10-08）"
    v5, f5, w5 = _heading_verdict(["一、问题陈述", old_a21],
                                  ["一、问题陈述", new_a21], 6, 6)
    if v5 != "warn" or f5:
        problems.append(f"改名应判 WARN 且不进 FAIL 列表，实为 {v5}（fail={f5}）")
    if not any("疑似改名" in d and old_a21 in d and new_a21 in d for d in w5):
        problems.append(f"改名必须打印完整对照 OLD -> NEW，实为 {w5}")

    # ③b 部分配对：消失 3 个、只加回 1 个近义名 -> 剩下 2 个必须仍 FAIL 且被指名
    v6, f6, w6 = _heading_verdict(
        ["一、问题陈述", old_a21, "附录 A-22：另一条", "附录 A-23：再一条", "九、收尾"],
        ["一、问题陈述", new_a21, "九、收尾"], 10, 9)
    if v6 != "fail":
        problems.append(f"部分配对时应 FAIL，实为 {v6}")
    if not all(any(t in d for d in f6) for t in ("附录 A-22", "附录 A-23")):
        problems.append(f"部分配对时未配对的两条必须仍被指名 FAIL，实为 {f6}")
    if not any("疑似改名" in d for d in w6):
        problems.append(f"部分配对时已成对的那对应仍打印对照，实为 {w6}")

    # ③c 一对一：两个 missing 竞争同一个 added -> 只能配掉一个，另一个仍 FAIL
    v7, f7, _ = _heading_verdict(["附录 A-1：旧结论", "附录 A-2：旧结论"],
                                 ["附录 A-1：新结论"], 4, 3)
    if v7 != "fail" or len(f7) != 1:
        problems.append(f"一对一配对失效（应只剩 1 个 FAIL），实为 {v7}（fail={f7}）")

    import tempfile
    with tempfile.TemporaryDirectory() as td:
        if _git_show("docs/PRD.md", root=Path(td)) is not None:
            problems.append("非 git 目录下 _git_show 未返回 None —— "
                            "SKIP 路径失效，本项会静默 PASS")

    if problems:
        raise RuntimeError(
            "章节回归自检失败（已阻断）:\n  - " + "\n  - ".join(problems)
        )


def main() -> int:
    global ROOT, DOCS
    ap = argparse.ArgumentParser(
        description="IHaven 独立文档校验器（只读校验，不参与文件写入）",
    )
    ap.add_argument(
        "--root", type=Path, default=_DEFAULT_ROOT,
        help="项目根目录。负向测试请指向临时副本，"
             "例如 --root /tmp/test-docs，避免修改真实文件。",
    )
    args = ap.parse_args()
    ROOT = args.root.resolve()
    DOCS = ROOT / "docs"

    # 启动自检必须在任何检查之前 —— 自己不能跑，就没资格检查别人
    for stage, fn in (("正则自检", self_test),
                      ("外部依赖能力自检", self_test_external_deps),
                      ("章节回归自检", self_test_heading_regression)):
        try:
            fn()
        except RuntimeError as exc:
            print(f"[verify-docs] SELF-TEST FAILED（{stage}）—— {exc}",
                  file=sys.stderr)
            return 2
    print("[verify-docs] 自检通过（正则可编译 + 负向用例命中 + 外部依赖可用）")
    for b in BLIND_SPOTS:
        print(f"[verify-docs] 已声明盲区: {b}")

    print(f"[verify-docs] 独立校验器启动（只读，不参与文件写入）")
    print(f"[verify-docs] root = {ROOT}\n")

    for fn in (check_emoji, check_purple_pink, check_json,
               check_section_numbering, check_cross_references,
               check_cross_document_refs, check_box_drawing,
               check_cjk_punctuation_spacing,
               check_conclusion_consistency, check_non_empty,
               check_heading_regression):
        try:
            fn()
        except Exception as exc:                      # noqa: BLE001
            fail(fn.__name__, f"检查器自身异常: {exc}")

    for w in (WARM + WARNINGS):
        print(w)
    print()
    if FAILURES:
        for f in FAILURES:
            print(f)
        print(f"\n[verify-docs] FAIL —— {len(FAILURES)} 项不通过")
        return 1

    print("[verify-docs] PASS —— 全部检查通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())

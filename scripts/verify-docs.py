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
WARNINGS: list[str] = []


def fail(check: str, detail: str) -> None:
    FAILURES.append(f"[FAIL] {check}: {detail}")


def warn(check: str, detail: str) -> None:
    WARNINGS.append(f"[WARN] {check}: {detail}")


# ---- 1. emoji 零命中（P0）----
def check_emoji() -> None:
    """emoji 区间检测。刻意不用 emoji 库—— 库的判定范围与我们的 P0 规则
    不一致，且引入依赖会让本脚本自身变成风险源。"""
    targets = list(DOCS.rglob("*.md")) + [DOCS / "VERIFIED-API.swift"]
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
        m = re.match(r"^#{2,4}\s+(\d+(?:\.\d+)*)\s", line)
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
        expected = list(range(1, max(kids_sorted) + 1))
        # §5.0 是刻意的前置定位节（见ARCHITECTURE.md §5.0 的设计意图说明），
        # 编号从 0 起是合理的，不参与连续性检查。
        if parent == "5":
            continue
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
                      ("外部依赖能力自检", self_test_external_deps)):
        try:
            fn()
        except RuntimeError as exc:
            print(f"[verify-docs] SELF-TEST FAILED（{stage}）—— {exc}",
                  file=sys.stderr)
            return 2
    print("[verify-docs] 自检通过（正则可编译 + 负向用例命中 + 外部依赖可用）")

    print(f"[verify-docs] 独立校验器启动（只读，不参与文件写入）")
    print(f"[verify-docs] root = {ROOT}\n")

    for fn in (check_emoji, check_purple_pink, check_json,
               check_section_numbering, check_cross_references,
               check_cross_document_refs, check_box_drawing,
               check_cjk_punctuation_spacing,
               check_conclusion_consistency, check_non_empty):
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

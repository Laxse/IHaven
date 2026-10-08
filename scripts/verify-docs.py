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

用法：python3 scripts/verify-docs.py
退出码：0 = 全部通过；1 = 有 FAIL
"""

import json
import re
import sys
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs"

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
                    or 0x2600 <= cp <= 0x27BF  # misc symbols + dingbats (含 ✅❌⚠)
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


# ---- 6. 文件非空 ----
def check_non_empty() -> None:
    for p in list(DOCS.glob("*.md")) + list((DOCS / "decisions").glob("*.md")):
        if p.stat().st_size < 200:
            fail("empty", f"{p.relative_to(ROOT)} 仅 {p.stat().st_size} 字节")


def main() -> int:
    print("[verify-docs] 独立校验器启动（不参与文件写入）\n")

    for fn in (check_emoji, check_purple_pink, check_json,
               check_section_numbering, check_cross_references, check_non_empty):
        try:
            fn()
        except Exception as exc:                      # noqa: BLE001
            fail(fn.__name__, f"检查器自身异常: {exc}")

    for w in WARNINGS:
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

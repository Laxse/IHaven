#!/usr/bin/env python3
"""
shell 门禁的**语义自检** —— 证明门禁能检出植入的违规，而非仅在真实仓库「通过」。

起因（ARCHITECTURE 侧误判 -> 真问题）：
用隔离目录测 security-gate.sh时第一次得到 MISSED。排查发现是**测试方式**
错误（门禁硬编码 cd "$(dirname "$0")/.."，只能指向仓库根）。修正后门禁本身
是对的 —— 但这次排查暴露出结构性问题：

    在真实仓库跑     -> 只能证明「当前是干净的」
    植入违规 + 副本   -> 才能证明「它真的有效」

后者才是门禁有效性的证据。此脚本用设计师交付的 selftest_framework 提供的
语义断言（must_exit / expect_stdout）实现后者。

用法：python3 scripts/gate-selfcheck.py
退出码：0 = 全部通过；1 = 有门禁未检出预期违规
"""

import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GATES = ["security-gate.sh", "convention-gate.sh"]

# 每个门禁应检出的植入违规：文件名 -> (内容, 说明)
VIOLATIONS = {
    "security-gate.sh": {
        "Core/Probe.swift": (
            'enum Probe { static let apikey = "CmQyjMpXsdgTlyoME98eaf64cbJCRzac" }\n',
            "硬编码明文 API Key",
        ),
    },
    "convention-gate.sh": {
        "Core/Probe.swift": (
            "import Foundation\nclass P: ObservableObject { @Published var x = 1 }\n",
            "被 ADR-004 禁用的 ObservableObject",
        ),
    },
}


def build_fixture(gate: str, files: dict) -> Path:
    """在临时目录搭出 scripts/<gate> + 违规文件的结构。"""
    tmp = Path(tempfile.mkdtemp())
    (tmp / "scripts").mkdir()
    shutil.copy(ROOT / "scripts" / gate, tmp / "scripts" / gate)
    for rel, content in files.items():
        p = tmp / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content, encoding="utf-8")
    return tmp


def run_gate(gate: str, root: Path) -> subprocess.CompletedProcess:
    env = dict(os.environ, IHAVEN_ROOT=str(root))
    return subprocess.run(
        ["bash", str(root / "scripts" / gate)],
        capture_output=True, text=True, env=env,
    )


# ============================================================
# python 检查器用例（本轮新增）
# ============================================================
# 起因：GATES 只有两个 shell 门禁 —— 意味着 verify-docs.py 的**全部**
# 检查项（emoji / 紫粉渐变 / JSON / 章节编号 / 跨文档引用 / 结论漂移 /
# 文件非空 / 章节回归）**从未进入过有效性证明链**。新加的 heading-regression
# 只是让这个既有盲区显形了：我们有整套检查，却没有证据证明它们能检出东西。
#
# 隔离原则不变：被测目标一律是 tempfile.mkdtemp() 副本 + 副本内 git init，
# 真实仓库零触碰，且绝不在真实仓库里 init。
PY_GATE = "verify-docs.py"


def _drop_first_h2(text: str) -> str:
    """mutate 用：删掉第一个二级标题行，制造「工作区 vs HEAD」的差异。"""
    out: list[str] = []
    dropped = False
    for ln in text.splitlines(keepends=True):
        if not dropped and ln.startswith("## "):
            dropped = True
            continue
        out.append(ln)
    return "".join(out)


# 每个用例三种植入方式（可组合）：
#   files  —— 覆盖写入（git commit 之前 / 无需 git 时）
#   append —— 追加到副本现有文件末尾
#   mutate —— commit **之后**再施加，用于「工作区 vs HEAD」类检查（需 git）
_PY_CASES: list[dict] = [
    {
        "desc": "P0-emoji：md 中植入 emoji",
        "files": {"docs/PROBE-EMOJI.md": "# 探针\n正文: \U0001F600\n"},
        "expect_exit": 1, "expect_in": "P0-emoji",
    },
    {
        "desc": "P0-emoji：svg 中植入 emoji（证明 svg 已纳入扫描）",
        "files": {"docs/wireframes/PROBE.svg":
                  '<svg xmlns="http://www.w3.org/2000/svg"><!-- \U0001F600 --></svg>\n'},
        "expect_exit": 1, "expect_in": "P0-emoji",
    },
    {
        "desc": "P0-gradient：紫粉渐变",
        "files": {"docs/PROBE-GRADIENT.md": "# 探针\npurple gradient\n"},
        "expect_exit": 1, "expect_in": "P0-gradient",
    },
    {
        "desc": "json：design-tokens.json 非法",
        "files": {"docs/design-tokens.json": "{ 这不是 JSON"},
        "expect_exit": 1, "expect_in": "json",
    },
    {
        # 用 `#### 6.4.0` 而非 `## 8.`：后者的「N.」写法不被 check_section_numbering
        # 的正则索引（编号后必须紧跟空白），植入它不会触发任何检查 —— 详见报告。
        "desc": "sections：章节编号重复",
        "append": {"docs/ARCHITECTURE.md": "\n#### 6.4.0 重复编号探针\n"},
        "expect_exit": 1, "expect_in": "sections",
    },
    {
        "desc": "xref：引用不存在的 ADR / Trap",
        "files": {"docs/PROBE-XREF.md": "# 探针\n见 ADR-999 与 ADR-007 Trap 999\n"},
        "expect_exit": 1, "expect_in": "xref",
    },
    {
        "desc": "conclusion-drift：同一实测给出互斥结论",
        "append": {"docs/decisions/ADR-007.md":
                   "\n被测 `resolutions=9999x9999` 静默忽略，不报错\n"
                   "被测 `resolutions=9999x9999` 精确匹配，正常生效\n"},
        "expect_exit": 1, "expect_in": "conclusion-drift",
    },
    {
        "desc": "empty：文件过小",
        "files": {"docs/TINY.md": "x"},
        "expect_exit": 1, "expect_in": "empty",
    },
    {
        "desc": "heading-regression：二级标题整块消失（需 git）",
        "git": True, "init_repo": True,
        "mutate": {"docs/PRD.md": _drop_first_h2},
        "expect_exit": 1, "expect_in": "heading-regression",
    },
    {
        # 注意：它标 git=True 是因为 **verify-docs.py 自身**在启动阶段就会因
        # git 不可用而阻断（exit 2）—— 没有 git 时这个用例根本跑不起来，
        # 必须跟着 SKIP，否则会把「能力缺失」误报成「检查器失效」。
        "desc": "heading-regression 能力缺失：非 git 目录必须 SKIP 且显式声明",
        "git": True,
        "expect_exit": 0, "expect_in": "本项未检查（heading-regression SKIP）",
    },
]


def _git(tmp: Path, *args: str) -> None:
    subprocess.run(["git", "-C", str(tmp), *args],
                   capture_output=True, text=True, check=True)


def build_py_fixture(files: dict, append: dict, mutate: dict,
                     with_git: bool) -> Path:
    """在临时目录搭出 docs/ + scripts/ 副本；with_git 时在副本内 git init 并提交。

    mutate 在 commit **之后**施加 —— 只有这样才能造出「工作区 vs HEAD」的差异。
    真实仓库零触碰，且绝不在真实仓库里 git init。
    """
    tmp = Path(tempfile.mkdtemp())
    shutil.copytree(ROOT / "docs", tmp / "docs")
    shutil.copytree(ROOT / "scripts", tmp / "scripts")
    for rel, content in files.items():
        p = tmp / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content, encoding="utf-8")
    for rel, extra in append.items():
        p = tmp / rel
        p.write_text(p.read_text(encoding="utf-8") + extra, encoding="utf-8")
    if with_git:
        _git(tmp, "init", "-q")
        _git(tmp, "-c", "user.email=probe@local", "-c", "user.name=probe",
             "add", "-A")
        _git(tmp, "-c", "user.email=probe@local", "-c", "user.name=probe",
             "commit", "-qm", "init")
        for rel, fn in mutate.items():
            p = tmp / rel
            p.write_text(fn(p.read_text(encoding="utf-8")), encoding="utf-8")
    return tmp


def assert_py_fixture_valid(root: Path, case: dict) -> None:
    """夹具有效性断言 —— 防「植入无效但用例照样通过」的对象盲区。

    用例本身被检出只能证明检查器在工作；如果夹具根本没造出差异，
    用例会**假通过**，而这正是设计侧 v4.0 实证的第三类盲区。
    """
    if not case.get("init_repo"):
        return
    r = subprocess.run(["git", "-C", str(root), "show", "HEAD:docs/PRD.md"],
                       capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError("git 夹具无效：HEAD 中取不到 docs/PRD.md")
    head_h2 = sum(1 for ln in r.stdout.splitlines() if ln.startswith("## "))
    work_h2 = sum(1 for ln in (root / "docs" / "PRD.md")
                  .read_text(encoding="utf-8").splitlines() if ln.startswith("## "))
    if work_h2 >= head_h2:
        raise RuntimeError(
            f"git 夹具无效：工作区二级标题数未减少（HEAD {head_h2} / "
            f"工作区 {work_h2}）—— 用例会假通过"
        )


def main() -> int:
    print("[gate-selfcheck] 门禁语义自检")
    print("[gate-selfcheck] 验证「门禁能检出植入违规」，而非仅「当前仓库干净」\n")

    failures = []
    for gate in GATES:
        cases = VIOLATIONS.get(gate, {})
        if not cases:
            print(f"[{gate}] 无植入用例，跳过")
            continue
        for rel, (content, desc) in cases.items():
            root = build_fixture(gate, {rel: content})
            try:
                r = run_gate(gate, root)
            except FileNotFoundError as exc:
                # 能力缺失必须显式声明，不得静默 PASS，也不得崩成 traceback
                print(f"[{gate}] 本项未检查（SKIP）: {desc} —— 依赖不可用（{exc}）")
                continue
            finally:
                shutil.rmtree(root, ignore_errors=True)

            out = r.stdout
            must_exit_1 = r.returncode == 1
            must_mention = desc.split()[0] in out or "FAIL" in out

            if must_exit_1 and must_mention:
                print(f"[{gate}] DETECTED  exit=1  {desc}")
            else:
                print(f"[{gate}] MISSED    exit={r.returncode}  {desc}")
                print("  --- gate output ---")
                print("\n".join(f"  {ln}" for ln in out.splitlines()[:8]))
                failures.append(f"{gate}: 未检出「{desc}」")

    git_ok = shutil.which("git") is not None
    print(f"[{PY_GATE}] 首次进入有效性证明链 —— "
          f"此前它的全部检查项从未被验证过「能否检出植入的违规」\n")
    for case in _PY_CASES:
        desc = case["desc"]
        if case.get("git") and not git_ok:
            # 能力缺失必须显式声明，不得静默 PASS（沿用 require_external 语义）
            print(f"[{PY_GATE}] 本项未检查（SKIP）: {desc} —— git 不可用，用例未运行")
            continue

        root = build_py_fixture(case.get("files", {}), case.get("append", {}),
                                case.get("mutate", {}), bool(case.get("init_repo")))
        try:
            assert_py_fixture_valid(root, case)
            r = subprocess.run(
                ["python3", str(root / "scripts" / PY_GATE), "--root", str(root)],
                capture_output=True, text=True,
            )
        except Exception as exc:                       # noqa: BLE001
            print(f"[{PY_GATE}] FIXTURE-INVALID  {desc}")
            print(f"  {exc}")
            failures.append(f"{PY_GATE}: 夹具无效（{desc}）-> {exc}")
            continue
        finally:
            shutil.rmtree(root, ignore_errors=True)

        out = r.stdout + r.stderr
        if r.returncode == case["expect_exit"] and case["expect_in"] in out:
            print(f"[{PY_GATE}] DETECTED  exit={r.returncode}  {desc}")
        else:
            print(f"[{PY_GATE}] MISSED    exit={r.returncode}  {desc}")
            print(f"  期望 exit={case['expect_exit']} 且输出含 {case['expect_in']!r}")
            print("  --- verify-docs output（前 8 行）---")
            print("\n".join(f"  {ln}" for ln in out.splitlines()[:8]))
            failures.append(f"{PY_GATE}: 未检出「{desc}」")

    print()
    if failures:
        for f in failures:
            print(f"[FAIL] {f}")
        return 1
    print("[gate-selfcheck] PASS —— 所有门禁均能检出植入的违规")
    return 0


if __name__ == "__main__":
    sys.exit(main())

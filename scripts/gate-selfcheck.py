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

    print()
    if failures:
        for f in failures:
            print(f"[FAIL] {f}")
        return 1
    print("[gate-selfcheck] PASS —— 所有门禁均能检出植入的违规")
    return 0


if __name__ == "__main__":
    sys.exit(main())

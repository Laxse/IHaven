"""校验器自检框架（可复用）
========================

**为什么有这个模块**：我们已四次遇到「检索/检查工具静默失效」——
security-gate 的空格类、cjk-spacing 的 PCRE 水平空白类、verify-docs 核实时的
BSD basic 模式 alternation、pre-commit 的 PCRE 模式开关。
四次里有两次是「能力不存在 + 失败静默」，静默失效比误报更危险：
它给人「已有防护」的错觉，而实际一条规则都没跑。

**核心原则**：自己不能跑，就没资格检查别人。

**三类自检**

| 类别 | 能抓 | 抓不到 |
|------|------|--------|
| 1 正则可编译性 | Python re 语法错误（如 PCRE 专有的水平空白类） | 外部工具能力缺失 |
| 2 负向用例 | 规则永不命中 / 过宽（误报） | 规则漏报 |
| 3 外部依赖能力 | 「以为有能力实际没有」（如 macOS 无 PCRE 模式） | — |

**用法**

```python
from selftest_framework import SelfTest

st = SelfTest("my-check")
emoji = st.compile(r'[\U0001F300-\U0001F9FF]')   # 1 正则可编译

@st.rule
def check_emoji():
    st.must_hit("有 emoji")       # 2 必须命中
    st.must_miss("纯中文无 emoji") # 2 必须不命中
    st.position("│ 状态栏 │ <- 说明", False)  # 2 位置用例

st.require_external("grep", "-P", "test")   # 3 外部能力
st.run()   # 自测不通过 -> SystemExit(2)
```

**为什么 POSITION_CASES 是独立的第三类**

负向用例防「误报」，位置用例防「误判该跳过的地方没跳过」。
例：ASCII 布局图里有大量对齐空格，若规则不跳过代码块就会误报——
这类「跳过逻辑失效」既不是过宽也不是漏报，而是第三种形态。
"""
import re
import subprocess
import sys
from dataclasses import dataclass, field
from typing import Callable, List, Tuple


@dataclass
class Case:
    """一个测试用例"""
    content: str
    should_flag: bool
    label: str = ""


@dataclass
class SelfTest:
    """校验器自检框架"""
    name: str = "check"
    _rules: List[Tuple[str, Callable]] = field(default_factory=list)
    _cases: List[Case] = field(default_factory=list)
    _external: List[Tuple[str, list, str]] = field(default_factory=list)
    blind_spots: List[str] = field(default_factory=list)

    # ---------- 盲区声明 ----------

    def declare_blind_spot(self, description: str) -> None:
        """显式声明本检查器**不检查**什么。

        起因（设计侧 v3.5 实证）：`check_punct_spacing.py` 不管 emoji，
        `verify.py` 只扫 .md/.css/.json 不扫 .py —— 三层防线全绿，
        但 .py 里仍有 3 处字面 emoji。延迟两轮才发现。

        核心原则：**声明了才能被讨论，没声明就默认它被检查了。**
        这是从「默认有防护」转向「显式声明防护边界」。
        """
        self.blind_spots.append(description)

    # ---------- 定义阶段（装饰器） ----------

    def rule(self, fn: Callable) -> Callable:
        self._rules.append((fn.__name__, fn))
        return fn

    # ---------- 用例 ----------

    def must_hit(self, content: str, label: str = "") -> None:
        """content 必须被规则命中"""
        self._cases.append(Case(content, True, label or f"必须命中: {content!r}"))

    def must_miss(self, content: str, label: str = "") -> None:
        """content 必须不被规则命中"""
        self._cases.append(Case(content, False, label or f"必须不命中: {content!r}"))

    def position(self, content: str, should_flag: bool, label: str = "") -> None:
        """位置用例 —— 验证「该跳过的区域确实被跳过」

        独立于 must_hit/must_miss，因为它防的是第三种失效：
        「跳过逻辑失效」既不是过宽也不是漏报。
        例：ASCII 布局图有对齐空格，规则若不跳过代码块就会误报。
        """
        self._cases.append(
            Case(content, should_flag, label or f"位置: {content!r}")
        )

    # ---------- 外部依赖 ----------

    def require_external(self, cmd: str, *args: str,
                         probe_input: str = "test",
                         must_exit: int | None = None,
                         expect_stdout: str | None = None) -> None:
        """声明外部依赖，并检查它是否真的具备该能力

        两��用法：

        1) 能力探测（只确认工具支持该选项）：
           st.require_external("grep", "-P", "test")
           → 退出码 2 或 stderr 含 invalid option => 能力不存在

        2) 语义断言（运行真实命令并断言结果）—— 架构师建议：
           st.require_external("grep", "-E", "x",
                               probe_input="x", must_exit=0)
           st.require_external("grep", "-E", "x",
                               probe_input="y", expect_stdout="")
           → 不只问「能不能跑」，而是断言「跑出来对不对」

        理由（架构师提出）：require_semantic 那一类无法机械判定
        （「语义是否正确」本身没有判据），所以不新增类型，
        而是把语义断言挂到已有的外部依赖检查上。
        """
        self._external.append((cmd, list(args), probe_input,
                               must_exit, expect_stdout))

    # ---------- 模块位置说明 ----------
    # 本模块是可复用的**代码**（非文档），理想位置是 `scripts/lib/`。
    # 当前在 docs/ 下是因为它与 GATE-USAGE.md 的自检规范配套阅读。
    # 若迁到 scripts/lib/，需同步更新 GATE-USAGE.md 里的引用路径。

    # ---------- 执行阶段 ----------

    @staticmethod
    def compile(pattern: str) -> "re.Pattern":
        """① 正则可编译性 —— PCRE 专有语法会在此抛异常"""
        try:
            return re.compile(pattern)
        except re.error as e:
            raise SyntaxCheckFailure(f"正则语法错误: {pattern!r} -> {e}")

    def run(self) -> None:
        """执行全部自检。失败则 SystemExit(2)"""
        print(f"[{self.name}] 自检开始")
        if self.blind_spots:
            print(f"[{self.name}] 已声明盲区（不检查这些）:")
            for b in self.blind_spots:
                print(f"    - {b}")
        failures = []

        # 执行规则（① 正则可编译性 + ② 用例）
        for rule_name, fn in self._rules:
            try:
                fn()
            except SyntaxCheckFailure as e:
                failures.append(f"[①正则] {rule_name}: {e}")
            except Exception as e:
                failures.append(f"[①正则] {rule_name} 执行异常: {type(e).__name__}: {e}")

        # ③ 外部依赖能力（+ 可选语义断言）
        for cmd, args, probe, must_exit, expect_stdout in self._external:
            try:
                r = subprocess.run([cmd] + args, input=probe,
                                   capture_output=True, text=True, timeout=5)
                stderr = (r.stderr or '').lower()

                # ③a 能力探测：不支持该选项（静默失效的形态）
                if r.returncode == 2 or 'invalid option' in stderr:
                    failures.append(
                        f"[③外部依赖] `{cmd} {' '.join(args)}` 在本平台不可用"
                        f"（exit={r.returncode}）—— 会静默失效"
                    )
                    continue

                # ③b 语义断言（架构师建议）：运行真实命令并断言结果
                if must_exit is not None and r.returncode != must_exit:
                    failures.append(
                        f"[③语义断言] `{cmd} {' '.join(args)}` "
                        f"期望 exit={must_exit}，实得 {r.returncode}"
                        f"（stderr: {r.stderr.strip()[:60]}）"
                    )
                if expect_stdout is not None:
                    if expect_stdout not in (r.stdout or ''):
                        failures.append(
                            f"[③语义断言] `{cmd} {' '.join(args)}` "
                            f"输出不含 {expect_stdout!r}"
                            f"，实得 {(r.stdout or '').strip()[:40]!r}"
                        )
            except FileNotFoundError:
                failures.append(f"[③外部依赖] `{cmd}` 不存在")
            except Exception as e:
                failures.append(f"[③外部依赖] `{cmd}` 探测异常: {e}")

        # 汇总
        if failures:
            print(f"[{self.name}] SELF-TEST FAILED", file=sys.stderr)
            for f in failures:
                print(f"  {f}", file=sys.stderr)
            sys.exit(2)

        print(f"[{self.name}] 自检通过"
              f"（{len(self._rules)} 条规则可编译"
              f" + {len(self._external)} 项外部依赖可用）")


class SyntaxCheckFailure(Exception):
    """正则语法错误 —— 对应自检类别①"""


# ---------- 便捷：带自检的匹配器 ----------

class GuardedPattern:
    """带自检的正则匹配器

    用法:
        gp = GuardedPattern("emoji", r'[\U0001F300-\U0001F9FF]')
        gp.must_hit("有 emoji \U0001F680")   # 用转义表达样本
        gp.must_miss("纯中文")
        gp.check()          # 自检不通过则 SystemExit(2)
        gp.search(text)     # 正常使用
    """

    def __init__(self, name: str, pattern: str):
        self.name = name
        self.raw = pattern
        try:
            self.p = re.compile(pattern)
        except re.error as e:
            print(f"[{name}] SELF-TEST FAILED: 正则语法错误 {e}",
                  file=sys.stderr)
            sys.exit(2)
        self._cases: List[Case] = []

    def must_hit(self, content: str):  self._cases.append(Case(content, True))
    def must_miss(self, content: str): self._cases.append(Case(content, False))

    def check(self):
        """执行负向/正向用例自检"""
        for c in self._cases:
            got = bool(self.p.search(c.content))
            if got != c.should_flag:
                print(f"[{self.name}] SELF-TEST FAILED: "
                      f"{c.label} 期望={c.should_flag} 实得={got}",
                      file=sys.stderr)
                sys.exit(2)
        return self

    def search(self, text: str):
        return self.p.search(text)

    def findall(self, text: str):
        return self.p.findall(text)


# ========== 使用示例（可直接运行验证框架本身） ==========
if __name__ == "__main__":
    st = SelfTest("demo")

    hit_emoji = st.compile(r'[\U0001F300-\U0001F9FF]')

    @st.rule
    def rule_emoji():
        st.must_hit("有 emoji \U0001F680")   # 用转义表达样本
        st.must_miss("纯中文无 emoji")
        # 位置用例：ASCII 图里不该命中
        st.position("│ 状态栏 │  <- 说明", False)

    @st.rule
    def rule_cjk_spacing():
        pat = st.compile(r'[一-鿿][。，][ \t]{2,}')
        st.must_hit("正常。  多余")
        st.must_miss("ASCII 0% -> 22%")
        st.must_miss("单个空格 正常。 一个")

    st.require_external("grep", "-P", "test")   # macOS 上会 WARN/失败
    st.run()
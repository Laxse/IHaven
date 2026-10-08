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
import ast
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


# ---- 跨工具正则语义一致性（v3.8 新增）----

def check_regex_dialect(pattern: str, warn_pure_escape: bool = False) -> None:
    """检查 `pattern` 是否混用了两种正则方言的 alternation 语法。

    背景（架构师提出、设计师实测确认）：
    同一写法 ``a\\|b`` 在不同工具下语义**完全不同**，且有**三种机制**：

    | 工具 | 写法 | 实测结果 | 机制 |
    |------|------|---------|------|
    | BSD grep basic | ``grep 'a\\|b'`` | exit=1，零命中，无报错 | **语法无效** |
    | Python re | ``r'a\\|b'`` | 匹配字面 ``a\\|b`` | **字面竖线匹配** |
    | Python 非 raw 串| ``'a\\|b'`` | 同上 + SyntaxWarning | **多一层警告** |

    这比「工具能力缺失」更隐蔽：语法都能编译，但匹配的东西不一样。

    **为什么不对「纯 \\|」也报警**（架构师提议过，我们实测后否决）：

    纯 ``\\|`` 在 Python 里确实是**合法的字面竖线匹配**，且有正当用途。
    本项目实例（verify.py 实测）：

        re.match(r"^\\| \\d{4}-\\d{2}-\\d{2} \\| (v[\\d.]+)", "| 2026-10-08 | v2.1 | ...")
        → 匹配成功，提取出 'v2.1'

    这是匹配 **Markdown 表格的行首竖线**，完全正当。若对纯 ``\\|`` 也报WARN，
    会误报这类用法 —— 而误报会导致检查被忽略，比漏报更糟。

    Args:
        pattern: 待检查的正则（Python re 语法）
        warn_pure_escape: 若为 True，含 ``\\|`` 但不含裸 ``|`` 时也发出警告。
            默认 False —— 实测表明这会误报 Markdown 表格匹配。

    Raises:
        SyntaxCheckFailure: 若同时出现 ``|`` 与 ``\\|``，极可能是方言混用
    """
    # 去掉 \| 后若还剩 |，说明两者同时出现 —— 方言混用的典型信号
    if r"\|" in pattern and "|" in pattern.replace(r"\|", ""):
        raise SyntaxCheckFailure(
            f"跨工具陷阱: {pattern!r} 同时含 | 与 \\|。"
            "Python re 中 \\| 是字面竖线（不是 or）；"
            "BSD grep basic 完全不支持 \\| alternation。"
            "建议 Python 侧统一用 |，shell 侧用 grep -E。"
        )

    # 可选：纯 \| 的警告（默认关闭，因实测会误报 Markdown 表格匹配）
    if warn_pure_escape and r"\|" in pattern:
        import warnings
        warnings.warn(
            f"模式 {pattern!r} 含 \\| 但无裸 |。在 Python re 中 \\| 是字面竖线，"
            "几乎总是想写 or的笔误。但它也可能是正当的字面匹配"
            "（如匹配 Markdown 表格竖线），故默认不报警。",
            SyntaxWarning,
            stacklevel=2
        )


def grep_pattern_safe(patterns: list) -> str:
    """把多个 pattern 拼成可在 BSD grep -E 下安全使用的 alternation。

    这是「跨工具陷阱」的正面解法：**统一用 -E + |**，
    不依赖 basic 模式的 \\| 语义。

    Args:
        patterns: 多个搜索模式

    Returns:
        可直接传给 ``grep -E`` 的模式串
    """
    escaped = [re.escape(p) for p in patterns]
    return "|".join(escaped)


def extract_code_patterns(source: str) -> list:
    """从源码中提取**代码区**的正则模式，跳过注释与 docstring。

    起因（架构师提出、设计师实测确认）：
    检查器不该检查解释它自己的文档。若不剥离 docstring，
    ``check_regex_dialect`` 会把说明陷阱的示例文本
    （如 ``a\\|b 与 a|b``）判为方言混用 —— **纯粹的误报**。

    同源问题（架构师指出）：emoji 检查器不检查 .py，
    因为 ``\\U0001F680`` 这类转义序列不是字面 emoji。
    两者的共同点是「盲区不只是『不检查什么』，
    也包括『不该检查什么』」。

    Args:
        source: Python 源码文本

    Returns:
        代码区字符串字面量列表
    """
    #剥离三引号块（docstring）
    no_doc = re.sub(r'\"\"\"[\s\S]*?\"\"\"', '', source)
    # 剥离 # 注释
    no_cmt = re.sub(r'#.*', '', no_doc)
    # 提取字符串字面量（支持单/双引号 + r 前缀）
    lits = (re.findall(r'r?\"([^\"]*)\"', no_cmt)
            + re.findall(r"r?'([^']*)'", no_cmt))
    return [s for s in lits if s]


def is_descriptive_text(literal: str) -> bool:
    """判断字符串字面量是否为**描述性文本**而非可执行正则。

    用于避免把错误提示文案误判为模式。例如::

        "跨工具陷阱: {pattern!r} 同时含 | 与 \\\\|。"
        "模式 {pattern!r} 含 \\\\ 但无裸 |。"

    这两条都是**给人看的提示**，但字符串里同时含 | 与 \\|
    —— 若不排除，`check_regex_dialect` 会报假阳性。

    判据：含格式化占位符（``{}``）、含中文说明词、或以
    「模式/规则/陷阱」等描述性词汇开头。

    Args:
        literal: 字符串字面量

    Returns:
        True 表示这是描述性文本，应跳过方言检查
    """
    # 格式化占位符 —— f-string / .format() 的强信号
    if "{" in literal and "}" in literal:
        return True
    # 说明性词汇
    desc_words = ("模式", "规则", "陷阱", "字面", "语义", "检查",
                  "字符类", "不支持", "解释", "含义")
    if any(w in literal for w in desc_words):
        return True
    # 含中文说明文字
    if re.search(r'[\u4e00-\u9fff]', literal):
        return True
    return False


def check_source_dialects(source: str) -> list:
    """扫描源码中**代码区**的正则，报告方言混用。

    这是 ``check_regex_dialect`` 的源码级封装，自动做了
    两层排除，避免误报：
    ①剥离 docstring 与注释（见 `extract_code_patterns`）
    ②排除描述性文本（见 `is_descriptive_text`）

    Args:
        source: Python 源码文本

    Returns:
        违规列表；每项是 (字面量, 原因)
    """
    violations = []
    for lit in extract_code_patterns(source):
        if r"\|" not in lit:
            continue
        # ① 排除描述性文本
        if is_descriptive_text(lit):
            continue
        # ② 正常检查
        try:
            check_regex_dialect(lit)
        except SyntaxCheckFailure as e:
            violations.append((lit, str(e)))
    return violations


# ---- AST 模式：精确区分「正则」与「说明文字」（v4.1）----

# re 模块的函数名—— 只有这些调用的首参才是正则
RE_FUNC_NAMES = frozenset({
    'compile', 'match', 'search', 'findall', 'finditer',
    'fullmatch', 'split', 'sub',
})


def check_source_dialects_ast(source: str) -> tuple:
    """AST 模式：只检查 ``re.*(...)`` 调用的**字面量**首参。

    **为什么值得做**（架构师提议、设计师实测确认）：

    启发式（`check_source_dialects`）要处理两类误报 ——
    docstring 与描述性文本。而这两类误报的**成因**是：
    检查器在扫描「所有字符串」，但真正该检查的只有「作为正则使用的字符串」。

    AST 解析天然区分二者：

    ===========================================  ================
    代码                                          AST 节点
    ===========================================  ================
    ``re.compile(r"a|b")``                       Call ->可检查
    ``"提示: {pattern} 同时含 | 与 \\|"``普通常量     -> 不可检查
    ===========================================  ================

    **这不是「增加能力」，而是「减少启发式依赖」** —— 第一类误报
    由解析器天然解决，启发式降级为 ``.sh`` 文件的唯一防线。

    **关于非字面量首参的处理**（架构师提问，设计师实测后否决 WARN）：

    架构师建议对「参数非字面量的 re.compile 调用」发 WARN。实测本项目：

    ==================  ==========  ================
    文件                re.* 调用   首参非字面量
    ==================  ==========  ================
    check_punct_spacing 3            2
    selftest_framework   12           5
    verify.py            12           2
    ==================  ==========  ================
    **合计**            **27**      **9（33%）**

    若每处都 WARN，将产生 9 条噪声 —— 而这 9 处多是
    ``re.compile(self.p)`` 这类**检查器自身的模式对象**，
    它们不可能有方言问题。

    **所以本实现选择：统计但不报警**（见返回值说明），
    仅当调用点显式标注了 ``# noqa: dialect-unchecked`` 时才提示。
    理由与PM 那句「一个总是误报的检查等于没有检查」一致。

    Args:
        source: Python 源码文本

    Returns:
        (violations, unchecked) 二元组：
        - violations: [(行号, 字面量, 原因)] —— 确认的方言混用
        - unchecked: [(行号, 节点类型)] —— 首参非字面量、**未被检查**的调用点
          （仅供人工审计，不自动报警）
    """
    violations = []
    unchecked = []

    try:
        tree = ast.parse(source)
    except SyntaxError as e:
        # AST 解析失败不应让整个检查崩溃
        return [(0, "<parse-error>", f"AST 解析失败: {e}")], []

    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue

        func = node.func
        if isinstance(func, ast.Attribute):
            fname = func.attr
        elif isinstance(func, ast.Name):
            fname = func.id
        else:
            continue

        if fname not in RE_FUNC_NAMES or not node.args:
            continue

        first = node.args[0]
        if isinstance(first, ast.Constant) and isinstance(first.value, str):
            try:
                check_regex_dialect(first.value)
            except SyntaxCheckFailure as e:
                violations.append((node.lineno, first.value, str(e)))
        else:
            # 首参非字面量 —— 记录但不报警（见 docstring 的实测依据）
            unchecked.append((node.lineno, type(first).__name__))

    return violations, unchecked


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
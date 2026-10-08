# 门禁使用说明

> 本文件说明四个门禁的职责边界与**正确使用方式**。
> 用错门禁和没有门禁一样危险 —— 假阴性（漏报）与假阳性（误报）都会让团队失去对工具的信任。

---

## 四个门禁的分工

| 门禁 | 覆盖对象 | 检查方式 |
| --- | --- | --- |
| `api-gate.sh` | Apple API 签名 | `swiftc -typecheck` 对真实 SDK 编译 |
| `security-gate.sh` | 明文 Key / 私有 API / 反模式认证 | 正则扫描 |
| `convention-gate.sh` | 单文件行数 / 状态管理 / 分层依赖 / F9 依赖方向 | 正则扫描 |
| `verify-docs.py` | 文档 P0 / JSON / 章节编号 / **跨文档引用** / ASCII 框线 | 结构化解析 |

**无重叠、无遗漏**：前三个扫 Swift 源码，第四个扫文档。

---

## 三条使用纪律

### 1. 门禁报错时，必须核对当前文件实际状态，不可直接转述给作者

**这是本项目最重要的使用纪律**，来源是一次真实的误报：

- 门禁报出 `DESIGN.md` 有 emoji
- 我据此发紧急告警给设计师，称文件被破坏
- **核实后发现**：那些问题在作者的 git HEAD 里就已存在，是作者自己的脚本副作用；我的测试残留为 0
- 误报的后果：作者若按告警去恢复，会用旧版本覆盖掉她刚完成的修复

**正确做法**：

```bash
# 报错后，先确认问题是否真实存在且未被并发修复
python3 scripts/verify-docs.py 2>&1 | grep <规则名>
git diff <文件>              # 看是否有未提交的并发修改
git show HEAD:<文件> | grep <同样的规则>   # 对比 HEAD 版本
```

若 HEAD 版本同样有问题，则问题来自作者本人，**应报告而非代改**。

### 2. 负向测试必须在临时副本上做，禁止在真实文件上注入违规后恢复

```bash
# 正确：--root 指向副本，真实文件零触碰
cp -R docs /tmp/t/docs && cp -R scripts /tmp/t/scripts
python3 scripts/verify-docs.py --root /tmp/t

# 错误：备份 -> 改原文件 -> 恢复（会吞掉测试期间的并行修改）
cp docs/X.md /tmp/bak; python3 -c "改 docs/X.md"; cp /tmp/bak docs/X.md
```

**「备份 + 恢复」不是隔离** —— 它假设文件静止，而团队里多人同时在改文档。`--root` 参数已为此提供。

### 3. 不代改他人负责的文档

架构侧只改 `ARCHITECTURE.md` / `decisions/ADR-*.md` / `VERIFIED-API.swift` / `scripts/*`。

`PRD.md` 属产品侧、`DESIGN.md` 属设计侧。发现问题应**报告并附行号**，由作者决定修改时机。

例外：机械可检出的问题（如 emoji）可先报告，若作者长时间未处理再由主理人裁定。

---

## WARN 与 FAIL 的区别

| 级别 | 含义 | 行为 |
| --- | --- | --- |
| **FAIL** | 确定性违规，阻断 | CI 红，必须修复 |
| **WARN** | 疑似问题，需人判断 | CI 绿，但列出待确认 |

`verify-docs.py` 当前把 **ASCII 框线不完整** 标为 WARN —— 因为修改 `DESIGN.md` 的时机属于设计侧，架构侧只报告不阻断。

---

## 新增检查项的要求

任何新增检查必须：

1. **先做负向测试**：在 `/tmp` 副本上注入违规 -> 确认拦截 -> 确认干净副本通过
2. **确认不是假阴性**：BSD grep 不支持 `\s` / `\d`，basic 模式不支持 `\|`。正则若未在 BSD 环境下验证，会静默失效（返回 PASS 但抓不到违规）—— 这是本项目踩过的坑
3. **确定 FAIL / WARN 归属**：能否用门禁自动检出的用 FAIL（先做），需靠人判断的用 WARN（后做）

---

## 当前状态

```
api-gate         PASS（零错误零警告）
security-gate    PASS
convention-gate  PASS
verify-docs      PASS（81 WARN，全在 DESIGN.md 的 ASCII 框线，作者自行处理中）
```

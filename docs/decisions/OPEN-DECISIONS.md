# OPEN-DECISIONS 登记册

> 铁律：只追加 + 就地关闭（OPEN → RESOLVED，补Resolution 字段）
> 每次 Phase 开始时，把未决项复现到工作上下文最前面

| Date | Source | Open Item | Related Constraints | Current Leaning | Blocked By | Resolves When | Status |
|------|--------|-----------|---------------------|-----------------|------------|---------------|--------|
| 2026-10-08 | Phase 1 | **API Key `<REDACTED_API_KEY>` 已泄露**（旧 Key 已吊销，值已脱敏，本文件不再记录原文） | 该 key 硬编码在 git tag 1.2 (a8cdcaf) 的 QueryParameter.swift:56，仓库 https://github.com/Laxse/IHaven 为公开仓库（HTTP 200），已随提交推送至 GitHub | **必须立即吊销并重新生成**；新代码库禁止任何明文 Key 常量，认证一律走 X-API-Key 请求头 | 用户需登录 wallhaven.cc 账户 Settings 页重新生成 |用户重新生成 Key 后 | OPEN |

---

## P0 安全事故记录

### 泄露详情
- **泄露内容**：wallhaven API Key `<REDACTED_API_KEY>`（旧 Key 已吊销，值已脱敏，本文件不再记录原文）
- **泄露路径**：`IHaven/Resource/WallHaven/QueryParameter.swift:56` 硬编码明文常量
- **暴露面**：GitHub 公开仓库 `Laxse/IHaven`，提交 `a8cdcaf`（tag 1.2）
- **二次泄露面**：旧代码通过 URL query 参数传递（`result["apikey"] = apikey`），会进入 URL 日志、代理日志、HTTP Referer 链
- **可利用性**：攻击者可用该 key 访问 NSFW 内容、消耗用户 API 配额（45次/分钟）、读取用户账号设置

### 立即行动项（用户执行）
1. 登录 https://wallhaven.cc/account/settings → 找到 API key 区域 → **重新生成（regenerate）**，旧 key 立即失效
2. 新 key 只需填入新软件的设置界面，**不要写进任何代码文件**
3. 新代码库通过 CI 门禁扫描，禁止明文 Key 常量

### 架构约束（已传达给架构师）
- 认证统一走 `X-API-Key` 请求头，**禁止 URL query 传递**（官方文档明确支持 header 方式且更安全）
- Key 存储~~用 macOS Keychain~~，**禁止 UserDefaults / plist / 硬编码** —— **2026-10-11 变更，见 ADR-010**
- 建议加 `.gitignore` 与 pre-commit hook 扫描 Key 模式

---

## 约束变更登记（2026-10-11，ADR-010）

**变更项**：上述「Key 存储用 macOS Keychain」一条。
**变更为**：`~/.ihaven/apikey`，目录 `0700` / 文件 `0600`，实现 `FileKeyProvider`（`Infrastructure/Security/FileKeyStore.swift`）。`KeychainStore.swift` 保留不删。

**变更理由（摘要，完整论证见 ADR-010）**：本地构建为 ad-hoc 签名（无 team identifier，designated requirement 基于 CDHash），每次重建 CDHash 都变，钥匙串 ACL 的「始终允许」无法命中 → 每次启动弹授权框；`kSecUseDataProtectionKeychain` 对 ad-hoc 二进制返回 -34018。这是签名属性，非代码缺陷，换存储是唯一能立刻消除弹窗的路径。

**未放宽的部分（仍然硬性）**：认证走 `X-API-Key` 头、禁止 URL query、禁止硬编码、禁止 UserDefaults / plist、禁止 Key 落日志。`security-gate.sh` 相应规则全部保留且通过。

**新增风险**：Key 明文落盘，同用户任意进程可读。已接受——危害面为「访问 NSFW、消耗 45 次/分钟配额、读取账号设置」，无资金路径与敏感 PII；且 P0 的实质危害（Key 进 git / 进 URL）在仓库外存储下被物理切断。

**回切条件**：构建带上稳定 Developer ID 签名，或本地自签身份固定 CDHash。满足即改 `IHavenApp.swift:5` 一行回 `KeychainKeyProvider`。

---

## 决策变更登记（2026-10-11，ADR-011）

**变更项**：筛选面板纯度分组的 NSFW 档位门禁——线稿 `docs/wireframes/filter-panel.svg` 原设计为「NSFW 灰置不可点」，并规划了三层门禁原因（需要密钥 · 未配置 / 需要开启 NSFW（L2）· 已关闭 / 需要开启本次可见（L3）· 已关闭）与「打开密钥设置」路由。
**变更为**：NSFW 不再做任何权限门禁，与全年龄、轻微暗示两档完全等价，三档一律可自由切换；默认档仍为 `PurityFilter.browseDefault`（全年龄 ON / 轻微暗示 ON / NSFW OFF，`Core/Models/Query.swift`）。

**变更理由（摘要，完整论证见 ADR-011）**：三层门禁里 L2 需要设置页承载、L3 需要菜单栏面板承载，MVP 阶段这两个界面都不存在，档位会被永久灰置——「灰置但永远点不开」呈现的是坏掉的功能而非范围外功能，比不做门禁更糟；探测本身消耗 API 配额，且其失败态（网络错误 / 配额耗尽 / 401）在 UI 上难以与「无权限」区分，会产生误导性提示；产品已明确要求不加限制。

**配套删除（死代码）**：`probeNSFWPermission()`（`Core/Protocols/WallhavenAPI.swift` 协议声明 + `Infrastructure/Network/WallhavenClient.swift` 实现）与结果类型 `NSFWProbeResult` 已一并删除，全仓库无残留引用。删除后 `WallhavenAPIProtocol` 仅剩 `search(_:)` 与 `keyStatus`。

**文档取代关系**：线稿 `filter-panel.svg` 纯度分组的灰置说明与三层门禁 hover 文案**已被 ADR-011 取代**。后续若重新引入门禁，应以 ADR-011 为起点，不得直接照抄线稿。

**未放宽的部分（仍然硬性）**：认证走 `X-API-Key` 请求头（不回退 query）；禁止用 `/settings` 验证 Key；禁止用响应里的 `data.purity` 判断 NSFW 权限（Trap 14 / 15 / 17）。这三条的本质是「不得依赖错误信号源」，与「不门禁」正交，全部保留。

**新增风险**：失去「防止用户在不知情下打开 NSFW」的提示层；将来重新引入门禁需重建探测基础设施。两项均已接受，见 ADR-011「负面」小节。
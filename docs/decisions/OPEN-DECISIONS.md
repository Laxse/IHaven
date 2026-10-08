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
- Key 存储用 macOS Keychain，**禁止 UserDefaults / plist / 硬编码**
- 建议加 `.gitignore` 与 pre-commit hook 扫描 Key 模式
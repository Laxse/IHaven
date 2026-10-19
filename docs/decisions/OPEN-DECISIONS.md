# OPEN-DECISIONS 登记册

> 铁律：只追加 + 就地关闭（OPEN → RESOLVED，补Resolution 字段）
> 每次 Phase 开始时，把未决项复现到工作上下文最前面

| Date | Source | Open Item | Related Constraints | Current Leaning | Blocked By | Resolves When | Status |
|------|--------|-----------|---------------------|-----------------|------------|---------------|--------|
| 2026-10-20 | #70 多厂商直连 | **AI 多厂商直连：六套协议全部未真机验证** —— 6 家的鉴权头 / 底图入参形状 / 轮询语义 / 输出形态均按各家公开文档整理，无一家用真 Key 跑通过 | ADR-019（原「走 Replicate 聚合层」结论已被推翻）；是否需要图床取决于各家是否接受 base64 / data URI 底图，另有同事在核，结论回填本条目 | 保持现状：目录与策略骨架照常落地，不因未验证而阻塞 | 没有这六家的 Key，且每家都要绑卡 / 充值才能出结果 | 用户拿到某家 Key 并真机跑过后，把该家的实际请求体与响应形状回写 ADR-019 与对应策略文件注释（逐家独立结算） | OPEN |
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

---

## 决策变更登记（2026-10-14，ADR-012）

**变更项**：ADR-011 结论中的「NSFW 档与另两档完全等价、一律可自由切换」这一条交互形态。
**变更为**：NSFW 档默认锁定（不可勾选，`opacity 0.45`），由**本机意愿开关**解锁——设置面板新增「内容」页签，开关文案「允许成人内容（NSFW）」，说明「默认关闭。开启后，筛选面板的 NSFW 档位才允许勾选，结果中可能包含裸露、暴力或色情等不适合在工作场合浏览的内容。」锁定态 chip 被点击时打开设置并直达「内容」页签；开关从开拨到关时收回已勾选的 NSFW 档并重查（`BrowseViewModel.disableNSFWIfNeeded()`）。开关存 `UserPreferenceKey.nsfwAllowed`（UserDefaults `ihaven.nsfwAllowed`），默认 `false`。

**变更理由（摘要，完整论证见 ADR-012）**：ADR-011 否决门禁的两条理由都绑定在「服务端探测」上（吃配额、失败态被误报成无权限），而本次的门是一次本地布尔读值，零请求、无失败态，两条理由都不触及；ADR-011 判定线稿方案不可接受的直接原因（设置页与菜单栏面板不存在 → 无处解锁）也随设置面板落地而消失。门的性质从「权限门禁（你配不配看）」换成「意愿门禁（你想不想看）」，与 ADR-011 确立的「可见性由使用者自己决定」定位一致，并补回了 ADR-011 自认丢失的「防止在不知情下打开 NSFW」提示层。

**未放宽的部分（仍然硬性）**：`probeNSFWPermission()` 与 `NSFWProbeResult` 不重建；Trap 15 / 17 继续生效；`PurityFilter` 取值与 `purity` 串下发逻辑一字未改。本次只改 UI 层是否允许勾选，不新增任何对账号权限的推断。

---

## 决策变更登记（2026-10-14）：「设为屏保」被再次提出并**维持不做**

**背景**：用户在详情页需求中再次要求「设置为壁纸 / 屏保」，而 `docs/PRD.md` 第九节「明确不做的事」已把「屏保（Screen Saver）整合」列为 Out-of-Scope。该裁定因此被重新审视一次，**结论是维持不做**（用户确认）。

**本次核实到的新事实（完整存档见 `docs/VERIFIED-SCREENSAVER.md` 与 ADR-007 Trap 20）**：

1. **macOS 14 起已不存在单张图形态的屏保**。系统自带屏保全部是 ExtensionKit `.appex` 动画播放器 + 一个 `Photos` 幻灯片；幻灯片屏保的配置粒度是**目录**（`SelectedFolderPath`）而非单文件。历史上唯一能枚举/选择屏保模块的公开类 `ScreenSaverModule.h` 已从 SDK 移除。
2. **历史 defaults 路径（写 `com.apple.screensaver moduleDict` / `com.apple.ScreenSaverPhotoChooser`）在 14+ 已失效**。Apple DTS 明确回复「no longer consults these (undocumented) user default settings」；本机实测写入可读回、但屏保不生效、系统对该 plist 零回写，`ScreenSaverEngine` 也无法被外部手动拉起。若照此实现并宣称成功，就是「点了没反应」的半功能。
3. **macOS 26/27 确有「把当前桌面壁纸当作屏保」的一等公民开关**（`Show wallpaper as screen saver`，App Intent 里也有 `ScreenSaverModel` / `changeTheScreenSaver`），语义上正好是「单张图当屏保」。但**没有任何公开 API 可写该开关**，第三方 app 也无法执行别的 app 的 App Intent；间接路径（AppleScript 调 Shortcuts Events）需 Automation 授权，且在 ad-hoc 签名下每次重签都会让已授予的授权失效 → 用户被反复弹窗。因此只能引导，不能自动。
4. 私有路径（改写 `com.apple.wallpaper` Store、私有 XPC）需要 `com.apple.private.wallpaper` 权限，ad-hoc 签名绝无可能，且 `WallpaperExtensionKit` 被 `scripts/security-gate.sh` 显式禁止。

**裁定**：详情页操作区只提供「设为壁纸」（主）与「下载原图」（次）两个动作，**不提供任何屏保按钮**。PRD 第九节那一条 Out-of-Scope 记载继续有效。

**重新评估的触发条件**（满足其一即可再议）：①Apple 提供设置屏保 / 该开关的公开 API；②出现不依赖私有权限且不触发 TCC 弹窗的可靠写入路径；③`~/Pictures` 等目录的 TCC 约束被解除，使得「复制素材 + 引导」的成本降到可接受。

**新增风险**：失去「防止用户在不知情下打开 NSFW」的提示层；将来重新引入门禁需重建探测基础设施。两项均已接受，见 ADR-011「负面」小节。
---

## 决策变更登记（2026-10-18）：PRD:697「本地项并入瀑布流」被**否决撤销**

**背景**：用户反馈「本地栏的图片都追加到了其他浏览页签内容的末尾」。PRD:697 要求「导入的图片与
网络壁纸在同一瀑布流展示，本地项有可区分标识」，ADR-015 §四 据此落地了 `WallpaperGridItem`
枚举包装。用户明确否决该设计：本地文件不该出现在浏览页签里，也就不需要「本地」标识去解释它。

**否决的三条实质理由**：

1. **混入范围与检索语义冲突**。风景 / 动漫 / 人物 是明确的 wallhaven 分类 + 关键词检索
   （`BrowseView.applyCategory` 下发 `q=nature` 等），本地文件与这些查询毫无关系 —— 混进去
   等于污染检索结果。
2. **位置不可达**。网络结果无限翻页累加，本地项拼在末尾会被越推越远，翻两页后就滚不到了，
   等于没展示；挪到最前则又变成「为什么要先看到我自己的图」。
3. **本地项已有专属入口**。「导入…」页签提供了完整的导入 / 设为壁纸 / 裁剪 / 删除管理，
   瀑布流里再塞一份是重复，且还要额外挂标识 —— 需要额外解释的存在本身说明设计不对。

**裁定**：

- 瀑布流（`browseSearchContent`）只渲染 `viewModel.wallpapers`，即 `[Wallpaper]`；
- `WallpaperGridItem` 枚举、`BrowseView.gridCard` 的 `.local` 分支、`setLocalWallpaper`
  一并删除（不保留死代码）。`Wallpaper` 本身即 `Identifiable`，无需包装类型；
- 本地导入项只在「导入…」页签管理。

**顺带修正**：`browseSearchContent` 的空态判断由 `viewModel.wallpapers.isEmpty` 改为
`gridItems.isEmpty`。两者当前等价，但判空应基于「实际要渲染的内容」而非某个数据源 ——
这是「判后者导致明明有内容可画却显示假空态」这一类 bug 的通防。

**重新评估的触发条件**：①出现「本地壁纸与检索结果一同浏览」的真实使用场景（例如本地库
支持分类 / 标签，使其能被同一套筛选语义命中）；②用户主动要求恢复混排。届时从 git 历史
找回 `WallpaperGridItem` 即可，本条目同步作废。

---

## 决策变更登记（2026-10-20）：AI 多厂商直连 —— 六套协议全部未真机验证（OPEN）

**背景**：ADR-019 于 2026-10-20 推翻了「走 Replicate 聚合层」的原结论，改为**直连六家模型厂商**
（Google Veo / MiniMax 海螺 / 生数 Vidu / 阿里百炼万相 / 火山方舟 Seedance / 快手可灵），每家
一把自己的 Key、一个自己的策略实现（`Infrastructure/Network/AIVendor/`）。本条目登记随之产生的
未决风险，不推翻任何既有决策。

**风险本体**：六家的**鉴权头 / 底图入参形状 / 轮询语义 / 输出形态**全部是按各家公开文档整理的，
**没有任何一家用真 Key 跑通过**。首次真机跑大概率会栽在字段名或底图格式上 —— 这不是猜测：
聚合层时代就栽在「底图入参键名」上（`image` / `start_image` / `first_frame_image` 各家不同），
**一个键名就是一次 422**，而 422 的服务端 detail 往往是唯一能定位问题的线索。

**为什么现在不验证**：没有这六家的 Key，且每家都要绑卡 / 充值才能出结果。在没有 Key 的前提下
任何「验证」都只是把文档再读一遍，不产生新信息。

**触发条件与动作**（逐家独立结算，不必等六家齐活）：

1. 用户拿到某家的 Key 并**真机跑通** —— 把该家的实际请求体（鉴权头、底图字段与 `data:` 前缀
   规则）与响应形状（任务标识形态、轮询路径、终态字段、视频 URI 在 JSON 的哪一层）回写到
   ADR-019「已知代价 / 首次真 Key 首验清单」一节与对应策略文件的文件头注释里，并把该家从本条
   目的未验证清单中划掉。
2. 真机跑**失败** —— 把服务端错误信息贴进对应策略文件的注释（`AIVideoError.requestRejected`
   已把服务端 detail 带出来，是可直接引用的原文），照它改实现后重跑；**不要凭文档猜字段名改
   代码** —— 那正是聚合层时代踩坑的方式。
3. 目录里那行「约 $x/秒」的价格与规格文案来自公开页面而非实测账单，**会漂移**，首验后按实际
   账单回写 `AIVideoVendor.swift`。

**是否需要图床（未决，挂在另一条线上）**：取决于各家是否接受 base64 / data URI 形式的底图 ——
接受则底图随请求体一起发，不需要图床；不接受则要先上传换 URL，需要一处临时图床，并会引入
「图床可用性 / 产物清理 / 隐私」的一整包新问题。该结论另有同事在核，**结论出来后回填到本
条目**；在此之前本条目下不做任何图床相关决策。

**未放宽的部分（仍然硬性）**：成本护栏不变 —— 每次生成前一次确认弹窗、设置页明示计费与网络
要求、客户端绝不自动重试连打。**未验证不等于可以放开重试**：自动重试会把一次 422 变成 N 次
计费，而错误信息还不会指向真正的原因。

**状态**：`Open`（2026-10-20）。

### 首验进展（2026-10-19 晚）

**火山方舟：已端到端跑通**（`doubao-seedance-1-0-pro-fast-251015`，用户真 Key）。
提交 → 轮询 30s → `content.video_url` 取到视频，1080p / 5s / 24fps，246,840 tokens。
【图床那条已部分结案】**底图用 `data:image/jpeg;base64,…` 传被接受**，本 App 不需要图床。
另确认方舟 model id 必须带日期后缀、且**充值 ≠ 开通**（未开通报 404 `ModelNotOpen`）。

**快手可灵：端点与鉴权已确认**。静态长钥 `Bearer` 即可过鉴权，「要 AK+SK 现签 JWT」的猜测不成立；
账户余额为 0 时返回 `HTTP 429 code:1102`。请求体形状仍未验（余额为 0 的账户在校验请求体前被挡）。

**仍未真机触碰**：Google Veo / MiniMax / Vidu / 阿里百炼四家。
**已知未修的小坑**：方舟要求底图短边 ≥ 300px（`400 InvalidParameter — expected the height to be
at least 300px`）；`jpegForAPI` 目前只缩不放，源图过小时会被拒。

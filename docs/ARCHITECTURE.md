# IHaven 技术架构文档

版本：1.0
状态：Accepted
适用：IHaven macOS 客户端（全新重写）
工具链锚定：Xcode 27.0（build 27A266a）、Swift 6.4（swiftlang-6.4.0.34.1）、macOS 27.0 SDK、部署目标 macOS 26.0

---

## 0. 阅读须知：本文件的核验方式

本文件所有 Apple API 签名均通过 `swiftc -typecheck` 对真实 SDK（`MacOSX.sdk` -> `MacOSX27.0.sdk`）编译核验，核验样本存档于 `docs/VERIFIED-API.swift`（零错误零警告）。

这不是形式主义。核验过程中编译器抓出了6 个凭直觉写就会错的签名，记录在 `docs/decisions/ADR-007.md`。任何人扩写本文档中的 API 调用前，应先跑一次编译核验。

复现命令：

```bash
swiftc -typecheck -sdk "$(xcrun --show-sdk-path)" \
  -target arm64-apple-macosx26.0 docs/VERIFIED-API.swift
```

---

## 1. 环境现状与P0 阻塞项

### 1.1 已确认可用

| 项 | 值 | 核验方式 |
| --- | --- | --- |
| 操作系统 | macOS 26.6.2 (25G83) | `sw_vers` |
| 架构 | arm64（Apple Silicon） | `swift -e` target |
| Xcode | 27.0 (27A266a)，bundle 25183.107.5 | `Info.plist` |
| Swift | 6.4 (swiftlang-6.4.0.34.1) | `swift --version` |
| SDK | MacOSX27.0.sdk（Xcode 侧）、MacOSX26.5.sdk（CLT 侧并存） | `ls SDKs` |

### 1.2 P0 阻塞：xcode-select 指向 CommandLineTools

`xcode-select -p` 返回 `/Library/Developer/CommandLineTools`，导致任何 `xcodebuild` 调用直接失败：

```
xcode-select: error: tool 'xcodebuild' requires Xcode, but active developer
directory '/Library/Developer/CommandLineTools' is a command line tools instance
```

这只影响命令行。Xcode.app 本身完整（内含 `MacOSX27.0.sdk`），GUI 内构建不受影响；但 CI、命令行构建、以及任何以 `xcodebuild` 为入口的自动化门禁全部不可用。

修复方式（需用户执行，涉及 sudo）：

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
```

在修复前，本项目的「构建即验证」门禁只能以`swiftc -typecheck` 形式在单文件层面执行，无法做整工程构建验证。这是当前最优先的环境事项。

### 1.3 P0 约束：Xcode 27 仅支持 Apple Silicon

Xcode 27 安装与运行均要求 Apple Silicon。本机满足。团队若有 Intel 机器，无法参与本项目构建。

ARCHS 默认行为变更：`MACOSX_DEPLOYMENT_TARGET >= 27.0` 时 `ARCHS_STANDARD` 丢弃 x86_64。本项目部署目标为 macOS 26.0，暂不触发该行为；且 PRD 已明确 Intel 为Out-of-Scope。

### 1.4 Debug 签名沿用既有结论

沿用仓库既有结论（commit 3ff48da）：Debug 用ad-hoc 签名（`CODE_SIGN_IDENTITY = "-"`）。App Sandbox + 开发者证书 + 无 profile 会在 macOS 26 下 SIGTRAP。

注意：动态壁纸需要窗口层级与跨 Space 行为，App Sandbox 下是否受限尚未验证，见 §5.7。

---

## 2. 技术选型总表

| 领域 | 选定方案 | 版本 | 一句话理由 |
| --- | --- | --- | --- |
| UI 框架 | SwiftUI | SDK 内置 | 团队已用；macOS 26 原生控件齐备 |
| 状态管理 | Observation（`@Observable`） | SDK 内置 | 与 `@Environment` 一致，无 `ObservableObject` 混用 |
| 最低部署目标 | macOS 26.0 | — | PRD 硬约束 |
| 架构 | arm64 only | — | PRD 硬约束 |
| 并发模型 | Swift 6 严格并发 + async/await | Swift 6.4 | 语言级数据竞争检查 |
| 图片加载 | Nuke + NukeUI | 13.2.0 | 见 §3.1 |
| 本地存储 | GRDB.swift | 7.11.1 | 见 §3.2 |
| 密钥存储 | Security.framework (Keychain) | SDK 内置 | 见 §3.3 |
| 图标 | SF Symbols | SDK 内置 | 见 §3.4 |
| 网络 | URLSession + async/await | SDK 内置 | 见 §6 |
| 动态壁纸 | AVFoundation + 独立 XPC helper | SDK 内置 | 见 §5 |
| 视频导出 | AVAssetExportSession (HEVC) | SDK 内置 | 见 §5.6 |

依赖总数：2 个第三方库（Nuke 13.2.0、GRDB 7.11.1）。两者均为 SPM、MIT/Apache-2.0、无传递依赖（Nuke 无 package dependencies）。

---

## 3. 关键选型对比矩阵

### 3.1 图片加载方案（最关键决策）

评估维度按team-lead 要求：内存控制、磁盘缓存、LRU、预取、性能、Swift 6 并发安全、维护活跃度。

| 维度 | Nuke 13.2.0 | SDWebImageSwiftUI 3.1.4 + SDWebImage 5.21.7 | 自研 URLSession + NSCache |
| --- | --- | --- | --- |
| 内存控制 | 内建`ImageCache` +按物理内存动态计算上限 | 内建 `SDImageCache`，成熟 | 需自建，NSCache 无成本感知 |
| 磁盘缓存 | 内建，LRU 淘汰 | 内建，LRU 淘汰 | 需自建 LRU（成本最高项） |
| LRU | 内建 | 内建 |需自建 |
| 预取 | `ImagePrefetcher`（priority-aware、并发受限） | `SDWebImagePrefetcher` | 需自建并发控制 |
| Swift 6 并发 | **全局 `ImagePipelineActor`**，编译器强制线程安全，13.0 起移除 20 处 `@unchecked Sendable` | ObjC 桥接，`Sendable` 语义靠注解 | 需自行保证，易漏 |
| 取消语义 | 类型化 `throws(ImagePipeline.Error)`，含 `.cancelled` | 回调 + `SDInternalOperation` | 需自建 |
| SwiftUI 适配 | `NukeUI.LazyImage` | `WebImage` / `AnimatedImage` | 需自写 |
| 解码压缩 | 后台队列解压，可配`maximumDecodedImageSize` | 后台解压 | 需自建，否则滚动卡顿 |
| 请求合并 | 内建（同 URL 合并为一次下载） | 内建 | 需自建 |
| 维护活跃度 | 13.2.0 / 2026-08-15；13.x 仍在迭代 | 5.21.7 / 2026-02-26；补丁级维护 | — |
| 最低要求 | Swift 6.2、Xcode 26、macOS 12 | 更低，但Swift 6 适配非其主战场 | — |
| 代码量| 4,669 行（含 96% 测试覆盖） | 更大（ObjC 核心 + 多模块） | 预估 800-1200 行自研 + 长期维护 |
| 测试时间 | 1.3s（并行化后） | — | — |

**选定：Nuke 13.2.0（`Nuke` + `NukeUI` 两个product）。**

理由：

1. 全局 `ImagePipelineActor` 是决定性因素。本项目要求 Swift 6 严格并发，Nuke 13 把线程安全变成编译器可验证的事实，而非代码评审时的口头约定。这与 `generated-code-failure-modes` 里「沉默逻辑错误最致命」直接对应 —— 图片管线的竞态是典型的静默错误（偶发错图、偶发崩溃），最难靠测试抓。
2. 瀑布流的核心压力是「大量并发解码 + 快速滚动取消」。Nuke 的 priority-aware 预取队列与类型化取消正好对上这个压力。
3. 自研方案在 LRU + 并发上限 + 请求合并 + 后台解压四项上都要重新踩坑，且这些坑全属静默错误类。按 MVP 不做过度设计的原则，这是明确的负收益。

**注意 Nuke 13.0.3 的行为变更**：自动降采样实现已移除，`ImagePipeline.Configuration.maximumDecodedImageSize` 与 `ImageDecodingContext.maximumDecodedImageSize` 已废弃且设置无效。缩略图尺寸必须走 `ImageRequest.ThumbnailOptions` 按请求控制，不要依赖全局配置。

**放弃 SDWebImage 的原因**：不是它不好，而是它的核心是 ObjC + category 体系，在纯 Swift + Swift 6 严格并发项目里我们拿不到编译器的并发保证，只能靠注解与人工评审。同时它默认只注册 GIF 与 APNG 动画 coder，WebP 需额外依赖 `SDWebImageWebPCoder`（独立仓库、独立版本），对 wallhaven 的 WebP 素材是额外供应链面。

**降级预案**：若 Nuke 13.2.0 在 Xcode 27.0 上出现兼容问题，回退到 Nuke 12.9（Swift 5.7+，已开启 Swift 6 支持，去除 Combine 依赖）。不使用自研。

### 3.2 本地存储

| 维度 | GRDB.swift 7.11.1 | SwiftData | Core Data |
| --- | --- | --- | --- |
| 底层 | 直接 SQLite，SQL 是一等公民 | 不透明 | 不透明 |
| Swift 6 | 7.0 起全 API 严格并发，公开类型审计 Sendable | `@ModelActor` 的 Sendable 问题在 Xcode 16.x 仍有未决 thread | CoreData 在 macOS 26 SDK 调整了 Sendable 注解以兼容 MainActor 默认隔离 |
| 并发模型 | `DatabaseQueue`（串行）/ `DatabasePool`（WAL，读者池 + 独立写者） | Model actor | `NSManagedObjectContext` 按队列 |
| 响应式 | `ValueObservation` -> async sequence，直接喂 `@Observable` | `@Query` | `NSFetchedResultsController` |
| 迁移 | 手写、显式、版本化 | 托管 | 托管 |
| 学习曲线 | 中（要按表想，不是对象图） | 缓 | 陡 |
| 关系 | `belongsTo` / `hasMany` 展开为 JOIN | 对象图 | 对象图 |

**选定：GRDB.swift 7.11.1，配置 `DatabasePool`（WAL 模式）。**

理由：核心判据是 Swift 6 严格并发下的可验证性。GRDB 7 的公开 API 全量 Sendable 审计 + 编译器强制；Core Data 在 macOS 26 SDK 里刚改过 Sendable 注解以迁就 MainActor 默认隔离，说明这块仍在动；SwiftData 的 `@ModelActor` Sendable 问题有公开未决讨论。选 GRDB 是选「把并发正确性交给类型系统」而不是「信任框架的文档约定」。

`DatabasePool` 而非 `DatabaseQueue`：瀑布流浏览时读多写少，WAL 读者池能让并发读不排在写者后面。

**各数据归属**：

| 数据 | 存放| 理由 |
| --- | --- | --- |
| 收藏集、收藏分组、标签 | GRDB `favorites` / `collections` 表 | 需要检索、分组、批量操作、跨屏同步，关系型最自然 |
| 下载/导入记录、应用历史 | GRDB `wallpaper_history` 表 | 与收藏库物理隔离（PRD F6 明确要求「与应用历史分离」） |
| 多屏配置（逐屏壁纸分配） | GRDB `display_assignments` 表 | 需要按displayID 索引与持久化，UserDefaults 不适合结构化查询 |
| 用户设置（非敏感） | `@AppStorage` / `UserDefaults` | 键值对，读写频繁、无需查询、单条更新 |
| API Key | **Keychain**（`kSecClassInternetPassword` 或 `kSecClassGenericPassword`） | 绝不入 UserDefaults / SQLite / 日志 |
| 图片二进制 | 磁盘（`Application Support/Wallpapers/`），DB 只存路径 | SQLite 存BLOB 会让 DB 膨胀、查询变慢、备份成本高 |

**迁移策略**：`dbMigrator` 显式版本化，每个 schema 变更一个 `migrate` 分支。GRDB 7 的 `DatabasePool` 支持在线迁移（` migrator.migrate(pool)`）。

**全文检索**：MVP 不需要。收藏集检索先用 `LIKE` + 索引；数据量若逼近 1 万条再评估 FTS5（GRDB 内建 FTS 支持）。不要提前优化。

### 3.3 API Key 存储

Keychain，`kSecClassGenericPassword`，`kSecAttrService = "com.ihaven.apikey"`，`kSecAttrAccount = "wallhaven"`。

- `kSecAttrAccessibleWhenUnlocked`：锁屏时不可读，避免后台任务在锁屏期间拿到明文 Key。
- 读取用 `SecItemCopyMatching`，写入用 `SecItemAdd` / `SecItemUpdate`。
- 绝不写日志、绝不进 UserDefaults、绝不放进 SQLite。埋点只记录 `has_key` 布尔值（PRD 埋点方案已定）。
- Debug 构建读取失败时返回明确错误，不静默吞掉。

### 3.4 图标库：锁定 SF Symbols

**选定：SF Symbols（系统原生，零依赖）。**

| 候选 | 评估 |
| --- | --- |
| SF Symbols | 系统原生、零依赖、macOS 11+ 全覆盖、自动适配浅色/深色与 Dynamic Type、macOS 26 下有 Tahoe 风格变体 |
| 自带 SVG 资源包 | 需手工维护上千图标、需自建深色变体、体积膨胀、无法跟随系统语义 |
| Lucide / Heroicons（web） | 面向 Web 的 24px 网格与 stroke 风格，与 macOS 26 视觉语言不匹配 |

反对意见预判：有人会认为 SF Symbols 样式单一不适合品牌化。反驳：PRD 明确「Apple官方级品质」定位，SF Symbols 是与该定位唯一一致的选择。若未来确需品牌化图标，应作为独立资源包叠加，而不是替换系统图标体系。

**硬规则**：全项目统一 SF Symbols，禁止混入任何其他图标库或 emoji 作为功能图标。AppIcon（应用图标）由设计侧用 Icon Composer 制作，属独立资产，不受此规则约束。

---

## 4. 分层架构

```
+----------------------------------------------------------------+
|  Presentation (SwiftUI)                                        |
|  MainWindow / MenuBarPanel / Editor / Settings                |
|  仅依赖 Feature 层；不直接触碰 DB / Network / Wallpaper       |
+----------------------------------------------------------------+
|  Feature (按用户能力切分)                |
|  Browse / Favorites / Filter / Assign / Editor / KeyConfig     |
+----------------------------------------------------------------+
|  Domain (纯值类型 + 协议，无 UIKit/DB 依赖)                |
|  Wallpaper / WallpaperFilter / DisplayAssignment / KeyProvider  |
+----------------------------------------------------------------+
|  Infrastructure (可替换实现)                                   |
|  Database (GRDB) / WallhavenAPI (URLSession) /                 |
|  ImagePipeline (Nuke) / KeychainStore / WallpaperEngine /     |
|  VideoExporter / Telemetry                                     |
+----------------------------------------------------------------+
|  Platform (系统能力封装)                                       |
|  WallpaperEngine (AVFoundation + 窗口) / ScreenWatcher         |
+----------------------------------------------------------------+
```

依赖方向严格单向向下。Feature 层不得跨层调用 Infrastructure 的具体实现，只依赖 Domain 协议。这样测试可用内存实现替换数据库与网络（F7 的离线兜底测试依赖这一点）。

### 4.1 代码组织（单文件 <= 300 行硬约束）

```
IHaven/
  App/
    IHavenApp.swift              应用入口，只做装配
    AppDelegate.swift生命周期
    AppEnvironment.swift         依赖注入容器
  Core/
    Models/                纯值类型（Wallpaper / Filter / Assignment）
    Protocols/             领域协议定义
    Extensions/
  Features/
    Browse/           瀑布流（每个文件 <= 300 行，超出即拆）
    Favorites/
    Filter/
    Assign/                多屏分配
    Editor/                动态壁纸编辑器（V3）
    Settings/
  Infrastructure/
    Database/
      Database.swift         DatabasePool 装配
      Migrations.swift       显式版本化迁移
      WallpaperRepository.swift
      FavoritesRepository.swift
      AssignmentRepository.swift
    Network/
      RateLimiter.swift  令牌桶
      WallhavenClient.swift
      APIError.swift
      Endpoints.swift
    Image/
      ImagePipeline.swift   Nuke 配置
      ImagePrefetcher.swift
    Security/
      KeychainStore.swift
    Telemetry/
      Telemetry.swift
  Platform/
    Wallpaper/
      WallpaperEngine.swift  协议
      SystemWallpaperEngine.swift  静态壁纸（NSWorkspace）
      DynamicWallpaperEngine.swift  动态壁纸（AVFoundation）
      WallpaperWindow.swift          桌面层窗口
      DynamicWallpaperService.swift  XPC helper（V2）
    Screen/
      ScreenWatcher.swift
      DisplayTopology.swift
    Media/
      VideoExporter.swift
      VideoFormatProbe.swift
  Resources/
    Assets.xcassets
    Localizable.xcstrings
```

规则：
- 单文件 <= 300 行。超出即拆，不靠压缩排版过关。
- 入口文件（`IHavenApp.swift`）只做装配，不含业务逻辑。
- 按资源分包，不建`Views/` `Models/` `Utils/` 这种横向大杂烩目录。
- 禁止 `import` 反向：Features 不得 import Infrastructure 的具体类型，只 import Core.Protocols。

---

## 5. 动态壁纸架构（最复杂部分）

### 5.0 产品定位：F9 靠什么与 Backdrop / Wallper 竞争

>本节刻意置于技术方案之前。若不先确认「用户为什么用它」，§5.1 之后的技术讨论就失去取舍依据。

PM 实测发现 wallhaven **零视频内容**（144 条样本 `file_type` 全为 `image/png` / `image/jpeg`；`/api/v1/video` 返回 404）。这改变了 F9 的价值主张：

| | 变更前（错误假设） | 变更后（实测结论） |
| --- | --- | --- |
| 素材来源 | wallhaven API | **用户本地文件**（F8 导入管线） |
| 价值主张 | 「浏览并播放」海量动态壁纸 | 「把用户**已有**的视频素材变成动态壁纸」 |
| 竞争维度 | 内容丰富度 | 播放体验 + 功耗控制 + 管理统一性 |

**这个变更不影响 V2 优先级**（理由见 5.0.3），但必须明确差异化理由，否则功能不成立。

#### 5.0.1 用户为什么不用 Backdrop / Wallper

如果 F9 的答案只是「我们也能播视频」，那这个功能不成立。真实差异有四条，前三条是**结构性优势**，不是营销话术：

| 维度 | Backdrop / Wallper | IHaven |
| --- | --- | --- |
| **账号与订阅** | 需要账号，部分内容需订阅 | **零账号**。用户自填 wallhaven API Key，无需注册 |
| **水印** | 部分版本有水印 | 无水印 |
| **安装成本** | 需装第二款软件，与现有壁纸工具并行 | **不装第二款**。静态库 + 动态素材在同一界面管理 |
| **多屏逐屏分配** | 各有短板 | 复用 F2 已验证的逐屏物理像素管线 |

**最强的差异化是第四条。** F2 的多屏逐屏分配（含裁切焦点、物理像素几何、同型号双屏歧义处理）是 PRD 里 RICE 最高的两个功能之一（F2 = 1080，F3/F4/F7 = 1200），而竞品的动态壁纸通常只能「整屏播放」。

这产生一个竞品无法提供的能力：**同一段视频，按每块屏的物理像素分别裁切并播放**。21:9 副屏不裁切、16:10 主屏按焦点裁切，两屏各自最优。

**功耗主张是可验证的差异**：提供四档暂停策略与实时 CPU/显存占用面板（F10），用户能自己看到数值。竞品宣称「省电」但不给数据。

#### 5.0.2 F9 依赖 F8（本地导入），复用同一管线

依赖关系已从「F9 独立读取 API」变为「F9 消费 F8 导入的素材」。架构侧确认并给出实现约束：

```
F8 LocalImportService  (唯一入口)
   |-- 静态图片 -> 存入 Wallpapers/          -> F1 浏览 / F2 设置
   +-- 动态视频 -> 存入 DynamicWallpapers/    -> 格式探测 -> F9 播放
```

**必须复用 F8 管线，不得为 F9 另建一套导入逻辑。** 理由：

1. 避免两套拖放 / 文件选择 / 安全作用域书签（security-scoped bookmark）实现
2. 导入时的格式探测、尺寸读取、去重逻辑天然共用
3. F8 在 MVP 就会实现，F9 复用则零额外成本

模块划分影响：F9 只消费「已导入的视频文件路径 + 元数据」，不关心文件从哪来。这让 F9 依赖面收窄，测试可用本地固定视频文件，不依赖 F8。

**依赖方向声明（架构侧明确，回应 PM 第4 次询问）**

F9 是**本地库的下游消费者**，不是「浏览结果的下游」：

```
wallhaven API -> WallhavenClient ------> F1 浏览 / F4 筛选 / F6 收藏
                                              |
                                    （静态图）|
                                              v
本地导入F8 -> LocalLibrary ----------> F2 设置
                |
                |（动态视频）
                v
                      F9 播放 -> WallpaperEngine(XPC)
```

| 维度 | F9 与 API 的关系 | F9 与 F8 的关系 |
| --- | --- | --- |
| 是否直接依赖 API | **否**。F9 不发起任何 wallhaven 请求 | **是**。素材全部来自 F8 导入结果 |
| 素材来源 | wallhaven 实测零视频内容，不存在 API 供给 | F8 导入到`DynamicWallpapers/` |
| 数据流位置 | 不在 API 数据流下游 | 在本地库下游 |

**模块归属**：`F9` 与 `F8` 同属 `Platform/LocalLibrary` 与 `Features/DynamicWallpaper` 两层，**F9 不import `WallhavenClient`**。若实现时发现 F9 需要引用任何 API 模块，说明依赖方向已错。

**顺序约束**：F8 必须先于 F9 交付。V2 内两者视为一个原子批次（F8 -> F9），已写入§8 风险表第 9 条。

**格式探测必须在 F8 完成**（导入时一次），而非 F9 播放时。探测有 IO 与解码开销，若播放时才做，用户会先看到卡顿再看到错误。导入时探测可立即给出「不支持该格式」反馈。

#### 5.0.3 是否应影响 V2 优先级：建议不变

**架构侧评估：不调整。** 理由：

| 考量 | 结论 |
| --- | --- |
| 技术风险是否上升 | 否。F9 的技术方案（桌面层窗口 + AVPlayer + XPC 隔离）不依赖素材来源，换成本地文件不改变任何技术路径 |
| 依赖复杂度是否上升 | 否。复用 F8 反而比独立 API 更简单 |
| 差异化是否削弱 | 部分削弱，但由 5.0.1 的四条结构性优势补偿，其中多屏逐屏裁切是竞品不具备的 |
| 用户价值是否下降 | 否。「把我已有的视频变成动态壁纸」本身是明确需求 |

**但依赖顺序必须调整**：V2 的 F9 应排在 F8 之后开发。若 F8（本地导入）未完成，F9 无法独立交付。两者在 V2 内应视为一个原子批次，顺序为 F8 -> F9。

#### 5.0.4 GIF：不作为壁纸播放；一键转换延后至 V3

GIF **不作为动态壁纸直接播放**（V2 与 V3 均不支持播放）。理由：

- macOS 不将 GIF 作为壁纸类型
- 逐帧解码功耗显著高于硬解视频，与「可测量可控的功耗」核心主张冲突
- 保留灰色项会在开发时变成没人拍板的事

**技术可行性已核验**：GIF -> MP4 是纯原生实现，不与「不集成 FFmpeg」冲突（见 5.6的格式表与`VERIFIED-API.swift` 的 `GIFTranscoder`）。

**但一键转换功能延后至 V3**，V2 仅提供引导。理由：

| # | 理由 |
| --- | --- |
| 1 | 转换器**零 F9 依赖**（不依赖 XPC 隔离、不依赖逐屏播放管线，独立于播放链路），因此不属于 V2 核心批次。捆绑会让 V2 从「动态壁纸播放」膨胀为「播放 + 格式转换工具」 |
| 2 | MVP 阶段连 GIF 的需求强度都无数据支撑，现在做是纯猜|
| 3 | 转换质量有风险（帧率降级、256 色 GIF 转 4:2:0 可能产生色带），需用户实际验证，V3 有更长观察窗口 |

**V2 行为**：GIF 出现在「不支持」列表，引导文案为「可用系统工具转换」并给出 macOS 转换路径（不提供应用内转换按钮）。

**V3 行为**：在 F9 播放稳定 + 有用户真实诉求反馈数据的前提下，提供应用内一键转换。

**GIF 转码必须先过实测门禁（V3 前置条件，不可跳过）**：

至少覆盖三类典型内容，每类肉眼确认**无色带、无卡顿、无音画不同步**：

| 内容类型 | 风险点 |
| --- | --- |
| 15fps / 256 色 / 含渐变 | 4:2:0 色度采样可能产生色带 |
| 15fps / 128 色 / 纯色块 | 帧率转换导致的时序异常 |
| 动态噪点（火焰 / 雨） | 高频细节在压缩后糊化 |

若某类内容质量不可接受，**需在导入时提示而非静默降级**。

**关键：「逐帧转 H.264 无质量损失」这句话本身需要验证。** 参数写得再细也不能替代实测——这正是我们这轮反复强调的「实测 > 文档推断」。

### 5.1 先说不可行项（避免团队走弯路）

以下路径经核验**不可行**，不得尝试：

| 方案 | 结论 | 原因 |
| --- | --- | --- |
| 系统级「视频壁纸」API | **不存在** | macOS 无公开 API 把视频设为桌面背景。`NSWorkspace.setDesktopImageURL` 只接受静态图片文件。Windows 的「动态壁纸」是 Windows 特有能力，不可移植。 |
| `AVPlayer` 直接渲染为壁纸 | 不可行 | `AVPlayerLayer` 只能存在于 `AVPlayerView`/自定义 `CALayer` 宿主中，必须有承载视图，即必须有窗口。 |
| ScreenSaver 引擎复用 | 不可行 | `ScreenSaverEngine` 面向全屏屏保，需 `.saver` 扩展点（独立 target + 特定 Info.plist），且会与系统屏保抢占同一进程槽位。属屏保整合，PRD 已列为 Out-of-Scope。 |
| WebView 播 WEBM | 技术可行但**否决** | WKWebView 确实能播 WebM，但每个壁纸需一个 WebContent 进程（约 300MB 级），与 PRD「可测量可控的功耗」核心主张直接冲突。PRD 已明确否决 HTML/CSS/JS 壁纸。 |
| SpriteKit 序列帧 | 技术可行但**否决** | 序列帧需预渲染全部帧为位图，4K 60fps 10 秒 = 大量内存占用，且无法按显示器分辨率动态适配。CPU/内存开销远高于硬解码视频。 |
| `WallpaperExtensionKit` 私有框架 | **不可依赖** | 需 `dlopen` + Mirror 反射调用私有 XPC 类型。Apple 可在任一系统版本移除或更改。社区仅验证 macOS 26 与 27 beta。PRD F12 已标注风险并排到 V3 末位。**MVP/V2 严禁依赖。** |

**API 素材侧的硬事实**：wallhaven 不提供任何视频内容（实测见 5.0）。动态壁纸素材**只能**来自用户本地文件，不存在「从 API 拉取动态壁纸」这条路径。

### 5.2 可行路径：桌面层窗口 + AVPlayerLayer

唯一稳定可行的方案：**双层结构**。

```
静态层：NSWorkspace.setDesktopImageURL 设置静帧（系统原生，锁屏/无窗口时兜底）
动态层：每屏一个 borderless NSWindow + AVPlayerLayer，窗口置于桌面层
```

原理：`WindowServer` 合成时按窗口层级从低到高绘制。静态壁纸在系统层，动态窗口用`CGWindowLevelForKey(.desktopWindow)` 贴在壁纸之上、桌面图标之下。

**为什么必须有静态层**：以下场景动态窗口不存在或不显示，静态层保证用户永远看到壁纸而不是黑屏。
- 锁屏（系统接管显示）
- 用户切换到全屏 Space 且窗口未跟随
- helper 进程崩溃或被系统回收
- 屏幕休眠

### 5.3 进程隔离方案（架构要求）

**选定：独立 XPC Service（`com.ihaven.wallpaper-helper`），每个显示器一个实例。**

对比方案：

| 方案 | 隔离性 | 崩溃影响 | 内存开销 | 评估 |
| --- | --- | --- | --- | --- |
| AppKit 应用内嵌（同进程） | 无 | 主窗口崩溃 = 壁纸全挂 | 最低 | **否决**。PRD 非功能需求明确「主窗口崩溃后菜单栏功能仍存活」，更严重的是渲染壁纸的 GPU/解码负载会污染主进程稳定性 |
| 独立 helper（NSApplication 无 UI） | 进程级 | 仅动态壁纸失效 | 单例开销 | 备选。实现简单，但所有屏幕共用一个 main run loop，单屏解码异常会影响全部 |
| **XPC Service，每屏一实例** | 进程级 | 仅该屏失效 | 每屏一份 | **选定**。单屏解码崩溃/泄漏不影响其他屏；可独立被系统按内存压力回收；XPC 天然提供跨进程状态同步 |
| LaunchAgent（登录项） | 进程级 | 同上 | 每屏一份 | 否决。需要用户授权安装登录项，违反零打扰定位；且难以精确跟随主应用生命周期 |

**为什么每屏一实例**：
- AVPlayer 的解码管线与 GPU 资源是 per-player 的，单进程多屏多 player 会在一处异常时互相影响。
- 内存压力下系统可选择性回收单屏实例（配合静帧兜底，用户无感）。
- XPC 连接由主进程统一管理，但播放实例彼此独立。

XPC Service 配置要点：
- Target 类型：XPC Service
- `ServiceType = Application`（`LaunchAgent` 类型受登录项授权约束，不采用）
- 独立 bundle id，独立 Info.plist
- 双向协议：主进程 -> helper「播放/暂停/停止/设置速率」；helper -> 主进程「播放状态/异常/内存压力」
- helper 需声明 `LSUIElement`（无 Dock 图标、无主窗口）

**注意**：XPC Service 与沙盒。App Sandbox 下 XPC Service 必须与应用同沙盒组，通过 `NSXPCConnection` 的 `.serviceName` 绑定。跨沙盒通信需 entitlement `com.apple.security.application-groups`，MVP 不引入（见 §5.7风险）。

### 5.4 窗口配置（已编译核验）

```swift
func makeWallpaperWindow(_ screen: NSScreen) -> NSWindow {
    let w = NSWindow(contentRect: screen.frame,
                     styleMask: .borderless,
                     backing: .buffered, defer: false)
    // 贴在桌面壁纸之上、桌面图标之下
    w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
    w.collectionBehavior = [.canJoinAllSpaces, .stationary,
                            .ignoresCycle, .fullScreenNone]
    w.sharingType = .none
    w.isOpaque = false
    w.backgroundColor = .clear
    w.ignoresMouseEvents = true
    w.hasShadow = false
    return w
}
```

每个属性的理由：
- `level = .desktopWindow`：关键。若用 `.normal`（0）会被普通窗口遮住；若用 `.desktopIconWindow` 会盖住桌面图标。
- `canJoinAllSpaces`：所有 Space 都显示，否则切Space 后壁纸消失。
- `stationary`：切换 Space 时不参与窗口移动动画。
- `ignoresCycle`：Cmd+` 不选中它。
- `fullScreenNone`：不进全屏 Space，避免与全屏应用抢占。
- `ignoresMouseEvents = true`：点击穿透，用户正常操作桌面图标。
- `sharingType = .none`：不参与屏幕共享/录制，避免动态壁纸出现在用户的屏幕共享里（隐私预期）。

### 5.5 循环播放（已编译核验）

```swift
func makeLoopingPlayer(_ url: URL) -> (AVQueuePlayer, AVPlayerLooper, AVPlayerLayer) {
    let player = AVQueuePlayer()
    player.isMuted = true
    player.actionAtItemEnd = .none
    let looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
    let layer = AVPlayerLayer(player: player)
    layer.videoGravity = .resizeAspectFill
    return (player, looper, layer)
}
```

- `AVQueuePlayer` + `AVPlayerLooper`：系统级无缝循环，比自己监听播放结束seek 可靠（无空帧、无累积漂移）。
- `isMuted = true`：壁纸无声。**这也是隐私选择**：播有声壁纸等于持续出声。
- `actionAtItemEnd = .none`：配合 looper，必须设，否则 looper 会与默认的暂停行为冲突。
- `videoGravity = .resizeAspectFill`：铺满屏幕，与静态层裁剪行为一致。不同分辨率显示器各自独立裁剪。
- `AVPlayerLooper` 必须被持有（helper 存为属性）。它是对象生命周期的一部分，若被释放循环会停。这是常见的静默 bug。

**AVPlayerLayer 的已知系统行为**（macOS 26 SDK Release Notes 记录）：替换 item 期间 `isReadyForDisplay` 可能短暂为 false。切换壁纸时应先暂停旧 player、设置新 item、等一帧再显示，避免黑帧闪烁。

### 5.6 降级策略与自我回收（PRD要求「无显示器接入时降级」「内存压力下自我回收」）

**媒体能力探测**：WEBM/VP8/VP9 在 macOS 上**无原生解码支持**。AVFoundation 不支持 Matroska/WebM 容器，Safari 之外的 WebKit 不内置这些 codec。

处理策略（**按是否可轻量转码区分**，设计侧提出的分类已写入）：

| 输入格式 | 可否原生播放 | 可否轻量转码为 MP4 | 处理 |
| --- | --- | --- | --- |
| MP4 / MOV（H.264 / HEVC） | 是（硬解） | 不需要 | 直接导入播放 |
| **GIF** | AVPlayer 可播，但逐帧解码功耗高 | **可以**（ImageIO 抽帧 + AVAssetWriter 编码，无需 FFmpeg） | 排除播放（见 5.0.4）。**V2** 仅引导用系统工具转换；**V3** 提供应用内一键转换（须先过转码质量实测门禁） |
| **WEBM / MKV / 其他** | **否**（macOS 无原生解码） | **不可以**（需重编码，耗时且有损） | 明确拒绝，**任何版本都不提供「转换为 MP4」**，只提示换素材 |

**关键区分：GIF 与 WEBM 的技术根据是「解封装」vs「重新编码」。**

- GIF 容器内的数据本就是逐帧压缩图像（MJPEG/调色板），拆出来重封装为 H.264 属于**解封装 + 重封装**，无需从像素重新编码
- WEBM 的 VP8/VP9 在 macOS 无解码器，必须**完整转码**，耗时且有损

因此两者的用户可行动作不同，**不能给同一文案**。

| 格式 | 用户可行动作 | 理由 |
| --- | --- | --- |
| GIF | 转换为 MP4（轻量，可自行完成） | 解封装级别操作 |
| WEBM / MKV | **换素材** | 重编码耗时且有损，给「转换」是指向一条很重的路 —— 用户照做却等很久、画质还变差，下次就不信了 |

这条区分由设计侧提出并写入 §4.9，架构侧确认成立。

**明确不做**：不集成 FFmpeg。理由：静态链接 FFmpeg 意味着二进制体积暴涨（数十 MB）、许可证合规复杂（LGPL/GPL 边界）、供应链风险显著上升。PRD 已把「可测量可控的功耗」与「Apple 官方级品质」作为核心主张，为支持一个格式引入巨量复杂度是负收益。

**GIF 转换为 MP4 不需要 FFmpeg**（已编译核验）：`CGImageSourceCreateWithURL` 可枚举 GIF 帧，`AVAssetWriter` + `AVAssetWriterInputPixelBufferAdaptor` 可编码为 H.264/HEVC 的 MP4。全部使用系统原生框架，与「不集成 FFmpeg」的决策不冲突。

GIF 与 WEBM 的正确处理时机见 5.0.2（**在 F8 导入时做一次格式探测**，不在播放时做）。

**降级链（按优先级）**：

```
1. 动态壁纸正常播放
2. 显示器休眠 / 锁屏 -> 暂停播放，静帧层仍在（用户看不到差异，省电）
3. helper 进程崩溃 / 被回收 -> 静帧层仍在，UI 提示「动态壁纸已停止」
4. AVPlayer 解码失败（格式不支持 / 文件损坏）-> 静帧 + 明确的错误原因
5. 无可用显示器（全拔） -> 销毁窗口，暂停播放，保留配置
```

**内存压力自我回收**：

监听 `NSApplication.didReceiveMemoryNotification`（AppKit）或在 helper 侧按RSS 阈值 + 心跳检查。处理顺序：

1. 压力等级 warning：暂停非主显示器的动态壁纸（主屏优先保留）
2. 压力等级 critical：暂停全部动态壁纸，静帧层接管
3. 压力缓解：恢复播放（注意需校验文件仍存在）

**屏幕拓扑变化**：监听 `NSApplication.didChangeScreenParametersNotification`，比对 `NSScreen.screens` 差异，为新增屏创建窗口、为移除屏销毁窗口。**只有拓扑真正变化时才重建窗口**，分辨率/位置变化也要处理（窗口需resize 并重新计算 `videoGravity` 裁剪）。

其他必须监听的通知（均已编译核验）：
- `NSWorkspace.activeSpaceDidChangeNotification`：Space 切换后重设静帧（系统壁纸在非活跃 Space 下可能不刷新）
- `NSWorkspace.didWakeNotification`：唤醒后重建（分辨率可能已变）
- `NSWorkspace.screensDidSleepNotification`：暂停播放
- `NSWorkspace.sessionDidResignActiveNotification`：切到其他应用时可降帧

**看门狗**：检测主线程无响应与播放停滞。超时即退出 helper，让静帧层兜底，而不是留一个卡死的窗口。

### 5.7 沙盒风险（必须实测）

App Sandbox 下，桌面层窗口 + 跨 Space 行为的实际表现**未经本机验证**。已知风险：

- 沙盒应用创建 `canJoinAllSpaces` 窗口是否被系统接受
- 沙盒下 `NSWorkspace.setDesktopImageURL` 是否需要额外 entitlement
- 沙盒应用能否在无焦点状态下维持播放

MVP 阶段建议：若实测受阻，Debug 构建临时关闭沙盒（`com.apple.security.app-sandbox = false`），Release 阶段再定。**不要在未验证前假设沙盒可用或不可用**，这一项必须在 Phase 1 用最小实验验证，不要留到 V2。

### 5.8 动态壁纸编辑器（V3，PRD 已排除出MVP）

PRD 5.1 判断RICE Score 37.5 排入 V3，架构师认同。本节只锁技术方案，不承诺排期。

**导出管线（已编译核验，macOS 26 API）**：

```swift
func exportLoop(source: AVURLAsset, range: CMTimeRange,
                size: CGSize, to out: URL) async throws {
    let comp = AVMutableComposition()
    guard let src = try await source.loadTracks(withMediaType: .video).first,
          let dest = comp.addMutableTrack(
              withMediaType: .video,
              preferredTrackID: kCMPersistentTrackID_Invalid)
    else { throw CocoaError(.fileReadCorruptFile) }
    try dest.insertTimeRange(range, of: src, at: .zero)
    guard let ct = try await comp.loadTracks(withMediaType: .video).first else { return }

    let layer = AVVideoCompositionLayerInstruction(
        configuration: .init(assetTrack: ct))
    let instr = AVVideoCompositionInstruction(
        configuration: .init(backgroundColor: CGColor(gray: 0, alpha: 1),
                             layerInstructions: [layer],
                             timeRange: range))
    let session = AVAssetExportSession(
        asset: comp,
        presetName: AVAssetExportPresetHEVCHighestQuality)!
    session.videoComposition = AVVideoComposition(
        configuration: .init(instructions: [instr], renderSize: size))
    session.shouldOptimizeForNetworkUse = true
    try await session.export(to: out, as: .mp4)
}
```

**参数决策**：

| 参数 | 取值 | 理由 |
| --- | --- | --- |
| preset | `AVAssetExportPresetHEVCHighestQuality` | HEVC 硬解，Apple Silicon 有专用解码单元，功耗显著低于 H.264 软解 |
| outputFileType | `.mp4` + HEVC | 兼容性最广；`.mov` 无收益 |
| renderSize | 目标显示器分辨率（可超采样到 1.5x） | 壁纸铺满需匹配物理像素。超采样给缩放留余量 |
| 时长 | 3-10 秒，可调 | 太短突兀，太长文件大且用户等待久 |
| 帧率 | 源帧率，上限 60 | 超过 60 对壁纸无感知收益，只增体积 |
| 音频 | **不导出** | 壁纸无声（§5.5 隐私决策），无谓的音频轨是体积浪费 |
| 裁剪 | `renderSize` + 变换实现 aspect fill | 见下方 |

**裁剪逻辑**：给定源 `naturalSize` 与目标 `renderSize`，若源更宽则按宽度铺满、上下裁掉；源更高则按高度铺满、左右裁掉。等比缩放系数 `= max(targetW/srcW, targetH/srcH)`。

**重要：视频合成 API 在 macOS 26 已弃用旧形态。** `AVMutableVideoComposition`、`AVMutableVideoCompositionLayerInstruction`、`AVMutableVideoCompositionInstruction` 均标记 `deprecated in macOS 26.0`。新形态是不可变的 `Configuration` 结构体 + 构造函数：

- `AVVideoCompositionLayerInstruction.Configuration(assetTrack:)`
- `AVVideoCompositionInstruction.Configuration(backgroundColor:layerInstructions:timeRange:)` —— **参数顺序固定，顺序错编译直接失败**
- `AVVideoComposition.Configuration(instructions:renderSize:)`

这些 `Configuration` 是不可变值类型，属性为 `get` only，**必须在构造时一次性传入全部参数**，构造后不能改。按旧 API 的「先new 再逐个 set」写法迁移会失败。

`AVMutableComposition.addMutableTrack` 与 `insertTimeRange` 是**同步**方法（返回 optional 与 `throws`，非 `async`）。误加 `await`/`try` 会产生警告。

`AVAsset.tracks(withMediaType:)` 在 macOS 13 起已弃用，必须用 `await asset.loadTracks(withMediaType:)`。

---

## 6. 多屏壁纸与API 客户端

### 6.1 逐屏不同壁纸

`NSWorkspace.setDesktopImageURL(_:for:options:)` 支持逐屏设置，**逐屏不同壁纸可行**。

```swift
for screen in NSScreen.screens {
    try NSWorkspace.shared.setDesktopImageURL(url(for: screen), for: screen, options: opts)
}
```

已核验事实：
- `for: screen` 参数非空。传 `nil` 会广播到所有活跃显示器（无法逐屏区分）。
- 静帧可用 `desktopImageURL(for:)` 与 `desktopImageOptions(for:)` 反查当前设置（用于读取系统已有配置而非猜测）。
- 必须在 `activeSpaceDidChangeNotification` 时重设，否则当前 Space 非活跃桌面时壁纸不刷新。这是社区方案与 Apple 文档之间的已知差异。

**已知限制**：macOS 在 `~/Library/Application Support/com.apple.wallpaper/Store/Index.plist` 维护自己的壁纸记录。仅用 API 设置时，用户在「系统设置 > 墙纸」里看到的可能与实际桌面不一致（会显示为空或旧值）。这是系统层行为，MVP 接受不改系统 plist（写入系统 plist 属于侵入系统状态，风险大于收益）。若后续用户投诉，再评估。

### 6.2 填充模式枚举（已编译核验，三项锁定）

`setDesktopImageURL` 支持的 **全部** option key 只有三个（来源：`AppKit.framework/Headers/NSWorkspace.h:203-219`，macOS 10.6+ 至今未变）：

| Key | 类型 | 语义（官方文档原文要点） |
| --- | --- | --- |
| `NSWorkspaceDesktopImageScalingKey` | `NSNumber(NSImageScaling)` | 缩放模式。**默认 `NSImageScaleProportionallyUpOrDown`**。文档注明 `NSImageScaleProportionallyDown` **目前不支持** |
| `NSWorkspaceDesktopImageAllowClippingKey` | `NSNumber(BOOL)` | **NO（默认）= 图片完整可见，但四周可能有空白**；**YES = 填满屏幕，图片可能被裁切**。**仅对比例缩放类型生效**，非比例类型**忽略此值** |
| `NSWorkspaceDesktopImageFillColorKey` | `NSColor` | **填充图片周围空隙的颜色**。仅支持可转换为 `NSCalibratedRGBColorSpace` 的颜色，**alpha 值被忽略** |

三项锁定模式（**枚举只有四个值，不存在平铺语义**）：

| 模式 | `.imageScaling` | `.allowClipping` | 空隙填充 | 说明 |
| --- | --- | --- | --- | --- |
| 适应 Fit | `scaleProportionallyUpOrDown` | `false` | **生效（见 6.2.1）** | 完整可见，四周可能留边 |
| 填充 Fill | `scaleProportionallyUpOrDown` | `true` | 不生效（无空隙） | 铺满，可能裁边（**系统默认**） |
| 拉伸 Stretch | `scaleAxesIndependently` | **忽略** | 不生效 | 变形铺满，比例失真 |

**为什么不提供「居中」与「平铺」**：

`NSImageScaling` 在 AppKit 中只有四个值——`ProportionallyDown`（壁纸 API 不支持）、`AxesIndependently`、`NSImageScaleNone`、`ProportionallyUpOrDown`。**其中不存在任何平铺语义**，平铺无法通过该 API 实现。

同理，「居中」不是独立选项：所谓「填满并居中裁切」就是 `ProportionallyUpOrDown` + `AllowClipping=YES` 的固定行为，系统永远居中裁切。也不存在「指定裁切哪一侧」——`AllowClipping` 只是 BOOL，用户无法控制裁切焦点（需要控制焦点时，由客户端用 Core Image 预裁切，见 PRD F2）。

因此 UI 与数据库都**不得出现** `tile` / `center` 这两个值。

已核验的类型名陷阱：
- 键名是 `.imageScaling`，**不是** `.scaling`（编译器验证：`.scaling` 不存在）
- 枚举是 `NSImageScaling.scaleProportionallyUpOrDown`，**不是** `.proportionallyUpOrDown`（编译器验证：前缀 `Scale` 未被剥离）

**拉伸模式忽略 AllowClipping**：`scaleAxesIndependently` 属于非比例缩放类型，官方注释明确「Non-proportional scaling types ignore this value」。所以拉伸模式下不存在「完整可见」变体。

**系统限制**：`NSImageScaleProportionallyDown`（只缩小不放大）在 AppKit 中定义但**系统声明不支持**。因此「填充」模式在小图放大到大屏时必然模糊—— 无法用参数规避，只能靠下载足够分辨率的原图。UI 上应提示用户。

**官方 UI 约束（必须遵守）**：`NSWorkspace.h:222-226` 原文 —
> You should normally NOT present a user interface for picking the options. Instead, just choose appropriate defaults and allow the user to adjust them in the System Preference Pane.

**权衡结论**：App 内提供**两档快捷预设**（适应 / 填充，覆盖 90% 场景）+ 空隙填充色选择器（高价值，见 6.2.1）。**不暴露 Stretch**——虽然 `scaleAxesIndependently` 是合法枚举值，但拉伸会导致比例失真，与本产品「视觉策展」的定位冲突。若用户需高级控制，引导至系统设置（`x-apple.systempreferences:com.apple.preference.wallpaper`）。这样既不违背官方建议，又满足 PM 的 F2 验收标准。

**Retina 处理**：`NSWorkspace` 直接处理壁纸文件的像素与屏幕 scale 的匹配，不需手动乘 `backingScaleFactor`。但**应用侧预裁剪时必须考虑**：若为省内存按逻辑分辨率预裁剪，在 Retina 屏上会模糊。策略：缩略图按逻辑分辨率（列表用），设置壁纸的原图按物理分辨率下载（wallhaven 提供原图 URL）。

### 6.2.1 空隙填充色（差异化能力，数据现成）

「适应 Fit」与「居中 Center」模式下图片四周留白，系统默认填充色往往与壁纸不协调。`NSWorkspaceDesktopImageFillColorKey` 允许自定义。

**数据现成**：wallhaven API 每个壁纸返回 `colors` 数组（5 个十六进制主色，如 `["#000000","#abbcda","#424153","#66cccc","#333399"]`），**无需任何额外请求**。

**取色策略**（按优先级）：
1. 用户显式选择（从 `colors` 数组点选，或自定义任意色）——最高优先级
2. 默认自动：取 `colors` 中第一个非黑非白的主色（索引 1 通常是主色，索引 0 常为纯黑）
3. 兜底：系统默认色

**技术约束（必须处理）**：
- 官方限制「仅支持可转换为 `NSCalibratedRGBColorSpace` 的颜色」→ 传入前必须做色彩空间转换，hex（通常为 sRGB）→ CalibratedRGB
- 官方明示「**alpha 值被忽略**」→ UI 不得提供透明度控制，直接用不透明色
- 需预计算转换结果并缓存（同一壁纸重复设置时避免重复转换）

**为何列为差异化点**：竞品普遍未实现此能力（需理解 `colors` 数组语义 + 做色彩空间转换 + 色彩协调策略），而数据零额外成本。这是「用户看得见效果」与「工程量可控」的交集。

### 6.2.2 裁切焦点预裁切（系统层无此能力，必须客户端实现）

**问题**：PM 的 F2 验收标准要求「用户可手动调整裁切焦点」。但官方 API 中 `AllowClipping` 只是一个 BOOL，**系统永远居中裁切，无任何指定裁切区域的能力**。系统层不存在「焦点」概念。

**唯一可行方案：客户端预裁切** —— 用 Core Image 按目标屏物理像素比例裁出正确像素的静态图，再将该图写入壁纸设置。

```
用户调整焦点 ──> 计算裁切矩形（按物理像素）
                └─> CIImage.cropped(to:) ──> 编码为 PNG/JPEG ──> 写入临时目录
                └─> NSWorkspace.setDesktopImageURL(裁切后图, for: screen, ...)
```

**实现要点**：

| 项 | 方案 |
| --- | --- |
| 物理像素计算 | `screen.frame` × `screen.backingScaleFactor` 得到目标屏物理像素尺寸。**不可只用逻辑点**，否则 Retina 屏会模糊 |
| 原图来源 | 必须下载**物理分辨率**原图（wallhaven `thumbs.original` 或 `path`），不用缩略图 |
| 执行线程 | **后台队列 + 异步**。4K 图裁切 + 编码不可在主线程执行 |
| 缓存策略 | 缓存键 = `wallpaperId + screenId + focusPoint + targetPixelSize`。重复设置同一壁纸到同一屏**必须命中缓存**，避免每次重裁 |
| 文件存放 | AppContainer 内的 `Caches/WallpaperCrop/`（沙盒可写，系统可回收）。**不写系统目录** |
| 内存 | 用 `CGImageSourceCreateThumbnailAtIndex` 的 `kCGImageSourceThumbnailMaxPixelSize` 做降采样，避免把 8K 原图全解码进内存 |
| 编码格式 | JPEG（quality 0.9）或 PNG，按裁切后像素量选择；避免 PNG 体积过大 |

**硬约束：预览与写入必须消费同一对象**

这是本节最重要的架构约束，由设计侧提出、架构侧升级为结构性保证。

裁切模块的输出必须是一个**可被 UI 直接消费的产物对象**，不是「一个文件路径 + 一堆需要重新计算的参数」。产物对象至少含：

| 字段 | 类型 | 用途 |
| --- | --- | --- |
| `image` | 已裁切的位图 | UI 预览直接渲染它，不再自行裁切 |
| `pixelSize` | `CGSize` | 预览显示的尺寸标注、放大倍数计算 |
| `cacheKey` | `String` | 命中缓存则复用，不重裁 |
| `fileURL` | `URL?` | 仅写入路径需要；预览不需要 |

**为什么这条是结构性的而非测试性的**：

「预览与实际一致」如果只作为一条验收标准，实现者完全可以写出两套逻辑——预览用 Core Image 裁一遍、写入用另一套参数再裁一遍，且两套在边界条件下（半像素、缩放插值、EXIF 方向）产生细微差异。这类差异不崩溃、用户只会觉得「预览和实际不一样」，属于典型的静默错误。

要求「预览与写入消费同一对象」之后，两套逻辑在结构上**无法存在**——预览没有裁切能力，它只能渲染产物对象；写入也只能写同一个产物对象。二者物理上共用同一份像素。

**实现约束**：
- 预览视图**禁止**自行调用 Core Image 裁切
- 产物对象生成后**不可变**（`let` 属性 + 值类型），焦点变化时生成新对象而非修改
- 产物对象与写入操作之间不得有第二次变换

**「放大倍数」必须实时计算，不得缓存跨屏结果**

分辨率预警要显示具体放大倍数 = `屏物理像素宽 / 壁纸物理像素宽`。这条是设计侧文案静默错误的来源：

- 放大倍数是 **(壁纸, 屏幕) 这一对的关系量**，不是壁纸的固有属性
- 同一张 3840×2160 的壁纸在 5120×2880 屏上是 1.33倍，在 2560×1440 屏上是 0.67 倍（不需放大）
- 用户拔掉外接屏、或把壁纸从副屏拖到主屏，放大倍数立即改变

因此：**放大倍数禁止缓存跨屏结果，禁止作为壁纸的持久化字段**。每次在给定 `(壁纸, 目标屏)` 上下文时由物理像素实时计算。

若需避免重复计算，缓存键必须包含目标屏标识（`(wallpaperId, screenId)`），等价于裁切缓存的键规则。

### 6.2.3 atleast 参数是任意分辨率字符串（非枚举）

**实测结论**（直接请求 wallhaven API，2026-10-08）：

| 请求 | total | last_page | HTTP |
| --- | --- | --- | --- |
| `atleast=5120x2880` | 22,728 | 947 | 200 |
| `atleast=3840x2160` | 80,905 | 3,372 | 200 |
| `atleast=2560x1440` | 160,732 | 6,698 | 200 |
| `atleast=1920x1080` | 388,406 | 16,184 | 200 |
| `atleast=abc` | — | — | **500** |

`atleast` 接受**任意** `WIDTHxHEIGHT` 字符串，不是固定枚举。这带来两个实现约束：

**1. 数据模型：`atleast` 必须是可变的按需构造值**

2020 雏形工程把它声明为 `let atleast: String = ""`（`QueryParameter.swift:32`），恒为空串、永远不下发。新代码必须改为**按当前显示器物理像素实时构造**：

```swift
// 不可硬编码枚举—— API 接受任意分辨率串
func atleast(forPhysicalSize size: CGSize) -> String {
    "\(Int(size.width))x\(Int(size.height))"
}
```

因为显示器拓扑会变（拔插外接屏、切换分辨率），固定值必然在某些拓扑下失效。

**2. 错误响应行为（已全面实测，2026-10-08）**

wallhaven 对非法参数**不返回 4xx**，而是返回 **HTTP 500 + `{"message":"Server Error"}`**。完整实测矩阵：

| 请求 | HTTP | 响应体 |
| --- | --- | --- |
| `atleast=abc` | **500** | `{"message":"Server Error"}` |
| `atleast=1920xabc` | **500** | `{"message":"Server Error"}` |
| `page=0` | **500** | `{"message":"Server Error"}` |
| `page=-1` | **500** | `{"message":"Server Error"}` |
| `page=99999`（越界过大） | 400 | `{"error":"Bad Request"}` |
| `resolutions=9999x9999` | 200 | **有数据**（1 张真实 9999×9999 壁纸） |
| `ratios=99x99` | 200 | **有数据**（24 张，`ratio` 被忽略回退默认） |
| `q=###` | 200 | 正常 JSON（空结果） |

**修正一处先前的错误结论**：早期我把 `resolutions=9999x9999` / `ratios=99x99` 记为「返回 200 空结果」，实测复核后**这是错的**：

```
resolutions=9999x9999 → total=1，返回 1 张真实的 9999×9999 壁纸
ratios=99x99          → total=5005，返回 24 张（ratio 参数被静默忽略，回退默认比例）
```

`resolutions` 会精确匹配（wallhaven 上确实存在 9999×9999 的壁纸）；`ratios` 非法值则被**静默忽略**而非报错。

两条关键结论：

**（a）500 既是服务端故障，也可能是客户端非法参数。** 二者响应体完全相同，无法靠响应区分。只能靠**发请求前的本地校验**。

**（b）响应体类型取决于 `Accept` 请求头，不是随机的。** 实测：

| 请求 | 响应体 |
| --- | --- |
| 带 `Accept: application/json` | JSON（`{"message":"Server Error"}`） |
| 不带 / `Accept: text/html` | **HTML 页面**（`<title>It broke - wallhaven.cc</title>`） |

连续 6 次请求结果一致，非间歇现象。**因此客户端必须始终显式发送 `Accept: application/json`** —— 否则错误路径下会拿到 HTML，把 HTML 喂给 `JSONDecoder` 产生误导性的「数据解析失败」，而真实原因是参数非法。

**（c）「格式合法但无匹配」返回 200 + 空数组，不是错误。** 实测 `atleast` 的上边界：

| `atleast` | total | 说明 |
| --- | --- | --- |
| `1x1` | 501,656 | 极小值正常匹配（全库） |
| `7680x4320`（8K） | 5,100 | 正常 |
| `9999x9999` | 32 | 接近上限，仍有结果 |
| `10000x10000` | 31 | 边界附近 |
| `20000x20000` | **0** | 格式合法但无匹配 |
| `50000x50000` | **0** | 同上 |

`20000x20000` 的完整响应体：
```json
{"data": [], "meta": {"current_page":1,"last_page":1,"per_page":24,"total":0,"query":null,"seed":null}}
```

**这是空态而非错误态** —— 请求成功、参数合法、内容库确实没有。UI 必须显示「没有符合此组合的壁纸」而非错误提示，更不能显示「加载失败」。

实现上：客户端**不应**对 `atleast` 做上界校验（`50000x50000` 格式完全合法，服务端正常接受）。它只校验格式 `^\d+x\d+$`，由服务端返回空结果来表达「无匹配」。

**3. 客户端校验规则（不依赖服务端正确响应）**

| 参数 | 本地校验 | 不通过时的行为 |
| --- | --- | --- |
| `atleast` | `^\d+x\d+$` | **不发该参数**（而非发出去等500） |
| `page` | `>= 1` | 停止翻页，不发请求 |
| `resolutions` / `ratios` | 宽松格式校验或直接放行 | 实测非法值返回 200，不构成风险 |
| `q` | 直接放行 | 实测特殊字符返回 200 空结果 |

原则：**所有参数在发请求前做本地格式校验，不依赖服务端 4xx 告知错误。** wallhaven 对非法参数返回 500 而非 4xx，指望服务端报错等于把客户端的正确性外包给了不可控的第三方。

**4. 响应处理顺序：必须先判 `statusCode`，再尝试解码**

```
1. 拿到 (data, response)
2. 先看 response.statusCode      ← 必须第一步
3. 非 2xx → 直接走错误分支，不碰 data
4. 2xx→ 才尝试 JSONDecoder 解码 data
```

**禁止先调 `JSONDecoder` 再判 `statusCode`。** 错误路径下的响应体可能是 HTML（见上表），先解码会产生「数据解析失败」这种误导性错误，把「我们的筛选条件写错了」误报成「服务端异常/网络问题」。

建议封装：`APIError` 的构造只依据 `statusCode` 与已解析的业务错误；解码失败单独归为 `.decodingFailed`，**不得与网络错误混为一类**。

**静默错误风险**：若把 500 一律当服务端故障静默重试，用户会看到「加载失败」却不知道是自己的筛选条件导致的。这与 generated-code-failure-modes 的静默错误防线同源。

因此**错误文案必须能区分三类**：「你的筛选条件有问题」/「wallhaven 服务异常」/「网络不可用」。不可统一显示「加载失败」。

**与反查逻辑的共存问题（必须明确预期）**：
预裁切写入后，`desktopImageURL(for: screen)` 反查返回的是**裁切后的临时文件**，不是用户下载的原图。用户打开「系统设置 >墙纸」看到的是裁切结果 —— 这**正是预期行为**（与系统设置里看到的即实际桌面内容一致）。需在文档与 UI 提示中说明，避免用户困惑「我的原图去哪了」。

**待实测（P0）**：Retina 4K 屏裁切 + 编码的**实际耗时量级**（ms 级 or 秒级）尚未测量。测量方法已写入 `VERIFIED-API.swift`，Phase 3 首个技术任务即为此基准测试。

**若实测显示性能不可接受**（例如 4K 原图裁切 > 2s），备选方案：
1. 降级为「只暴露适应/填充两档 + 居中裁切」，放弃焦点调整（需同步退PM 的 F2 验收标准）
2. 焦点调整改为「后台异步预生成」，用户调整焦点后先显示模糊占位、完成后淡入

### 6.2.4 ratios / resolutions 必须为封闭枚举（ADR-007 Trap 13）

实测证明这两个参数**不能作为自由字符串**：

| 请求 | total | 真实语义 |
| --- | --- | --- |
| `ratios=99x99` | 5,005 | **静默匹配「比例≈1」**，返回 24 条全为 1:1 方图，`meta.query` 为 `null` |
| `resolutions=9999x9999` | 1 | 精确匹配成功（wallhaven 确实有 9999×9999 的壁纸） |

**`ratios` 非法值是静默错误中最严重的一类**：用户以为设了比例筛选，实际拿到完全不同比例的内容，且无任何信号。必须客户端拦截。

**实现**：定义封闭枚举，非法值在构造请求前抛出，**不发出请求**。

```swift
/// 官方文档列举的比例取值（12 个，含 UNSET 哨兵）
enum Ratio: String, CaseIterable, Sendable {
    case unset  = ""       // 不下发
    case r9x16  = "9x16"
    case r10x16 = "10x16"
    case r9x18  = "9x18"
    case r1x1   = "1x1"
    case r3x2   = "3x2"
    case r4x3   = "4x3"
    case r5x4   = "5x4"
    case r16x9  = "16x9"
    case r16x10 = "16x10"
    case r21x9  = "21x9"
    case r32x9  = "32x9"
    case r48x9  = "48x9"
}

/// 精确分辨率（24 个，含 UNSET 哨兵）。
/// 注意：官方明确「Single resolution allowed」，故本enum 一次只表达一个值。
enum ExactResolution: String, CaseIterable, Sendable {
    case unset = ""
    case r1280x720  = "1280x720"
    case r1280x800  = "1280x800"
    case r1280x960  = "1280x960"
    case r1280x1024 = "1280x1024"
    case r3440x1440 = "3440x1440"
    case r1600x900  = "1600x900"
    case r1600x1000 = "1600x1000"
    case r1600x1200 = "1600x1200"
    case r1600x1280 = "1600x1280"
    case r3840x1600 = "3840x1600"
    case r1920x1080 = "1920x1080"
    case r1920x1200 = "1920x1200"
    case r1920x1440 = "1920x1440"
    case r1920x1536 = "1920x1536"
    case r2560x1440 = "2560x1440"
    case r2560x1600 = "2560x1600"
    case r2560x1920 = "2560x1920"
    case r2560x2048 = "2560x2048"
    case r3840x2160 = "3840x2160"
    case r3840x2400 = "3840x2400"
    case r3840x2880 = "3840x2880"
    case r3840x3072 = "3840x3072"
}
```

**与 `atleast` 的差异**：`atleast` 是**任意分辨率字符串**（见 6.2.3），客户端按当前屏物理像素实时构造，只校验格式 `^\d+x\d+$`、**不做上界校验**（`50000x50000` 服务端正常接受并返回 200 + 空数组）。而 `ratios` / `resolutions` 是**封闭枚举**，值域极窄，不存在自由文本的语义空间。

**禁止**：新增未在枚举中的取值、或退回自由字符串拼接。

---

### 6.2.5 筛选维度分档规则（推导值，非官方字段）

wallhaven API **没有提供「4K/5K/8K」这类分辨率档位字段**（已实测确认）。若 UI 需要按分辨率分档，只能自行推导。

**两条独立推导轴，禁止混用维度：**

| 轴 | 依据字段 | 用途 | 禁止 |
| --- | --- | --- | --- |
| `pixelScore` | `dimension_x × dimension_y`（物理像素面积） | 判断清晰度、是否需放大、atleast 筛选 | 不得与 file_size 混用 |
| `visualScore` | `file_size` | 判断下载成本、流量消耗 | 不得与像素数混用 |

同一条 `WallpaperItem` 同时计算两个分值，**各自独立分档**。

**为什么必须分两轴**：一张 5120×2880 的 JPEG 可能只有 300KB（纯色渐变压缩率高），也可能有 8MB（高频细节）。用体积推断清晰度会误判，用像素推断流量同样会误判。

**强制标注**：这两项都是**推导值，不是官方字段**。文档、UI、埋点中引用时必须写明「架构侧推导」。若 wallhaven 后续提供官方档位字段，需重新评估此推导并废弃。

**PNG/JPEG 格式徽标不建议展示**：实测 `type:png` = 115,989（23.1%）、`type:jpg` = 385,667（76.9%），格式维度上只有两种，徽标信息量接近零。若需要占用位展示信息，优先展示 `file_size`。

### 6.3 物理像素几何与显示器标识（F2 硬要求）

这一节是**静默错误高发区**：预览正确但实际设置后错位，不崩溃，用户只会认为「这 App 壁纸质量差」。

**所有缩放/裁切/填充判断必须基于物理像素**，不得用逻辑点：

```swift
let scale = screen.backingScaleFactor
let physical = CGSize(width: screen.frame.width * scale,
                      height: screen.frame.height * scale)
```

用逻辑点会错的三种场景：

1. MacBook 内屏 2x 与外接 4K 1x，逻辑点可能同为 16:10，但 4K 屏物理像素是内屏的 2.25 倍。按逻辑点算会让 4K 屏的图被放大到模糊。
2. 用户切换「更大文字」缩放时，逻辑点变化而 `backingScaleFactor` 不变。只看逻辑点会静默算错。
3. 「这张图 3840×2160，屏幕物理像素也是 3840×2160，刚好 1:1 清晰」——只有物理像素能给出这个判断。

**显示器标识必须两级**（编译核验见 `VERIFIED-API.swift` §6，陷阱详见 ADR-007 Trap 7/8/9）：

| 层级 | 键 | 用途 | 稳定性 |
| --- | --- | --- | --- |
| 会话级 | `CGDirectDisplayID`（`screen.cgDirectDisplayID`，Optional） | 运行期索引、窗口与播放器绑定 | 单次运行内唯一 |
| 持久级 | `v\(vendor)-m\(model)-s\(serial)` | SQLite `display_assignments` 存储键 | 硬件不变时跨重启稳定 |

**为什么不能用 `CGDirectDisplayID` 直接落库**：

依据 Apple 官方文档 [CGDirectDisplayID](https://developer.apple.com/documentation/CoreGraphics/CGDirectDisplayID) 的 Discussion 段（**注意：该表述在 SDK 头文件中不存在，仅见于 Apple 在线文档**；`CGDirectDisplay.h` 只声明 `typedef uint32_t CGDirectDisplayID`，未说明持久性）：

> When a monitor is attached, Quartz assigns a unique display identifier (ID). **A display ID can persist across processes and typically remains constant until the machine is restarted.**
>
> When assigning a display ID, Quartz considers the following parameters: Vendor, Model, Serial number, Position in the I/O Kit registry

关键在 *typically* 而非 *always*——Apple 未承诺跨重启稳定。此外社区有记录显示多 GPU 机型上显示输出切换 GPU 时 displayID 会变化。**因此本项目按「displayID 不保证跨重启稳定」设计**，这是保守但正确的取舍。

`CGDisplayVendorNumber` / `CGDisplayModelNumber` / `CGDisplaySerialNumber` / `CGDisplayUnitNumber` 四个 API 经核验声明于 `CGDisplayConfiguration.h:352/357/362/367`，均**无 DEPRECATED 标记**，当前 SDK 下完全可用。

**绝不能用 `NSScreen.screens` 的数组下标做 key** —— 拔插显示器后数组顺序会变。

`CGDisplaySerialNumber` 为 0（部分外接屏不报序列号）时，`hardwareKey` 为 nil，该屏配置不跨重启保留。这是诚实的行为，不静默错误。

**同型号双屏的歧义（hardware_key 冲突）**：

用户接两台同型号显示器时，vendor/model/serial 完全相同，物理上是两块屏。此时 `hardwareKey` 相同，裁切焦点会互相串——同样是静默错误。

处理方式：启动时检测同组 `hardwareKey` 的屏幕数量，若 >1 则置 `hardware_key_ambiguous = 1`，UI 对该组屏幕禁用「跨重启记忆裁切焦点」（退化为每次启动询问），并提示「检测到多台相同型号显示器，无法区分」。宁可诚实告知，不静默错误。

**注意**：`NSScreen.displayID` 不存在（编译验证），正确名是 `cgDirectDisplayID` 且为 Optional。`deviceDescription` 键类型是 `NSDeviceDescriptionKey` 枚举而非 String，取标识请用 `CGDisplay*` 系列。

**F15 跨屏拼接延后的技术理由**：物理像素能力是 F15 的前置子集。F2 做对了物理像素计算，F15 在 V2 只需增加「切图 + 逐屏写入」，不需重做裁切管线。所以 F2 不要为省事用逻辑点近似——能力在 MVP 就位，F15 才是增量。

设计侧对应决策：MVP 阶段 UI 完全不渲染「跨所有显示器」选项，不做置灰占位、不做「即将推出」标签。用不了的按钮会被反复点击追问原因，消耗的是用户信任。

### 6.4 API 客户端架构

**基础**：`URLSession` + `async/await`，无 Alamofire。

理由：项目已锁定 Nuke（基于自己的 `DataLoading`），不再叠一层网络库。`URLSession` 在 Swift 6 下有完整的 Sendable 语义，`async` API 是官方一等公民。Alamofire 增加的便利（重试、拦截器）我们只需要其中两样，自建更可控且避免依赖冲突。

**认证**：`X-API-Key` 请求头。**禁止**用 `?apikey=` 查询参数（key 会进日志、浏览器历史、代理缓存）。

```swift
var request = URLRequest(url: endpoint)
request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
```

Key 从 `KeyProvider`协议取（Domain 层协议，Infrastructure 提供 Keychain 实现），使测试可注入假Key。

**令牌桶限流（45 次/分钟）**：

```swift
actor RateLimiter {
    private let capacity: Double      // 45
    private var tokens: Double        // 起始 45
    private var lastRefill: ContinuousClock.Instant

    func acquire() async throws {
        while true {
            refill()
            if tokens >= 1 {
                tokens -= 1
                return
            }
            let wait = timeUntilNextToken()
            try await Task.sleep(for: wait)
        }
    }
}
```

要点：
- 用 `actor` 隔离，手动改`DispatchQueue` 会引入 Swift 6 并发违规。
- **突发容量设45**：允许短时间突发 45 次，然后按`45/60≈0.75 次/秒` 匀速释放。这符合用户快速滚动翻页的真实行为。
- **每个请求类型都要过桶**，包括图片请求（若走自建 URLSession）与元数据请求。豁免任何一类都会击穿限额。
- 空闲时不需精确计时，`ContinuousClock` 单调，免疫系统时间跳变。

**429 退避重试**：

```
第 n 次重试延迟 = min(baseDelay × 2^(n-1) + jitter, maxDelay)
baseDelay = 1s, maxDelay = 60s, maxRetries = 4
```

- 必须加 jitter，否则多个并发请求会在同一时刻重试，形成同步重试风暴。
- 尊重 `Retry-After` 头（若服务端提供），优先于本地计算。
- 重试耗尽后向上抛`APIError.rateLimited(retryAfter:)`，UI 显示明确的下次可用时间，**不要静默失败**。

**空 Key 会被当作匿名请求（critical 静默错误）**

**禁止用 `200` 判定 Key 有效。** 实测（2026-10-08）：

| `X-API-Key` 头 | HTTP | 语义 |
| --- | --- | --- |
| 头缺失 | 200 | 匿名 |
| 头存在但值为空 | **200** | **等同匿名** |
| 值为纯空格 / 制表符 | **200** | **等同匿名** |
| 任意非空非法值（1 / 3 / 5 / 8 / 10 / 32 / 300 字符） | 401 | Key 无效 |
| `%20`（字面量，非空格） | 401 | Key 无效 |
| `null`（字面量字符串） | 401 | Key 无效 |

**根因**：wallhaven 允许匿名浏览，服务端把「空/纯空白 Key」等同于「无 Key」。

**危害等级 critical（静默错误）**：若客户端以 `200 = Key 有效` 为判据，用户输入空 Key 会「保存成功」，之后行为与未配置完全相同，**界面上没有任何异常**。用户不会发现任何问题，只会以为「这个 Key 看起来不需要配」。

**正确判定逻辑（方向不能写反）**：

```
本地预校验（发请求前）-> Key.trim() 为空或纯空白 -> 直接拦截，不发请求
发请求（Key 非空）    -> 401 = Key 无效
                     -> 200 = Key 有效
```

**200 是「非空前提下的结论」，不是「有效」的充分条件。** 把它当充分条件即产生上述静默错误。

**三条硬约束**：

| # | 约束 | 理由 |
| --- | --- | --- |
| 1 | 本地预校验必须在**发请求前**完成：`trim()` 后为空或纯空白 -> 拦截，**不发请求** | 空 Key 的200 与匿名的 200 完全相同，服务端无从区分 |
| 2 | 保存按钮可用状态由**本地预校验**决定，不由服务端响应决定 | ��则空 Key 会「保存成功」 |
| 3 | 粘贴去空格后**必须再次判空** | 纯空格 `trim()` 成空串，若不二次判空会漏过 |

**关于长度阈值**：实测长度与判定**完全无关** —— 1 字符与 300 字符均返回 401。真正的分界线只有「非空 vs 空」。

长度阈值**可作额外防御，但不得替代非空判断**。理由：用户把 Key 填成 `"a"` 时，服务端本会返回 401 给出准确信息；长度检查若先拦截，反而给出更含糊的提示，**掩盖了服务端能提供的准确信息**。

**Key 验证端点必须用 `/search`，不能用 `/settings`**：

| 端点 | 无效 Key | 无 Key |
| --- | --- | --- |
| `/api/v1/search` | **401** `{"error":"Unauthorized"}` | 200 |
| `/api/v1/settings` | **404** `{"error":"Nothing here"}` | 401 |

`/settings` 是「读取用户设置」端点，仅当用户**已开启 API 访问授权**时才返回数据。仅有 API Key 但未授权的用户请求它会得到 404 —— 这与「Key 无效」是两件不同的事。

**若用 `/settings` 验证，一个完全有效的 Key 会被判为无效，用户根本配不进去。**

`/search` 在六类边界场景下（无效 Key / 超长 / 特殊字符 / 短 Key / 有效 Key / 无参数）**均不返回 404**，仅在认证失败时返回 401。**所以设置页当前不需要 404 分支**，为不可达状态写 UI 分流是死代码。

若将来引入 `/settings`，404 会立即变成真实且语义不同的分支 —— **届时切勿归因为「Key 无效」**。

**NSFW 权限的真实语义（修正此前推断）**

此前本文件写「401 需区分 NSFW 无权限与 Key 无效」，**该表述与实测不符，已修正**。实测：

| 场景 | HTTP | 说明 |
| --- | --- | --- |
| SFW + 无效 Key | 401 | Key 无效 |
| SFW + 无 Key | 200 | 匿名可用 |
| **NSFW(`purity=001`) + 无效 Key** | **401** | Key 无效 |
| **NSFW(`purity=001`) + 无 Key** | **200，但 `total=0`** | **不是 401，是空结果** |
| `purity=100`（仅 SFW）+ 无 Key | 200，`total=501661` | 匿名可用 |
| 无 `purity` + 无 Key | 200，`total=501661` | 匿名可用 |

**结论：401 只表示「Key 无效」，与 purity 无关。** 匿名请求 NSFW 时服务端返回 200 + 空数组（`total=0`），**而非 401**。

因此不需要「分别探测 SFW 与 NSFW 来分类 401」—— 401 只有一个含义。NSFW 权限不足的表现是**空结果**，不是 401。

**实现**：
- `401` -> `.invalidAPIKey`，文案「API Key 无效」
- NSFW 请求返回 200 + `total=0` 且用户已配置 Key -> 「此 Key 无 NSFW 访问权限」（这是**权限**问题，不是 Key 无效）
- 判定 NSFW 权限需在用户已配置 Key 的前提下进行

**分页**：每页 24 条，`meta.last_page` 是上界。**不得假设无限滚动** —— 到达 `last_page` 必须停止并提示，这是 PRD 边界条件。`page` 发请求前必须校验 `>= 1`（`page=0` / `page=-1` 实测返回 500，见 §6.2.3）。

**响应处理顺序（硬约束）**：

```
1. 拿到 (data, response)
2. 先判 response.statusCode      ← 必须第一步
3. 非 2xx → 直接走错误分支，完全不碰 data
4. 2xx→ 才尝试 JSONDecoder 解码
```

**禁止先解码再判状态码。** wallhaven 错误路径下的响应体可能是 HTML（取决于 `Accept` 头），先解码会把「参数非法」误报成「数据解析失败 / 网络异常」。详见 §6.2.3 的实测矩阵。

**必须显式发送 `Accept: application/json`**。不带该头时，错误响应体会变成 HTML 页面而非 JSON。

**`APIError` 分类**（三类不可合并，错误文案需据此区分）：

| 类别 | 触发条件 | 文案方向 |
| --- | --- | --- |
| `.invalidParameter` | 本地校验未通过，**请求未发出** | 「你的筛选条件有问题」 |
| `.serverError(status)` | 5xx 且本地参数合法 | 「wallhaven 服务异常」 |
| `.networkUnavailable` | `URLError` 族 | 「网络不可用」 |
| `.rateLimited(retryAfter)` | 429 | 「请求过于频繁」 |
| `.decodingFailed` | 2xx 但解码失败 | 「服务返回了无法解析的数据」 |

**`.decodingFailed` 与 `.serverError` 不可合并**，否则又回到了「一律显示加载失败」这个静默错误。

**空态不是第六类错误**：`atleast=20000x20000` 这类「格式合法但无匹配」返回 **200 + 空数组**，是成功响应，不是错误。UI 应显示「没有符合此组合的壁纸」，不显示任何错误提示，更不显示「加载失败」。

区分信号只有一条：**请求是否发出**。
- 请求**未发出**（本地校验拦下）→ 错误态，提示参数无效
- 请求**已发出**且返回 200 + `data: []` → 空态，提示无匹配

客户端**不需要**为 `atleast` 做上界校验（`50000x50000` 格式合法、服务端正常接受），只校验格式 `^\d+x\d+$`。

**离线兜底**：网络失败时降级到本地导入库（PRD F8），UI 明确标注「离线模式」，不静默显示空列表。

**Xcode Preview**：API 层用协议注入，预览时提供 `MockWallhavenClient` 返回 fixture 数据。**不在 Preview 里打真实网络请求**（Preview 反复求值会迅速耗尽限流额度）。

---

## 7. 状态管理

**选定：`@Observable`（Observation 框架），全项目统一，不混用。**

| 维度 | `@Observable` (Observation) | `ObservableObject` + `@Published` |
| --- | --- | --- |
| 依赖注入 | `@Environment(Type.self)` | `@EnvironmentObject` |
| 视图消费 | `@State` / 属性直接读 | `@StateObject` / `@ObservedObject` / `@EnvironmentObject` |
| 性能 | 属性级追踪，未读的属性变更不触发重绘 | 对象级，任一`@Published` 变更触发全对象观察者重绘 |
| Swift 6 | 天然适配 | 需 `@MainActor` 标注配合 |
| 与 Nuke 13 | 一致（`ImagePipelineActor` 同为actor 隔离思路） | 不一致 |

选 `@Observable` 的决定性理由是性能：瀑布流滚动时，逐格图片加载状态变化极其频繁。`ObservableObject` 的对象级重绘在这种场景是明确的性能隐患；而 `@Observable` 只追踪视图实际读取的属性，配合 Nuke 的按请求状态可精准控制失效范围。

**迁移策略**：新工程，无需迁移存量代码。规则：
1. 全项目禁止 `ObservableObject` / `@Published` / `@ObservedObject` / `@StateObject` / `@EnvironmentObject`。
2. 状态对象加 `@Observable` + `@MainActor`（UI 相关）或 `actor`（数据相关）。
3. 跨视图共享用 `@Environment(Type.self)` + `@Bindable`。
4. 枚举取代布尔标志（`LoadState` 而非 `isLoading: Bool` + `error: Error?`），避免非法组合状态。
5. CI 加静态检查拦截 `ObservableObject` 关键字，防止回潮。

---

## 8. 已知风险与待验证项

| # | 项 | 等级 | 说明 | 验证时机 |
| --- | --- | --- | --- | --- |
| 1 | `xcode-select` 未指向 Xcode | **P0 阻塞** | `xcodebuild` 全部不可用，CI 门禁无法建立 | 立即，需用户执行 sudo |
| 2 | App Sandbox 下桌面层窗口行为 | P0 | 未实测，可能需关闭沙盒 | Phase 1最小实验 |
| 3 | Nuke 13.2.0 在 Xcode 27.0 兼容性 | P1 | Nuke 13.0.1 曾修Xcode 26 兼容问题，27.0 需验证 | Phase 1 首次集成 |
| 4 | 系统壁纸 plist 与 API 设置不一致 | P2 | 用户在系统设置看到的与实际不符 | V1 上线后观察 |
| 5 | 小图放大模糊无法参数规避 | P2 | 系统不支持 `ProportionallyDown` | UI 层提示 |
| 6 | 沙盒下 `setDesktopImageURL` 权限 | P1 | 需实测 | Phase 1 |
| 7 | WEBM 播放不支持 | 已决策 | 不集成 FFmpeg，明确不支持 | V2 |
| 8 | 菜单栏面板与主窗口状态同步 | P1 | 双进程/双场景状态一致性 | Phase 2 |
| 9 | F9 依赖 F8 导入管线 | P0 | F9 无法独立交付，两者须同批 | V2 排期时按 F8 -> F9 顺序 |

---

## 9. 端到端验证步骤

架构交付的完成定义不是「文档写完」，而是以下步骤可从头到尾跑通。

**Step 0 — 环境门禁**

**本机 `xcode-select -p` 指向 `/Library/Developer/CommandLineTools`**，直接调用 `xcodebuild` / `xcrun` 会报错：
```
xcode-select: error: tool 'xcodebuild' requires Xcode, but active developer
directory '/Library/Developer/CommandLineTools' is a command line tools instance
```

**根治命令（需 sudo，需用户执行）**：
```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
```

**未根治前的临时方案：所有命令显式指定 `DEVELOPER_DIR`**（已实测有效）：
```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

# 验证
"$DEVELOPER_DIR/usr/bin/xcodebuild" -version   # 期望：Xcode 27.0 / build 27A266a
"$DEVELOPER_DIR/usr/bin/xcrun" --show-sdk-version # 期望：27.0
```

后续所有 `xcodebuild` / `xcrun` / `swiftc` 调用均需带此环境变量。

**Step 1 — API 核验门禁**

```bash
swiftc -typecheck -sdk "$(xcrun --show-sdk-path)" \
  -target arm64-apple-macosx26.0 docs/VERIFIED-API.swift
```
期望：零输出（零错误零警告）。任何 Apple API 调用必须先过此门。

**Step 2 — 依赖可解析**

```bash
swift package resolve
```
期望：`Nuke 13.2.0` 与 `GRDB.swift 7.11.1` 均解析成功。

**Step 2.5 — 门禁全绿**

```bash
bash scripts/api-gate.sh# ADR-007 API 存在性核验
bash scripts/security-gate.sh         # ADR-006/008 安全
bash scripts/convention-gate.sh       # ADR-004/009 规范
```
期望：三者均输出 PASS。

**注意 BSD grep 陷阱**：macOS 自带 BSD grep，`-E` 不支持 `\s`/`\d`，basic 模式不支持 `\|`。本次门禁首版有 3 条规则因此静默失效（返回 PASS 但抓不到违规）。**任何新增门禁规则必须先做负向测试**——注入违规、确认拦截、清理、确认通过。门禁的假阴性比没有门禁更危险。

**Step 3 — 静态壁纸端到端（核心闭环）**

1. 配置 API Key（SFW 可跳过）
2. 主窗口显示首屏 24 张缩略图，2 秒内完成
3. 滚动触发预取，无空白闪烁
4. 点击某张 -> 预览 -> 设为壁纸
5. 桌面出现该壁纸
6. 双屏 + 分屏不同壁纸：两屏显示不同图，填充模式生效
7. 菜单栏面板：上/下/随机切换壁纸，主窗口状态同步

**Step 4 — 限流边界流（错误路径）**

1. 快速滚动 60 次触发 429
2. 断言 UI 显示明确限流提示与重试倒计时，不静默失败
3. 无效 API Key 请求 NSFW -> 断言区分「Key 无效」与「无 NSFW 权限」

**Step 5 — 降级流（错误路径）**

1. 断网后启动 -> 断言降级到本地导入库，UI 标注离线模式
2. 无可用显示器 -> 断言不崩溃，配置保留
3. 主窗口崩溃 -> 断言菜单栏功能仍存活

**Step 6 — 动态壁纸（V2）**

1. 设置 MP4 动态壁纸 -> 断言逐屏独立循环播放
2. 锁屏/解锁 -> 断言暂停与恢复
3. 切换 Space -> 断言静帧不消失
4. 内存压力注入 -> 断言按§5.6 顺序降级
5. 播放 WebM -> 断言明确的不支持提示，不静默黑屏

**回归**：上述每条暴露的问题沉淀为回归用例，失败即阻断合并。

---

## 10. 明确不做（架构层）

| 项 | 原因 |
| --- | --- |
| 集成 FFmpeg | 体积、许可证、供应链风险，换一个格式不划算（§5.6） |
| 依赖 `WallpaperExtensionKit` 私有 API | Apple 可随时移除，PRD 已列风险（§5.1） |
| WebView 壁纸渲染 | 功耗不可控，PRD 已否决（§5.1） |
| 自研图片加载管线 | 静默错误风险高，Nuke 已给编译期保证（§3.1） |
| Alamofire / 其他网络库 | 官方 URLSession 已足够，避免依赖冲突（§6.3） |
| 自建数据库层 | GRDB 已在Swift 6 下全量 Sendable 审计（§3.2） |
| 跨屏状态同步的分布式方案 | 单主进程 + 观察即可，不引入额外一致性机制 |

---

## 11. ADR 索引

| ADR | 决策 |
| --- | --- |
| ADR-001 | 图片加载选用 Nuke 13.2.0 |
| ADR-002 | 本地存储选用 GRDB.swift 7.11.1（DatabasePool） |
| ADR-003 | 动态壁纸采用桌面层窗口 + AVPlayerLayer，逐屏 XPC Service 隔离 |
| ADR-004 | 状态管理统一使用 Observation（@Observable） |
| ADR-005 | 图标库锁定 SF Symbols |
| ADR-006 | API 客户端自建令牌桶 + X-API-Key 头，不引入网络库 |
| ADR-007 | macOS 26 弃用 API 的规避清单（编译核验产出） |
| ADR-008 | 不集成 FFmpeg，不依赖私有 API |
| ADR-009 | 代码组织与单文件 300 行约束 |

---

## 12. 交付物清单

| 路径 | 内容 |
| --- | --- |
| `docs/ARCHITECTURE.md` | 本文件 |
| `docs/VERIFIED-API.swift` | 编译核验样本（零错误零警告），可复现 |
| `docs/decisions/ADR-001..009.md` | 决策记录 |
| `scripts/api-gate.sh` | Apple API 存在性门禁 |
| `scripts/security-gate.sh` | 安全门禁（明文 Key / query 传参 / 私有 API） |
| `scripts/convention-gate.sh` | 规范门禁（行数 / 状态管理 / 分层依赖） |
| `.github/workflows/gates.yml` | CI：三个门禁 + 构建 |
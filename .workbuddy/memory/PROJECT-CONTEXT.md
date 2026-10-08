# IHaven 项目上下文（重写版）

## 背景
- 现有工程是 2020 年的雏形（IHaven），已废弃重写。原代码在 git tag 1.2 (a8cdcaf)，分支 baseline/pre-upgrade。
- 保留仓库历史，新代码全新重写。
- 现有 macOS 26 签名坑已定位并解决：App Sandbox + 开发者证书 + 无 profile 会 SIGTRAP，Debug 用 ad-hoc 签名（CODE_SIGN_IDENTITY = "-"）。

## 核心需求（Phase 0 已确认）
- **产品形态**：双模式融合。主窗口做深度浏览管理（瀑布流/筛选/收藏/多屏），菜单栏面板做高频快捷（搜索/换壁纸/上下张）。数据共享状态同步。
- **壁纸能力**：静态壁纸 + 动态壁纸播放（GIF/WEBM/MP4，逐屏循环、CPU 可控）+ 内置简易动态壁纸编辑器（静态图/短视频裁成循环视频，调速度/裁剪区域）。
- **账号**：引导用户自填 wallhaven API Key，解锁 NSFW + 同步账号默认筛选设置。Key 存本地 Keychain。
- **技术底座**：SwiftUI 全新重写，macOS 26+，Observation + async/await。

## API 约束（wallhaven.cc/help/api）
- 限流 **45 次/分钟**，超限 429。
- 每页 **24 条**。分页非真正无限。
- NSFW 需 API key，无效 key 返回 401。
- 认证：URL ?apikey= 或请求头 X-API-Key（**优先用头**，避免 key 出现在日志/历史）。
- 端点：
  - GET /api/v1/search —— q(支持 +tag -tag @user id: type: like:)、categories、purity、sorting、order、topRange、atleast、resolutions、ratios、colors、page、seed、apikey
  - GET /api/v1/w/<id> —— 单壁纸详情，含 uploader、tags
  - GET /api/v1/tag/<id> —— 标签信息
  - GET /api/v1/settings?apikey= —— 用户设置（thumb_size/per_page/purity/categories/toplist_range/blacklist）
  - GET /api/v1/collections[/{user}[/{id}]] —— 收藏集
- sorting: date_added(默认)/relevance/random/views/favorites/toplist；random 用 seed 保证不重复。
- topRange 仅 sorting=toplist 时生效：1d/3d/1w/1M/3M/6M/1y。
- 响应 meta: current_page/last_page/per_page/total/query/seed。

## 已知技术约束
- macOS 26 SDK（Xcode 27）下NavigationView 已废弃→ NavigationSplitView/ NavigationStack。
- @Observable 与 @ObservedObject 不兼容，选定方案需统一。
- 动态壁纸需独立子进程 + AVFoundation/SpriteKit 类方案，需评估 CPU 与多屏策略。

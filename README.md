

<p align="center">
<img src="screenshots/logo.png" alt="IHaven" width="100">
</p>
<h1 align="center" style="font-size:36px" >IHaven</h1>
<h4 align="center" style="font-size:18px" >🍭Awesome Wallpaper App Based on SwiftUI Power By Wallhaven aimed to macOS</h4>
<p align="center"> 
<img class="for-the-badge"src="https://forthebadge.com/images/badges/made-with-swift.svg">
        <img
          class="for-the-badge"
          src="https://forthebadge.com/images/badges/ages-18.svg"
        >
        <img
          class="for-the-badge"
          src="https://forthebadge.com/images/badges/built-with-love.svg"
        >
        <img
          class="for-the-badge"
          src="https://forthebadge.com/images/badges/uses-git.svg"
        >
        <img
          class="for-the-badge"
          src="https://forthebadge.com/images/badges/fuck-it-ship-it.svg"
        >
        <img
          class="for-the-badge"
          src="https://forthebadge.com/images/badges/makes-people-smile.svg"
        ></p>
<p style="font-size:14px" >Visit website <a href="http://ihaven.laxse.cn">IHaven</a> or （release to）download. f^_^;</p>

# 本地开发（免 VPN Mock）
`wallhaven.cc` 在部分网络下需启用 VPN 才能访问，开发环境不便长期开 VPN。本项目内置了**进程内 Mock 服务**，开启后直接返回合成数据，无需任何网络即可开发调试。

启用方式（Xcode）：
1. 打开项目，`Edit Scheme → Run → Arguments → Environment Variables`
2. 添加 `IHAVEN_MOCK = 1`
3. `⌘R` 运行。瀑布流会直接加载合成壁纸（竖图 / 方图 / 横图 / 宽屏 / 超宽 五种比例循环，渐变占位图），翻页、收藏、设为壁纸均可正常走通。

关闭：删除该环境变量即切回真实 `wallhaven.cc` 服务。**真实环境零影响**——仅当 `IHAVEN_MOCK=1` 时才接管请求。

实现说明：拦截逻辑在 `Sources/IHavenApp/Infrastructure/Network/MockWallhaven.swift`，由 `IHavenApp.bootstrap()` 在启动最开头调用 `MockWallhaven.configureIfNeeded()` 注册 `URLProtocol`，拦截对 `mock.wallhaven.local` 的请求——`/api/v1/search` 返回合成 `WallhavenPage` JSON，`/thumb` 与 `/wallpaper` 路径返回进程内（CoreGraphics + ImageIO）生成的渐变 JPEG。整条链路（请求 → JSON 解码 → Nuke 预取 → 缩略图渲染 → 设为壁纸原图下载）零网络。

# Features
* Browse wallhaven.cc as a native macOS waterfall grid — infinite scroll, mixed aspect ratios, instant low-res preview that swaps to the full-resolution original (with a visible download progress bar)
* Rich filters — resolution, aspect ratio, dominant color, category, purity, sorting and time range
* Detail page — the whole image, never cropped, plus a metadata sidebar, download original and set-as-wallpaper
* Favorites library and "already applied" history, both stored locally in SQLite
* Import your own images; turn any static wallpaper into a locally generated dynamic wallpaper (breathe / pan / push-in, seamless loop, no video involved)
* Image cache on disk (Nuke `DataCache`, 512 MB) so a wallpaper you have seen is never downloaded twice — Settings ▸ Storage shows the usage and lets you clear it
* API key stays on your machine (a local file, never in logs or crash reports) and is sent as an `X-API-Key` header
* Crop before you set — pick the part of a portrait image you actually want, locked to your screen's aspect ratio, so vertical wallpapers never end up with black bars on the sides
* Chinese and English UI
* Built-in in-process mock so you can develop and debug with no network and no VPN — see below
# Screenshots
 - v1
<p align="center">
<img src="screenshots/v1.png" alt="IHaven" width="600">
</p>

 - v2
<p align="center">
<img src="screenshots/v2.png" alt="IHaven" width="600">
</p>

# Roadmap
* Menu bar panel — search, random, previous / next, one-click change, favorites, without opening the main window
* Per-screen wallpaper assignment and a fill color derived from the wallpaper's own palette
* Performance guard for dynamic wallpapers — auto-pause when the frontmost app is full screen, on low battery, or in Low Power Mode, plus a visible CPU / memory readout
* Wallpaper rotation schedule — switch by time of day or weekday
* Free-form crop aspect ratios and a cleanup policy for the derived crop files (`Application Support/IHaven/Crops/`)
* Client-side rate limiting (45 req/min token bucket) with backoff, and an offline fallback backed by the local image cache


# Localization
IHaven follows your system language and also lets you pick one manually in Settings ▸ Appearance.

Currently shipped: **Chinese (Simplified)** and **English**. Translations live in
`Sources/IHavenApp/Resources/{zh-Hans,en}.lproj/Localizable.strings`; Chinese is the development
language, so the Chinese string in the source is itself the localization key. Adding a language means
adding one `.lproj` with the same keys — `scripts/build-and-package.sh` fails the build if the two
sides ever drift apart in key count.

# License
IHaven itself is licensed under the  MIT License  license.

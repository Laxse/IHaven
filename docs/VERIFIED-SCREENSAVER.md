# VERIFIED-SCREENSAVER.md：macOS「把本地图片设为屏保」实测存档

> **配套于 ADR-007 Trap 20**。Traps 1–17 核验 macOS 系统 API（编译核验），Traps 18–19 核验 wallhaven 服务端 API（curl 实测），**Trap 20 与本文档核验的是「某个能力是否存在」**——方法是「公开 API 存在性核验 + 默认域读写实测 + 系统代码字符串取证」三者交叉。
>
> 核验对象：macOS 上「把一张本地图片设置为屏幕保护程序」的可行实现路径
> **核验日期：2026-10-14**
> 核验工具：`defaults`、`sw_vers`、`PlistBuddy`、`plutil`、`strings`、`swiftc` + `ScreenSaver.framework`（未签名探针二进制）、`pgrep`、dyld 共享缓存字符串取证
>
> **机器环境（一并记录，供后续复现对照）**：
>
> | 项 | 值 |
> | --- | --- |
> | `ProductVersion` | 27.0.1 |
> | `BuildVersion` | 26A434 |
> | 架构 | `arm64`（Apple silicon） |
> | Xcode / SDK | Xcode 27.0（Build 27A266a），`MacOSX.sdk` Version 27.0 |
> | Swift | 6.4（`swiftlang-6.4.0.34.1`） |
> | 屏保初始状态 | `defaults -currentHost read com.apple.screensaver` 返回 `Domain 'com.apple.screensaver' not found.`，`~/Library/Preferences/ByHost/` 下无任何 screensaver plist |
>
> **回滚声明（本次调研已完成）**：调研过程中写入本机的所有偏好设置**已全部回滚**。恢复后复测：`defaults -currentHost read com.apple.screensaver` 回到 `Domain not found`；`~/Library/Preferences/ByHost/` 下由本次测试创建的 `com.apple.screensaver.*.plist`、`com.apple.ScreenSaverPhotoChooser.*.plist`、`com.apple.ScreenSaver.iLifeSlideShows.*.plist` 三个文件已删除；非 ByHost 的 `com.apple.ScreenSaverPhotoChooser.plist` 已删除；`cfprefsd` 已 HUP 刷新缓存；临时目录 `/tmp/ihaven-sstest`（含测试图片与探针源码、二进制）已整体删除。**调研全程未修改项目内任何源码文件。**

## 核验方法

1. **公开 API 存在性以 SDK 头文件为准**，不以记忆或网络文章为准。判断「能不能做」先看有没有公开入口，再看有没有替代路径。
2. **系统内部行为以二进制字符串取证为准**。`ScreenSaver.framework` 等系统二进制本体在 dyld 共享缓存中（`strings` 直接读磁盘文件只得到极少量字符串），因此取证方式是**在 dyld 共享缓存里定位字符串偏移，再取偏移附近上下文**，以确认归属模块。
3. **所有候选路径必须在真机上跑一遍**，并记录观测信号是什么。凡「读取成功」不等于「系统消费了它」的，必须给出第二个独立观测来区分（见 §5）。
4. 凡本次未能驱动的，一律标注「**未实测**」，**禁止凭猜填充**。

---

## 1. 公开 API 不存在

**结论：macOS 上没有任何公开 API 可以设置「当前使用哪个屏保」，更没有「把某一张图设为屏保」的 API。**

| 核验项 | 事实 | 证据 |
| --- | --- | --- |
| `NSWorkspace` | 只有 `setDesktopImageURL(_:for:options:)` / `desktopImageURL(for:)` / `desktopImageOptions(for:)`。**对整个 `NSWorkspace.h` 做 saver / idle / lockscreen 检索，零命中** | SDK 路径 `.../MacOSX.sdk/System/Library/Frameworks/AppKit.framework/Headers/NSWorkspace.h` |
| `ScreenSaver.framework` 公开头文件 | 只剩 `ScreenSaver.h`、`ScreenSaverDefaults.h`、`ScreenSaverView.h`。**`ScreenSaverModule.h` 已被移除**——历史上唯一能枚举/选择屏保模块的公开类已不存在 | SDK 路径 `.../MacOSX.sdk/System/Library/Frameworks/ScreenSaver.framework/Headers/` |
| `ScreenSaverDefaults` | 是公开类，`defaultsForModuleWithName:` 可用；但按头文件注释，它的语义是「把偏好**关联到你自己的那个屏保模块**」，**不是选择用哪个屏保** | 同一头文件原文：*instantiate this class using the `defaultsForModuleWithName:` method* |
| 私有框架 | 真正能写屏保的实现位于 `WallpaperExtensionKit` / `WallpaperServices` / `WallpaperSettingsUI` 等私有框架（SDK 的 `System/Library/PrivateFrameworks/` 下） | SDK 目录枚举；**全部不可用**（见 §3 方案 D） |

**因此不存在 `setScreenSaver(fileURL:)` 这种 API 可以对接。**

---

## 2. 现代屏保的真实架构

以下均为本机实测枚举：

### 2.1 系统的 `.saver` 只剩两个，其余全部是 ExtensionKit `.appex`

`/System/Library/Screen Savers/` 目录下仅剩：

- `Random.saver`（`com.apple.ScreenSaver.Random`）
- `FloatingMessage.saver`（`com.apple.ScreenSaver.FloatingMessage`）

其余屏保全部位于 `/System/Library/ExtensionKit/Extensions/`，扩展点统一为 `NSExtensionPointIdentifier = com.apple.screensaver`：`Drift.appex`、`Hello.appex`、`Monterey.appex`、`Ventura.appex`、`Computer Name.appex`（`com.apple.ScreenSaver.Computer-Name`）、`Album Artwork.appex`（`com.apple.screensaver.AlbumArtwork`），以及关键的：

- **`iLifeSlideshows.appex`**，bundle id `com.apple.ScreenSaver.iLife-Slideshow-Extension`，`CFBundleDisplayName = Photos`

系统侧也可证：`ScreenSaver.framework` 的 `Resources/Info.plist` 内含 `NSExtensionSDK` → `com.apple.screensaver` → `NSExtensionPointName = com.apple.screensaver`，即**屏保已整体改为 ExtensionKit 扩展模型**。

### 2.2 旧 pref pane 已空壳

`/System/Library/PreferencePanes/DesktopScreenEffectsPref.prefPane`（历史上的「桌面与屏幕保护程序」）**目录下已无 `Contents/`**，为残留空壳。

### 2.3 设置 UI 挂在 Wallpaper.appex

- 屏保选择 UI：`com.apple.Wallpaper-Settings.extension`（`Wallpaper.appex`），内含 `ScreenSaverSettingsController`、`ScreenSaverSettingsViewModel`、`LegacyScreenSaverOptionsView`、`LegacyPhotosScreenSaverOptions`。
- 空闲时长 UI：`com.apple.Lock-Screen-Settings.extension`（`LockScreen.appex`），内含 `ScreenSaverDelayView`，并引用 `ScreenSaverDefaults` 与域 `com.apple.screensaver`。
- **全系统没有独立的「Screen Saver」设置面板扩展**（对 `/System/Library/ExtensionKit/Extensions/` 下所有 `.appex` 的 bundle id / display name 做过检索）。

### 2.4 幻灯片屏保的配置粒度是目录，不是单文件

`iLifeSlideshows.appex` 二进制内含 `defaultsForModuleWithName:`、`styleKey`、`spansScreensKey`、`listOfPhotoPathsFromSelectedSource`；而「图片来源」由系统框架里的 `ScreenSaverPhotoChooser` 类负责（见 §3 的域归属说明）。其可配置项为**目录**（`SelectedFolderPath`）或**相册**（`SelectedMediaGroup`），**没有「单个文件」这一档**。

---

## 3. 候选路径盘点

### 方案 A：历史 `defaults` 写入（最常被引用的方案）

```
defaults -currentHost write com.apple.screensaver moduleDict \
    -dict moduleName iLifeSlideshows path /System/Library/ExtensionKit/Extensions/iLifeSlideshows.appex type 0
defaults -currentHost write com.apple.ScreenSaverPhotoChooser SelectedSource     -int 3
defaults -currentHost write com.apple.ScreenSaverPhotoChooser SelectedFolderPath -string /path/to/folder
defaults -currentHost write com.apple.ScreenSaverPhotoChooser ShufflesPhotos     -bool false
defaults -currentHost write com.apple.ScreenSaver.iLifeSlideShows styleKey       -string Classic
killall -hup cfprefsd
```

**域归属（易错点，网上脚本普遍混用）**：`SelectedSource` / `SelectedFolderPath` / `ShufflesPhotos` / `SelectedMediaGroup` / `LastViewedPhotoPath` / `CustomFolderDict` 属于 **`com.apple.ScreenSaverPhotoChooser`**；`styleKey` / `spansScreensKey` 才属于 **`com.apple.ScreenSaver.iLifeSlideShows`**。取证：dyld 缓存中 `ScreenSaverPhotoChooser` 类的字符串表里 `com.apple.ScreenSaverPhotoChooser`、`SelectedSource`、`SelectedFolderPath`、`ShufflesPhotos`、`SelectedMediaGroup`、`LastViewedPhotoPath` 连续相邻，且符号名 `- [ScreenSaverPhotoChooser changeToSourceType:identifier:persistChange:]`、`-[ScreenSaverPhotoChooser listOfPhotoPathsFromSelectedSource]` 可证。

- **是否实测**：是（见 §4）。
- **私有 API**：否。
- **TCC**：否（见 §3 的权限总表）。

### 方案 B：用公开 API `ScreenSaverDefaults` 写同一批偏好

```swift
import ScreenSaver

let d = ScreenSaverDefaults(forModuleWithName: "com.apple.ScreenSaverPhotoChooser")
d?.set(3, forKey: "SelectedSource")
d?.set("/path/to/folder", forKey: "SelectedFolderPath")
d?.synchronize()
```

- **是否实测**：是。用 `swiftc` 编译的**未签名**（无 entitlements）探针二进制可正常取得实例、`synchronize()` 返回 `true`，**全程无 TCC 弹窗**，落盘到 `~/Library/Preferences/ByHost/com.apple.ScreenSaverPhotoChooser.<UUID>.plist`。
- **私有 API**：否（`ScreenSaverDefaults` 是公开类）。
- **TCC**：否。
- **与方案 A 的关系**：写入的是同一批值，因此**与方案 A 同命运**——§5 的结论对两者同时成立。

### 方案 C：AppleScript 经 System Events 设置

```applescript
tell application "System Events" to set current screen saver to screen saver "Photos"
```

- **是否实测**：否（本机未执行，原因见下）。
- **私有 API**：否，但需 Apple Events（Automation）授权 → **会弹「IHaven 想要控制 System Events」**。
- **TCC**：**是**，且对本项目尤其严重：应用为 **ad-hoc 签名**（无 Developer ID、CDHash 每次重建都变），TCC 的 Automation 授权记录绑定签名身份，**每次重签会让已授予的授权失效 → 用户被反复弹窗**。
- **兼容性**：macOS 14 起与方案 A 同步失效（Apple 官方回复，见 §5）。

### 方案 D：改写现代 Wallpaper Store（私有路径）

- 目标文件：`~/Library/Application Support/com.apple.wallpaper/Store/Index.plist`。实测该文件含 `Idle` 类型记录（`Type: idle`，`Choices[].Provider`）；dyld 缓存中存在 provider `com.apple.wallpaper.choice.screen-saver`（与 `choice.image`、`choice.color`、`choice.ventura` 等并列）。
- 写入通道：私有 XPC `com.apple.wallpaper` + 权限 **`com.apple.private.wallpaper`**（该 entitlement 字符串在 dyld 缓存中出现）。
- **是否实测**：否 —— **不可达**，无需实测。
- **私有 API**：**是**（`WallpaperExtensionKit` 等）。
- **否决理由（双重）**：①ad-hoc 签名绝无可能获得 `com.apple.private.wallpaper`；②`scripts/security-gate.sh` 第 4 条显式禁止 `dlopen` 与 `WallpaperExtensionKit`。

### 方案 E：App Intent（存在，但第三方不可调用）

见 §6。

### 兼容性矩阵

| 路径 | 12 及更早 | 13 | 14 Sonoma | 15 Sequoia | 26–27 |
| --- | --- | --- | --- | --- | --- |
| A 历史 defaults | 有效 | 大部分仍有效 | **失效** | 失效 | 失效 |
| B `ScreenSaverDefaults` | 有效 | 大部分仍有效 | **失效** | 失效 | 失效 |
| C System Events AppleScript | 有效 | 有效 | **失效** | 失效 | 失效 |
| D 私有 Wallpaper XPC | 不存在 | 不存在 | 可行（需私有权限） | 可行 | 可行（需私有权限） |
| 公开 API | 无 | 无 | 无 | 无 | 无 |

### 权限总表

| 关注点 | 结论 | 依据 |
| --- | --- | --- |
| 写 `~/Library/Preferences` 下的 plist | **不触发 TCC**（该目录不是 TCC 受保护位置） | 实测：shell 与未签名二进制写 `ScreenSaverDefaults` 均无弹窗 |
| 写 app 自己的 `~/Library/Application Support/IHaven/` | 无需任何授权 | 标准行为 |
| 写 `~/Pictures`、`~/Downloads`、`~/Documents`、`~/Desktop` | **会触发「文件与文件夹」TCC 弹窗**（非沙箱 app 同样会弹） | 文档声称 → 降级方案的素材目录**不得**放这些位置 |
| Apple Events / System Events | **会弹 Automation 授权**；ad-hoc 签名下每次重签都会失效 | 文档声称 + ad-hoc 签名属性推理 |
| 私有 entitlement | 需 `com.apple.private.wallpaper`，ad-hoc 不可获得 | 实测：dyld 缓存中出现该 entitlement 字符串 |

---

## 4. 实测记录（本机 macOS 27.0.1）

| 编号 | 实验 | 结果 |
| --- | --- | --- |
| 1 | `defaults -currentHost read com.apple.screensaver` 基线 | `Domain 'com.apple.screensaver' not found.`；ByHost 下无任何 screensaver plist |
| 2 | 写 `moduleDict` + `idleTime` | 立即写入 `ByHost/com.apple.screensaver.<UUID>.plist`，`defaults -currentHost read` 可读回，**无弹窗** |
| 3 | 未签名 Swift 探针调 `ScreenSaverDefaults(forModuleWithName:)` 写入 | `synchronize()` = `true`，落盘到 ByHost 同名 plist，**无弹窗** |
| 4 | `SelectedSource` 遍历 0–8 共 9 组，固定 `SelectedFolderPath` 指向仅含 1 张图的目录，每组启动引擎约 12 秒 | **9/9 均未产生 `LastViewedPhotoPath`**（该键只有引擎真的显示过图片才会被写回） |
| 5 | `moduleDict` 写法矩阵 4 组（`moduleName` 分别取 `iLifeSlideshows` / `iLifeSlideshows.appex` / bundle id；`path` 分别指向目录与 `.appex` 本身），每组全屏启动约 9 秒 | **4/4 均未产生 `LastViewedPhotoPath`，且未观察到任何屏保扩展子进程** |
| 6 | 写入 `idleTime = 20`，静置 30 秒 | 屏保**未触发**。说明 `com.apple.screensaver` 已不是空闲时长的权威来源（尽管 `LockScreen.appex` 仍引用该域） |
| 7 | dyld 共享缓存字符串计数 | `moduleDict` ×3、`PhotoChooser` ×103、`SelectedFolderPath` ×1、`com.apple.ScreenSaver.iLifeSlideShows` ×1、`idleWallpaper` ×6 |
| 8 | 取 `moduleDict` 偏移附近上下文（ScreenSaver.framework 的日志串） | 见到 `"Did not find a module in the legacy defaults"`、`"Found legacy SSILifeMediaType, converting to iLifeSlideshows.appex"`、`"Failed to retrieve a moduleDict from SSUserDefaults!"` |
| 9 | 测试前后比对 plist 的内容与 mtime | **系统对这些 plist 零回写**（内容、mtime 均为我方写入时的状态），与「系统已不再消费这些值」一致 |

**关于「引擎拉不起来」的独立发现**：`ScreenSaverEngine` 已无法被外部手动驱动。

- 直接执行 `/System/Library/CoreServices/ScreenSaverEngine.app/Contents/MacOS/ScreenSaverEngine`（含 `-background`）→ **立即退出**。
- `open -a ScreenSaverEngine`（无参）→ **立即退出**。
- `open -a ScreenSaverEngine --args -background` → 有时可存活数秒，但上述 4/5 组实验在此模式下长跑 30 秒同样无效果。
- 原因可循：dyld 缓存中存在 `SACScreenSaverStartNow`、`SACScreenSaverStartNowWithOptions`、`SACRestartForUser`、`SACScreenSaverDidFadeInBackground` 等符号名，现代引擎由私有 XPC 驱动，不再接受手动启动。

**因此 `killall ScreenSaverEngine` 这条让改动生效的老办法，在 26/27 上无从谈起。**

---

## 5. 「读到」不等于「生效」

**这是本次核验最需要留给后来人的一条。**

`moduleDict` 这个字符串在 dyld 共享缓存里**仍然 grep 得到（×3）**，很容易被误读成「老办法还有效」。但把偏移附近的上下文取出来看，同一段日志串里有：

```
Did not find a module in the legacy defaults
Found legacy SSILifeMediaType, converting to iLifeSlideshows.appex
Failed to retrieve a moduleDict from SSUserDefaults!
```

正确的解读是：**`moduleDict` 只是 legacy fallback / 迁移路径，不是主路径。** 系统代码里还留着读它的分支，不代表屏保选择仍由它决定。

**为什么这条要单独成节**：仅凭「grep 到了 `moduleDict`」这一个证据，可以推出两个相反结论，而且正向结论（还有效）看起来更自然。本次是靠另外三个**独立**证据才把它否掉的：

1. 实验 6：写入 `idleTime = 20` 静置 30 秒不触发 → 该域已非权威；
2. 实验 9：系统对这些 plist 零回写 → 没有消费方；
3. Apple DTS 官方回复（forums thread 739314）：
   > The screen saver implementation changed a lot in macOS 14. As a side effect of that, it **no longer consults these (undocumented) user default settings**.

**方法论沉淀**：判断「某个默认值还生不生效」，不能只看「键还在不在」，必须找一个系统侧的**写回 / 行为**作为第二个观测点。这与 ADR-007 总则的「前提机制」同型——把「我还能读到它」等同于「它还在被使用」。

---

## 6. macOS 26/27 确有「壁纸兼作屏保」，但第三方改不了那个开关

**这是本次唯一真正接近「单张图当屏保」的能力，此前未被注意到。**

实测发现（均为本机取证）：

- 系统自带 `WallpaperSettingsIntents.appex` 暴露了 App Intents：`ScreenSaverModel`、`ScreenSaverNameIntent`、`changeTheScreenSaver`（文案串 `Change the screen saver`），以及 `UpdateShowWallpaperOnAllSpacesEntityValueIntent`、`UpdateShowScreenSaverOnAllSpacesEntityValueIntent`。
- 文案串 **"Show wallpaper as screen saver on main display"** 与 **"Show screen saver as wallpaper on main display"**。
- `Wallpaper.appex` 内含实例变量 **`_useAsBothDesktopAndScreensaver`** 与 `_itemsUsableAsScreenSaver`。

即：**macOS 26/27 提供一等公民能力，把当前桌面壁纸直接当作屏保**。对 IHaven 的含义是——应用已能用公开的 `NSWorkspace.setDesktopImageURL` 设壁纸，若用户一次性打开该开关，此后**每一次「设为桌面壁纸」就等价于「把这单张图设为屏保」**，且是单张图、不是轮播。

**但是第三方改不了这个开关**：

- 该开关**没有任何公开 API** 可写。
- App Intent 由系统（Siri / 快捷指令 / 聚焦）调用，**第三方 app 无法执行别的 app 的 App Intent**。
- 唯一间接路径是 AppleScript 调 `Shortcuts Events` 跑用户预先建好的快捷指令 → 需要 Automation 授权，且在 ad-hoc 签名下每次重签都会让授权失效。**否决。**

**所以可做的只有「引导」**：检测到开关未开启时提示用户，并给出直达路径让他自己开一次；不能代开，也不能宣称已开启。

---

## 7. 诚实局限

1. **我在本机无法手动驱动 `ScreenSaverEngine`**（§4 已记录三种启动方式均无效），因此第 4、5 组实验严格来说只能得出「**未观察到生效**」，**不能 100% 证明该代码路径已被删除**。存在一种可能：是我的驱动方式不对，而非系统不消费这些值。
2. 之所以仍然判定「不可用」，依据是三个**独立于该实验**的证据相互印证（实验 6、实验 9、Apple DTS 官方回复）。但**证据强度是「高度可信」而非「铁证」**。
3. **对外措辞纪律（重要）**：不要说「macOS 27 实测失效」，应该说——

   > **macOS 14 起官方回复已不再读取这些默认域，且本机无可靠效果。**

   前一说法把「未观察到」说成「已证伪」，是过度承诺；后一说法与证据强度匹配。
4. **未实测项**：方案 C（AppleScript System Events）本机未执行；`SelectedSource` 各取值的语义（哪一个对应「自选目录」）未能确定——枚举 0–8 全部无效果，无法从结果反推枚举含义；`SelectedSource` 是否应为字符串而非整数，同样未实测。
5. **跨版本声明**：矩阵中 12 / 13 / 15 三列的行为**来自文档与社区报告，非本机实测**，本机只能实测 27.0.1。

---

## 8. 降级方案排序与 API 语义建议

### 8.1 降级方案排序（含用户步骤数）

| 方案 | 做法 | 用户步骤 | 评价 |
| --- | --- | --- | --- |
| **A（推荐）** | 复制图片到 app 自己的长期素材目录（如 `~/Library/Application Support/IHaven/ScreenSaverAssets/`）+ 打开系统设置 + 给出不超过 4 步的图文指引（Screen Saver → Photos → Choose Folder → 选 IHaven 目录） | 4–6 步 | 零私有 API、零授权、跨版本稳定。**推荐。** 引导文案需按 14 之前 / 之后两套写 |
| **B（次选，仅 26+）** | 引导用户一次性打开「壁纸兼作屏保」开关（§6）。开启后，既有的「设为桌面壁纸」即等价于「单张图设为屏保」 | 一次性 2 步，之后 1 步 | 产品价值最高，真正回答了「我要这张图当屏保」。仅 26+；开关无法代开 |
| **C（保底）** | 只提供「打开屏保设置」菜单项，不做素材复制 | 1 步 | 风险最低，功能感最弱 |
| **D（不推荐）** | 直接写 `defaults` 并宣称成功 | 1 步 | **禁止。** 14+ 大概率不生效，用户点了没反应，等于交付一个坏掉的功能 |

### 8.2 素材落点警告（与现有实现相关）

`ImageFileDownloader`（`Sources/IHavenApp/Infrastructure/Image/ImageFileDownloader.swift`）落盘在 `FileManager.default.temporaryDirectory` 下的 `IHavenOriginals/`。**该目录系统可回收，不能作为屏保素材的落点**——屏保素材必须长期有效。若实施方案 A，需要单独的持久落点（建议给 `ImageDownloading.download` 增加 `destination` 参数，而不是复制一份下载器）。同时**不得**选用 `~/Pictures` / `~/Downloads` 等目录（触发 TCC，见 §3 权限总表）。

### 8.3 `setScreenSaver(fileURL:)` 式的 API 应该承诺什么

**建议不要用 `setScreenSaver` 这个名字。** 名字本身就是在承诺一个做不到的结果。建议语义：

```swift
/// 把图片准备为屏保素材：复制到长期有效的 IHaven 屏保素材目录，并返回该目录 URL。
///
/// 警告：macOS 14 起已无公开、可靠的 API 可以自动切换系统当前屏保，
/// 因此本方法**不保证**系统屏保会变成这张图；调用方必须引导用户完成最后一步。
func prepareAsScreenSaverAsset(_ fileURL: URL) throws -> URL
```

**应该承诺**：

- 图片被**复制**到一个稳定、长期有效、且 app 拥有写权限的目录；
- 返回一个可直接用于 macOS「Photos 屏保 → Choose Folder」的目录 URL；
- 明确告知用户「还剩最后一步需要你在系统设置里完成」。

**不该承诺**：

- **错误**：不承诺「屏保自动变成这一张图」——macOS 14+ 做不到；
- **错误**：不承诺「零用户操作」；
- **错误**：不要在按钮 / 菜单文案上写「设为屏保」。否则用户点了没反应，会把范围外功能感知成坏掉的功能。**建议措辞：「准备屏保素材…」或「导出到屏保文件夹」。**

**四条硬禁止**：

1. **错误**：不要写 `defaults` 之后就宣称成功；
2. **错误**：不要使用任何私有 XPC / `WallpaperExtensionKit`（`scripts/security-gate.sh` 明禁，且 ad-hoc 签名拿不到 `com.apple.private.wallpaper`）；
3. **错误**：不要把素材写到 `~/Pictures` / `~/Downloads`（触发 TCC 弹窗）；
4. **错误**：不要用 AppleScript / System Events（Automation 弹窗，且 ad-hoc 签名每次重签会让已授予的授权失效，用户被反复弹窗）。

### 8.4 项目当前状态

`docs/PRD.md` 第九节「明确不做的事」已把「屏保（Screen Saver）整合」列为 Out-of-Scope。本存档出具后该条目经重新审视，**维持不做**，登记见 `docs/decisions/OPEN-DECISIONS.md`。

---

## Related

ADR-007 Trap 20（不存在「把某一张图设为屏保」的能力；历史 defaults 路径在 macOS 14+ 已失效）
`docs/decisions/OPEN-DECISIONS.md`（2026-10-14 条目：「设为屏保」被再次提出并维持不做）
`docs/VERIFIED-WALLHAVEN-DETAIL.md`（同体例的另一份实测存档）

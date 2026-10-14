#!/usr/bin/env bash
#
# build-and-package.sh — 把 SwiftPM 可执行包成真正的 .app（Dock 图标 + 顶部菜单栏 + 应用图标）。
#
# 产物: dist/IHaven.app/Contents/{MacOS/IHavenApp, Resources/AppIcon.icns, Info.plist}
#
# 用法:
#   scripts/build-and-package.sh
#   打开: open dist/IHaven.app
#   Mock 联调（GUI 启动不继承 shell 环境变量，需直接拉二进制）:
#     IHAVEN_MOCK=1 dist/IHaven.app/Contents/MacOS/IHavenApp &
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="IHaven"
BIN="IHavenApp"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
ICON_PNG="$ROOT/Packaging/AppIcon.png"

echo "==> [1/4] swift build (release)"
swift build --disable-sandbox -c release

BIN_PATH=".build/release/$BIN"
if [ ! -x "$BIN_PATH" ]; then
    echo "error: binary missing at $BIN_PATH" >&2
    exit 1
fi

echo "==> [2/4] assemble $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH" "$APP/Contents/MacOS/$BIN"
cp "$ROOT/Packaging/Info.plist" "$APP/Contents/Info.plist"

# 本地化资源：*.lproj 必须落到 main bundle（Contents/Resources），否则设置里切换语言不会生效
# （SwiftPM 的 Bundle.module 只服务于 swift build 直接跑，.app 是自己组装的）。
# SwiftPM 资源 bundle：一并放进 Contents/Resources，让 `Bundle.module` 在 .app 里也能解析。
# 少了它，任何访问 `Bundle.module` 的代码路径都会撞上生成的 `fatalError`（实测启动即崩）。
# 界面本地化本身走的是下面复制到 Contents/Resources 的 *.lproj（Bundle.main），不依赖这个 bundle。
SPM_BUNDLE=".build/release/${BIN}_${BIN}.bundle"
if [ -d "$SPM_BUNDLE" ]; then
    cp -R "$SPM_BUNDLE" "$APP/Contents/Resources/"
    echo "    spm bundle: $(basename "$SPM_BUNDLE")"
fi

RES="$ROOT/Sources/IHavenApp/Resources"
if [ -d "$RES" ]; then
    cp -R "$RES"/*.lproj "$APP/Contents/Resources/"
    echo "    lproj: $(ls "$APP/Contents/Resources" | grep '\.lproj' | tr '\n' ' ')"
    # 防「产物与源码不同步」：两份表 key 数不一致时界面会一半英文一半中文（key 即中文原文，
    # 缺翻译的项静默回退成中文），看起来就是「切换语言没生效」—— 这里主动报错而不是静默打包。
    count_keys() { grep -cE '^"' "$1" || true; }
    EN_KEYS=$(count_keys "$APP/Contents/Resources/en.lproj/Localizable.strings")
    ZH_KEYS=$(count_keys "$APP/Contents/Resources/zh-Hans.lproj/Localizable.strings")
    echo "    keys: en=$EN_KEYS zh-Hans=$ZH_KEYS"
    if [ "$EN_KEYS" != "$ZH_KEYS" ]; then
        echo "error: 两份 Localizable.strings 的 key 数不一致（en=$EN_KEYS zh-Hans=$ZH_KEYS）" >&2
        exit 1
    fi
fi

echo "==> [3/4] build AppIcon.icns from master PNG"
if [ -f "$ICON_PNG" ]; then
    ICONSET="$(mktemp -d)/AppIcon.iconset"
    mkdir -p "$ICONSET"
    # 基础尺寸
    for s in 16 32 64 128 256 512 1024; do
        sips -z "$s" "$s" "$ICON_PNG" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    done
    # @2x 变体
    sips -z 32 32   "$ICON_PNG" --out "$ICONSET/icon_16x16@2x.png"   >/dev/null
    sips -z 64 64   "$ICON_PNG" --out "$ICONSET/icon_32x32@2x.png"   >/dev/null
    sips -z 128 128 "$ICON_PNG" --out "$ICONSET/icon_64x64@2x.png"   >/dev/null
    sips -z 256 256 "$ICON_PNG" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
    sips -z 512 512 "$ICON_PNG" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
    sips -z 1024 1024 "$ICON_PNG" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
    iconutil --convert icns "$ICONSET" --output "$APP/Contents/Resources/AppIcon.icns"
    rm -rf "$ICONSET"
    echo "    icon: $APP/Contents/Resources/AppIcon.icns"
else
    echo "warning: $ICON_PNG not found, app will use default icon" >&2
fi

echo "==> [4/4] ad-hoc codesign (local run only)"
if codesign --force --deep --sign - "$APP" 2>/dev/null; then
    echo "    codesign ok (ad-hoc)"
else
    echo "    codesign skipped (non-fatal)"
fi

echo
echo "Done: $APP"
echo "  open:        open \"$APP\""
echo "  mock debug:  IHAVEN_MOCK=1 \"$APP/Contents/MacOS/$BIN\" &"

#!/bin/sh
# 把 SwiftPM 的可执行文件组装成 build/Cove.app。没有 Xcode 工程，签名只做 ad-hoc，
# 本机运行足够；正式分发的签名与公证在 M5。
set -e
cd "$(dirname "$0")/.."
CONFIG=${1:-release}
swift build -c "$CONFIG"
APP=build/Cove.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c "$CONFIG" --show-bin-path)/Cove" "$APP/Contents/MacOS/Cove"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/CupMark.png "$APP/Contents/Resources/CupMark.png"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "$APP"

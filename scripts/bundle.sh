#!/bin/bash
# 先完整构建并签名，再替换输出包；不覆盖正在运行的应用。
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG=${1:-release}
APP=${2:-build/Cove.app}
ARCH=${COVE_ARCH:-$(uname -m)}
case "$CONFIG" in debug|release) ;; *) echo "Expected debug or release." >&2; exit 1 ;; esac
case "$APP" in *.app) ;; *) echo "Output must end in .app." >&2; exit 1 ;; esac
case "$ARCH" in arm64|x86_64) ;; *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;; esac
mkdir -p "$(dirname "$APP")"
APP="$(cd "$(dirname "$APP")" && pwd -P)/$(basename "$APP")"
if ps -axo comm= | grep -Fxq "$APP/Contents/MacOS/Cove"; then
  echo "Cove is running from $APP. Choose a separate output path." >&2
  exit 1
fi
swift build -c "$CONFIG" --arch "$ARCH"
BIN=$(swift build -c "$CONFIG" --arch "$ARCH" --show-bin-path)
STAGE=$(mktemp -d "$(dirname "$APP")/.cove-bundle.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
BUNDLE="$STAGE/Cove.app"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN/Cove" "$BUNDLE/Contents/MacOS/Cove"
cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"
cp Resources/AppIcon.icns Resources/CupMark.png "$BUNDLE/Contents/Resources/"
cp LICENSE "$BUNDLE/Contents/Resources/LICENSE"
cp .build/checkouts/SwiftTerm/LICENSE "$BUNDLE/Contents/Resources/SwiftTerm-LICENSE"
# SwiftTerm 会从应用的 Resources 查找 Metal 资源；不能依赖构建机的 .build 路径。
for resource in "$BIN"/*.bundle; do
  if [[ -d "$resource" ]]; then ditto "$resource" "$BUNDLE/Contents/Resources/$(basename "$resource")"; fi
done
if [[ -n "${COVE_BUNDLE_ID:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $COVE_BUNDLE_ID" "$BUNDLE/Contents/Info.plist"
fi
if [[ -n "${COVE_VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $COVE_VERSION" "$BUNDLE/Contents/Info.plist"
fi
if [[ -n "${COVE_BUILD_NUMBER:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $COVE_BUILD_NUMBER" "$BUNDLE/Contents/Info.plist"
fi
plutil -lint "$BUNDLE/Contents/Info.plist"
codesign --force --deep --sign - "$BUNDLE"
codesign --verify --deep --strict "$BUNDLE"
if [[ -e "$APP" ]]; then rm -rf "$APP"; fi
mv "$BUNDLE" "$APP"
echo "$APP"

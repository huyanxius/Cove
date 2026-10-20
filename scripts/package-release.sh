#!/bin/bash
# 接收已经签名的应用；发布目录必须是新目录，避免覆盖已经交付的版本。
set -euo pipefail
cd "$(dirname "$0")/.."
APP=${1:-build/Cove.app}
OUTPUT=${2:-build/distribution}
if [[ ! -d "$APP/Contents" || ! -x "$APP/Contents/MacOS/Cove" ]]; then
  echo "Expected a Cove.app bundle: $APP" >&2
  exit 1
fi
if [[ -e "$OUTPUT" ]]; then
  echo "Distribution output already exists: $OUTPUT" >&2
  exit 1
fi
plutil -lint "$APP/Contents/Info.plist"
codesign --verify --deep --strict "$APP"
for license in LICENSE SwiftTerm-LICENSE; do
  test -s "$APP/Contents/Resources/$license"
done
if [[ ! -d "$APP/Contents/Resources/SwiftTerm_SwiftTerm.bundle" ]]; then
  echo "Missing SwiftTerm runtime resources." >&2
  exit 1
fi
# 下载包不能依赖构建机上的 Homebrew 或 SwiftPM 路径。
if otool -L "$APP/Contents/MacOS/Cove" | tail -n +2 | awk '{print $1}' | grep -Ev '^(/usr/lib/|/System/Library/|@rpath/|@executable_path/|@loader_path/)' | grep -q .; then
  echo "The app links to a non-system absolute library." >&2
  exit 1
fi
ARCHES=$(lipo -archs "$APP/Contents/MacOS/Cove")
case "$ARCHES" in
  arm64) ARCH=arm64 ;;
  x86_64) ARCH=x86_64 ;;
  *arm64*x86_64*|*x86_64*arm64*) ARCH=universal ;;
  *) echo "Unsupported architecture: $ARCHES" >&2; exit 1 ;;
esac
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
mkdir -p "$(dirname "$OUTPUT")"
STAGE=$(mktemp -d "$(dirname "$OUTPUT")/.cove-distribution.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
mkdir "$STAGE/volume" "$STAGE/assets"
ditto "$APP" "$STAGE/volume/Cove.app"
ln -s /Applications "$STAGE/volume/Applications"
cp docs/INSTALL.txt "$STAGE/volume/Read Me First.txt"
ditto -c -k --sequesterRsrc --keepParent "$STAGE/volume/Cove.app" "$STAGE/assets/Cove-macOS-$ARCH.zip"
hdiutil create -quiet -volname "Cove $VERSION" -srcfolder "$STAGE/volume" -format UDZO "$STAGE/assets/Cove-macOS-$ARCH.dmg"
hdiutil verify -quiet "$STAGE/assets/Cove-macOS-$ARCH.dmg"
(
  cd "$STAGE/assets"
  shasum -a 256 ./*.dmg ./*.zip > SHA256SUMS.txt
  shasum -a 256 -c SHA256SUMS.txt
)
mv "$STAGE/assets" "$OUTPUT"
echo "Distribution: $OUTPUT ($VERSION, $ARCH)"

#!/bin/sh
# 由 Resources/AppIcon.svg 生成 Resources/AppIcon.icns 与 docs/assets/icon.png。
# 图标里的 C 用 macOS 自带的 Apple Chancery，毛边和白点靠 SVG 滤镜，只有浏览器能完整渲染，
# 所以借无头 Chrome 出 1024 底图，再用 sips 缩出各尺寸。
set -e
cd "$(dirname "$0")/.."
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cp Resources/AppIcon.svg "$TMP/icon.svg"
printf '<html style="background:transparent"><body style="margin:0"><img src="icon.svg" width="1024" height="1024"></body></html>' > "$TMP/icon.html"
"$CHROME" --headless=new --disable-gpu --hide-scrollbars --default-background-color=00000000 \
  --force-device-scale-factor=1 --window-size=1024,1024 --user-data-dir="$TMP/profile" \
  --screenshot="$TMP/icon_1024.png" "file://$TMP/icon.html" >/dev/null 2>&1 &
PID=$!
i=0; while [ ! -s "$TMP/icon_1024.png" ] && [ $i -lt 40 ]; do sleep 0.5; i=$((i+1)); done
sleep 0.5; kill $PID 2>/dev/null || true
[ -s "$TMP/icon_1024.png" ] || { echo "render failed" >&2; exit 1; }
SET="$TMP/AppIcon.iconset"; mkdir -p "$SET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$TMP/icon_1024.png" --out "$SET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$TMP/icon_1024.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o Resources/AppIcon.icns
mkdir -p docs/assets
sips -z 256 256 "$TMP/icon_1024.png" --out docs/assets/icon.png >/dev/null
echo "wrote Resources/AppIcon.icns and docs/assets/icon.png"

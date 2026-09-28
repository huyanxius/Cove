#!/usr/bin/env python3
"""生成 Cove 的像素图标：16×16 网格，C 形海湾 + 湾口的终端光标。

同一张网格同时产出三样东西：
  - Resources/AppIcon.icns       Finder / Dock 用
  - docs/assets/icon.svg         README 用
  - 打印 Swift 字面量            贴进 Sources/Cove/Theme/PixelLogo.swift（App 内欢迎页）
网格手绘在 ART 里：o 海岸，~ 水纹，# 光标，. 底色。改图标只改 ART，再重跑本脚本。

用法：python3 scripts/make_icon.py [--preview out.png] [--swift]
"""
import os
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw

N = 16
PALETTE = {
    ".": (0x1C, 0x33, 0x4D),  # 深港湾蓝，底
    "o": (0xF3, 0xEE, 0xE3),  # 暖纸色，海岸
    "~": (0x4E, 0x79, 0xA6),  # 浅一档的水纹
    "#": (0x9F, 0xC3, 0xE6),  # 光标，唯一的亮蓝
}


ART = [
    "................",
    "................",
    ".....oooooo.....",
    "....oooooooo....",
    "...ooo....ooo...",
    "..ooo...........",
    "..oo........##..",
    "..oo.~~.....##..",
    "..oo...~~...##..",
    "..oo........##..",
    "..ooo...........",
    "...ooo....ooo...",
    "....oooooooo....",
    ".....oooooo.....",
    "................",
    "................",
]


def grid():
    assert len(ART) == N and all(len(r) == N for r in ART)
    return ART


def render(size, rows, rounded=True):
    """按 Apple 图标网格：1024 画布里内容区 832，四周留 96 透明边，圆角约 22%。"""
    scale = size / 1024
    inset = round(96 * scale)
    content = size - 2 * inset
    art = Image.new("RGB", (N, N))
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            art.putpixel((x, y), PALETTE[ch])
    art = art.resize((content, content), Image.NEAREST)  # 最近邻，保证像素锐利
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    mask = Image.new("L", (content, content), 0)
    radius = round(content * 0.225) if rounded else 0
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, content - 1, content - 1), radius=radius, fill=255)
    canvas.paste(art, (inset, inset), mask)
    return canvas


def svg(rows):
    cell = 52
    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {N * cell} {N * cell}" shape-rendering="crispEdges">',
             f'<clipPath id="c"><rect width="{N * cell}" height="{N * cell}" rx="{N * cell * 0.225:.0f}"/></clipPath><g clip-path="url(#c)">']
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            r, g, b = PALETTE[ch]
            parts.append(f'<rect x="{x * cell}" y="{y * cell}" width="{cell}" height="{cell}" fill="#{r:02X}{g:02X}{b:02X}"/>')
    parts.append("</g></svg>")
    return "\n".join(parts)


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    rows = grid()
    if "--preview" in sys.argv:
        render(512, rows).save(sys.argv[sys.argv.index("--preview") + 1])
        print("\n".join(rows))
        return
    if "--swift" in sys.argv:
        print("\n".join(f'        "{r}",' for r in rows))
        return

    os.makedirs(os.path.join(root, "Resources"), exist_ok=True)
    os.makedirs(os.path.join(root, "docs", "assets"), exist_ok=True)
    with open(os.path.join(root, "docs", "assets", "icon.svg"), "w") as f:
        f.write(svg(rows))
    with tempfile.TemporaryDirectory() as tmp:
        iconset = os.path.join(tmp, "AppIcon.iconset")
        os.makedirs(iconset)
        for base in (16, 32, 128, 256, 512):
            render(base, rows).save(os.path.join(iconset, f"icon_{base}x{base}.png"))
            render(base * 2, rows).save(os.path.join(iconset, f"icon_{base}x{base}@2x.png"))
        subprocess.run(["iconutil", "-c", "icns", iconset, "-o", os.path.join(root, "Resources", "AppIcon.icns")], check=True)
    print("wrote Resources/AppIcon.icns and docs/assets/icon.svg")


if __name__ == "__main__":
    main()

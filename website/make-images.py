#!/usr/bin/env python3
"""Draws the website's raster images from the app icon, assets/icon.png.

    python3 website/make-images.py

It needs Pillow (pip install pillow). The site's build does not: these files
are committed in website/static, and only need drawing again when the icon
changes.

- favicon.png and icon-64/128/180/256.png: the icon, resized.
- og.png: the picture shown when a link to the site is shared, the brand
  wallpaper (amber, coral, violet) with the icon in the middle.
"""
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
ICON = HERE.parent / "assets" / "icon.png"
STATIC = HERE / "static"


def main():
    icon = Image.open(ICON).convert("RGBA")
    for size, name in [(32, "favicon.png"), (64, "icon-64.png"), (128, "icon-128.png"),
                       (180, "icon-180.png"), (256, "icon-256.png")]:
        icon.resize((size, size), Image.LANCZOS).save(STATIC / name, optimize=True)

    width, height = 1200, 630
    stops = [(0.0, (255, 196, 92)), (0.4, (255, 94, 98)), (0.75, (217, 68, 154)), (1.0, (178, 52, 214))]
    card = Image.new("RGB", (width, height))
    pixels = card.load()
    for y in range(height):
        for x in range(width):
            t = x / width * 0.62 + y / height * 0.38
            for (a, ca), (b, cb) in zip(stops, stops[1:]):
                if a <= t <= b:
                    u = (t - a) / (b - a)
                    pixels[x, y] = tuple(round(ca[i] + (cb[i] - ca[i]) * u) for i in range(3))
                    break
    card = card.convert("RGBA")
    card.alpha_composite(icon.resize((360, 360), Image.LANCZOS), ((width - 360) // 2, (height - 360) // 2))
    card.convert("RGB").save(STATIC / "og.png", optimize=True)
    print("Drew the website's images into", STATIC.relative_to(HERE.parent))


if __name__ == "__main__":
    main()

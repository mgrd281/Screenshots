# Draws the Snapfly app icon: a screenshot card flying up and away, with
# speed lines behind it, over a warm amber-to-magenta gradient.
# Usage: python3 scripts/make-icon.py assets/icon.png
# With --ios it draws the iPhone icon instead: the same picture, full bleed
# and opaque, since iOS rounds the corners itself.
#   python3 scripts/make-icon.py --ios iOS/Snapfly/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

S = 4                 # drawn four times larger, then scaled down for smooth edges
N = 1024 * S
ios = "--ios" in sys.argv
args = [a for a in sys.argv[1:] if a != "--ios"]
out = args[0] if args else "icon.png"


def gradient(w, h, stops, angle_from=(0, 0), angle_to=(1, 1)):
    """A linear gradient between points given in 0...1 of the image."""
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    ax, ay = angle_from[0] * w, angle_from[1] * h
    bx, by = angle_to[0] * w, angle_to[1] * h
    dx, dy = bx - ax, by - ay
    t = ((xs - ax) * dx + (ys - ay) * dy) / (dx * dx + dy * dy)
    t = np.clip(t, 0, 1)
    rgb = np.zeros((h, w, 3), np.float32)
    positions = [p for p, _ in stops]
    for c in range(3):
        rgb[..., c] = np.interp(t, positions, [col[c] for _, col in stops])
    return Image.fromarray(rgb.astype(np.uint8), "RGB").convert("RGBA")


def squircle(w, h, n=4.3):
    """The rounded square of a macOS icon, as a superellipse mask."""
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    u = np.abs((xs + 0.5) / w * 2 - 1)
    v = np.abs((ys + 0.5) / h * 2 - 1)
    inside = (u ** n + v ** n) <= 1
    return Image.fromarray((inside * 255).astype(np.uint8), "L")


def rounded(w, h, r, fill):
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(img).rounded_rectangle([0, 0, w - 1, h - 1], r, fill=fill)
    return img


canvas = Image.new("RGBA", (N, N), (0, 0, 0, 0))

# The body: 824 of 1024, centred, as the macOS icon grid has it.
B = 824 * S
x0 = y0 = 100 * S
mask = Image.new("L", (B, B), 255) if ios else squircle(B, B)

if not ios:
    shadow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    shadow.paste((40, 10, 40, 110), (x0, y0 + 14 * S), mask)
    canvas = Image.alpha_composite(canvas, shadow.filter(ImageFilter.GaussianBlur(22 * S)))

body = gradient(B, B, [(0.0, (255, 196, 92)), (0.45, (255, 94, 98)), (1.0, (178, 52, 214))],
                (0.1, 0.0), (0.9, 1.0))
# A soft light from the top left, so it reads as glass rather than paint.
glow = Image.new("RGBA", (B, B), (0, 0, 0, 0))
ImageDraw.Draw(glow).ellipse([-B * 0.35, -B * 0.55, B * 0.85, B * 0.55], fill=(255, 255, 255, 45))
body = Image.alpha_composite(body, glow.filter(ImageFilter.GaussianBlur(90 * S)))
layer = Image.new("RGBA", (N, N), (0, 0, 0, 0))
layer.paste(body, (x0, y0), mask)
canvas = Image.alpha_composite(canvas, layer)

# Speed lines, trailing down and to the left of the card.
lines = Image.new("RGBA", (N, N), (0, 0, 0, 0))
d = ImageDraw.Draw(lines)
# Along the flight, up and to the right at about 33 degrees.
for (sx, sy, length, width, alpha) in [
    (322, 690, 170, 30, 170),
    (380, 780, 230, 26, 120),
    (248, 618, 120, 20, 90),
]:
    ex, ey = sx + length * 0.84, sy - length * 0.55
    d.line([(sx * S, sy * S), (ex * S, ey * S)], fill=(255, 255, 255, alpha), width=width * S)
    for (cx, cy) in [(sx, sy), (ex, ey)]:
        r = width * S / 2
        d.ellipse([cx * S - r, cy * S - r, cx * S + r, cy * S + r], fill=(255, 255, 255, alpha))
canvas = Image.alpha_composite(canvas, lines)

# The card: a white frame around a screenshot of a window.
CW, CH = 450 * S, 344 * S
card = rounded(CW, CH, 54 * S, (255, 255, 255, 255))
inset = 26 * S
screen_w, screen_h = CW - 2 * inset, CH - 2 * inset
screen = gradient(screen_w, screen_h, [(0, (58, 44, 120)), (1, (34, 26, 78))], (0, 0), (1, 1))
screen_mask = Image.new("L", (screen_w, screen_h), 0)
ImageDraw.Draw(screen_mask).rounded_rectangle([0, 0, screen_w - 1, screen_h - 1], 32 * S, fill=255)
ui = ImageDraw.Draw(screen)
# Window buttons.
for i, col in enumerate([(255, 95, 87), (254, 188, 46), (40, 200, 64)]):
    cx, cy, r = (44 + i * 40) * S, 42 * S, 12 * S
    ui.ellipse([cx - r, cy - r, cx + r, cy + r], fill=col + (255,))
# Lines of text, in solid colours so nothing behind shows through, and one
# picked out in the gradient's warm colour.
for (lx, ly, lw, col) in [(34, 92, 300, (226, 220, 245)), (34, 136, 230, (128, 116, 182)),
                          (34, 180, 270, (128, 116, 182)), (34, 224, 170, (255, 128, 104))]:
    ui.rounded_rectangle([lx * S, ly * S, (lx + lw) * S, (ly + 20) * S], 10 * S, fill=col + (255,))
card.paste(screen, (inset, inset), screen_mask)

# Tilted up and to the right, as if taking off.
angle = 14
card_r = card.rotate(angle, resample=Image.BICUBIC, expand=True)
cx, cy = 572 * S, 452 * S
pos = (int(cx - card_r.width / 2), int(cy - card_r.height / 2))
card_shadow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
alpha = card_r.split()[3].point(lambda a: a * 0.45)
card_shadow.paste((70, 10, 60, 255), (pos[0] + 10 * S, pos[1] + 30 * S), alpha)
canvas = Image.alpha_composite(canvas, card_shadow.filter(ImageFilter.GaussianBlur(26 * S)))
layer = Image.new("RGBA", (N, N), (0, 0, 0, 0))
layer.paste(card_r, pos, card_r)
canvas = Image.alpha_composite(canvas, layer)

if ios:
    # The body alone, scaled to the whole icon.
    canvas = canvas.crop((x0, y0, x0 + B, y0 + B)).convert("RGB")
canvas.resize((1024, 1024), Image.LANCZOS).save(out)
print("saved", out)

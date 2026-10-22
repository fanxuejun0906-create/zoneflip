#!/usr/bin/env python3
"""Generate ZoneFlip.icns (a clock on a blue-violet rounded square)."""
import math
import os
import subprocess
import tempfile

from PIL import Image, ImageDraw

S = 2048          # supersampled canvas
OUT = 1024        # final size
RADIUS = int(OUT * 0.225)

def gradient(size):
    top = (30, 94, 255)
    bottom = (122, 60, 255)
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        t = y / (size - 1)
        color = tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        for x in range(size):
            px[x, y] = color
    return img

def rounded_mask(size, radius):
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return mask

def main():
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    bg = gradient(S).convert("RGBA")
    bg.putalpha(rounded_mask(S, int(RADIUS * S / OUT)))
    canvas.alpha_composite(bg)

    # Soft highlight in the top-left corner.
    glow = Image.new("L", (S, S), 0)
    gd = ImageDraw.Draw(glow)
    gd.ellipse([-S * 0.35, -S * 0.5, S * 0.85, S * 0.7], fill=46)
    glow = glow.filter(__import__("PIL.ImageFilter", fromlist=["GaussianBlur"]).GaussianBlur(S * 0.08))
    white = Image.new("RGBA", (S, S), (255, 255, 255, 255))
    canvas.paste(white, (0, 0), glow)

    draw = ImageDraw.Draw(canvas)
    cx = cy = S / 2
    ring_r = S * 0.30
    ring_w = int(S * 0.043)
    draw.ellipse([cx - ring_r, cy - ring_r, cx + ring_r, cy + ring_r], outline=(255, 255, 255, 235), width=ring_w)

    # 10:10 hands (hour to the upper right, minute to the upper left).
    def hand(angle_deg, length, width):
        a = math.radians(angle_deg)
        x = cx + math.sin(a) * length
        y = cy - math.cos(a) * length
        draw.line([cx, cy, x, y], fill=(255, 255, 255, 255), width=width)
        for px, py in ((cx, cy), (x, y)):
            r = width / 2
            draw.ellipse([px - r, py - r, px + r, py + r], fill=(255, 255, 255, 255))

    hand(52, S * 0.20, int(S * 0.052))
    hand(-62, S * 0.155, int(S * 0.052))
    dot = S * 0.021
    draw.ellipse([cx - dot, cy - dot, cx + dot, cy + dot], fill=(255, 255, 255, 255))

    # Small accent dot suggesting "the other timezone".
    ax, ay = cx + ring_r * 0.98, cy - ring_r * 0.62
    ar = S * 0.020
    draw.ellipse([ax - ar, ay - ar, ax + ar, ay + ar], fill=(255, 194, 92, 255))

    icon = canvas.resize((OUT, OUT), Image.LANCZOS)

    with tempfile.TemporaryDirectory() as tmp:
        iconset = os.path.join(tmp, "AppIcon.iconset")
        os.makedirs(iconset)
        for base in (16, 32, 128, 256, 512):
            for scale in (1, 2):
                size = base * scale
                name = f"icon_{base}x{base}{'@2x' if scale == 2 else ''}.png"
                icon.resize((size, size), Image.LANCZOS).save(os.path.join(iconset, name))
        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        target = os.path.join(root, "Resources", "AppIcon.icns")
        subprocess.run(["/usr/bin/iconutil", "-c", "icns", iconset, "-o", target], check=True)
        icon.save(os.path.join(root, "Resources", "icon-preview.png"))
        print("wrote", target)

if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Render the ClipStack macOS app icon at all required sizes.

Design: indigo->violet gradient squircle; three fanned clipboard cards
(back two translucent white), front card solid white with an indigo clip
and two text lines. Drawn at 1024 with Pillow, then downscaled.
"""
import os
from PIL import Image, ImageDraw, ImageFilter

SS = 4          # supersample factor
BASE = 1024
S = BASE * SS   # working canvas

TOP = (91, 92, 226)    # #5B5CE2 indigo
BOT = (142, 92, 240)   # #8E5CF0 violet

OUT = os.path.join(os.path.dirname(__file__), "..",
                   "Paste/Paste/Assets.xcassets/AppIcon.appiconset")
MASTER = os.path.join(os.path.dirname(__file__), "..",
                      "Paste/Paste/Resources/AppIcon-1024.png")


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def vgrad(size, top, bot):
    w, h = size
    img = Image.new("RGB", (1, h))
    px = img.load()
    for y in range(h):
        px[0, y] = lerp(top, bot, y / max(h - 1, 1))
    return img.resize((w, h))


def rounded_mask(size, radius):
    m = Image.new("L", size, 0)
    d = ImageDraw.Draw(m)
    d.rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius=radius, fill=255)
    return m


def main():
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))

    # --- tile geometry (macOS icon grid: ~824/1024) ---
    tile = int(S * 0.805)
    t0 = (S - tile) // 2
    radius = int(tile * 0.2237)

    # soft shadow
    sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle(
        [t0, t0 + int(S * 0.012), t0 + tile, t0 + tile + int(S * 0.012)],
        radius=radius, fill=(20, 16, 60, 110))
    sh = sh.filter(ImageFilter.GaussianBlur(int(S * 0.02)))
    canvas.alpha_composite(sh)

    # gradient tile
    grad = vgrad((tile, tile), TOP, BOT).convert("RGBA")
    tile_img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    tile_img.paste(grad, (t0, t0), rounded_mask((tile, tile), radius))
    canvas.alpha_composite(tile_img)

    # subtle top sheen
    sheen = Image.new("RGBA", (tile, tile), (0, 0, 0, 0))
    ImageDraw.Draw(sheen).rounded_rectangle(
        [0, 0, tile - 1, tile // 2], radius=radius, fill=(255, 255, 255, 26))
    canvas.alpha_composite(
        Image.composite(sheen, Image.new("RGBA", (tile, tile), (0, 0, 0, 0)),
                        rounded_mask((tile, tile), radius)),
        (t0, t0))

    # --- cards ---
    cw = int(tile * 0.46)   # card width
    ch = int(tile * 0.56)   # card height
    cr = int(tile * 0.075)  # card corner radius
    cx = t0 + tile // 2
    cy = t0 + int(tile * 0.54)

    def card(offset_x, offset_y, alpha):
        layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        x0 = cx - cw // 2 + offset_x
        y0 = cy - ch // 2 + offset_y
        d.rounded_rectangle([x0, y0, x0 + cw, y0 + ch], radius=cr,
                            fill=(255, 255, 255, alpha))
        canvas.alpha_composite(layer)

    # back cards fanned up-left
    card(-int(tile * 0.085), -int(tile * 0.085), 70)
    card(-int(tile * 0.042), -int(tile * 0.042), 140)

    # front card
    fx0 = cx - cw // 2
    fy0 = cy - ch // 2
    front = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    fd = ImageDraw.Draw(front)
    fd.rounded_rectangle([fx0, fy0, fx0 + cw, fy0 + ch], radius=cr,
                         fill=(255, 255, 255, 255))

    # clipboard clip: white tab with an indigo pill knob
    clip_w = int(cw * 0.46)
    clip_h = int(tile * 0.10)
    clip_x = cx - clip_w // 2
    clip_y = fy0 - int(clip_h * 0.45)
    fd.rounded_rectangle([clip_x, clip_y, clip_x + clip_w, clip_y + clip_h],
                         radius=int(clip_h * 0.4), fill=(255, 255, 255, 255))
    knob_w = int(clip_w * 0.52)
    knob_h = int(clip_h * 0.34)
    fd.rounded_rectangle([cx - knob_w // 2, clip_y + (clip_h - knob_h) // 2,
                          cx + knob_w // 2,
                          clip_y + (clip_h - knob_h) // 2 + knob_h],
                         radius=knob_h // 2, fill=TOP + (255,))

    # text lines on front card
    line_h = int(tile * 0.042)
    line_r = line_h // 2
    lx = fx0 + int(cw * 0.16)
    ly = fy0 + int(ch * 0.40)
    for i, frac in enumerate((0.68, 0.5)):
        lw = int(cw * frac)
        y = ly + i * int(line_h * 2.2)
        fd.rounded_rectangle([lx, y, lx + lw, y + line_h], radius=line_r,
                             fill=(99, 102, 241, 255))
    # small accent thumbnail (image snippet hint)
    dot = int(tile * 0.085)
    dy = ly + 2 * int(line_h * 2.2)
    fd.rounded_rectangle([lx, dy, lx + dot, dy + dot], radius=int(dot * 0.28),
                         fill=(142, 92, 240, 255))
    canvas.alpha_composite(front)

    # --- downscale to all icon sizes ---
    final = canvas.resize((BASE, BASE), Image.LANCZOS)
    os.makedirs(OUT, exist_ok=True)
    final.save(os.path.join(OUT, "icon_512x512@2x.png"))
    final.save(MASTER)

    sizes = {
        "icon_16x16.png": 16, "icon_16x16@2x.png": 32,
        "icon_32x32.png": 32, "icon_32x32@2x.png": 64,
        "icon_128x128.png": 128, "icon_128x128@2x.png": 256,
        "icon_256x256.png": 256, "icon_256x256@2x.png": 512,
        "icon_512x512.png": 512,
    }
    for name, px in sizes.items():
        final.resize((px, px), Image.LANCZOS).save(os.path.join(OUT, name))
    print("wrote", len(sizes) + 1, "icons ->", os.path.normpath(OUT))
    print("master ->", os.path.normpath(MASTER))


if __name__ == "__main__":
    main()

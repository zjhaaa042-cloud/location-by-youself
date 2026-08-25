#!/usr/bin/env python3
"""Generate the LocationMocker app icon (single 1024x1024, Xcode single-size).

Design: indigo-to-cyan diagonal gradient, a solid white map pin with a
translucent "ghost" twin offset to the lower right (the mocked position),
connected by a dashed route from a small start dot.

Usage:  python3 tools/gen_appicon.py
Output: LocationMocker/LocationMocker/Resources/Assets.xcassets/AppIcon.appiconset/
Requires: Pillow
"""

import math
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

SCALE = 4                      # draw at 4x, downscale for antialiasing
SIZE = 1024 * SCALE

# Diagonal gradient stops (top-left -> bottom-right)
COLOR_A = (43, 50, 178)        # indigo  #2B32B2
COLOR_B = (20, 136, 204)       # cyan    #1488CC

OUT_DIR = (
    Path(__file__).resolve().parent.parent
    / "LocationMocker/LocationMocker/Resources/Assets.xcassets/AppIcon.appiconset"
)


def lerp(a: tuple, b: tuple, t: float) -> tuple:
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def make_gradient() -> Image.Image:
    """Small diagonal gradient, then upscaled smoothly."""
    n = 256
    grad = Image.new("RGB", (n, n))
    px = grad.load()
    for y in range(n):
        for x in range(n):
            t = (x + y) / (2 * (n - 1))
            px[x, y] = lerp(COLOR_A, COLOR_B, t)
    return grad.resize((SIZE, SIZE), Image.BICUBIC)


def pin_mask(cx: float, cy: float, r: float) -> Image.Image:
    """White-on-black teardrop pin: circle + triangle from tangent points to tip."""
    mask = Image.new("L", (SIZE, SIZE), 0)
    d = ImageDraw.Draw(mask)
    tip_y = cy + r * 1.78
    # tangent angle from tip (cx, tip_y) to the circle
    dist = tip_y - cy
    sin_a = r / dist
    ang = math.asin(sin_a)                 # angle between tip->center and tip->tangent
    # tangent points relative to center, measured from straight-down direction
    p1 = (cx - r * math.cos(ang), cy + r * math.sin(ang))
    p2 = (cx + r * math.cos(ang), cy + r * math.sin(ang))
    d.polygon([p1, p2, (cx, tip_y)], fill=255)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
    # punch the hole
    hole = r * 0.40
    d.ellipse([cx - hole, cy - hole, cx + hole, cy + hole], fill=0)
    return mask, tip_y


def outline_of(mask: Image.Image, width: float) -> Image.Image:
    """Ring = mask minus eroded mask."""
    eroded = mask.filter(ImageFilter.MinFilter(int(width) * 2 + 1))
    return ImageChops.subtract(mask, eroded)


def dashed_bezier(p0, p1, p2, dash=26, gap=20, width=14):
    """Yield short line segments along a quadratic bezier."""
    seg_len = 400
    pts = []
    for i in range(seg_len + 1):
        t = i / seg_len
        x = (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t ** 2 * p2[0]
        y = (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t ** 2 * p2[1]
        pts.append((x, y))
    segs, acc, i = [], 0.0, 0
    while i < len(pts) - 1:
        # accumulate one dash
        dash_pts = [pts[i]]
        run = 0.0
        while i < len(pts) - 1 and run < dash:
            step = math.dist(pts[i], pts[i + 1])
            run += step
            i += 1
            dash_pts.append(pts[i])
        if len(dash_pts) > 1:
            segs.append((dash_pts, width))
        # skip the gap
        skipped = 0.0
        while i < len(pts) - 1 and skipped < gap:
            skipped += math.dist(pts[i], pts[i + 1])
            i += 1
    return segs


def main() -> None:
    icon = make_gradient().convert("RGBA")
    u = SCALE  # 1 design unit = 1pt at 1024

    # soft glow behind the pin
    glow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gr = 300 * u
    gcx, gcy = 512 * u, 470 * u
    gd.ellipse([gcx - gr, gcy - gr, gcx + gr, gcy + gr], fill=(255, 255, 255, 16))
    icon = Image.alpha_composite(icon, glow.filter(ImageFilter.GaussianBlur(55 * u)))

    # dashed route: start dot (lower left) -> tip of the ghost pin area
    route = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    rd = ImageDraw.Draw(route)
    p0 = (215 * u, 815 * u)
    p1 = (330 * u, 620 * u)
    p2 = (620 * u, 730 * u)
    for seg_pts, w in dashed_bezier(p0, p1, p2, dash=30 * u, gap=22 * u, width=13 * u):
        rd.line(seg_pts, fill=(255, 255, 255, 150), width=int(w), joint="curve")
        for end in (seg_pts[0], seg_pts[-1]):
            rd.ellipse(
                [end[0] - w / 2, end[1] - w / 2, end[0] + w / 2, end[1] + w / 2],
                fill=(255, 255, 255, 150),
            )
    icon = Image.alpha_composite(icon, route)

    # start dot
    dot = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    dd = ImageDraw.Draw(dot)
    dr = 30 * u
    dd.ellipse([p0[0] - dr, p0[1] - dr, p0[0] + dr, p0[1] + dr],
               fill=(255, 255, 255, 235))
    icon = Image.alpha_composite(icon, dot)

    # ghost pin (the mocked position): translucent outline, offset down-right
    ghost, _ = pin_mask(618 * u, 500 * u, 128 * u)
    ghost_ring = outline_of(ghost, 9 * u)
    ghost_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ghost_layer.paste((255, 255, 255, 110), (0, 0), ghost_ring)
    icon = Image.alpha_composite(icon, ghost_layer)

    # main pin: drop shadow + solid white
    main_pin, _ = pin_mask(472 * u, 420 * u, 172 * u)
    shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    shadow_mask = main_pin.transform(
        (SIZE, SIZE), Image.AFFINE, (1, 0, -14 * u, 0, 1, -22 * u)
    )
    shadow.paste((10, 20, 60, 90), (0, 0), shadow_mask)
    icon = Image.alpha_composite(icon, shadow.filter(ImageFilter.GaussianBlur(10 * u)))
    pin_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    pin_layer.paste((255, 255, 255, 255), (0, 0), main_pin)
    icon = Image.alpha_composite(icon, pin_layer)

    # accent: fill the pin hole with a warm dot for contrast
    accent = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ad = ImageDraw.Draw(accent)
    hole_r = 172 * u * 0.40
    inner = hole_r * 0.62
    ad.ellipse([472 * u - inner, 420 * u - inner, 472 * u + inner, 420 * u + inner],
               fill=(255, 159, 67, 255))   # #FF9F43
    icon = Image.alpha_composite(icon, accent)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    final = icon.resize((1024, 1024), Image.LANCZOS).convert("RGB")
    png = OUT_DIR / "AppIcon-1024.png"
    final.save(png)

    (OUT_DIR / "Contents.json").write_text(
        """{
  "images" : [
    {
      "filename" : "AppIcon-1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""
    )
    print(f"[icon] wrote {png}")
    print(f"[icon] wrote {OUT_DIR / 'Contents.json'}")


if __name__ == "__main__":
    main()

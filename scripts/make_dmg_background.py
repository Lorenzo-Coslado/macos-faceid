"""Disk image backdrop: charcoal gradient, a green arrow, and the two drop points.

Rendered at 1x and 2x; build-release.sh combines them into a multi-resolution TIFF so the
window stays sharp on Retina. Keep in sync with the window geometry in build-release.sh.
"""
import numpy as np
import cv2
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "assets"

W, H = 600, 340
# Deeper than the icon's mint so it stays legible on white; same green as the README badges.
GREEN = (93, 165, 59)            # BGR, #3BA55D
ICON_Y = 155                     # icon centres, mirrored in the AppleScript
APP_X, FOLDER_X = 150, 450
ARC_RISE = 46                    # how far the arc bows above the icons


def render(scale: int) -> np.ndarray:
    w, h = W * scale, H * scale
    img = np.full((h, w, 3), 255, np.uint8)

    # A quadratic Bezier bowing upward between the two icons, stopping short of both so
    # it never crowds them. Round caps everywhere and a chevron head rather than a filled
    # triangle, so it reads as drawn rather than as a UI glyph.
    y = ICON_Y * scale
    x0 = (APP_X + 88) * scale
    x1 = (FOLDER_X - 88) * scale
    ctrl = ((x0 + x1) / 2, y - 2 * ARC_RISE * scale)   # pulls the curve halfway up
    t = max(2, 9 * scale)
    r = t // 2

    def bezier(s):
        u = 1 - s
        return (u * u * x0 + 2 * u * s * ctrl[0] + s * s * x1,
                u * u * y + 2 * u * s * ctrl[1] + s * s * y)

    pts = np.array([bezier(i / 60) for i in range(61)], np.int32)
    cv2.polylines(img, [pts], False, GREEN, t, cv2.LINE_AA)
    cv2.circle(img, tuple(pts[0]), r, GREEN, -1, cv2.LINE_AA)

    # Head aligned with the tangent at the end of the curve.
    tip = np.array(bezier(1.0))
    ang = np.arctan2(tip[1] - bezier(0.98)[1], tip[0] - bezier(0.98)[0])
    head = 18 * scale
    for spread in (2.5, -2.5):
        end = (int(tip[0] + head * np.cos(ang + spread)),
               int(tip[1] + head * np.sin(ang + spread)))
        cv2.line(img, (int(tip[0]), int(tip[1])), end, GREEN, t, cv2.LINE_AA)
        cv2.circle(img, end, r, GREEN, -1, cv2.LINE_AA)
    cv2.circle(img, (int(tip[0]), int(tip[1])), r, GREEN, -1, cv2.LINE_AA)

    # No captions: the Finder already draws the item names under each icon, and anything
    # painted there collides with them.
    return img


for scale, name in ((1, "dmg-background.png"), (2, "dmg-background@2x.png")):
    path = OUT_DIR / name
    cv2.imwrite(str(path), render(scale))
    print("wrote", path)

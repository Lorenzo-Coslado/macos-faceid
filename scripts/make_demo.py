"""Rend l'animation « Dynamic Island » du Face ID en frames PNG (→ GIF via ffmpeg).

Reproduit le HUD : pilule noire, glyphe Face ID vert qui pulse + ligne de scan,
puis morph vers un checkmark vert. Fond sombre type bureau."""
import numpy as np
import cv2
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GLYPH = cv2.imread(str(ROOT / "assets" / "faceid-icon.png"), cv2.IMREAD_UNCHANGED)
OUT = ROOT / "assets" / "demo_frames"
OUT.mkdir(parents=True, exist_ok=True)

W, H = 900, 340
GREEN = (138, 232, 134)     # BGR ~ #86E88A
PILL_W, PILL_H = 360, 84
ICON = 52

# fond : dégradé sombre vertical
bg = np.zeros((H, W, 3), np.float32)
for y in range(H):
    t = y / (H - 1)
    bg[y, :] = np.array([22, 20, 18]) * (1 - t) + np.array([14, 13, 12]) * t
BG = bg.astype(np.uint8)

px = (W - PILL_W) // 2
py = 96


def rounded(img, x, y, w, h, r, color, alpha=1.0):
    ov = img.copy()
    cv2.rectangle(ov, (x + r, y), (x + w - r, y + h), color, -1)
    cv2.rectangle(ov, (x, y + r), (x + w, y + h - r), color, -1)
    for cx, cy in [(x + r, y + r), (x + w - r, y + r), (x + r, y + h - r), (x + w - r, y + h - r)]:
        cv2.circle(ov, (cx, cy), r, color, -1, cv2.LINE_AA)
    cv2.addWeighted(ov, alpha, img, 1 - alpha, 0, img)


def put_text(img, text, x, y, scale, color, thick=2):
    cv2.putText(img, text, (x, y), cv2.FONT_HERSHEY_DUPLEX, scale, color, thick, cv2.LINE_AA)


def paste_glyph(img, gx, gy, size, alpha_mul=1.0):
    g = cv2.resize(GLYPH, (size, size), interpolation=cv2.INTER_AREA)
    a = (g[:, :, 3:4].astype(np.float32) / 255.0) * alpha_mul
    roi = img[gy:gy + size, gx:gx + size, :3].astype(np.float32)
    img[gy:gy + size, gx:gx + size, :3] = (g[:, :, :3] * a + roi * (1 - a)).astype(np.uint8)


def frame(i, n):
    img = BG.copy()
    # ombre + pilule
    rounded(img, px, py + 6, PILL_W, PILL_H, PILL_H // 2, (0, 0, 0), 0.35)
    rounded(img, px, py, PILL_W, PILL_H, PILL_H // 2, (10, 10, 10), 1.0)

    ix, iy = px + 18, py + (PILL_H - ICON) // 2
    tx = ix + ICON + 20

    scan_len = 46          # frames de scan
    if i < scan_len:
        pulse = 0.82 + 0.18 * abs(np.sin(i * 0.28))
        paste_glyph(img, ix, iy, ICON, pulse)
        # ligne de scan
        yy = iy + int((ICON - 6) * (0.5 + 0.5 * np.sin(i * 0.34)))
        line = img[yy:yy + 3, ix + 4:ix + ICON - 4].astype(np.float32)
        img[yy:yy + 3, ix + 4:ix + ICON - 4] = np.clip(line + np.array(GREEN) * 0.5, 0, 255).astype(np.uint8)
        put_text(img, "Face ID", tx, py + PILL_H // 2 + 8, 0.72, (240, 240, 240))
    else:
        p = min(1.0, (i - scan_len) / 16.0)      # progression du checkmark
        cx, cy, r = ix + ICON // 2, iy + ICON // 2, ICON // 2 - 3
        # cercle progressif
        end = int(360 * p)
        cv2.ellipse(img, (cx, cy), (r, r), -90, 0, end, GREEN, 3, cv2.LINE_AA)
        # coche progressive
        if p > 0.35:
            q = (p - 0.35) / 0.65
            p1 = (cx - 12, cy + 1); p2 = (cx - 3, cy + 10); p3 = (cx + 13, cy - 9)
            if q < 0.5:
                a = q / 0.5
                pt = (int(p1[0] + (p2[0] - p1[0]) * a), int(p1[1] + (p2[1] - p1[1]) * a))
                cv2.line(img, p1, pt, GREEN, 3, cv2.LINE_AA)
            else:
                a = (q - 0.5) / 0.5
                cv2.line(img, p1, p2, GREEN, 3, cv2.LINE_AA)
                pt = (int(p2[0] + (p3[0] - p2[0]) * a), int(p2[1] + (p3[1] - p2[1]) * a))
                cv2.line(img, p2, pt, GREEN, 3, cv2.LINE_AA)
        put_text(img, "Unlocked", tx, py + PILL_H // 2 + 8, 0.72, GREEN)

    cv2.imwrite(str(OUT / f"f{i:04d}.png"), img)


N = 78
for i in range(N):
    frame(i, N)
print(f"{N} frames -> {OUT}")

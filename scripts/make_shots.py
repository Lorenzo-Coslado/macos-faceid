"""Compose les fenêtres de l'app sur un fond façon macOS (dégradé + ombre)."""
import cv2
import numpy as np
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
W, H = 2400, 1500


def wallpaper():
    # dégradé diagonal bleu-nuit -> violet profond, léger halo (style macOS sombre)
    top = np.array([88, 60, 38], np.float32)      # BGR ~ #263c58
    bot = np.array([40, 24, 30], np.float32)      # ~ #1e1828
    g = np.zeros((H, W, 3), np.float32)
    for y in range(H):
        t = y / (H - 1)
        g[y, :] = top * (1 - t) + bot * t
    # halo radial doux vers le centre-haut
    yy, xx = np.mgrid[0:H, 0:W]
    d = np.sqrt((xx - W * 0.5) ** 2 + (yy - H * 0.32) ** 2)
    halo = np.clip(1 - d / (W * 0.7), 0, 1)[..., None] ** 2
    g += halo * np.array([70, 45, 30], np.float32)
    return np.clip(g, 0, 255).astype(np.uint8)


def rounded_alpha(win, r):
    h, w = win.shape[:2]
    m = np.zeros((h, w), np.uint8)
    cv2.rectangle(m, (r, 0), (w - r, h), 255, -1)
    cv2.rectangle(m, (0, r), (w, h - r), 255, -1)
    for cx, cy in [(r, r), (w - r, r), (r, h - r), (w - r, h - r)]:
        cv2.circle(m, (cx, cy), r, 255, -1, cv2.LINE_AA)
    return m


def compose(win_path, out_path, target_h=880, r=30):
    win = cv2.imread(str(win_path))
    h, w = win.shape[:2]
    s = target_h / h
    win = cv2.resize(win, (int(w * s), target_h), interpolation=cv2.INTER_AREA)
    h, w = win.shape[:2]
    alpha = rounded_alpha(win, r).astype(np.float32) / 255.0

    canvas = wallpaper().astype(np.float32)
    ox, oy = (W - w) // 2, (H - h) // 2

    # ombre portée douce
    shadow = np.zeros((H, W), np.float32)
    sm = np.zeros((H, W), np.float32)
    sm[oy:oy + h, ox:ox + w] = alpha
    sm = cv2.GaussianBlur(sm, (0, 0), 40)
    shad_off = 26
    shadow = np.roll(sm, shad_off, axis=0)
    canvas *= (1 - shadow[..., None] * 0.55)

    roi = canvas[oy:oy + h, ox:ox + w]
    a3 = alpha[..., None]
    canvas[oy:oy + h, ox:ox + w] = win.astype(np.float32) * a3 + roi * (1 - a3)
    out = np.clip(canvas, 0, 255).astype(np.uint8)
    # sortie ~1600px de large pour le README
    out = cv2.resize(out, (1600, int(1600 * H / W)), interpolation=cv2.INTER_AREA)
    cv2.imwrite(str(out_path), out)
    print("écrit", out_path, out.shape)


compose("/tmp/onb-en-check.png", ROOT / "assets" / "onboarding.png", target_h=980)
compose("/tmp/panel-en.png", ROOT / "assets" / "modal.png", target_h=820)

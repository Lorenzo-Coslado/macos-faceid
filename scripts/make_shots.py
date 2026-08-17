"""Compose une fenêtre de l'app sur un fond façon macOS (dégradé + ombre).

    python scripts/make_shots.py <capture.png> <sortie.png> [hauteur]

La capture d'entrée est la fenêtre seule. Pour l'obtenir sans le bureau ni les fenêtres
voisines, passer par son identifiant plutôt que par sa position :

    swiftc -O -o /tmp/window-id scripts/window-id.swift -framework CoreGraphics
    /tmp/window-id Mugshot
    screencapture -o -l<id> /tmp/win.png

Sans argument, régénère les captures du dépôt depuis /tmp (comportement d'origine).
"""
import sys
import cv2
import numpy as np
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
W, H = 2400, 1500


def wallpaper():
    """Fond sombre à deux halos colorés, façon fond d'écran macOS.

    L'ancien dégradé linéaire aplatissait l'image : la fenêtre, elle-même sombre, s'y
    fondait. Deux sources lumineuses décentrées — une verte reprenant l'accent de l'app,
    une indigo en contrepoint — creusent la profondeur et détachent la fenêtre, sans
    attirer l'œil puisqu'elles restent loin du centre où elle se pose.
    """
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)

    # Base : bleu nuit en haut, prune sombre en bas. Assez présent pour porter la
    # couleur, assez sombre pour qu'une fenêtre sombre s'en détache.
    t = (yy / (H - 1))[..., None]
    canvas = (np.array([74, 46, 30], np.float32) * (1 - t)
              + np.array([62, 28, 44], np.float32) * t)

    def glow(cx, cy, radius, colour, strength):
        """Halo radial à décroissance douce (cx, cy en fraction de l'image)."""
        d = np.sqrt((xx - W * cx) ** 2 + (yy - H * cy) ** 2) / (W * radius)
        falloff = np.clip(1.0 - d, 0.0, 1.0) ** 2.2
        return falloff[..., None] * np.array(colour, np.float32) * strength

    # BGR. Le vert reprend Brand.green (#86E88A), l'indigo lui répond en diagonale.
    canvas += glow(0.14, 0.12, 0.66, (86, 190, 92), 0.85)
    canvas += glow(0.88, 0.90, 0.62, (196, 92, 120), 0.70)
    # Voile central : évite que le milieu, là où se pose la fenêtre, vire au gris mort.
    canvas += glow(0.50, 0.42, 0.95, (96, 62, 58), 0.45)

    # Vignettage : assombrit les bords, ramène le regard vers la fenêtre.
    d = np.sqrt((xx - W / 2) ** 2 + (yy - H / 2) ** 2) / (W * 0.72)
    canvas *= np.clip(1.10 - d * 0.38, 0.55, 1.0)[..., None]

    # Grain fin : sans lui, un dégradé aussi sombre montre des bandes de quantification.
    rng = np.random.default_rng(7)
    canvas += rng.normal(0.0, 1.6, (H, W, 1)).astype(np.float32)

    return np.clip(canvas, 0, 255).astype(np.uint8)


def rounded_alpha(win, r):
    h, w = win.shape[:2]
    m = np.zeros((h, w), np.uint8)
    cv2.rectangle(m, (r, 0), (w - r, h), 255, -1)
    cv2.rectangle(m, (0, r), (w, h - r), 255, -1)
    for cx, cy in [(r, r), (w - r, r), (r, h - r), (w - r, h - r)]:
        cv2.circle(m, (cx, cy), r, 255, -1, cv2.LINE_AA)
    return m


def compose(win_path, out_path, target_h=880, r=30):
    # IMREAD_UNCHANGED : une capture de fenêtre par identifiant contient un canal alpha
    # qui décrit ses vrais coins arrondis et sa transparence. L'ignorer et arrondir
    # nous-mêmes laissait des coins noirs sur les fenêtres sans bord, comme le panneau
    # de choix, dont le rayon ne correspond pas à celui qu'on devinait.
    win = cv2.imread(str(win_path), cv2.IMREAD_UNCHANGED)
    if win is None:
        raise SystemExit(f"capture illisible : {win_path}")
    captured_alpha = win[:, :, 3] if win.shape[2] == 4 else None
    win = win[:, :, :3]

    h, w = win.shape[:2]
    s = target_h / h
    size = (int(w * s), target_h)
    win = cv2.resize(win, size, interpolation=cv2.INTER_AREA)
    h, w = win.shape[:2]
    if captured_alpha is not None:
        alpha = cv2.resize(captured_alpha, size,
                           interpolation=cv2.INTER_AREA).astype(np.float32) / 255.0
    else:
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


if len(sys.argv) >= 3:
    compose(sys.argv[1], sys.argv[2],
            target_h=int(sys.argv[3]) if len(sys.argv) > 3 else 880)
else:
    compose("/tmp/onb-en-check.png", ROOT / "assets" / "onboarding.png", target_h=980)
    compose("/tmp/panel-en.png", ROOT / "assets" / "modal.png", target_h=820)

"""Icône d'app (1024) Mugshot : clin d'oeil vert dans un cadre, sur squircle sombre.

Indépendant de faceid-icon.png (le glyphe interne Face ID reste inchangé)."""
import numpy as np
import cv2
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "appicon-1024.png"

S = 1024
GREEN = (134, 232, 138)          # BGR ~ #8AE886


def squircle(size, margin, radius):
    m = np.zeros((size, size), np.uint8)
    x0, y0, x1, y1 = margin, margin, size - margin, size - margin
    cv2.rectangle(m, (x0 + radius, y0), (x1 - radius, y1), 255, -1)
    cv2.rectangle(m, (x0, y0 + radius), (x1, y1 - radius), 255, -1)
    for cx, cy in [(x0 + radius, y0 + radius), (x1 - radius, y0 + radius),
                   (x0 + radius, y1 - radius), (x1 - radius, y1 - radius)]:
        cv2.circle(m, (cx, cy), radius, 255, -1)
    return m


def cap(img, p, c, r):
    cv2.circle(img, (int(p[0]), int(p[1])), r, c, -1, cv2.LINE_AA)


def seg(img, p1, p2, c, t):
    cv2.line(img, (int(p1[0]), int(p1[1])), (int(p2[0]), int(p2[1])), c, t, cv2.LINE_AA)
    cap(img, p1, c, t // 2); cap(img, p2, c, t // 2)


def rrect(img, x0, y0, x1, y1, rad, c, t):
    cv2.line(img, (x0 + rad, y0), (x1 - rad, y0), c, t, cv2.LINE_AA)
    cv2.line(img, (x0 + rad, y1), (x1 - rad, y1), c, t, cv2.LINE_AA)
    cv2.line(img, (x0, y0 + rad), (x0, y1 - rad), c, t, cv2.LINE_AA)
    cv2.line(img, (x1, y0 + rad), (x1, y1 - rad), c, t, cv2.LINE_AA)
    for cx, cy, a in [(x0 + rad, y0 + rad, 180), (x1 - rad, y0 + rad, 270),
                      (x1 - rad, y1 - rad, 0), (x0 + rad, y1 - rad, 90)]:
        cv2.ellipse(img, (cx, cy), (rad, rad), a, 0, 90, c, t, cv2.LINE_AA)


# fond : dégradé vertical charbon
top = np.array([46, 44, 42], np.float32)
bot = np.array([16, 15, 14], np.float32)
bg = np.zeros((S, S, 3), np.float32)
for y in range(S):
    t = y / (S - 1)
    bg[y, :] = top * (1 - t) + bot * t
bg = bg.astype(np.uint8)

# cadre + visage clin d'oeil (proportions du logo, mises à l'échelle 1024)
rrect(bg, 226, 226, 798, 798, 106, GREEN, 40)
cx, cy = 512, 500
seg(bg, (cx - 96, cy - 60), (cx - 96, cy + 3), GREEN, 48)          # oeil ouvert
seg(bg, (cx + 60, cy - 27), (cx + 132, cy - 27), GREEN, 48)        # clin d'oeil
cv2.ellipse(bg, (cx, cy + 75), (120, 87), 0, 20, 160, GREEN, 48, cv2.LINE_AA)
for a in (20, 160):
    r = np.deg2rad(a)
    cap(bg, (cx + 120 * np.cos(r), cy + 75 + 87 * np.sin(r)), GREEN, 24)

img = np.dstack([bg, squircle(S, 88, 196)])
cv2.imwrite(str(OUT), img)
print("écrit", OUT)

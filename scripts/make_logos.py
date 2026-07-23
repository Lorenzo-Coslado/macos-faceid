"""Dessine 3 concepts de logo pour Mugshot, inspirés du glyphe visage actuel."""
import numpy as np
import cv2
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "logos"
OUT.mkdir(parents=True, exist_ok=True)

S = 680
GREEN = (134, 232, 138)        # BGR ~ #8AE886
DIM = (86, 150, 96)            # vert plus sombre
T = 32


def squircle_mask(size=S, margin=56, radius=132):
    m = np.zeros((size, size), np.uint8)
    x0, y0, x1, y1 = margin, margin, size - margin, size - margin
    cv2.rectangle(m, (x0 + radius, y0), (x1 - radius, y1), 255, -1)
    cv2.rectangle(m, (x0, y0 + radius), (x1, y1 - radius), 255, -1)
    for cx, cy in [(x0 + radius, y0 + radius), (x1 - radius, y0 + radius),
                   (x0 + radius, y1 - radius), (x1 - radius, y1 - radius)]:
        cv2.circle(m, (cx, cy), radius, 255, -1)
    return m


def base3():
    top = np.array([46, 44, 42], np.float32)
    bot = np.array([16, 15, 14], np.float32)
    g = np.zeros((S, S, 3), np.float32)
    for y in range(S):
        t = y / (S - 1)
        g[y, :] = top * (1 - t) + bot * t
    return g.astype(np.uint8)


def save(bg3, name):
    out = np.dstack([bg3, squircle_mask()])
    cv2.imwrite(str(OUT / name), out)


def cap(img, p, color, r):
    cv2.circle(img, (int(p[0]), int(p[1])), r, color, -1, cv2.LINE_AA)


def seg(img, p1, p2, color, t):
    cv2.line(img, (int(p1[0]), int(p1[1])), (int(p2[0]), int(p2[1])), color, t, cv2.LINE_AA)
    cap(img, p1, color, t // 2); cap(img, p2, color, t // 2)


def face(img, cx, cy, s, color=GREEN, t=T):
    seg(img, (cx - 76 * s, cy - 44 * s), (cx - 76 * s, cy + 3 * s), color, t)
    seg(img, (cx + 76 * s, cy - 44 * s), (cx + 76 * s, cy + 3 * s), color, t)
    seg(img, (cx, cy - 44 * s), (cx, cy + 28 * s), color, t)
    cv2.ellipse(img, (int(cx - 24 * s), int(cy + 28 * s)), (int(24 * s), int(24 * s)), 0, 0, 90, color, t, cv2.LINE_AA)
    cap(img, (cx, cy - 44 * s), color, t // 2)
    cv2.ellipse(img, (int(cx), int(cy + 60 * s)), (int(86 * s), int(62 * s)), 0, 25, 155, color, t, cv2.LINE_AA)
    for a in (25, 155):
        r = np.deg2rad(a)
        cap(img, (cx + 86 * s * np.cos(r), cy + 60 * s + 62 * s * np.sin(r)), color, t // 2)


def rrect(img, x0, y0, x1, y1, rad, color, t):
    cv2.line(img, (x0 + rad, y0), (x1 - rad, y0), color, t, cv2.LINE_AA)
    cv2.line(img, (x0 + rad, y1), (x1 - rad, y1), color, t, cv2.LINE_AA)
    cv2.line(img, (x0, y0 + rad), (x0, y1 - rad), color, t, cv2.LINE_AA)
    cv2.line(img, (x1, y0 + rad), (x1, y1 - rad), color, t, cv2.LINE_AA)
    for (cx, cy, a) in [(x0 + rad, y0 + rad, 180), (x1 - rad, y0 + rad, 270),
                        (x1 - rad, y1 - rad, 0), (x0 + rad, y1 - rad, 90)]:
        cv2.ellipse(img, (cx, cy), (rad, rad), a, 0, 90, color, t, cv2.LINE_AA)


# --- 1 : mugshot / height chart derrière le visage ---
c1 = base3()
for y in range(200, 500, 74):
    cv2.line(c1, (150, y), (530, y), DIM, 7, cv2.LINE_AA)
    cv2.line(c1, (152, y - 14), (152, y + 14), DIM, 7, cv2.LINE_AA)
face(c1, 340, 336, 0.94)
save(c1, "1_mugbook.png")

# --- 2 : visage encadré (photo / mugshot) ---
c2 = base3()
rrect(c2, 150, 150, 530, 530, 70, GREEN, 26)
face(c2, 340, 332, 0.82)
save(c2, "2_frame.png")

# --- 3 : jeu de mots "mug" (tasse) avec un visage + vapeur ---
c3 = base3()
rrect(c3, 200, 250, 452, 480, 42, GREEN, T)
cv2.ellipse(c3, (474, 330), (54, 54), 0, -68, 68, GREEN, T, cv2.LINE_AA)
seg(c3, (283, 318), (283, 352), GREEN, 26)
seg(c3, (373, 318), (373, 352), GREEN, 26)
cv2.ellipse(c3, (328, 372), (52, 40), 0, 25, 155, GREEN, 26, cv2.LINE_AA)
for x in (300, 356):
    cv2.ellipse(c3, (x, 210), (15, 24), 0, 90, 300, DIM, 9, cv2.LINE_AA)
save(c3, "3_mug.png")

# --- 4 : appareil photo dont l'objectif est un visage ---
c4 = base3()
rrect(c4, 172, 258, 508, 486, 44, GREEN, T)
rrect(c4, 236, 224, 322, 260, 14, GREEN, T)          # bosse viseur
cv2.circle(c4, (340, 376), 90, GREEN, T, cv2.LINE_AA)  # objectif
face(c4, 340, 368, 0.54)
cv2.circle(c4, (455, 292), 11, GREEN, -1, cv2.LINE_AA)  # flash
save(c4, "4_camera.png")

# --- 5 : visage + plaque d'identité (numéro de booking) ---
c5 = base3()
face(c5, 340, 288, 0.6)
rrect(c5, 210, 398, 470, 502, 26, GREEN, 26)
for yy in (432, 466):
    cv2.line(c5, (250, yy), (430, yy), GREEN, 15, cv2.LINE_AA)
save(c5, "5_placard.png")

def brackets(img, x0, y0, x1, y1, r, L, color, t):
    cv2.ellipse(img, (x0 + r, y0 + r), (r, r), 180, 0, 90, color, t, cv2.LINE_AA)
    seg(img, (x0, y0 + r), (x0, y0 + r + L), color, t); seg(img, (x0 + r, y0), (x0 + r + L, y0), color, t)
    cv2.ellipse(img, (x1 - r, y0 + r), (r, r), 270, 0, 90, color, t, cv2.LINE_AA)
    seg(img, (x1, y0 + r), (x1, y0 + r + L), color, t); seg(img, (x1 - r, y0), (x1 - r - L, y0), color, t)
    cv2.ellipse(img, (x1 - r, y1 - r), (r, r), 0, 0, 90, color, t, cv2.LINE_AA)
    seg(img, (x1, y1 - r), (x1, y1 - r - L), color, t); seg(img, (x1 - r, y1), (x1 - r - L, y1), color, t)
    cv2.ellipse(img, (x0 + r, y1 - r), (r, r), 90, 0, 90, color, t, cv2.LINE_AA)
    seg(img, (x0, y1 - r), (x0, y1 - r - L), color, t); seg(img, (x0 + r, y1), (x0 + r + L, y1), color, t)


def wink_face(img, cx, cy, color=GREEN, t=T):
    seg(img, (cx - 64, cy - 40), (cx - 64, cy + 2), color, t)          # oeil ouvert
    seg(img, (cx + 40, cy - 18), (cx + 88, cy - 18), color, t)         # clin d'oeil
    cv2.ellipse(img, (cx, cy + 50), (80, 58), 0, 20, 160, color, t, cv2.LINE_AA)
    for a in (20, 160):
        r = np.deg2rad(a)
        cap(img, (cx + 80 * np.cos(r), cy + 50 + 58 * np.sin(r)), color, t // 2)


# --- 6 : clin d'oeil dans les 4 crochets d'angle (comme le logo actuel) ---
c6 = base3()
brackets(c6, 156, 160, 524, 512, 58, 72, GREEN, 30)
wink_face(c6, 340, 330)
save(c6, "6_wink.png")

# --- planches contact ---
strip2 = np.full((360, 1140, 3), 245, np.uint8)
for i, name in enumerate(["4_camera.png", "5_placard.png", "6_wink.png"]):
    im = cv2.imread(str(OUT / name), cv2.IMREAD_UNCHANGED)
    a = im[:, :, 3:4].astype(np.float32) / 255
    comp = (im[:, :, :3].astype(np.float32) * a + 245 * (1 - a)).astype(np.uint8)
    comp = cv2.resize(comp, (320, 320))
    strip2[20:340, 40 + i * 370:40 + i * 370 + 320] = comp
cv2.imwrite("/tmp/logos-strip2.png", strip2)

strip = np.full((360, 1140, 3), 245, np.uint8)
for i, name in enumerate(["1_mugbook.png", "2_frame.png", "3_mug.png"]):
    im = cv2.imread(str(OUT / name), cv2.IMREAD_UNCHANGED)
    a = im[:, :, 3:4].astype(np.float32) / 255
    comp = (im[:, :, :3].astype(np.float32) * a + 245 * (1 - a)).astype(np.uint8)
    comp = cv2.resize(comp, (320, 320))
    x = 40 + i * 370
    strip[20:340, x:x + 320] = comp
cv2.imwrite("/tmp/logos-strip.png", strip)
print("ok")

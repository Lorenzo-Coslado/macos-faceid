"""Génère l'icône d'app (1024) : squircle sombre + glyphe Face ID vert."""
import numpy as np
import cv2
from pathlib import Path

S = 1024
ROOT = Path(__file__).resolve().parent.parent
GLYPH = ROOT / "assets" / "faceid-icon.png"
OUT = ROOT / "assets" / "appicon-1024.png"


def rounded_mask(size, margin, radius):
    m = np.zeros((size, size), np.uint8)
    x0, y0, x1, y1 = margin, margin, size - margin, size - margin
    cv2.rectangle(m, (x0 + radius, y0), (x1 - radius, y1), 255, -1)
    cv2.rectangle(m, (x0, y0 + radius), (x1, y1 - radius), 255, -1)
    for cx, cy in [(x0 + radius, y0 + radius), (x1 - radius, y0 + radius),
                   (x0 + radius, y1 - radius), (x1 - radius, y1 - radius)]:
        cv2.circle(m, (cx, cy), radius, 255, -1)
    return m


# fond : dégradé vertical charbon (haut plus clair)
top = np.array([46, 44, 42], np.float32)     # BGR ~ #2A2C2E
bot = np.array([16, 15, 14], np.float32)     # ~ #0E0F10
grad = np.zeros((S, S, 3), np.float32)
for y in range(S):
    t = y / (S - 1)
    grad[y, :, :] = top * (1 - t) + bot * t
bg = grad.astype(np.uint8)

# masque squircle
mask = rounded_mask(S, margin=88, radius=196)

# canvas RGBA
img = np.zeros((S, S, 4), np.uint8)
img[:, :, :3] = bg
img[:, :, 3] = mask

# liseré subtil clair sur le bord
edge = cv2.dilate(mask, np.ones((3, 3), np.uint8)) - cv2.erode(mask, np.ones((3, 3), np.uint8))
img[edge > 0, :3] = (70, 70, 74)

# composite du glyphe vert centré
glyph = cv2.imread(str(GLYPH), cv2.IMREAD_UNCHANGED)  # BGRA
g = 620
glyph = cv2.resize(glyph, (g, g), interpolation=cv2.INTER_AREA)
ox = (S - g) // 2
oy = (S - g) // 2
ga = glyph[:, :, 3:4].astype(np.float32) / 255.0
roi = img[oy:oy + g, ox:ox + g, :3].astype(np.float32)
img[oy:oy + g, ox:ox + g, :3] = (glyph[:, :, :3].astype(np.float32) * ga + roi * (1 - ga)).astype(np.uint8)
# l'alpha du glyphe renforce l'alpha global là où il dépasserait (il ne dépasse pas ici)
img[oy:oy + g, ox:ox + g, 3] = np.maximum(img[oy:oy + g, ox:ox + g, 3], glyph[:, :, 3])

cv2.imwrite(str(OUT), img)
print("écrit", OUT)

"""Dessine le glyphe Face ID (vert) en 512x512 PNG transparent."""
import numpy as np, cv2

S = 512
img = np.zeros((S, S, 4), dtype=np.uint8)
COL = (134, 232, 138, 255)  # BGR+A ~ #8AE886
T = 30                       # épaisseur de trait
R2 = T // 2                  # rayon des bouts ronds

def cap(p):
    cv2.circle(img, p, R2, COL, -1, cv2.LINE_AA)

def seg(p1, p2):
    cv2.line(img, p1, p2, COL, T, cv2.LINE_AA); cap(p1); cap(p2)

def arc(center, radius, a0, a1, caps=True):
    cv2.ellipse(img, center, (radius, radius), 0, a0, a1, COL, T, cv2.LINE_AA)
    if caps:
        for a in (a0, a1):
            r = np.deg2rad(a)
            cap((int(center[0] + radius*np.cos(r)), int(center[1] + radius*np.sin(r))))

# --- 4 crochets d'angle (arc 90° + 2 bras courts) ---
M, R, L = 62, 85, 50   # marge, rayon d'angle, longueur de bras
c = M + R
for (cx, cy, a0) in [(c, c, 180), (S-c, c, 270), (S-c, S-c, 0), (c, S-c, 90)]:
    arc((cx, cy), R, a0, a0+90, caps=False)
# bras + bouts ronds
seg((c, M), (c+L, M) if False else (c+L, M))            # TL horizontal
seg((M, c), (M, c+L))                                    # TL vertical
seg((S-c-L, M), (S-c, M))                                # TR horizontal
seg((S-M, c), (S-M, c+L))                                # TR vertical
seg((S-c-L, S-M), (S-c, S-M))                            # BR horizontal
seg((S-M, S-c-L), (S-M, S-c))                            # BR vertical
seg((c, S-M), (c+L, S-M))                                # BL horizontal
seg((M, S-c-L), (M, S-c))                                # BL vertical

# --- visage ---
seg((180, 185), (180, 232))          # œil gauche
seg((332, 185), (332, 232))          # œil droit
seg((256, 185), (256, 256))          # nez (vertical)
arc((232, 256), 24, 0, 90)           # petit crochet du nez vers la gauche
# sourire
cv2.ellipse(img, (256, 290), (86, 62), 0, 25, 155, COL, T, cv2.LINE_AA)
for a in (25, 155):
    r = np.deg2rad(a)
    cap((int(256 + 86*np.cos(r)), int(290 + 62*np.sin(r))))

cv2.imwrite("assets/faceid-icon.png", img)
print("assets/faceid-icon.png écrit")

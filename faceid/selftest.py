"""Selftest sans caméra : prouve que les modèles chargent et que le pipeline
d'embeddings fonctionne (détection sans crash + feature 128-d + cosinus).

Usage :  python -m faceid.selftest
"""
import numpy as np

from .recognizer import FaceEngine


def main():
    eng = FaceEngine()

    # 1) Le détecteur doit tourner sans crash sur une image vide.
    blank = np.zeros((240, 320, 3), dtype=np.uint8)
    faces = eng.detect(blank)
    print(f"[1] détecteur OK — {len(faces)} visage(s) sur image vide (attendu 0)")

    # 2) SFace doit produire un vecteur 128-d sur un crop aligné 112x112.
    rng = np.random.default_rng(0)
    crop = (rng.random((112, 112, 3)) * 255).astype(np.uint8)
    feat = eng.recognizer.feature(crop).flatten()
    print(f"[2] SFace feature dim = {feat.shape[0]} (attendu 128)")

    # 3) Cohérence du cosinus.
    self_sim = FaceEngine.cosine(feat, feat)
    print(f"[3] cosine(feat, feat) = {self_sim:.4f} (attendu ~1.0)")

    assert feat.shape[0] == 128, "dimension d'embedding inattendue"
    assert abs(self_sim - 1.0) < 1e-3, "cosinus incohérent"

    print("SELFTEST OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

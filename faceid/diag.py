"""Diagnostic caméra + reconnaissance, à lancer depuis le Terminal.

Affiche, pour chaque frame : taille du visage détecté et meilleur score cosinus
vs les embeddings enrôlés. Vérifie aussi la cohérence interne de l'enrôlement.

Usage :  ./.venv/bin/python -m faceid.diag [secondes]
"""
import sys
import time

import numpy as np
import cv2

from . import config
from .recognizer import FaceEngine, load_embeddings, best_match


def enrollment_health(enrolled):
    """Cohérence interne : cosinus moyen de chaque vecteur vs la moyenne."""
    mean = enrolled.mean(axis=0)
    sims = [FaceEngine.cosine(mean, e) for e in enrolled]
    print(f"  {len(enrolled)} vecteurs enrôlés")
    print(f"  cohérence (cos vs moyenne) : "
          f"moy={np.mean(sims):.3f}  min={np.min(sims):.3f}  max={np.max(sims):.3f}")
    # cohérence deux-à-deux la plus faible
    worst = 1.0
    for i in range(len(enrolled)):
        for j in range(i + 1, len(enrolled)):
            worst = min(worst, FaceEngine.cosine(enrolled[i], enrolled[j]))
    print(f"  paire la moins cohérente   : {worst:.3f} "
          f"(si très bas → enrôlement bruité)")


def main():
    duration = float(sys.argv[1]) if len(sys.argv) > 1 else 6.0

    engine = FaceEngine()
    enrolled = load_embeddings()
    if enrolled is None:
        print("Aucun embedding enrôlé. Lance d'abord : python -m faceid.enroll",
              file=sys.stderr)
        return 1

    print("=== Santé de l'enrôlement ===")
    enrollment_health(enrolled)

    print(f"\n=== Capture live {duration:.0f}s (regarde la caméra) ===")
    cap = cv2.VideoCapture(config.CAMERA_INDEX)
    if not cap.isOpened():
        print("ERREUR : caméra non autorisée/indisponible dans CE contexte.",
              file=sys.stderr)
        return 2

    scores = []
    faces_seen = 0
    frames = 0
    t0 = time.time()
    try:
        while time.time() - t0 < duration:
            ok, frame = cap.read()
            if not ok:
                continue
            frames += 1
            feat, face = engine.frame_feature(frame)
            if feat is None:
                # visage absent ou trop petit
                if face is not None:
                    print(f"  frame {frames:3d} : visage trop petit "
                          f"({int(face[2])}x{int(face[3])} px)")
                continue
            faces_seen += 1
            score = best_match(feat, enrolled)
            scores.append(score)
            flag = "OK  " if score >= config.COSINE_THRESHOLD else "fail"
            print(f"  frame {frames:3d} : [{flag}] score={score:.3f} "
                  f"visage {int(face[2])}x{int(face[3])} px")
    finally:
        cap.release()

    print("\n=== Résumé ===")
    print(f"  frames lues            : {frames}")
    print(f"  frames avec visage     : {faces_seen}")
    if scores:
        arr = np.array(scores)
        print(f"  score  max={arr.max():.3f}  moy={arr.mean():.3f}  "
              f"min={arr.min():.3f}")
        print(f"  seuil actuel           : {config.COSINE_THRESHOLD}")
        n_pass = int((arr >= config.COSINE_THRESHOLD).sum())
        print(f"  frames au-dessus seuil : {n_pass}/{len(scores)}")
        print("\nInterprétation :")
        if arr.max() >= 0.45:
            print("  → scores bons : le pipeline marche. Si le daemon échoue,")
            print("    c'est l'autorisation caméra sous launchd (TCC).")
        elif arr.max() >= 0.30:
            print("  → scores moyens : baisse FACEID_THRESHOLD (~0.30) ou")
            print("    ré-enrôle dans les mêmes conditions de lumière.")
        else:
            print("  → scores bas : ré-enrôlement nécessaire (enrôlement bruité")
            print("    ou conditions très différentes).")
    else:
        print("  aucun visage exploitable capté (cadre/lumière ?).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

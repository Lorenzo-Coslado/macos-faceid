"""Enrôlement : capture ton visage et enregistre les embeddings de référence.

Usage :  python -m faceid.enroll [--json] [--append]
  --json   : émet la progression en JSON (une ligne par événement) pour l'UI.
  --append : ajoute une apparence au lieu de remplacer l'enrôlement existant.

L'ajout sert exactement à ce que fait le vrai Face ID avec ses « apparences » : des
lunettes, une barbe, la lumière du soir. `best_match` compare déjà à tous les vecteurs
enregistrés, donc ajouter revient à concaténer.
"""
import sys
import json
import time

import numpy as np
import cv2

from . import config
from .recognizer import FaceEngine, load_embeddings, save_embeddings

JSON = "--json" in sys.argv
APPEND = "--append" in sys.argv


def emit(**ev):
    """Émet un événement. Les erreurs portent un CODE stable (`msg`), pas une phrase :
    l'app le traduit via la clé `err.<code>`. Auparavant le moteur renvoyait des
    phrases françaises, affichées telles quelles dans une interface anglaise."""
    if JSON:
        print(json.dumps(ev), flush=True)
    else:
        if ev.get("event") == "progress":
            print(f"  [{ev['i']}/{ev['n']}] visage capturé", flush=True)
        elif ev.get("event") == "start":
            print(f"Enrôlement : {ev['n']} échantillons à capturer.", flush=True)
        elif ev.get("event") == "done":
            print(f"\nOK — {ev['kept']} échantillons gardés "
                  f"({ev['dropped']} écarté(s)). Cohérence {ev['consistency']:.3f}")
        elif ev.get("event") == "error":
            print(f"ERREUR : {ev['msg']}", file=sys.stderr)


def _filter_outliers(samples, min_keep=6, min_cos=0.45):
    arr = np.vstack(samples)
    n = len(arr)
    scores = np.empty(n, dtype=np.float32)
    for i in range(n):
        others = np.delete(arr, i, axis=0)
        scores[i] = FaceEngine.cosine(arr[i], others.mean(axis=0))
    order = np.argsort(-scores)
    kept = [int(i) for i in order if scores[i] >= min_cos]
    if len(kept) < min_keep:
        kept = [int(i) for i in order[:min_keep]]
    kept.sort()
    return arr[kept], scores, kept


def main():
    try:
        engine = FaceEngine()
    except FileNotFoundError as e:
        emit(event="error", msg="models-missing", detail=str(e))
        return 1

    cap = cv2.VideoCapture(config.CAMERA_INDEX, cv2.CAP_AVFOUNDATION)
    if not cap.isOpened():
        emit(event="error", msg="camera-unavailable")
        return 1
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, config.CAPTURE_WIDTH)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, config.CAPTURE_HEIGHT)

    for _ in range(config.CAMERA_WARMUP_FRAMES):
        cap.read()

    emit(event="start", n=config.ENROLL_SAMPLES)

    samples = []
    last_capture = 0.0
    try:
        while len(samples) < config.ENROLL_SAMPLES:
            ok, frame = cap.read()
            if not ok:
                continue
            feat, _ = engine.frame_feature(frame)
            now = time.time()
            if feat is not None and (now - last_capture) > 0.4:
                samples.append(feat)
                last_capture = now
                emit(event="progress", i=len(samples), n=config.ENROLL_SAMPLES)
    except KeyboardInterrupt:
        emit(event="error", msg="interrupted")
        return 1
    finally:
        cap.release()

    if len(samples) < config.ENROLL_SAMPLES:
        emit(event="error", msg="not-enough-samples")
        return 1

    kept_arr, scores, kept = _filter_outliers(samples)
    dropped = len(samples) - len(kept)

    # Cohérence calculée sur la seule nouvelle série : la mélanger aux apparences déjà
    # enregistrées ferait chuter le chiffre alors que la capture est bonne — deux
    # apparences se ressemblent moins entre elles qu'une apparence avec elle-même.
    mean = kept_arr.mean(axis=0)
    cons = float(np.mean([FaceEngine.cosine(mean, s) for s in kept_arr]))

    if APPEND:
        existing = load_embeddings()
        if existing is not None and len(existing):
            kept_arr = np.vstack([existing, kept_arr])
    save_embeddings(kept_arr)

    emit(event="done", kept=len(kept_arr), dropped=dropped, consistency=cons)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

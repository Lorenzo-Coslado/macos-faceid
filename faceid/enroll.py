"""Enrôlement : capture ton visage et enregistre les embeddings de référence.

Usage :  python -m faceid.enroll [--json]
  --json : émet la progression en JSON (une ligne par événement) pour l'UI.
"""
import sys
import json
import time

import numpy as np
import cv2

from . import config
from .recognizer import FaceEngine, save_embeddings

JSON = "--json" in sys.argv


def emit(**ev):
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
        emit(event="error", msg=str(e))
        return 1

    cap = cv2.VideoCapture(config.CAMERA_INDEX)
    if not cap.isOpened():
        emit(event="error", msg="camera-unavailable")
        return 1

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
        emit(event="error", msg="interrompu")
        return 1
    finally:
        cap.release()

    if len(samples) < config.ENROLL_SAMPLES:
        emit(event="error", msg="pas assez d'échantillons")
        return 1

    kept_arr, scores, kept = _filter_outliers(samples)
    dropped = len(samples) - len(kept)
    save_embeddings(kept_arr)

    mean = kept_arr.mean(axis=0)
    cons = float(np.mean([FaceEngine.cosine(mean, s) for s in kept_arr]))
    emit(event="done", kept=len(kept_arr), dropped=dropped, consistency=cons)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

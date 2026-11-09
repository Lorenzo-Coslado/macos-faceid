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
import base64
import math
import select

import numpy as np
import cv2

from . import config
from .recognizer import FaceEngine, load_embeddings, save_embeddings
from .enrollment import HeadCoverage, SECTORS, face_position, landmark_pose

JSON = "--json" in sys.argv
APPEND = "--append" in sys.argv
GUIDED = "--guided" in sys.argv


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


def _preview(frame):
    """JPEG stays in the local pipe; neither frames nor video are saved to disk."""
    height, width = frame.shape[:2]
    side = min(width, height)
    left, top = (width - side) // 2, (height - side) // 2
    square = frame[top:top + side, left:left + side]
    square = cv2.resize(cv2.flip(square, 1), (360, 360))
    ok, jpeg = cv2.imencode(".jpg", square, [cv2.IMWRITE_JPEG_QUALITY, 72])
    return base64.b64encode(jpeg).decode("ascii") if ok else None


def _guided_samples(engine, cap):
    per_sector = max(1, math.ceil(config.ENROLL_SAMPLES / (2 * SECTORS)))
    coverage = HeadCoverage(per_sector)
    total = 2 * (1 + SECTORS * per_sector)
    emit(event="start", n=total, passes=2)
    samples = []
    pass_number = 1
    waiting = False
    started = last_capture = last_frame = time.monotonic()
    while True:
        now = time.monotonic()
        if now - started > (180 if waiting else config.ENROLL_TIMEOUT_S):
            emit(event="error", msg="enroll-timeout")
            return None
        if waiting and select.select([sys.stdin], [], [], 0)[0]:
            command = sys.stdin.readline()
            if not command:  # The UI disappeared: immediately release the camera.
                return None
            if command.strip() == "CONTINUE":
                waiting = False
                pass_number = 2
                coverage.reset_pass()
                started = now
                emit(event="pass-start", passIndex=pass_number, coverage=coverage.coverage)
        ok, frame = cap.read()
        if not ok:
            continue
        if now - last_frame < 0.09:
            continue
        last_frame = now
        faces = engine.detect(frame)
        hint = "no-face" if len(faces) == 0 else "one-face"
        pose = None
        face = faces[0] if len(faces) == 1 else None
        if face is not None:
            hint = face_position(face, frame.shape)
            if hint == "move":
                pose = landmark_pose(face)
                if pose is None:
                    hint = "center"
        if pose is not None and not waiting:
            if not coverage.centered:
                hint = "look-straight"
            if now - last_capture >= 0.28:
                # Only advance after a usable embedding has actually been made.
                feature = engine.feature(frame, face)
                if feature is not None and coverage.capture(pose):
                    samples.append(feature)
                    last_capture = now
                    emit(event="progress", i=len(samples), n=total,
                         passIndex=pass_number, coverage=coverage.coverage)
        sector, x, y = coverage.direction(pose) if pose is not None else (None, 0, 0)
        emit(event="frame", jpeg=_preview(frame), hint=hint,
             passIndex=pass_number, coverage=coverage.coverage,
             sector=sector, headX=float(x), headY=float(y))
        if coverage.complete and not waiting:
            if pass_number == 2:
                return samples
            waiting = True
            started = now
            emit(event="pass-complete", passIndex=pass_number)


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

    samples = []
    last_capture = 0.0
    started = time.time()
    try:
        if GUIDED:
            samples = _guided_samples(engine, cap)
            if samples is None:
                return 1
        else:
            emit(event="start", n=config.ENROLL_SAMPLES)
        while not GUIDED and len(samples) < config.ENROLL_SAMPLES:
            # La boucle attendait ses échantillons sans limite de temps : quand la
            # fenêtre se fermait en cours de route, ou que personne ne se présentait
            # devant la caméra, elle tenait l'objectif et un cœur indéfiniment.
            if (time.time() - started) > config.ENROLL_TIMEOUT_S:
                emit(event="error", msg="enroll-timeout",
                     captured=len(samples), expected=config.ENROLL_SAMPLES)
                return 1
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

#!/usr/bin/env python3
"""Tests du moteur qui ne demandent ni caméra ni visage.

Ils couvrent ce que `faceid.selftest` ne voit pas : le comportement du daemon autour de
la reconnaissance — préchauffage, abandon, enrôlement cumulatif, lecture des réglages —
et le protocole de sa socket. Chacun correspond à un défaut réel rencontré.

    python tests/test_engine.py
"""
import os
import socket
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

import numpy as np                                          # noqa: E402
import cv2                                                  # noqa: E402

from faceid import config, daemon, recognizer, verify_client  # noqa: E402

FAILURES = []


def check(name, ok, detail=""):
    print(f"  {'OK  ' if ok else 'FAIL'}  {name}" + (f"  → {detail}" if detail else ""))
    if not ok:
        FAILURES.append(name)


# --------------------------------------------------------------------------- warmup
class FakeCapture:
    """Caméra factice qui débite une suite de luminosités connues."""

    def __init__(self, brightnesses):
        self.queue = list(brightnesses)
        self.last = 0
        self.reads = 0

    def read(self):
        self.reads += 1
        if self.queue:
            self.last = self.queue.pop(0)
        return True, np.full((8, 8, 3), self.last, dtype=np.uint8)


def test_warmup():
    print("préchauffage adaptatif")
    cap = FakeCapture([100] * 8)
    daemon._adaptive_warmup(cap)
    check("s'arrête dès que l'exposition est stable", cap.reads == 2,
          f"{cap.reads} frames")

    cap = FakeCapture([10, 40, 70, 100, 130, 160, 190, 220])
    daemon._adaptive_warmup(cap)
    check("garde le plafond quand elle bouge encore",
          cap.reads == config.CAMERA_WARMUP_FRAMES, f"{cap.reads} frames")


def test_verify_client_mode():
    print("client de vérification")
    check("VERIFY reste le mode par défaut",
          verify_client.command_for_args([]) == b"VERIFY\n")
    check("--lock sélectionne VERIFY_LOCK",
          verify_client.command_for_args(["--lock"]) == b"VERIFY_LOCK\n")


# ---------------------------------------------------------------------- annulation
class SlowCapture:
    """Caméra qui ne montre jamais de visage : sans abandon, on attend le budget."""

    def __init__(self):
        self.released = False

    def isOpened(self):                                     # noqa: N802 (API OpenCV)
        return True

    def set(self, *_):
        pass

    def read(self):
        time.sleep(0.01)
        return True, np.zeros((480, 640, 3), dtype=np.uint8)

    def release(self):
        self.released = True


def test_cancel():
    print("abandon depuis la capsule")
    fake = SlowCapture()
    original = cv2.VideoCapture
    cv2.VideoCapture = lambda *a, **k: fake
    try:
        d = daemon.Daemon.__new__(daemon.Daemon)
        d.enrolled = np.random.rand(4, 128).astype(np.float32)
        d.enrolled_mtime = 0.0
        d._mtime = lambda: 0.0
        d.engine = type("E", (), {"frame_feature": lambda self, f: (None, None)})()

        cancelled = threading.Event()
        threading.Timer(0.25, cancelled.set).start()
        started = time.time()
        ok, reason = d._verify_face_camera(timeout=30, cancelled=cancelled)
        elapsed = time.time() - started

        check("le clic interrompt la reconnaissance",
              not ok and "cancelled" in reason, reason)
        check("il rend la main sans attendre le budget", elapsed < 2.0,
              f"{elapsed:.2f}s au lieu de 30s")
        check("la caméra est relâchée", fake.released)
    finally:
        cv2.VideoCapture = original


# ------------------------------------------------------------- absence de visage
def test_no_face_abort():
    print("abandon quand personne n'est devant la caméra")
    fake = SlowCapture()
    original = cv2.VideoCapture
    cv2.VideoCapture = lambda *a, **k: fake
    saved = config.VERIFY_NO_FACE_ABORT_S
    config.VERIFY_NO_FACE_ABORT_S = 0.5
    try:
        d = daemon.Daemon.__new__(daemon.Daemon)
        d.enrolled = np.random.rand(4, 128).astype(np.float32)
        d.enrolled_mtime = 0.0
        d._mtime = lambda: 0.0
        d.engine = type("E", (), {"frame_feature": lambda self, f: (None, None)})()

        started = time.time()
        ok, reason = d._verify_face_camera(timeout=30)
        elapsed = time.time() - started

        check("il renonce au lieu d'épuiser le budget",
              not ok and "no-face" in reason, reason)
        check("sans attendre les 30 s de budget", elapsed < 2.0,
              f"{elapsed:.2f}s")
        check("la caméra est relâchée", fake.released)
    finally:
        config.VERIFY_NO_FACE_ABORT_S = saved
        cv2.VideoCapture = original


def test_present_face_is_never_cut_short():
    print("un visage présent n'est jamais coupé par l'abandon")
    # Le pendant du test précédent : l'abandon ne doit mordre QUE sur l'absence. On
    # met le délai à une valeur absurde (1 ms) et on présente un visage dès la
    # première frame ; la reconnaissance doit aboutir malgré tout.
    fake = SlowCapture()
    original = cv2.VideoCapture
    cv2.VideoCapture = lambda *a, **k: fake
    saved = config.VERIFY_NO_FACE_ABORT_S
    config.VERIFY_NO_FACE_ABORT_S = 0.001
    try:
        enrolled = np.random.rand(1, 128).astype(np.float32)
        d = daemon.Daemon.__new__(daemon.Daemon)
        d.enrolled = enrolled
        d.enrolled_mtime = 0.0
        d._mtime = lambda: 0.0
        # Caméra qui montre toujours le visage enrôlé : score = 1.0 à chaque frame.
        d.engine = type("E", (), {
            "frame_feature": lambda self, f: (enrolled[0], None)})()

        ok, reason = d._verify_face_camera(timeout=30)
        check("la reconnaissance aboutit", ok, reason)
        check("l'abandon ne s'est pas déclenché", "no-face" not in reason, reason)
        check("elle s'arrête au nombre de correspondances requis",
              f"frames={config.VERIFY_REQUIRED_MATCHES}" in reason, reason)
    finally:
        config.VERIFY_NO_FACE_ABORT_S = saved
        cv2.VideoCapture = original


def test_enroll_is_bounded():
    print("budget de l'enrôlement")
    # La boucle de capture n'avait aucune limite de temps : un enrôlement laissé en
    # plan gardait la caméra et un cœur jusqu'à la fin de la session. On exerce la
    # vraie boucle, caméra factice à l'appui, plutôt que de relire le source.
    from faceid import enroll

    fake = SlowCapture()
    original = cv2.VideoCapture
    cv2.VideoCapture = lambda *a, **k: fake
    saved_budget, saved_emit = config.ENROLL_TIMEOUT_S, enroll.emit
    config.ENROLL_TIMEOUT_S = 0.5
    events = []
    enroll.emit = lambda **ev: events.append(ev)
    started = time.time()
    try:
        code = enroll.main()
    finally:
        enroll.emit = saved_emit
        config.ENROLL_TIMEOUT_S = saved_budget
        cv2.VideoCapture = original
    elapsed = time.time() - started

    check("la boucle rend la main au lieu d'attendre un visage", code == 1)
    check("elle dit pourquoi",
          any(e.get("msg") == "enroll-timeout" for e in events),
          ", ".join(str(e.get("msg") or e.get("event")) for e in events))
    check("dans son budget", elapsed < 3.0, f"{elapsed:.2f}s")
    check("la caméra est relâchée", fake.released)


# ------------------------------------------------------------------- apparences
def test_append():
    print("apparences cumulatives")
    with tempfile.TemporaryDirectory() as tmp:
        saved_dir, saved_path = config.APP_DIR, config.EMBEDDINGS_PATH
        config.APP_DIR = Path(tmp)
        config.EMBEDDINGS_PATH = config.APP_DIR / "embeddings.npy"
        try:
            first = np.random.rand(8, 128).astype(np.float32)
            recognizer.save_embeddings(first)
            merged = np.vstack([recognizer.load_embeddings(),
                                np.random.rand(8, 128).astype(np.float32)])
            recognizer.save_embeddings(merged)
            after = recognizer.load_embeddings()
            check("ajouter concatène au lieu de remplacer", len(after) == 16,
                  f"8 → {len(after)}")
            check("les vecteurs d'origine sont intacts", np.allclose(after[:8], first))
        finally:
            config.APP_DIR, config.EMBEDDINGS_PATH = saved_dir, saved_path


# ----------------------------------------------------------------------- réglages
def test_flags():
    print("lecture des réglages")
    check("le panneau de choix est absent par défaut", config.MODAL_ENABLED is False)
    check("la capsule est présente par défaut", config.HUD_ENABLED is True)
    check("capture en 640×480",
          (config.CAPTURE_WIDTH, config.CAPTURE_HEIGHT) == (640, 480))
    # Une variable posée mais vide valait « activé », parce que "" n'est pas "0".
    check("une variable vide vaut le défaut", config._flag("ABSENTE_ICI", "0") is False)


# ------------------------------------------------------------------------- i18n
def test_i18n():
    print("traductions du moteur")
    table = ROOT / "i18n" / "engine.json"
    if not table.exists():
        check("i18n/engine.json est généré", False, "lancer scripts/make_i18n.py")
        return
    import json
    data = json.loads(table.read_text(encoding="utf-8"))
    check("toutes les langues sont présentes", len(data) == 11, f"{len(data)} langues")
    keys = set(data["en"])
    check("chaque langue a les mêmes clés",
          all(set(v) == keys for v in data.values()))
    check("aucune traduction vide",
          all(all(s.strip() for s in v.values()) for v in data.values()))


# ---------------------------------------------------------------------- socket
def test_socket():
    print("protocole de la socket")
    # Chemin court obligatoire : une socket UNIX est limitée à ~104 caractères.
    runtime = tempfile.mkdtemp(dir="/tmp", prefix="mg")
    env = dict(os.environ)
    env.update({
        "HOME": runtime,             # isole APP_DIR → aucun enrôlement, aucune caméra
        "FACEID_HUD": "0",
        "PYTHONUNBUFFERED": "1",
        "FACEID_I18N": str(ROOT / "i18n"),
    })
    models = os.environ.get(
        "FACEID_MODELS_DIR",
        os.path.expanduser("~/Library/Application Support/faceid/models"))
    env["FACEID_MODELS_DIR"] = models
    # Le daemon refuse de démarrer sans les modèles, et l'échec ressemblait alors à une
    # régression du protocole plutôt qu'à un dépôt incomplet.
    if not os.path.exists(os.path.join(models, "face_detection_yunet_2023mar.onnx")):
        check("les modèles de reconnaissance sont présents", False,
              f"absents de {models} — lancer scripts/download-models.sh")
        return
    os.makedirs(f"{runtime}/Library/Application Support/faceid/logs", exist_ok=True)

    proc = subprocess.Popen([sys.executable, "-m", "faceid.daemon"],
                            cwd=str(ROOT), env=env,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    sock_path = f"{runtime}/Library/Application Support/faceid/faceid.sock"
    for _ in range(150):
        if os.path.exists(sock_path):
            break
        if proc.poll() is not None:
            check("le daemon démarre", False, proc.stdout.read()[:200])
            return
        time.sleep(0.1)
    else:
        check("le daemon crée sa socket", False)
        proc.kill()
        return

    def ask(command):
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(20)
        try:
            s.connect(sock_path)
            s.sendall(command + b"\n")
            return s.recv(64).decode().strip()
        finally:
            s.close()

    try:
        check("le daemon démarre et écoute", True)
        check("PING répond PONG", ask(b"PING") == "PONG")
        check("VERIFY répond sans enrôlement", ask(b"VERIFY") == "FAIL")
        check("VERIFY_LOCK répond aussi", ask(b"VERIFY_LOCK") == "FAIL")
        check("une commande inconnue est rejetée", ask(b"NAWAK").startswith("ERR"))
        for _ in range(5):
            ask(b"PING")
        check("il survit à des connexions successives", proc.poll() is None)
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()


def main():
    for test in (test_warmup, test_verify_client_mode, test_cancel, test_no_face_abort,
                 test_present_face_is_never_cut_short,
                 test_enroll_is_bounded, test_append,
                 test_flags, test_i18n, test_socket):
        test()
    print()
    if FAILURES:
        print(f"ÉCHECS ({len(FAILURES)}) : " + ", ".join(FAILURES))
        return 1
    print("Tous les tests passent.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

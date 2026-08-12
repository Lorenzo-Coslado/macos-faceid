"""Daemon d'authentification (tourne dans la session utilisateur).

Écoute sur une socket Unix. Sur "VERIFY", affiche un modal de choix
(Face ID / Empreinte / Mot de passe) puis :
  - Face ID   -> caméra + reconnaissance faciale (OpenCV)
  - Empreinte -> Touch ID via le helper Swift (LocalAuthentication)
  - Mot de passe / annulation -> FAIL (PAM retombe sur le mot de passe)

Le module PAM (root, lancé par sudo) est le client : il n'a ni caméra ni
accès biométrique, donc c'est ce daemon — dans la session GUI — qui fait tout.
"""
import os
import subprocess
import threading
import time
import socket
import ctypes

import cv2

from . import config
from .recognizer import FaceEngine, load_embeddings, best_match

_libc = ctypes.CDLL(None, use_errno=True)


def log(msg):
    line = f"[faceid] {msg}"
    print(line, flush=True)
    try:
        config.LOG_DIR.mkdir(parents=True, exist_ok=True)
        with open(config.LOG_DIR / "daemon.log", "a") as f:
            f.write(f"{time.strftime('%H:%M:%S')} {line}\n")
    except OSError:
        pass


def peer_euid(conn):
    """euid du process connecté, via getpeereid(2). None si indéterminé."""
    uid = ctypes.c_uint32()
    gid = ctypes.c_uint32()
    if _libc.getpeereid(conn.fileno(), ctypes.byref(uid), ctypes.byref(gid)) != 0:
        return None
    return uid.value


# Libellés du modal, dans la langue du système (cf. config.t). Ils sont aussi passés
# à auth-modal en arguments : ce binaire n'a pas de bundle et ne peut pas les résoudre
# lui-même.
_L_TITLE = config.t("engine.prompt.title", "Authentication required")
_L_SUBTITLE = config.t("engine.prompt.subtitle", "sudo wants to verify your identity")
_L_FACE = config.t("engine.btn.face", "Use Face ID")
_L_TOUCH = config.t("engine.btn.touch", "Use fingerprint")
_L_PASSWORD = config.t("engine.btn.password", "Enter password")


def _quote(s):
    """Échappe une chaîne pour un littéral AppleScript."""
    return s.replace("\\", "\\\\").replace('"', '\\"')


def _build_applescript():
    """Modal de choix. Icône custom (glyphe Face ID) si présente, sinon icône système."""
    if config.MODAL_ICON.exists():
        icon = f'with icon POSIX file "{config.MODAL_ICON}"'
    else:
        icon = "with icon note"
    # AppleScript ne renvoie que le libellé du bouton : on compare ensuite au libellé
    # localisé plutôt qu'à un mot français.
    return (
        f'display dialog "{_quote(_L_SUBTITLE)}" '
        f'with title "{_quote(_L_TITLE)}" '
        f'buttons {{"{_quote(_L_PASSWORD)}", "{_quote(_L_TOUCH)}", "{_quote(_L_FACE)}"}} '
        f'default button "{_quote(_L_FACE)}" {icon}\n'
        'return button returned of result'
    )


# Choix proposés dans le modal. Ordre = ordre des boutons (droite = défaut).
_APPLESCRIPT = _build_applescript()


def _adaptive_warmup(cap):
    """Jette les premières frames, le temps que l'auto-exposition se stabilise.

    On jetait un nombre fixe de frames (8), calibré au pire cas : sur une caméra qui
    se stabilise vite, c'est du temps perdu à chaque `sudo`. On s'arrête maintenant dès
    que la luminosité moyenne cesse de bouger, avec le même plafond qu'avant en garde-fou.
    """
    previous = None
    for _ in range(config.CAMERA_WARMUP_FRAMES):
        ok, frame = cap.read()
        if not ok:
            continue
        brightness = float(frame.mean())
        if previous is not None and abs(brightness - previous) < config.WARMUP_STABLE_DELTA:
            return
        previous = brightness


class Daemon:
    def __init__(self):
        self.engine = FaceEngine()
        self.enrolled = load_embeddings()
        self.enrolled_mtime = self._mtime()
        if self.enrolled is None:
            log("ATTENTION : aucun visage enrôlé (embeddings.npy manquant).")
        else:
            log(f"{len(self.enrolled)} vecteurs enrôlés chargés.")

    # ---- enrôlement ----
    def _mtime(self):
        try:
            return config.EMBEDDINGS_PATH.stat().st_mtime
        except FileNotFoundError:
            return 0.0

    def _maybe_reload(self):
        m = self._mtime()
        if m != self.enrolled_mtime:
            self.enrolled = load_embeddings()
            self.enrolled_mtime = m
            log("embeddings rechargés.")

    # ---- modal de choix ----
    def choose_method(self):
        """Retourne 'face', 'touch' ou 'password' (défaut si modal indispo)."""
        if not config.MODAL_ENABLED:
            return "face"
        # 1) panneau natif AppKit si présent
        if config.AUTH_MODAL.exists():
            try:
                r = subprocess.run(
                    [str(config.AUTH_MODAL), "--timeout", "90",
                     "--title", _L_TITLE, "--subtitle", _L_SUBTITLE,
                     "--face", _L_FACE, "--touch", _L_TOUCH,
                     "--password", _L_PASSWORD],
                    capture_output=True, text=True, timeout=100,
                )
                choice = r.stdout.strip()
                if choice in ("face", "touch", "password"):
                    return choice
                log(f"auth-modal sortie inattendue: {choice!r} -> osascript")
            except (subprocess.SubprocessError, OSError) as e:
                log(f"auth-modal indisponible ({e}) -> osascript")
        # 2) fallback : dialogue osascript
        try:
            r = subprocess.run(
                ["osascript", "-e", _APPLESCRIPT],
                capture_output=True, text=True, timeout=90,
            )
        except (subprocess.SubprocessError, OSError) as e:
            log(f"modal indisponible ({e}) -> Face ID par défaut")
            return "face"
        if r.returncode != 0:
            return "password"
        choice = r.stdout.strip()
        if choice == _L_FACE:
            return "face"
        if choice == _L_TOUCH:
            return "touch"
        return "password"

    # ---- capsule HUD (Dynamic Island) ----
    def _hud_start(self):
        """Lance la capsule. Retourne (process, event d'annulation)."""
        if not config.HUD_ENABLED or not config.FACEID_HUD.exists():
            return None, None
        try:
            hud = subprocess.Popen([str(config.FACEID_HUD)],
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        except OSError as e:
            log(f"hud start error : {e}")
            return None, None

        # Sans panneau de choix, cliquer la capsule est la seule façon de renoncer au
        # visage et de revenir au mot de passe sans attendre l'expiration du budget.
        cancelled = threading.Event()

        def watch():
            try:
                for line in hud.stdout:
                    if line.strip().upper() == b"CANCEL":
                        cancelled.set()
                        return
            except (OSError, ValueError):
                pass

        threading.Thread(target=watch, daemon=True).start()
        return hud, cancelled

    @staticmethod
    def _hud_finish(hud, ok):
        if hud is None:
            return
        try:
            hud.stdin.write(b"SUCCESS\n" if ok else b"FAIL\n")
            hud.stdin.flush()
            hud.stdin.close()   # EOF : le HUD joue l'anim finale puis se ferme
        except (OSError, ValueError):
            pass

    # ---- Face ID (caméra) ----
    def verify_face(self):
        hud, cancelled = self._hud_start()
        ok, reason = self._verify_face_camera(cancelled=cancelled)
        self._hud_finish(hud, ok)
        return ok, reason

    def verify_lock(self):
        # Écran verrouillé : pas de modal, visage direct, budget court.
        # Le HUD (Dynamic Island) est affiché comme sur sudo.
        hud, cancelled = self._hud_start()
        ok, reason = self._verify_face_camera(timeout=config.LOCK_TIMEOUT_S,
                                              cancelled=cancelled)
        self._hud_finish(hud, ok)
        return ok, f"[lock] {reason}"

    def _verify_face_camera(self, timeout=None, cancelled=None):
        self._maybe_reload()
        if self.enrolled is None or len(self.enrolled) == 0:
            return False, "no-enrollment"
        tmo = timeout if timeout else config.VERIFY_TIMEOUT_S

        # Backend explicite : sans lui, OpenCV essaie ses backends dans l'ordre et perd
        # du temps avant de retomber sur AVFoundation, le seul qui marche ici.
        cap = cv2.VideoCapture(config.CAMERA_INDEX, cv2.CAP_AVFOUNDATION)
        if not cap.isOpened():
            return False, "camera-unavailable"
        # 640×480 suffit largement : le visage doit faire 80 px au minimum, et une frame
        # plus petite arrive plus vite et se détecte plus vite.
        cap.set(cv2.CAP_PROP_FRAME_WIDTH, config.CAPTURE_WIDTH)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, config.CAPTURE_HEIGHT)

        _adaptive_warmup(cap)

        matches = 0
        frames = 0
        faces_seen = 0
        best_overall = -1.0
        max_bright = 0.0
        last_frame = None
        t0 = time.time()
        try:
            while (frames < config.VERIFY_MAX_FRAMES
                   and (time.time() - t0) < tmo):
                if cancelled is not None and cancelled.is_set():
                    return False, f"cancelled frames={frames}"
                ok, frame = cap.read()
                if not ok:
                    continue
                frames += 1
                last_frame = frame
                b = float(frame.mean())
                if b > max_bright:
                    max_bright = b
                feat, _ = self.engine.frame_feature(frame)
                if feat is None:
                    continue
                faces_seen += 1
                score = best_match(feat, self.enrolled)
                best_overall = max(best_overall, score)
                if score >= config.COSINE_THRESHOLD:
                    matches += 1
                    if matches >= config.VERIFY_REQUIRED_MATCHES:
                        dt = time.time() - t0
                        return True, (f"score={score:.3f} frames={frames} "
                                      f"faces={faces_seen} bright={max_bright:.0f} "
                                      f"t={dt:.1f}s")
        finally:
            cap.release()
        if faces_seen == 0 and last_frame is not None:
            try:
                cv2.imwrite(str(config.LOG_DIR / "last_frame.png"), last_frame)
            except Exception:  # noqa: BLE001
                pass
        dt = time.time() - t0
        return False, (f"best={best_overall:.3f} frames={frames} "
                       f"faces={faces_seen} bright={max_bright:.0f} t={dt:.1f}s")

    # ---- Touch ID (helper Swift) ----
    def verify_touch(self):
        if not config.TOUCHID_HELPER.exists():
            return False, "touchid-helper-absent"
        try:
            r = subprocess.run(
                [str(config.TOUCHID_HELPER),
                 config.t("engine.touchid.reason", "unlock sudo")],
                capture_output=True, text=True, timeout=60,
            )
        except (subprocess.SubprocessError, OSError) as e:
            return False, f"touchid-error:{e}"
        out = r.stdout.strip()
        return (r.returncode == 0 and out == "OK"), f"touchid={out or r.returncode}"

    # ---- orchestration ----
    def verify(self):
        method = self.choose_method()
        if method == "face":
            ok, reason = self.verify_face()
        elif method == "touch":
            ok, reason = self.verify_touch()
        else:
            return False, "user-chose-password"
        return ok, f"[{method}] {reason}"

    # ---- serveur socket ----
    def handle(self, conn):
        try:
            conn.settimeout(120)

            euid = peer_euid(conn)
            if euid is not None and euid not in (0, os.getuid()):
                log(f"connexion refusée (euid={euid})")
                conn.sendall(b"ERR forbidden\n")
                return

            data = conn.recv(64)
            if not data:
                return
            cmd = data.decode("ascii", "ignore").strip().upper()
            if cmd.startswith("PING"):
                conn.sendall(b"PONG\n")
                return
            if cmd.startswith("VERIFY_LOCK"):
                ok, reason = self.verify_lock()
                log(f"verify -> {'OK' if ok else 'FAIL'} ({reason})")
                conn.sendall(b"OK\n" if ok else b"FAIL\n")
                return
            if not cmd.startswith("VERIFY"):
                conn.sendall(b"ERR bad-command\n")
                return

            ok, reason = self.verify()
            log(f"verify -> {'OK' if ok else 'FAIL'} ({reason})")
            conn.sendall(b"OK\n" if ok else b"FAIL\n")
        except Exception as e:  # noqa: BLE001 — un daemon ne doit jamais tomber
            log(f"handle error : {e}")
            try:
                conn.sendall(b"ERR exception\n")
            except OSError:
                pass
        finally:
            conn.close()

    def serve(self):
        config.APP_DIR.mkdir(parents=True, exist_ok=True)
        config.LOG_DIR.mkdir(parents=True, exist_ok=True)
        os.chmod(config.APP_DIR, 0o700)

        if config.SOCKET_PATH.exists():
            config.SOCKET_PATH.unlink()

        srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        srv.bind(str(config.SOCKET_PATH))
        os.chmod(config.SOCKET_PATH, 0o600)
        srv.listen(4)
        log(f"daemon en écoute sur {config.SOCKET_PATH} "
            f"(modal={'on' if config.MODAL_ENABLED else 'off'})")

        while True:
            try:
                conn, _ = srv.accept()
            except KeyboardInterrupt:
                break
            self.handle(conn)


def main():
    try:
        d = Daemon()
    except Exception as e:  # noqa: BLE001
        log(f"init échouée : {e}")
        return 1
    d.serve()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

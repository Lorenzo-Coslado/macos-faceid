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


def _build_applescript():
    """Modal de choix. Icône custom (glyphe Face ID) si présente, sinon icône système."""
    if config.MODAL_ICON.exists():
        icon = f'with icon POSIX file "{config.MODAL_ICON}"'
    else:
        icon = "with icon note"
    return (
        'display dialog "Déverrouiller sudo — choisis ta méthode" '
        'with title "Authentification" '
        'buttons {"Mot de passe", "Empreinte", "Face ID"} '
        f'default button "Face ID" {icon}\n'
        'return button returned of result'
    )


# Choix proposés dans le modal. Ordre = ordre des boutons (droite = défaut).
_APPLESCRIPT = _build_applescript()


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
                    [str(config.AUTH_MODAL), "--timeout", "90"],
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
        if "Face" in choice:
            return "face"
        if "Empreinte" in choice:
            return "touch"
        return "password"

    # ---- capsule HUD (Dynamic Island) ----
    def _hud_start(self):
        if not config.HUD_ENABLED or not config.FACEID_HUD.exists():
            return None
        try:
            return subprocess.Popen([str(config.FACEID_HUD)], stdin=subprocess.PIPE)
        except OSError as e:
            log(f"hud start error : {e}")
            return None

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
        hud = self._hud_start()
        ok, reason = self._verify_face_camera()
        self._hud_finish(hud, ok)
        return ok, reason

    def verify_lock(self):
        # Écran verrouillé : pas de modal, visage direct, budget court.
        # Le HUD (Dynamic Island) est affiché comme sur sudo.
        hud = self._hud_start()
        ok, reason = self._verify_face_camera(timeout=config.LOCK_TIMEOUT_S)
        self._hud_finish(hud, ok)
        return ok, f"[lock] {reason}"

    def _verify_face_camera(self, timeout=None):
        self._maybe_reload()
        if self.enrolled is None or len(self.enrolled) == 0:
            return False, "no-enrollment"
        tmo = timeout if timeout else config.VERIFY_TIMEOUT_S

        cap = cv2.VideoCapture(config.CAMERA_INDEX)
        if not cap.isOpened():
            return False, "camera-unavailable"

        for _ in range(config.CAMERA_WARMUP_FRAMES):
            cap.read()

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
                [str(config.TOUCHID_HELPER), "Déverrouiller sudo"],
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

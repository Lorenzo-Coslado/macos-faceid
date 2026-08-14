"""Chemins et paramètres partagés par tous les composants."""
import json
import os
import subprocess
from pathlib import Path

# Chemins. En bundle autonome (Mugshot.app), l'app pose des variables d'env vers
# l'intérieur du bundle. En développement, repli sur l'arborescence du projet.
PROJECT_ROOT = Path(__file__).resolve().parent.parent


def _dir(env, default):
    v = os.environ.get(env)
    return Path(v) if v else default


HELPERS_DIR = _dir("FACEID_HELPERS_DIR", PROJECT_ROOT / "helpers")
ASSETS_DIR = _dir("FACEID_ASSETS_DIR", PROJECT_ROOT / "assets")

TOUCHID_HELPER = HELPERS_DIR / "touchid-helper"
AUTH_MODAL = HELPERS_DIR / "auth-modal"    # panneau natif AppKit
FACEID_HUD = HELPERS_DIR / "faceid-hud"    # capsule Dynamic Island

def _flag(name, default):
    """Drapeau on/off depuis l'environnement.

    `os.environ.get(name, default)` ne suffit pas : une variable présente mais vide
    (`FACEID_MODAL=`) renvoie "", qui n'est pas "0" et passait donc pour « activé ».
    """
    return (os.environ.get(name) or default) != "0"


# Capsule animée pendant le scan Face ID (scan -> checkmark). FACEID_HUD=0 désactive.
HUD_ENABLED = _flag("FACEID_HUD", "1")

# Modal de choix (Face ID / Empreinte / Mot de passe) avant l'authentification.
#
# Désactivé par défaut : l'app existe pour supprimer une friction (taper un mot de passe)
# et le panneau en rajoutait une (cliquer un bouton) à chaque `sudo`. On lance donc
# directement le scan ; la capsule HUD porte l'échappatoire (un clic dessus annule et
# rend la main au mot de passe). FACEID_MODAL=1 rétablit le panneau.
MODAL_ENABLED = _flag("FACEID_MODAL", "0")

# Icône du modal (glyphe Face ID vert, générée par scripts/make_icon.py).
MODAL_ICON = ASSETS_DIR / "faceid-icon.icns"

# ---- traductions du moteur ----
# Le moteur tourne hors bundle : pas de NSBundle, donc pas de .lproj. Ses invites
# viennent d'un JSON généré par scripts/make_i18n.py depuis la même table que l'app.
# FACEID_LANG est posé par l'app (localisation retenue par macOS) ; sans lui, on
# interroge les préférences système, et en dernier ressort on parle anglais.
I18N_PATH = _dir("FACEID_I18N", PROJECT_ROOT / "i18n") / "engine.json"


def _preferred_lang():
    forced = os.environ.get("FACEID_LANG")
    if forced:
        return forced
    try:
        out = subprocess.run(["defaults", "read", "-g", "AppleLanguages"],
                             capture_output=True, text=True, timeout=3).stdout
    except (OSError, subprocess.SubprocessError):
        return "en"
    for token in out.replace('"', " ").replace(",", " ").split():
        if token[0].isalpha():
            return token
    return "en"


def _load_translations():
    try:
        table = json.loads(I18N_PATH.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    lang = _preferred_lang()
    # "fr-CA" doit retomber sur "fr", "zh-Hans-CN" sur "zh-Hans".
    for candidate in (lang, lang.rsplit("-", 1)[0], lang.split("-")[0], "en"):
        if candidate in table:
            return table[candidate]
    return {}


_TR = _load_translations()


def t(key, fallback=""):
    """Texte localisé pour le moteur. `fallback` si la clé manque."""
    return _TR.get(key) or fallback

# Données runtime (embeddings, socket, logs) : toujours propres à l'utilisateur.
APP_DIR = Path(os.path.expanduser("~/Library/Application Support/faceid"))
EMBEDDINGS_PATH = APP_DIR / "embeddings.npy"
SOCKET_PATH = APP_DIR / "faceid.sock"
LOG_DIR = APP_DIR / "logs"

# Modèles : embarqués dans le bundle (FACEID_MODELS_DIR) sinon Application Support.
MODELS_DIR = _dir("FACEID_MODELS_DIR", APP_DIR / "models")
YUNET_PATH = MODELS_DIR / "face_detection_yunet_2023mar.onnx"
SFACE_PATH = MODELS_DIR / "face_recognition_sface_2021dec.onnx"

# Seuil de similarité cosinus pour SFace.
# Référence OpenCV Zoo : 0.363. On reste proche pour rester utilisable.
# Plus haut = plus strict (moins de faux positifs, plus de faux négatifs).
COSINE_THRESHOLD = float(os.environ.get("FACEID_THRESHOLD", "0.36"))

# Plafond de frames jetées quand la caméra vient de s'ouvrir (auto-exposition). Le
# warmup s'arrête avant si la luminosité s'est stabilisée — cf. _adaptive_warmup.
CAMERA_WARMUP_FRAMES = int(os.environ.get("FACEID_WARMUP", "8"))
# Écart de luminosité moyenne en dessous duquel on considère l'exposition stabilisée.
WARMUP_STABLE_DELTA = float(os.environ.get("FACEID_WARMUP_DELTA", "1.5"))

# Résolution demandée à la caméra. Le visage doit faire au moins MIN_FACE_SIZE pixels ;
# au-delà de 640×480 on paie de la latence pour une précision qu'on n'exploite pas.
CAPTURE_WIDTH = int(os.environ.get("FACEID_CAPTURE_WIDTH", "640"))
CAPTURE_HEIGHT = int(os.environ.get("FACEID_CAPTURE_HEIGHT", "480"))

# Confiance minimale du DÉTECTEUR de visage (YuNet). La sécurité repose sur le
# seuil de reconnaissance (cosinus), pas ici : une fausse détection ne matchera
# pas les embeddings. 0.9 rate des visages en contre-jour.
DETECT_CONFIDENCE = float(os.environ.get("FACEID_DETECT_CONF", "0.7"))

# Nombre d'échantillons collectés à l'enrôlement.
ENROLL_SAMPLES = int(os.environ.get("FACEID_ENROLL_SAMPLES", "12"))

# Vérification : combien de frames indépendantes doivent matcher, et budget temps.
# Le TEMPS est la vraie limite ; le plafond de frames n'est qu'un garde-fou haut
# (une caméra ouverte à froid met ~1,5-2 s avant de fournir un visage exploitable).
VERIFY_REQUIRED_MATCHES = int(os.environ.get("FACEID_REQUIRED_MATCHES", "2"))
VERIFY_MAX_FRAMES = int(os.environ.get("FACEID_MAX_FRAMES", "300"))
VERIFY_TIMEOUT_S = float(os.environ.get("FACEID_TIMEOUT", "8.0"))
# Écran verrouillé : budget plus court (< timeout du module PAM = 6 s) pour
# basculer vite sur le mot de passe si besoin.
LOCK_TIMEOUT_S = float(os.environ.get("FACEID_LOCK_TIMEOUT", "5.0"))

# Taille minimale (px) du visage détecté pour être exploitable.
MIN_FACE_SIZE = int(os.environ.get("FACEID_MIN_FACE", "80"))

def _resolve_camera_index():
    """Index de la caméra à ouvrir.

    macOS expose l'iPhone appairé comme caméra (Continuity Camera) et le place parfois
    en premier : déverrouiller sudo réveillerait le téléphone au lieu d'utiliser la
    webcam. On préfère donc explicitement la caméra intégrée. `FACEID_CAMERA` force un
    index précis et court-circuite cette détection.
    """
    forced = os.environ.get("FACEID_CAMERA")
    if forced is not None:
        return int(forced)

    lister = HELPERS_DIR / "camera-list"
    if not lister.exists():
        return 0
    try:
        out = subprocess.run([str(lister)], capture_output=True, text=True, timeout=5).stdout
    except (OSError, subprocess.SubprocessError):
        return 0

    cameras = []
    for line in out.splitlines():
        parts = line.split("\t")
        if len(parts) >= 2 and parts[0].isdigit():
            cameras.append((int(parts[0]), parts[1]))
    for index, kind in cameras:
        if kind == "builtin":
            return index
    for index, kind in cameras:      # pas de caméra intégrée : un moniteur externe fera l'affaire
        if kind != "continuity":
            return index
    return cameras[0][0] if cameras else 0


CAMERA_INDEX = _resolve_camera_index()

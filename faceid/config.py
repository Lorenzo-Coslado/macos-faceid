"""Chemins et paramètres partagés par tous les composants."""
import os
from pathlib import Path

# Racine du projet (contient helpers/, pam/, faceid/).
PROJECT_ROOT = Path(__file__).resolve().parent.parent
TOUCHID_HELPER = PROJECT_ROOT / "helpers" / "touchid-helper"
AUTH_MODAL = PROJECT_ROOT / "helpers" / "auth-modal"    # panneau natif AppKit
FACEID_HUD = PROJECT_ROOT / "helpers" / "faceid-hud"    # capsule Dynamic Island

# Capsule animée pendant le scan Face ID (scan -> checkmark). FACEID_HUD=0 désactive.
HUD_ENABLED = os.environ.get("FACEID_HUD", "1") != "0"

# Modal de choix (Face ID / Empreinte / Mot de passe) avant l'authentification.
# Mettre FACEID_MODAL=0 pour aller directement au Face ID (ancien comportement).
MODAL_ENABLED = os.environ.get("FACEID_MODAL", "1") != "0"

# Icône du modal (glyphe Face ID vert, générée par scripts/make_icon.py).
MODAL_ICON = PROJECT_ROOT / "assets" / "faceid-icon.icns"



# Répertoire de données runtime (modèles, embeddings, socket, logs).
APP_DIR = Path(os.path.expanduser("~/Library/Application Support/faceid"))
MODELS_DIR = APP_DIR / "models"
EMBEDDINGS_PATH = APP_DIR / "embeddings.npy"
SOCKET_PATH = APP_DIR / "faceid.sock"
LOG_DIR = APP_DIR / "logs"

YUNET_PATH = MODELS_DIR / "face_detection_yunet_2023mar.onnx"
SFACE_PATH = MODELS_DIR / "face_recognition_sface_2021dec.onnx"

# Seuil de similarité cosinus pour SFace.
# Référence OpenCV Zoo : 0.363. On reste proche pour rester utilisable.
# Plus haut = plus strict (moins de faux positifs, plus de faux négatifs).
COSINE_THRESHOLD = float(os.environ.get("FACEID_THRESHOLD", "0.36"))

# Frames de warmup à jeter quand la caméra vient de s'ouvrir (auto-exposition).
CAMERA_WARMUP_FRAMES = int(os.environ.get("FACEID_WARMUP", "8"))

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

CAMERA_INDEX = int(os.environ.get("FACEID_CAMERA", "0"))

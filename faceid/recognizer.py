"""Moteur de reconnaissance faciale : détection (YuNet) + embeddings (SFace)."""
import numpy as np
import cv2

from . import config


class FaceEngine:
    def __init__(self):
        if not config.YUNET_PATH.exists():
            raise FileNotFoundError(f"Modèle YuNet manquant : {config.YUNET_PATH}")
        if not config.SFACE_PATH.exists():
            raise FileNotFoundError(f"Modèle SFace manquant : {config.SFACE_PATH}")
        # La taille d'entrée est réajustée par frame via setInputSize().
        self.detector = cv2.FaceDetectorYN.create(
            str(config.YUNET_PATH), "", (320, 320),
            score_threshold=config.DETECT_CONFIDENCE, nms_threshold=0.3, top_k=5000,
        )
        self.recognizer = cv2.FaceRecognizerSF.create(str(config.SFACE_PATH), "")

    def detect(self, img):
        h, w = img.shape[:2]
        self.detector.setInputSize((w, h))
        _, faces = self.detector.detect(img)
        if faces is None:
            return np.empty((0, 15), dtype=np.float32)
        return faces

    @staticmethod
    def largest_face(faces):
        if faces is None or len(faces) == 0:
            return None
        # colonnes 2,3 = largeur, hauteur du bbox
        areas = faces[:, 2] * faces[:, 3]
        return faces[int(np.argmax(areas))]

    def feature(self, img, face):
        aligned = self.recognizer.alignCrop(img, face)
        return self.recognizer.feature(aligned).flatten().astype(np.float32)

    def frame_feature(self, img, min_size=None):
        """Retourne (embedding, face) pour le plus grand visage exploitable."""
        if min_size is None:
            min_size = config.MIN_FACE_SIZE
        faces = self.detect(img)
        face = self.largest_face(faces)
        if face is None:
            return None, None
        w, h = float(face[2]), float(face[3])
        if min(w, h) < min_size:
            return None, face
        return self.feature(img, face), face

    @staticmethod
    def cosine(a, b):
        a = np.asarray(a, dtype=np.float32).flatten()
        b = np.asarray(b, dtype=np.float32).flatten()
        denom = (np.linalg.norm(a) * np.linalg.norm(b)) + 1e-9
        return float(np.dot(a, b) / denom)


def load_embeddings():
    if not config.EMBEDDINGS_PATH.exists():
        return None
    arr = np.load(config.EMBEDDINGS_PATH)
    if arr.ndim == 1:
        arr = arr.reshape(1, -1)
    return arr.astype(np.float32)


def save_embeddings(arr):
    config.APP_DIR.mkdir(parents=True, exist_ok=True)
    np.save(config.EMBEDDINGS_PATH, np.asarray(arr, dtype=np.float32))


def best_match(feat, enrolled):
    """Meilleure similarité cosinus entre `feat` et les vecteurs enrôlés."""
    best = -1.0
    for e in enrolled:
        s = FaceEngine.cosine(feat, e)
        if s > best:
            best = s
    return best

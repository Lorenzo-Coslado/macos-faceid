#!/usr/bin/env bash
# Télécharge les modèles ONNX (YuNet + SFace) depuis OpenCV Zoo.
set -euo pipefail

DEST="${HOME}/Library/Application Support/faceid/models"
mkdir -p "$DEST"

BASE="https://github.com/opencv/opencv_zoo/raw/main/models"
YUNET="${BASE}/face_detection_yunet/face_detection_yunet_2023mar.onnx"
SFACE="${BASE}/face_recognition_sface/face_recognition_sface_2021dec.onnx"

echo "Téléchargement YuNet (détection)..."
curl -fL "$YUNET" -o "$DEST/face_detection_yunet_2023mar.onnx"

echo "Téléchargement SFace (embeddings)..."
curl -fL "$SFACE" -o "$DEST/face_recognition_sface_2021dec.onnx"

echo "Modèles enregistrés dans : $DEST"
ls -la "$DEST"

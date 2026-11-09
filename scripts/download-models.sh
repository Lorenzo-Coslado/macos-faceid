#!/usr/bin/env bash
# Télécharge les modèles ONNX (YuNet + SFace) depuis OpenCV Zoo, et vérifie qu'ils
# sont bien ceux sur lesquels le moteur est calibré.
#
# La vérification n'est pas une précaution de principe. Les fichiers sont tirés de la
# branche `main` du zoo : rien n'empêche leur contenu de changer sous le même nom. Or
# COSINE_THRESHOLD est calibré pour CE modèle SFace, et les `embeddings.npy` déjà
# enrôlés en viennent — un modèle différent, et le seuil ne veut plus rien dire,
# silencieusement, sur ce qui garde `sudo`.
set -euo pipefail

DEST="${FACEID_MODELS_DIR:-${HOME}/Library/Application Support/faceid/models}"
mkdir -p "$DEST"

BASE="https://github.com/opencv/opencv_zoo/raw/main/models"

# nom:sous-dossier du zoo:sha256
MODELS=(
  "face_detection_yunet_2023mar.onnx:face_detection_yunet:8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4"
  "face_recognition_sface_2021dec.onnx:face_recognition_sface:0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79"
)

for entry in "${MODELS[@]}"; do
  IFS=":" read -r name dir want <<< "$entry"
  echo "Téléchargement ${name}..."
  curl -fL "${BASE}/${dir}/${name}" -o "$DEST/$name"
  got="$(shasum -a 256 "$DEST/$name" | awk '{print $1}')"
  if [ "$got" != "$want" ]; then
    echo "empreinte inattendue pour ${name}" >&2
    echo "  attendu : $want" >&2
    echo "  obtenu  : $got" >&2
    echo "Le modèle a changé en amont. Revérifier le seuil de reconnaissance et les" >&2
    echo "enrôlements existants avant d'accepter cette version." >&2
    rm -f "$DEST/$name"
    exit 1
  fi
done

echo "Modèles vérifiés et enregistrés dans : $DEST"
ls -la "$DEST"

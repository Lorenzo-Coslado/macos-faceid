#!/usr/bin/env bash
# Prépare l'environnement : venv, dépendances, modèles, selftest.
# N'exige AUCUN sudo. Ne touche pas à la config système.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE"

PY="${FACEID_PYTHON:-python3.12}"
if ! command -v "$PY" >/dev/null 2>&1; then
  echo "Python introuvable : $PY (surcharge via FACEID_PYTHON=...)" >&2
  exit 1
fi

echo "== Création du venv (.venv) avec $PY =="
"$PY" -m venv .venv
./.venv/bin/pip install --upgrade pip wheel >/dev/null

echo "== Installation des dépendances =="
./.venv/bin/pip install -r requirements.txt

echo "== Téléchargement des modèles =="
bash scripts/download-models.sh

echo "== Compilation des helpers natifs (Touch ID) =="
bash scripts/build-helpers.sh

echo "== Préparation des répertoires runtime =="
mkdir -p "${HOME}/Library/Application Support/faceid/logs"

echo "== Selftest (sans caméra) =="
./.venv/bin/python -m faceid.selftest

echo
echo "Setup terminé."
echo "Étape suivante : ./.venv/bin/python -m faceid.enroll  (enrôle ton visage)"

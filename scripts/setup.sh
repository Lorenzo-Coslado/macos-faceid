#!/usr/bin/env bash
# Prépare l'environnement : venv, dépendances, modèles, selftest.
# N'exige AUCUN sudo. Ne touche pas à la config système.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE"

# Prefer the python.org framework. Homebrew builds Python against the running OS, so a
# release frozen with it refuses to launch on anything older (see scripts/setup-python.sh).
ORG_PY="/Library/Frameworks/Python.framework/Versions/3.12/bin/python3.12"
PY="${FACEID_PYTHON:-}"
if [ -z "$PY" ]; then
  if [ -x "$ORG_PY" ]; then
    PY="$ORG_PY"
  else
    PY="python3.12"
    echo "Note: python.org framework not found; using $PY." >&2
    echo "      Fine for development, but releases built this way only run on this macOS" >&2
    echo "      version or newer. Run scripts/setup-python.sh before building a release." >&2
  fi
fi
if ! command -v "$PY" >/dev/null 2>&1 && [ ! -x "$PY" ]; then
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

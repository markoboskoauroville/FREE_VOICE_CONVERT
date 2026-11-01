#!/bin/bash
# setup.sh: installs everything the engine needs into the data folder (macOS, Apple Silicon).
# The app runs this at first start; every line starting with @ is progress JSON for the window.
#   uv (Astral) -> Python 3.11 -> torch + the packages -> Seed-VC's code (pinned commit) -> every model.
set -euo pipefail
ENGINE="$(cd "$(dirname "$0")" && pwd)"
source "$ENGINE/PINS"
FVC_HOME="${FVC_HOME:-$HOME/Library/Application Support/FreeVoiceConvert}"
export FVC_HOME
mkdir -p "$FVC_HOME"
cd "$FVC_HOME"
p() { echo "@{\"pct\": $1, \"msg\": \"$2\"}"; }
[ "$(uname -m)" = "arm64" ] || { echo '@{"error": "Free Voice Convert needs a Mac with Apple Silicon (M1 or newer)."}'; exit 1; }

if [ ! -x bin/uv ]; then
  p 2 "downloading uv (the Python installer)"
  mkdir -p bin
  curl -fsSL "https://github.com/astral-sh/uv/releases/download/$UV_VERSION/uv-aarch64-apple-darwin.tar.gz" | tar -xz -C bin --strip-components 1
fi
export UV_PYTHON_INSTALL_DIR="$FVC_HOME/python" UV_CACHE_DIR="$FVC_HOME/uv-cache"
if [ ! -x venv/bin/python ]; then
  p 6 "installing Python $PYTHON"
  bin/uv venv -q --python "$PYTHON" --python-preference only-managed venv
fi
p 12 "installing torch $TORCH"
bin/uv pip install -q --python venv/bin/python "torch==$TORCH" "torchaudio==$TORCH"
p 30 "installing the audio packages"
bin/uv pip install -q --python venv/bin/python -r "$ENGINE/requirements.txt"
if [ ! -f "seed-vc/.commit" ] || [ "$(cat seed-vc/.commit)" != "$SEEDVC_COMMIT" ]; then
  p 40 "downloading Seed-VC"
  rm -rf seed-vc seed-vc-*
  curl -fsSL "https://github.com/Plachtaa/seed-vc/archive/$SEEDVC_COMMIT.tar.gz" | tar -xz --exclude='*/examples' --exclude='*/assets' --exclude='*/campplus_cn_common.bin'
  mv "seed-vc-$SEEDVC_COMMIT" seed-vc && echo "$SEEDVC_COMMIT" > seed-vc/.commit
fi
p 45 "downloading the models (about 2.5 GB)"
venv/bin/python "$ENGINE/fvc.py" fetch

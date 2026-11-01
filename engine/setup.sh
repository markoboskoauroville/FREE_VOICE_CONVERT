#!/bin/bash
# setup.sh: installs everything the engine needs into the data folder (macOS, Apple Silicon).
# The app runs this at every start until everything is here; every line starting with @ is progress JSON.
# Every step resumes: curl -C - for the files, uv's cache for the packages, Hugging Face's .incomplete files for the
# models. Closing the app halfway costs nothing; the next start continues where it stopped.
#   uv (Astral) -> Python 3.11 -> torch + the packages -> Seed-VC's code (pinned commit) -> every model.
set -euo pipefail
ENGINE="$(cd "$(dirname "$0")" && pwd)"
source "$ENGINE/PINS"
FVC_HOME="${FVC_HOME:-$HOME/Library/Application Support/FreeVoiceConvert}"
export FVC_HOME
mkdir -p "$FVC_HOME"
cd "$FVC_HOME"
p() { echo "@{\"pct\": $1, \"msg\": \"$2\"}"; }
# fetch <file> <url>: continues a broken download from its last byte; a server that cannot continue gets a fresh one
fetch() {
  [ -f "$1.done" ] && [ -f "$1" ] && return 0   # finished before: never fetched twice
  curl -fL --retry 10 --retry-delay 3 -C - -o "$1" "$2" || { rm -f "$1"; curl -fL --retry 10 --retry-delay 3 -o "$1" "$2"; } && touch "$1.done"
}
[ "$(uname -m)" = "arm64" ] || { echo '@{"error": "Free Voice Convert needs a Mac with Apple Silicon (M1 or newer)."}'; exit 1; }

if [ ! -x bin/uv ]; then
  p 2 "downloading uv (the Python installer)"
  mkdir -p bin
  fetch uv.tar.gz "https://github.com/astral-sh/uv/releases/download/$UV_VERSION/uv-aarch64-apple-darwin.tar.gz"
  tar -xzf uv.tar.gz -C bin --strip-components 1 && rm -f uv.tar.gz uv.tar.gz.done
fi
export UV_PYTHON_INSTALL_DIR="$FVC_HOME/python" UV_CACHE_DIR="$FVC_HOME/uv-cache"
if [ ! -x venv/bin/python ]; then
  p 6 "installing Python $PYTHON"
  bin/uv venv -q --python "$PYTHON" --python-preference only-managed venv
fi
if venv/bin/python -c "import torch,torchaudio,sys; sys.exit(torch.__version__.split('+')[0] != '$TORCH')" 2>/dev/null; then
  p 20 "torch $TORCH is here"
else
p 12 "downloading torch $TORCH"
# the two big wheels by curl, so a broken download continues; uv then installs them (and their small helpers)
mkdir -p wheels
W=https://download.pytorch.org/whl/cpu
T1="torch-$TORCH-cp311-none-macosx_11_0_arm64.whl"; T2="torchaudio-$TORCH-cp311-cp311-macosx_11_0_arm64.whl"
fetch "wheels/$T1" "$W/$T1"; fetch "wheels/$T2" "$W/$T2"
p 20 "installing torch $TORCH"
bin/uv pip install -q --python venv/bin/python "wheels/$T1" "wheels/$T2" && rm -rf wheels
fi
p 30 "installing the audio packages"
bin/uv pip install -q --python venv/bin/python -r "$ENGINE/requirements.txt"
if [ ! -f "seed-vc/.commit" ] || [ "$(cat seed-vc/.commit)" != "$SEEDVC_COMMIT" ]; then
  p 40 "downloading Seed-VC"
  rm -rf seed-vc "seed-vc-$SEEDVC_COMMIT"
  # to a file with -C -: a broken download continues from its last byte at the next start
  fetch "seedvc-$SEEDVC_COMMIT.tar.gz" "https://github.com/Plachtaa/seed-vc/archive/$SEEDVC_COMMIT.tar.gz"
  tar -xzf "seedvc-$SEEDVC_COMMIT.tar.gz" --exclude='*/examples' --exclude='*/assets' --exclude='*/campplus_cn_common.bin'
  mv "seed-vc-$SEEDVC_COMMIT" seed-vc && echo "$SEEDVC_COMMIT" > seed-vc/.commit && rm -f "seedvc-$SEEDVC_COMMIT.tar.gz" "seedvc-$SEEDVC_COMMIT.tar.gz.done"
fi
p 45 "downloading the models (about 2.5 GB)"
venv/bin/python "$ENGINE/fvc.py" fetch

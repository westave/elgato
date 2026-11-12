#!/bin/bash
# Development/CI only. The resulting app needs no Python installation.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"
BUILD_PYTHON="${BUILD_PYTHON:-python3}"
TARGET_ARCH="${TARGET_ARCH:-$(uname -m)}"
ENV_DIR="$SCRIPT_DIR/.build/homekit-venv"

if [[ ! -x "$ENV_DIR/bin/python" ]]; then
    "$BUILD_PYTHON" -m venv "$ENV_DIR"
fi
# Compile orjson for the deployment target; prebuilt wheels may require a newer macOS.
MACOSX_DEPLOYMENT_TARGET=13.0 "$ENV_DIR/bin/python" -m pip install --quiet --no-binary=orjson -r requirements-build.txt
MACOSX_DEPLOYMENT_TARGET=13.0 "$ENV_DIR/bin/python" -m PyInstaller \
    --noconfirm --clean --onefile --name ElgatoHomeKitBridge \
    --target-arch "$TARGET_ARCH" --python-option u \
    --collect-all pyhap --collect-submodules zeroconf \
    --distpath .build/homekit-dist --workpath .build/homekit-work \
    --specpath .build/homekit-spec \
    elgato_homekit_bridge.py

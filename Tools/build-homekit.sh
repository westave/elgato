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
# Source builds of cryptography (e.g. Intel) must not share Python's libssl filename.
OPENSSL_STATIC=1 MACOSX_DEPLOYMENT_TARGET=13.0 "$ENV_DIR/bin/python" -m pip install --quiet --no-binary=orjson -r requirements-build.txt
"$ENV_DIR/bin/python" - <<'PY'
import subprocess
from cryptography.hazmat.bindings import _rust

dependencies = subprocess.check_output(["otool", "-L", _rust.__file__], text=True)
if "libssl." in dependencies or "libcrypto." in dependencies:
    raise SystemExit("cryptography must use static OpenSSL. Recreate .build/homekit-venv and rebuild.")
PY
MACOSX_DEPLOYMENT_TARGET=13.0 "$ENV_DIR/bin/python" -m PyInstaller \
    --noconfirm --clean --onefile --name ElgatoHomeKitBridge \
    --target-arch "$TARGET_ARCH" --python-option u \
    --collect-all pyhap --collect-submodules zeroconf \
    --distpath .build/homekit-dist --workpath .build/homekit-work \
    --specpath .build/homekit-spec \
    elgato_homekit_bridge.py

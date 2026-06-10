#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
PYTHON_DIR="$REPO_ROOT/python"
PYTHON_VERSION="${PYTHON_VERSION:-3.12}"
LEGACY_BIN_DIR="$PYTHON_DIR/lib/bin"

if ! command -v uv >/dev/null 2>&1; then
    echo "uv is required. Install it from https://docs.astral.sh/uv/ and rerun this script." >&2
    exit 1
fi

cd "$PYTHON_DIR"

rm -rf "$PYTHON_DIR/lib"
rm -rf "$PYTHON_DIR/.venv"

uv python install "$PYTHON_VERSION"
MANAGED_PYTHON=$(uv python find --managed-python "$PYTHON_VERSION")
MANAGED_ROOT=$(CDPATH= cd -- "$(dirname "$MANAGED_PYTHON")/.." && pwd)

mkdir -p "$PYTHON_DIR/lib"
cp -R "$MANAGED_ROOT"/. "$PYTHON_DIR/lib"
rm -f "$LEGACY_BIN_DIR/python" "$LEGACY_BIN_DIR/python3" "$LEGACY_BIN_DIR/python3.12"
cp "$MANAGED_PYTHON" "$LEGACY_BIN_DIR/python3.12"
ln -sfn python3.12 "$LEGACY_BIN_DIR/python"
ln -sfn python3.12 "$LEGACY_BIN_DIR/python3"

"$LEGACY_BIN_DIR/python3.12" -m venv .venv
VIRTUAL_ENV="$PYTHON_DIR/.venv" uv sync --locked --active --link-mode copy

echo "Python sidecar bootstrapped in $PYTHON_DIR"
echo "Bundled interpreter: $PYTHON_DIR/lib/bin/python"
echo "Dependency environment: $PYTHON_DIR/.venv"

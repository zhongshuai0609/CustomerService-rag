#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON_BIN="${PYTHON_BIN:-python3}"
PYTHON_VERSION="${PYTHON_VERSION:-3.12}"
LAMBDA_PLATFORM="${LAMBDA_PLATFORM:-manylinux2014_x86_64}"
PACKAGE_DIR="${PACKAGE_DIR:-$ROOT_DIR/package}"
ZIP_FILE="${ZIP_FILE:-$ROOT_DIR/function.zip}"

if [[ "$PACKAGE_DIR" != /* ]]; then
  PACKAGE_DIR="$ROOT_DIR/$PACKAGE_DIR"
fi

if [[ "$ZIP_FILE" != /* ]]; then
  ZIP_FILE="$ROOT_DIR/$ZIP_FILE"
fi

echo "Cleaning old build output..."
rm -rf "$PACKAGE_DIR" "$ZIP_FILE"
mkdir -p "$PACKAGE_DIR"

echo "Installing dependencies for AWS Lambda..."
"$PYTHON_BIN" -m pip install \
  --platform "$LAMBDA_PLATFORM" \
  --implementation cp \
  --python-version "$PYTHON_VERSION" \
  --only-binary=:all: \
  -r "$ROOT_DIR/requirements.txt" \
  -t "$PACKAGE_DIR"

echo "Copying Lambda source files..."
cp "$ROOT_DIR"/*.py "$PACKAGE_DIR"/

echo "Creating zip package..."
(
  cd "$PACKAGE_DIR"
  zip -qr "$ZIP_FILE" .
)

echo "Build complete: $ZIP_FILE"

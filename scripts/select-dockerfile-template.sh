#!/usr/bin/env sh
set -eu

if [ "${1:-}" = "" ]; then
  echo "Usage: $0 <template-dir>"
  exit 1
fi

TEMPLATE_DIR="$1"

if [ ! -d "$TEMPLATE_DIR" ]; then
  echo "ERROR: template directory not found: $TEMPLATE_DIR"
  exit 1
fi

if grep -q '"@nitrostack/cli"' package.json 2>/dev/null; then
  TEMPLATE_FILE="$TEMPLATE_DIR/Dockerfile.nitro-v2"
  TEMPLATE_NAME="NitroStack v2"
elif grep -q '"nitrostack"' package.json 2>/dev/null || [ -f "src/widgets/package.json" ]; then
  TEMPLATE_FILE="$TEMPLATE_DIR/Dockerfile.nitro-legacy"
  TEMPLATE_NAME="NitroStack legacy"
else
  TEMPLATE_FILE="$TEMPLATE_DIR/Dockerfile.node"
  TEMPLATE_NAME="Standard Node.js"
fi

if [ ! -f "$TEMPLATE_FILE" ]; then
  echo "ERROR: template file not found: $TEMPLATE_FILE"
  exit 1
fi

echo "Selected Dockerfile template: $TEMPLATE_NAME"
cp "$TEMPLATE_FILE" Dockerfile

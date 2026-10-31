#!/usr/bin/env bash
# Run the vendored lazy.nvim tests against a lazy.nvim checkout.
# Usage: LAZY_DIR=/tmp/lazy.nvim tests/vendor/lazy.nvim/run.sh
set -euo pipefail

VENDOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAZY_DIR="${LAZY_DIR:-/tmp/lazy.nvim}"

if [ ! -d "$LAZY_DIR" ]; then
  echo "error: lazy.nvim checkout not found: $LAZY_DIR" >&2
  echo "  clone it first: git clone --depth 1 https://github.com/folke/lazy.nvim $LAZY_DIR" >&2
  exit 1
fi

if [ ! -f "$LAZY_DIR/lua/lazy/minit.lua" ]; then
  echo "error: $LAZY_DIR does not look like a lazy.nvim checkout" >&2
  exit 1
fi

# minit.lua prepends "." to 'runtimepath' and stores its test state in
# .tests/ relative to the cwd, so run from the lazy.nvim checkout.
cd "$LAZY_DIR"

exec nvim -l "$VENDOR_DIR/tests/minit.lua" --minitest \
  "$VENDOR_DIR/tests/manage/semver_spec.lua" \
  "$VENDOR_DIR/tests/handlers/keys_spec.lua" \
  "$VENDOR_DIR/tests/core/plugin_spec.lua"

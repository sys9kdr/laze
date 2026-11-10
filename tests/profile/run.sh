#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAZE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

nvim \
  --cmd "set rtp+=${LAZE_DIR}" \
  -u "${SCRIPT_DIR}/init.lua" \
  "$@"

#!/bin/bash
# Cloud sessions only: install shellcheck so `shellcheck scripts/*.sh` works as CLAUDE.md asks.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

if ! command -v shellcheck >/dev/null 2>&1; then
  pip install --quiet shellcheck-py
fi

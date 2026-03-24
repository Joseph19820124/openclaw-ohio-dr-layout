#!/usr/bin/env bash
set -euo pipefail

export OPENCLAW_STATE_DIR=/mnt/openclaw/state
export OPENCLAW_AUTH_DIR=/mnt/openclaw/auth
exec /mnt/openclaw/bin/openclaw --config /mnt/openclaw/config/config.yaml

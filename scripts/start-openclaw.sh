#!/usr/bin/env bash
set -euo pipefail

export OPENCLAW_STATE_DIR=/mnt/openclaw/state
export OPENCLAW_AUTH_DIR=/mnt/openclaw/auth
export OPENCLAW_CONFIG_PATH=/mnt/openclaw/config/config.json5
exec /mnt/openclaw/bin/openclaw gateway run --allow-unconfigured

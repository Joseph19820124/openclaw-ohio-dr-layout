#!/usr/bin/env bash
set -euo pipefail

export OPENCLAW_STATE_DIR=/mnt/openclaw/state
export OPENCLAW_AUTH_DIR=/mnt/openclaw/auth
export OPENCLAW_CONFIG_PATH=/mnt/openclaw/config/config.json5
mkdir -p /mnt/openclaw/logs/runtime
mkdir -p /tmp/openclaw
chmod 0700 /mnt/openclaw/logs/runtime /tmp/openclaw
if ! mountpoint -q /tmp/openclaw; then
  mount --bind /mnt/openclaw/logs/runtime /tmp/openclaw
fi
exec /mnt/openclaw/bin/openclaw gateway run --allow-unconfigured

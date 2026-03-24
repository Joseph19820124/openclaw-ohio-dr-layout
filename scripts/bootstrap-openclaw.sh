#!/usr/bin/env bash
set -euo pipefail

MOUNT_POINT="/mnt/openclaw"
if ! mountpoint -q "$MOUNT_POINT"; then
  mount "$MOUNT_POINT"
fi

if [ ! -x "${MOUNT_POINT}/bin/openclaw" ]; then
  echo "OpenClaw binary not found under ${MOUNT_POINT}/bin"
  exit 1
fi

systemctl daemon-reload
systemctl enable openclaw
systemctl restart openclaw
systemctl status openclaw --no-pager || true

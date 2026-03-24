#!/usr/bin/env bash
set -euo pipefail

mkdir -p /mnt/openclaw/bin /mnt/openclaw/config /mnt/openclaw/state /mnt/openclaw/cache /mnt/openclaw/logs /mnt/openclaw/auth /mnt/openclaw/app /mnt/openclaw/releases /opt/openclaw-base
mountpoint -q /mnt/openclaw || mount LABEL=OPENCLAW_DATA /mnt/openclaw

npm install -g openclaw@2026.3.23-2 --prefix /mnt/openclaw/app
ln -sfn /mnt/openclaw/app/bin/openclaw /mnt/openclaw/bin/openclaw

cat > /mnt/openclaw/bin/start-openclaw.sh <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
export OPENCLAW_STATE_DIR=/mnt/openclaw/state
export OPENCLAW_AUTH_DIR=/mnt/openclaw/auth
exec /mnt/openclaw/bin/openclaw --config /mnt/openclaw/config/config.yaml
EOS
chmod 0755 /mnt/openclaw/bin/start-openclaw.sh

cat > /opt/openclaw-base/bootstrap-openclaw.sh <<'EOS'
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
EOS
chmod 0755 /opt/openclaw-base/bootstrap-openclaw.sh

if ! grep -q '^LABEL=OPENCLAW_DATA /mnt/openclaw ' /etc/fstab; then
  echo 'LABEL=OPENCLAW_DATA /mnt/openclaw ext4 defaults,nofail 0 2' >> /etc/fstab
fi

if [ ! -f /mnt/openclaw/config/config.yaml ]; then
  cat > /mnt/openclaw/config/config.yaml <<'EOS'
# Populate this file before starting OpenClaw.
# The install intentionally stops before onboarding/runtime startup.
EOS
fi

cat > /etc/systemd/system/openclaw.service <<'EOS'
[Unit]
Description=OpenClaw
After=network-online.target mnt-openclaw.mount
Wants=network-online.target
RequiresMountsFor=/mnt/openclaw

[Service]
Type=simple
User=root
WorkingDirectory=/mnt/openclaw
Environment=OPENCLAW_STATE_DIR=/mnt/openclaw/state
Environment=OPENCLAW_AUTH_DIR=/mnt/openclaw/auth
ExecStart=/bin/bash /mnt/openclaw/bin/start-openclaw.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOS

systemctl daemon-reload
systemctl disable openclaw || true
systemctl stop openclaw || true

#!/usr/bin/env bash
set -euo pipefail

# Generate host keys if missing (first boot).
ssh-keygen -A >/dev/null 2>&1 || true

# Ensure permissions for authorized_keys (mounted by compose).
mkdir -p /root/.ssh
chmod 700 /root/.ssh
if [[ -f /root/.ssh/authorized_keys ]]; then
  chmod 600 /root/.ssh/authorized_keys
fi

exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf


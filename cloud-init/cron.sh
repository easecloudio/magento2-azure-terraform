#!/bin/bash
set -euo pipefail

BRAND="${brand}"
PROJECT="${project}"
ENVIRONMENT="${environment}"
LOCATION="${location}"

hostnamectl set-hostname "cron.$${BRAND}.internal"
echo "127.0.0.1 cron.$${BRAND}.internal" >> /etc/hosts

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl jq unzip python3-pip python3-venv

curl -sL https://aka.ms/InstallAzureCLIDeb | bash

pip3 install pipx --quiet
pipx install ansible-core
pipx ensurepath

cat > /etc/systemd/system/magento-cron.service <<'UNIT'
[Unit]
Description=Magento 2 Cron
After=network.target

[Service]
Type=oneshot
User=www-data
WorkingDirectory=/var/www/html
ExecStart=/usr/bin/php bin/magento cron:run
StandardOutput=journal
StandardError=journal
UNIT

cat > /etc/systemd/system/magento-cron.timer <<'UNIT'
[Unit]
Description=Run Magento 2 cron every minute

[Timer]
OnBootSec=5min
OnUnitActiveSec=1min
Unit=magento-cron.service

[Install]
WantedBy=timers.target
UNIT

systemctl daemon-reload
systemctl enable magento-cron.timer

echo "Cron instance initialized: $PROJECT/$ENVIRONMENT" >> /var/log/cloud-init-custom.log

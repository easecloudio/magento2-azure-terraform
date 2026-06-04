#!/bin/bash
set -euo pipefail

BRAND="${brand}"
PROJECT="${project}"
ENVIRONMENT="${environment}"
LOCATION="${location}"

hostnamectl set-hostname "admin.$${BRAND}.internal"
echo "127.0.0.1 admin.$${BRAND}.internal" >> /etc/hosts

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl jq unzip python3-pip python3-venv

curl -sL https://aka.ms/InstallAzureCLIDeb | bash

pip3 install pipx --quiet
pipx install ansible-core
pipx ensurepath

echo "Admin instance initialized: $PROJECT/$ENVIRONMENT" >> /var/log/cloud-init-custom.log

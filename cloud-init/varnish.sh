#!/bin/bash
set -euo pipefail

BRAND="${brand}"
PROJECT="${project}"
ENVIRONMENT="${environment}"
LOCATION="${location}"

hostnamectl set-hostname "varnish.$${BRAND}.internal"
echo "127.0.0.1 varnish.$${BRAND}.internal" >> /etc/hosts

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl jq unzip varnish python3-pip python3-venv

curl -sL https://aka.ms/InstallAzureCLIDeb | bash

pip3 install pipx --quiet
pipx install ansible-core
pipx ensurepath

echo "Varnish instance initialized: $PROJECT/$ENVIRONMENT" >> /var/log/cloud-init-custom.log

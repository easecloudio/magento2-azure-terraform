#!/bin/bash
set -euo pipefail

# Set hostname
BRAND="${brand}"
PROJECT="${project}"
ENVIRONMENT="${environment}"

hostnamectl set-hostname "frontend.$${BRAND}.internal"
echo "127.0.0.1 frontend.$${BRAND}.internal" >> /etc/hosts

# Update and install base packages
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl jq unzip python3-pip python3-venv

# Install Azure CLI (needed to pull secrets from Key Vault using MSI)
curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# Install Ansible via pipx
pip3 install pipx --quiet
pipx install ansible-core
pipx ensurepath

echo "Frontend instance initialized: $PROJECT/$ENVIRONMENT" >> /var/log/cloud-init-custom.log

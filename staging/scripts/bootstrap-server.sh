#!/usr/bin/env bash
# Runs ON the staging server — `make bootstrap` pipes it over SSH.
# Installs Docker, creates the /opt layout and the shared "proxy" network.
# Idempotent: safe to re-run.
set -euo pipefail

if ! command -v docker >/dev/null; then
  echo "== installing docker (get.docker.com) =="
  if curl -fsSL https://get.docker.com | sudo sh; then
    echo "docker installed from get.docker.com"
  else
    echo "== get.docker.com failed; falling back to Ubuntu packages =="
    sudo apt-get update -y
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io docker-compose-v2
  fi
else
  echo "docker already installed: $(docker --version)"
fi

sudo systemctl enable --now docker

# Deploy user runs docker without sudo in future sessions.
sudo usermod -aG docker ubuntu || true

# Layout for the shared proxy + one dir per app (source rsynced from the Mac).
sudo mkdir -p /opt/caddy /opt/naikbusaja /opt/maribelanja
sudo chown -R ubuntu:ubuntu /opt/caddy /opt/naikbusaja /opt/maribelanja

# Shared network so Caddy can reach app containers across compose projects.
if sudo docker network create proxy 2>/dev/null; then
  echo "network 'proxy' created"
else
  echo "network 'proxy' already exists"
fi

echo "== done =="

#!/bin/bash
set -euo pipefail

# ----------------------------------------
# Bootstrap Script - Post-VM provisioning
# Installs Docker and deploys enabled modules
# ----------------------------------------

REPO_URL="https://raw.githubusercontent.com/mohamadmussa/oracle-vm-hunter/main"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Use local modules if available, otherwise fetch from GitHub
if [ -d "$REPO_ROOT/modules" ]; then
  MODULES_DIR="$REPO_ROOT/modules"
else
  MODULES_DIR=$(mktemp -d)
  trap 'rm -rf "$MODULES_DIR"' EXIT
  echo "Fetching modules from GitHub..."
  mkdir -p "$MODULES_DIR/kavita"
  curl -sL "$REPO_URL/modules/kavita/docker-compose.yml" -o "$MODULES_DIR/kavita/docker-compose.yml"
fi

# Module toggles (controlled via env vars)
ENABLE_KAVITA="${ENABLE_KAVITA:-true}"
ENABLE_NEXTCLOUD="${ENABLE_NEXTCLOUD:-false}"
ENABLE_BACKUP="${ENABLE_BACKUP:-false}"

# --- Install Docker if not present ---
install_docker() {
  if command -v docker &>/dev/null; then
    echo "Docker already installed: $(docker --version)"
    return 0
  fi

  echo "Installing Docker..."
  curl -fsSL https://get.docker.com | sh
  sudo usermod -aG docker "$USER"
  sudo systemctl enable --now docker
  echo "Docker installed: $(docker --version)"
}

# --- Deploy a module ---
deploy_module() {
  local name="$1"
  local dir="$MODULES_DIR/$name"

  if [ ! -f "$dir/docker-compose.yml" ]; then
    echo "WARNING: Module '$name' has no docker-compose.yml — skipping."
    return 1
  fi

  echo "Deploying module: $name"
  sudo docker compose -f "$dir/docker-compose.yml" up -d
  echo "Module '$name' is running."
}

# --- Main ---
echo "=== Bootstrap Start ==="

install_docker

# Create data directories
sudo mkdir -p /data/manga /data/config
sudo chown -R "$USER:$USER" /data

# Deploy enabled modules
[ "$ENABLE_KAVITA" = "true" ] && deploy_module "kavita"
[ "$ENABLE_NEXTCLOUD" = "true" ] && deploy_module "nextcloud"
[ "$ENABLE_BACKUP" = "true" ] && deploy_module "backup"

echo "=== Bootstrap Complete ==="

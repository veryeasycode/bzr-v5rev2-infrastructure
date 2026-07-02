#!/bin/bash

# --- Global Configuration ---
# Set package versions for your target platform before running.
## General
NJS_PACKAGE="libnginx-mod-http-js"
PAM_PACKAGE="libnginx-mod-http-auth-pam"
DOCKER_VERSION="5:29.5.3*"
MONGODB_VERSION="8.0"
## Platform: Raspberry Pi 5 — Debian Trixie arm64
# NGINX_VERSION="1.26.3-3*"
# NJS_VERSION="0.8.9-1*"
# PAM_VERSION="1:1.5.5-3*"
## Platform: Ubuntu Noble x86_64
NGINX_VERSION="1.24.0-2*"
NJS_VERSION="0.8.2-1*"
PAM_VERSION="1:1.5.5-2*"

# Exit immediately if a command exits with a non-zero status
set -e

# Automatically move to the directory where this script lives
cd "$(dirname "$0")"

# --- Helper Functions ---

help() {
  echo "Usage: ./bootstrap.sh [options] [software ...]"
  echo "Options:"
  echo "  -i [software ...]   Installation only, without configuring."
  echo "                      Optionally pick specific software: docker, nginx, mongodb (default: all)"
  echo "  -r                  Reconfigure only (run deploy config)"
  echo "  -u                  Uninstall services, purge packages, and autoremove"
  echo "  -h                  Show this help message"
  echo "  (no args)           Run full setup steps"
  echo "Examples:"
  echo "  ./bootstrap.sh -i                # install docker, nginx, and mongodb"
  echo "  ./bootstrap.sh -i nginx mongodb  # install only nginx and mongodb"
  echo "  ./bootstrap.sh -u"
}

log() {
  echo -e "\n⚙️  \033[1;34m$1\033[0m"
}

install_and_pin() {
  local package_name=$1
  local version=$2
  log "Installing $package_name (Version: $version)..."
  sudo apt-get install -y --allow-downgrades "${package_name}=${version}"
  sudo apt-mark hold "$package_name"
}

wait_for_mongodb() {
  until bash -c '</dev/tcp/localhost/27017' 2>/dev/null; do sleep 1; done
}

# --- Core Setup Steps ---

prepare_environment() {
  log "Preparing environment and scripts..."
  sudo apt-get update
  chmod 755 scripts/*.sh
}

setup_docker() {
  log "Setting up Docker..."

  sudo apt-get update
  sudo apt-get install -y ca-certificates curl gnupg
  sudo install -m 0755 -d /etc/apt/keyrings

  local os_id
  os_id=$(. /etc/os-release && echo "$ID")
  if [ "$os_id" != "ubuntu" ] && [ "$os_id" != "debian" ]; then
    os_id="debian"
  fi

  local codename
  codename=$(. /etc/os-release && echo "$VERSION_CODENAME")
  # Trixie has no official Docker release yet; fall back to bookworm
  if [ "$codename" = "trixie" ]; then
    codename="bookworm"
  fi

  sudo curl -fsSL "https://download.docker.com/linux/${os_id}/gpg" -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${os_id} ${codename} stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  log "Installing Docker packages..."
  sudo apt-get update
  install_and_pin "docker-ce" "${DOCKER_VERSION}"
  install_and_pin "docker-ce-cli" "${DOCKER_VERSION}"
  sudo apt-get install -y containerd.io docker-buildx-plugin docker-compose-plugin

  log "Starting and enabling Docker service..."
  sudo systemctl enable docker
  sudo systemctl start docker
  sudo systemctl status docker --no-pager

  log "Adding www-data user to docker group..."
  sudo usermod -a -G docker www-data
}

setup_nginx() {
  log "Setting up Nginx..."

  install_and_pin "nginx" "${NGINX_VERSION}"
  install_and_pin "${NJS_PACKAGE}" "${NJS_VERSION}"

  install_and_pin "${PAM_PACKAGE}" "${PAM_VERSION}"

  log "Starting and enabling Nginx..."
  sudo systemctl enable nginx
  sudo systemctl start nginx
  sudo systemctl status nginx --no-pager
}

setup_mongodb() {
  log "Setting up MongoDB ${MONGODB_VERSION}..."

  sudo apt-get update
  sudo apt-get install -y gnupg curl

  curl -fsSL "https://www.mongodb.org/static/pgp/server-${MONGODB_VERSION}.asc" | \
    sudo gpg -o /usr/share/keyrings/mongodb-server-${MONGODB_VERSION}.gpg --dearmor

  local os_id codename arch
  os_id=$(. /etc/os-release && echo "$ID")
  codename=$(. /etc/os-release && echo "$VERSION_CODENAME")
  arch=$(dpkg --print-architecture)

  # MongoDB only publishes arm64 packages for Ubuntu, not Debian.
  # Raspberry Pi (arm64) on Debian must use the Ubuntu Jammy repo instead.
  if [ "$arch" = "arm64" ] && [ "$os_id" = "debian" ]; then
    os_id="ubuntu"
    codename="jammy"
  elif [ "$os_id" = "debian" ] && [ "$codename" = "trixie" ]; then
    # Trixie has no official MongoDB release yet; fall back to bookworm
    codename="bookworm"
  fi

  echo "deb [ arch=${arch} signed-by=/usr/share/keyrings/mongodb-server-${MONGODB_VERSION}.gpg ] \
https://repo.mongodb.org/apt/${os_id} ${codename}/mongodb-org/${MONGODB_VERSION} multiverse" | \
    sudo tee /etc/apt/sources.list.d/mongodb-org-${MONGODB_VERSION}.list > /dev/null

  log "Installing MongoDB packages..."
  sudo apt-get update
  sudo apt-get install -y mongodb-org
  sudo apt-mark hold mongodb-org

  log "Stopping auto-started MongoDB instance from package postinst..."
  sudo systemctl stop mongod || true
  sudo rm -rf /var/lib/mongodb/*

  log "Generating MongoDB keyfile..."
  sudo mkdir -p /opt/keyfile
  openssl rand -base64 756 | sudo tee /opt/keyfile/mongo-keyfile > /dev/null
  sudo chmod 400 /opt/keyfile/mongo-keyfile
  sudo chown mongodb:mongodb /opt/keyfile/mongo-keyfile

  log "Initializing MongoDB data directory permissions..."
  sudo mkdir -p /var/lib/mongodb /var/log/mongodb
  sudo chown -R mongodb:mongodb /var/lib/mongodb /var/log/mongodb
  sudo cp templates/mongodb/mongod-01.conf /etc/mongod.conf

  log "Starting and enabling MongoDB service..."
  sudo systemctl enable mongod
  sudo systemctl start mongod
  sudo systemctl status mongod --no-pager

  log "Creating MongoDB admin user..."
  wait_for_mongodb
  mongosh ./scripts/create_mongodb_user.js

  log "Enabling MongoDB authentication..."
  sudo cp templates/mongodb/mongod-02.conf /etc/mongod.conf
  sudo systemctl restart mongod

  log "Initializing MongoDB replica set..."
  local replica_set
  replica_set=$(grep '^MONGO_REPLICA_SET=' .env | cut -d= -f2)
  sudo cp templates/mongodb/mongod-03.conf /etc/mongod.conf
  sudo sed -i "s/{{MONGO_REPLICA_SET}}/${replica_set}/" /etc/mongod.conf
  sudo systemctl restart mongod
  wait_for_mongodb
  mongosh ./scripts/init_mongodb_repset.js
}

configure_pam() {
  log "Configuring PAM permissions for Nginx..."
  sudo cp templates/pam.d/* /etc/pam.d/
  sudo groupadd shadow 2>/dev/null || true
  sudo usermod -a -G shadow www-data
  sudo chown root:shadow /etc/shadow
  sudo chmod g+r /etc/shadow
}

deploy_config() {
  log "Deploying Nginx configuration..."
  sudo ./scripts/deploy_nginx_conf.sh
}

# --- Core Uninstall Steps ---

uninstall() {
  log "Stopping and disabling Nginx service..."
  sudo systemctl stop nginx || true
  sudo systemctl disable nginx || true

  log "Removing package holds..."
  sudo apt-mark unhold nginx "${NJS_PACKAGE}" "${PAM_PACKAGE}" docker-ce docker-ce-cli || true

  log "Purging Nginx and NJS packages..."
  sudo apt-get purge -y nginx nginx-common "${NJS_PACKAGE}" "${PAM_PACKAGE}"
  sudo apt-get autoremove -y

  log "Stopping and disabling Docker service..."
  sudo systemctl stop docker || true
  sudo systemctl disable docker || true

  log "Purging Docker packages..."
  sudo apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras || true

  log "Removing Docker directories and repository configuration..."
  sudo rm -rf /var/lib/docker /var/lib/containerd || true
  sudo rm -f /etc/apt/sources.list.d/docker.list /etc/apt/keyrings/docker.asc || true

  log "Stopping and disabling MongoDB service..."
  sudo systemctl stop mongod || true
  sudo systemctl disable mongod || true

  log "Purging MongoDB packages..."
  sudo apt-mark unhold mongodb-org || true
  sudo apt-get purge -y mongodb-org || true

  log "Removing MongoDB directories and repository configuration..."
  sudo rm -rf /var/lib/mongodb /var/log/mongodb /opt/keyfile || true
  sudo rm -f /etc/mongod.conf || true
  sudo rm -f /etc/apt/sources.list.d/mongodb-org-${MONGODB_VERSION}.list /usr/share/keyrings/mongodb-server-${MONGODB_VERSION}.gpg || true

  # 💡 Future software uninstalls can be appended here (e.g., uninstall_node)

  log "🗑️ Uninstall and cleanup complete!"
}

# --- Main Workflows ---

run_reconfig_only() {
  prepare_environment
  deploy_config
  log "🔄 Reconfiguration complete!"
}

run_installation_only() {
  local components=("$@")
  if [ ${#components[@]} -eq 0 ]; then
    components=(docker nginx mongodb)
  fi

  # Validate all names before installing anything
  local component
  for component in "${components[@]}"; do
    case $component in
      docker|nginx|mongodb ) ;;
      * ) echo "❌ Unknown software: $component (available: docker, nginx, mongodb)"; help; exit 1 ;;
    esac
  done

  prepare_environment
  for component in "${components[@]}"; do
    case $component in
      docker ) setup_docker ;;
      nginx ) setup_nginx ;;
      mongodb ) setup_mongodb ;;
    esac
  done
  # 💡 Future software installs can be appended to the case above (e.g., node)
  log "📦 Installation complete (configuration and PAM skipped)!"
}

run_full_setup() {
  prepare_environment
  setup_docker
  setup_nginx
  setup_mongodb
  configure_pam
  deploy_config
  # 💡 Future software setups can be appended here (e.g., setup_node)
  log "🎉 Full bootstrap complete!"
}

# --- Option Parsing ---

INSTALL_ONLY=false
RECONFIG_ONLY=false
UNINSTALL_ONLY=false

while getopts "iruh" opt; do
  case ${opt} in
    i ) INSTALL_ONLY=true ;;
    r ) RECONFIG_ONLY=true ;;
    u ) UNINSTALL_ONLY=true ;;
    h ) help; exit 0 ;;
    \? ) help; exit 1 ;;
  esac
done
shift $((OPTIND - 1))

if [ "$UNINSTALL_ONLY" = true ]; then
  uninstall
elif [ "$RECONFIG_ONLY" = true ]; then
  run_reconfig_only
elif [ "$INSTALL_ONLY" = true ]; then
  run_installation_only "$@"
else
  run_full_setup
fi

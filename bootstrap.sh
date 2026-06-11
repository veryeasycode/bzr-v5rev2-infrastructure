#!/bin/bash

# --- Global Configuration ---
# Set package names and targeted versions for Debian 13 (Trixie) / Ubuntu stock repos
NGINX_VERSION="1.26.3-3*"
NJS_PACKAGE="libnginx-mod-http-js"
NJS_VERSION="0.8.9-1*"
DOCKER_VERSION="5:29.5.3*"

# Exit immediately if a command exits with a non-zero status
set -e

# Automatically move to the directory where this script lives
cd "$(dirname "$0")"

# --- Helper Functions ---

help() {
  echo "Usage: ./bootstrap.sh [options]"
  echo "Options:"
  echo "  -i          Installation only (install Docker and Nginx without configuring)"
  echo "  -r          Reconfigure only (run deploy config)"
  echo "  -u          Uninstall services, purge packages, and autoremove"
  echo "  -h          Show this help message"
  echo "  (no args)   Run full setup steps"
  echo "Example: ./bootstrap.sh -u"
}

log() {
  echo -e "\n🚀 \033[1;34m$1\033[0m"
}

install_and_pin() {
  local package_name=$1
  local version=$2
  
  log "Installing $package_name (Version: $version)..."
  sudo apt install "${package_name}=${version}" -y
  
  log "Pinning $package_name to prevent accidental updates..."
  sudo apt-mark hold "$package_name"
}

# --- Core Setup Steps ---

prepare_environment() {
  log "Preparing environment and scripts..."
  sudo apt update
  chmod 755 scripts/*.sh
}

setup_docker() {
  log "Setting up Docker..."
  
  # Install prerequisites
  sudo apt-get update
  sudo apt-get install -y ca-certificates curl gnupg
  
  # Create keyrings directory
  sudo install -m 0755 -d /etc/apt/keyrings
  
  # Determine OS distribution and codename
  local os_id
  os_id=$(. /etc/os-release && echo "$ID")
  
  # Fallback to debian if the OS is not ubuntu or debian
  if [ "$os_id" != "ubuntu" ] && [ "$os_id" != "debian" ]; then
    os_id="debian"
  fi
  
  local codename
  codename=$(. /etc/os-release && echo "$VERSION_CODENAME")
  # Handle fallback for Debian 13 (Trixie) which might not have official Docker release yet
  if [ "$codename" = "trixie" ]; then
    codename="bookworm"
  fi
  
  # Fetch Docker GPG key
  sudo curl -fsSL "https://download.docker.com/linux/${os_id}/gpg" -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc
  
  # Setup Docker repository list
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${os_id} \
    ${codename} stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
  log "Installing Docker packages..."
  sudo apt-get update
  
  install_and_pin "docker-ce" "${DOCKER_VERSION}"
  install_and_pin "docker-ce-cli" "${DOCKER_VERSION}"
  
  log "Installing additional Docker components..."
  sudo apt install -y containerd.io docker-buildx-plugin docker-compose-plugin
  
  log "Starting and enabling Docker service..."
  sudo systemctl enable docker
  sudo systemctl start docker
  sudo systemctl status docker --no-pager
  
  log "Adding www-data user to docker group..."
  sudo usermod -a -G docker www-data
}

setup_nginx() {
  # Install standard Nginx
  install_and_pin "nginx" "${NGINX_VERSION}"
  
  # Install NJS using the global native package variable
  install_and_pin "${NJS_PACKAGE}" "${NJS_VERSION}"
  
  log "Starting and enabling Nginx..."
  sudo systemctl enable nginx
  sudo systemctl start nginx
  sudo systemctl status nginx --no-pager
}

configure_pam() {
  log "Configuring PAM permissions for Nginx..."
  sudo cp templates/pam.d/* /etc/pam.d/
  
  # Silently handle group creation if 'shadow' already exists by dropping stderr
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
  sudo apt-mark unhold nginx "${NJS_PACKAGE}" docker-ce docker-ce-cli || true

  log "Purging Nginx and NJS modules (removing configs)..."
  sudo apt purge nginx nginx-common "${NJS_PACKAGE}" -y

  log "Running autoremove to clean up unused dependencies..."
  sudo apt autoremove -y

  log "Stopping and disabling Docker service..."
  sudo systemctl stop docker || true
  sudo systemctl disable docker || true

  log "Purging Docker packages..."
  sudo apt purge docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras -y || true

  log "Removing Docker directories and repository configuration..."
  sudo rm -rf /var/lib/docker /var/lib/containerd || true
  sudo rm -f /etc/apt/sources.list.d/docker.list || true
  sudo rm -f /etc/apt/keyrings/docker.asc || true

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
  prepare_environment
  setup_docker
  setup_nginx
  log "📦 Installation complete (configuration and PAM skipped)!"
}

run_full_setup() {
  prepare_environment
  setup_docker
  setup_nginx
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

# Run chosen workflow based on flags
if [ "$UNINSTALL_ONLY" = true ]; then
  uninstall
elif [ "$RECONFIG_ONLY" = true ]; then
  run_reconfig_only
elif [ "$INSTALL_ONLY" = true ]; then
  run_installation_only
else
  run_full_setup
fi
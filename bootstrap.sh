#!/bin/bash

# --- Global Configuration ---
# Set package names and targeted versions for Debian 13 (Trixie) / Ubuntu stock repos
NGINX_VERSION="1.26.3-3*"
NJS_PACKAGE="libnginx-mod-http-js"
NJS_VERSION="0.8.9-1*"

# Exit immediately if a command exits with a non-zero status
set -e

# Automatically move to the directory where this script lives
cd "$(dirname "$0")"

# --- Helper Functions ---

help() {
  echo "Usage: ./bootstrap.sh [options]"
  echo "Options:"
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
  sudo apt-mark unhold nginx "${NJS_PACKAGE}" || true

  log "Purging Nginx and NJS modules (removing configs)..."
  sudo apt purge nginx nginx-common "${NJS_PACKAGE}" -y

  log "Running autoremove to clean up unused dependencies..."
  sudo apt autoremove -y

  # 💡 Future software uninstalls can be appended here (e.g., uninstall_node)

  log "🗑️ Uninstall and cleanup complete!"
}

# --- Main Workflows ---

run_reconfig_only() {
  prepare_environment
  deploy_config
  log "🔄 Reconfiguration complete!"
}

run_full_setup() {
  prepare_environment
  setup_nginx
  configure_pam
  deploy_config
  # 💡 Future software setups can be appended here (e.g., setup_node)
  log "🎉 Full bootstrap complete!"
}

# --- Option Parsing ---

RECONFIG_ONLY=false
UNINSTALL_ONLY=false

while getopts "ruh" opt; do
  case ${opt} in
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
else
  run_full_setup
fi
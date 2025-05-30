#!/usr/bin/env bash

# installFrog.sh — FrogNet Phase 1 installer
# This script will:
#   1. Verify we're on Debian/Ubuntu and running as root
#   2. Update system packages
#   3. Install any missing OS packages needed by FrogNet
#   4. Prompt the user for FrogNet configuration values with clear explanations
#   5. Save those values to /etc/frognet/frognet.env
#   6. Copy all installer files to /etc/frognet for Phase 2
#   7. Set up Phase 2 to run after reboot
#
# Phase 2 will handle all FrogNet network configuration, service setup, etc.
set -euo pipefail

# --- Constants -------------------------------------------------------------

# Directory where this installer script lives
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# List of Debian/Ubuntu packages FrogNet requires
REQUIRED_PKGS=(
  apache2
  php
  php-cgi
  jq
  iptables
  network-manager
  dnsmasq
  inotify-tools
  python3
  openssh-server
  net-tools
  hostapd
  bridge-utils
)

# Installation directories
INSTALL_DIR="/etc/frognet"
TARBALL="$SCRIPT_DIR/installable_tar.tar"
ENV_FILE="$INSTALL_DIR/frognet.env"

# --- Helper Functions -----------------------------------------------------

echo_err() { echo -e "\033[1;31mERROR:\033[0m $*" >&2; exit 1; }
echo_info() { echo -e "\033[1;32m[*]\033[0m $*"; }
echo_warn() { echo -e "\033[1;33m[!]\033[0m $*"; }

# --- Pre-flight Checks ---------------------------------------------------
echo_info " =========================================================="
echo_info " FrogNet Phase 1 Installer - System Setup and Configuration"
echo_info " =========================================================="
echo ""

[[ -f /etc/os-release ]] || echo_err "This installer only supports Debian/Ubuntu systems."
source /etc/os-release
[[ "$ID" =~ ^(debian|ubuntu)$ ]] || echo_err "This installer only supports Debian/Ubuntu systems. Detected: $ID"

(( EUID == 0 )) || echo_err "Must be run as root. Please re-run with: sudo $0"

ORIGINAL_USER="${SUDO_USER:-$(logname 2>/dev/null || echo 'unknown')}"

# --- System Updates and Package Installation -------------------------------
echo_info "Updating system packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
echo_info "Upgrading existing packages..."
apt-get upgrade -y -qq

missing=()
for pkg in "${REQUIRED_PKGS[@]}"; do
  dpkg -s "$pkg" &>/dev/null || missing+=("$pkg")
done

if (( ${#missing[@]} > 0 )); then
  echo_info "Installing missing packages: ${missing[*]}"
  apt-get install -y -qq "${missing[@]}"
else
  echo_info "All required packages are already installed."
fi

# --- Port 53 Conflict Check ---
if lsof -i :53 | grep -q systemd-resolve; then
  echo_warn "Port 53 in use by systemd-resolved. Disabling it..."
  systemctl stop systemd-resolved
  systemctl disable systemd-resolved
  rm -f /etc/resolv.conf
  echo "nameserver 1.1.1.1" > /etc/resolv.conf
fi

# --- Extract Tarball ---
[[ -f "$TARBALL" ]] || echo_err "Tarball $(basename "$TARBALL") not found in $SCRIPT_DIR"
echo_info "Extracting contents of $(basename "$TARBALL")..."
tar xvf "$TARBALL" -C /

# --- Configuration Collection ---------------------------------------------
echo ""
echo_info "FrogNet Configuration Setup"
echo_info "==========================="
echo ""
echo "FrogNet creates a local network that other devices can connect to."
echo "This network will have its own domain name and IP address range."
echo "You'll need to provide some basic configuration information."
echo ""

# NETWORK DOMAIN NAME
cat <<EODOM
1. NETWORK DOMAIN NAME
   This is the name that will appear when users search for WiFi networks.
   It's also the local domain name for this FrogNet node.
EODOM
read -rp "Enter the domain name for this FrogNet network [default: FrogNet-001]: " domain_input
FROGNET_DOMAIN="${domain_input:-FrogNet-001}"

# NODE IP ADDRESS
echo ""
cat <<EOIP
2. NODE IP ADDRESS
   This is the IP address this FrogNet node will use on its local network.
   It should not conflict with your existing network ranges.
EOIP
read -rp "Enter the IP address for this node [default: 10.8.8.1]: " ip_input
FROGNET_NODE_IP="${ip_input:-10.8.8.1}"

# UPSTREAM NETWORK INTERFACE
echo ""
cat <<EOIF
3. UPSTREAM NETWORK INTERFACE
   This is the network interface that connects to the internet.
   FrogNet will share this connection with devices that connect to it.
EOIF
DEFAULT_IFACE="$(ip route 2>/dev/null | awk '/^default/ {print $5; exit}')"
read -rp "Enter the upstream network interface [default: $DEFAULT_IFACE]: " iface_input
FROGNET_INTERFACE="${iface_input:-$DEFAULT_IFACE}"

# --- Save Configuration ---------------------------------------------------
echo_info "Saving configuration to $ENV_FILE"
mkdir -p "$INSTALL_DIR"
cat > "$ENV_FILE" <<EOF
# FrogNet Phase 1 Configuration
# Generated on $(date)
FROGNET_DOMAIN="$FROGNET_DOMAIN"
FROGNET_NODE_IP="$FROGNET_NODE_IP"
FROGNET_INTERFACE="$FROGNET_INTERFACE"
EOF
chmod 600 "$ENV_FILE"
chown root:root "$ENV_FILE"

# --- Copy Installation Files ----------------------------------------------
echo_info "Copying installer files to $INSTALL_DIR"
[[ "$SCRIPT_DIR" != "$INSTALL_DIR" ]] && rsync -a --exclude="*.backup.*" "$SCRIPT_DIR"/ "$INSTALL_DIR"/
chmod +x "$INSTALL_DIR"/*.sh 2>/dev/null || true
chown -R root:root "$INSTALL_DIR"

# --- Summary --------------------------------------------------------------
echo ""
echo_info "Configuration Summary"
echo_info "===================="
echo "Domain Name:      $FROGNET_DOMAIN"
echo "Node IP:          $FROGNET_NODE_IP"
echo "Interface:        $FROGNET_INTERFACE"
echo "Install Directory: $INSTALL_DIR"
echo ""
echo_info "✅ Phase 1 Complete!"
echo "System has been updated and configured."
echo "All FrogNet files have been copied to $INSTALL_DIR"
echo "To complete setup, run Phase 2:"
echo "  cd $INSTALL_DIR"
echo "  ./phase2_setup.sh"

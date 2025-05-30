#!/usr/bin/env bash

# installFrog.sh - FrogNet Node Installer (tarball mode)
# Unzip the purchased FrogNet package and run this script as root.

set -euo pipefail

# --- Constants ---
ENV_FILE="/etc/frognet/frognet.env"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARBALL="$SCRIPT_DIR/installable_tar.tar"
MAP_SCRIPT="/usr/local/bin/mapInterfaces"
REQUIRED_PKGS=(apache2 php jq iptables php-cgi network-manager dnsmasq inotify-tools python3 openssh-server net-tools)

# --- Helpers ---
echo_err() { echo -e "\033[1;31mERROR:\033[0m $*" >&2; }
echo_info() { echo -e "\033[1;32m[*]\033[0m $*"; }
echo_warn() { echo -e "\033[1;33m[!]\033[0m $*"; }

# --- OS & Permissions Check ---
if [[ ! -d /etc/apt || ! -f /etc/os-release ]]; then
  echo_err "This installer supports Debian/Ubuntu only."
  exit 1
fi

if [[ $EUID -ne 0 ]]; then
  echo_err "Must be run as root. Use: sudo $0"
  exit 1
fi

# --- Enable IP Forwarding if Needed ---
if grep -q '^#net.ipv4.ip_forward=1' /etc/sysctl.conf; then
  sed -i 's/^#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
elif ! grep -q '^net.ipv4.ip_forward=1' /etc/sysctl.conf; then
  echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
fi

# --- Port 53 Conflict Resolution ---
if lsof -i :53 | grep -q systemd-resolve; then
  echo_warn "Port 53 in use by systemd-resolved. Disabling it..."
  systemctl stop systemd-resolved
  systemctl disable systemd-resolved
  rm -f /etc/resolv.conf
  echo "nameserver 1.1.1.1" > /etc/resolv.conf
fi

# --- Extract Tarball Early ---
if [[ -f "$TARBALL" ]]; then
  echo_info "Extracting contents of $(basename "$TARBALL")..."
  tar xvf "$TARBALL" -C /
else
  echo_err "Tarball $(basename "$TARBALL") not found in $SCRIPT_DIR"
  exit 1
fi

# --- Configure Interface Mapping (mapInterfaces) ---
echo_info "Configuring interface map..."
cat > "$MAP_SCRIPT" <<EOF
#!/bin/bash
export eth0Name="eth0"
export wlan0Name="wlan0"
export wlan1Name=""
EOF
chmod +x "$MAP_SCRIPT"

# --- User Prompts ---
echo "FrogNet will use a dedicated interface for its subnet (not your upstream network)."
DEFAULT_IFACE=$(ip route 2>/dev/null | awk '/^default/ {print $5; exit}')
read -rp "Enter the FrogNet-dedicated network interface [default: $DEFAULT_IFACE]: " iface_input
FROGNET_INTERFACE=${iface_input:-$DEFAULT_IFACE}

echo "This is the local domain this FrogNet node will serve (e.g., frognet.local)"
read -rp "Enter your FrogNet domain name (FQDN) [default: frognet.local]: " domain_input
FROGNET_DOMAIN=${domain_input:-frognet.local}

echo "Enter the IP for this node on the FrogNet subnet. Should not conflict with existing LAN."
read -rp "FrogNet node IP [default: 10.8.8.1]: " ip_input
FROGNET_NODE_IP=${ip_input:-10.8.8.1}

# --- Save Config ---
mkdir -p "$(dirname "$ENV_FILE")"
cat > "$ENV_FILE" <<EOF
FROGNET_INTERFACE="$FROGNET_INTERFACE"
FROGNET_DOMAIN="$FROGNET_DOMAIN"
FROGNET_NODE_IP="$FROGNET_NODE_IP"
EOF

echo_info "Configuration saved to $ENV_FILE"

# --- Install Required Packages ---
missing=()
for pkg in "${REQUIRED_PKGS[@]}"; do
  dpkg -s "$pkg" &>/dev/null || missing+=("$pkg")
done

if (( ${#missing[@]} )); then
  echo_info "Installing missing packages: ${missing[*]}"
  apt-get update && apt-get install -y "${missing[@]}"
else
  echo_info "All required packages present."
fi

# --- Done ---
echo_info "DEBUG: FrogNet installation complete."

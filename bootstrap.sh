#!/usr/bin/env bash
echo -e "\n"
cat <<'EOF'
##############################################################
#                                                            #
#  Copyright (c) 2025, Fawcett Innovations, LLC              #
#  All Rights Reserved                                       #
#                                                            #
#  This software is proprietary and confidential.            #
#  Unauthorized copying, distribution, or use of this        #
#  code, via any medium, is strictly prohibited.             #
#                                                            #
#  If you wish to license this software or use it in a       #
#  commercial or non-commercial project, please contact:     #
#     contact@fawcettinnovations.com                         #
#                                                            #
##############################################################
EOF
echo -e "\n"
# bootstrap.sh - FrogNet Full Bootstrap Installer
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/EventStreamInc/installer/jeremy/bootstrap.sh | sudo bash

set -euo pipefail

# --- Constants -------------------------------------------------------------
GITHUB_REPO="EventStreamInc/installer"
GITHUB_BRANCH="jeremy"
TEMP_DIR="/tmp/frognet-install"
INSTALL_TARBALL="installable_tar.tar"
INSTALL_DEST="/"
REQUIRED_PKGS=(git apache2 php jq iptables php-cgi network-manager dnsmasq inotify-tools python3 openssh-server net-tools)

# --- Helper Functions -----------------------------------------------------
echo_err() { echo -e "\033[1;31mERROR:\033[0m $*" >&2; exit 1; }
echo_info() { echo -e "[ \033[1;32m*\033[0m ] $*"; }
echo_warn() { echo -e "\033[1;33m[!]\033[0m $*"; }

# ------------------------------------------------------
echo "===================================================="
echo "     FrogNet Full Bootstrap Installer"
echo "===================================================="

if (( EUID != 0 )); then
  echo_err "Must be run as root. Use: sudo bash"
fi

if [[ ! -f /etc/os-release ]]; then
  echo_err "Only Debian/Ubuntu-based systems are supported."
fi

source /etc/os-release
if [[ "$ID" != "debian" && "$ID" != "ubuntu" && "$ID" != "raspbian" ]]; then
  echo_err "Unsupported OS: $ID"
fi

echo_info "Detected OS: $PRETTY_NAME"

# --- Install Dependencies -------------------------------------------------
echo_info "Installing required packages..."

apt-get update -qq
for pkg in "${REQUIRED_PKGS[@]}"; do
  if ! dpkg -s "$pkg" &>/dev/null; then
    echo_info "Installing $pkg..."
    apt-get install -y "$pkg"
  else
    echo_info "$pkg already installed."
  fi
done

# --- Clone Repository -----------------------------------------------------
echo_info "Cloning FrogNet installer repository..."

rm -rf "$TEMP_DIR"
if ! git clone --depth 1 "https://github.com/${GITHUB_REPO}.git" "$TEMP_DIR"; then
  echo_err "Failed to clone repository."
fi

echo_info "Repository cloned to $TEMP_DIR"

# --- Extract Installer Tarball --------------------------------------------
if [[ ! -f "$TEMP_DIR/$INSTALL_TARBALL" ]]; then
  echo_err "Tarball not found in repo: $INSTALL_TARBALL"
fi

echo_info "Extracting $INSTALL_TARBALL to $INSTALL_DEST ..."
tar -xvf "$TEMP_DIR/$INSTALL_TARBALL" -C "$INSTALL_DEST"

MAP_FILE="/usr/local/bin/mapInterfaces"

# Patch mapInterfaces for correct interface names
if [[ -f "$MAP_FILE" ]]; then
  echo_info "Patching mapInterfaces for correct interface names..."

  sed -i 's/^export wlan0Name=.*/export wlan0Name="wlan0"/' "$MAP_FILE"
  sed -i 's/^export wlan1Name=.*/export wlan1Name=""/' "$MAP_FILE"

  echo_info "mapInterfaces updated:"
  grep -E 'wlan0Name|wlan1Name' "$MAP_FILE"
else
  echo_warn "mapInterfaces file not found at $MAP_FILE — skipping patch."
fi

# --- Default Configuration ------------------------------------------------
FROGNET_DOMAIN="${FROGNET_DOMAIN:-frognet.local}"
FROGNET_NODE_IP="${FROGNET_NODE_IP:-10.2.2.1}"

echo_info "Running setup_lillypad with domain $FROGNET_DOMAIN and IP $FROGNET_NODE_IP..."

if [[ -x "/usr/local/bin/setup_lillypad.bash" ]]; then
  echo_info "Executing setup_lillypad.bash..."
  /usr/local/bin/setup_lillypad.bash "$FROGNET_DOMAIN" "$FROGNET_NODE_IP"
else
  echo_err "setup_lillypad.bash not found or not executable at /usr/local/bin/"
fi

# --- IPV4 Forwarding -------------------------------------------
sudo sed -i 's/^#\?net\.ipv4\.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
sudo sysctl -w net.ipv4.ip_forward=1
sudo sysctl -p /etc/sysctl.conf


# --- Final Network Sanity Check -------------------------------------------
echo_info "Running final network fixups..."

NEEDS_REPAIR=false

if ! grep -q nameserver /etc/resolv.conf 2>/dev/null || [[ ! -s /etc/hosts ]]; then
  NEEDS_REPAIR=true
fi

if [[ -d /etc/sentinels && -n "$(ls -A /etc/sentinels 2>/dev/null)" ]]; then
  NEEDS_REPAIR=true
fi

if $NEEDS_REPAIR; then
  echo_warn "Network configs appear broken. Attempting repair..."

  rm -f /etc/hosts /etc/resolv.conf
  rm -f /etc/sentinels/* || true

  echo_info "Restarting NetworkManager and dnsmasq..."
  service NetworkManager restart
  service dnsmasq restart

  sleep 2

  if ping -c1 8.8.8.8 &>/dev/null; then
    echo_info "Network repair successful: ping working."
  else
    echo_err "Network repair attempted, but ping to 8.8.8.8 still failed."
  fi
else
  echo_info "Network appears to be functioning. No repair needed."
fi

# --- Final Setup Message and Reboot ---------------------------------------

echo_warn "No automated network repair will be attempted."

echo_info "IMPORTANT: Please make sure the Ethernet cable is plugged in."
echo_info "The system will wait 30 seconds, then reboot automatically..."

for i in {30..1}; do
  printf "\rRebooting in %2d seconds... Press Ctrl+C to cancel." "$i"
  sleep 1
done

echo -e "\n"
echo_info "Rebooting now!"
reboot

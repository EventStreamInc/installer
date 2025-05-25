#!/usr/bin/env bash
# installer.sh — FrogNet Phase 1 installer (tarball mode)
# This script will:
#   1. Verify we’re on Debian/Ubuntu and running as root
#   2. Install any missing OS packages needed by FrogNet
#   3. Prompt the user for FrogNet configuration values
#   4. Save those values to /etc/frognet/frognet.env
#   5. Copy the entire unpacked ZIP (scripts, README, tarball, etc.) into /etc/frognet
#
# It does NOT extract the tarball—that’s reserved for Phase 2.
set -euo pipefail

# --- Constants -------------------------------------------------------------

# List of Debian/Ubuntu packages FrogNet requires
REQUIRED_PKGS=(
  apache2
  php
  jq
  iptables
  php-cgi
  network-manager
  dnsmasq
  inotify-tools
  python3
  openssh-server
  net-tools
)

# Where we’ll install all FrogNet files for inspection
INSTALL_DIR="/etc/frognet"

# The env file that will hold user-provided settings
ENV_FILE="$INSTALL_DIR/frognet.env"

# Directory where this installer script lives (the unpacked ZIP root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


# --- Helper Functions -----------------------------------------------------

# Print an error message in red, then exit
echo_err() {
  echo -e "\033[1;31mERROR:\033[0m $*" >&2
  exit 1
}

# Print an informational message in green
echo_info() {
  echo -e "\033[1;32m[*]\033[0m $*"
}

# Print a warning in yellow
echo_warn() {
  echo -e "\033[1;33m[!]\033[0m $*"
}


# --- 1) Pre-flight Checks -------------------------------------------------

# Ensure we’re on a Debian/Ubuntu-like system
if [[ ! -f /etc/os-release ]]; then
  echo_err "This installer only supports Debian/Ubuntu."
fi

# Ensure script is run as root (so we can write to /etc and install packages)
if (( EUID != 0 )); then
  echo_err "Must be run as root. Please re-run with: sudo $0"
fi


# --- 2) Install Missing OS Packages --------------------------------------

# Build a list of packages not yet installed
missing=()
for pkg in "${REQUIRED_PKGS[@]}"; do
  if ! dpkg -s "$pkg" &>/dev/null; then
    missing+=("$pkg")
  fi
done

# If any are missing, install them
if (( ${#missing[@]} > 0 )); then
  echo_info "Installing missing packages: ${missing[*]}"
  # Non-interactive frontend prevents prompts
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y "${missing[@]}"
else
  echo_info "All required packages are already installed."
fi


# --- 3) Prompt User for Configuration ------------------------------------

echo_info "Now configuring FrogNet. You can press ENTER to accept each default."

# 3a) Network interface for FrogNet’s dedicated subnet
echo "This is the network interface that FrogNet will use for its own private subnet."
DEFAULT_IFACE="$(ip route 2>/dev/null | awk '/^default/ {print $5; exit}')"
read -rp "FrogNet interface [default: $DEFAULT_IFACE]: " iface_input
FROGNET_INTERFACE="${iface_input:-$DEFAULT_IFACE}"

# 3b) Local domain name (FQDN) FrogNet will serve
echo "This is the local domain (FQDN) that this node will answer for."
read -rp "FrogNet domain [default: frognet.local]: " domain_input
FROGNET_DOMAIN="${domain_input:-frognet.local}"

# 3c) Node’s IP address on the FrogNet subnet
echo "This is the static IP for this node on the FrogNet subnet."
echo "It should not conflict with your existing LAN—recommended: 10.101.0.1"
read -rp "FrogNet node IP [default: 10.101.0.1]: " ip_input
FROGNET_NODE_IP="${ip_input:-10.101.0.1}"


# --- 4) Save Configuration to ENV File -----------------------------------

echo_info "Saving configuration to $ENV_FILE"
mkdir -p "$(dirname "$ENV_FILE")"

cat > "$ENV_FILE" <<EOF
# FrogNet configuration (Phase 1)
// Generated on $(date)
FROGNET_INTERFACE="$FROGNET_INTERFACE"
FROGNET_DOMAIN="$FROGNET_DOMAIN"
FROGNET_NODE_IP="$FROGNET_NODE_IP"
EOF


# --- 5) Copy All Files into /etc/frognet ----------------------------------

# If an old install exists, confirm overwrite
if [[ -d "$INSTALL_DIR" ]]; then
  echo_warn "Existing FrogNet installation detected at $INSTALL_DIR."
  read -rp "Overwrite it? [y/N]: " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo_info "Aborting—no changes made."
    exit 0
  fi
fi

echo_info "Copying all files from $SCRIPT_DIR → $INSTALL_DIR"
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
# -a: archive mode (preserves subdirs, permissions, symlinks)
# --chown=root:root: make everything owned by root
rsync -a --chown=root:root "$SCRIPT_DIR"/ "$INSTALL_DIR"/

echo_info "All files are now available under $INSTALL_DIR for inspection."


# --- Phase 1 Complete ------------------------------------------------------

echo_info "✅ Phase 1 complete! Dependencies installed, config written, and files copied."
echo_info "Next up: Phase 2 (tarball extraction, symlinks, service setup, etc.)."

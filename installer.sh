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

# Directory where this installer script lives
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

# Generate a random IP in the 10.x.x.x range to avoid conflicts
generate_random_ip() {
  echo "10.$((RANDOM % 254 + 1)).$((RANDOM % 254 + 1)).1"
}

# Check if an IP range conflicts with existing interfaces
check_ip_conflict() {
  local test_ip="$1"
  local network=$(echo "$test_ip" | cut -d. -f1-3).0/24
  
  # Check if this network is already in use
  if ip route show | grep -q "$network"; then
    return 1  # Conflict found
  fi
  return 0  # No conflict
}

# --- Pre-flight Checks ---------------------------------------------------
echo_info " =========================================================="
echo_info " FrogNet Phase 1 Installer - System Setup and Configuration"
echo_info " =========================================================="
echo ""

# Ensure we're on a Debian/Ubuntu-like system
if [[ ! -f /etc/os-release ]]; then
  echo_err "This installer only supports Debian/Ubuntu systems."
fi

source /etc/os-release
if [[ ! "$ID" =~ ^(debian|ubuntu)$ ]]; then
  echo_err "This installer only supports Debian/Ubuntu systems. Detected: $ID"
fi

# Ensure script is run as root
if (( EUID != 0 )); then
  echo_err "Must be run as root. Please re-run with: sudo $0"
fi

# Get the original user who ran sudo (for later use)
ORIGINAL_USER="${SUDO_USER:-$(logname 2>/dev/null || echo 'unknown')}"

# --- System Updates and Package Installation -------------------------------

echo_info "Updating system packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq

echo_info "Upgrading existing packages..."
apt-get upgrade -y -qq

# Check which packages are missing
missing=()
for pkg in "${REQUIRED_PKGS[@]}"; do
  if ! dpkg -s "$pkg" &>/dev/null; then
    missing+=("$pkg")
  fi
done

# Install missing packages
if (( ${#missing[@]} > 0 )); then
  echo_info "Installing missing packages: ${missing[*]}"
  apt-get install -y -qq "${missing[@]}"
else
  echo_info "All required packages are already installed."
fi

# Extract the tarball containing the FrogNet installer files
if [[ -f "$TARBALL" ]]; then
  echo_info "Extracting contents of $(basename "$TARBALL")..."
  tar xvf "$TARBALL" -C /
else
  echo_err "Tarball $(basename "$TARBALL") not found in $SCRIPT_DIR"
  exit 1
fi
# --- Configuration Collection ---------------------------------------------

echo ""
echo_info "FrogNet Configuration Setup"
echo_info "==========================="
echo ""
echo "FrogNet creates a local network that other devices can connect to."
echo "This network will have its own domain name and IP address range."
echo "You'll need to provide some basic configuration information."
echo ""

# 1. Network domain name (what users will see when connecting)
echo "1. NETWORK DOMAIN NAME"
echo "   This is the name that will appear when users search for WiFi networks."
echo "   It's also the local domain name for this FrogNet node."
echo ""
read -rp "Enter the domain name for this FrogNet network [default: FrogNet-001]: " domain_input
FROGNET_DOMAIN="${domain_input:-FrogNet-001}"

# 2. Node IP address (avoid conflicts)
echo ""
echo "2. NODE IP ADDRESS"
echo "   This is the IP address this FrogNet node will use on its local network."
echo "   It should not conflict with your existing network ranges."
echo ""

# Generate a default IP that doesn't conflict
DEFAULT_NODE_IP=""
for attempt in {1..10}; do
  candidate_ip=$(generate_random_ip)
  if check_ip_conflict "$candidate_ip"; then
    DEFAULT_NODE_IP="$candidate_ip"
    break
  fi
done

# Fallback if we couldn't find a non-conflicting IP
if [[ -z "$DEFAULT_NODE_IP" ]]; then
  DEFAULT_NODE_IP="10.10.10.1"
  echo_warn "Could not auto-generate non-conflicting IP. Using default: $DEFAULT_NODE_IP"
  echo_warn "Please verify this doesn't conflict with your existing networks."
fi

read -rp "Enter the IP address for this node [default: $DEFAULT_NODE_IP]: " ip_input
FROGNET_NODE_IP="${ip_input:-$DEFAULT_NODE_IP}"

# Validate IP format
if ! [[ $FROGNET_NODE_IP =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
  echo_err "Invalid IP address format: $FROGNET_NODE_IP"
fi

# 3. Network interface selection
echo ""
echo "3. UPSTREAM NETWORK INTERFACE"
echo "   This is the network interface that connects to the internet."
echo "   FrogNet will share this connection with devices that connect to it."
echo ""

# Find the interface with the default route
DEFAULT_IFACE="$(ip route 2>/dev/null | awk '/^default/ {print $5; exit}')"
if [[ -z "$DEFAULT_IFACE" ]]; then
  DEFAULT_IFACE="wlan0"  # Reasonable fallback for Pi
fi

# Show available interfaces
echo "Available network interfaces:"
ip link show | grep -E '^[0-9]+:' | while IFS=': ' read num iface rest; do
  if [[ "$iface" != "lo" ]]; then
    status=""
    if ip addr show "$iface" | grep -q "inet "; then
      status=" (has IP)"
    fi
    echo "  - $iface$status"
  fi
done
echo ""

read -rp "Enter the upstream network interface [default: $DEFAULT_IFACE]: " iface_input
FROGNET_INTERFACE="${iface_input:-$DEFAULT_IFACE}"

# Verify the interface exists
if ! ip link show "$FROGNET_INTERFACE" &>/dev/null; then
  echo_err "Network interface '$FROGNET_INTERFACE' does not exist."
fi



# --- Save Configuration ---------------------------------------------------

echo ""
echo_info "Saving configuration to $ENV_FILE"

# Create the installation directory
mkdir -p "$INSTALL_DIR"

# Write the environment file
cat > "$ENV_FILE" <<EOF
# FrogNet Phase 1 Configuration
# Generated on $(date)
# 
# This file contains the basic configuration for this FrogNet node.
# Phase 2 will use these values to configure the network services.

# Network Configuration
FROGNET_DOMAIN="$FROGNET_DOMAIN"
FROGNET_NODE_IP="$FROGNET_NODE_IP"
FROGNET_INTERFACE="$FROGNET_INTERFACE"



# System Information
INSTALL_DATE="$(date -Iseconds)"
INSTALLER_VERSION="1.134"
ORIGINAL_USER="$ORIGINAL_USER"
EOF

# Set proper permissions
chmod 600 "$ENV_FILE"
chown root:root "$ENV_FILE"

# --- Copy Installation Files ----------------------------------------------

echo_info "Copying installer files to $INSTALL_DIR"

# Remove any existing installation
if [[ -d "$INSTALL_DIR" && "$INSTALL_DIR" != "$SCRIPT_DIR" ]]; then
  echo_warn "Existing installation found. Backing up configuration..."
  if [[ -f "$ENV_FILE" ]]; then
    cp "$ENV_FILE" "${ENV_FILE}.backup.$(date +%s)"
  fi
fi

# Copy all files from the current directory to the install directory
# Use rsync to preserve permissions and handle the case where source = destination
if [[ "$SCRIPT_DIR" != "$INSTALL_DIR" ]]; then
  rsync -a --exclude="*.backup.*" "$SCRIPT_DIR"/ "$INSTALL_DIR"/
  chown -R root:root "$INSTALL_DIR"
fi

# Make sure scripts are executable
chmod +x "$INSTALL_DIR"/*.sh 2>/dev/null || true

# --- Configuration Summary ------------------------------------------------

echo ""
echo_info "Configuration Summary"
echo_info "===================="
echo "Domain Name:      $FROGNET_DOMAIN"
echo "Node IP:          $FROGNET_NODE_IP"  
echo "Interface:        $FROGNET_INTERFACE"
echo "Install Directory: $INSTALL_DIR"
echo ""



# --- Completion -----------------------------------------------------------

echo ""
echo_info "✅ Phase 1 Complete!"
echo_info "==================="
echo ""
echo "System has been updated and configured."
echo "All FrogNet files have been copied to $INSTALL_DIR"
echo ""
echo "To complete FrogNet setup, run Phase 2:"
echo "  cd $INSTALL_DIR"
echo "  ./phase2_setup.sh"
echo ""
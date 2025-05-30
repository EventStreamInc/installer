#!/usr/bin/env bash
# installer.sh - FrogNet Complete Installer
# This script handles the complete FrogNet installation process based on 
# lessons learned from troubleshooting sessions.
#
# Key fixes implemented:
# - Automatic IP forwarding enablement 
# - Proper mapInterfaces file generation
# - Clean DNS configuration to prevent malformed entries
# - Integrated lillypad setup with user configuration
#
set -euo pipefail

# --- Constants -------------------------------------------------------------
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
  git
)

INSTALL_DIR="/etc/frognet"
ENV_FILE="$INSTALL_DIR/frognet.env"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Helper Functions -----------------------------------------------------
echo_err() {
  echo -e "\033[1;31mERROR:\033[0m $*" >&2
  exit 1
}

echo_info() {
  echo -e "\033[1;32m[*]\033[0m $*"
}

echo_warn() {
  echo -e "\033[1;33m[!]\033[0m $*"
}

echo_success() {
  echo -e "\033[1;32m✅\033[0m $*"
}

prompt_with_default() {
  local prompt="$1"
  local default="$2"
  local result
  
  read -rp "$prompt [default: $default]: " result
  echo "${result:-$default}"
}

validate_ip() {
  local ip="$1"
  if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    return 0
  else
    return 1
  fi
}

generate_random_ip() {
  echo "10.$((RANDOM % 254 + 1)).$((RANDOM % 254 + 1)).1"
}

check_ip_conflict() {
  local test_ip="$1"
  local network=$(echo "$test_ip" | cut -d. -f1-3).0/24
  
  if ip route show | grep -q "$network"; then
    return 1  # Conflict found
  fi
  return 0  # No conflict
}

# --- Pre-flight Checks ---------------------------------------------------
echo_info "=========================================================="
echo_info "FrogNet Complete Installer - System Setup and Configuration"
echo_info "=========================================================="
echo ""

# Ensure we're on a Debian/Ubuntu-like system
if [[ ! -f /etc/os-release ]]; then
  echo_err "This installer only supports Debian/Ubuntu systems."
fi

source /etc/os-release
if [[ ! "$ID" =~ ^(debian|ubuntu|raspbian)$ ]]; then
  echo_err "This installer only supports Debian/Ubuntu/Raspbian systems. Detected: $ID"
fi

echo_info "Detected OS: $PRETTY_NAME"

# Ensure script is run as root
if (( EUID != 0 )); then
  echo_err "Must be run as root. Please re-run with: sudo $0"
fi

ORIGINAL_USER="${SUDO_USER:-$(logname 2>/dev/null || echo 'unknown')}"

# --- System Updates and Package Installation -----------------------------
echo_info "Updating system packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq

echo_info "Upgrading existing packages..."
apt-get upgrade -y -qq

# Install missing packages
missing=()
for pkg in "${REQUIRED_PKGS[@]}"; do
  if ! dpkg -s "$pkg" &>/dev/null; then
    missing+=("$pkg")
  fi
done

if (( ${#missing[@]} > 0 )); then
  echo_info "Installing missing packages: ${missing[*]}"
  apt-get install -y -qq "${missing[@]}"
else
  echo_info "All required packages are already installed."
fi

# --- CRITICAL FIX: Enable IP Forwarding ----------------------------------
echo_info "Configuring IP forwarding (CRITICAL for internet sharing)..."

# Check if ip_forward is present and uncommented
if grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
  echo_info "IP forwarding already enabled."
elif grep -q "^#net.ipv4.ip_forward=1" /etc/sysctl.conf; then
  echo_info "Enabling IP forwarding (uncommenting existing line)..."
  sed -i 's/^#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
elif grep -q "net.ipv4.ip_forward" /etc/sysctl.conf; then
  echo_info "Updating existing IP forwarding setting..."
  sed -i 's/^.*net.ipv4.ip_forward.*$/net.ipv4.ip_forward=1/' /etc/sysctl.conf
else
  echo_info "Adding IP forwarding setting..."
  echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi

# Apply immediately without reboot
echo 1 > /proc/sys/net/ipv4/ip_forward
echo_success "IP forwarding enabled!"

# --- Network Interface Discovery -----------------------------------------
echo_info "Discovering network interfaces..."

# Find available interfaces
available_interfaces=($(ip -o link show | awk -F': ' '{print $2}' | grep -v lo))
wifi_interfaces=($(iwconfig 2>/dev/null | grep -o '^[a-zA-Z0-9]*' || true))

echo_info "Available network interfaces: ${available_interfaces[*]}"
if (( ${#wifi_interfaces[@]} > 0 )); then
  echo_info "WiFi interfaces detected: ${wifi_interfaces[*]}"
fi

# Find the interface with default route (internet connection)
DEFAULT_INTERNET_IFACE="$(ip route 2>/dev/null | awk '/^default/ {print $5; exit}')"

# --- User Configuration --------------------------------------------------
echo ""
echo_info "FrogNet Configuration"
echo_info "===================="
echo_info "Please provide the following configuration details:"
echo ""

# 1. Access Point Name (SSID)
echo_info "1. Access Point Configuration"
echo "This will be the WiFi network name that devices connect to."
ap_name=$(prompt_with_default "Access Point Name (SSID)" "bob")

# 2. Access Point Password (optional)
echo ""
echo "WiFi Password (leave empty for open network - not recommended):"
echo -n "Access Point Password (8+ characters): "
read -rs ap_password
echo ""

# Validate password if provided
if [[ -n "$ap_password" && ${#ap_password} -lt 8 ]]; then
  echo_err "Password must be at least 8 characters long"
fi

# 3. Domain name
echo ""
echo_info "2. Network Configuration"
echo "This is the local domain name for this FrogNet node."
domain=$(prompt_with_default "Local domain name" "freddy")

# 4. FrogNet subnet IP
echo ""
echo "FrogNet Subnet Configuration:"
echo "This node needs its own IP address on the FrogNet subnet."

# Generate a default IP that doesn't conflict
DEFAULT_NODE_IP="10.8.8.1"  # From successful troubleshooting session

# Check if this IP conflicts, if so suggest alternative
if ! check_ip_conflict "$DEFAULT_NODE_IP"; then
  echo_warn "Default IP $DEFAULT_NODE_IP may conflict with existing network"
  for attempt in {1..5}; do
    candidate_ip=$(generate_random_ip)
    if check_ip_conflict "$candidate_ip"; then
      echo_info "Alternative suggestion: $candidate_ip"
      DEFAULT_NODE_IP="$candidate_ip"
      break
    fi
  done
fi

while true; do
  frognet_ip=$(prompt_with_default "FrogNet subnet gateway IP" "$DEFAULT_NODE_IP")
  if validate_ip "$frognet_ip"; then
    break
  else
    echo_warn "Invalid IP address format. Please try again."
  fi
done

# Extract subnet base from IP (e.g., 10.8.8.1 -> 10.8.8)
subnet_base="${frognet_ip%.*}"

# 5. Interface configuration
echo ""
echo_info "3. Interface Configuration"
echo "Select which interface will serve the FrogNet subnet:"

if (( ${#available_interfaces[@]} == 1 )); then
  eth_interface="${available_interfaces[0]}"
  echo_info "Using interface: $eth_interface"
else
  echo "Available interfaces:"
  for i in "${!available_interfaces[@]}"; do
    interface="${available_interfaces[i]}"
    status=""
    if [[ "$interface" == "$DEFAULT_INTERNET_IFACE" ]]; then
      status=" (currently has internet)"
    elif ip addr show "$interface" | grep -q "inet "; then
      status=" (has IP)"
    fi
    echo "  $((i+1)). $interface$status"
  done
  
  while true; do
    read -rp "Select ethernet interface for FrogNet subnet (1-${#available_interfaces[@]}): " selection
    if [[ "$selection" =~ ^[0-9]+$ ]] && (( selection >= 1 && selection <= ${#available_interfaces[@]} )); then
      eth_interface="${available_interfaces[$((selection-1))]}"
      break
    else
      echo_warn "Invalid selection. Please choose 1-${#available_interfaces[@]}."
    fi
  done
fi

# 6. WiFi interface for internet connection
echo ""
echo_info "4. Internet Interface Selection"
wifi_interface=""
if [[ -n "$DEFAULT_INTERNET_IFACE" ]]; then
  echo "Current internet interface detected: $DEFAULT_INTERNET_IFACE"
  use_current=$(prompt_with_default "Use $DEFAULT_INTERNET_IFACE for internet connection? (y/n)" "y")
  if [[ "$use_current" =~ ^[Yy] ]]; then
    wifi_interface="$DEFAULT_INTERNET_IFACE"
  fi
fi

if [[ -z "$wifi_interface" && ${#wifi_interfaces[@]} -gt 0 ]]; then
  echo "Available WiFi interfaces:"
  for i in "${!wifi_interfaces[@]}"; do
    echo "  $((i+1)). ${wifi_interfaces[i]}"
  done
  echo "  $((${#wifi_interfaces[@]}+1)). None (manual configuration later)"
  
  while true; do
    read -rp "Select WiFi interface for internet connection (1-$((${#wifi_interfaces[@]}+1))): " selection
    if [[ "$selection" =~ ^[0-9]+$ ]]; then
      if (( selection >= 1 && selection <= ${#wifi_interfaces[@]} )); then
        wifi_interface="${wifi_interfaces[$((selection-1))]}"
        break
      elif (( selection == ${#wifi_interfaces[@]}+1 )); then
        wifi_interface=""
        echo_info "No WiFi interface selected - manual configuration required later"
        break
      fi
    fi
    echo_warn "Invalid selection. Please choose 1-$((${#wifi_interfaces[@]}+1))."
  done
fi

# Detect wlan1 (second WiFi interface)
wlan1_interface=""
for iface in "${wifi_interfaces[@]}"; do
  if [[ "$iface" != "$wifi_interface" ]]; then
    wlan1_interface="$iface"
    break
  fi
done

# --- Save Configuration --------------------------------------------------
echo_info "Saving configuration..."

mkdir -p "$INSTALL_DIR"
cat > "$ENV_FILE" << EOF
# FrogNet Configuration
# Generated on $(date)
# Based on troubleshooting fixes by John W. Fawcett

# Access Point Settings
FROGNET_AP_NAME="$ap_name"
FROGNET_AP_PASSWORD="$ap_password"

# Network Settings
FROGNET_DOMAIN="$domain"
FROGNET_NODE_IP="$frognet_ip"
FROGNET_SUBNET_BASE="$subnet_base"

# Interface Settings  
FROGNET_ETH_INTERFACE="$eth_interface"
FROGNET_WIFI_INTERFACE="$wifi_interface"

# Derived Settings
FROGNET_DHCP_RANGE="$subnet_base.2,$subnet_base.254"

# Detected Interfaces (for debugging)
DETECTED_ETH_INTERFACE="$eth_interface"
DETECTED_WIFI_INTERFACE="$wifi_interface"
DETECTED_WLAN1_INTERFACE="$wlan1_interface"

# System Information
INSTALL_DATE="$(date -Iseconds)"
INSTALLER_VERSION="2.0-johns-fixes"
ORIGINAL_USER="$ORIGINAL_USER"
EOF

chmod 600 "$ENV_FILE"
chown root:root "$ENV_FILE"

echo_success "Configuration saved to $ENV_FILE"

# --- Install FrogNet Files -----------------------------------------------
echo_info "Installing FrogNet files..."

# Copy all files to install directory
if [[ "$SCRIPT_DIR" != "$INSTALL_DIR" ]]; then
  rsync -a --chown=root:root "$SCRIPT_DIR"/ "$INSTALL_DIR"/
fi

# --- CRITICAL FIX: Update Existing mapInterfaces File --------------------
echo_info "Updating mapInterfaces file (preserving existing structure)..."

# First extract the tar if it exists to get the mapInterfaces file
if [[ -f "$INSTALL_DIR/installable_tar.tar" ]]; then
  echo_info "Extracting FrogNet system files..."
  cd /
  tar xf "$INSTALL_DIR/installable_tar.tar"
  
  # Make scripts executable
  chmod +x /usr/local/bin/*.sh 2>/dev/null || true
  chmod +x /usr/local/bin/*.bash 2>/dev/null || true
fi

# Now update the mapInterfaces file if it exists
if [[ -f /usr/local/bin/mapInterfaces ]]; then
  echo_info "Updating existing mapInterfaces file with detected interfaces..."
  
  # Update eth0Name
  sed -i "s/^export eth0Name=.*/export eth0Name=\"$eth_interface\"/" /usr/local/bin/mapInterfaces
  
  # Update wlan0Name (internet interface)
  if [[ -n "$wifi_interface" ]]; then
    sed -i "s/^export wlan0Name=.*/export wlan0Name=\"$wifi_interface\"/" /usr/local/bin/mapInterfaces
  else
    sed -i "s/^export wlan0Name=.*/export wlan0Name=\"\"/" /usr/local/bin/mapInterfaces
  fi
  
  # Update wlan1Name (second WiFi interface or empty)
  if [[ -n "$wlan1_interface" ]]; then
    sed -i "s/^export wlan1Name=.*/export wlan1Name=\"$wlan1_interface\"/" /usr/local/bin/mapInterfaces
  else
    sed -i "s/^export wlan1Name=.*/export wlan1Name=\"\"/" /usr/local/bin/mapInterfaces
  fi
  
  echo_success "mapInterfaces file updated successfully!"
  echo_info "Current interface mapping:"
  echo_info "  eth0Name: $eth_interface"
  echo_info "  wlan0Name: ${wifi_interface:-\"\"}"
  echo_info "  wlan1Name: ${wlan1_interface:-\"\"}"
else
  echo_warn "mapInterfaces file not found at /usr/local/bin/mapInterfaces"
  echo_warn "This may cause issues with the FrogNet setup"
fi
  
  # Run the lillypad setup with user configuration
  echo_info "Running FrogNet lillypad setup..."
  cd /usr/local/bin
  ./setup_lillypad.bash "$ap_name" "$frognet_ip"
  
  echo_success "FrogNet system configured successfully!"
else
  echo_warn "installable_tar.tar not found. Skipping FrogNet setup."
fi

# --- Clean Up DNS Configuration ------------------------------------------
echo_info "Cleaning up DNS configuration (prevents startup failures)..."

if [[ -f /etc/dnsmasq.d/opts_only.conf ]]; then
  # Remove any malformed entries that might have been generated
  sed -i '/such\.\.\.1/d' /etc/dnsmasq.d/opts_only.conf
  sed -i '/No\/such/d' /etc/dnsmasq.d/opts_only.conf
  echo_success "DNS configuration cleaned!"
fi

# Remove any corrupted hosts/resolv.conf files and regenerate
if [[ -f /usr/local/bin/mergeHostsAndResolve.bash ]]; then
  echo_info "Regenerating clean hosts and resolv.conf files..."
  cd /usr/local/bin
  rm -f /etc/hosts /etc/resolv.conf /etc/sentinels/* 2>/dev/null || true
  ./mergeHostsAndResolve.bash
  echo_success "Clean network configuration generated!"
fi

# --- Start and Enable Services -------------------------------------------
echo_info "Starting FrogNet services..."

# Start and enable dnsmasq
systemctl restart dnsmasq
systemctl enable dnsmasq

# Check if dnsmasq started successfully
if systemctl is-active --quiet dnsmasq; then
  echo_success "dnsmasq service started successfully!"
else
  echo_warn "dnsmasq service failed to start. Checking status..."
  systemctl status dnsmasq --no-pager || true
fi

# --- Installation Complete -----------------------------------------------
echo ""
echo_success "🎉 FrogNet installation complete!"
echo ""
echo_info "Configuration Summary:"
echo_info "====================="
echo_info "Access Point Name: $ap_name"
echo_info "Domain: $domain"
echo_info "Gateway IP: $frognet_ip"  
echo_info "Ethernet Interface: $eth_interface"
if [[ -n "$wifi_interface" ]]; then
  echo_info "WiFi Interface: $wifi_interface"
fi
echo_info "DHCP Range: $subnet_base.2 - $subnet_base.254"
echo ""
echo_info "Key Fixes Applied:"
echo_info "✅ IP forwarding enabled (critical for internet sharing)"
echo_info "✅ Clean mapInterfaces file (prevents DNS corruption)"
echo_info "✅ Proper interface mapping"
echo_info "✅ Clean DNS configuration"
echo ""
echo_info "Next Steps:"
if [[ -n "$wifi_interface" && "$wifi_interface" != "$eth_interface" ]]; then
  echo_info "1. Ensure $wifi_interface is connected to the internet"
  echo_info "2. Connect devices to the FrogNet  subnet via $eth_interface"
else
  echo_info "1. Connect your internet source to $eth_interface"
fi
echo_info "2. Connect devices to the '$ap_name' access point"
echo_info "3. Devices will receive IP addresses in the $subnet_base.2-254 range"
echo ""
echo_warn "IMPORTANT: A system reboot is recommended to ensure all changes take effect."
echo_info "Run: sudo reboot"
echo ""
echo_info "After reboot, check service status with:"
echo_info "  sudo systemctl status dnsmasq"
echo_info "  ip a"
echo_info "  ip r"
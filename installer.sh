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
echo ""

# Use pre-configured values or sensible defaults
ap_name="bob"  # Default AP name from troubleshooting session
ap_password="frognet123"  # Default password
domain="freddy"  # Default domain from troubleshooting

echo_info "Using default configuration:"
echo_info "Access Point Name: $ap_name"
echo_info "Domain: $domain"
echo ""

# 1. FrogNet subnet IP (auto-generate or use default from troubleshooting)
echo_info "Network Configuration:"
echo "This node needs its own IP address on the FrogNet subnet."

# Use default IP from troubleshooting session or auto-generate
DEFAULT_NODE_IP="10.8.8.1"  # From successful troubleshooting session

# Check if this IP conflicts, if so generate alternative
if ! check_ip_conflict "$DEFAULT_NODE_IP"; then
  echo_warn "Default IP $DEFAULT_NODE_IP conflicts with existing network"
  for attempt in {1..10}; do
    candidate_ip=$(generate_random_ip)
    if check_ip_conflict "$candidate_ip"; then
      DEFAULT_NODE_IP="$candidate_ip"
      echo_info "Using alternative IP: $DEFAULT_NODE_IP"
      break
    fi
  done
fi

frognet_ip="$DEFAULT_NODE_IP"
echo_info "FrogNet gateway IP: $frognet_ip"

# Extract subnet base from IP (e.g., 10.8.8.1 -> 10.8.8)
subnet_base="${frognet_ip%.*}"

# 2. Interface configuration (auto-detect or use common defaults)
echo ""
echo_info "Interface Configuration:"

# Auto-detect ethernet interface (prefer eth0)
if ip link show eth0 &>/dev/null; then
  eth_interface="eth0"
  echo_info "Using ethernet interface: $eth_interface"
elif (( ${#available_interfaces[@]} > 0 )); then
  # Use first available non-wifi interface
  for iface in "${available_interfaces[@]}"; do
    if [[ ! " ${wifi_interfaces[*]} " =~ " $iface " ]]; then
      eth_interface="$iface"
      break
    fi
  done
  echo_info "Using ethernet interface: $eth_interface"
else
  echo_err "No suitable ethernet interface found"
fi

# Auto-detect WiFi interface for internet connection
wifi_interface=""
if [[ -n "$DEFAULT_INTERNET_IFACE" ]]; then
  wifi_interface="$DEFAULT_INTERNET_IFACE"
  echo_info "Using internet interface: $wifi_interface"
elif ip link show wlan0 &>/dev/null; then
  wifi_interface="wlan0"
  echo_info "Using WiFi interface: $wifi_interface"
elif (( ${#wifi_interfaces[@]} > 0 )); then
  wifi_interface="${wifi_interfaces[0]}"
  echo_info "Using WiFi interface: $wifi_interface"
fi

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

# --- CRITICAL FIX: Create Proper mapInterfaces File ---------------------
echo_info "Creating mapInterfaces file (fixes malformed DNS entries)..."

cat > "$INSTALL_DIR/usr/local/bin/mapInterfaces" << EOF
#!/usr/bin/env bash
# FrogNet Interface Mapping
# Auto-generated by installer to prevent malformed entries

eth0Name="$eth_interface"
wlan0Name="$wifi_interface"
wlan1Name=""

# Domain settings (prevent malformed entries)
eth0InDomain=""
wlan0InDomain=""  
wlan1InDomain=""
EOF

chmod +x "$INSTALL_DIR/usr/local/bin/mapInterfaces"
echo_success "mapInterfaces file created successfully!"

# --- Extract and Setup Tarball -------------------------------------------
if [[ -f "$INSTALL_DIR/installable_tar.tar" ]]; then
  echo_info "Extracting FrogNet system files..."
  
  cd /
  tar xf "$INSTALL_DIR/installable_tar.tar"
  
  # Make scripts executable
  chmod +x /usr/local/bin/*.sh 2>/dev/null || true
  chmod +x /usr/local/bin/*.bash 2>/dev/null || true
  
  # Copy our fixed mapInterfaces to the live location
  cp "$INSTALL_DIR/usr/local/bin/mapInterfaces" /usr/local/bin/mapInterfaces
  
  # Run the lillypad setup with user configuration
  echo_info "Running FrogNet lillypad setup..."
  cd /usr/local/bin
  ./setup_lillypad.bash "$ap_name" "$frognet_ip"
  
  echo_success "FrogNet system files extracted and configured!"
else
  echo_warn "installable_tar.tar not found. Skipping tarball extraction."
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
  echo_info "2. Connect devices to the FrogNet subnet via $eth_interface"
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
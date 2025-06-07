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

# ---------------------------------------------------------
# 1) Setup and Logging
# ---------------------------------------------------------
INSTALL_DIR="/etc/frognet"
ENV_FILE="$INSTALL_DIR/frognet.env"
LOG_FILE="$INSTALL_DIR/installer.log"
REQUIRED_PKGS=(git apache2 php jq iptables php-cgi network-manager dnsmasq inotify-tools python3 openssh-server net-tools)
MAP_FILE="/usr/local/bin/mapInterfaces"

mkdir -p "$INSTALL_DIR"
> "$LOG_FILE"   # clear log
> "$ENV_FILE"   # clear env file
chmod 600 "$ENV_FILE"

# Helper functions
echo_info() { printf "[ \033[1;32m✅\033[0m ] %s\n" "$*"; }
echo_warn() { printf "[ \033[1;33m⚠️\033[0m ] %s\n" "$*"; }
echo_err() { printf "[ \033[1;31m❌\033[0m ] %s\n" "$*" >&2; exit 1; }

# Redirect all output to console and log
exec > >(tee -a "$LOG_FILE") 2>&1

# ---------------------------------------------------------
# 2) Detect script and work dirs
# ---------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo_info "Script directory: $SCRIPT_DIR"
CURRENT_DIR="$(pwd)"
echo_info "Current working directory: $CURRENT_DIR"

# ---------------------------------------------------------
# 3) Sanity checks
# ---------------------------------------------------------
echo_info "FrogNet Phase 1 Installer — Logging to $LOG_FILE"
(( EUID == 0 )) || echo_err "Must be run as root. Use: sudo $0"
ORIGINAL_USER="${SUDO_USER:-$(logname 2>/dev/null || echo 'unknown')}"

# ---------------------------------------------------------
# 4) Find tarball
# ---------------------------------------------------------
if [[ -f "$SCRIPT_DIR/installable_tar.tar" ]]; then
  TARBALL="$SCRIPT_DIR/installable_tar.tar"
elif [[ -f "$INSTALL_DIR/installable_tar.tar" ]]; then
  TARBALL="$INSTALL_DIR/installable_tar.tar"
else
  echo_err "installable_tar.tar not found in $SCRIPT_DIR or $INSTALL_DIR"
fi
echo_info "Using tarball: $TARBALL"

# ---------------------------------------------------------
# 5) Install dependencies
# ---------------------------------------------------------
echo_info "Updating packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq && apt-get upgrade -y -qq

missing=()
for pkg in "${REQUIRED_PKGS[@]}"; do
  dpkg -s "$pkg" &>/dev/null || missing+=("$pkg")
done
if (( ${#missing[@]} )); then
  echo_info "Installing: ${missing[*]}"
  apt-get install -y -qq "${missing[@]}"
else
  echo_info "All required packages installed"
fi

# ---------------------------------------------------------
# 6) Extract and copy tarball
# ---------------------------------------------------------
echo_info "Extracting tarball to /"
tar -xvf "$TARBALL" -C /
cp "$TARBALL" "$INSTALL_DIR/"

# ---------------------------------------------------------
# 7) Enable IPv4 forwarding
# ---------------------------------------------------------
echo_info "Enabling IPv4 forwarding..."
sed -i 's/^#\?net\.ipv4\.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
sysctl -w net.ipv4.ip_forward=1

# ---------------------------------------------------------
# 8) Interactive prompts
# ---------------------------------------------------------
echo -e "\n****Starting interactive configuration****\n"

# Choose upstream interface
echo_info "Detecting Ethernet interfaces..."
ETH_IFACES=()
for iface in /sys/class/net/*; do
  name=$(basename "$iface")
  [[ "$name" == lo ]] && continue
  [[ -d "/sys/class/net/$name/wireless" ]] && continue
  ETH_IFACES+=("$name")
done
(( ${#ETH_IFACES[@]} )) || echo_err "No Ethernet interfaces found"
echo "Detected: ${ETH_IFACES[*]}"
DEFAULT_IFACE="${ETH_IFACES[0]}"
read -rp "Upstream interface [${DEFAULT_IFACE}]: " UPSTREAM_INTERFACE
UPSTREAM_INTERFACE="${UPSTREAM_INTERFACE:-$DEFAULT_IFACE}"
[[ " ${ETH_IFACES[*]} " =~ " $UPSTREAM_INTERFACE " ]] || echo_err "Invalid interface"
echo_info "Using upstream: $UPSTREAM_INTERFACE"

# Hostname/domain
echo_info "Enter FrogNet hostname"
read -rp "Hostname [FrogNet-001]: " FROGNET_HOSTNAME
FROGNET_HOSTNAME="${FROGNET_HOSTNAME:-FrogNet-001}"
echo_info "Hostname: $FROGNET_HOSTNAME"

# Static IP
echo_info "Enter static IP (10.x.x.1)"
read -rp "IP [10.2.2.1]: " PI_IP_ADDRESS
PI_IP_ADDRESS="${PI_IP_ADDRESS:-10.2.2.1}"
[[ "$PI_IP_ADDRESS" =~ ^10\.[0-9]{1,3}\.[0-9]{1,3}\.1$ ]] || echo_err "Invalid IP"

echo_info "Static IP: $PI_IP_ADDRESS"

# Email for registration
read -rp "Enter your email: " USER_EMAIL
USER_EMAIL="${USER_EMAIL:-default@frognet.org}"

# ---------------------------------------------------------
# 9) Network ID generation & storage
# ---------------------------------------------------------
NETWORK_ID="$(tr -dc 'a-f0-9' < /dev/urandom | head -c32)"
PART1="${NETWORK_ID:0:8}"
PART2="${NETWORK_ID:8:8}"
PART3="${NETWORK_ID:16:8}"
PART4="${NETWORK_ID:24:8}"

mkdir -p "$HOME"
echo "$PART1" > "$HOME/.fn_g1"
echo "$PART2" > "/etc/FrogNetID"
echo "$PART3" > "/usr/local/bin/.fnid"

chmod 600 "$HOME/.fn_g1" /etc/FrogNetID /usr/local/bin/.fnid

# Reassemble for phone-home
FULL_NETWORK_ID="$PART1$PART2$PART3$PART4"

#echo_info "Full Network ID: $FULL_NETWORK_ID"

# ---------------------------------------------------------
# 10) Phone home via GET
# ---------------------------------------------------------
ENDPOINT="https://oureventstream.com/registerFrogNet.php"
echo_info "Registering with FrogNet..."
RESPONSE=$(curl -s -G "$ENDPOINT" \
  --data-urlencode "CustomerEmail=$USER_EMAIL" \
  --data-urlencode "NetworkID=$FULL_NETWORK_ID" \
  --data-urlencode "NetworkName=$FROGNET_HOSTNAME")

echo_info "Response: $RESPONSE"

echo_info "Saving configuration..."
cat > "$ENV_FILE" <<EOF
# FrogNet Config
FROGNET_HOSTNAME="$FROGNET_HOSTNAME"
PI_IP_ADDRESS="$PI_IP_ADDRESS"
UPSTREAM_INTERFACE="$UPSTREAM_INTERFACE"
INSTALL_DATE="$(date -Iseconds)"
INSTALLER_VERSION="1.134"
ORIGINAL_USER="$ORIGINAL_USER"
NETWORK_ID_PART4="$PART4"
NETWORK_ID_FULL="$FULL_NETWORK_ID"
EOF
chmod 600 "$ENV_FILE"; chown root:root "$ENV_FILE"

# ---------------------------------------------------------
# 11) Patch mapInterfaces
# ---------------------------------------------------------
if [[ -f "$MAP_FILE" ]]; then
  echo_info "Patching mapInterfaces..."
  sed -i 's/^export eth0Name=.*/export eth0Name="'"$UPSTREAM_INTERFACE"'"/' "$MAP_FILE"
  sed -i 's/^export wlan0Name=.*/export wlan0Name="wlan0"/' "$MAP_FILE"
  sed -i 's/^export wlan1Name=.*/export wlan1Name=""/' "$MAP_FILE"
fi

# ---------------------------------------------------------
# 12) Final notice & reboot
# ---------------------------------------------------------
echo_info "Installation complete. Rebooting in 30 seconds..."
for i in {30..1}; do printf "\rReboot %2d… Ctrl+C to cancel" "$i"; sleep 1; done

echo -e "\n"; echo_info "Rebooting now..."; reboot

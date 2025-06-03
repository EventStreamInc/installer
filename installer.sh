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
# 1) Set up install‐dir + log file
# ---------------------------------------------------------
INSTALL_DIR="/etc/frognet"
ENV_FILE="$INSTALL_DIR/frognet.env"
LOG_FILE="$INSTALL_DIR/installer.log"
REQUIRED_PKGS=(git apache2 php jq iptables php-cgi network-manager dnsmasq inotify-tools python3 openssh-server net-tools)
MAP_FILE="/usr/local/bin/mapInterfaces"

mkdir -p "$INSTALL_DIR"
> "$LOG_FILE"   # create/clear the log
> "$ENV_FILE"   # create/clear the environment file
chmod 600 "$ENV_FILE" || echo_err "Cannot chmod $ENV_FILE"
# (Don’t touch MAP_FILE here—I only want to patch if it already exists later.)

# ---------------------------------------------------------
# 1.5) Helper‐function definitions
# ---------------------------------------------------------
echo_info() {
  printf "[ \033[1;32m✅\033[0m ] %s\n" "$*"
}
echo_warn() {
  printf "[ \033[1;33m⚠️\033[0m ] %s\n" "$*"
}
echo_err() {
  printf "[ \033[1;31m❌\033[0m ] %s\n" "$*" >&2
  exit 1
}

# Redirect stdout/stderr to both console and $LOG_FILE
exec > >(tee -a "$LOG_FILE") 2>&1

# ---------------------------------------------------------
# 2) Figure out where we are
# ---------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo_info "Script directory: $SCRIPT_DIR"
CURRENT_DIR="$(pwd)"
echo_info "Current working directory: $CURRENT_DIR"

# ---------------------------------------------------------
# 3) Initial sanity checks
# ---------------------------------------------------------
echo_info "FrogNet Phase 1 Installer — Logging to $LOG_FILE"
echo_info "Checking OS and privileges…"
(( EUID == 0 )) || echo_err "Must be run as root. Use: sudo $0"
ORIGINAL_USER="${SUDO_USER:-$(logname 2>/dev/null || echo 'unknown')}"

# ---------------------------------------------------------
# 4) Locate the tarball
# ---------------------------------------------------------
if [[ -f "$SCRIPT_DIR/installable_tar.tar" ]]; then
  TARBALL="$SCRIPT_DIR/installable_tar.tar"
  echo_info "Found tarball alongside the script: $TARBALL"
elif [[ -f "$INSTALL_DIR/installable_tar.tar" ]]; then
  TARBALL="$INSTALL_DIR/installable_tar.tar"
  echo_info "Found tarball in $INSTALL_DIR: $TARBALL"
else
  echo_err "installable_tar.tar not found in $SCRIPT_DIR or $INSTALL_DIR. Aborting."
fi

# ---------------------------------------------------------
# 5) Install missing packages
# ---------------------------------------------------------
echo_info "Updating packages…"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq

missing=()
for pkg in "${REQUIRED_PKGS[@]}"; do
  dpkg -s "$pkg" &>/dev/null || missing+=("$pkg")
done

if (( ${#missing[@]} )); then
  echo_info "Installing missing packages: ${missing[*]}"
  apt-get install -y -qq "${missing[@]}"
else
  echo_info "All required packages are installed."
fi

# ---------------------------------------------------------
# 6) Extract the tarball
# ---------------------------------------------------------
[[ -f "$TARBALL" ]] || echo_err "Tarball not found: $TARBALL"
echo_info "Extracting tarball to /…"
tar -xvf "$TARBALL" -C /

# ---------------------------------------------------------
# 7) Enable IPv4 forwarding
# ---------------------------------------------------------
echo_info "Enabling IPv4 forwarding…"
sed -i 's/^#\?net\.ipv4\.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
sysctl -w net.ipv4.ip_forward=1
sysctl -p /etc/sysctl.conf

# ---------------------------------------------------------
echo_info "Starting interactive configuration…"

# 1) Discover wired‐Ethernet interfaces
ETH_IFACES=()
for iface_path in /sys/class/net/*; do
  name=$(basename "$iface_path")
  [[ "$name" == "lo" ]] && continue
  [[ -d "/sys/class/net/$name/wireless" ]] && continue
  ETH_IFACES+=("$name")
done

if (( ${#ETH_IFACES[@]} == 0 )); then
  echo_err "No Ethernet interfaces detected. Aborting."
fi

# 2) Display the list and prompt for choice
echo_info "Detected Ethernet interfaces:"
for idx in "${!ETH_IFACES[@]}"; do
  # show 1-based indices
  printf "  [%d] %s\n" $((idx+1)) "${ETH_IFACES[$idx]}"
done


# List all non-loopback interfaces so the user can choose
echo_info "Detected network interfaces:"
ip -o link show | awk -F': ' '$2 != "lo" { print "  •", $2 }'

cat <<EOF

You need to tell me which interface on the Pi has a working Internet connection (i.e. “upstream”).
The Pi will route outgoing FrogNet traffic through that interface.
For example, if you plug a cable from your modem/router into eth0, choose “eth0” here.
If you have eth0 and eth1 available, pick whichever is actually plugged into your upstream network.

EOF

# Automatically detect the interface that currently has the default route
DETECTED_UPSTREAM="$(ip route 2>/dev/null | awk '/^default/ { print $5; exit }')"
DETECTED_UPSTREAM="${DETECTED_UPSTREAM:-eth0}"

read -rp "Enter the Pi’s upstream interface [default: $DETECTED_UPSTREAM]: " upstream_input
UPSTREAM_INTERFACE="${upstream_input:-$DETECTED_UPSTREAM}"

if ! ip link show "$UPSTREAM_INTERFACE" &>/dev/null; then
  echo_err "Interface “$UPSTREAM_INTERFACE” does not exist. Please double-check and rerun."
fi

echo_info "Using $UPSTREAM_INTERFACE for upstream (WAN) traffic."

# Prompt for hostname that FrogNet clients will see
echo_info "Now choose a hostname for your FrogNet network (this becomes the domain name)."
read -rp "Enter the hostname [default: FrogNet-001]: " hostname_input
FROGNET_HOSTNAME="${hostname_input:-FrogNet-001}"

# Prompt for static IP address of the Pi (must be 10.x.x.1)
cat <<EOF

Next, choose the Pi’s static IP address on the 10.x.x.1 subnet.
This address is what clients will use to reach the Pi.
If you want the default, use 10.2.2.1.
Ensure that whatever you pick follows the format 10.<any>.<any>.1 (e.g., 10.5.10.1).

EOF

read -rp "Enter the Pi’s IP address [default: 10.2.2.1]: " ip_input
PI_IP_ADDRESS="${ip_input:-10.2.2.1}"

# Validate that it matches 10.x.x.1 pattern
if [[ ! "$PI_IP_ADDRESS" =~ ^10\.[0-9]{1,3}\.[0-9]{1,3}\.1$ ]]; then
  echo_err "Invalid IP “$PI_IP_ADDRESS”. Must be in the form 10.x.x.1."
fi

echo_info "Using $PI_IP_ADDRESS as the Pi’s static address."

# ---------------------------------------------------------
# 8) Save configuration
# ---------------------------------------------------------
echo_info "Saving configuration to $ENV_FILE…"
cat > "$ENV_FILE" <<EOF
# FrogNet Config
FROGNET_HOSTNAME="$FROGNET_HOSTNAME"
PI_IP_ADDRESS="$PI_IP_ADDRESS"
UPSTREAM_INTERFACE="$UPSTREAM_INTERFACE"
INSTALL_DATE="$(date -Iseconds)"
INSTALLER_VERSION="1.134"
ORIGINAL_USER="$ORIGINAL_USER"
EOF
chmod 600 "$ENV_FILE"
chown root:root "$ENV_FILE"

# ---------------------------------------------------------
# 9) Run setup_lillypad.bash with the hostname and IP
# ---------------------------------------------------------
echo_info "Executing setup_lillypad.bash with $FROGNET_HOSTNAME and $PI_IP_ADDRESS…"
if [[ -x "/usr/local/bin/setup_lillypad.bash" ]]; then
  /usr/local/bin/setup_lillypad.bash "$FROGNET_HOSTNAME" "$PI_IP_ADDRESS"
else
  echo_warn "setup_lillypad.bash not found or not executable at /usr/local/bin/"
fi

# ---------------------------------------------------------
# 10) Patch mapInterfaces if it already exists
# ---------------------------------------------------------
if [[ -f "$MAP_FILE" ]]; then
  echo_info "Patching mapInterfaces…"
  sed -i 's/^export wlan0Name=.*/export wlan0Name="wlan0"/' "$MAP_FILE"
  sed -i 's/^export wlan1Name=.*/export wlan1Name=""/' "$MAP_FILE"
  grep -E 'wlan0Name|wlan1Name' "$MAP_FILE"
else
  echo_warn "mapInterfaces not found—skipping patch."
fi

# ---------------------------------------------------------
# 11) Port 53 conflict resolution (commented out by default)
# ---------------------------------------------------------
# if lsof -i :53 | grep -q systemd-resolve; then
#   echo_warn "Port 53 in use by systemd-resolved. Disabling it…"
#   systemctl stop systemd-resolved
#   systemctl disable systemd-resolved
#   rm -f /etc/resolv.conf
#   echo "nameserver 1.1.1.1" > /etc/resolv.conf
# fi

# ---------------------------------------------------------
# 12) Final notice & reboot
# ---------------------------------------------------------
echo_info "Installation complete."
echo_info "Review the log at: $LOG_FILE"
echo_info "Ensure Ethernet is connected. Rebooting in 30 seconds…"
for i in {30..1}; do
  printf "\rRebooting in %2d seconds… Press Ctrl+C to cancel." "$i"
  sleep 1
done

echo -e "\n"
echo_info "Rebooting now."
reboot

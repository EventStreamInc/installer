#!/usr/bin/env bash
# installer.sh - FrogNet Node Installer (single-archive mode)
# Unzip or untar the purchased package and run this script as root (sudo) to set up a FrogNet node.
set -euo pipefail

# --- Constants ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/frognet.env"
TARBALL="$SCRIPT_DIR/installable_tar.tar"
MAP_SCRIPT="/usr/local/bin/mapInterface"
START_SCRIPT_NAMES=("startFrog.bash" "startFrogNet.bash" "setup_lillypad.bash")

# Packages required by FrogNet
REQUIRED_PKGS=(apache2 php jq iptables php-cgi network-manager dnsmasq inotify-tools python3 openssh-server net-tools)

# --- Helpers ---
echo_err() { echo -e "\033[1;31mERROR:\033[0m $*" >&2; }
echo_info() { echo -e "\033[1;32m[*]\033[0m $*"; }
echo_warn() { echo -e "\033[1;33m[!]\033[0m $*"; }

# 1) Ensure Debian-based
if [[ ! -d /etc/apt || ! -f /etc/os-release ]]; then
  echo_err "This installer supports Debian/Ubuntu only."
  exit 1
fi

# 2) Require root
if [[ $EUID -ne 0 ]]; then
  echo_err "Must be run as root. Use: sudo $0"
  exit 1
fi

# 3) Parse "--on-reboot" flag
on_reboot=false
if [[ "${1-}" == "--on-reboot" ]]; then
  on_reboot=true
fi

if $on_reboot; then
  # Post-reboot actions: start FrogNet
  echo_info "Running post-reboot startup..."
  source "$ENV_FILE"
  # run available start script
  for name in "${START_SCRIPT_NAMES[@]}"; do
    if [[ -x "$SCRIPT_DIR/$name" ]]; then
      echo_info "Invoking $name..."
      nohup "$SCRIPT_DIR/$name" > /var/log/frognet-start.log 2>&1 &
      break
    fi
  done
  # cleanup cron entry
  ( crontab -l 2>/dev/null | grep -v "$0 --on-reboot" ) | crontab -
  echo_info "Post-reboot startup complete."
  exit 0
fi

# 4) Gather inputs
# interface
DEFAULT_IFACE=$(ip route 2>/dev/null | awk '/^default/ {print $5; exit}')
read -rp "Network interface to use [default: $DEFAULT_IFACE]: " iface_input
FROGNET_INTERFACE=${iface_input:-$DEFAULT_IFACE}

# domain & node IP
read -rp "FrogNet domain (FQDN) [default: frognet.local]: " domain_input
FROGNET_DOMAIN=${domain_input:-frognet.local}
read -rp "Node IP on FrogNet network [default: 10.10.10.1]: " ip_input
FROGNET_NODE_IP=${ip_input:-192.168.1.100}
# oct1=`$random%254`
#last digit must be a one 
# 5) Write .env
cat > "$ENV_FILE" <<EOF
FROGNET_INTERFACE="$FROGNET_INTERFACE"
FROGNET_DOMAIN="$FROGNET_DOMAIN"
FROGNET_NODE_IP="$FROGNET_NODE_IP"
EOF
echo_info "Configuration saved to $ENV_FILE"

# 6) Install packages
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

# 7) Extract tarball
if [[ -f "$TARBALL" ]]; then
  echo_info "Extracting contents of $(basename "$TARBALL")..."
  tar xvf "$TARBALL" -C /
else
  echo_err "Tarball $(basename "$TARBALL") not found in $SCRIPT_DIR"
  exit 1
fi

# 8) Update interface mapping
if [[ -f "$MAP_SCRIPT" ]]; then
  sed -i "s/eth0\|ens33\|ens34\|eth1/$FROGNET_INTERFACE/g" "$MAP_SCRIPT"
  echo_info "Updated interface mapping in $MAP_SCRIPT"
else
  echo_warn "$MAP_SCRIPT missing, skipping interface mapping"
fi

# 9) Schedule post-reboot startup
echo "@reboot $0 --on-reboot" | { crontab -l 2>/dev/null || true; cat; } | crontab -
echo_info "Scheduled post-reboot startup via cron"

# 10) Final reboot
echo_info "Initial setup complete. Rebooting now to apply changes..."
reboot

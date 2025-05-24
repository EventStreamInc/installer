#!/usr/bin/env bash
# installer.sh - FrogNet Node Installer (single-archive mode)
# Unpressed package contains all scripts + installable_tar.tar.
# Usage: unzip package && sudo ./installer.sh
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
echo_err()  { echo -e "\033[1;31mERROR:\033[0m $*" >&2; }
echo_info() { echo -e "\033[1;32m[*]\033[0m $*"; }
echo_warn() { echo -e "\033[1;33m[!]\033[0m $*"; }

# 1) Ensure running on Debian/Ubuntu
if [[ ! -d /etc/apt || ! -f /etc/os-release ]]; then
  echo_err "This installer is only compatible with Debian-based distributions (Debian/Ubuntu)."
  exit 1
fi

# 2) Must be root
if [[ $EUID -ne 0 ]]; then
  echo_err "Please run as root: sudo $0"
  exit 1
fi

# 3) Detect post-reboot invocation
on_reboot=false
if [[ "${1-}" == "--on-reboot" ]]; then
  on_reboot=true
fi

if $on_reboot; then
  # Log both to console & reboot log
  exec > >(tee -a /var/log/frognet-reboot.log) 2> >(tee -a /var/log/frognet-reboot.log >&2)
  echo_info "=== Post-Reboot Initialization ==="

  # Load previous answers
  source "$ENV_FILE"

  # Run startup script in background
  for script in "${START_SCRIPT_NAMES[@]}"; do
    if [[ -x "$SCRIPT_DIR/$script" ]]; then
      echo_info "Launching $script in background..."
      nohup "$SCRIPT_DIR/$script" > /var/log/frognet-start.log 2>&1 &
      echo_info "Output being captured to /var/log/frognet-start.log"
      break
    fi
  done

  # Remove cron entry
  (crontab -l 2>/dev/null | grep -v "$0 --on-reboot") | crontab -
  echo_info "Cron entry cleaned up."
  echo_info "Post-reboot steps complete."
  exit 0
fi

# --- User Prompts with Detailed Explanations ---
# 4.1) Network Interface
#    This should be the interface connected to your upstream network
#    (e.g., Ethernet or Wi-Fi) that FrogNet uses for internet access.
DEFAULT_IFACE=$(ip route 2>/dev/null | awk '/^default/ {print $5; exit}')
read -rp "Network interface to use (connected to upstream or LAN) [default: $DEFAULT_IFACE]: " iface_input
FROGNET_INTERFACE=${iface_input:-$DEFAULT_IFACE}

# 4.2) Admin Username
#    The local user account that will own FrogNet services
#    (usually the user you log in as).
default_user=${SUDO_USER:-$(whoami)}
read -rp "Admin username to configure (services run as this user) [default: $default_user]: " user_input
FROGNET_USERNAME=${user_input:-$default_user}

# 4.3) FrogNet Domain (FQDN)
#    The fully-qualified domain name this node will respond to
#    (e.g., frognet.local or your.custom.domain). 
read -rp "FrogNet domain (FQDN) for this node [default: frognet.local]: " domain_input
FROGNET_DOMAIN=${domain_input:-frognet.local}

# 4.4) Node IP Address
#    The static IP address on the FrogNet subnet that this node will use.
#    It must not conflict with other devices on the 192.168.1.0/24 network
#    unless you have customized your FrogNet subnet.
read -rp "Node IP on FrogNet network (e.g., 192.168.1.100) [default: 192.168.1.100]: " ip_input
FROGNET_NODE_IP=${ip_input:-192.168.1.100}

# 5) Save answers to .env file
cat > "$ENV_FILE" <<EOF
FROGNET_INTERFACE="$FROGNET_INTERFACE"
FROGNET_USERNAME="$FROGNET_USERNAME"
FROGNET_DOMAIN="$FROGNET_DOMAIN"
FROGNET_NODE_IP="$FROGNET_NODE_IP"
EOF

echo_info "Configuration saved to $ENV_FILE"

# 6) Ensure prerequisite packages installed
missing=()
for pkg in "${REQUIRED_PKGS[@]}"; do
  dpkg -s "$pkg" &>/dev/null || missing+=("$pkg")
done
if (( ${#missing[@]} )); then
  echo_info "Installing missing packages: ${missing[*]}"
  apt-get update && apt-get install -y "${missing[@]}"
else
  echo_info "All prerequisite packages are already installed."
fi

# 7) Extract bundled software
if [[ -f "$TARBALL" ]]; then
  echo_info "Extracting $(basename "$TARBALL") to root directory..."
  tar xvf "$TARBALL" -C /
else
  echo_err "Could not find tarball $(basename "$TARBALL") in $SCRIPT_DIR"
  exit 1
fi

# 8) Patch interface mapping script
if [[ -f "$MAP_SCRIPT" ]]; then
  sed -i "s/eth0\|ens33\|ens34\|eth1/$FROGNET_INTERFACE/g" "$MAP_SCRIPT"
  echo_info "Updated network interface in $MAP_SCRIPT"
else
  echo_warn "$MAP_SCRIPT missing; skipping interface mapping"
fi

# 9) Schedule post-reboot actions
( crontab -l 2>/dev/null || true; echo "@reboot $0 --on-reboot" ) | crontab -
echo_info "Scheduled post-reboot startup via cron"

# 10) Final step: reboot
echo_info "Setup complete. Rebooting now to apply all changes..."
reboot
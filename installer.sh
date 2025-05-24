#!/usr/bin/env bash
# installFrog.sh - FrogNet Node Installer
# Clones and configures a FrogNet node on Debian-based systems.
set -euo pipefail

# Color codes
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
RESET="\033[0m"

# --- Configuration ---
# Packages required by FrogNet
REQUIRED_PKGS=(
  apache2 php jq iptables php-cgi network-manager dnsmasq inotify-tools python3 openssh-server net-tools
)

# 1) Verify Debian-based
if [[ ! -d /etc/apt || ! -f /etc/os-release ]]; then
  echo -e "${RED}ERROR:${RESET} This installer supports Debian/Ubuntu only."
  exit 1
fi

# 2) Require root
if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}ERROR:${RESET} Please run as root: sudo $0"
  exit 1
fi

# 3) Detect default network interface
DEFAULT_IFACE=$(ip route 2>/dev/null | awk '/default/ {print $5; exit}')
read -rp "Detected network interface is '$DEFAULT_IFACE'. Press Enter to use it or specify another: " IFACE_INPUT
FROGNET_INTERFACE=${IFACE_INPUT:-$DEFAULT_IFACE}

# 4) Determine admin username
DEFAULT_USER=${SUDO_USER:-$(whoami)}
read -rp "Enter the FrogNet admin user [default: $DEFAULT_USER]: " FROGNET_USERNAME
FROGNET_USERNAME=${FROGNET_USERNAME:-$DEFAULT_USER}

# 5) Read node settings
echo "\n--- FrogNet Node Settings ---"
read -rp "Enter the network domain (FQDN) this node will host [default: frognet.local]: " FROGNET_DOMAIN
FROGNET_DOMAIN=${FROGNET_DOMAIN:-frognet.local}
read -rp "Enter this node's IP on the FrogNet network [default: 192.168.1.100]: " FROGNET_NODE_IP
FROGNET_NODE_IP=${FROGNET_NODE_IP:-192.168.1.100}

# 6) Save configuration to .env
ENV_FILE="$(dirname "$0")/frognet.env"
cat > "$ENV_FILE" <<EOF
FROGNET_INTERFACE="$FROGNET_INTERFACE"
FROGNET_USERNAME="$FROGNET_USERNAME"
FROGNET_DOMAIN="$FROGNET_DOMAIN"
FROGNET_NODE_IP="$FROGNET_NODE_IP"
EOF
echo -e "${GREEN}[✓]${RESET} Saved config to $ENV_FILE"

# 7) Install prerequisites
MISSING=()
for pkg in "${REQUIRED_PKGS[@]}"; do
  dpkg -s "$pkg" &>/dev/null || MISSING+=("$pkg")
done
if [ ${#MISSING[@]} -gt 0 ]; then
  echo -e "${YELLOW}[!]${RESET} Installing missing packages: ${MISSING[*]}"
  apt-get update && apt-get install -y "${MISSING[@]}"
  echo -e "${GREEN}[✓]${RESET} Packages installed."
else
  echo -e "${GREEN}[✓]${RESET} All required packages already present."
fi

# 8) Extract release archive
TARBALL="installable_tar.tar"
if [[ -f "$TARBALL" ]]; then
  echo -e "${GREEN}[*]${RESET} Extracting $TARBALL to /"
  tar xvf "$TARBALL" -C /
else
  echo -e "${RED}[!]${RESET} $TARBALL not found in $(pwd)!"
  exit 1
fi

# 9) Update interface mapping script
MAP_SCRIPT="/usr/local/bin/mapInterface"
if [[ -f "$MAP_SCRIPT" ]]; then
  sed -i "s/eth0/${FROGNET_INTERFACE}/g" "$MAP_SCRIPT"
  echo -e "${GREEN}[✓]${RESET} Updated interface in $MAP_SCRIPT"
else
  echo -e "${YELLOW}[!]${RESET} $MAP_SCRIPT missing, skipping mapping."
fi

# 10) Add @reboot cronjob for any post-install commands
( crontab -l 2>/dev/null | grep -v restartInstaller.sh; echo "@reboot $0 --on-reboot" ) | crontab -

echo -e "${GREEN}[✓]${RESET} Queued post-reboot tasks via cron."

# 11) Handle post-reboot initialization
if [[ "${1:-}" == "--on-reboot" ]]; then
  echo -e "${GREEN}[*]${RESET} Running post-reboot setup..."
  REPO_DIR="${HOME}/installer"
  cd "$REPO_DIR"
  ./setup_lillypad.bash "$FROGNET_DOMAIN" "$FROGNET_NODE_IP"

  # Link files to /
  echo "${GREEN}[*]${RESET} Linking files to /"
  find . -type f -exec ln -sf {} / \

  # Clean up cron
  ( crontab -l 2>/dev/null | grep -v restartInstaller.sh ) | crontab -
  echo -e "${GREEN}[✓]${RESET} Post-reboot tasks complete."
  exit 0
fi

# 12) Final reboot
echo -e "${GREEN}[✓]${RESET} Initial install done. Rebooting now to apply changes..."
reboot
#!/bin/bash
set -e

# Colors
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
RESET="\033[0m"

# Fail early if system is not Debian-based
if [[ ! -d /etc/apt || ! -f /etc/os-release ]]; then
    echo -e "${RED}ERROR: Couldn't find '/etc/apt' or '/etc/os-release'.${RESET}"
    echo -e "${RED}This script is for Debian-based distributions using APT only.${RESET}"
    exit 1
fi

# Require root
if [[ $(id -u) -ne 0 ]]; then
    echo -e "${RED}ERROR: This script must be run as root or with sudo.${RESET}"
    echo -e "${YELLOW}Try: curl <SCRIPT_URL> | sudo bash${RESET}"
    exit 1
fi

# Get environment variables from the user
ENV_FILE="frognet.env"

echo -e "${GREEN}[*] Setting up FrogNet configuration...${RESET}"

# Prompt for network name
read -rp "Enter your FrogNet network name [default: FrogNet-001]: " NETWORK_NAME
NETWORK_NAME=${NETWORK_NAME:-FrogNet-001}

# Prompt for IP address
read -rp "Enter the IP address for this node [default: 192.168.1.100]: " NODE_IP
NODE_IP=${NODE_IP:-192.168.1.100}

# Determine default network interface
DEFAULT_IFACE=$(ip route | grep default | awk '{print $5}')
read -rp "Detected network interface is '$DEFAULT_IFACE'. Use this? [Y/n]: " IFACE_CONFIRM
if [[ "$IFACE_CONFIRM" =~ ^[Nn]$ ]]; then
  read -rp "Enter your network interface name (e.g., eth0, ens33): " CUSTOM_IFACE
  DEFAULT_IFACE=$CUSTOM_IFACE
fi

# Save to .env file
echo "FROGNET_NETWORK_NAME=\"$NETWORK_NAME\"" > "$ENV_FILE"
echo "FROGNET_NODE_IP=\"$NODE_IP\"" >> "$ENV_FILE"
echo "FROGNET_INTERFACE=\"$DEFAULT_IFACE\"" >> "$ENV_FILE"

echo -e "${GREEN}[*] Configuration saved to $ENV_FILE${RESET}"


REQUIREMENTS_FILE="./requirements.txt"
REQUIRED_PKGS=()

echo -e "${GREEN}[*] Parsing requirements...${RESET}"
while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line%%#*}"                 # strip inline comments
  line="$(echo "$line" | xargs)"     # trim
  [ -n "$line" ] && REQUIRED_PKGS+=("$line")
done < "$REQUIREMENTS_FILE"

echo -e "${GREEN}[*] Checking installed packages...${RESET}"
MISSING_PKGS=()
for pkg in "${REQUIRED_PKGS[@]}"; do
  dpkg -s "$pkg" &>/dev/null || MISSING_PKGS+=("$pkg")
done

if [ "${#MISSING_PKGS[@]}" -eq 0 ]; then
  echo -e "${GREEN}[✓] All packages already installed.${RESET}"
else
  echo -e "${YELLOW}[!] Missing packages: ${MISSING_PKGS[*]}${RESET}"
  echo -e "${GREEN}[>] Installing with: sudo apt-get install -y ${MISSING_PKGS[*]}${RESET}"
  apt-get update
  apt-get install -y "${MISSING_PKGS[@]}"

  if [ $? -eq 0 ]; then
    echo -e "${GREEN}[✓] All packages installed successfully.${RESET}"
  else
    echo -e "${RED}[!] Failed to install packages.${RESET}"
    exit 1
  fi
fi

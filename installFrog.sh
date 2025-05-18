#!/bin/bash
#  _______                                            _             _                             _              
# (_______)                             _      _     | |           | |                _          (_)             
#  _____  _____  _ _ _   ____  _____  _| |_  _| |_   | | ____    __| | _   _   ___  _| |_   ____  _  _____   ___ 
# |  ___)(____ || | | | / ___)| ___ |(_   _)(_   _)  | ||  _ \  / _  || | | | /___)(_   _) / ___)| || ___ | /___)
# | |    / ___ || | | |( (___ | ____|  | |_   | |_   | || | | |( (_| || |_| ||___ |  | |_ | |    | || ____||___ |
# |_|    \_____| \___/  \____)|_____)   \__)   \__)  |_||_| |_| \____||____/ (___/    \__)|_|    |_||_____)(___/ 
                                                                                                               
set -e

# Colors for vanity ;)
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
RESET="\033[0m"

# Fail early if system is not Debian-based
if [[ ! -d /etc/apt || ! -f /etc/os-release ]]; then
    echo -e "${RED}ERROR:${RESET} Couldn't find '/etc/apt' or '/etc/os-release'."
    echo -e "${RED}ERROR:${RESET} This script is for Debian-based distributions using APT only."
    exit 1
fi

# Require root
if [[ $(id -u) -ne 0 ]]; then
    echo -e "${RED}ERROR:${RESET} This script must be run as root or with sudo."
    echo -e "${YELLOW}[!]${RESET} Try: curl <SCRIPT_URL> | sudo bash"
    exit 1
fi

# Check for eth0
if ! ip link show eth0 &>/dev/null; then
    echo -e "${YELLOW}[!]${RESET} Interface 'eth0' not found. System may use a different name (e.g., enp0s3 or ens33)."
fi

# Get environment variables from the user
ENV_FILE="frognet.env"

echo -e "${GREEN}[*]${RESET} Setting up FrogNet configuration..."

read -rp "Enter your FrogNet network name [default: FrogNet-001]: " NETWORK_NAME
NETWORK_NAME=${NETWORK_NAME:-FrogNet-001}

read -rp "Enter the IP address for this node [default: 192.168.1.100]: " NODE_IP
NODE_IP=${NODE_IP:-192.168.1.100}

DEFAULT_IFACE=$(ip route | grep default | awk '{print $5}')
read -rp "Detected network interface is '$DEFAULT_IFACE'. Use this? [Y/n]: " IFACE_CONFIRM
if [[ "$IFACE_CONFIRM" =~ ^[Nn]$ ]]; then
    read -rp "Enter your network interface name (e.g., eth0, ens33): " CUSTOM_IFACE
    DEFAULT_IFACE=$CUSTOM_IFACE
fi

echo "FROGNET_NETWORK_NAME=\"$NETWORK_NAME\"" > "$ENV_FILE"
echo "FROGNET_NODE_IP=\"$NODE_IP\"" >> "$ENV_FILE"
echo "FROGNET_INTERFACE=\"$DEFAULT_IFACE\"" >> "$ENV_FILE"

echo -e "${GREEN}[*]${RESET} Configuration saved to $ENV_FILE"

# Parse requirements.txt
REQUIREMENTS_FILE="./requirements.txt"
REQUIRED_PKGS=()

echo -e "${GREEN}[*]${RESET} Parsing requirements..."
while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"                 # strip inline comments
    line="$(echo "$line" | xargs)"     # trim
    [ -n "$line" ] && REQUIRED_PKGS+=("$line")
done < "$REQUIREMENTS_FILE"

echo -e "${GREEN}[*]${RESET} Checking installed packages..."
MISSING_PKGS=()
for pkg in "${REQUIRED_PKGS[@]}"; do
    dpkg -s "$pkg" &>/dev/null || MISSING_PKGS+=("$pkg")
done

if [ "${#MISSING_PKGS[@]}" -eq 0 ]; then
    echo -e "${GREEN}[✓]${RESET} All packages already installed."
else
    echo -e "${YELLOW}[!]${RESET} Missing packages: ${MISSING_PKGS[*]}"
    echo -e "${GREEN}[>]${RESET} Installing with: sudo apt-get install -y ${MISSING_PKGS[*]}"
    apt-get update
    apt-get install -y "${MISSING_PKGS[@]}"

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[✓]${RESET} All packages installed successfully."
    else
        echo -e "${RED}[!]${RESET} Failed to install packages."
        exit 1
    fi
fi

# Add @reboot cron entry for restartInstaller.sh
CRON_JOB="@reboot /usr/local/bin/restartInstaller.sh"
if ! crontab -l 2>/dev/null | grep -q "restartInstaller.sh"; then
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    echo -e "${GREEN}[*]${RESET} Added one-time @reboot cron job for restartInstaller.sh"
else
    echo -e "${YELLOW}[!]${RESET} @reboot cron job already exists."
fi

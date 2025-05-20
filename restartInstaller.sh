#!/bin/bash
set -euo pipefail

# Clean cronjob
crontab -l | grep -v 'restartInstaller.sh' | crontab -
echo "[✓] Cronjob cleaned up."

LOG_FILE="/var/log/frognet-restart.log"
exec >> "$LOG_FILE" 2>&1

echo "========== $(date) Restart Phase =========="

# Load config
ENV_FILE="/root/frognet.env"
if [ -f "$ENV_FILE" ]; then
  source "$ENV_FILE"
else
  echo "[!] frognet.env not found at $ENV_FILE. Aborting."
  exit 1
fi

echo "[*] Running with user: $FROGNET_USERNAME"

REQUIRED_PKGS=(apache2 php php-cgi network-manager dnsmasq inotify-tools python3 openssh-server net-tools)
MISSING_PKGS=()

for pkg in "${REQUIRED_PKGS[@]}"; do
  dpkg -s "$pkg" &>/dev/null || MISSING_PKGS+=("$pkg")
done

if [ "${#MISSING_PKGS[@]}" -gt 0 ]; then
  echo "[!] Installing: ${MISSING_PKGS[*]}"
  apt-get update
  apt-get install -y "${MISSING_PKGS[@]}"
fi

# Tarball install
INSTALL_TAR="/root/installable_tar.tar"
if [ -f "$INSTALL_TAR" ]; then
  echo "[*] Extracting tarball..."
  tar xvf "$INSTALL_TAR" -C /
else
  echo "[!] Tarball not found at $INSTALL_TAR. Aborting."
  exit 1
fi
#update network IF names in mapInterface file
echo "[*] Updating network interface names..."
sed -i "s/ens33/$DEFAULT_IFACE/g" /etc/frognet/mapInterface
./setupLily.sh
echo "[*] Setting up Lilypad..."

echo "[*] Linking files..."
find "$REPO_DIR" -type f -exec ln -sf {} / \;


echo "========== Setup complete =========="
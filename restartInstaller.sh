#!/bin/bash
set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# remove cron entry
crontab -l | grep -v restartInstaller.sh | crontab -
echo "[✓] Cronjob cleaned up."

LOG_FILE=/var/log/frognet-restart.log
exec >>"$LOG_FILE" 2>&1
echo "==== $(date) Restart Phase ===="

# load config
source /~/frognet/frognet.env

# map interface
if [ -f /etc/frognet/mapInterface ]; then
  sed -i "s/ens33/${FROGNET_INTERFACE}/g" /etc/frognet/mapInterface
  echo "[✓] Interface mapped to ${FROGNET_INTERFACE}"
else
  echo "[!] mapInterface not found, skipping"
fi

# cd into FrogNet dir
REPO_DIR=~/frognet    
cd "$REPO_DIR"

# run the lilypad setup
echo "[*] Running setup_lillypad..."
./setup_lillypad.bash "$FROGNET_DOMAIN" "$FROGNET_NODE_IP"

# Reboot again
# echo "[*] Rebooting to apply changes..."
reboot

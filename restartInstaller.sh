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

# --- Port 53 Conflict Resolution ---
if lsof -i :53 | grep -q systemd-resolve; then
  echo_warn "Port 53 in use by systemd-resolved. Disabling it..."
  systemctl stop systemd-resolved
  systemctl disable systemd-resolved
  rm -f /etc/resolv.conf
  echo "nameserver 1.1.1.1" > /etc/resolv.conf
fi

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

# --- Schedule Post-Reboot Task ---
INSTALLER=$(readlink -f "$0")
echo "@reboot $INSTALLER --on-reboot" | { crontab -l 2>/dev/null || true; cat; } | crontab -
echo_info "Scheduled post-reboot startup via cron"

# --- Handle Reboot Flag ---
on_reboot=false
if [[ "${1-}" == "--on-reboot" ]]; then
  on_reboot=true
fi

if \$on_reboot; then
  exec > >(tee -a /var/log/frognet-reboot.log) 2> >(tee -a /var/log/frognet-reboot.log >&2)
  echo_info "=== Post-Reboot Initialization ==="
  source "$ENV_FILE"
  for name in "${START_SCRIPT_NAMES[@]}"; do
    if [[ -x "$SCRIPT_DIR/$name" ]]; then
      echo_info "Invoking $name..."
      nohup "$SCRIPT_DIR/$name" > /var/log/frognet-start.log 2>&1 &
      break
    fi
  done
  ( crontab -l 2>/dev/null | grep -v "$0 --on-reboot" ) | crontab -
  echo_info "Post-reboot startup complete."
  exit 0
fi

# --- Final Step ---
echo_info "Initial setup complete. Rebooting now to apply changes..."
reboot


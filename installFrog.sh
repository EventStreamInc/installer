#!/bin/bash
set -e

REQUIREMENTS_FILE="./requirements.txt"
REQUIRED_PKGS=()

echo "[*] Parsing requirements..."
while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line%%#*}"                 # strip inline comments
  line="$(echo "$line" | xargs)"     # trim
  [ -n "$line" ] && REQUIRED_PKGS+=("$line")
done < requirements.txt

echo "[*] Checking installed packages..."
MISSING_PKGS=()
for pkg in "${REQUIRED_PKGS[@]}"; do
  dpkg -s "$pkg" &>/dev/null || MISSING_PKGS+=("$pkg")
done

if [ "${#MISSING_PKGS[@]}" -eq 0 ]; then
  echo "[✓] All packages already installed."
else
  echo "[!] Missing packages: ${MISSING_PKGS[*]}"
  echo "[>] Installing with: sudo apt-get install -y ${MISSING_PKGS[*]}"
  sudo apt-get update
  sudo apt-get install -y "${MISSING_PKGS[@]}"

  if [ $? -eq 0 ]; then
    echo "[✓] All packages installed successfully."
  else
    echo "[!] Failed to install packages."
    exit 1
  fi
fi

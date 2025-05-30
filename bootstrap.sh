#!/usr/bin/env bash
# bootstrap.sh - FrogNet Bootstrap Installer
# Usage: curl -fsSL https://raw.githubusercontent.com/EventStreamInc/installer/jeremy/bootstrap.sh | sudo bash
#
# This script:
# 1. Verifies system requirements
# 2. Downloads the full installer package
# 3. Launches the main installer
#
set -euo pipefail

# --- Constants -------------------------------------------------------------
GITHUB_REPO="EventStreamInc/installer"
GITHUB_BRANCH="jeremy"
TEMP_DIR="/tmp/frognet-install"
INSTALLER_URL="https://github.com/${GITHUB_REPO}/archive/${GITHUB_BRANCH}.tar.gz"

# --- Helper Functions -----------------------------------------------------
echo_err() {
  echo -e "\033[1;31mERROR:\033[0m $*" >&2
  exit 1
}

echo_info() {
  echo -e "\033[1;32m[*]\033[0m $*"
}

echo_warn() {
  echo -e "\033[1;33m[!]\033[0m $*"
}

# --- Pre-flight Checks ---------------------------------------------------
echo_info "FrogNet Bootstrap Installer"
echo_info "=========================="

# Check if running as root
if (( EUID != 0 )); then
  echo_err "Must be run as root. Please re-run with: curl -fsSL https://raw.githubusercontent.com/EventStreamInc/installer/jeremy/bootstrap.sh | sudo bash"
fi

# Check OS compatibility
if [[ ! -f /etc/os-release ]]; then
  echo_err "This installer only supports Debian/Ubuntu systems."
fi

source /etc/os-release
if [[ "$ID" != "debian" && "$ID" != "ubuntu" && "$ID" != "raspbian" ]]; then
  echo_err "Unsupported OS: $ID. This installer supports Debian, Ubuntu, and Raspbian only."
fi

echo_info "Detected OS: $PRETTY_NAME"

# Check for required tools
for tool in curl tar; do
  if ! command -v "$tool" &>/dev/null; then
    echo_info "Installing missing tool: $tool"
    apt-get update -qq
    apt-get install -y "$tool"
  fi
done

# --- Download Main Installer ---------------------------------------------
echo_info "Downloading FrogNet installer from GitHub..."

# Clean up any previous installation attempts
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR"

# Download and extract
if ! curl -fsSL "$INSTALLER_URL" | tar -xz -C "$TEMP_DIR" --strip-components=1; then
  echo_err "Failed to download installer from $INSTALLER_URL"
fi

echo_info "Download complete."

# --- Launch Main Installer -----------------------------------------------
MAIN_INSTALLER="$TEMP_DIR/install.sh"

if [[ ! -f "$MAIN_INSTALLER" ]]; then
  echo_err "Main installer script not found at $MAIN_INSTALLER"
fi

echo_info "Launching main installer..."
chmod +x "$MAIN_INSTALLER"

# Pass any arguments to the main installer
exec "$MAIN_INSTALLER" "$@"
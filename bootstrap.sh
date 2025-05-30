#!/usr/bin/env bash
# bootstrap.sh - FrogNet Bootstrap Installer
# Usage: curl -fsSL https://raw.githubusercontent.com/EventStreamInc/installer/jeremy/bootstrap.sh | sudo bash
# Alternative: wget -qO- https://raw.githubusercontent.com/EventStreamInc/installer/jeremy/bootstrap.sh | sudo bash
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
REPO_URL="https://github.com/${GITHUB_REPO}.git"

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

# Check for required tools and install if missing
echo_info "Checking for required tools..."

for tool in git; do
  if ! command -v "$tool" &>/dev/null; then
    echo_info "Installing missing tool: $tool"
    apt-get update -qq
    apt-get install -y "$tool"
  fi
done

echo_info "All required tools are available."

# --- Clone Repository -----------------------------------------------------
echo_info "Cloning FrogNet installer repository..."

# Clean up any previous installation attempts
rm -rf "$TEMP_DIR"

# Clone the repository
if ! git clone --branch "$GITHUB_BRANCH" --depth 1 "$REPO_URL" "$TEMP_DIR"; then
  echo_err "Failed to clone repository from $REPO_URL (branch: $GITHUB_BRANCH)"
fi

echo_info "Repository cloned successfully."

# --- Launch Main Installer -----------------------------------------------
MAIN_INSTALLER="$TEMP_DIR/installer.sh"

if [[ ! -f "$MAIN_INSTALLER" ]]; then
  echo_err "Main installer script not found at $MAIN_INSTALLER"
fi

echo_info "Launching main installer..."
chmod +x "$MAIN_INSTALLER"

# Pass any arguments to the main installer
exec "$MAIN_INSTALLER" "$@"
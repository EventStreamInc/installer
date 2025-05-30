# 🐸 FrogNet Installer

This script sets up a FrogNet node on a compatible Debian or Ubuntu machine.

---

## Requirements

- A Linux system with:
  - One Ethernet port
  - One other internet connection (Wi-Fi or other)
- A router in **Access Point (Gateway/Passive)** mode
- Internet access during install (Upstream)

Tested on:
- Raspberry Pi 4b

---

## What It Installs

The script installs:
- Apache2 with PHP and CGI
- NetworkManager
- dnsmasq
- Python3
- inotify-tools
- openssh-server
- net-tools

---

## Installation

```bash
git clone -b jeremy https://github.com/EventStreamInc/FrogNetHost.git
cd installer
chmod +x installer.sh
sudo ./installer.sh

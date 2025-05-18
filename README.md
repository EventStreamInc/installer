# 🐸 FrogNet Installer

This script sets up a FrogNet node on a compatible Linux machine.

---

## Requirements

- A Linux system with:
  - One Ethernet port
  - One other internet connection (Wi-Fi or USB Ethernet)
- A router in **Access Point (Gateway/Passive)** mode
- Internet access during install

Tested on:
- Raspberry Pi 4
- Intel NUC

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
git clone https://github.com/EventStreamInc/FrogNetHost.git
cd FrogNetHost
chmod +x installer.sh
sudo ./installer.sh

# 🐸 FrogNet Installer

##  Copyright (c) 2025, Fawcett Innovations, LLC              
#  All Rights Reserved                                       

This software is proprietary and confidential.            
Unauthorized copying, distribution, or use of this        
code, via any medium, is strictly prohibited.             
   If you wish to license this software or use it in a       
For commercial or non-commercial projects, please contact:  
[contact@fawcettinnovations.com](mailto:contact@fawcettinnovations.com)

---

## 🛠 Requirements

- A Linux system with:
  - One **Ethernet port**
  - One other **internet-connected interface** (Wi-Fi or USB Ethernet)
- A router in **Access Point (Gateway/Passive)** mode
- Active **internet connection** during installation (Upstream)

Tested on:
- ✅ Raspberry Pi 4 (Rasberry Pi mini)

---

## 🚀 One-Line Installation

If you want the fastest setup and trust this repo, run:

```bash
curl -fsSL https://raw.githubusercontent.com/EventStreamInc/installer/jeremy/bootstrap.sh | sudo bash
```


This will:
1. Verify your OS and root permissions
2. Install required packages
3. Clone the FrogNet installer repository
4. Extract all files directly into `/`
5. Prompt for configuration values
6. Apply network changes immediately
6.5 You will need to insert the eth0 cord into the access point at this time.
8. Reboot your system after 30 seconds


⚠️⚠️⚠️ **Warning:** This script writes files directly into your root filesystem (`/`). Do not run on a production system unless you've reviewed the code and tarball contents. ⚠️⚠️⚠️

---

## 🐢 Manual Installation (Advanced Users)

If you prefer to inspect and run the installer manually:

```bash
git clone https://github.com/EventStreamInc/installer.git
cd installer
chmod +x installer.sh
sudo ./installer.sh
```

This will perform the same setup process interactively.

---

## 📦 What It Installs

The installer sets up:

- Apache2 with PHP + CGI
- NetworkManager
- dnsmasq
- iptables
- hostapd (for Wi-Fi AP support)
- Python 3
- inotify-tools
- openssh-server
- net-tools
- bridge-utils

All configuration is stored in:

```
/etc/frognet/frognet.env
```

Log file (for debugging):

```
/var/log/frognet-install.log
```

---

## ✅ After Installation

Once installed, your system will reboot and begin acting as a FrogNet node.

The Ethernet port will serve IP addresses via DHCP. The upstream interface will share internet access to connected clients.

You can modify the configuration at any time by editing `/etc/frognet/frognet.env`.

---
###  Copyright (c) 2025, Fawcett Innovations, LLC              
###  All Rights Reserved        

##FrogNet Installer

This package contains everything you need to install and configure a FrogNet node on a Debian/Ubuntu-based system.

Contents

installer.sh — Main bootstrap script

Prerequisites

A Debian-based distribution (Debian, Ubuntu)

sudo or root access

An empty directory to unzip this package into

Quick Start

Unzip the downloaded .zip into an empty folder:

unzip FrogNet-Installer-vX.Y.zip -d frognet-installer
cd frognet-installer

Make the installer executable:

chmod +x installer.sh

Run the installer (as root):

sudo ./installer.sh

The script will guide you through:

Selecting your network interface (upstream/Wi‑Fi)

Choosing an admin username

Defining the FrogNet domain (FQDN)

Assigning a static IP on the FrogNet subnet

Reboot — the installer automatically schedules a post-boot startup:

# The script will reboot for you, or you can run:
sudo reboot

Verify

Check /var/log/frognet-reboot.log for the installer’s reboot-phase logs.

Check /var/log/frognet-start.log for the FrogNet startup script output.

Your node should now advertise the configured FQDN on the FrogNet network.

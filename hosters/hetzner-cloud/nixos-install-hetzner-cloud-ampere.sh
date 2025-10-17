#! /usr/bin/env bash

# Script to install NixOS from the Hetzner Cloud NixOS bootable ISO image.
# (tested with Hetzner's `NixOS 25.05 (ampere)` ISO image).
#
# This script wipes the disk of the server!
#
# Instructions:
#
# 1. Mount the above mentioned ISO image from the Hetzner Cloud GUI
#    and reboot the server into it; do not run the default system (e.g. Ubuntu).
# 2. To be able to SSH straight in (recommended), you must replace hardcoded pubkey
#    further down in the section labelled "Replace this by your SSH pubkey" by you own,
#    and host the modified script way under a URL of your choosing
#    (e.g. gist.github.com with git.io as URL shortener service).
# 3. Run on the server:
#
#       # Replace this URL by your own that has your pubkey in
#       curl -L https://raw.githubusercontent.com/nix-community/nixos-install-scripts/master/hosters/hetzner-cloud/nixos-install-hetzner-cloud-ampere.sh | sudo bash
#
#    This will install NixOS and power off the server.
# 4. Unmount the ISO image from the Hetzner Cloud GUI.
# 5. Turn the server back on from the Hetzner Cloud GUI.
#
# To run it from the Hetzner Cloud web terminal without typing it down,
# you can either select it and then middle-click onto the web terminal, (that pastes
# to it), or use `xdotool` (you have e.g. 3 seconds to focus the window):
#
#     sleep 3 && xdotool type --delay 50 'curl YOUR_URL_HERE | sudo bash'
#
# (In the xdotool invocation you may have to replace chars so that
# the right chars appear on the US-English keyboard.)
#
# If you do not replace the pubkey, you'll be running with my pubkey, but you can
# change it afterwards by logging in via the Hetzner Cloud web terminal as `root`
# with empty password.

set -e

if [ -z "$SSH_KEY" ]; then
    echo "Error: SSH_KEY is unset or empty!" >&2
    exit 1
fi

umount /dev/sda1 || true
umount /dev/sda2 || true


# Determine the correct disk device
DISK="/dev/vda"
if [ ! -b "$DISK" ]; then
    DISK="/dev/sda"
fi

if [ ! -b "$DISK" ]; then
    echo "Error: Could not find disk device"
    exit 1
fi

echo "Using disk: $DISK"

# Wipe and create new partition table
sgdisk -Z "$DISK"
sgdisk -n 1:0:+512M -t 1:ef00 "$DISK"  # EFI System Partition
sgdisk -n 2:0:0 -t 2:8300 "$DISK"      # Linux root partition
partprobe "$DISK"

# Format partitions
mkfs.vfat -F32 "${DISK}1"  # EFI partition
mkfs.ext4 -F "${DISK}2"     # Root partition

# Mount partitions
mount "${DISK}2" /mnt
mkdir -p /mnt/boot
mount "${DISK}1" /mnt/boot

nixos-generate-config --root /mnt

# Delete trailing `}` from `configuration.nix`
sed -i -E 's:^\}\s*$::g' /mnt/etc/nixos/configuration.nix

# Comment out the default boot loader settings, they are incorrect
sed -i '/boot.loader/d' /mnt/etc/nixos/configuration.nix

# Extend/override default `configuration.nix`:
cat >> /mnt/etc/nixos/configuration.nix <<EOF
  # EFI boot loader for ARM
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = false;
  boot.loader.efi.efiSysMountPoint = "/boot";

  # Disable GRUB
  boot.loader.grub.enable = false;

  # Initial empty root password for easy login:
  users.users.root.initialHashedPassword = "";
  services.openssh.settings.PermitRootLogin = "prohibit-password";

  services.openssh.enable = true;

  users.users.root.openssh.authorizedKeys.keys = [
    "$SSH_KEY"
  ];
}
EOF

nixos-install --no-root-passwd

poweroff

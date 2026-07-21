#!/bin/sh
# Runs as root inside the NixOS installer environment (typed in by
# scripts/install.ws from the NIXSETUP media ISO). Partitions the
# virtio disk GPT/UEFI, installs with the configuration.nix shipped on
# the same ISO, and powers off so the build can seal the disk.
set -eux

parted -s /dev/vda -- mklabel gpt \
  mkpart ESP fat32 1MiB 513MiB \
  set 1 esp on \
  mkpart root ext4 513MiB 100%

mkfs.fat -F 32 -n BOOT /dev/vda1
mkfs.ext4 -F -L nixos /dev/vda2

# Mount by device node — the by-label symlinks may not exist yet right
# after mkfs (udev race), which would abort the script under set -e.
mount /dev/vda2 /mnt
mkdir -p /mnt/boot
mount /dev/vda1 /mnt/boot

nixos-generate-config --root /mnt
# Keep the generated hardware-configuration.nix; replace the system config
# with ours (guest agent, vmlab user, ssh).
cp "$(dirname "$0")/configuration.nix" /mnt/etc/nixos/configuration.nix

nixos-install --no-root-passwd

# Stage the vmlab guest agent binary from the VMLAB bootstrap ISO (the
# systemd unit is declared in configuration.nix; it starts on first boot,
# and the build verifies the handshake with an extra boot after sealing
# the install).
mkdir -p /media/vmlab
if ! mount -o ro LABEL=VMLAB /media/vmlab; then
  for d in /dev/sr0 /dev/sr1 /dev/sr2; do
    mount -o ro "$d" /media/vmlab 2>/dev/null || continue
    [ -e /media/vmlab/install.sh ] && break
    umount /media/vmlab
  done
fi
mkdir -p /mnt/usr/local/lib/vmlab
cp "/media/vmlab/linux/$(uname -m)/vmlab-agent" /mnt/usr/local/lib/vmlab/vmlab-agent
chmod 0755 /mnt/usr/local/lib/vmlab/vmlab-agent
umount /media/vmlab

poweroff

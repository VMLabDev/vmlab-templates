#!/bin/sh
# Runs as root inside the NixOS installer environment (typed in by
# scripts/install.wisp from the NIXSETUP media ISO). Partitions the
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

poweroff

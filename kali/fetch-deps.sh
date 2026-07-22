#!/bin/sh
# Download + verify + extract the official Kali QEMU image into disk/, then
# inject the vmlab-agent first-boot bootstrap.
#
# Kali distributes the image as a 7z archive, which vmlab's URL sources
# cannot unpack — so this script stages the raw qcow2 for vmlab.wcl's
# `source "qcow2" { path = "./disk/kali.qcow2" }`.
#
# Kali's prebuilt QEMU image has no cloud-init or unattended-install hook, so
# nothing would run the VMLAB bootstrap ISO's install.sh on its own — and the
# build's agent verification blocks *before* the provision script can. We
# therefore offline-inject a virt-customize firstboot command that mounts the
# VMLAB ISO (attached during the build) and runs its installer, so vmlab-agent
# is up and answering by the time the build verifies it. The install bakes the
# agent into the sealed image, so clones come up "ready" too.
set -eu

VERSION="2026.1"
ARCHIVE="kali-linux-${VERSION}-qemu-amd64.7z"
URL="https://cdimage.kali.org/kali-${VERSION}/${ARCHIVE}"
SHA256="efce2da10c775da5f58954166f633d5da9115e29663731dcb65d616f19d966f4"

cd "$(dirname "$0")"
mkdir -p disk

if [ ! -f disk/kali.qcow2 ]; then
    if [ ! -f "disk/${ARCHIVE}" ]; then
        echo "downloading ${URL} ..."
        curl -L --fail -o "disk/${ARCHIVE}.part" "$URL"
        mv "disk/${ARCHIVE}.part" "disk/${ARCHIVE}"
    fi

    echo "${SHA256}  disk/${ARCHIVE}" | sha256sum -c -

    echo "extracting ..."
    7z x -odisk -y "disk/${ARCHIVE}" >/dev/null
    QCOW2="$(find disk -name '*.qcow2' ! -name kali.qcow2 | head -n1)"
    [ -n "$QCOW2" ] || { echo "no qcow2 found in the archive" >&2; exit 1; }
    mv "$QCOW2" disk/kali.qcow2
    rm -f "disk/${ARCHIVE}"
    find disk -mindepth 1 -type d -empty -delete
    echo "staged disk/kali.qcow2"
fi

# Bake a one-shot first-boot bootstrap that installs vmlab-agent from the
# VMLAB ISO the build attaches. virt-customize runs it once, then removes it;
# the install itself persists into the sealed image for clones.
if [ ! -f disk/.agent-injected ]; then
    echo "injecting vmlab-agent first-boot bootstrap into disk/kali.qcow2 ..."
    virt-customize -a disk/kali.qcow2 --firstboot-command \
      'mkdir -p /media/vmlab; mounted=; if mount -o ro LABEL=VMLAB /media/vmlab 2>/dev/null; then mounted=1; else for d in /dev/sr0 /dev/sr1 /dev/sr2 /dev/vdb /dev/vdc /dev/vdd; do mount -o ro "$d" /media/vmlab 2>/dev/null || continue; if [ -e /media/vmlab/install.sh ]; then mounted=1; break; fi; umount /media/vmlab 2>/dev/null || true; done; fi; [ -n "$mounted" ] && sh /media/vmlab/install.sh; umount /media/vmlab 2>/dev/null || true'
    touch disk/.agent-injected
    echo "vmlab-agent bootstrap injected"
fi

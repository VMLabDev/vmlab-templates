#!/bin/sh
# Download + verify + extract the official Parrot Security QEMU image
# into disk/, then inject the vmlab-agent first-boot bootstrap.
#
# Parrot distributes it compressed with xz, which vmlab's URL sources cannot unpack —
# so this script stages the raw qcow2 for vmlab.wcl's
# `source "qcow2" { path = "./disk/parrot.qcow2" }`.
#
# Parrot's prebuilt QEMU image has no cloud-init or unattended-install hook, so
# nothing would run the VMLAB bootstrap ISO's install.sh on its own — and the
# build's agent verification blocks *before* the provision script can. We
# therefore offline-inject a virt-customize firstboot command that mounts the
# VMLAB ISO (attached during the build) and runs its installer, so vmlab-agent
# is up and answering by the time the build verifies it. The install bakes the
# agent into the sealed image, so clones come up "ready" too.
set -eu

VERSION="7.4"
ARCHIVE="Parrot-security-${VERSION}_amd64.qcow2.xz"
URL="https://deb.parrot.sh/parrot/iso/${VERSION}/${ARCHIVE}"
SHA256="2cd864cd528e166840775792f39f141cffa3dc770faadea7d9adbb049fc1ec52"

cd "$(dirname "$0")"
mkdir -p disk

if [ ! -f disk/parrot.qcow2 ]; then
    if [ ! -f "disk/${ARCHIVE}" ]; then
        echo "downloading ${URL} ..."
        curl -L --fail -o "disk/${ARCHIVE}.part" "$URL"
        mv "disk/${ARCHIVE}.part" "disk/${ARCHIVE}"
    fi

    echo "${SHA256}  disk/${ARCHIVE}" | sha256sum -c -

    echo "extracting ..."
    xz -dc "disk/${ARCHIVE}" >disk/parrot.qcow2.part
    mv disk/parrot.qcow2.part disk/parrot.qcow2
    rm -f "disk/${ARCHIVE}"
    echo "staged disk/parrot.qcow2"
fi

# Bake a one-shot first-boot bootstrap that installs vmlab-agent from the
# VMLAB ISO the build attaches. virt-customize runs it once, then removes it;
# the install itself persists into the sealed image for clones.
if [ ! -f disk/.agent-injected ]; then
    echo "injecting vmlab-agent first-boot bootstrap into disk/parrot.qcow2 ..."
    virt-customize -a disk/parrot.qcow2 --firstboot-command \
      'mkdir -p /media/vmlab; mounted=; if mount -o ro LABEL=VMLAB /media/vmlab 2>/dev/null; then mounted=1; else for d in /dev/sr0 /dev/sr1 /dev/sr2 /dev/vdb /dev/vdc /dev/vdd; do mount -o ro "$d" /media/vmlab 2>/dev/null || continue; if [ -e /media/vmlab/install.sh ]; then mounted=1; break; fi; umount /media/vmlab 2>/dev/null || true; done; fi; [ -n "$mounted" ] && sh /media/vmlab/install.sh; umount /media/vmlab 2>/dev/null || true'
    touch disk/.agent-injected
    echo "vmlab-agent bootstrap injected"
fi

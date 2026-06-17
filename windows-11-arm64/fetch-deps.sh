#!/usr/bin/env bash
# Pull the ARM64 virtio-win bits the unattended install needs into unattend/:
#   unattend/drivers/{viostor,netkvm}/   boot-critical virtio drivers (WinPE)
#   unattend/virtio-win-gt-arm64.msi     full guest driver/tool package (ARM64)
#   unattend/qemu-ga-arm64.msi           QEMU guest agent (ARM64)
# These are redistributable binaries and stay out of git (.gitignore).
#
# NOTE: ARM64 guest-tools/agent packaging on virtio-win.iso has shifted over
# time (separate MSIs vs. a bundled virtio-win-guest-tools.exe). This script
# copies whatever ARM64 guest-tools + agent artefacts it can find and warns if
# a name is missing — verify against your virtio-win.iso and adjust the
# first-logon commands in unattend/autounattend.xml to match.
set -euo pipefail
cd "$(dirname "$0")"

# Windows 11 ARM64 client driver set.
OSDIRS=(w11 w10)
ARCH=ARM64

VIRTIO_ISO="${VIRTIO_ISO:-/tmp/vmlab-fetch/virtio-win.iso}"
URL="https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso"

if [[ ! -f "$VIRTIO_ISO" ]]; then
    mkdir -p "$(dirname "$VIRTIO_ISO")"
    echo "downloading virtio-win.iso..."
    curl -fSL --retry 3 -o "$VIRTIO_ISO" "$URL"
fi

# bsdtar preserves the ISO's read-only modes, so re-add +w before cleanup.
tmp=$(mktemp -d)
trap 'chmod -R u+w "$tmp" 2>/dev/null; rm -rf "$tmp"' EXIT
bsdtar -xf "$VIRTIO_ISO" -C "$tmp"

osdir() {
    local drv=$1
    for os in "${OSDIRS[@]}"; do
        [[ -d "$tmp/$drv/$os/$ARCH" ]] && { echo "$os"; return; }
    done
    echo "no driver dir under $drv/ for ${OSDIRS[*]} ($ARCH)" >&2
    exit 1
}

chmod -R u+w unattend 2>/dev/null || true
rm -rf unattend/drivers
rm -f unattend/*.msi
for drv in viostor NetKVM; do
    os=$(osdir "$drv")
    dest="unattend/drivers/${drv,,}"
    mkdir -p "$dest"
    cp "$tmp/$drv/$os/$ARCH/"* "$dest/"
    echo "drivers: $drv/$os/$ARCH -> $dest"
done

# Guest tools + agent. Names vary across virtio-win releases — copy the first
# match for each and warn if none is found so the answer file can be fixed.
stage() {
    local label=$1; shift
    for cand in "$@"; do
        if [[ -f "$tmp/$cand" ]]; then
            cp "$tmp/$cand" unattend/
            echo "staged $label: $cand"
            return
        fi
    done
    echo "WARNING: no $label found on the ISO (tried: $*) — adjust autounattend.xml" >&2
}
stage "guest tools (arm64)" virtio-win-gt-arm64.msi virtio-win-guest-tools.exe
stage "qemu guest agent (arm64)" guest-agent/qemu-ga-arm64.msi guest-agent/qemu-ga-aarch64.msi
echo "MSIs staged into unattend/"

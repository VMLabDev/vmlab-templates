#!/usr/bin/env bash
# Pull the virtio-win bits the unattended install needs into unattend/:
#   unattend/drivers/{viostor,netkvm}/   boot-critical virtio drivers (WinPE)
#   unattend/virtio-win-gt-x64.msi       full guest driver/tool package
# These are redistributable binaries and stay out of git (.gitignore).
set -euo pipefail
cd "$(dirname "$0")"

# virtio-win driver directories to try, newest-acceptable first. Windows 11
# uses the w11 client driver set (fall back to w10).
OSDIRS=(w11 w10)
ARCH=amd64

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

cp "$tmp/virtio-win-gt-x64.msi" unattend/
# WinFsp: the user-mode filesystem framework the virtio-win virtiofs
# service needs — enables the virtiofs share transport (vmlab §7.5).
# Pinned release; redistributable (GPLv3 with FLOSS exception).
WINFSP_URL="https://github.com/winfsp/winfsp/releases/download/v2.0/winfsp-2.0.23075.msi"
curl -fSL --retry 3 -o unattend/winfsp.msi "$WINFSP_URL"
echo "6324dc81194a6a08f97b6aeca303cf5c2325c53ede153bae9fc4378f0838c101  unattend/winfsp.msi" | sha256sum -c --quiet -

echo "MSIs staged into unattend/"

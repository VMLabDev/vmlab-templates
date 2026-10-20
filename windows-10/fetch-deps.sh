#!/usr/bin/env bash
# Pull the virtio-win bits the unattended install needs into unattend/:
#   unattend/drivers/{viostor,netkvm}/   boot-critical virtio drivers (WinPE)
#   unattend/virtio-win-gt-x64.msi       full guest driver/tool package
# and the vmlab-win3d driver package the `win3d` variant installs into win3d/.
# These are redistributable binaries and stay out of git (.gitignore).
set -euo pipefail
cd "$(dirname "$0")"

# virtio-win driver directories to try, newest-acceptable first. Windows 10
# uses the w10 client driver set.
OSDIRS=(w10)
ARCH=amd64

VIRTIO_ISO="${VIRTIO_ISO:-/tmp/vmlab-fetch/virtio-win-0.1.285.iso}"
# Pinned to 0.1.285. Its successor, 0.1.302, fails large virtiofs reads
# at random ("Error performing inpage operation", vmlab #137): its new
# zero-copy read path locks the caller's buffer from the wrong process
# context (virtio-win/kvm-guest-drivers-windows#1659). Move on once a
# release carries the fix.
URL="https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/virtio-win-0.1.285-1/virtio-win-0.1.285.iso"
SHA256="e14cf2b94492c3e925f0070ba7fdfedeb2048c91eea9c5a5afb30232a3976331"

if [[ ! -f "$VIRTIO_ISO" ]]; then
    mkdir -p "$(dirname "$VIRTIO_ISO")"
    echo "downloading virtio-win.iso..."
    curl -fSL --retry 3 -o "$VIRTIO_ISO" "$URL"
    echo "$SHA256  $VIRTIO_ISO" | sha256sum -c --quiet - \
        || { echo "virtio-win.iso failed its checksum" >&2; exit 1; }
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

# vmlab-win3d: the test-signed virtio-gpu 3D driver package (KMD, D3D/OpenGL
# UMDs, Venus Vulkan ICD, D3D12 bridge) the `win3d` variant installs. One
# pinned GitHub release; the zip is sha256-checked, then unpacked flat into
# win3d/ (Install.cmd at the top), which the variant attaches as the WIN3D ISO.
WIN3D_VERSION="0.1.1-alpha"
WIN3D_SHA256="153c458127bce348d9b036603b759e99f8f2eb5655d0a8274160e99cc5c5b8c9"
WIN3D_URL="https://github.com/VMLabDev/vmlab-win3d/releases/download/v${WIN3D_VERSION}/vmlab-win3d-${WIN3D_VERSION}-windows-x64.zip"
WIN3D_ZIP="${WIN3D_ZIP:-/tmp/vmlab-fetch/vmlab-win3d-${WIN3D_VERSION}-windows-x64.zip}"

if [[ ! -f "$WIN3D_ZIP" ]]; then
    mkdir -p "$(dirname "$WIN3D_ZIP")"
    echo "downloading vmlab-win3d ${WIN3D_VERSION}..."
    curl -fSL --retry 3 -o "$WIN3D_ZIP" "$WIN3D_URL"
fi
echo "$WIN3D_SHA256  $WIN3D_ZIP" | sha256sum -c --quiet - \
    || { echo "vmlab-win3d zip failed its checksum" >&2; exit 1; }

chmod -R u+w win3d 2>/dev/null || true
rm -rf win3d
mkdir -p win3d
# The zip holds one top-level directory (vmlab-win3d-<version>/) plus a
# README.txt beside it that the strip discards; Install.cmd sits at the root.
bsdtar -xf "$WIN3D_ZIP" -C win3d --strip-components=1
[[ -f win3d/Install.cmd && -f win3d/manifest.json ]] \
    || { echo "vmlab-win3d zip did not unpack to win3d/Install.cmd" >&2; exit 1; }

echo "vmlab-win3d ${WIN3D_VERSION} staged into win3d/"


#!/usr/bin/env bash
# Stage the one virtio driver this template needs into unattend/, which is
# packed into the UNATTEND ISO the build attaches.
#
# Not the whole virtio-win set: the windows-legacy profile gives the guest an
# IDE disk and an e1000 NIC, both inbox on Windows 7, so viostor and NetKVM
# would be dead weight. What Windows 7 has no driver for is virtio-serial —
# the agent's channel — so without vioserial the agent installs, starts, and
# finds nothing to talk to, and the build fails its verification boot.
#
# These are redistributable binaries and stay out of git (.gitignore).
set -euo pipefail
cd "$(dirname "$0")"

VIRTIO_ISO="${VIRTIO_ISO:-/tmp/vmlab-fetch/virtio-win-0.1.126.iso}"
# Pinned to 0.1.126 (2016), two constraints deep.
#
# The first is the one 8/2012 and later share: 0.1.190 (2020) is the last
# release Microsoft cross-signed, and a pre-Windows-10 kernel refuses to
# load an attestation-signed driver — verified on Windows 8 x64, where
# 2023 drivers are rejected outright and 2022 install but will not load.
#
# The second is this family's alone. Windows 7 and Server 2008 R2 RTM
# (6.1.7600 — our media is pre-SP1) have no SHA-2 code signing support,
# which arrived in KB3033929 and needs SP1. 0.1.190's catalogs list only
# SHA-256 member hashes, so the OS computes the INF's SHA-1, finds no
# entry, and reports the package tampered:
#
#   INF hash is not present in the catalog. Driver package appears to be
#   tampered. ... Error = 0xE000024B
#
# which pnputil raises as "Windows can't verify the publisher of this
# driver software" — the dialog that hung two Server 2008 R2 builds on
# 2026-09-05, on an image whose publisher was already trusted. 0.1.126
# still carries SHA-1 catalogs, and verified live on Windows 7 x64:
# 0.1.190 fails the hash check, 0.1.126 imports.
URL="https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/virtio-win-0.1.126-2/virtio-win.iso"
SHA256="39890b158664fbfe080ed880a61a81d20c80e0b8762febb8f8e09a82be65dd38"

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
# Extract the whole ISO: several vioserial builds hard-link their KMDF
# coinstaller out of a sibling driver's directory (which one varies by
# release), and bsdtar fails an extraction whose link target is absent.
bsdtar -xf "$VIRTIO_ISO" -C "$tmp"

# w7 covers Windows 7 and Server 2008 R2; the x86 tree is the 32-bit build.
SRC="$tmp/vioserial/w7/x86"
[[ -d "$SRC" ]] || { echo "no vioserial/w7/x86 in $VIRTIO_ISO" >&2; exit 1; }

chmod -R u+w unattend 2>/dev/null || true
rm -rf unattend/drivers
mkdir -p unattend/drivers/vioserial
# The .pdb is 1.4MB of debug symbols Setup never reads.
find "$SRC" -maxdepth 1 -type f ! -name '*.pdb' -exec cp {} unattend/drivers/vioserial/ \;
echo "drivers: vioserial/w7/x86 -> unattend/drivers/vioserial"
ls -la unattend/drivers/vioserial

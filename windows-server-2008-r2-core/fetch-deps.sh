#!/usr/bin/env bash
# Stage the one virtio driver this template needs into unattend/, which is
# packed into the UNATTEND ISO the build attaches.
#
# Not the whole virtio-win set: the windows-legacy profile gives the guest an
# IDE disk and an e1000 NIC, both inbox on this Windows, so viostor and NetKVM
# would be dead weight. What it has no driver for is virtio-serial —
# the agent's channel — so without vioserial the agent installs, starts, and
# finds nothing to talk to, and the build fails its verification boot.
#
# These are redistributable binaries and stay out of git (.gitignore).
set -euo pipefail
cd "$(dirname "$0")"

VIRTIO_ISO="${VIRTIO_ISO:-/tmp/vmlab-fetch/virtio-win-0.1.190.iso}"
# Pinned to 0.1.190 (2020), the last release whose drivers are
# Microsoft cross-signed. Red Hat moved to attestation signing after
# it, and a pre-Windows-10 kernel refuses to load such a driver —
# verified on Windows 8 x64, where 2023 drivers are rejected outright,
# 2022 install but will not load, and these prompt and install.
URL="https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/virtio-win-0.1.190-1/virtio-win.iso"
SHA256="dc6044e02fa6739881246843287481919ebcd4484f4bf23247741100489e9930"

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

# 2k8R2/amd64 is this guest's driver build in the virtio-win tree.
SRC="$tmp/vioserial/2k8R2/amd64"
[[ -d "$SRC" ]] || { echo "no vioserial/2k8R2/amd64 in $VIRTIO_ISO" >&2; exit 1; }

chmod -R u+w unattend 2>/dev/null || true
rm -rf unattend/drivers
mkdir -p unattend/drivers/vioserial
# The .pdb is 1.4MB of debug symbols Setup never reads.
find "$SRC" -maxdepth 1 -type f ! -name '*.pdb' -exec cp {} unattend/drivers/vioserial/ \;
echo "drivers: vioserial/2k8R2/amd64 -> unattend/drivers/vioserial"
ls -la unattend/drivers/vioserial

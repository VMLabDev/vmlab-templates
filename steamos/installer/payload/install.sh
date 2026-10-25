#!/bin/bash
# Runs as root inside the live SteamOS recovery image, from the STEAMINST ISO
# that fetch-deps.sh attaches. Installs SteamOS onto the disk whose virtio
# serial is `steamos-target` with Valve's own repair_device.sh, then bakes the
# vmlab-agent first-boot bootstrap into both partition sets.
#
# The markers "vmlab install done" and "vmlab install failed" are what the
# driving script reads off the console with OCR (lowercase words: OCR misreads
# the M in an all-caps VMLAB as H). Nothing else reaches the host from here.
set -euo pipefail
trap 'echo; echo "vmlab install failed at line $LINENO"' ERR

here="$(cd -- "$(dirname -- "$0")" && pwd)"
target="$(readlink -f /dev/disk/by-id/virtio-steamos-target)"
[[ -b $target ]] || { echo "no target disk (virtio serial steamos-target)"; false; }
echo "installing SteamOS onto $target"

# repair_device.sh assumes the Deck's NVMe drive. Point it at the target,
# drop the NVMe sanitize (QEMU's virtio disk has no NVMe admin commands), and
# leave the reboot prompt out: the bootstrap below has to go in first.
rd=/tmp/repair_device.sh
cp /home/deck/tools/repair_device.sh "$rd"
sed -i \
    -e "s|^DISK=/dev/nvme0n1\$|DISK=$target|" \
    -e 's|^DISK_SUFFIX=p$|DISK_SUFFIX=|' \
    -e 's|^  sanitize_all$|  : # sanitize_all (not an NVMe drive)|' \
    -e 's|^  prompt_reboot "Reimaging complete."$|  : # reboot left to the vmlab installer|' \
    "$rd"
for want in "^DISK=$target\$" '^DISK_SUFFIX=$' 'sanitize_all (not an NVMe drive)' 'reboot left to the vmlab installer'; do
    grep -q -- "$want" "$rd" || { echo "repair_device.sh did not take the patch: $want"; false; }
done

# The BIOS and controller updaters flash Steam Deck firmware. The script
# prefers a vendored copy under /home/deck when one exists, so a stub there
# turns both into no-ops without touching the script.
for stub in jupiter-bios/jupiter-biosupdate jupiter-controller-fw/jupiter-controller-update; do
    mkdir -p "/home/deck/${stub%/*}"
    printf '#!/bin/sh\necho "vmlab: skipping %s (not a Steam Deck)"\n' "${stub##*/}" > "/home/deck/$stub"
    chmod 0755 "/home/deck/$stub"
done

NOPROMPT=1 bash "$rd" all

# The agent comes from the VMLAB ISO that `vmlab template build` attaches, so
# it cannot be installed from here. A oneshot unit in /etc (an overlay kept on
# that partition set's var) installs it on the build's first boot. Both sets
# get it: Valve's bootloader picks between A and B itself, and after a fresh
# image that is B as often as A.
for partset in A B; do
    steamos-chroot --disk "$target" --partset "$partset" -- /bin/bash -euc '
        mkdir -p /etc/vmlab
        printf "%s\n" "$1" > /etc/vmlab/bootstrap.sh
        chmod 0755 /etc/vmlab/bootstrap.sh
        printf "%s\n" "$2" > /etc/systemd/system/vmlab-bootstrap.service
        systemctl enable vmlab-bootstrap.service
    ' -- "$(cat "$here/bootstrap.sh")" "$(cat "$here/vmlab-bootstrap.service")"
done

sync
# install.ws reads the marker off the screen and stops the VM itself.
echo
echo "vmlab install done"

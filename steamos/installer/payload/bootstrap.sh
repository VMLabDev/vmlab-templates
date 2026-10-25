#!/bin/sh
# vmlab-bootstrap.service: install vmlab-agent from the VMLAB ISO the template
# build attaches, then disable this unit. Baked into partition set A's /etc by
# the installer (installer/payload/install.sh).
#
# The bootstrap installs the agent to /usr/local/lib/vmlab, which is on
# SteamOS's read-only root, so the root is made writable first and left that
# way: `vmlab machine repair-agent` and the stale-agent refresh on `up` write
# to the same path later.
set -u

steamos-readonly disable

iso=/run/vmlab-iso
mkdir -p "$iso"
found=
# The CD-ROM can show up a little after local-fs; give it a minute.
for _ in $(seq 1 30); do
    for dev in /dev/disk/by-label/VMLAB /dev/sr0 /dev/sr1 /dev/sr2; do
        [ -e "$dev" ] || continue
        mount -o ro "$dev" "$iso" 2>/dev/null || continue
        if [ -e "$iso/install.sh" ]; then found=1; break 2; fi
        umount "$iso"
    done
    sleep 2
done
if [ -z "$found" ]; then
    echo "vmlab-bootstrap: no VMLAB ISO attached" >&2
    exit 1
fi

sh "$iso/install.sh"
rc=$?
umount "$iso"
[ "$rc" -eq 0 ] && systemctl disable vmlab-bootstrap.service
exit "$rc"

#!/bin/sh
# The macos-tahoe build's work inside macOS Recovery. scripts/install.ws types
# one line into the Recovery Terminal for each stage; this ISO (MACSETUP)
# mounts at /Volumes/MACSETUP:
#
#   sh /Volumes/MACSETUP/recovery.sh install
#       Erase the target disk and install macOS Tahoe onto it with the
#       Recovery's own startosinstall, which downloads the OS from Apple
#       (~12 GB) and reboots into the installer when it has it.
#
#   sh /Volumes/MACSETUP/recovery.sh finish
#       On the installed system's Data volume: the vmlab agent and the vmlab
#       account (the VMLAB ISO's macos/install.sh), the USB keyboard's type
#       (so the Keyboard Setup Assistant never asks); then OpenCore into the
#       target disk's own EFI system partition, so a clone boots from its one
#       disk with a fresh UEFI VARS.
#
# A stage that fails prints "VMLAB <STAGE> FAILED", and finish ends with
# "VMLAB FINISH DONE": the build reads them off the screen with OCR, so they
# are plain words. While startosinstall runs, a
# heartbeat line every 20 s keeps the screen changing, so the build's stall
# watch can tell a live download from a hung guest.

here="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
stage="$1"

say() {
    echo "vmlab: $*"
}

fail() {
    say "$*"
    # Three times: one OCR misread must not hide it.
    for i in 1 2 3; do echo "VMLAB $(echo "$stage" | tr a-z A-Z) FAILED"; done
    exit 1
}

# The disk macOS goes onto: the largest internal physical disk. Recovery
# numbers disks in its own order, not by SATA port (the build's FAT boot
# disk can be disk0), so it is found by size: the template's disk is far
# larger than the boot disk and the ISOs.
target_disk() {
    best=""
    bestsize=0
    for dev in $(diskutil list physical | sed -n 's|^/dev/\(disk[0-9]*\) (internal, physical):.*|\1|p'); do
        size=$(diskutil info "$dev" | sed -n 's/.*Disk Size:.*(\([0-9]*\) Bytes).*/\1/p')
        if [ -n "$size" ] && [ "$size" -gt "$bestsize" ]; then
            best="$dev"
            bestsize="$size"
        fi
    done
    [ "$bestsize" -ge 40000000000 ] || return 1
    echo "$best"
}

install_macos() {
    disk=$(target_disk) || fail "no internal disk of 40 GB or more to install onto"
    say "installing onto /dev/$disk"
    diskutil eraseDisk APFS "Macintosh HD" GPT "$disk" || fail "diskutil eraseDisk $disk failed"

    soi=""
    for app in /Install\ macOS*.app /Applications/Install\ macOS*.app; do
        if [ -x "$app/Contents/Resources/startosinstall" ]; then
            soi="$app/Contents/Resources/startosinstall"
            break
        fi
    done
    [ -n "$soi" ] || fail "no Install macOS app with startosinstall in this Recovery"
    say "running $soi"

    log=/tmp/vmlab-startosinstall.log
    "$soi" --agreetolicense --volume "/Volumes/Macintosh HD" --nointeraction >"$log" 2>&1 &
    pid=$!
    # A display that sleeps freezes the screen the build watches for stalls.
    pmset -a displaysleep 0 sleep 0 2>/dev/null
    caffeinate -dims -w "$pid" 2>/dev/null &
    # startosinstall reboots the machine itself once the OS is downloaded
    # and staged; until then, show that it is alive.
    while kill -0 "$pid" 2>/dev/null; do
        sleep 20
        last=$(tr '\r' '\n' <"$log" | sed '/^ *$/d' | tail -n 1)
        say "$(date -u +%H:%M:%S) startosinstall running: $last"
    done
    wait "$pid"
    rc=$?
    tr '\r' '\n' <"$log" | sed '/^ *$/d' | tail -n 5
    fail "startosinstall exited $rc without rebooting"
}

finish() {
    data="/Volumes/Macintosh HD - Data"
    [ -d "$data/private/var" ] || fail "no installed Data volume at $data"
    i=0
    until [ -x /Volumes/VMLAB/macos/install.sh ]; do
        i=$((i + 1))
        [ "$i" -ge 30 ] && fail "the VMLAB ISO never mounted at /Volumes/VMLAB"
        sleep 2
    done

    /Volumes/VMLAB/macos/install.sh --user vmlab --password vmlab --full-name vmlab "$data" \
        || fail "the VMLAB ISO's macos/install.sh failed"

    # QEMU's usb-kbd (vendor 0x0627, product 0x0001) is no Apple keyboard,
    # so the Keyboard Setup Assistant asks what it is on the first desktop.
    # Saying ANSI (40) here keeps it quiet.
    cp "$here/com.apple.keyboardtype.plist" "$data/Library/Preferences/com.apple.keyboardtype.plist" \
        || fail "could not write com.apple.keyboardtype.plist"
    chown root:wheel "$data/Library/Preferences/com.apple.keyboardtype.plist"
    chmod 0644 "$data/Library/Preferences/com.apple.keyboardtype.plist"

    disk=$(target_disk) || fail "no target disk"
    esp="${disk}s1"
    diskutil info "$esp" | grep -q 'Partition Type: *EFI' || fail "$esp is not an EFI system partition"
    diskutil mount "$esp" || fail "could not mount $esp"
    mp=$(diskutil info "$esp" | sed -n 's/^ *Mount Point: *//p')
    [ -d "$mp" ] || fail "$esp mounted nowhere"
    rm -rf "$mp/EFI/OC" "$mp/EFI/BOOT"
    mkdir -p "$mp/EFI"
    cp -R "$here/EFI/OC" "$here/EFI/BOOT" "$mp/EFI/" || fail "could not copy OpenCore into $esp"
    say "OpenCore installed in $esp ($mp)"
    ls -R "$mp/EFI" | head -n 20

    sync
    diskutil unmount "$esp" || fail "could not unmount $esp"
    diskutil unmount "$data" || say "could not unmount $data (the host reset is still safe after sync)"
    sync
    for i in 1 2 3; do echo "VMLAB FINISH DONE"; done
}

case "$stage" in
    install) install_macos ;;
    finish) finish ;;
    *) fail "usage: recovery.sh install|finish" ;;
esac

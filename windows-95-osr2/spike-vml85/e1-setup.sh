#!/bin/sh
# VML-85 E1: private overlay on the OSR2 TCG template + FIX95CPU floppy.
# The store disk is only a read-only backing file.
set -eu
base=/var/build/cache/vmlab/vml85
e=$base/e1
store=/home/wil/.local/share/vmlab/templates/x86/windows-95-osr2/4.00.1111.3/disk.qcow2
case "$e" in /var/build/cache/vmlab/vml85/*) ;; *) echo refused; exit 2;; esac
test -f "$store"
mkdir -p "$e" "$base/fix95cpu"
zip=$base/fix95cpu/FIX95CPU_V3_FINAL.ZIP
sum=7618245fcc1005a975006c5f625ebf581a58309491642c8fdc9eef583deb0d40
if ! printf '%s  %s\n' "$sum" "$zip" | sha256sum -c --status - 2>/dev/null; then
  curl -L --fail --connect-timeout 10 --max-time 180 -o "$zip.part" \
    https://archive.org/download/fix-95-cpu-v3-final/FIX95CPU_V3_FINAL.ZIP
  printf '%s  %s\n' "$sum" "$zip.part" | sha256sum -c -
  mv "$zip.part" "$zip"
fi
printf '%s  %s\n' "$sum" "$zip" | sha256sum -c -
mkdir -p "$base/fix95cpu/payload"
7z x -y -o"$base/fix95cpu/payload" "$zip" >/dev/null
ls -la "$base/fix95cpu/payload"
test -f "$base/fix95cpu/payload/FIX95CPU.IMA"
cp "$base/fix95cpu/payload/FIX95CPU.IMA" "$e/fix95.img"
mdir -i "$e/fix95.img" ::
test ! -e "$e/disk.qcow2"
qemu-img create -f qcow2 -b "$store" -F qcow2 "$e/disk.qcow2" >/dev/null
qemu-img info "$e/disk.qcow2" | head -8

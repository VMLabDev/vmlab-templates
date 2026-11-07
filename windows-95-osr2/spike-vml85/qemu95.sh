#!/bin/sh
# VML-85: start a Windows 95 guest like vmlab's windows-9x profile on KVM.
# Usage: qemu95.sh <dir> <boot a|c> [floppy.img]
# <dir> holds disk.qcow2. Writes mon.sock, agent.sock, com2.log, qemu.pid there.
# Run inside: systemd-run --user --scope -q -p MemoryMax=24G -p MemorySwapMax=0
set -eu
d=${1:?dir}
boot=${2:?boot}
fl=${3:-}
case "$d" in /var/build/cache/vmlab/vml85/*) ;; *) echo "refused: $d" >&2; exit 2;; esac
test -f "$d/disk.qcow2"
if [ -f "$d/qemu.pid" ] && kill -0 "$(cat "$d/qemu.pid")" 2>/dev/null; then
  echo "refused: qemu already running in $d" >&2; exit 2
fi
fdarg=""
if [ -n "$fl" ]; then
  test -f "$fl"
  fdarg="-drive if=floppy,index=0,format=raw,file=$fl"
fi
# shellcheck disable=SC2086
ionice -c3 nice -n19 qemu-system-i386 -name vml85 \
  -machine pc -accel kvm -cpu pentium3 -smp 1 -m 64 \
  -rtc base=localtime \
  -vga cirrus \
  -drive if=ide,index=0,format=qcow2,file="$d/disk.qcow2" \
  $fdarg \
  -nic user,model=pcnet \
  -chardev socket,id=vagent0,path="$d/agent.sock",server=on,wait=off \
  -device isa-serial,chardev=vagent0,index=0 \
  -chardev file,id=serlog,path="$d/com2.log" \
  -device isa-serial,chardev=serlog,index=1 \
  -monitor unix:"$d/mon.sock",server=on,wait=off \
  -display none -vnc unix:"$d/vnc.sock" \
  -boot "$boot" \
  -pidfile "$d/qemu.pid" -daemonize
echo "started pid $(cat "$d/qemu.pid")"

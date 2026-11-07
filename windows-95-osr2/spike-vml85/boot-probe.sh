#!/bin/sh
# VML-85: boot <dir>/disk.qcow2 from C: on KVM and probe the COM1 agent like
# vmlab does (a fresh Hello every <interval> s). Screenshots every 30 s.
# Usage: boot-probe.sh <dir> <tag> <secs> <interval> [silent]
set -eu
d=${1:?dir}
tag=${2:?tag}
secs=${3:?secs}
iv=${4:?interval}
mode=${5:-}
case "$d" in /var/build/cache/vmlab/vml85/*) ;; *) echo "refused: $d" >&2; exit 2;; esac
B=/var/build/cache/vmlab/vml85
Q="python3 -I $B/bin/q.py"
if [ -S "$d/mon.sock" ] && [ -f "$d/qemu.pid" ] && kill -0 "$(cat "$d/qemu.pid")" 2>/dev/null; then
  $Q hmp "$d/mon.sock" quit >/dev/null 2>&1 || true
  sleep 2
fi
mkdir -p "$d/$tag"
sh "$B/bin/qemu95.sh" "$d" c
(
  i=0
  while [ $i -lt $((secs / 30)) ]; do
    sleep 30
    i=$((i + 1))
    $Q shot "$d/mon.sock" "$d/$tag/s$(printf %03d $((i * 30))).png" >/dev/null 2>&1 || true
  done
) &
$Q host "$d/agent.sock" "$d/$tag/host.log" "$secs" "$iv" $mode
wait
grep -c ANSWERED "$d/$tag/host.log" || true
tail -5 "$d/$tag/host.log"

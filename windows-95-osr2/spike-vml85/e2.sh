#!/bin/sh
# VML-85 E2: E1's FIX95CPU'd image (frozen as backing) + VMM2XUPD, run like the
# ed7a7d0 OSR2 template does it (agent exec, /Q:A /R:N), then a cold restart
# and the same COM1 probes as E1.
set -eu
B=/var/build/cache/vmlab/vml85
e=$B/e2
Q="python3 -I $B/bin/q.py"
case "$e" in /var/build/cache/vmlab/vml85/e2) ;; *) exit 2;; esac
mkdir -p "$e"
if [ ! -f "$e/disk.qcow2" ]; then
  qemu-img create -f qcow2 -b "$B/e1/disk.qcow2" -F qcow2 "$e/disk.qcow2" >/dev/null
fi
if [ ! -f "$e/upd.img" ]; then
  mformat -C -f 1440 -v VMMUPD -i "$e/upd.img" ::
  mcopy -i "$e/upd.img" "$B/fix95cpu/payload/VMM2XUPD.EXE" ::VMM2XUPD.EXE
fi
sh "$B/bin/qemu95.sh" "$e" c "$e/upd.img"
# wait for the agent
n=0
until $Q exec "$e/agent.sock" 20 'C:\VMLAB\VMLABAGT.EXE' --probe >/dev/null 2>"$e/probe.err"; do
  grep -q 'exit 2' "$e/probe.err" && break
  n=$((n + 1)); [ $n -lt 20 ] || { echo "agent never answered before the update"; exit 1; }
  sleep 10
done
echo "agent answered before the update (after $n retries)"
$Q exec "$e/agent.sock" 60 'C:\WINDOWS\REGEDIT.EXE' /e 'C:\VMLAB\PRE.REG' 'HKEY_LOCAL_MACHINE\Enum' || true
echo "== VMM2XUPD"
$Q exec "$e/agent.sock" 300 'A:\VMM2XUPD.EXE' /Q:A /R:N; echo "vmm2xupd exec rc=$?"
sleep 5
$Q shot "$e/mon.sock" "$e/after-upd.png" >/dev/null
$Q hmp "$e/mon.sock" quit >/dev/null 2>&1 || true
sleep 3
sh "$B/bin/boot-probe.sh" "$e" run1 300 15

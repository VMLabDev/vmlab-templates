#!/bin/sh
# VML-85 E3: KVM build of the ed7a7d0 windows-95-osr2 template in the private env.
# Pins 4.00.1111.4 (refuses if it exists). Screenshots every 30 s, the log
# redacted of the OEM key. The key files are mode 600.
# Run inside: systemd-run --user --scope -q -p MemoryMax=24G -p MemorySwapMax=0
set -eu
B=/var/build/cache/vmlab/vml85
. "$B/bin/env85.sh"
ver=${1:-4.00.1111.4}
e=$B/e3
tpl=$B/tpl
store=$(readlink -f "$XDG_DATA_HOME/vmlab/templates")/x86/windows-95-osr2
case "$e:$tpl" in /var/build/cache/vmlab/vml85/e3:/var/build/cache/vmlab/vml85/tpl) ;; *) exit 2;; esac
[ ! -e "$store/$ver" ] || { echo "refused: $store/$ver exists (MEM-101)"; exit 3; }
mkdir -p "$e/shots" "$tpl/iso"
ls "$store" > "$e/versions-before.txt"
# template source: ed7a7d0, exported in the sandbox
rm -rf -- "$tpl/windows-95-osr2"
cp -r /work/vmlab/vml-85/e3src/windows-95-osr2 "$tpl/windows-95-osr2"
[ -L "$tpl/iso/win95_osr2_en.iso" ] || ln -s /home/wil/dev/vmlab-templates/iso/win95_osr2_en.iso "$tpl/iso/win95_osr2_en.iso"
# FIX95CPU zip from E1 (same sha256) so stage-fix95cpu.sh does not download it
mkdir -p "$tpl/windows-95-osr2/fix95cpu"
cp "$B/fix95cpu/FIX95CPU_V3_FINAL.ZIP" "$tpl/windows-95-osr2/fix95cpu/"
# only the key line, private; also clear any leftover of a killed run
rm -f -- "$tpl/.env" "$tpl/windows-95-osr2/scripts/install.ws"
umask 077
grep '^WINDOWS_95_OEM_KEY=' /home/wil/dev/vmlab-templates/.env > "$tpl/.env"
umask 022
[ -s "$tpl/.env" ] || { echo "no key line"; exit 3; }
R="python3 -I $B/bin/redact.py $tpl/.env"
cleanup() {
  rm -f -- "$tpl/.env" "$tpl/windows-95-osr2/scripts/install.ws"
}
trap cleanup EXIT
cd "$tpl/windows-95-osr2"
# umask 077 only here: install.ws (key inside) is written mode 600
( umask 077; ./fetch-deps.sh ) 2>&1 | $R > "$e/fetch-deps.log"
tail -3 "$e/fetch-deps.log"
[ -f scripts/install.ws ] && [ -f src/VMLABAGT.EXE ] && [ -f src/FIX95CPU/FIX95CPU.BAT ] || { echo "fetch-deps did not stage"; exit 4; }
shots() {
  n=0
  while :; do
    sleep 30; n=$((n + 1))
    ref=$(vmlab template status 2>/dev/null | grep -o '[A-Za-z0-9._-]*/[A-Za-z0-9._-]*' | grep -v '^x86/' | head -1)
    for vm in $ref build-x86-windows-95-osr2/build; do
      timeout 30s vmlab vm screenshot "$vm" "$e/shots/$(printf %04d $n)-$(date +%H%M%S).png" >/dev/null 2>&1 && break
    done
  done
}
shots & sp=$!
t0=$(date +%s)
set +e
{ timeout 120m vmlab template build --version "$ver"; echo $? > "$e/rc"; } 2>&1 | $R > "$e/build.log"
rc=$(cat "$e/rc")
set -e
kill $sp 2>/dev/null || true
echo "build rc=$rc minutes=$(( ($(date +%s) - t0 + 59) / 60 ))"
ls "$store" > "$e/versions-after.txt"
diff "$e/versions-before.txt" "$e/versions-after.txt" || true
tail -25 "$e/build.log"
rm -f -- "$tpl/windows-95-osr2/scripts/install.ws"
python3 -I "$B/bin/redact.py" "$tpl/.env" --scan "$e" "$tpl"
# stop this env's vmlab daemons (environ holds XDG_RUNTIME_DIR=/tmp/v85run)
for p in $(pgrep -u "$(id -u)" -f 'vmlab' || true); do
  [ "$p" != $$ ] || continue
  if tr '\0' '\n' < /proc/$p/environ 2>/dev/null | grep -qx 'XDG_RUNTIME_DIR=/tmp/v85run'; then
    case "$(tr '\0' ' ' < /proc/$p/cmdline)" in
      *vmlab/bin/vmlab*) echo "stopping $p: $(tr '\0' ' ' < /proc/$p/cmdline | cut -c1-120)"; kill "$p" || true;;
    esac
  fi
done

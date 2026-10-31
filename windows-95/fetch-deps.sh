#!/usr/bin/env bash
# Stage everything the build needs from the vanilla CD in ../iso/:
#   - ./src/      the CD's \WIN98 folder, staged for installation (VMLABSRC ISO)
#   - ./answer/   MSBATCH.INF and BOOT.BAT (the floppy Setup reads as B:\)
#   - scripts/install.ws  with the OEM Product ID from ../.env: retail 4.00.950
#                 Setup takes an OEM ID only when it is typed, not from MSBATCH.INF
# All of it is gitignored and rebuilt on every run.
set -euo pipefail
cd "$(dirname "$0")"

ISO=../iso/win95_en.iso
SRC_DIR=WIN95                 # the install folder on the CD
DST_DIR=WIN95                 # its name on the VMLABSRC ISO and on C:
KEY_VAR=WINDOWS_95_OEM_KEY

for tool in 7z curl sha256sum; do
    command -v "$tool" >/dev/null || { echo "fetch-deps: $tool is required" >&2; exit 1; }
done
[ -f "$ISO" ] || { echo "fetch-deps: put the vanilla CD image at $ISO (see ../iso/README.md)" >&2; exit 1; }

if [ -f ../.env ]; then set -a; . ../.env; set +a; fi
# The CD is OEM media (ProductType=9 in SETUPPP.INF), which takes only the
# 20-digit OEM Product ID (xxxxx-OEM-xxxxxxx-xxxxx); a retail key is rejected.
KEY="${!KEY_VAR:-}"
[ -n "$KEY" ] || { echo "fetch-deps: set $KEY_VAR in ../.env (see ../.env.example)" >&2; exit 1; }

rm -rf answer
mkdir -p answer
# DOS-era tools want CRLF line endings.
sed 's/$/\r/' MSBATCH.INF.in > answer/MSBATCH.INF
sed 's/$/\r/' VMLAB.BAT > answer/VMLAB.BAT
IFS=- read -r COA_1 _ COA_2 COA_3 <<< "$KEY"
sed -e "s/__PRODUCT_KEY__/${KEY}/" -e "s/__COA_1__/${COA_1}/" -e "s/__COA_2__/${COA_2}/" \
    -e "s/__COA_3__/${COA_3}/" scripts/install.ws.in > scripts/install.ws

# Install vanilla files, then apply FIX95CPU from DOS at Setup's first
# reboot. Avoid combining patcher9x's speed patch with replacement VXDs.
rm -rf ./src ./src.tmp
mkdir -p ./src.tmp "./src/${DST_DIR}"
7z x -y -o./src.tmp "$ISO" "$SRC_DIR" >/dev/null
[ -d "./src.tmp/${SRC_DIR}" ] || { echo "fetch-deps: no \\${SRC_DIR} folder on $ISO" >&2; exit 1; }
# Setup needs only the folder's own files; its long-named subfolders (the
# tour, online services) would not survive as 8.3 names. Upper-case names
# keep DOS's view of the ISO plain.
for f in "./src.tmp/${SRC_DIR}"/*; do
    [ -f "$f" ] && cp "$f" "./src/${DST_DIR}/$(basename "$f" | tr '[:lower:]' '[:upper:]')"
done
rm -rf ./src.tmp
echo "vmlab: Windows 95 installation files with FIX95CPU" > ./src/VMLABSRC.TXT
bash ./stage-fix95cpu.sh

# vmlab's legacy agent for 9x, from the installed guest assets. Windows 95
# hangs when a DOS virtual machine starts on this hardware, so the agent cannot
# come from the bootstrap ISO's install-9x.bat (a batch file needs COMMAND.COM).
# VMLAB.BAT copies it to C:\VMLAB during the DOS stage instead, and
# MSBATCH.INF registers it under RunServices directly.
AGENT="${VMLAB_GUEST_ASSET_DIR:-$HOME/.local/share/vmlab/guest}/agent/windows-9x-x86/vmlab-agent-legacy.exe"
[ -f "$AGENT" ] || { echo "fetch-deps: no 9x agent at $AGENT (install vmlab's guest assets)" >&2; exit 1; }
cp "$AGENT" ./src/VMLABAGT.EXE

echo "staged src/${DST_DIR} (patched) + answer/ + scripts/install.ws (ID from ${KEY_VAR})"

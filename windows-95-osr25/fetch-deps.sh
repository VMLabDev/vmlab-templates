#!/usr/bin/env bash
# Stage everything the build needs from the vanilla CD in ../iso/:
#   - ./src/      the CD's \WIN98 folder, patched for modern CPUs (VMLABSRC ISO)
#   - ./answer/   MSBATCH.INF and BOOT.BAT (the floppy Setup reads as B:\)
#   - scripts/install.ws  with the OEM Product ID from ../.env: retail 4.00.950
#                 Setup takes an OEM ID only when it is typed, not from MSBATCH.INF
# All of it is gitignored and rebuilt on every run.
set -euo pipefail
cd "$(dirname "$0")"

ISO=../iso/win95c_osr25.iso
SRC_DIR=WIN95                 # the install folder on the CD
DST_DIR=WIN95                 # its name on the VMLABSRC ISO and on C:
KEY_VAR=WINDOWS_95_OEM_KEY

for tool in 7z curl sha256sum tar; do
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
cp VMLAB.BAT answer/
IFS=- read -r COA_1 _ COA_2 COA_3 <<< "$KEY"
sed -e "s/__PRODUCT_KEY__/${KEY}/" -e "s/__COA_1__/${COA_1}/" -e "s/__COA_2__/${COA_2}/" \
    -e "s/__COA_3__/${COA_3}/" scripts/install.ws.in > scripts/install.ws

# Windows 9x does not survive a modern CPU: the CPU speed test divides by zero
# above ~2 GHz (95, 98 FE), and 98/98 SE corrupt memory through the TLB
# invalidation bug on AMD Zen 2+ and Intel Tiger Lake+. patcher9x
# (JHRobotics/patcher9x, MIT) patches the installation folder; Setup prefers
# the loose patched files over its cabinets. scripts/install.ws copies the
# patched folder to C: and runs Setup from there. VMLABSRC.TXT marks the ISO
# for its drive probe.
PATCHER9X_VERSION=0.9.91
PATCHER9X_SHA256=ca787d7c6421959c9f37afdd998feb9393fe07c1c63c43c4e22db5b170a79908
PATCHER9X_ARCHIVE="patcher9x/patcher9x-${PATCHER9X_VERSION}-linux-amd64.tar.gz"
mkdir -p patcher9x
if ! echo "${PATCHER9X_SHA256}  ${PATCHER9X_ARCHIVE}" | sha256sum -c --status - 2>/dev/null; then
    curl -L --fail -o "${PATCHER9X_ARCHIVE}.part" \
        "https://github.com/JHRobotics/patcher9x/releases/download/v${PATCHER9X_VERSION}/patcher9x-${PATCHER9X_VERSION}-linux-amd64.tar.gz"
    mv "${PATCHER9X_ARCHIVE}.part" "${PATCHER9X_ARCHIVE}"
fi
echo "${PATCHER9X_SHA256}  ${PATCHER9X_ARCHIVE}" | sha256sum -c -
tar -xzf "${PATCHER9X_ARCHIVE}" -C patcher9x patcher9x

rm -rf ./src ./src.tmp
mkdir -p ./src.tmp "./src/${DST_DIR}"
7z x -y -o./src.tmp "$ISO" "$SRC_DIR" >/dev/null
[ -d "./src.tmp/${SRC_DIR}" ] || { echo "fetch-deps: no \\${SRC_DIR} folder on $ISO" >&2; exit 1; }
# Windows 95 needs only the CPU speed fix (the TLB bug is 98's, and 64 MiB is
# far below the memory limit); the full set hangs 95 Setup's hardware detection.
./patcher9x/patcher9x -auto -select speed "./src.tmp/${SRC_DIR}" | tail -3
# Setup needs only the folder's own files; its long-named subfolders (the
# tour, online services) would not survive as 8.3 names. Upper-case names
# keep DOS's view of the ISO plain.
for f in "./src.tmp/${SRC_DIR}"/*; do
    [ -f "$f" ] && cp "$f" "./src/${DST_DIR}/$(basename "$f" | tr '[:lower:]' '[:upper:]')"
done
rm -rf ./src.tmp
echo "vmlab: patched Windows 9x installation files" > ./src/VMLABSRC.TXT

# vmlab's legacy agent for 9x, from the installed guest assets. Windows 95
# hangs when a DOS virtual machine starts on this hardware, so the agent cannot
# come from the bootstrap ISO's install-9x.bat (a batch file needs COMMAND.COM).
# VMLAB.BAT copies it to C:\VMLAB during the DOS stage instead, and
# MSBATCH.INF registers it under RunServices directly.
AGENT="${VMLAB_GUEST_ASSET_DIR:-$HOME/.local/share/vmlab/guest}/agent/windows-9x-x86/vmlab-agent-legacy.exe"
[ -f "$AGENT" ] || { echo "fetch-deps: no 9x agent at $AGENT (install vmlab's guest assets)" >&2; exit 1; }
cp "$AGENT" ./src/VMLABAGT.EXE

echo "staged src/${DST_DIR} (patched) + answer/ + scripts/install.ws (ID from ${KEY_VAR})"

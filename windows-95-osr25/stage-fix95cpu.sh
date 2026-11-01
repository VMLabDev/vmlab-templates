#!/usr/bin/env bash
# Run from a Windows 95 template directory after src/ and answer/ are staged.
set -euo pipefail
test -d src
test -d answer

# Author release: https://msfn.org/board/topic/141402-windows-95-21ghz-cpu-limit-broken/
# Canonical link: http://www.tmeeco.eu/9X4EVER/GOODIES/FIX95CPU_V3_FINAL.ZIP
# The canonical host timed out; this pinned archive mirror carries v3.0.
FIX95CPU_URL=https://archive.org/download/fix-95-cpu-v3-final/FIX95CPU_V3_FINAL.ZIP
FIX95CPU_SHA256=7618245fcc1005a975006c5f625ebf581a58309491642c8fdc9eef583deb0d40
FIX95CPU_CACHE=fix95cpu
FIX95CPU_ARCHIVE="$FIX95CPU_CACHE/FIX95CPU_V3_FINAL.ZIP"
mkdir -p "$FIX95CPU_CACHE/payload" "$FIX95CPU_CACHE/floppy" src/FIX95CPU
if ! printf '%s  %s\n' "$FIX95CPU_SHA256" "$FIX95CPU_ARCHIVE" | sha256sum -c --status - 2>/dev/null; then
    curl -L --fail --connect-timeout 10 --max-time 120 -o "${FIX95CPU_ARCHIVE}.part" "$FIX95CPU_URL"
    printf '%s  %s\n' "$FIX95CPU_SHA256" "${FIX95CPU_ARCHIVE}.part" | sha256sum -c -
    mv "${FIX95CPU_ARCHIVE}.part" "$FIX95CPU_ARCHIVE"
fi
printf '%s  %s\n' "$FIX95CPU_SHA256" "$FIX95CPU_ARCHIVE" | sha256sum -c -
7z x -y -o"$FIX95CPU_CACHE/payload" "$FIX95CPU_ARCHIVE" >/dev/null
7z x -y -o"$FIX95CPU_CACHE/floppy" "$FIX95CPU_CACHE/payload/FIX95CPU.IMA" >/dev/null
cp -a "$FIX95CPU_CACHE/floppy/." src/FIX95CPU/
# Preserve the author's installer and README. Adapt only its floppy source
# paths for the VMLABSRC CD; all target files and registry operations remain.
sed -e 's|A:\\|%FIX95SRC%\\|g' \
    -e 's|MORE README.TXT|MORE %FIX95SRC%\\README.TXT|' \
    "$FIX95CPU_CACHE/floppy/FIX95CPU.BAT" > src/FIX95CPU/FIX95CPU.BAT
cp "$FIX95CPU_CACHE/payload/VMM2XUPD.EXE" src/VMM2XUPD.EXE
sed 's/$/\r/' > answer/FIX95.BAT <<'BAT'
@echo off
set FIX95SRC=
for %%d in (x y z) do if exist %%d:\vmlabsrc.txt set FIX95SRC=%%d:\fix95cpu
if "%FIX95SRC%"=="" goto missing
path %FIX95SRC%;%PATH%
call %FIX95SRC%\FIX95CPU.BAT
goto end
:missing
echo vmlab: FIX95CPU source not found
:end
BAT

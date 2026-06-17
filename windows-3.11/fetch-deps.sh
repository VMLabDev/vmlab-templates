#!/usr/bin/env bash
# Stage the Windows for Workgroups 3.11 payload for the media ISO.
#
# ../iso/Windows-3.11-stock.zip is not an installer — it is a *pre-installed*
# WfW 3.11 tree (WINDOWS/, WIN32APP/, windows.bat). The build's install.wisp
# copies it onto the dos-6.22 base disk. We only have to (a) extract it and
# (b) point its display driver at the generic VGA driver: the stock SYSTEM.INI
# is configured for an S3 Trio64V card, which QEMU does not emulate, so on the
# windows-9x profile's Cirrus VGA the S3 driver would fail to start. VGA.DRV +
# its grabber/fonts (VGA.3GR, VGA*.FON) are already present in WINDOWS/SYSTEM.
set -euo pipefail
cd "$(dirname "$0")"

ZIP=../iso/Windows-3.11-stock.zip
OUT=win311

if [ ! -f "$ZIP" ]; then
  echo "missing $ZIP — place the WfW 3.11 stock tree there (see ../iso/README.md)" >&2
  exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT"
echo "extracting Windows for Workgroups 3.11 tree -> $OUT/ ..."
if command -v unzip >/dev/null 2>&1; then
  unzip -q -o "$ZIP" -d "$OUT"
elif command -v 7z >/dev/null 2>&1; then
  7z x -y -o"$OUT" "$ZIP" >/dev/null
else
  echo "need unzip or 7z to extract $ZIP" >&2
  exit 1
fi

# Drop the *.inib backups (Control/System/Win.inib). They are not needed, and
# their 4-char extension collides with the real CONTROL.INI/SYSTEM.INI/WIN.INI
# in the ISO9660 8.3 namespace — which is the *only* tree MSCDEX reads (it can't
# see the Joliet long names). The collision makes the ISO builder rename the
# real SYSTEM.INI to SYSTEM0.INI, so the guest copy lacks SYSTEM.INI and Windows
# refuses to start ("Cannot find SYSTEM.INI").
rm -f "$OUT"/WINDOWS/*.inib

# Repoint the display from the (unemulated) S3 Trio to the generic VGA driver.
SI="$OUT/WINDOWS/SYSTEM.INI"
if [ ! -f "$SI" ]; then
  echo "SYSTEM.INI not found at $SI after extract" >&2
  exit 1
fi
sed -i 's/^display\.drv=S3TRIO\.DRV/display.drv=VGA.DRV/I' "$SI"   # [boot]
sed -i 's/^display=VDDS3764\.386/display=*vddvga/I'        "$SI"   # [386Enh]

echo "staged $OUT/ (SYSTEM.INI patched to generic VGA):"
grep -iE '^display\.drv=|^display=' "$SI" | sed 's/^/  /'

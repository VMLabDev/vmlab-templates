# Windows 95 OSR2.5

Builds `x86/windows-95-osr25` (4.03.1216) from the vanilla Windows 95 OSR2.5 CD, unattended, with
vmlab's legacy agent baked in.

- `../iso/win95c_osr25.iso` (gitignored) is the install media. It is OEM media
  (`ProductType=9`), so Setup takes only the 20-digit OEM Product ID
  (`xxxxx-OEM-xxxxxxx-xxxxx`), read from `WINDOWS_95_OEM_KEY` in `../.env`.
- `fetch-deps.sh` extracts the CD's installation folder and stages it with
  vmlab's 9x agent and FIX95CPU v3 as the `VMLABSRC` ISO. The local
  `stage-fix95cpu.sh` pins the download URL and SHA256, preserves the author's
  README, and adapts the installer's source paths for the CD. It also stages `./answer/`
  (`MSBATCH.INF`, `VMLAB.BAT`), the floppy Setup reads as `B:\`, and writes
  the Product ID into `scripts/install.ws`: Setup takes an OEM ID only when it
  is typed.
- `scripts/install.ws` lets the CD's own Setup partition (FAT32, which OSR2 introduced) and format the
  disk, quits to `X:\WIN95>`, and runs `B:\VMLAB.BAT`, which copies the agent
  and the installation tree to C: and runs Setup there. When Setup's reboot lands
  back in the CD's Setup (its boot floppy has no "boot from hard disk"), the
  provision runs FIX95CPU from DOS before ejecting the CD and resetting onto
  the disk. It requires the installer's success message before continuing.
- `MSBATCH.INF` registers `C:\VMLAB\VMLABAGT.EXE` under `RunServices`, so the
  agent answers on COM1 before logon, exec only. The build seals with a
  graceful shutdown.

The build targets KVM with `cpu_model = "pentium3"`. It retains the existing
patcher9x speed-only staging for Setup, then applies FIX95CPU's replacement
drivers at the first reboot. This ordering preserves the earlier installer
fixes without applying two binary patches blindly to the same installed files.
Needs a vmlab with `Machine.eject_cdrom`
and `cpu_model`. The template sets no `accel`: vmlab picks hardware
virtualisation, because x86 TCG is removed (Phase 4 decision D7). Runs on the `windows-9x` profile (i440fx/SeaBIOS,
Cirrus VGA, IDE, PCnet).

## Why FIX95CPU

Unpatched Windows 95 stops at Setup's first reboot on a fast CPU, and under
KVM the guest sees the host's real speed:

- above 350 MHz: `While initializing device IOS: Windows Protection Error`
  (Microsoft fixed it in AMDK6UPD.EXE, which runs only inside Windows);
- above 2.1 GHz: `While initializing device NDIS: Windows Protection Error`
  (MSKB Q312108; Microsoft shipped a fix for 98 only).

FIX95CPU v3.0 by LoneCrusader installs the fixed system files from DOS, so
the build can apply it before Windows first boots. The template used to run
on TCG to avoid these errors; with x86 TCG removed, the patch is the fix.

Source (staged by `stage-fix95cpu.sh`, not committed):

- canonical: http://www.tmeeco.eu/9X4EVER/GOODIES/FIX95CPU_V3_FINAL.ZIP
  (timed out when the template was written)
- pinned mirror: https://archive.org/download/fix-95-cpu-v3-final/FIX95CPU_V3_FINAL.ZIP
- sha256: `7618245fcc1005a975006c5f625ebf581a58309491642c8fdc9eef583deb0d40`
  (the author publishes no hash; this is the mirror's file)
- author's release: https://msfn.org/board/topic/141402-windows-95-21ghz-cpu-limit-broken/

## Build

```
just windows-95-osr25-build
# or: cd windows-95-osr25 && ./fetch-deps.sh && vmlab template build
```

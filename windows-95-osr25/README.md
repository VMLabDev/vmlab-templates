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

The build targets KVM with `cpu_model = "pentium3"`. It applies FIX95CPU at
the first Setup reboot instead of combining it with patcher9x's speed patch.
FIX95CPU's author release is
https://msfn.org/board/topic/141402-windows-95-21ghz-cpu-limit-broken/.
Needs a vmlab with `Machine.eject_cdrom`,
`cpu_model` and `accel`. Runs on the `windows-9x` profile (i440fx/SeaBIOS,
Cirrus VGA, IDE, PCnet).

## Build

```
just windows-95-osr25-build
# or: cd windows-95-osr25 && ./fetch-deps.sh && vmlab template build
```

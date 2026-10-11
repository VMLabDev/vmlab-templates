# Windows 95

Builds `x86/windows-95` (4.00.950) from the vanilla Windows 95 CD, unattended, with
vmlab's legacy agent baked in.

- `../iso/win95_en.iso` (gitignored) is the install media. It is OEM media
  (`ProductType=9`), so Setup takes only the 20-digit OEM Product ID
  (`xxxxx-OEM-xxxxxxx-xxxxx`), read from `WINDOWS_95_OEM_KEY` in `../.env`.
- `fetch-deps.sh` extracts the CD's `\WIN95` folder, patches it with
  [patcher9x](https://github.com/JHRobotics/patcher9x) for the CPU speed bug
  (Windows 95 divides by zero in its speed test above about 2 GHz), and stages
  it with vmlab's 9x agent as the `VMLABSRC` ISO. It also stages `./answer/`
  (`MSBATCH.INF`, `VMLAB.BAT`), the floppy Setup reads as `B:\`, and writes
  the Product ID into `scripts/install.ws`: Setup takes an OEM ID only when it
  is typed.
- `scripts/install.ws` lets the CD's own Setup partition (FAT16) and format the
  disk, quits to `X:\WIN95>`, and runs `B:\VMLAB.BAT`, which copies the agent
  and the patched tree to C: and runs Setup there. When Setup's reboot lands
  back in the CD's Setup (its boot floppy has no "boot from hard disk"), the
  CD is ejected and the machine reset onto the disk.
- `MSBATCH.INF` registers `C:\VMLAB\VMLABAGT.EXE` under `RunServices`, so the
  agent answers on COM1 before logon, exec only. The build seals with a
  graceful shutdown.

It runs under TCG (`accel = "tcg"`) on a `pentium3` CPU model: on AMD hosts
Windows 95 hangs at random under KVM (its TLB-invalidation bug, which
patcher9x fixes only for 98 and later). Needs a vmlab with `Machine.eject_cdrom`,
`cpu_model` and `accel`. Runs on the `windows-9x` profile (i440fx/SeaBIOS,
Cirrus VGA, IDE, PCnet).

## Build

```
just windows-95-build
# or: cd windows-95 && ./fetch-deps.sh && vmlab template build
```

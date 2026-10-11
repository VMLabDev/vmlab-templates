# Windows 98 Second Edition

Builds `x86/windows-98-se` from the vanilla Windows 98 Second Edition CD, unattended, with vmlab's
legacy agent baked in.

- `../iso/win98_se_en.iso` (gitignored) is the install media. It is OEM media
  (`ProductType=9`), so Setup takes only an OEM-range key, read from
  `WINDOWS_98_OEM_KEY` in `../.env`.
- `fetch-deps.sh` extracts the CD's `\WIN98` folder and patches it with
  [patcher9x](https://github.com/JHRobotics/patcher9x) for the CPU speed and
  TLB invalidation bugs that stop Windows 98 on modern CPUs, staged as the
  `VMLABSRC` ISO. It also stages `./answer/` (`MSBATCH.INF` with the key,
  `VMLAB.BAT`, `BOOT.BAT`), the floppy Setup reads as `B:\`.
- `scripts/install.ws` lets the CD's own Setup partition (FAT32) and format the
  disk, quits to a prompt, and runs `B:\VMLAB.BAT`, which copies the patched
  folder to C: and runs Setup there. It answers the wizard pages the answer
  file does not suppress, then waits for the agent.
- `MSBATCH.INF` registers `BOOT.BAT` under `RunServices`; it runs the VMLAB
  bootstrap ISO's `install-9x.bat` until the agent is installed. The agent
  answers on COM1 before logon, exec only. The build seals with a graceful
  shutdown.

Runs on the `windows-9x` profile (i440fx/SeaBIOS, Cirrus VGA, IDE, PCnet) with
a `pentium3` CPU model. In a clone, run COMMAND.COM built-ins as
`vmlab exec <vm> -- command.com /c ver`, one word per argument. Needs a vmlab
with `cpu_model`.

## Build

```
just windows-98-se-build
# or: cd windows-98-se && ./fetch-deps.sh && vmlab template build
```

# Windows for Workgroups 3.11

Builds an `x86/windows-3.11` template: a ready-to-run WfW 3.11 desktop that
auto-launches Program Manager at boot.

## How it works

This is **not** a setup-driven install. `../iso/Windows-3.11-stock.zip`
(gitignored) is a *pre-installed* WfW 3.11 tree. The template layers on the
`x86/dos-6.22` template (build that first) and the provision wisp copies the
Windows tree onto C:.

- `fetch-deps.sh` extracts the zip into `./win311/` (gitignored) and patches
  `SYSTEM.INI` from the stock S3 Trio64V display driver — which QEMU does not
  emulate — to the generic **VGA** driver (`VGA.DRV` + its grabber/fonts are
  already in the tree). `./win311/` is built into the `WIN311` media ISO.
- `scripts/install.wisp` boots the dos-6.22 disk, loads the Oak CD driver that
  dos-6.22 already carries in `C:\DOS` (`cd1.sys` + `MSCDEX`) to mount the CD at
  `R:`, `xcopy`s `WINDOWS`/`WIN32APP` onto C:, writes a `HIMEM`-based
  `CONFIG.SYS` and an `AUTOEXEC.BAT` that launches `win`, then verifies Program
  Manager appears before sealing the disk.

## Build

```
just windows-3-11-build      # builds dos-6.22 first if needed
# or directly:
cd dos-6.22 && vmlab template build && cd ..
cd windows-3.11 && ./fetch-deps.sh && vmlab template build
```

Runs on the `windows-9x` profile (i440fx/SeaBIOS, Cirrus VGA, IDE, PCnet).
Shows in `vmlab template list` as `x86/windows-3.11` (runs on the x86_64
emulator). Display is 640×480 16-colour VGA.

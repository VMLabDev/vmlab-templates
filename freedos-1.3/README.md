# FreeDOS 1.3

Builds an `x86/freedos-1.3` template: a bootable FreeDOS 1.3 C: drive with the
**Full** package set (BASE + apps/bonus) and vmlab's legacy guest agent. Runs on
the `windows-9x` profile (i440fx/SeaBIOS, Cirrus VGA, IDE, AMD PCnet, the agent
on a 16550 at COM1); shows in `vmlab template list` as `x86/freedos-1.3` (it
runs on the x86_64 emulator).

Unlike the proprietary `dos-6.22` entry, FreeDOS is FOSS / freely
redistributable, so this template carries a `registry` and is **publishable** to
GHCR (`just freedos-push`).

## How it works

This is a setup-driven install with no answer file — FreeDOS predates that, so
the build drives the official **FDI** batch installer over the live screen
(VNC + OCR), the same way `dos-6.22` is built.

- `fetch-deps.sh` downloads the official `FD13-LiveCD.zip`, sha256-verifies it,
  and extracts `FD13LIVE.iso` (gitignored). vmlab's URL sources can't unpack the
  multi-file zip, hence the script.
- `scripts/install.ws` boots the LiveCD, drives FDI through language → welcome →
  auto-partition (which forces a reboot) → format → **Full** package set →
  install, and returns to the live prompt.
- It then installs the agent: the build attaches vmlab's bootstrap ISO as a
  second CD, and the script types its `INSTALL.BAT` at the live prompt. That
  copies `VMLABAGT.EXE` to `C:\VMLAB`, adds it to `C:\FDAUTO.BAT` (FreeDOS boots
  `FDCONFIG.SYS` → `FDAUTO.BAT` and never reads `AUTOEXEC.BAT`) and starts it on
  COM1. Once the agent answers, the script checks over `exec` that
  `FDAUTO.BAT` starts it (adding the line itself for a vmlab whose
  `INSTALL.BAT` still wrote `AUTOEXEC.BAT`), then `poweroff`s to seal (FreeDOS
  has no ACPI, so a clean QMP quit is what flushes the qcow2).

## Using a clone

A clone boots past the FDCONFIG menu (it picks option 2 after five seconds),
runs `FDAUTO.BAT`, starts the agent last and reports `ready`. The agent is the
exec-only legacy tier (PRD §7.4): a command runs through `COMMAND.COM`, and its
output comes back when it exits.

```sh
vmlab exec dos -- ver
vmlab exec dos -- dir C:\\FREEDOS
```

DOS runs one program at a time: the agent is the foreground program, so the
console shows its banner rather than a prompt, and it answers nothing else
while a command runs. `vmlab cp` and `vmlab shell` refuse by name — the agent
has no file transfer and no terminal. `vmlab vm stop` powers the guest off
through the agent's APM call. Press Ctrl-Break at the console to stop the agent
and get a prompt.

The agent cannot be replaced over its own channel, so `vmlab up` leaves it as
sealed; rebuild the template to pick up a newer one.

## Build

```sh
just freedos-build           # runs fetch-deps.sh, then builds; idempotent
# or directly:
cd freedos-1.3 && ./fetch-deps.sh && vmlab template build
```

The build needs vmlab's DOS agent (`VMLABAGT.EXE`, from
`guest/build-agent-legacy.sh`) among its guest assets; without it the bootstrap
ISO carries no `LEGACY\DOS` and the agent never answers.

## Publish

FreeDOS is redistributable, so the built template can be pushed (authenticate
once with `vmlab template login`):

```sh
just freedos-push            # -> ghcr.io/vmlabdev/vmlab-templates/freedos-1.3:1.3
```

## Bumping the version

Update `SHA256`/`URL` in `fetch-deps.sh` (sums in the release's `verify.txt` on
ibiblio) and `version` in `vmlab.wcl`.

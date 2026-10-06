# TempleOS

[TempleOS](https://templeos.org/) — Terry A. Davis's 64-bit public-domain
hobby operating system: a single-address-space, ring-0, non-networked
"Commodore 64 of the 21st century" written in its own HolyC language, with a
640×480 16-colour graphical shell.

This template downloads the official `TempleOS.ISO`, boots it, drives the
CD's built-in installer onto a blank RedSea hard disk, types the vmlab guest
agent in, and seals the installed disk. TempleOS is public domain, so the built
template is freely redistributable and is published to
`ghcr.io/vmlabdev/vmlab-templates/templeos`.

## Build

```
vmlab template build     # ~12 minutes: 2-3 for the install, ~8 typing the agent
```

The ISO is downloaded and sha256-verified into the artefact cache — no
`fetch-deps.sh`. `scripts/install.ws` works in three stages:

1. **Install.** TempleOS has no answer file and its bitmap font defeats OCR,
   so the two variable-timing prompts (the first install question after boot,
   and "Reboot Now" after the copy) are matched with small reference images
   under `scripts/images/`; the intervening yes/no prompts are answered on a
   short fixed delay. It answers **yes** to "install to hard drive" and to
   "installing inside a VM?" (which lets `OSInstall.HC` auto-partition, format
   and copy), then **no** to "Reboot Now" (a reboot would boot the CD again)
   and "Take Tour".
2. **Agent.** TempleOS reads no ISO 9660 and has no network, so the agent
   cannot come in on the bootstrap ISO. The script types it at the shell
   (`vmlab::templeos_agent_script()`, about twelve thousand keystrokes over QMP
   at 40 ms each). The session is still the CD boot, where `~` is the CD's
   `T:/Home`, so the script first runs `HomeSet("C:/Home")`: the agent's
   source then lands in the installed `C:/Home/VmlabAgt.HC` and its start-up
   lines in `C:/Home/MakeHome.HC.Z`, which `StartOS.HC` includes at every
   boot. The agent starts at once, and the build waits for its handshake on
   COM1.
3. **Boot loader.** The installer's master boot loader menu (`0. Old Boot
   Record` / `1. Drive C` / `2. Drive D`) waits for a key forever. Over
   `exec`, the script patches the loader's key read into a fixed `1` and
   reinstalls it with `BootMHDIns('C')`, so a clone boots Drive C unattended.
   It then checks over `exec` that the agent is registered on `C:` and powers
   off cleanly (a QMP quit — TempleOS has no ACPI, so a hard kill could leave
   the RedSea image unbootable).

## Using a clone

A clone boots straight into TempleOS, starts the agent from
`~/MakeHome.HC.Z`, and reports `ready`. The agent is the exec-only legacy tier
(PRD §7.4): a command is HolyC source, compiled and run in the agent's task,
and what it prints comes back as stdout.

```
vmlab exec temple -- 'Dir;'
vmlab exec temple -- '"hello %d\n",42;'
```

An exception, including a compile error, exits 1 with the compiler's report.
`vmlab cp` and `vmlab shell` refuse by name: the agent has no file transfer and
no terminal. The agent runs one command at a time, so a long-running command
holds the channel until it returns. `vmlab console <vm>` still shows the
desktop.

## Notes

- **Hardware.** The shipped `templeos` profile: i440fx + SeaBIOS (legacy MBR
  boot), an IDE/ATA disk (TempleOS's only disk driver), plain std VGA (it
  drives VBE directly), QMP keyboard input (over VNC, TempleOS sees each shift
  a keystroke late, which would garble the typed agent) and a 16550 on COM1
  for the agent. The profile's e1000 NIC is unused — TempleOS has no
  networking.
- **Drive D.** The installer also puts a copy of TempleOS on `D:`. The agent
  is installed on `C:` only, and the patched boot loader always boots `C:`.
- **Agent updates.** The agent is the legacy tier, which cannot be replaced
  over its own channel; `vmlab up` leaves it as sealed. Rebuild the template
  to pick up a newer agent.

## Refreshing

TempleOS releases are rare. To update: download the new `TempleOS.ISO`, put its
`sha256` and version in `vmlab.wcl`, rebuild, and — if the installer's prompt
wording or layout changed — re-capture the two reference images under
`scripts/images/` (each is a ≤7-pixel-tall crop of the prompt text, which keeps
the matcher on its exact full-scan path rather than the coarse pyramid pass
that blurs thin bitmap text). A new release can also move the boot loader's
key read; the build fails by name if the patch finds no `XOR AH,AH; INT 16h`.

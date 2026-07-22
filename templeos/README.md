# TempleOS

[TempleOS](https://templeos.org/) — Terry A. Davis's 64-bit public-domain
hobby operating system: a single-address-space, ring-0, non-networked
"Commodore 64 of the 21st century" written in its own HolyC language, with a
640×480 16-colour graphical shell.

This template downloads the official `TempleOS.ISO`, boots it, and drives the
CD's built-in installer onto a blank RedSea hard disk — then seals the
installed disk. TempleOS is public domain, so the built template is freely
redistributable and is published to `ghcr.io/vmlabdev/vmlab-templates/templeos`.

## Build

```
vmlab template build     # ~2-3 minutes (mostly the auto-install copy)
```

The ISO is downloaded and sha256-verified into the artefact cache — no
`fetch-deps.sh`. `scripts/install.ws` drives the installer over the live
screen: TempleOS has no answer file, no networking and no guest agent, and its
bitmap font defeats OCR, so the two variable-timing prompts (the first install
question after boot, and "Reboot Now" after the copy) are matched with small
reference images under `scripts/images/`; the intervening yes/no prompts are
answered on a short fixed delay. It answers **yes** to "install to hard drive"
and to "installing inside a VM?" (which lets `OSInstall.HC` auto-partition,
format and copy), then **no** to "Reboot Now" and "Take Tour", and powers off
cleanly (a QMP quit — TempleOS has no ACPI, so a hard kill could leave the
RedSea image unbootable).

## Notes

- **`agent = false`.** TempleOS cannot run the vmlab guest agent, so clones
  never report `ready` and have no `exec`/`cp`/`shell`. Interact with a clone
  through its console (`vmlab console <vm>`).
- **Boot menu keypress.** A clone boots its installed MBR into the *TempleOS
  Boot Loader* menu (`Drive C` / `Drive D` / `Old Boot Record`), which waits
  for a selection — press **1** (Drive C) at the console to boot into TempleOS.
  This is inherent to TempleOS's installer, not a vmlab limitation.
- **Hardware.** The `windows-legacy` profile fits it: i440fx + SeaBIOS (legacy
  MBR boot), an IDE/ATA disk (TempleOS's only disk driver) and plain std VGA
  (it drives VBE directly). The profile's e1000 NIC is unused — TempleOS has no
  networking.

## Refreshing

TempleOS releases are rare. To update: download the new `TempleOS.ISO`, put its
`sha256` and version in `vmlab.wcl`, rebuild, and — if the installer's prompt
wording or layout changed — re-capture the two reference images under
`scripts/images/` (each is a ≤7-pixel-tall crop of the prompt text, which keeps
the matcher on its exact full-scan path rather than the coarse pyramid pass
that blurs thin bitmap text).

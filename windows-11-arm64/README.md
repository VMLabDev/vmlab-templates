# Windows 11 Enterprise (Evaluation) on aarch64 — EXPERIMENTAL

Builds `aarch64/windows-11-arm64` into the local template store. vmlab maps
`arch = "aarch64"` onto the QEMU `virt` machine + aarch64 UEFI firmware
automatically (the `windows-11` profile's `q35`/`ovmf` are x86 hints that get
overridden), and emits `tpm-tis-device` for the TPM. The QEMU plumbing is
sound; this template is marked experimental because of two practical blockers
— read both before spending hours on a build.

This template is **not** part of `just build-arm64`: it can't be fully
automated because Microsoft does not publish a stable ARM64 eval ISO link/hash.
Build it on its own with `just windows11-arm64-build` after filling in the ISO.

## Before you build: fill in the ISO

`vmlab.wcl` ships with a tripwire all-zero `sha256` and the eval-center page as
the `url`; the build refuses to run until you replace them:

1. Download the **Arm64 ISO** from
   <https://www.microsoft.com/en-us/evalcenter/evaluate-windows-11-enterprise>
   (or `MediaCreationTool.exe /MediaArch arm64 /MediaEdition Enterprise /Retail`).
2. `sha256sum` it, then set `url`, `sha256`, and `version` in `vmlab.wcl`.

## Build

```sh
./fetch-deps.sh          # one-time: ARM64 virtio drivers + guest MSIs
vmlab template build     # SLOW — see below
vmlab template list      # → aarch64/windows-11-arm64@<version>
```

`autounattend.xml` is the x86 answer file with every `processorArchitecture`
switched to `arm64`, the single Enterprise-eval image (index 1), and ARM64
guest-tools/agent MSI names. Like the other client templates the image is
sysprep-generalized — AppX packages are stripped first so `sysprep /generalize`
succeeds.

## Known risks

- **Speed.** On an x86 host there is no KVM for aarch64, so the entire guest
  runs under TCG emulation. A Windows install that takes ~30 min natively can
  take **many hours** here; `scripts/install.wisp` waits up to 8h for the guest
  agent. On a real arm64 host (KVM) it is far quicker.
- **Guest-tools/agent packaging.** ARM64 boot drivers (`viostor`/`netkvm`
  under `w11/ARM64`) are present on `virtio-win.iso`, but the guest-tools and
  `qemu-ga` packaging for ARM64 has varied across releases. `fetch-deps.sh`
  copies the first match it finds and **warns** if a name is missing — if you
  see a warning, check the ISO and update the first-logon command lines in
  `unattend/autounattend.xml` to match. The build's "finished" signal is the
  guest agent responding, so the agent MSI in particular must install.

If the build proves unworkable on your host, that's an accepted limitation of
this experimental template — the x86 Windows templates are independent of it.

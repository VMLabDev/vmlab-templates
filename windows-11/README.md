# Windows 11 Enterprise (Evaluation) template

Requires vmlab 0.30.0-alpha or later (the `win3d` variant 0.31.0-alpha or
later). The template is a base plus variants (see
[Base and variants](#base-and-variants)), which vmlab 0.30.0-alpha
introduced. The first-boot script also calls `vm.boot_id()` and
`vm.wait_rebooted()`, so the template records wscript surface 2, and an older
vmlab refuses to clone it with a message to upgrade.

Builds `x86_64/windows-11` into the local template store from the Microsoft Evaluation
Center ISO (downloaded and sha256-verified automatically), fully unattended via
`unattend/autounattend.xml`. The `windows-11` profile supplies the q35/OVMF + secure boot + TPM 2.0 hardware Windows 11 requires.

```sh
./fetch-deps.sh          # one-time: virtio drivers + guest MSIs into unattend/
vmlab template build     # ~30-45 minutes
vmlab template list      # → windows-11 26100.1742.<N>, with a #standard row marked default
```

What happens (`scripts/install.ws` narrates it in the build log):

1. The build VM boots the eval ISO; the script types through the
   "Press any key to boot from CD or DVD" prompt (and resets + retries if
   the firmware shell appears instead).
2. `autounattend.xml` (on the UNATTEND ISO built from `unattend/`) loads
   the virtio storage/net drivers in WinPE, partitions UEFI/GPT, installs
   the single **Enterprise Evaluation** image, sets `Administrator` / `vmlab123!`, and on first logon installs
   the virtio guest tools and the vmlab guest agent.
3. The script waits for the guest agent — that's the "install finished" signal.
4. It disables Windows Update, copies `generalize.ps1` and
   `sysprep-unattend.xml` from the UNATTEND ISO into
   `C:\ProgramData\vmlab\sysprep\`, and shuts the VM down. vmlab seals
   this as the **base**, which is installed and patched but not generalized.
5. The `standard` variant boots a linked overlay of the base and runs
   `scripts/generalize.ws`. That runs the staged `generalize.ps1`: it
   strips per-user and provisioned AppX packages (otherwise `sysprep
   /generalize` aborts on client SKUs), runs `sysprep /generalize /oobe`
   with `sysprep-unattend.xml`, and the VM powers off. vmlab seals the
   generalized overlay as the `standard` variant.

## Base and variants

A built version holds an unsealed base disk and named, sealed variants. Each
variant is a qcow2 overlay on the base. This template defines two variants,
`standard` (the default) and `win3d`:

- `x86_64/windows-11` (no `#`) still means the sealed `standard` variant,
  so existing lab files keep working unchanged.
- `x86_64/windows-11#standard` names it explicitly.
- `x86_64/windows-11#win3d` is `standard` plus the vmlab-win3d 3D driver
  package, for labs with `gpu { mode = "vulkan" }`. See
  [The win3d variant](#the-win3d-variant).
- `#base` is reachable only from template builds. A lab that asks for it is
  refused, because the base is not generalized and every clone would share
  one SID and computer name.

The base has no first-boot script. `scripts/firstboot.ws` belongs to the
`standard` variant, because only a generalized image has a specialize pass
to wait for.

### The win3d variant

`#win3d` installs [vmlab-win3d](https://github.com/VMLabDev/vmlab-win3d) on
the base before generalizing it: a test-signed virtio-gpu WDDM driver with
Direct3D 9/10/11 and OpenGL user-mode drivers, the Venus Vulkan ICD and a
D3D12-over-Vulkan bridge, so a clone renders D3D, OpenGL and Vulkan on the
host's GPU through virtio-gpu Venus with nothing more to install. The
package version is pinned once, in `fetch-deps.sh` (`WIN3D_VERSION`, with
the release zip's sha256); it is staged into `win3d/` (gitignored) and rides
the variant build as the WIN3D ISO.

```sh
./fetch-deps.sh                                   # stages win3d/ too
vmlab template build windows-11 --variant win3d   # onto the newest installed version, ~20-30 min
```

What `scripts/win3d-setup.ws` does, before `scripts/generalize.ws` seals
the overlay:

1. Copies the bundle off the WIN3D ISO to `C:\vmlab-win3d` and runs its
   `Install.cmd` as SYSTEM. The installer trusts the test certificate,
   turns test signing on, restarts Windows, installs the driver and the
   runtime, and restarts again; the script follows each restart by boot id
   (`vm.boot_id()` / `vm.wait_rebooted()`) until
   `C:\ProgramData\vmlab-win3d\state.json` says `Installed`, or fails
   with the installer's journal tail.
2. Runs `vulkaninfo --summary` (x64 and x86) in the console user's session,
   because Vulkan enumerates nothing from SYSTEM. With nobody logged on it
   arms a one-shot autologon, reboots once more, and clears the values
   again afterwards. Both summaries must list a `Virtio-GPU Venus` device.
3. Checks the end state (`scripts/win3d-verify.ps1`): test signing on in the
   BCD and active in the kernel, the display device bound to `viogpu3d.inf`
   with problem code 0, both Vulkan ICDs registered, the `vmlab-win3d-resume`
   task gone and `vmlab-win3d-repair` present, no reboot pending, no
   autologon values left. Then generalize runs as for `standard`.

**Building `#win3d` needs vmlab 0.31.0-alpha or later and a Venus-capable
host.** The installer's verify needs the driver started, which only a
virtio-gpu device with the VIRGL feature and blob resources gives, so the
variant block declares `gpu { mode = "vulkan" }`. vmlab 0.31.0-alpha
introduced `gpu {}` on template and variant blocks: the build VM gets it
resolved like a lab VM's, on the host's default GPU from
`~/.config/vmlab/config.wcl` (or `host_gpu` names one), with that GPU's
`qemu_binary` and `qemu_env` and the Vulkan loader filtered to it. The build
log says which: `build VM gpu: mode=vulkan host_gpu=...`. The host needs a GPU
Venus works on (AMD with RADV, Intel with ANV, or an RTX 5090; vmlab-win3d's
`docs/host.md`). Nothing about the build GPU is recorded in the variant.

Using it:

- A clone **must** declare `gpu { mode = "vulkan" }` (or `"virgl"`), with
  `host_gpu` naming a GPU from `~/.config/vmlab/config.wcl` or taking the
  host's default. Without a `gpu {}` block the clone boots with plain
  `virtio-vga`, the driver package finds no Venus device, and there is no 3D.
- `secure_boot = false` is recorded in the variant, so `#win3d` clones boot
  without Secure Boot (the `windows-11` profile turns Secure Boot on) and the test-signed
  driver loads; `standard` clones are unaffected.
- The sysprep answer file is shared with `standard` and unchanged (no
  `PersistAllDeviceInstalls`): generalize keeps the package in the driver
  store and drops the device binding, and the clone's specialize pass binds
  the device to it again. `scripts/firstboot.ws` holds `ready` until that
  pass is over.
- The clone keeps the `vmlab-win3d-repair` startup task (part of the
  package), the test certificate in the Root and TrustedPublisher stores,
  and `testsigning` in the BCD.

### Adding a variant

A variant is a `variant` block in `vmlab.wcl` with its own provisions. List
them before `scripts/generalize.ws`, so the variant's changes are made on the
installed base and then generalized with it:

```wcl
variant "tools" {
  description = "standard, plus a lab toolset"
  first_boot  = "scripts/firstboot.ws"
  provision "scripts/install-tools.ws" { }
  provision "scripts/generalize.ws" { }
}
```

Build only the new variant onto the newest installed version, without
rebuilding the base or `standard`:

```sh
vmlab template build windows-11 --variant tools
vmlab template list      # → a #tools row under the version, beside #standard
```

Add `--version <version>` to build it onto an older installed version. A lab
then selects it with `template = "x86_64/windows-11#tools"`.

Notes:

- `fetch-deps.sh` stages redistributable binaries (virtio drivers, MSIs) into
  `unattend/`; they are gitignored, only the answer file is tracked. `just`
  runs it automatically before the build.
- The evaluation license runs 90 days from install. The `sha256` in
  `vmlab.wcl` is authoritative — the build refuses any ISO that doesn't match
  it. If the `url` ever 404s (eval-center CDN paths can change), grab the
  current direct link for this build from the eval center and keep the same
  `sha256` (or update both for a newer build via `sha256sum`).
- The `standard` variant is **generalized**: each clone's first boot replays
  `sysprep-unattend.xml` — fresh SID, auto-generated computer name, OOBE
  skipped, `Administrator` / `vmlab123!` restored, no autologon — so
  clones are domain-joinable out of the box. (the build-time name VMLAB-WIN11 is replaced per clone)
- `scripts/firstboot.ws` holds a clone's `ready` until user OOBE has exited.
  That exit clears Winlogon's autologon values, so an autologon a lab sets up
  before it is lost on the next boot; after `ready` it sticks.
- First boot then reboots the clone once from inside Windows. The lab log
  records the boot id before and after, and each reboot request's exit code.
  A clone often reboots in a few seconds, too fast for the agent to be seen
  dropping, so the reboot is watched by boot id (`vm.wait_rebooted()`). A
  request that has not taken after ~60 s, with the guest still on the same
  boot, is made again, aborting any delayed shutdown already scheduled, then
  through `Restart-Computer`. A host restart happens only if all three fail,
  after ~3 minutes.
- First boot reads `HKLM\SOFTWARE\vmlab` `SysprepContext` to decide whether
  the clone needs the XAML hook and the 5-minute warm hold. A failed read is
  retried up to five times. If none succeeds, the log says the clone defaulted
  to the hook and the hold.

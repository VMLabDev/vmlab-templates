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
4. It disables Windows Update, uninstalls OneDrive, copies `generalize.ps1` and
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

OneDrive is removed from the base before generalize, so both variants inherit
the removal. Provisioning clears its first-logon setup from the default user
hive, removes leftover Start menu shortcuts and Explorer navigation entries,
and sets `DisableFileSyncNGSC=1` to prevent file sync after feature updates.
If shell DLLs remain locked, provisioning reboots and requires cleanup to
succeed before generalize.

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
  `virtio-vga` (nothing of the build GPU is recorded): the package's driver
  binds to that device but cannot start on it, so there is no 3D.
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

### Timeout recovery rebuild

The local `26100.1742.10#win3d` rebuild uses the unreleased `0.1.3` package
from vmlab-win3d commit `8f0a61f2baae7e6c8e1ae3ed9a0660cead0c6404`.
Its KMD version is `100.6.101.58104`. The driver implements adapter timeout
reset and restart, cancels pending transport requests, restores legacy
contexts, and rejects lost opaque Vulkan/VirGL state. It also handles both
queue and configuration causes for INTx status 3.

The user-mode driver reports device loss when reset revokes a cached
batch-feedback mapping. Native x64/x86 production-code probes reproduce
the old access violation and confirm the corrected device-loss result.

Driver PR: https://github.com/VMLabDev/vmlab-win3d/pull/3.

The candidate's `SHA256SUMS` records:

```text
725a40921b1103542d73442e21b106732f00fcfa5b12f2b96f907128b644945a  vmlab-win3d-0.1.3.zip
555954bfce7512f005d8d593713c623cea1f7a51d63189763b4b8f6cfb5555f5  vmlab-win3d-0.1.3/manifest.json
```

The package and manifest were checked against the build's `SHA256SUMS`,
then all files were checked against `manifest.json`. The package is staged
flat in `win3d/`, with `Install.cmd` and `manifest.json` at the WIN3D ISO
root. No GitHub release was published. `fetch-deps.sh` still pins the
published `0.1.2-alpha` bundle and replaces this local candidate if rerun.

The new version has independent reflinks of the base and `standard` variant
from `26100.1742.7`; only `win3d` is rebuilt. Earlier versions remain in place.
The sealed `win3d/disk.qcow2` SHA256 is
`4aaed1a2eab48884c18188ed5ba5ffd10112170c672b4fddaa35d2fe778ad512`.
The build passed both Vulkan architectures and all static checks, then
sysprep generalized on pass 0.

The old `58101` driver reproduced bugcheck `0x116` on a forced native TDR,
with reset returning `0xc00000bb`. Event 1001, WER BlueScreen code 116,
and the minidump agree. The original unforced OOBE stall is not attributed
to a specific cause.

Four fresh native first boots passed, twice on NVIDIA and twice on AMD.
All 24 Vulkan and x64/x86 D3D11 hardware readbacks passed before and after
forced TDR. Both recovery counters advanced from zero to one, both statuses
were zero, test policy was restored, and Windows continued without a
bugcheck or OS reboot. First-boot counters were zero in every run.

The intermediate `.9` checked-copy candidate fails x86 D3D11 device creation
on both native NVIDIA and AMD before forced TDR. It is retained for evidence.
The `.10` replacement uses direct memory access with a thread-scoped x86
exception frame. Native production-code feedback tests also pass all ten cases.

A OneDrive `ucrtbase.dll` access violation after forced TDR was seen in three
runs. The owner explicitly excluded OneDrive and stopped its investigation.
It was deliberately not pursued and does not block the acceptance bar of
recovered Vulkan and x64/x86 D3D11 readback with no bugcheck.

Native vmlab-hv reset currently lacks an explicit renderer-worker/GPU-idle
acknowledgement and logs teardown errors without rejecting reset. Removed
guest BAR aliases limit the memory-lifetime risk, but functional recovery
does not prove the full backend quiescence contract. The driver PR records
this limitation separately from the owner's functional acceptance. The host
contract and current gap are documented in the regression PR:
https://github.com/VMLabDev/vmlab-hypervisor/pull/4.

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

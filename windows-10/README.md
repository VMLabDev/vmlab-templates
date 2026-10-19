# Windows 10 Enterprise (Evaluation) template

Requires vmlab 0.30.0-alpha or later. The template is a base plus variants
(see [Base and variants](#base-and-variants)), which vmlab 0.30.0-alpha
introduced. The first-boot script also calls `vm.boot_id()` and
`vm.wait_rebooted()` (wscript surface 2).

Builds `x86_64/windows-10` into the local template store from the Microsoft Evaluation
Center ISO (downloaded and sha256-verified automatically), fully unattended via
`unattend/autounattend.xml`. Windows 10 needs no TPM/secure boot, so the `windows-10` profile leaves both off.

```sh
./fetch-deps.sh          # one-time: virtio drivers + guest MSIs into unattend/
vmlab template build     # ~30-45 minutes
vmlab template list      # → windows-10 19045.2006.<N>, with a #standard row marked default
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
variant is a qcow2 overlay on the base. This template defines one variant,
`standard`, and it is the default:

- `x86_64/windows-10` (no `#`) still means the sealed `standard` variant,
  so existing lab files keep working unchanged.
- `x86_64/windows-10#standard` names it explicitly.
- `#base` is reachable only from template builds. A lab that asks for it is
  refused, because the base is not generalized and every clone would share
  one SID and computer name.

The base has no first-boot script. `scripts/firstboot.ws` belongs to the
`standard` variant, because only a generalized image has a specialize pass
to wait for.

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
  skipped, `Administrator` / `vmlab123!` restored with one autologon — so
  clones are domain-joinable out of the box. (the build-time name VMLAB-WIN10 is replaced per clone)

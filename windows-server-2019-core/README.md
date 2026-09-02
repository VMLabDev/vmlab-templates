# Windows Server 2019 (Evaluation, Server Core) template

Builds `x86_64/windows-server-2019-core` into the local template store from
the Microsoft Evaluation Center ISO (downloaded and sha256-verified
automatically), fully unattended via `unattend/autounattend.xml`.

Same ISO, same answer file and same build as `windows-server-2019/`, with one
line changed: the installed image is index 1, **Standard Evaluation (Server
Core)**, so the guest has no Desktop Experience — no explorer, no MMC, and a
much smaller patch and attack surface.

```sh
./fetch-deps.sh          # one-time: virtio drivers + guest MSIs into unattend/
vmlab validate
vmlab template build     # ~30-45 minutes
vmlab template list      # → x86_64/windows-server-2019-core@17763.737
```

What happens (`scripts/install.ws` narrates it in the build log):

1. The build VM boots the eval ISO; the script types through the
   "Press any key to boot from CD or DVD" prompt (and resets + retries if
   the firmware shell appears instead).
2. `autounattend.xml` (on the UNATTEND ISO built from `unattend/`) loads
   the virtio storage/net drivers in WinPE, partitions UEFI/GPT, installs
   **Standard Evaluation (Server Core)**, sets `Administrator` /
   `vmlab123!`, and on first logon installs the virtio guest tools and the
   vmlab guest agent.
3. The script waits for the guest agent — that's the "install finished"
   signal.
4. The script stages `unattend/sysprep-unattend.xml` onto the disk and runs
   `sysprep /generalize /oobe /shutdown`, which powers the VM off; vmlab
   seals the generalized disk.

Notes:

- Nothing vmlab needs is missing on Core: the guest agent, `vmlab exec`,
  `vmlab cp` and the SSH facade are all agent-side, and PowerShell and
  `cmd.exe` are present. What is missing is the console desktop — open the
  VM's console and you get one `cmd.exe` window (`sconfig` for the built-in
  configuration menu).
- The image index is the only difference from the Desktop Experience
  template. Confirm it against a given ISO with
  `dism /Get-WimInfo /WimFile:D:\sources\install.wim` if a future eval build
  reorders its images.
- `fetch-deps.sh` stages redistributable binaries (virtio drivers, MSIs)
  into `unattend/`; they are gitignored, only the answer file is tracked.
- The evaluation license runs 180 days from install. To move to a newer
  eval build, update `version`, the `url`, and `sha256` in `vmlab.wcl`
  (sha256: download the ISO once and `sha256sum` it).
- The sealed image is **generalized**: each clone's first boot replays
  `sysprep-unattend.xml` — fresh SID, auto-generated computer name, OOBE
  skipped, `Administrator` / `vmlab123!` restored with one autologon — so
  clones are domain-joinable out of the box (the build-time computer name
  VMLAB-WS2019C is replaced per clone). First boot of a clone takes a few extra
  minutes while specialize runs.

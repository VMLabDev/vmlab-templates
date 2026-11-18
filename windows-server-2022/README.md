# Windows Server 2022 (Evaluation) template

Builds `x86_64/windows-server-2022` into the local template store from the Microsoft Evaluation
Center ISO (downloaded and sha256-verified automatically), fully unattended via
`unattend/autounattend.xml`.

```sh
./fetch-deps.sh          # one-time: virtio drivers + guest MSIs into unattend/
vmlab template build     # ~30-45 minutes
vmlab template list      # → x86_64/windows-server-2022@20348.169
```

What happens (`scripts/install.ws` narrates it in the build log):

1. The build VM boots the eval ISO; the script types through the
   "Press any key to boot from CD or DVD" prompt (and resets + retries if
   the firmware shell appears instead).
2. `autounattend.xml` (on the UNATTEND ISO built from `unattend/`) loads
   the virtio storage/net drivers in WinPE, partitions UEFI/GPT, installs
   **Standard Evaluation (Desktop Experience)**, sets `Administrator` / `vmlab123!`, and on first logon installs
   the virtio guest tools and the vmlab guest agent.
3. The script waits for the guest agent — that's the "install finished" signal.
4. The script stages `unattend/sysprep-unattend.xml` onto the disk and runs
   `sysprep /generalize /oobe /shutdown`, which powers the VM off; vmlab seals
   the generalized disk.

Notes:

- `fetch-deps.sh` stages redistributable binaries (virtio drivers, MSIs) into
  `unattend/`; they are gitignored, only the answer file is tracked. `just`
  runs it automatically before the build.
- The evaluation license runs 180 days from install. The `sha256` in
  `vmlab.wcl` is authoritative — the build refuses any ISO that doesn't match
  it. If the `url` ever 404s (eval-center CDN paths can change), grab the
  current direct link for this build from the eval center and keep the same
  `sha256` (or update both for a newer build via `sha256sum`).
- The sealed image is **generalized**: each clone's first boot replays
  `sysprep-unattend.xml` — fresh SID, auto-generated computer name, OOBE
  skipped, `Administrator` restored with the build password, which the first boot replaces (see [Login password](#login-password)), no autologon — so
  clones are domain-joinable out of the box. (the build-time computer name VMLAB-WS2022 is replaced per clone)

## Login password

Each clone gets its own password for `Administrator` at its first boot
(`scripts/firstboot.ws`), after sysprep's OOBE pass and before the clone is
reported ready, so no lab starts with the `vmlab123!` build password from the
answer files.

- To choose a password, declare a login for the account on the machine in
  the lab file: `login "admin" { user = "Administrator" password = "..." }`. The first boot sets it. It must meet the Windows
  password policy. With the login declared, `vmlab exec`, `vmlab shell` and
  RDP app sharing log on as that account.
- Every account without a declared password gets one random 24-character
  password. Read it with
  `vmlab exec <vm> -- cmd /c type C:\ProgramData\vmlab\password.txt`
  (only SYSTEM and Administrators can read the file).

`vmlab exec`, `vmlab shell` and provisions without a declared login run
through the guest agent as SYSTEM and need no password.

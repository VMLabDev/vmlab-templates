# Ubuntu Server 26.04 LTS template

Builds `x86_64/ubuntu-26.04` into the local template store from the official
Ubuntu **cloud image** + cloud-init (the `ubuntu-24.04` example uses the
subiquity installer ISO instead; this is the simpler cloud-image path).

```sh
vmlab validate
vmlab template build
vmlab template list      # → x86_64/ubuntu-26.04@26.04
```

What happens (`scripts/install.ws` narrates it in the build log):

1. The build VM boots the cloud image with `cloudinit/` attached as a
   `CIDATA` volume (NoCloud datasource).
2. cloud-init creates user `vmlab` (password `vmlab`, passwordless sudo),
   installs the vmlab guest agent (from the auto-attached VMLAB ISO), enables it, and disables cloud-init for
   subsequent boots.
3. The script waits for the guest agent to respond and cloud-init to finish.
4. vmlab powers the VM off and seals the disk into the store.

The cloud image is pinned to `releases/26.04/release-20261108/` so upstream
refreshes do not change the download. To update it, choose a dated release
directory and update both `url` and `sha256` in `vmlab.wcl`. Verify that
directory's `SHA256SUMS.gpg` signature over `SHA256SUMS` with the Ubuntu cloud
image signing key `D2EB44626FDDC30B513D5BB71A5D6C4C7DB87C81`, then use the
checksum for `ubuntu-26.04-server-cloudimg-amd64.img`. Regenerate the unified
definition with `bash scripts/generate-unified-wcl.sh`.

The profile is `linux-modern` with `firmware = "seabios"` — cloud images
boot via BIOS.

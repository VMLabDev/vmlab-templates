# Windows 8.1 Enterprise (x86) template

Builds `x86/windows-8.1` from the local Enterprise ISO named in
`vmlab.wcl`. Run `./fetch-deps.sh` before `vmlab template build` to stage
the virtio-serial driver used by the guest agent.

Windows 8.1's built-in OneDrive cannot be uninstalled. Instead,
`unattend/disable-onedrive.ps1` disables it by policy before generalize.
The script sets `DisableFileSync=1` for the built-in client and
`DisableFileSyncNGSC=1` for newer sync clients, under both the OneDrive
and SkyDrive policy keys. It leaves Windows shell files intact.

Microsoft documents the uninstall restriction:
https://support.microsoft.com/en-us/onedrive/turn-off-disable-or-uninstall-onedrive

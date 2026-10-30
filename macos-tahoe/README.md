# macos-tahoe

macOS Tahoe 26 for Intel, the final Intel macOS, on vmlab's `macos` profile.
The template carries the vmlab agent and nothing else.

- Credentials: `vmlab` / `vmlab`, an administrator. The login window shows on
  every boot; there is no auto-login.
- The agent runs as root under launchd (`dev.vmlab.agent`). It serves `exec`,
  `cp`, `shell`, metrics and the clipboard; the clipboard needs someone logged
  in at the console. Clones turn ready on its handshake.
- SSH (Remote Login) is off, as macOS ships it. The template has no SSH host
  keys.
- Each clone's first boot sets its ComputerName, LocalHostName and HostName to
  its VM's name. If sshd is on by then, it also regenerates the host keys.
- The Keyboard Setup Assistant does not appear: the build records QEMU's USB
  keyboard as an ANSI keyboard.
- Screen 1280x800 (OpenCore's GOP mode on VMware SVGA). There is no 3D: Apple
  ships no virtio GPU driver for x86.
- Local-only. Apple's licence allows macOS only on Apple hardware, so the
  definition has no `registry`; build it on the host that runs it.

## Requirements

- vmlab with the `macos` profile and the macOS agent (`macos/` on the VMLAB
  bootstrap ISO).
- KVM, and `kvm.ignore_msrs=1` on the host. Without it XNU's Intel MSR reads
  fault during boot. `vmlab up` warns about this; a template build does not.

  ```sh
  echo "options kvm ignore_msrs=1 report_ignored_msrs=0" | sudo tee /etc/modprobe.d/kvm-msrs.conf
  echo 1 | sudo tee /sys/module/kvm/parameters/ignore_msrs   # until the next boot
  ```

- About 13 GB of downloads, about 1 GB of it cached in `../iso/`, and about 40
  GB free for the build disk.

## Build

```sh
./fetch-deps.sh         # Apple's recovery image and OpenCore, staged
vmlab template build    # about 75 minutes
```

`just macos-tahoe-build` from the repo root does both.

`fetch-deps.sh` stages three things, all gitignored:

| Path | What |
|---|---|
| `bootdisk/` | The build's FAT boot disk: OpenCore with the `build` config, and Apple's recovery image under `com.apple.recovery.boot/`. |
| `setup/EFI/` | OpenCore with the `disk` config, for the installed disk's ESP. `setup/` is the MACSETUP ISO, and `recovery.sh` and the keyboard plist beside it are tracked. |
| `opencore/smbios.conf` | The iMac20,1 serial, board serial, UUID and ROM. These are generated once with macserial and kept, so a rebuild keeps the same identity. |

The recovery image is what `../iso/fetch-macos-tahoe.sh` downloads from
Apple's Internet Recovery service. The script checks it against Apple's
RSA-signed chunklist.

OpenCore is acidanthera's OpenCorePkg 1.0.8 release, pinned by sha256 in
`fetch-deps.sh`. `opencore/mkconfig.py` writes both configs from that
release's own `Sample.plist`, and the release's `ocvalidate` checks them.
To bump OpenCore, change `OC_VERSION` and `OC_SHA256`.

## How the build works

The build VM boots OpenCore from the FAT boot disk. `scripts/install.ws`
drives the picker and the Recovery Terminal over the screen. A fresh macOS
has no unattended hook, so the work inside Recovery is done by
`setup/recovery.sh`, run from the MACSETUP ISO:

1. **Install.** The build boots the recovery image (`NO NAME (dmg)` in the
   picker), opens Utilities > Terminal and runs `recovery.sh install`. That
   erases the largest internal disk to APFS and runs the Recovery's own
   `startosinstall`. `startosinstall` downloads Tahoe from Apple (about 12 GB),
   reboots into the installer, and installs. The build waits for Setup
   Assistant's first screen. This takes 50 to 60 minutes.
2. **Finish.** The build resets the VM into the recovery image again and runs
   `recovery.sh finish`, which does three things:
   - It runs the VMLAB ISO's `macos/install.sh --user vmlab --password vmlab`,
     which installs the agent, skips Setup Assistant, and creates the account
     on first boot.
   - It writes `/Library/Preferences/com.apple.keyboardtype.plist`.
   - It copies OpenCore with the `disk` config into the disk's own EFI system
     partition.
3. **First boot.** The build resets the VM into the installed system. That
   boot goes through the ESP's OpenCore, which is the path a clone takes. The
   build then waits for the agent's handshake, checks the version, the
   account and the keyboard setting, and gives the machine a generic name.
   vmlab shuts it down and seals the disk.

The FAT boot disk and the MACSETUP ISO are build-only. A clone has one disk,
boots with a fresh UEFI VARS, and finds OpenCore in that disk's ESP.

### OpenCore configuration

The two configs differ only in what the picker lists. Everything else is set
by `mkconfig.py`:

- **Kexts and ACPI tables:** none. QEMU's `isa-applesmc` is a real SMC, and
  macOS drives AHCI, virtio-net and the GOP framebuffer natively.
- **CPU:** `ProvideCurrentCpuInfo`, for the MSR 0x35 KVM does not provide, and
  `DummyPowerManagement`.
- **SMBIOS:** iMac20,1, a model Tahoe supports, with the generated serials.
- **Security:** `SecureBootModel = Disabled`. A VM has no T2 chip, and the
  SMBIOS is not one Apple personalises. SIP stays on.
- **Picker:** the text picker (`Builtin`), shown for 5 seconds before it boots
  the default entry. The build reads it by image match: tesseract misreads its
  font. The reference crops are in `scripts/images/`.
- **`build` config:** `ScanPolicy = 0` and auxiliary entries shown, so the
  recovery image on the FAT disk is listed.
- **`disk` config (the clone's):** APFS and HFS+ only (`ScanPolicy = 0x301`),
  auxiliary entries hidden.
  - A fresh VARS puts the firmware's boot option for the disk itself first in
    `BootOrder`. Listed, that option would be the default, and OpenCore would
    boot into itself and stop at "Timeout". Hidden, the default falls to
    Macintosh HD.
  - To reach Recovery on a clone, press a key during the countdown, then
    space.

### The shutdown hang

On an AMD host, Tahoe sometimes panics on the way down and the panic handler
spins every vCPU. This happens on about 2 shutdowns or reboots in 5, and the
guest never resets. The build therefore avoids guest reboots:

- Stages 2 and 3 start with a host reset (a QEMU quit, which flushes the block
  caches, then a fresh start). Stage 2 syncs and unmounts the disk before its
  reset.
- During the install, the build watches the screen. Recovery prints a
  heartbeat line every 20 seconds while it downloads. If the screen stays the
  same for 10 minutes, the build resets the VM and points OpenCore back at the
  installer.
- If the agent does not answer within 20 minutes of the first boot, the build
  resets the VM once.

The final shutdown is vmlab's stop ladder: the agent's shutdown, then ACPI,
then a QEMU quit. The ladder ends a hung guest within about a minute. The same
ladder ends a hung `vmlab down` on a clone.

## Versions

`version = "26.7"`. `startosinstall` installs whatever Tahoe build Apple
serves on the day, and the build fails unless `sw_vers` says 26.x. The
recovery image is pinned by Apple product ID in `../iso/fetch-macos-tahoe.sh`.

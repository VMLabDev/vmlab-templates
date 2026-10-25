# steamos

SteamOS 3.8.14 (build 20260707.10), installed from Valve's Steam Deck
recovery image the same way a Deck is reimaged.

- Credentials: `deck` with no password (Valve's default, and the account both
  sessions log in as), plus `vmlab` / `vmlab`, added by the provision, in
  `wheel` with full `sudo`. SSH is off, as Valve ships it.
- 3D: SteamOS already ships Mesa's Venus Vulkan driver and virgl, so a clone
  with `gpu { mode = "vulkan" }` gets hardware Vulkan and OpenGL on the host
  GPU with nothing added. Without `gpu {}` the clone gets plain virtio-vga
  and software rendering.
- The build needs a Venus-capable host GPU. It boots with
  `gpu { mode = "vulkan" }` and fails unless `vulkaninfo` lists a
  `DRIVER_ID_MESA_VENUS` device and OpenGL runs on virgl.
- Clones boot to **game mode** (gamescope and the Steam client), as a Deck
  does, and land on Steam's first-boot setup. "Switch to Desktop" gives KDE
  Plasma on X11.
- Game mode runs OpenGL on Zink. Out of the box GL in the guest is virgl, so
  Xwayland's buffers are virgl resources, which the Venus render server
  cannot import (`vkr: failed to import resource: invalid res_id`): Venus
  aborts and gamescope crash-loops. The provision adds systemd drop-ins that
  set `MESA_LOADER_DRIVER_OVERRIDE=zink` on `gamescope-session.service` and
  `steam-launcher.service` only (`/etc/systemd/user/<unit>.d/vmlab-zink.conf`).
  Desktop mode keeps virgl, which is faster there.
- The template replaces SteamOS's Venus driver, `libvulkan_virtio.so` in
  `/usr/lib` and `/usr/lib32`, with the same Mesa 25.3.0 release plus the
  Mesa 26.0 fix that lets Venus use the hardware WSI on NVIDIA drivers
  590.48.01 and newer (`venus/build.sh`, `venus/patches/`). SteamOS's own
  copies stay beside them as `libvulkan_virtio.so.steamos`. Without the fix,
  Venus presents every X11 window by CPU copy on an NVIDIA host, and Steam's
  UI in game mode is black (https://github.com/VMLabDev/vmlab/issues/171).
- **Game mode on an NVIDIA host also needs the vmlab render server** with
  vmlab-win3d's `patches/host/virglrenderer/0003`, named by the GPU's
  `qemu_env` `RENDER_SERVER_EXEC_PATH`. NVIDIA's driver turns a dma-buf
  import that also asks for export into a fresh allocation, so without it
  everything Xwayland draws itself (X11 windows that are not flipped, such
  as menus, dialogs and `xterm`) reaches gamescope black. Steam's full-screen
  UI shows either way. AMD needs neither. Desktop mode works on both. Intel
  is untested.
- The default session is `/etc/sddm.conf.d/zz-steamos-autologin.conf`, the
  file `steamos-session-select gamescope` leaves behind.
- vmlab-agent: the recovery image has no unattended-install hook, so the
  installer bakes a oneshot `vmlab-bootstrap.service` into the `/etc` of
  both partition sets, A and B. Valve's bootloader picks the set itself, and
  after a fresh image it can pick B. On the build's first boot the unit
  mounts the VMLAB ISO and runs its `install.sh`.
- The root filesystem is left writable (`steamos-readonly disable`). The
  agent lives at `/usr/local/lib/vmlab/vmlab-agent` on the read-only root,
  and `vmlab machine repair-agent` and the stale-agent refresh on `up` write
  there.
- Disk: 128 GiB virtual. `/home` grows to fill it on first boot (about
  117 GiB).
- Not tested: SteamOS OS updates. An update writes the other partition set's
  root filesystem, and the agent binary is not in that image.
- No push recipe. The template carries Valve's OS image and a bootstrapped
  Steam client, and redistributing them has not been cleared.

## Build

`fetch-deps.sh` stages `disk/steamos.qcow2` (gitignored). It downloads and
sha256-verifies the 3.1 GiB recovery image, then installs it in a throwaway
lab. The live recovery image boots read-only beside a blank target disk.
`installer/install.ws` opens Konsole through the console and runs
`installer/payload/install.sh`. That script runs Valve's
`~/tools/repair_device.sh all` against the target and bakes in the agent
bootstrap. The patched copy of `repair_device.sh` points the script at the
virtio disk instead of `/dev/nvme0n1`, skips the NVMe sanitize, and turns the
Steam Deck BIOS and controller updaters into no-ops. The lab is destroyed
afterwards. The install takes about ten minutes, and the archive stays in
`disk/` so a second run skips the download.

Requires vmlab, `curl`, `bzip2`, `qemu-img`, KVM and Docker on the build
host. Docker runs `venus/build.sh`, which builds the Venus driver in
`debian:trixie` (glibc 2.41, SteamOS 3.8's) into `venus/out/`.

```sh
./fetch-deps.sh
vmlab template build
```

`just steamos-build` runs both.

To bump: pick a newer `steamdeck-oobe-repair-<build>-<version>.img.bz2` from
<https://steamdeck-images.steamos.cloud/recovery/>. Valve publishes no
checksums, so compute the sha256 of the download. Then update `VERSION` and
`SHA256` in `fetch-deps.sh` and `version` in `vmlab.wcl`, and delete
`disk/steamos.qcow2`.

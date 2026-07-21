# home-assistant (aarch64)

Home Assistant OS for **aarch64**, built from the official
**generic-aarch64** image. Store ref: `aarch64/home-assistant`.

## Why generic-aarch64, not the Pi image

The literal Raspberry Pi build (`haos_rpi4-64`) boots via **U-Boot** and does
not run in a VM. The **generic-aarch64** image is the same Home Assistant OS
built for **UEFI/GRUB2**, so it boots on the QEMU `virt` machine — this is the
image Home Assistant documents for QEMU/KVM
(<https://developers.home-assistant.io/docs/operating-system/boards/generic-aarch64/>).
On x86 hosts it runs under **TCG** (no KVM), so it is slow.

## Appliance caveats

HAOS is a sealed appliance:

- **No vmlab guest agent and no cloud-init** — `vmlab exec`/`cp`/provisioning
  do not work against it, and there is no SSH login by default.
- Drive it through its **web UI on port 8123**. In a lab, forward a host port
  to the guest:

  ```wcl
  segment "lan" {
    subnet = "10.82.0.0/24"
    nat    = true
    forward { host_port = 8123 to = "ha:8123" }
  }
  vm "ha" { template = "aarch64/home-assistant" memory = 2GiB
            nic { segment = "lan" } }
  ```

  Then open <http://localhost:8123> and complete onboarding.

The build boots the pristine image once and seals it; Home Assistant's
first-boot setup (supervisor + core container pulls, needs internet) runs when
you boot it in your lab, so allow a few minutes before the UI responds.

- Boots UEFI on the QEMU `virt` machine. Host needs `qemu-system-aarch64` and
  the aarch64 UEFI firmware (`qemu-efi-aarch64` / AAVMF).
- To bump: pick a release from
  <https://github.com/home-assistant/operating-system/releases>, take the
  `haos_generic-aarch64-<ver>.qcow2.xz` URL and its asset sha256, and update
  `vmlab.wcl`.

```sh
vmlab template build
```

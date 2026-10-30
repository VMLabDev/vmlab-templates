#!/usr/bin/env python3
"""Write the template's OpenCore config.plist from the pinned release's Sample.plist.

    mkconfig.py SAMPLE.plist OUT.plist --variant build|disk --smbios smbios.conf

Starting from the Sample.plist that ships with the pinned OpenCorePkg release
keeps every key that release expects; this script only changes what a QEMU
guest needs, so a version bump is a new Sample.plist and nothing else. The
changes, by section:

  ACPI, Kernel   nothing added: QEMU's isa-applesmc is a real SMC, AHCI,
                 virtio-net and the GOP framebuffer need no kexts.
                 ProvideCurrentCpuInfo gives XNU the MSR 0x35 KVM does not;
                 DummyPowerManagement stops CPU power management (AMD hosts).
  Booter         OSX-KVM's quirk set, proven on QEMU's OVMF.
  Misc           the text picker (keys and OCR both work on it), shown for
                 Timeout seconds and then booting the default entry, so a
                 clone with a fresh VARS boots unattended; no Apple Secure
                 Boot (SecureBootModel Disabled: a VM has no T2 and the SMBIOS
                 is not one Apple personalises); every volume scanned.
                 `build` lists Recovery and the downloaded recovery image
                 (HideAuxiliary off) so the build can pick them; `disk`, the
                 copy installed into the template's own ESP, hides them
                 (space shows them at the picker).
  NVRAM          SIP on, US keyboard, keepsyms.
  PlatformInfo   iMac20,1, which Tahoe supports, with the serials in
                 smbios.conf (fetch-deps.sh generates them once with
                 macserial).
  UEFI           OpenRuntime and OpenHfsPlus only (the recovery image is
                 HFS+); any APFS driver version; the firmware's own GOP mode
                 (1280x800 on vmware-svga), which the build's clicks assume.
"""
import argparse
import plistlib
import sys


def load_smbios(path):
    vals = {}
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#"):
                k, _, v = line.partition("=")
                vals[k.strip()] = v.strip()
    for key in ("model", "serial", "mlb", "uuid", "rom"):
        if not vals.get(key):
            sys.exit(f"mkconfig: {path} has no {key}=")
    return vals


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("sample")
    ap.add_argument("out")
    ap.add_argument("--variant", choices=("build", "disk"), required=True)
    ap.add_argument("--smbios", required=True)
    ap.add_argument("--timeout", type=int, default=5)
    a = ap.parse_args()

    with open(a.sample, "rb") as f:
        p = plistlib.load(f)
    smb = load_smbios(a.smbios)

    p["ACPI"]["Add"] = []
    p["ACPI"]["Patch"] = []
    p["DeviceProperties"]["Add"] = {}

    k = p["Kernel"]
    k["Add"] = []
    k["Block"] = []
    k["Force"] = []
    k["Patch"] = []
    k["Quirks"]["ProvideCurrentCpuInfo"] = True
    k["Quirks"]["DisableLinkeditJettison"] = True
    k["Emulate"]["DummyPowerManagement"] = True

    b = p["Booter"]["Quirks"]
    b.update(
        AvoidRuntimeDefrag=True,
        EnableWriteUnprotector=True,
        EnableSafeModeSlide=False,
        FixupAppleEfiImages=False,
        ProvideCustomSlide=False,
        SetupVirtualMap=False,
        RebuildAppleMemoryMap=False,
        SyncRuntimePermissions=False,
        ResizeAppleGpuBars=0,
    )
    p["Booter"]["Patch"] = []

    m = p["Misc"]
    m["Boot"].update(
        PickerMode="Builtin",
        ShowPicker=True,
        Timeout=a.timeout,
        HideAuxiliary=(a.variant == "disk"),
        PollAppleHotKeys=True,
    )
    m["Security"].update(
        SecureBootModel="Disabled",
        Vault="Optional",
        # build: every filesystem, so the recovery image on the build's FAT
        # disk is found. disk: APFS and HFS+ only (file-system lock), so
        # neither the ESP OpenCore runs from nor the firmware's own boot
        # option for it is listed — with a fresh VARS that option is first
        # in BootOrder and would otherwise be the default, booting OpenCore
        # into itself.
        ScanPolicy=0 if a.variant == "build" else 0x301,
        DmgLoading="Signed",
        AllowSetDefault=True,
    )
    m["Tools"] = []
    m["Entries"] = []

    apple = "7C436110-AB2A-4BBB-A880-FE41995C9F82"
    nv = p["NVRAM"]
    nv["Add"][apple].update(
        {
            "boot-args": "keepsyms=1",
            "csr-active-config": b"\x00\x00\x00\x00",
            "prev-lang:kbd": b"en-US:0",
        }
    )
    nv["Delete"][apple] = ["boot-args", "csr-active-config", "prev-lang:kbd"]

    g = p["PlatformInfo"]["Generic"]
    g.update(
        SystemProductName=smb["model"],
        SystemSerialNumber=smb["serial"],
        MLB=smb["mlb"],
        SystemUUID=smb["uuid"],
        ROM=bytes.fromhex(smb["rom"]),
    )

    u = p["UEFI"]
    u["Drivers"] = [
        {
            "Arguments": "",
            "Comment": name,
            "Enabled": True,
            "HideVerbose": False,
            "LoadEarly": False,
            "Path": name,
        }
        for name in ("OpenRuntime.efi", "OpenHfsPlus.efi")
    ]
    u["APFS"].update(MinDate=-1, MinVersion=-1)
    u["Output"]["Resolution"] = ""

    with open(a.out, "wb") as f:
        plistlib.dump(p, f)


if __name__ == "__main__":
    main()

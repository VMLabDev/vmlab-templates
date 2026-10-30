# Local install ISOs

MSDN / Volume-License Windows ISOs (plus retail Win9x from Bob Pony,
https://dl.bobpony.com/windows/9x/) used as `source "iso" { path = "../iso/<file>" }`
by the legacy/VL Windows templates. The ISOs themselves are **gitignored**
(`*.iso`) — only this README is tracked. Drop the ISOs here.

Most of these install **keyless** (skip the key during setup → trial/grace
period, activate later via KMS/MAK), so they need nothing in `.env`. Only the
pre-Vista editions force a key at install — put those in the repo-root `.env`
(see `../.env.example`).

| ISO | Product | Key (`.env`) |
|---|---|---|
| `MS-DOS-6.22-bootable.iso` | MS-DOS 6.22 (bootable) | — none |
| `Windows-3.11-stock.zip` | Windows for Workgroups 3.11 (runs on DOS) | — none |
| `win95_en.iso` | Windows 95 (4.00.950, OEM media) | **`WINDOWS_95_OEM_KEY`** |
| `win95_osr2_en.iso` | Windows 95B OSR2 (4.00.1111, OEM media) | **`WINDOWS_95_OEM_KEY`** |
| `win95c_osr25.iso` | Windows 95C OSR2.5 (4.03.1216, OEM media) | **`WINDOWS_95_OEM_KEY`** |
| `win98_fe_en.iso` | Windows 98 First Edition (OEM media) | **`WINDOWS_98_OEM_KEY`** |
| `win98_se_en.iso` | Windows 98 Second Edition (4.10.2222A, OEM media) | **`WINDOWS_98_OEM_KEY`** |
| `Windows-2000-Professional-SP4.iso` | Windows 2000 Professional SP4 | **`WINDOWS_2000_PRO_KEY`** |
| `en_winxp_pro_vl_iso.img` | Windows XP Professional x86 (VL) | **`WINDOWS_XP_PRO_X86_KEY`** |
| `en_win_xp_pro_x64_vl.iso` | Windows XP Professional x64 (VL) | **`WINDOWS_XP_PRO_X64_KEY`** |
| `en_windows_server_2003_enterprise_x64.iso` | Windows Server 2003 Enterprise x64 | **`WINDOWS_SERVER_2003_ENTERPRISE_KEY`** |
| `en_windows_server_2003_enterprise_vl.iso` | Windows Server 2003 Enterprise (VL) | **`WINDOWS_SERVER_2003_ENTERPRISE_KEY`** |
| `en_win_srv_2003_r2_enterprise_cd1.iso` | Windows Server 2003 R2 Enterprise (disc 1) | **`WINDOWS_SERVER_2003_R2_ENTERPRISE_KEY`** |
| `en_win_srv_2003_r2_enterprise_cd2.iso` | Windows Server 2003 R2 Enterprise (disc 2) | **`WINDOWS_SERVER_2003_R2_ENTERPRISE_KEY`** |
| `en_windows_vista_enterprise_x64_dvd_vl_x13-17316.iso` | Windows Vista Enterprise x64 | — keyless |
| `en_windows_vista_ee_x86_dvd_vl_x13-17271.iso` | Windows Vista Enterprise x86 | — keyless |
| `en_windows_7_enterprise_x64_dvd_x15-70749.iso` | Windows 7 Enterprise x64 | — keyless |
| `en_windows_7_enterprise_x86_dvd_x15-70745.iso` | Windows 7 Enterprise x86 | — keyless |
| `en_windows_8_enterprise_x64_dvd_917522.iso` | Windows 8 Enterprise x64 | — keyless |
| `en_windows_8_enterprise_x86_dvd_917587.iso` | Windows 8 Enterprise x86 | — keyless |
| `en_windows_8_1_enterprise_x64_dvd_2971902.iso` | Windows 8.1 Enterprise x64 | — keyless |
| `en_windows_8_1_enterprise_x86_dvd_2972289.iso` | Windows 8.1 Enterprise x86 | — keyless |
| `en_windows_server_2008_x64_dvd_x14-26714.iso` | Windows Server 2008 x64 | — keyless |
| `en_windows_server_2008_x86_dvd_x14-26710.iso` | Windows Server 2008 x86 | — keyless |
| `en_windows_server_2008_r2_x64_dvd_x15-50365.iso` | Windows Server 2008 R2 x64 | — keyless |
| `en_windows_server_2012_vl_x64_dvd_917758.iso` | Windows Server 2012 (VL) x64 | — keyless |
| `en_windows_server_2012_r2_x64_dvd_2707946.iso` | Windows Server 2012 R2 x64 | — keyless |
| `en_windows_server_2016_x64_dvd_9327751.iso` | Windows Server 2016 x64 | — keyless |

## macOS (Intel)

`fetch-macos-tahoe.sh` downloads the macOS Tahoe 26 recovery image from
Apple's Internet Recovery service and checks it against Apple's RSA-signed
chunklist. Tahoe is the final Intel macOS. It needs no Mac and no Apple
account. A rerun reuses the cached files if they still verify.

`../macos-tahoe/fetch-deps.sh` runs the script with `NO_IMG=1`, and the
template boots the DMG through OpenCore (see `../macos-tahoe/README.md`).
Without `NO_IMG=1` the script also converts the DMG to a raw disk image, for
attaching it to a QEMU VM as a disk by hand.

The recovery build is pinned by Apple product ID (`PRODUCT_PIN` in the
script). When Apple serves a newer one, the script stops and says how to
adopt it.

| File | Product | Key (`.env`) |
|---|---|---|
| `macos-tahoe-recovery.dmg` | macOS Tahoe 26 recovery (Intel), the Apple DMG, chunklist-verified | — none |
| `macos-tahoe-recovery.chunklist` | Apple chunklist (per-chunk SHA-256 + RSA signature) | — none |
| `macos-tahoe-recovery.img` | The DMG as a raw disk image (skipped with `NO_IMG=1`) | — none |

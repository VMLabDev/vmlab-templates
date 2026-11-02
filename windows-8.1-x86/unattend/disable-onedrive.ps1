# Windows 8.1's shell-integrated OneDrive cannot be uninstalled.
# Apply the Windows 8.1 policy before generalize, without removing OS files.
$ErrorActionPreference = 'Stop'
foreach ($key in @('HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive',
                    'HKLM\SOFTWARE\Policies\Microsoft\Windows\SkyDrive')) {
    foreach ($name in @('DisableFileSync', 'DisableFileSyncNGSC')) {
        & reg.exe add $key /v $name /t REG_DWORD /d 1 /f | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Could not set $key\$name" }
    }
}
Get-Process -Name OneDrive, SkyDrive -ErrorAction SilentlyContinue | Stop-Process -Force
Write-Output 'ONEDRIVE_DISABLED=OK'

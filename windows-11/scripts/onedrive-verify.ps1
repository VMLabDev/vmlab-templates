# Run as a fresh local user after logging on, not as SYSTEM.
$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if ($identity.IsSystem) { throw 'Run this check as the new local user' }
$profileKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$($identity.User.Value)"
$profilePath = [Environment]::ExpandEnvironmentVariables((Get-ItemProperty $profileKey).ProfileImagePath)
if ($env:USERPROFILE -ine $profilePath -or
    $env:LOCALAPPDATA -ine (Join-Path $profilePath 'AppData\Local')) {
    throw 'The process environment does not belong to this user profile'
}

$run = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue
$policy = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive'
$result = [ordered]@{
    User = $identity.Name
    Profile = $env:USERPROFILE
    OneDriveProcesses = @(Get-Process -Name OneDrive -ErrorAction SilentlyContinue).Count
    OneDriveRun = [bool]($run -and $run.PSObject.Properties['OneDrive'])
    OneDriveSetupRun = [bool]($run -and $run.PSObject.Properties['OneDriveSetup'])
    OneDriveLocalAppData = Test-Path -LiteralPath "$env:LOCALAPPDATA\Microsoft\OneDrive"
    DisableFileSyncNGSC = $policy.DisableFileSyncNGSC
}
$result | ConvertTo-Json
if ($result.OneDriveProcesses -ne 0 -or $result.OneDriveRun -or $result.OneDriveSetupRun -or
    $result.OneDriveLocalAppData -or $result.DisableFileSyncNGSC -ne 1) {
    throw 'OneDrive removal verification failed'
}
Write-Output 'ONEDRIVE_FRESH_USER=OK'

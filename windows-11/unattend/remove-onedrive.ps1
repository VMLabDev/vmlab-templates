# Remove OneDrive before generalize. This runs as SYSTEM through the guest
# agent, so clean the default and build-user hives as well as HKCU.
param([switch]$CleanupOnly)
$ErrorActionPreference = 'Stop'
$script:NeedsReboot = $false

function Invoke-Reg {
    param([string[]]$Arguments)
    & reg.exe @Arguments | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "reg.exe failed: $($Arguments -join ' ')" }
}

function Test-RegEntry {
    param([string[]]$Arguments)
    $ErrorActionPreference = 'Continue'
    & reg.exe query @Arguments 2>$null | Out-Null
    return $LASTEXITCODE -eq 0
}

function Remove-RegValue {
    param([string]$Key, [string]$Name)
    if (Test-RegEntry -Arguments @($Key, '/v', $Name)) { Invoke-Reg -Arguments @('delete', $Key, '/v', $Name, '/f') }
}

function Clear-UserHive {
    param([string]$Root)
    foreach ($run in @('Software\Microsoft\Windows\CurrentVersion\Run',
                       'Software\Microsoft\Windows\CurrentVersion\RunOnce',
                       'Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Run',
                       'Software\Wow6432Node\Microsoft\Windows\CurrentVersion\RunOnce')) {
        foreach ($name in @('OneDriveSetup', 'OneDrive')) {
            Remove-RegValue "$Root\$run" $name
        }
    }
    $uninstall = "$Root\Software\Microsoft\Windows\CurrentVersion\Uninstall\OneDriveSetup.exe"
    if (Test-RegEntry -Arguments @($uninstall)) { Invoke-Reg -Arguments @('delete', $uninstall, '/f') }
    foreach ($classes in @('Software\Classes', 'Software\Classes\Wow6432Node')) {
        $key = "$Root\$classes\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}"
        if (Test-RegEntry -Arguments @($key)) {
            Invoke-Reg -Arguments @('add', $key, '/v', 'System.IsPinnedToNameSpaceTree', '/t', 'REG_DWORD', '/d', '0', '/f')
        }
    }
}

function Remove-Leftover {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        try { Remove-Item -LiteralPath $Path -Recurse -Force }
        catch [System.UnauthorizedAccessException], [System.IO.IOException] {
            if ($CleanupOnly) { throw }
            $script:NeedsReboot = $true
            Write-Output "OneDrive leftover needs a reboot: $Path"
            return
        }
        if (Test-Path -LiteralPath $Path) { throw "OneDrive leftover remains: $Path" }
    }
}

function Uninstall-UserOneDrive {
    param([string]$Setup)
    $user = (Get-CimInstance Win32_ComputerSystem).UserName
    if (-not $user) { throw 'No logged-on build user for the OneDrive uninstaller' }
    $name = 'vmlab-remove-onedrive'
    if (Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue) {
        throw "Scheduled task already exists: $name"
    }
    $action = New-ScheduledTaskAction -Execute $Setup -Argument '/uninstall'
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
    Register-ScheduledTask -TaskName $name -Action $action -Principal $principal -Settings $settings | Out-Null
    try {
        $before = (Get-ScheduledTaskInfo -TaskName $name).LastRunTime
        Start-ScheduledTask -TaskName $name
        $deadline = (Get-Date).AddMinutes(5)
        do {
            Start-Sleep -Seconds 1
            $task = Get-ScheduledTask -TaskName $name
            $info = Get-ScheduledTaskInfo -TaskName $name
            if ($info.LastRunTime -gt $before -and $task.State -ne 'Running') {
                Write-Output "OneDriveSetup.exe /uninstall user=$user exit=$($info.LastTaskResult)"
                if ($info.LastTaskResult -eq 2147747483) {
                    $account = New-Object System.Security.Principal.NTAccount($user)
                    $sid = $account.Translate([System.Security.Principal.SecurityIdentifier]).Value
                    $profile = Get-CimInstance Win32_UserProfile | Where-Object { $_.SID -eq $sid }
                    if (-not $profile) { throw "No profile for $user" }
                    $client = Join-Path $profile.LocalPath 'AppData\Local\Microsoft\OneDrive\OneDrive.exe'
                    $key = "HKU\$sid\Software\Microsoft\Windows\CurrentVersion\Uninstall\OneDriveSetup.exe"
                    if (-not (Test-Path -LiteralPath $client) -and -not (Test-RegEntry -Arguments @($key))) {
                        Write-Output '0x8004069B: no per-user executable or uninstall registration remains'
                        return
                    }
                }
                if ($info.LastTaskResult -notin @(0, 3010)) { throw 'User OneDrive uninstall failed' }
                return
            }
        } while ((Get-Date) -lt $deadline)
        throw 'User OneDrive uninstall timed out'
    } finally {
        Stop-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $name -Confirm:$false
    }
}

$policy = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive'
Invoke-Reg -Arguments @('add', $policy, '/v', 'DisableFileSyncNGSC', '/t', 'REG_DWORD', '/d', '1', '/f')

# Stop a first-logon setup already in flight before invoking the uninstaller.
Get-Process -Name OneDrive, OneDriveSetup -ErrorAction SilentlyContinue | Stop-Process -Force
$setup = @("$env:SystemRoot\SysWOW64\OneDriveSetup.exe",
           "$env:SystemRoot\System32\OneDriveSetup.exe") |
    Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $setup) { throw 'System OneDriveSetup.exe not found' }
# Per-user setup refuses SYSTEM (0x8004069B). Use the build user's existing
# interactive token, without storing a password or changing autologon.
if (-not $CleanupOnly) {
    Uninstall-UserOneDrive $setup
}
if (-not $CleanupOnly -and
    ((Test-RegEntry -Arguments @('HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\OneDriveSetup.exe')) -or
    (Test-RegEntry -Arguments @('HKLM\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\OneDriveSetup.exe')))) {
    $result = Start-Process -FilePath $setup -ArgumentList '/uninstall /allusers' -Wait -PassThru
    Write-Output "OneDriveSetup.exe /uninstall /allusers exit=$($result.ExitCode)"
    if ($result.ExitCode -notin @(0, 3010)) { throw 'Machine OneDrive uninstall failed' }
}
Get-Process -Name OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force
Get-ScheduledTask | Where-Object { $_.TaskName -like 'OneDrive*' } |
    Unregister-ScheduledTask -Confirm:$false

# reg.exe avoids PowerShell registry handles that can prevent hive unloading.
$profiles = @(Get-CimInstance Win32_UserProfile | Where-Object { -not $_.Special })
$users = Split-Path $env:PUBLIC -Parent
$profiles += [pscustomobject]@{ LocalPath = (Join-Path $users 'Default'); SID = '' }
foreach ($profile in $profiles) {
    $hive = Join-Path $profile.LocalPath 'NTUSER.DAT'
    if (-not (Test-Path -LiteralPath $hive)) { throw "User hive missing: $hive" }
    $root = "HKU\$($profile.SID)"
    $loaded = $false
    if ($profile.SID) {
        $loaded = Test-RegEntry -Arguments @($root)
    }
    if (-not $loaded) {
        $root = 'HKU\VMLabOneDrive'
        Invoke-Reg -Arguments @('load', $root, $hive)
    }
    try { Clear-UserHive $root }
    finally {
        if (-not $loaded) { Invoke-Reg -Arguments @('unload', $root) }
    }
    Remove-Leftover (Join-Path $profile.LocalPath 'AppData\Local\Microsoft\OneDrive')
    foreach ($name in @('OneDrive.lnk', 'OneDrive.exe.lnk')) {
        Remove-Leftover (Join-Path $profile.LocalPath "AppData\Roaming\Microsoft\Windows\Start Menu\Programs\$name")
    }
}
Clear-UserHive 'HKCU'
Clear-UserHive 'HKLM'

foreach ($programs in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
    if ($programs) { Remove-Leftover (Join-Path $programs 'Microsoft OneDrive') }
}
foreach ($name in @('OneDrive.lnk', 'OneDrive.exe.lnk')) {
    Remove-Leftover (Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs\$name")
}
foreach ($classes in @('HKLM\SOFTWARE\Classes', 'HKLM\SOFTWARE\Classes\Wow6432Node')) {
    $key = "$classes\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}"
    if (Test-RegEntry -Arguments @($key)) {
        Invoke-Reg -Arguments @('add', $key, '/v', 'System.IsPinnedToNameSpaceTree', '/t', 'REG_DWORD', '/d', '0', '/f')
    }
}
if (Get-Process -Name OneDrive -ErrorAction SilentlyContinue) { throw 'OneDrive is still running' }
if ($script:NeedsReboot) {
    Write-Output 'ONEDRIVE_REMOVED=REBOOT'
    exit 3010
}
Write-Output 'ONEDRIVE_REMOVED=OK'

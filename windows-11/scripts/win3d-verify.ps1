<#
.SYNOPSIS
Guest-side checks for the `win3d` variant build (scripts/win3d-setup.ws runs
this as SYSTEM through the vmlab agent, Windows PowerShell 5.1).

.DESCRIPTION
-Phase Static   Checks the end state the variant seals: vmlab-win3d's
                state.json says Installed; test signing is on in the running
                kernel; the display device with the package's hardware ID is
                bound to the package's INF (viogpu3d.inf) with problem code 0;
                both Vulkan ICDs are registered and present; the resume task is
                gone and the repair task registered; no reboot is pending. One
                line per check, `ok:` or `FAIL:`; exit 1 when anything failed.
-Phase Vulkan   Runs vulkaninfo --summary (System32 and SysWOW64) in the
                console user's session, because Vulkan enumerates nothing from
                SYSTEM (session 0). With nobody logged on it arms a one-shot
                autologon for -User (default: the first enabled local account
                of vmlab and Administrator, so the build VM's Administrator
                and a sealed clone's vmlab both work) and exits 3: the caller
                reboots the guest
                and runs this phase again. Prints both summaries; exit 1 unless
                each lists a "Virtio-GPU Venus" device. Clears the autologon
                values afterwards, so nothing of it reaches the sealed image.
-Phase Cleanup  Removes the bundle copied from the WIN3D media and any
                autologon values left behind.
#>
[CmdletBinding()]
param(
    [ValidateSet('Static', 'Vulkan', 'Cleanup')][string]$Phase = 'Static',
    [string]$User = '',
    [string]$Password = 'vmlab123!',
    [string]$BundleCopy = 'C:\vmlab-win3d'
)
Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
$StateDir = 'C:\ProgramData\vmlab-win3d'
$Winlogon = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
$script:failed = 0

function Ok([string]$m) { "ok: $m" }
function Fail([string]$m) { "FAIL: $m"; $script:failed++ }

function Get-Prop($Device, [string]$Key) {
    (Get-PnpDeviceProperty -InstanceId $Device.InstanceId -KeyName $Key -ErrorAction SilentlyContinue).Data
}

function Get-ConsoleUser {
    $name = (Get-CimInstance Win32_ComputerSystem).UserName
    if ($name) { return $name }
    $explorer = Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" |
        Where-Object { $_.SessionId -ne 0 } | Select-Object -First 1
    if ($explorer) {
        $owner = Invoke-CimMethod -InputObject $explorer -MethodName GetOwner
        if ($owner.User) { return "$($owner.Domain)\$($owner.User)" }
    }
    return $null
}

# Whether the running kernel accepts test-signed code, which can differ from
# the BCD setting until the next boot (the same query vmlab-win3d's installer
# makes: SystemCodeIntegrityInformation, CODEINTEGRITY_OPTION_TESTSIGN).
function Test-TestSigningActive {
    if (-not ('VmlabWin3dVerify.CodeIntegrity' -as [type])) {
        Add-Type -Namespace VmlabWin3dVerify -Name CodeIntegrity -MemberDefinition @'
[DllImport("ntdll.dll")]
public static extern int NtQuerySystemInformation(int cls, byte[] info, int len, out int retLen);
public static int Options() {
    byte[] b = new byte[8];
    System.BitConverter.GetBytes(8).CopyTo(b, 0);
    int r;
    int st = NtQuerySystemInformation(103, b, 8, out r);
    if (st != 0) throw new System.ComponentModel.Win32Exception("NtQuerySystemInformation " + st);
    return System.BitConverter.ToInt32(b, 4);
}
'@
    }
    return ([VmlabWin3dVerify.CodeIntegrity]::Options() -band 0x2) -ne 0
}

# The build VM has only the built-in Administrator; on a sealed clone the
# specialize pass creates vmlab and disables Administrator.
function Get-AutologonUser {
    foreach ($n in 'vmlab', 'Administrator') {
        $u = Get-LocalUser -Name $n -ErrorAction SilentlyContinue
        if ($u -and $u.Enabled) { return $n }
    }
    throw 'neither vmlab nor Administrator is an enabled local account; pass -User'
}

function Clear-Autologon {
    Set-ItemProperty -Path $Winlogon -Name AutoAdminLogon -Value '0' -Type String
    foreach ($n in 'DefaultPassword', 'AutoLogonCount', 'ForceAutoLogon') {
        Remove-ItemProperty -Path $Winlogon -Name $n -ErrorAction SilentlyContinue
    }
}

function Test-Static {
    $statePath = Join-Path $StateDir 'state.json'
    if (-not (Test-Path -LiteralPath $statePath)) { Fail "no $statePath"; return }
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    if ($state.status -eq 'Installed') { Ok "state.json: Installed (version $($state.version))" }
    else { Fail "state.json: status $($state.status), step $($state.step), error $($state.last_error)" }

    $bcd = (& bcdedit.exe /enum '{current}') -join "`n"
    if ($bcd -match '(?im)^\s*testsigning\s+Yes\s*$') { Ok 'testsigning Yes in the BCD' } else { Fail 'testsigning is not Yes in the BCD' }
    if (Test-TestSigningActive) { Ok 'test signing active in the running kernel' } else { Fail 'test signing is not active in the running kernel' }

    $manifest = Join-Path $StateDir 'bundle\manifest.json'
    if (-not (Test-Path -LiteralPath $manifest)) { Fail "no staged bundle manifest at $manifest"; return }
    $hwid = (Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json).hardware_id
    $device = $null
    foreach ($d in Get-PnpDevice -Class Display -ErrorAction SilentlyContinue) {
        $ids = @(Get-Prop $d 'DEVPKEY_Device_HardwareIds')
        if ($ids -contains $hwid) { $device = $d; break }
    }
    if (-not $device) { Fail "no display device with hardware ID $hwid"; return }
    $problem = Get-Prop $device 'DEVPKEY_Device_ProblemCode'
    $inf = Get-Prop $device 'DEVPKEY_Device_DriverInfPath'
    $ver = Get-Prop $device 'DEVPKEY_Device_DriverVersion'
    $prov = Get-Prop $device 'DEVPKEY_Device_DriverProvider'
    $original = ''
    if ($inf) {
        $lines = & pnputil.exe /enum-drivers
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match "^\s*Published Name:\s+$([regex]::Escape($inf))\s*$") {
                for ($j = $i + 1; $j -lt $lines.Count -and $j -le $i + 3; $j++) {
                    if ($lines[$j] -match '^\s*Original Name:\s+(\S+)') { $original = $Matches[1]; break }
                }
                break
            }
        }
    }
    "device: $($device.FriendlyName) [$($device.InstanceId)] inf=$inf ($original) version=$ver provider=$prov problem=$problem"
    if ($problem -eq 0) { Ok 'display device problem code 0' } else { Fail "display device problem code $problem" }
    if ($original -ieq 'viogpu3d.inf') { Ok "display device bound to $inf = viogpu3d.inf" } else { Fail "display device driver is $inf ($original), not viogpu3d.inf" }

    foreach ($pair in @(
            @{ key = 'HKLM:\SOFTWARE\Khronos\Vulkan\Drivers'; icd = 'C:\Windows\System32\virtio_icd.x86_64.json' },
            @{ key = 'HKLM:\SOFTWARE\WOW6432Node\Khronos\Vulkan\Drivers'; icd = 'C:\Windows\SysWOW64\virtio_icd.x86.json' })) {
        $k = Get-Item -Path $pair.key -ErrorAction SilentlyContinue
        $registered = $k -and ($k.GetValueNames() -contains $pair.icd) -and ($k.GetValue($pair.icd) -eq 0)
        if ($registered -and (Test-Path -LiteralPath $pair.icd)) { Ok "Vulkan ICD registered: $($pair.icd)" }
        else { Fail "Vulkan ICD not registered or missing: $($pair.icd)" }
    }

    if (Get-ScheduledTask -TaskName 'vmlab-win3d-resume' -ErrorAction SilentlyContinue) { Fail 'task vmlab-win3d-resume is still registered' }
    else { Ok 'no vmlab-win3d-resume task' }
    if (Get-ScheduledTask -TaskName 'vmlab-win3d-repair' -ErrorAction SilentlyContinue) { Ok 'task vmlab-win3d-repair registered' }
    else { Fail 'task vmlab-win3d-repair is missing' }

    $pending = @()
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { $pending += 'CBS RebootPending' }
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { $pending += 'WindowsUpdate RebootRequired' }
    $sm = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -ErrorAction SilentlyContinue
    if ($sm -and ($sm.PSObject.Properties.Name -contains 'PendingFileRenameOperations') -and $sm.PendingFileRenameOperations) {
        $pending += "PendingFileRenameOperations ($(@($sm.PendingFileRenameOperations | Where-Object { $_ }).Count) entries)"
    }
    if ($pending.Count) { Fail "reboot pending: $($pending -join ', ')" } else { Ok 'no reboot pending' }

    # Strict mode throws on a missing property, and a Winlogon key with no
    # autologon ever configured has no AutoAdminLogon value.
    $wlNames = (Get-ItemProperty -Path $Winlogon).PSObject.Properties.Name
    $autoAdmin = if ($wlNames -contains 'AutoAdminLogon') { (Get-ItemProperty -Path $Winlogon).AutoAdminLogon } else { $null }
    if ($autoAdmin -eq '1' -or ($wlNames -contains 'DefaultPassword')) { Fail 'Winlogon autologon values are still set' }
    else { Ok 'no autologon values in Winlogon' }
}

function Invoke-Vulkan {
    $console = Get-ConsoleUser
    if (-not $console) {
        # Nobody to run vulkaninfo as: arm one autologon for $User and ask the
        # caller for a reboot. AutoLogonCount=1 makes Windows clear the
        # values itself after that logon; Clear-Autologon below makes sure.
        if (-not $User) { $User = Get-AutologonUser }
        Set-ItemProperty -Path $Winlogon -Name AutoAdminLogon -Value '1' -Type String
        Set-ItemProperty -Path $Winlogon -Name DefaultUserName -Value $User -Type String
        Set-ItemProperty -Path $Winlogon -Name DefaultDomainName -Value $env:COMPUTERNAME -Type String
        Set-ItemProperty -Path $Winlogon -Name DefaultPassword -Value $Password -Type String
        Set-ItemProperty -Path $Winlogon -Name AutoLogonCount -Value 1 -Type DWord
        "nobody is logged on; armed a one-shot autologon for $User (reboot needed)"
        exit 3
    }
    "console user: $console"
    $outDir = Join-Path $env:SystemRoot 'Temp\vmlab-win3d-verify'
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    Get-ChildItem -LiteralPath $outDir -File | Remove-Item -Force
    & icacls.exe $outDir /grant "${console}:(OI)(CI)M" /Q | Out-Null
    $cmd = Join-Path $outDir 'vulkaninfo.cmd'
    @"
@echo off
"%SystemRoot%\System32\vulkaninfo.exe" --summary > "$outDir\vulkaninfo-x64.txt" 2>&1
echo exit %ERRORLEVEL% >> "$outDir\vulkaninfo-x64.txt"
"%SystemRoot%\SysWOW64\vulkaninfo.exe" --summary > "$outDir\vulkaninfo-x86.txt" 2>&1
echo exit %ERRORLEVEL% >> "$outDir\vulkaninfo-x86.txt"
echo done > "$outDir\done.txt"
"@ | Set-Content -LiteralPath $cmd -Encoding ascii
    $taskName = 'vmlab-win3d-verify-vulkaninfo'
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    $action = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\cmd.exe" -Argument "/c `"$cmd`"" -WorkingDirectory $outDir
    $principal = New-ScheduledTaskPrincipal -UserId $console -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Settings $settings | Out-Null
    try {
        Start-ScheduledTask -TaskName $taskName
        # A task for an interactive logon stays Queued until that logon has
        # finished, which on a fresh boot can take a few minutes.
        $deadline = (Get-Date).AddSeconds(300)
        while (-not (Test-Path -LiteralPath (Join-Path $outDir 'done.txt')) -and (Get-Date) -lt $deadline) { Start-Sleep -Seconds 2 }
        "task state: $((Get-ScheduledTask -TaskName $taskName).State), result $((Get-ScheduledTaskInfo -TaskName $taskName).LastTaskResult)"
    } finally {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        Clear-Autologon
    }
    if (-not (Test-Path -LiteralPath (Join-Path $outDir 'done.txt'))) { Fail 'vulkaninfo did not run in the console session within 300 s'; return }
    foreach ($a in 'x64', 'x86') {
        $f = Join-Path $outDir "vulkaninfo-$a.txt"
        "## vulkaninfo --summary ($a)"
        $text = if (Test-Path -LiteralPath $f) { Get-Content -LiteralPath $f -Raw } else { '' }
        $text
        $names = @([regex]::Matches($text, '(?m)^\s*deviceName\s*=\s*(.+?)\s*$') | ForEach-Object { $_.Groups[1].Value })
        $venus = @($names | Where-Object { $_ -match 'Virtio-GPU Venus' })
        if ($venus.Count -and $text -match '(?m)^exit 0\s*$') { Ok "vulkaninfo $a lists $($venus.Count) Venus device(s): $($venus -join '; ')" }
        else { Fail "vulkaninfo $a lists no Virtio-GPU Venus device (devices: $($names -join '; '))" }
    }
}

switch ($Phase) {
    'Static' { Test-Static }
    'Vulkan' { Invoke-Vulkan }
    'Cleanup' {
        if (Test-Path -LiteralPath $BundleCopy) { Remove-Item -LiteralPath $BundleCopy -Recurse -Force }
        Remove-Item -LiteralPath (Join-Path $env:SystemRoot 'Temp\vmlab-win3d-verify') -Recurse -Force -ErrorAction SilentlyContinue
        Clear-Autologon
        Ok "removed $BundleCopy and any autologon values"
    }
}
if ($script:failed) { "$($script:failed) check(s) failed"; exit 1 }
exit 0

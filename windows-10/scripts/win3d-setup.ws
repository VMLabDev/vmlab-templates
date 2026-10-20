// Provision for the `win3d` variant of the windows-10 template (PRD §6.6):
// installs the vmlab-win3d driver package (virtio-gpu 3D: a test-signed
// WDDM KMD, D3D9/10/11 and OpenGL UMDs, the Venus Vulkan ICD and a D3D12
// bridge) on a linked overlay of the base, verifies it, and leaves the guest
// in a state scripts/generalize.ws can seal. Listed before generalize.ws in
// the variant block, so clones of `#win3d` come up generalized AND with the
// driver bound.
//
// The package rides the WIN3D ISO the variant attaches (fetch-deps.sh stages
// the pinned release into win3d/). Its Install.cmd restarts Windows itself,
// once for test signing and once more after the driver and runtime land, and
// continues after each restart from the `vmlab-win3d-resume` startup task.
// Each reboot is watched by boot id (vm.boot_id() before, vm.wait_rebooted()
// after; wscript surface 2): a Windows reboot is often too fast for the
// agent to be seen dropping. The loop ends when
// C:\ProgramData\vmlab-win3d\state.json says Installed, or Failed, or the
// budget runs out.
//
// The build VM needs a Venus device: the installer's final verify wants the
// KMD started (problem code 0), which a plain virtio-vga never gives. The
// variant block supplies it with `display` + `qemu_args` (see vmlab.wcl).
//
// Checks before sealing (scripts/win3d-verify.ps1, run as SYSTEM through the
// agent): test signing on in the BCD and active in the kernel, the display
// device bound to viogpu3d.inf with problem code 0, both Vulkan ICDs
// registered, no resume task, the repair task present, no reboot pending,
// and vulkaninfo listing a Virtio-GPU Venus device. Vulkan enumerates nothing
// from session 0, so vulkaninfo runs in the console user's session; with
// nobody logged on, the script arms a one-shot autologon, the guest is
// rebooted once more, and the values are cleared again before sealing.

use vmlab

// Run a guest exec, retrying transient agent hiccups: the agent answers its
// handshake (so the build's readiness check passes) a little before its exec
// channel is fully ready, so the first exec after boot can fail with "agent
// did not open the channel in time" even though the guest is fine.
fn exec_ok(lab: Lab, vm: Machine, cmd: string, args: List[string]) -> Result[ExecResult, string] {
    let last = "exec never ran"
    for i in 0..12 {                 // up to ~1 min of transient-blip tolerance
        match vm.exec(cmd, args) {
            Ok(r)  => return Ok(r),
            Err(e) => {
                last = e
                lab.log(fmt("win3d: exec transient failure (try {}); retrying: {}", i, e))
                vmlab::sleep_ms(5000)
            },
        }
    }
    Err("exec failed after retries: " + last)
}

// Run scripts/win3d-verify.ps1 (copied beside the bundle) for one phase.
fn verify(lab: Lab, vm: Machine, phase: string, timeout: int) -> Result[ExecResult, string] {
    let r = vm.exec_timeout("powershell.exe", [
        "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
        "-File", "C:\\vmlab-win3d\\win3d-verify.ps1", "-Phase", phase,
    ], timeout)?
    lab.log(fmt("win3d: verify {} (exit {}):\n{}", phase, r.exit_code, (r.stdout + r.stderr).trim()))
    Ok(r)
}

// "status=<status> step=<step> error=<last_error>" from state.json, or
// "status=NotInstalled" before Install.cmd has written it.
fn state(vm: Machine) -> Result[string, string] {
    let r = vm.exec_timeout("powershell.exe", [
        "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command",
        "$p = 'C:\\ProgramData\\vmlab-win3d\\state.json'; if (Test-Path $p) {{ $s = Get-Content $p -Raw | ConvertFrom-Json; 'status={{0}} step={{1}} error={{2}}' -f $s.status, $s.step, $s.last_error }} else {{ 'status=NotInstalled step= error=' }}",
    ], 60)?
    Ok(r.stdout.trim())
}

fn journal_tail(vm: Machine) -> string {
    match vm.exec_timeout("powershell.exe", [
        "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command",
        "Get-Content C:\\ProgramData\\vmlab-win3d\\journal.log -Tail 40",
    ], 60) {
        Ok(r)  => r.stdout.trim(),
        Err(e) => "(journal unreadable: " + e + ")",
    }
}

// Copy the bundle off the WIN3D ISO (its drive letter shifts, so probe a
// few) to C:\vmlab-win3d, and the verify script beside it.
fn stage(lab: Lab, vm: Machine) -> Result[unit, string] {
    let copy = exec_ok(lab, vm, "cmd.exe", [
        "/c",
        "rmdir /s /q C:\\vmlab-win3d 2>nul & for %d in (D E F G H) do if exist %d:\\Install.cmd if exist %d:\\manifest.json xcopy /e /i /q /y /h %d:\\ C:\\vmlab-win3d\\ >nul && attrib -r C:\\vmlab-win3d\\* /s /d",
    ])?
    let check = exec_ok(lab, vm, "cmd.exe", [
        "/c",
        "if exist C:\\vmlab-win3d\\Install.cmd if exist C:\\vmlab-win3d\\manifest.json echo STAGED",
    ])?
    if !check.stdout.contains("STAGED") {
        return Err("no vmlab-win3d bundle on the WIN3D media (run ./fetch-deps.sh to stage it into win3d/); xcopy said: " + copy.stdout.trim() + " " + copy.stderr.trim())
    }
    vm.copy_to("win3d-verify.ps1", "C:\\vmlab-win3d\\win3d-verify.ps1")?
    let ver = exec_ok(lab, vm, "powershell.exe", [
        "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command",
        "$m = Get-Content C:\\vmlab-win3d\\manifest.json -Raw | ConvertFrom-Json; '{{0}} {{1}} (commit {{2}}, driver {{3}})' -f $m.name, $m.version, $m.commit, $m.driver_version",
    ])?
    lab.log("win3d: staged " + ver.stdout.trim())
    Ok(())
}

// Run Install.cmd and follow it through its restarts until state.json says
// Installed. Budget: ~40 minutes all told.
fn install(lab: Lab, vm: Machine) -> Result[unit, string] {
    let before = vm.boot_id()?
    lab.log("win3d: running Install.cmd as SYSTEM (boot id " + before + "); it restarts Windows once or twice")
    match vm.exec_timeout("cmd.exe", ["/c", "C:\\vmlab-win3d\\Install.cmd"], 1200) {
        Ok(r)  => lab.log(fmt("win3d: Install.cmd exited {}: {}", r.exit_code, (r.stdout + r.stderr).trim())),
        Err(e) => lab.log("win3d: Install.cmd exec ended early (the restart may have cut it off): " + e),
    }

    let last = ""
    let reboots = 0
    for i in 0..160 {                // 160 x 15 s = 40 min
        let st = match state(vm) {
            Ok(s)  => s,
            Err(e) => "status=Away step= error=" + e,
        }
        if st != last {
            lab.log("win3d: " + st)
            last = st
        }
        if st.contains("status=Installed ") {
            lab.log(fmt("win3d: installed after {} restart(s)", reboots))
            return Ok(())
        }
        if st.contains("status=Failed ") {
            return Err("vmlab-win3d install failed (" + st + "); journal tail:\n" + journal_tail(vm))
        }
        if st.contains("status=RebootPending ") || st.contains("status=Away ") {
            // The installer asked for a restart (or the guest is already
            // away on one): watch it by boot id, then give the resume task
            // (20 s after boot) time to take the state onward.
            match vm.wait_rebooted(before, 900) {
                Ok(_) => {
                    reboots = reboots + 1
                    before = vm.boot_id()?
                    lab.log(fmt("win3d: restart {} seen (boot id now {}); waiting for vmlab-win3d-resume", reboots, before))
                    for j in 0..20 {
                        match state(vm) {
                            Ok(s) => {
                                if !s.contains("status=RebootPending ") {
                                    break
                                }
                            },
                            Err(_) => {},
                        }
                        vmlab::sleep_ms(15000)
                    }
                },
                Err(e) => return Err("the installer requested a restart that never came: " + e + "; journal tail:\n" + journal_tail(vm)),
            }
        } else {
            vmlab::sleep_ms(15000)
        }
    }
    Err("vmlab-win3d did not reach Installed within the budget (last: " + last + "); journal tail:\n" + journal_tail(vm))
}

// Reboot the guest once for the one-shot autologon the verify script armed.
fn reboot_for_logon(lab: Lab, vm: Machine) -> Result[unit, string] {
    let before = vm.boot_id()?
    lab.log("win3d: nobody logged on for vulkaninfo; rebooting once with a one-shot autologon (boot id " + before + ")")
    let r = vm.exec_timeout("cmd.exe", ["/c", "shutdown /r /t 5 /f"], 60)
    vm.wait_rebooted(before, 1800)?
    match vm.boot_id() {
        Ok(after) => lab.log("win3d: rebooted (boot id " + before + " -> " + after + ")"),
        Err(e)    => lab.log("win3d: rebooted (boot id after unreadable: " + e + ")"),
    }
    // Give the logon a moment to land before asking for the console user.
    vmlab::sleep_ms(60000)
    Ok(())
}

fn setup(lab: Lab) -> Result[unit, string] {
    let vm = lab.vm("build")?
    vm.wait_ready(1800)?

    stage(lab, vm)?
    install(lab, vm)?

    // vulkaninfo in the console session; with nobody logged on, one reboot.
    let vk = verify(lab, vm, "Vulkan", 900)?
    let vk_exit = if vk.exit_code == 3 {
        reboot_for_logon(lab, vm)?
        let again = verify(lab, vm, "Vulkan", 900)?
        again.exit_code
    } else {
        vk.exit_code
    }
    if vk_exit != 0 {
        return Err(fmt("vulkaninfo verification failed (exit {}); see the verify output above", vk_exit))
    }

    // The end state generalize.ws seals, checked after the autologon
    // reboot above so nothing of it can be left behind. Cleanup comes last:
    // it removes C:\vmlab-win3d, the verify script included.
    let st = verify(lab, vm, "Static", 600)?
    if st.exit_code != 0 {
        return Err(fmt("win3d end-state checks failed (exit {}); see the verify output above", st.exit_code))
    }
    verify(lab, vm, "Cleanup", 300)?
    lab.log("win3d: package installed and verified; handing over to generalize.ws")
    Ok(())
}

fn main(lab: Lab) {
    // `expect` drops the Err payload, so the cause rides the message instead.
    match setup(lab) {
        Ok(u)  => u,
        Err(e) => {
            let failed: Result[unit, string] = Err(e)
            failed.expect("windows-10 win3d variant failed: " + e)
        },
    }
}

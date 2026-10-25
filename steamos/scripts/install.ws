// Build provision for the steamos template. The installed disk fetch-deps.sh
// staged carries a first-boot unit that installs vmlab-agent from the VMLAB
// ISO, so the agent is up and verified before this runs. Here: prove the
// guest's 3D stack reaches the host GPU through the build's gpu {}, and add
// the vmlab login, before the image is sealed.

use vmlab

fn sh(lab: Lab, vm: Vm, what: string, script: string) -> Result[string, string] {
    let r = vm.exec_timeout("/bin/sh", ["-c", script], 300)?
    if r.exit_code != 0 {
        return Err(fmt("{} failed (exit {}): {}{}", what, r.exit_code, r.stdout, r.stderr))
    }
    Ok(r.stdout)
}

fn provision(lab: Lab) -> Result[unit, string] {
    let vm = lab.vm("build")?

    lab.log("waiting for the vmlab-agent (installed by the first-boot unit)...")
    vm.wait_ready(900)?
    let rel = sh(lab, vm, "os-release", ". /etc/os-release; echo \"$PRETTY_NAME $VERSION_ID ($BUILD_ID)\"")?
    lab.log("guest: " + rel.trim())

    // Venus: the Vulkan loader lists the host GPU behind a Virtio-GPU Venus
    // device. --summary needs no display, so it runs from the agent as is.
    let vk = sh(lab, vm, "vulkaninfo", "vulkaninfo --summary 2>/dev/null | grep -E 'deviceName|driverID|driverInfo'")?
    lab.log("vulkan: " + vk.trim())
    if !vk.contains("DRIVER_ID_MESA_VENUS") {
        return Err("no Venus device in vulkaninfo; the build needs gpu {{ mode = \"vulkan\" }} on a Venus-capable host")
    }

    // OpenGL goes through virgl on the same GPU; a surfaceless EGL context
    // shows the renderer without a display.
    let gl = sh(lab, vm, "eglinfo", "eglinfo -B -p surfaceless 2>/dev/null | grep -m1 'OpenGL core profile renderer'")?
    lab.log("opengl: " + gl.trim())
    if !gl.contains("virgl") {
        return Err("OpenGL is not on virgl: " + gl.trim())
    }

    // Game mode needs OpenGL on Zink. By default GL in the guest is virgl, so
    // Xwayland's buffers are virgl resources, which the Venus render server
    // cannot import ("vkr: failed to import resource: invalid res_id"):
    // Venus aborts and gamescope crash-loops. On Zink every buffer is a Venus
    // one. Only the two game-mode units get it; desktop mode keeps virgl,
    // which is several times faster there.
    sh(lab, vm, "game mode on zink",
        "for u in gamescope-session steam-launcher; do mkdir -p /etc/systemd/user/$u.service.d; printf '[Service]\\nEnvironment=MESA_LOADER_DRIVER_OVERRIDE=zink\\n' > /etc/systemd/user/$u.service.d/vmlab-zink.conf; done")?
    lab.log("game mode: gamescope-session and steam-launcher run GL on zink")

    // Venus from SteamOS's Mesa 25.3.0 forces the software WSI on an NVIDIA
    // host, and Steam's GPU-composited UI then shows black in game mode
    // (VMLabDev/vmlab#171). venus/build.sh builds the same release with the
    // Mesa 26.0 fix backported; install it over both copies, 64- and 32-bit,
    // keeping SteamOS's as libvulkan_virtio.so.steamos.
    sh(lab, vm, "venus staging", "mkdir -p /var/tmp/vmlab-venus/lib /var/tmp/vmlab-venus/lib32")?
    vm.copy_to("../venus/out/x86_64/libvulkan_virtio.so", "/var/tmp/vmlab-venus/lib/libvulkan_virtio.so")?
    vm.copy_to("../venus/out/i686/libvulkan_virtio.so", "/var/tmp/vmlab-venus/lib32/libvulkan_virtio.so")?
    sh(lab, vm, "venus",
        "set -e; for d in lib lib32; do [ -e /usr/$d/libvulkan_virtio.so.steamos ] || cp -a /usr/$d/libvulkan_virtio.so /usr/$d/libvulkan_virtio.so.steamos; install -m 755 /var/tmp/vmlab-venus/$d/libvulkan_virtio.so /usr/$d/libvulkan_virtio.so; cmp /var/tmp/vmlab-venus/$d/libvulkan_virtio.so /usr/$d/libvulkan_virtio.so; done; rm -rf /var/tmp/vmlab-venus")?
    let vk2 = sh(lab, vm, "vulkaninfo (patched venus)", "vulkaninfo --summary 2>/dev/null | grep -E 'driverID|driverInfo'")?
    if !vk2.contains("DRIVER_ID_MESA_VENUS") {
        return Err("no Venus device after installing the patched libvulkan_virtio.so: " + vk2.trim())
    }
    lab.log("venus: patched libvulkan_virtio.so installed (" + vk2.trim() + ")")

    // Clones log in to game mode, as a Deck does. This file is what
    // `steamos-session-select gamescope` leaves behind; it is written
    // directly because deck's session bus, which that command needs, may
    // not be up yet.
    sh(lab, vm, "game mode session",
        "printf '[Autologin]\\nSession=gamescope-wayland.desktop\\n' > /etc/sddm.conf.d/zz-steamos-autologin.conf")?
    lab.log("default session: game mode (gamescope-wayland)")

    sh(lab, vm, "vmlab user",
        "id vmlab >/dev/null 2>&1 || useradd -m -s /bin/bash -G wheel vmlab; echo vmlab:vmlab | chpasswd")?
    lab.log("vmlab user created (wheel)")
    Ok(())
}

fn main(lab: Lab) {
    match provision(lab) {
        Ok(u)  => u,
        Err(e) => {
            let failed: Result[unit, string] = Err(e)
            failed.expect("steamos build failed: " + e)
        },
    }
}

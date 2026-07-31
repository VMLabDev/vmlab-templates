# vmlab-templates

Reproducible guest images for vmlab labs. Each template describes one operating
system on one architecture, together with everything needed to install it
unattended, seal it, and publish it.

## Language

### Templates and artefacts

**Template**:
The definition of a reproducible guest image for one operating system on one
architecture. A template is a definition, not a running guest.
_Avoid_: image, box, VM

**Short name**:
The registry-facing name of a template, without an architecture prefix. One
short name covers every architecture the template is built for.
_Avoid_: slug, id

**Store ref**:
The architecture-qualified name a built template is addressed by, in the form
`<arch>/<short-name>`. Two templates may share a short name but never a store
ref.
_Avoid_: tag, image name, path

**Profile**:
The hardware and firmware personality vmlab applies to a guest. Chosen by what
the guest needs to boot, not by what the guest is — a non-Windows OS may take a
Windows profile if that is the machine shape it wants.
_Avoid_: platform, machine type

**Catalog**:
The single generated definition listing every template in the repository, used
to drive the Web UI. Derived from the standalone template definitions; never
authored directly.
_Avoid_: index, manifest, registry

**Example lab**:
The minimal single-guest lab kept alongside a template, used to smoke-test that
the built template boots.
_Avoid_: demo, test lab, sample

**Vintage**:
A template for an operating system old enough that it cannot be driven through
the guest agent, and is installed by keystrokes and screen recognition instead.
_Avoid_: legacy, retro, old

**Keyed template**:
A template whose install media or answer file needs a product key supplied from
the environment rather than committed.
_Avoid_: licensed, proprietary

### Provisioning

**Build provision**:
The script that drives a fresh installation to produce the sealed image. Runs
once, on the build guest.
_Avoid_: installer, build script, setup

**First-boot provision**:
The script that runs on every clone's first boot, before the guest is reported
ready. Runs many times over a template's life — once per clone.
_Avoid_: post-install, firstboot script, init

**Staged media**:
Install media and payloads prepared on the host before a build, because they
cannot be fetched from inside the guest.
_Avoid_: assets, downloads, deps

**Unattend**:
The vendor answer-file set handed to an installer as attached media so it
completes without interaction.
_Avoid_: autounattend, answer files, config

**Generalize**:
The pass that strips machine identity from an installed guest so the image can
be cloned. Distinct from the tool that performs it.
_Avoid_: sysprep, seal

### Guest contact

**Guest agent**:
The vmlab agent running inside a guest, through which vmlab execs commands,
judges readiness, and requests shutdown. Not the QEMU guest agent, which is a
different thing that some images ship instead.
_Avoid_: agent (when the QEMU one is also in play), qemu-guest-agent

**Bootstrap ISO**:
The VMLAB-labelled ISO attached to a build, carrying the guest agent installer.
Templates differ in what invokes it, not in what it does.
_Avoid_: agent ISO, seed ISO

**Ready**:
vmlab's judgement that a guest is usable. Sticky — once a guest has been ready,
it is reported ready again immediately, including across a reboot it has not yet
performed.
_Avoid_: up, alive, healthy

**Agent probe**:
A live check of whether the guest agent answers right now. Distinct from ready
precisely because it is not sticky.
_Avoid_: ping, health check

**Boot stamp**:
The guest's last-boot time, captured before and after a reboot to prove the
reboot actually happened. The only evidence that distinguishes a completed
reboot from a swallowed shutdown request.
_Avoid_: uptime, reboot flag

### Windows build lifecycle

**Update pass**:
One round of applying Windows Updates to the build guest. Passes repeat until a
pass reports nothing left to install.
_Avoid_: update run, patch cycle

**Settle**:
The wait for background guest work to quiesce before the next step is allowed to
start. What is settling differs by step; the need to wait does not.
_Avoid_: cooldown, drain

### Publication

**Publication gate**:
The hand-authored presentation copy for a template. A template is published to
the site only if it has an entry, so the gate is a deliberate editorial
decision, not a derived fact.
_Avoid_: metadata, curation list

**Registry**:
The GHCR location a built template is published to.
_Avoid_: repo, remote

---
status: accepted, not yet implemented
---

# Generalize must run in a user context, and the marker must record what happened

Sysprep must not generalize an image while running as Local System. On 24H2 and
Server 2025 codebases a SYSTEM-context generalize skips AppX registration for
the XAML CBS packages, and every clone's first interactive logon then
permanently breaks that profile's shell. Running provisions through the guest
agent means Local System, so a build provision has to seal through a one-shot
scheduled task registered as Administrator, which is a real batch logon.

Only `windows-server-2025` does this today. The fix landed on one of five copies
in `90581ea`, and `windows-11` — the same 26100 build, so the same exposure —
still seals as SYSTEM. All the modern Windows templates will adopt the
scheduled-task seal.

`generalize.ps1` must record the context it actually ran in rather than
asserting one. It currently writes `SysprepContext=user` unconditionally, and
the first-boot provision reads that marker to decide whether an image needs its
mitigations. A template sealing the wrong way therefore stamps a marker claiming
it sealed the right way, and switches off the very retrofits covering for it —
which is the state `windows-11` is in.

## Consequences

The marker is an interface between the two provisions, so it has to carry
evidence, not a claim. A mis-sealed image will report `system`, keep its
retrofits, and be visible instead of silently degraded.

Templates that seal by some other route — `windows-11-arm64` generalizes inline
— write no marker at all, which correctly reads as "not sealed in a user
context" and leaves the mitigations on.

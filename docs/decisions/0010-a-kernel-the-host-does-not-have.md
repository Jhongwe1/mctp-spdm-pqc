# ADR 0010 — A kernel the host does not have

**Date:** 2026-09-18
**Status:** accepted
**Supersedes:** nothing. **Related:** [0001](0001-two-build-flavors.md),
[0002](0002-wsl-and-docker-parity.md), [0009](0009-a-third-build-flavor.md)

## Context

Gate 5 asks for a handshake on a transport that is not a TCP socket. The
cheapest real one is Linux MCTP: a kernel subsystem, an address family, a
netdev with a transmission unit, and packetisation the emulator's socket
transport cannot perform. The development host cannot run any of it.

```console
$ zcat /proc/config.gz | grep CONFIG_MCTP
# CONFIG_MCTP is not set
$ ./afmctp_probe
socket(AF_MCTP) -> errno 97 (Address family not supported by protocol)
```

Nor can it offer a PCIe device with a Data Object Exchange capability, which is
what the second half of Gate 5 needs.

Both are one kernel away, and there were two ways to get that kernel.

## The option that was rejected

**Rebuild the host kernel with `CONFIG_MCTP=y`.** It is the shortest path.
Microsoft publishes the WSL2 kernel source, the build is twenty minutes, and
`.wslconfig` points at the result. It is also reversible: delete one line and
restart.

It was rejected for a reason that has nothing to do with difficulty.

**`host_kernel` is recorded in every `manifest.json` in `bench/data/`.** Twenty-
five run directories, going back to 2026-08-11, each naming
`6.6.87.2-microsoft-standard-WSL2` as the kernel their numbers were produced
under. Replacing it would have made every one of those lines name a kernel that
no longer exists on the machine — and this project's central claim is that any
published number can be traced to the conditions that produced it.

That is not a hypothetical loss. [ADR 0001](0001-two-build-flavors.md) keeps two
spdm-emu builds rather than one for the same reason, and
[ADR 0009](0009-a-third-build-flavor.md) adds a third rather than rebuild `pqc`
with different buffers: *the build every published number came from does not get
rebuilt*. A kernel is a build. The rule does not stop applying because the
artifact is larger.

There is a second, smaller reason. A result that needs a hand-built host kernel
is a result nobody else can reproduce without rebuilding their own host kernel
first, and "clone this and run it" is worth more than twenty minutes saved.

## Decision

**The new subsystems live in a guest, and the host is left alone.**

`harness/build_guest_kernel.sh` builds Linux 6.12.110 from a pinned tarball with
`CONFIG_MCTP=y`, `CONFIG_MCTP_SERIAL=y`, `CONFIG_PACKET=y` and the 9p and virtio
support needed to boot. `third_party/linux.pin` records the version and the
SHA-256 of the source tarball, of the resulting `.config`, and of the `bzImage`.

Three properties make this cheap enough to be the default rather than a last
resort:

1. **The guest's root filesystem is the host's**, exported over virtio-9p and
   mounted read-only. There is no image to build and nothing to copy in. The
   `spdm_requester_emu` and `spdm_responder_emu` built in week one run inside
   the guest unchanged, from the same paths, against the same certificates —
   which is what makes "the same experiment over a different transport" a fact
   rather than a hope.
2. **No initramfs.** 9p has to work before any userspace exists, so 9p, virtio
   and MCTP are all `=y` and there are no modules at all. That removes the
   entire class of problem where a module is missing from an initramfs.
3. **The host orchestrates and owns provenance; the guest only executes.**
   `prov_begin` runs on the host, the guest writes artifacts to a read-write 9p
   share, and the host collects and analyses them with the tools that already
   exist — `spdm_dump`, `fields.py`, `check_negotiated.py`, `pcapstat.py`. No
   analysis code runs in the guest, so nothing about the verdict depends on the
   virtual machine.

The guest kernel version is recorded in the manifest of every run that uses one,
beside the host kernel, so a reader can see both.

## Consequences

**Good.**

- Every capture taken before 2026-09-18 still reproduces on the host that took
  it, and the manifests still name a kernel that is installed.
- The same guest serves both halves of Gate 5: MCTP needs `CONFIG_MCTP`, PCIe
  DOE needs a machine that can be given an emulated device, and one virtual
  machine is both.
- The MCTP route runs on the *distribution's* QEMU 8.2.2. Only the DOE route
  needs the 9.2 built by `harness/build_qemu_doe.sh`, and that is stated where
  it matters: a result that needs only packaged software is easier for someone
  else to reproduce, and it is worth knowing which results those are.
- A reviewer can read the guest kernel's configuration: the fragment is in
  `harness/build_guest_kernel.sh` and the script reads the resulting `.config`
  back and fails if a symbol did not take. Standing rule 8 — verify the
  independent variable, do not assume it — applies to a kernel config as much as
  to a command-line flag.

**Bad, and worth saying.**

- **Two kernels now exist in the story**, and a reader has to keep track of
  which results came from which. Every manifest names both, and every document
  that reports a Gate 5 number says it came from a guest.
- **The guest kernel is not a distribution kernel.** Ubuntu's own 6.8 ships
  `CONFIG_MCTP=y` and `CONFIG_MCTP_SERIAL=m`, which is worth stating: this
  configuration is not exotic, and the reason for building rather than extracting
  a distribution image is that modules would have required an initramfs.
- **A virtual machine is a new dependency in the measurement path.** It brought
  its own failure modes on the first day — a capture that started late because a
  `sleep` was standing in for a synchronisation, and an `AF_PACKET` socket that
  dropped packets under a burst — and both had to be turned into checks rather
  than into longer sleeps. See `docs/fragmentation.md` §2.4.
- **The host kernel still cannot run any of this.** Anyone reading
  `harness/run_afmctp.sh` and expecting to run its parts by hand on the host
  gets `EAFNOSUPPORT`, which is why the script boots the guest itself rather
  than documenting a sequence to be typed.

## What would change this decision

If the host kernel gained `CONFIG_MCTP` by an upgrade that happened for some
other reason, the guest would still be the right place to run these experiments
— because by then there would be Gate 5 results whose manifests name *it*, and
the same argument would apply in the other direction.

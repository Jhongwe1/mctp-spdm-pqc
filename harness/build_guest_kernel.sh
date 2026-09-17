#!/usr/bin/env bash
#
# harness/build_guest_kernel.sh — build the kernel the host does not have.
#
#     bash harness/build_guest_kernel.sh
#     JOBS=4 bash harness/build_guest_kernel.sh
#
# Why a kernel is built at all
# ----------------------------
# Gate 5 needs a handshake on a transport that is not a TCP socket, and the
# cheapest real one is Linux MCTP over a serial link. This host cannot run it:
#
#     $ zcat /proc/config.gz | grep CONFIG_MCTP
#     # CONFIG_MCTP is not set
#     $ socket(AF_MCTP, SOCK_DGRAM, 0)  ->  errno 97, EAFNOSUPPORT
#
# There were two ways to fix that and only one of them is defensible.
#
# Rebuilding the WSL2 kernel with CONFIG_MCTP=y would have been quicker. It
# would also have replaced the kernel under which every capture in bench/data/
# was taken. Every manifest records host_kernel; every one of them would then
# name a kernel that no longer exists on the machine, and "reproduce this on
# the host that produced it" would quietly stop being true. The environment
# that produced the evidence is part of the evidence.
#
# So the new subsystem goes in a guest instead, and the host is left alone.
# The guest kernel is built here, from a pinned tarball, with a config fragment
# that is committed — third_party/linux.pin records the version and the SHA-256
# of the source tarball and of the bzImage this script produces.
#
# Why everything is built in and there is no initramfs
# ----------------------------------------------------
# The guest's root filesystem is the host's, exported over virtio-9p and
# mounted read-only. That is what makes this cheap: the spdm-emu binaries built
# in weeks one to eight run in the guest unchanged, from the same paths, with
# no image to build and nothing to copy in. It only works if the kernel can
# mount 9p before any userspace exists, so 9p, virtio and the MCTP stack are
# all =y and there is no initramfs at all.
#
# Why 6.12 and not the newest
# ---------------------------
# It is the longterm series OpenBMC machines are mostly on. The question this
# guest exists to answer is what a BMC's MCTP stack does to a 16 KB
# certificate chain, and the answer should come from a kernel a BMC would
# plausibly be running rather than from the newest one available.
#
# Exit codes: 0 built (or already built) · 2 a prerequisite is missing

set -uo pipefail
_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "${_HERE}/lib/common.sh"

KVER="${KVER:-6.12.110}"
SRC_URL="https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${KVER}.tar.xz"
W9="${LAB_DIR}/w9"
SRC_DIR="${W9}/linux-${KVER}"
TARBALL="${W9}/dl/linux-${KVER}.tar.xz"
BZIMAGE="${SRC_DIR}/arch/x86/boot/bzImage"
PIN="${REPO_ROOT}/third_party/linux.pin"

hdr "guest kernel ${KVER}"

need gcc make curl tar
for t in bison flex bc; do
    command -v "$t" >/dev/null 2>&1 || die \
        "missing '$t' — apt install bc bison flex libelf-dev libssl-dev"
done

# Already built, and the pin already describes it: nothing to do.
#
# The pin is part of the condition rather than a side effect of building,
# because a tree with no pin beside it is a version claim nobody can check —
# which is the one thing third_party/ exists to prevent. If the image is there
# and the pin is not, fall through: the build below is a no-op for make and the
# pin gets written.
if [ -f "$BZIMAGE" ] && [ -f "$PIN" ] && [ -z "${FORCE:-}" ]; then
    ok "already built: $BZIMAGE"
    dim "    sha256 $(sha256sum "$BZIMAGE" | cut -d' ' -f1)"
    dim "    pin    $PIN"
    exit 0
fi

mkdir -p "${W9}/dl" "${W9}/logs"

if [ ! -f "$TARBALL" ]; then
    log "fetching ${KVER}"
    run curl -fsSL -o "$TARBALL" "$SRC_URL"
fi
SRC_SHA="$(sha256sum "$TARBALL" | cut -d' ' -f1)"
ok "tarball sha256 ${SRC_SHA}"

if [ ! -d "$SRC_DIR" ]; then
    log "extracting"
    run tar -C "$W9" -xf "$TARBALL"
fi

cd "$SRC_DIR" || die "no source tree"

# ── the fragment ───────────────────────────────────────────────────────────
#
# defconfig gives a kernel that boots on qemu -M pc; kvm_guest.config is the
# kernel's own target for "running as a guest", and adds virtio and 9p. What
# is left is the part this project needs, and each line is here for a reason
# that is stated rather than inherited from someone's gist.
cat > .w9-fragment <<'FRAG'
# the reason this kernel exists
CONFIG_MCTP=y
CONFIG_MCTP_SERIAL=y
# AF_PACKET, so the link can be captured from inside the guest
CONFIG_PACKET=y
CONFIG_PACKET_DIAG=y
# two ends of one link, kept in separate network namespaces so that a socket
# bound to MCTP_ADDR_ANY on one end cannot match the other end's traffic
CONFIG_NAMESPACES=y
CONFIG_NET_NS=y
CONFIG_UNIX=y
CONFIG_UNIX98_PTYS=y
# root over 9p: the host filesystem, read-only, no initramfs
CONFIG_NET_9P=y
CONFIG_NET_9P_VIRTIO=y
CONFIG_9P_FS=y
CONFIG_9P_FS_POSIX_ACL=y
CONFIG_VIRTIO=y
CONFIG_VIRTIO_PCI=y
CONFIG_VIRTIO_BLK=y
CONFIG_VIRTIO_CONSOLE=y
CONFIG_TMPFS=y
CONFIG_TMPFS_POSIX_ACL=y
CONFIG_DEVTMPFS=y
CONFIG_DEVTMPFS_MOUNT=y
CONFIG_OVERLAY_FS=y
# the other half of Gate 5: a PCIe device whose DOE mailbox is real
CONFIG_PCI=y
CONFIG_BLK_DEV_NVME=y
CONFIG_NVME_CORE=y
# console
CONFIG_SERIAL_8250=y
CONFIG_SERIAL_8250_CONSOLE=y
CONFIG_PRINTK=y
FRAG

log "defconfig + kvm_guest.config + fragment"
{
    make -s defconfig
    make -s kvm_guest.config
    ./scripts/kconfig/merge_config.sh -m .config .w9-fragment
    make -s olddefconfig
} > "${W9}/logs/kconfig.log" 2>&1 || die "kconfig failed — see ${W9}/logs/kconfig.log"

# ── read the config back ───────────────────────────────────────────────────
#
# Standing rule 8, applied to a kernel config. merge_config.sh prints what it
# merged; it does not promise the result survived olddefconfig, and a symbol
# whose dependencies are unmet is dropped silently. The only honest way to know
# what this kernel has is to read the .config that will be compiled.
#
# CONFIG_PCI_DOE is expected to be absent and that is not a failure: it has no
# prompt and is only ever selected by a driver that wants it. Nothing here
# wants it — the DOE mailbox in section two is driven from userspace through
# config space, which needs no kernel support and avoids a driver claiming the
# mailbox out from under the experiment.
MISSING=0
for s in CONFIG_MCTP CONFIG_MCTP_SERIAL CONFIG_PACKET CONFIG_NET_NS \
         CONFIG_9P_FS CONFIG_NET_9P_VIRTIO CONFIG_VIRTIO_PCI \
         CONFIG_BLK_DEV_NVME CONFIG_DEVTMPFS_MOUNT CONFIG_UNIX98_PTYS; do
    if grep -q "^${s}=y" .config; then
        printf '  ok   %-24s =y\n' "$s"
    else
        printf '  FAIL %-24s %s\n' "$s" "$(grep -E "^# ${s} is not set" .config || echo absent)"
        MISSING=1
    fi
done
[ "$MISSING" -eq 0 ] || die "the fragment did not take; the guest would not do what it is for"

log "make -j$(jobs_default) bzImage"
if ! make -j"$(jobs_default)" bzImage > "${W9}/logs/kbuild.log" 2>&1; then
    tail -30 "${W9}/logs/kbuild.log" >&2
    die "kernel build failed — full log at ${W9}/logs/kbuild.log"
fi

IMG_SHA="$(sha256sum "$BZIMAGE" | cut -d' ' -f1)"
CFG_SHA="$(sha256sum .config | cut -d' ' -f1)"
ok "bzImage $(stat -c%s "$BZIMAGE") bytes, sha256 ${IMG_SHA}"

cat > "$PIN" <<PINEOF
# third_party/linux.pin — the guest kernel, and why there is one.
#
# Written by harness/build_guest_kernel.sh. Do not edit by hand: this file and
# the tree it describes are the same fact, and a hand-edit makes them two.
#
# The host kernel has no CONFIG_MCTP (docs/env-baseline.md). Rather than
# replace the kernel every published capture was taken under, the MCTP
# subsystem lives in a guest, and this is that guest's kernel.
version=${KVER}
source_url=${SRC_URL}
source_sha256=${SRC_SHA}
config_sha256=${CFG_SHA}
bzimage_sha256=${IMG_SHA}
bzimage_bytes=$(stat -c%s "$BZIMAGE")
config_base=defconfig + kvm_guest.config + harness/build_guest_kernel.sh fragment
built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
built_on=$(uname -srm)
cc=$(gcc -dumpfullversion -dumpversion 2>/dev/null || echo unknown)
PINEOF
ok "pin written: third_party/linux.pin"

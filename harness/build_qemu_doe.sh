#!/usr/bin/env bash
#
# harness/build_qemu_doe.sh — a QEMU with an SPDM-capable NVMe device.
#
#     bash harness/build_qemu_doe.sh
#
# Why the distribution's QEMU is not enough
# ----------------------------------------
# Ubuntu 24.04 ships QEMU 8.2.2. The nvme `spdm_port` property that gives the
# emulated controller a Data Object Exchange capability is not in it, and a
# property QEMU does not have is a realize-time error rather than a warning, so
# the failure looks like a broken command line.
#
# This builds one target, x86_64-softmmu, with the tools and the front ends
# turned off — under three minutes on eight cores, which is a smaller cost than
# the time spent working out why the distribution build would not do.
#
# ★ A NOTE ON A WIDELY REPEATED COMMAND LINE. Much of the writing about this
# feature, including this project's own week-nine plan, gives the invocation as
#
#     -device nvme,...,spdm_port=2323,spdm_trans=doe
#
# There is no `spdm_trans` property on the nvme device in 9.2. The transport is
# implied: hw/nvme/ctrl.c registers CMA-SPDM and Secured CMA-SPDM on a DOE
# mailbox and forwards both to the socket with
# SPDM_SOCKET_TRANSPORT_TYPE_PCI_DOE. harness/run_doe.sh therefore checks the
# property list rather than the version number, which is the same discipline
# the rest of this repository applies to flags: ask the binary, not the
# documentation.
#
# Exit codes: 0 built (or already built) · 2 a prerequisite is missing

set -uo pipefail
_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "${_HERE}/lib/common.sh"

REF="${QEMU_REF:-v9.2.0}"
W9="${LAB_DIR}/w9"
SRC="${W9}/qemu"
BIN="${SRC}/build/qemu-system-x86_64"
PIN="${REPO_ROOT}/third_party/qemu.pin"

hdr "QEMU ${REF} (x86_64-softmmu only)"
need git python3 ninja gcc pkg-config

if [ -x "$BIN" ] && [ -f "$PIN" ] && [ -z "${FORCE:-}" ]; then
    ok "already built: $BIN"
    dim "    $("$BIN" --version | head -1)"
    exit 0
fi

mkdir -p "$W9" "${W9}/logs"
if [ ! -d "$SRC" ]; then
    log "cloning ${REF}"
    run git clone -q --depth 1 --branch "$REF" \
        https://gitlab.com/qemu-project/qemu.git "$SRC" || die "clone failed"
fi
cd "$SRC" || die "no source tree"
COMMIT="$(git rev-parse HEAD)"

# ★ Read the source before building it, not the release notes. If this grep
# finds nothing, the rest of the build is wasted time and the run script would
# fail later with a confusing message about an unknown property.
log "checking the tree for nvme SPDM support"
if ! grep -q 'spdm_port' hw/nvme/ctrl.c; then
    die "this QEMU tree has no nvme spdm_port; pick a newer ref with QEMU_REF="
fi
grep -n 'PCI_SIG_DOE_CMA\|spdm_socket_connect\|DEFINE_PROP_UINT16("spdm_port"' \
    hw/nvme/ctrl.c | sed 's/^/    /'

if [ ! -f build/build.ninja ]; then
    log "configure"
    run ./configure --target-list=x86_64-softmmu --disable-docs \
        --disable-werror --enable-kvm --disable-gtk --disable-sdl \
        --disable-vnc --disable-spice --disable-tools --disable-guest-agent \
        --prefix="${W9}/qemu-install" > "${W9}/logs/qemu-configure.log" 2>&1 \
        || { tail -20 "${W9}/logs/qemu-configure.log" >&2; die "configure failed"; }
fi

log "ninja -C build"
run ninja -C build > "${W9}/logs/qemu-build.log" 2>&1 \
    || { tail -20 "${W9}/logs/qemu-build.log" >&2; die "build failed"; }

[ -x "$BIN" ] || die "qemu-system-x86_64 was not produced"
ok "$("$BIN" --version | head -1)"

log "the property, from the binary"
"$BIN" -device nvme,help 2>&1 | grep -i spdm | sed 's/^/    /' \
    || die "the built QEMU has no nvme spdm property after all"

cat > "$PIN" <<PINEOF
# third_party/qemu.pin — the QEMU that has an SPDM-capable NVMe device.
#
# Written by harness/build_qemu_doe.sh. Do not edit by hand.
#
# The distribution's 8.2.2 has no nvme spdm_port. This one does, and it is the
# only QEMU any DOE result in this repository was produced with. The MCTP runs
# in harness/run_afmctp.sh use the distribution build instead, on purpose: that
# experiment needs no feature newer than virtio-9p, and a result that needs
# only a packaged QEMU is easier for someone else to reproduce.
repo=https://gitlab.com/qemu-project/qemu.git
ref=${REF}
commit=${COMMIT}
version=$("$BIN" --version | head -1)
binary_sha256=$(sha256sum "$BIN" | cut -d' ' -f1)
targets=x86_64-softmmu
built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
cc=$(gcc -dumpfullversion -dumpversion 2>/dev/null || echo unknown)
PINEOF
ok "pin written: third_party/qemu.pin"

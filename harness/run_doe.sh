#!/usr/bin/env bash
#
# harness/run_doe.sh — Gate 5, second half: an SPDM message across a real
# PCIe DOE mailbox.
#
#     bash harness/run_doe.sh
#
# What this is
# ------------
# harness/run_afmctp.sh answers "does the whole handshake survive a real
# transport". This answers a narrower and differently interesting question:
# does an SPDM message cross a real PCIe Data Object Exchange mailbox — config
# space, a DWORD-at-a-time write mailbox, a busy/ready handshake, a read
# mailbox that has to be popped — and come back answered?
#
#     spdm_responder_emu --trans PCI_DOE          (host)
#              ^  TCP 127.0.0.1:2323, the twelve-byte socket protocol
#              |
#          qemu-system-x86_64 -device nvme,...,spdm_port=2323
#              |  DOE extended capability in the guest's config space
#              v
#          transport/doe_probe --device <BDF> --discovery --spdm   (guest)
#
# QEMU's NVMe model registers two DOE protocols and forwards both to the SPDM
# socket (hw/nvme/ctrl.c, doe_spdm_prot[]), so the responder at the far end is
# the same emulator every other capture in this repository was taken against.
# The transport is what changed.
#
# Three things this deliberately does not claim
# ---------------------------------------------
# * The DOE mailbox is emulated. It is QEMU's, not silicon's, and the timing
#   means nothing. What is real is the register protocol and the fact that the
#   guest kernel enumerated the capability out of config space.
# * There is no in-kernel requester. Linux 6.12 has no CMA-SPDM support, so
#   doe_probe drives the mailbox from userspace. Nothing here is a driver.
# * One message, not a handshake. doe_probe sends GET_VERSION and prints the
#   reply. State machines, transcripts and signatures live in libspdm and are
#   exercised over the socket and MCTP paths.
#
# Exit codes: 0 the capability was found and the exchange completed
#             1 it did not, and the evidence is kept
#             2 a prerequisite is missing

set -uo pipefail
_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "${_HERE}/lib/common.sh"
# shellcheck source=lib/provenance.sh
. "${_HERE}/lib/provenance.sh"
set +e

FLAVOR="pqc"
RUN_NAME="w9-doe"
PORT=2323
TIMEOUT=600

while [ $# -gt 0 ]; do
    case "$1" in
        --name)    RUN_NAME="${2:?}"; shift 2 ;;
        --flavor)  FLAVOR="${2:?}"; shift 2 ;;
        --port)    PORT="${2:?}"; shift 2 ;;
        --timeout) TIMEOUT="${2:?}"; shift 2 ;;
        -h|--help) sed -n '3,12p' "$0"; exit 0 ;;
        *)         die "unknown argument '$1'" ;;
    esac
done

hdr "Gate 5 · SPDM over a real PCIe DOE mailbox · ${RUN_NAME}"

W9="${LAB_DIR}/w9"
QEMU="${W9}/qemu/build/qemu-system-x86_64"
KVER="$(sed -n 's/^version=//p' "${REPO_ROOT}/third_party/linux.pin" 2>/dev/null)"
BZIMAGE="${W9}/linux-${KVER}/arch/x86/boot/bzImage"
BIN="$(flavor_bin "$FLAVOR")"

need gcc python3 make
[ -x "$QEMU" ] || die "no QEMU with spdm_port — run: bash harness/build_qemu_doe.sh"
[ -f "$BZIMAGE" ] || die "no guest kernel — run: bash harness/build_guest_kernel.sh"
[ -x "${BIN}/spdm_responder_emu" ] || die \
    "no ${FLAVOR} build — run: bash harness/build_spdm_emu.sh ${FLAVOR}"

# ★ The property is read back from the binary rather than assumed from the
# version. QEMU 9.2 has spdm_port on the nvme device and does NOT have the
# spdm_trans property that a lot of the writing about this feature mentions;
# passing one it does not have is an unknown-property error at realize time,
# which is a confusing way to learn a version number.
# A here-string rather than a pipe into grep -q: grep exits at the first
# match, the producer takes SIGPIPE, and under `pipefail` the branch would be
# decided by 141 instead of by the match. verify_repo.sh refuses that shape,
# and 2026-09-10 in LOG.md is the day it inverted two branches elsewhere.
QEMU_NVME_PROPS="$("$QEMU" -device nvme,help 2>&1)"
if ! grep -q 'spdm_port' <<<"$QEMU_NVME_PROPS"; then
    die "this QEMU has no nvme spdm_port property"
fi
ok "$("$QEMU" --version | head -1) has nvme spdm_port"

log "building the probe"
make -s -C "${REPO_ROOT}/transport" || die "transport/ did not build"

KVM_ARGS=()
[ -w /dev/kvm ] && KVM_ARGS=(-enable-kvm -cpu host)

prov_begin "$RUN_NAME" "$FLAVOR"
prov_pin_file "${REPO_ROOT}/third_party/linux.pin" BUILD_PIN.linux.txt guest_kernel
prov_pin_file "${REPO_ROOT}/third_party/qemu.pin" BUILD_PIN.qemu.txt qemu
prov_note transport "PCI_DOE, QEMU-emulated NVMe DOE mailbox"
prov_note guest_kernel_version "$KVER"
prov_note qemu "$("$QEMU" --version | head -1)"
prov_note doe_probe_sha256 "$(sha256sum "${REPO_ROOT}/transport/doe_probe" | cut -d' ' -f1)"

STAGE="${W9}/doe"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp "${REPO_ROOT}/transport/doe_probe" "${STAGE}/doe_probe"
cp "${REPO_ROOT}/harness/vm_guest_init.sh" "${STAGE}/init.sh"
chmod +x "${STAGE}/init.sh" "${STAGE}/doe_probe"

# A backing file for the NVMe namespace. It is never read: the guest is not
# asked to do any I/O, and the smallest thing QEMU will accept is cheaper than
# the two gigabytes the obvious recipe suggests.
NVME_IMG="${STAGE}/nvme.raw"
run dd if=/dev/zero of="$NVME_IMG" bs=1M count=16 status=none

cat > "${STAGE}/guest_cmd.sh" <<'GEOF'
#!/bin/bash
set -u
OUT=/run/out
rc=0
note() { printf '\n======== %s\n' "$*"; }

note "kernel"
uname -srm

note "the device the guest enumerated"
lspci -nn | tee "$OUT/lspci.txt"

BDF=$(lspci -D -n | awk '$2 ~ /^0108:/ {print $1; exit}')
if [ -z "$BDF" ]; then
    echo "no NVMe class device found"
    lspci -D -n
    exit 3
fi
echo "NVMe at $BDF"
echo "$BDF" > "$OUT/bdf.txt"

# ★ The demo frame. A DOE capability in `lspci -vvv` is the guest's own
# enumeration of config space, and it is there whether or not anything ever
# drives the mailbox -- which is exactly why it is not the whole claim.
note "lspci -vvv, in full"
lspci -vvv -s "$BDF" > "$OUT/lspci-vvv.txt" 2>&1
if grep -qiE 'Data Object Exchange|DOE' "$OUT/lspci-vvv.txt"; then
    echo "Data Object Exchange capability present:"
    grep -iA6 -E 'Data Object Exchange|\[DOE\]' "$OUT/lspci-vvv.txt" | head -20
else
    echo "no DOE capability reported by lspci"
    echo "  (pciutils may be older than the capability; the probe checks config space directly)"
    rc=1
fi

note "extended capability walk and the two DOE protocols"
"$OUT/doe_probe" --device "$BDF" --verbose --discovery 2>&1 | tee "$OUT/doe-discovery.txt"
[ "${PIPESTATUS[0]}" -eq 0 ] || rc=1

note "one SPDM message across the mailbox"
"$OUT/doe_probe" --device "$BDF" --verbose --spdm 2>&1 | tee "$OUT/doe-spdm.txt"
[ "${PIPESTATUS[0]}" -eq 0 ] || rc=1

sync
exit $rc
GEOF
chmod +x "${STAGE}/guest_cmd.sh"
cp "${STAGE}/guest_cmd.sh" "${PROV_RUN_DIR}/guest_cmd.sh"

# ── the responder has to be listening before QEMU realizes the device ──────
#
# nvme_init_pci() calls spdm_socket_connect() during realize and fails the
# device outright if the connect fails, so this is an ordering requirement and
# not a race to be slept over.
log "starting the responder (--trans PCI_DOE)"
RSP_LOG="${PROV_RUN_DIR}/responder.log"
prov_cmd "${BIN}/spdm_responder_emu" --trans PCI_DOE
( cd "$BIN" && ./spdm_responder_emu --trans PCI_DOE ) > "$RSP_LOG" 2>&1 &
RSP_PID=$!
listening() { grep -q ":${PORT}" <<<"$(ss -ltnH 2>/dev/null)"; }
for _ in $(seq 100); do
    listening && break
    sleep 0.1
done
if ! listening; then
    kill "$RSP_PID" 2>/dev/null
    prov_note verdict "fail: the responder never listened"
    prov_finish
    die "the responder never started listening on ${PORT}"
fi
ok "responder listening on 127.0.0.1:${PORT}"

APPEND="root=/dev/root rootfstype=9p"
APPEND="${APPEND} rootflags=trans=virtio,version=9p2000.L,cache=loose,msize=262144"
APPEND="${APPEND} ro console=ttyS0 panic=5 init=${STAGE}/init.sh"

log "booting the guest with an SPDM-capable NVMe device"
prov_cmd "$QEMU" -M q35 "${KVM_ARGS[@]}" -smp 2 -m 2048 -nodefaults \
    -kernel "$BZIMAGE" -append "$APPEND" \
    -drive "file=${NVME_IMG},if=none,id=nvm,format=raw" \
    -device "nvme,drive=nvm,serial=deadbeef,spdm_port=${PORT}" \
    -display none -monitor none -no-reboot

timeout "$TIMEOUT" "$QEMU" -M q35 "${KVM_ARGS[@]}" -smp 2 -m 2048 -nodefaults \
    -kernel "$BZIMAGE" -append "$APPEND" \
    -fsdev "local,id=fsroot,path=/,security_model=none,readonly=on,multidevs=remap" \
    -device virtio-9p-pci,fsdev=fsroot,mount_tag=/dev/root \
    -fsdev "local,id=fsout,path=${STAGE},security_model=none" \
    -device virtio-9p-pci,fsdev=fsout,mount_tag=w9out \
    -drive "file=${NVME_IMG},if=none,id=nvm,format=raw" \
    -device "nvme,drive=nvm,serial=deadbeef,spdm_port=${PORT}" \
    -display none -monitor none -no-reboot -serial "file:${STAGE}/console.log"
QRC=$?
prov_note qemu_exit "$QRC"

kill "$RSP_PID" 2>/dev/null
wait "$RSP_PID" 2>/dev/null

GUEST_STATUS="$(cat "${STAGE}/guest_status" 2>/dev/null || echo none)"
prov_note guest_status "$GUEST_STATUS"

for f in "${STAGE}"/*.txt "${STAGE}"/*.log; do
    [ -e "$f" ] || continue
    cp "$f" "${PROV_RUN_DIR}/" 2>/dev/null
done

printf '\n'
if [ -s "${PROV_RUN_DIR}/doe-spdm.txt" ]; then
    sed 's/^/  /' "${PROV_RUN_DIR}/doe-spdm.txt"
fi
printf '\n'

if [ "$GUEST_STATUS" = "0" ]; then
    prov_note verdict pass
    prov_finish
    ok "Gate 5: an SPDM message crossed a real PCIe DOE mailbox and was answered"
    exit 0
fi
prov_note verdict fail
prov_finish
warn "the DOE path did not complete (guest status ${GUEST_STATUS});"
warn "  the console and the probe output are kept in ${PROV_RUN_DIR}"
exit 1

#!/usr/bin/env bash
#
# harness/run_afmctp.sh — Gate 5: the handshake on a transport that is not a
# TCP socket.
#
#     bash harness/run_afmctp.sh
#     bash harness/run_afmctp.sh --arms A0,P2 --name w9-afmctp
#
# What this runs, and why it is arranged this way
# -----------------------------------------------
# Weeks one to eight measured SPDM over spdm-emu's own socket transport. That
# transport is a twelve-byte header on a TCP connection (docs/transports.md);
# `--trans MCTP` picks an encoding and not a network. So every MCTP packet
# count this repository has published is arithmetic on a measured message
# length, labelled computed, and docs/fragmentation.md §5 opens with the
# sentence "No packet count here has been observed."
#
# This script is what that sentence was waiting for. It boots a guest whose
# kernel has CONFIG_MCTP — the host's does not — builds a real MCTP link inside
# it out of a pty pair and mctp-serial, puts the two emulators in separate
# network namespaces at either end of it, and runs the same arms with the same
# controlled flags as harness/run_pair.sh, which is why harness/lib/arms.sh
# exists.
#
#     netns A                         netns B
#     spdm_requester_emu  --TCP-->    <--TCP--  spdm_responder_emu
#       mctp_bridge  ====== mctpserial0 ======  mctp_bridge
#       EID 8            a real MCTP link            EID 9
#                        mtu 68 = 64 + header
#
# TWO CAPTURES OF ONE HANDSHAKE, AT TWO LAYERS
#
#   <arm>.pcap        written by spdm_requester_emu, one record per SPDM
#                     message, exactly as in every previous run. It feeds the
#                     existing analysis unchanged — spdm_dump, fields.py,
#                     check_negotiated.py — and it is the control: if these
#                     records match the socket-line run's, the transport
#                     changed nothing about the protocol.
#
#   <arm>.link.pcap   written by harness/mctp_capture.py from an AF_PACKET
#                     socket on mctpserial0, one record per MCTP *packet*.
#                     This is the thing that could not exist before.
#
# The difference between those two files is the whole of Gate 5.
#
# Everything the guest does is in a generated script that is archived into the
# run directory, so what ran and what is kept are the same file.
#
# Exit codes
#   0  the guest completed and every arm negotiated what it declared
#   1  an arm failed, or the wire disagreed with the flags. Evidence is KEPT.
#   2  a prerequisite is missing

set -uo pipefail
_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "${_HERE}/lib/common.sh"
# shellcheck source=lib/provenance.sh
. "${_HERE}/lib/provenance.sh"
# shellcheck source=lib/arms.sh
. "${_HERE}/lib/arms.sh"
set +e

FLAVOR="pqc"
RUN_NAME="w9-afmctp"
WANT="A0,P2"
TIMEOUT=1200
EID_A=8
EID_B=9
MCTP_NET=1

# The calibration lengths. Not a sweep: the set is chosen so that several of
# them are lengths at which the two candidate formulas give DIFFERENT answers,
# and 16853 is the post-quantum certificate chain measured in week eight, so the
# headline number is a measurement of the real thing rather than of a round
# number near it.
#
#   L      ceil((L+1)/64)   ceil(L/(64-4-1))
#   1            1                 1          agree
#   60           1                 2          SEPARATES
#   63           1                 2          SEPARATES
#   64           2                 2          agree - a boundary, not a test
#   119          2                 3          SEPARATES
#   127          2                 3          SEPARATES
#   177          3                 3          agree  <- see below
#   1024        17                18          SEPARATES
#   4352        69                74          SEPARATES
#  16853       264               286          SEPARATES
#
# ★ 177 is in the list because it was wrong. Until 2026-09-18 this project
# published, in docs/fragmentation.md and in a comment in
# bench/exp04_fragmentation.py, that 177 was THE case separating the two
# formulas because the wrong one "says 4". 59 x 3 = 177 exactly, so it says 3,
# and 177 is one of the 300 lengths in 1..399 where the two agree. It stays in
# the set as the control: a length that must be reproduced and must NOT
# discriminate.
LENGTHS="1,60,63,64,65,119,127,128,177,1024,4352,16853"

while [ $# -gt 0 ]; do
    case "$1" in
        --name)    RUN_NAME="${2:?--name needs a value}"; shift 2 ;;
        --flavor)  FLAVOR="${2:?--flavor needs a value}"; shift 2 ;;
        --arms)    WANT="${2:?--arms needs a list, e.g. A0,P2}"; shift 2 ;;
        --lengths) LENGTHS="${2:?--lengths needs a list}"; shift 2 ;;
        --timeout) TIMEOUT="${2:?--timeout needs seconds}"; shift 2 ;;
        -h|--help) sed -n '3,12p' "$0"; exit 0 ;;
        *)         die "unknown argument '$1'" ;;
    esac
done

hdr "Gate 5 · SPDM over a real MCTP link · ${RUN_NAME}"

# ── prerequisites, each named with the script that produces it ─────────────
need qemu-system-x86_64 gcc python3 make

W9="${LAB_DIR}/w9"
KVER="$(sed -n 's/^version=//p' "${REPO_ROOT}/third_party/linux.pin" 2>/dev/null)"
[ -n "$KVER" ] || die "third_party/linux.pin is missing — run: bash harness/build_guest_kernel.sh"
BZIMAGE="${W9}/linux-${KVER}/arch/x86/boot/bzImage"
[ -f "$BZIMAGE" ] || die "no guest kernel — run: bash harness/build_guest_kernel.sh"

MCTP_CLI="${W9}/mctp/obj/mctp"
[ -x "$MCTP_CLI" ] || die "no mctp tool — run: bash harness/build_mctp_tools.sh"

BIN="$(flavor_bin "$FLAVOR")"
[ -x "${BIN}/spdm_requester_emu" ] || die \
    "no ${FLAVOR} build — run: bash harness/build_spdm_emu.sh ${FLAVOR}"

log "building the bridge"
make -s -C "${REPO_ROOT}/transport" || die "transport/ did not build"
BRIDGE="${REPO_ROOT}/transport/mctp_bridge"

KVM_ARGS=()
if [ -w /dev/kvm ]; then
    KVM_ARGS=(-enable-kvm -cpu host)
    ok "/dev/kvm is usable"
else
    warn "/dev/kvm not writable — falling back to TCG, which is slow but correct"
fi

# ── the arms ───────────────────────────────────────────────────────────────
#
# Taken from lib/arms.sh, the same file harness/run_pair.sh reads, and built
# the same way its `${g}-all` arms are. Anything else and "the same experiment
# over a different transport" would be a claim about two flag lists.
SELECTED=()
for spec in "${ALGO_GROUPS[@]}"; do
    IFS='|' read -r g extra expect <<<"$spec"
    case ",${WANT}," in *",${g},"*) ;; *) continue ;; esac
    SELECTED+=("${g}|--meas_op ALL ${extra}|${EXPECT_FIXED};${expect}")
done
[ "${#SELECTED[@]}" -gt 0 ] || die "--arms '${WANT}' selected nothing"

# ── provenance ─────────────────────────────────────────────────────────────
prov_begin "$RUN_NAME" "$FLAVOR"
prov_pin_file "${WORK_DIR}/spdm-dump/BUILD_PIN.txt" BUILD_PIN.spdm-dump.txt spdm_dump
prov_pin_file "${REPO_ROOT}/third_party/linux.pin" BUILD_PIN.linux.txt guest_kernel
prov_pin_file "${REPO_ROOT}/third_party/mctp-tools.pin" BUILD_PIN.mctp-tools.txt mctp_tools
prov_note controlled_flags "${COMMON[*]}"
prov_note transport "AF_MCTP over mctp-serial, two network namespaces"
prov_note guest_kernel_version "$KVER"
prov_note guest_accel "$([ "${#KVM_ARGS[@]}" -gt 0 ] && echo kvm || echo tcg)"
prov_note calibration_lengths "$LENGTHS"
prov_note bridge_sha256 "$(sha256sum "$BRIDGE" | cut -d' ' -f1)"
prov_note qemu "$(qemu-system-x86_64 --version | head -1)"

# ── stage what the guest needs on ext4 ─────────────────────────────────────
#
# The guest sees the host filesystem, so it could read these out of the repo on
# /mnt/c. It does not, deliberately: that path is 9p inside the VM on top of
# drvfs inside WSL on top of NTFS, and a measurement should not have three
# filesystem translations in its critical path. Everything the guest touches
# while a capture is running lives on ext4.
STAGE="${W9}/run"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp "$BRIDGE" "${STAGE}/mctp_bridge"
cp "${REPO_ROOT}/harness/mctp_capture.py" "${STAGE}/mctp_capture.py"
cp "${REPO_ROOT}/harness/vm_guest_init.sh" "${STAGE}/init.sh"
chmod +x "${STAGE}/init.sh" "${STAGE}/mctp_bridge"

# ── the script the guest runs ──────────────────────────────────────────────
GUEST_CMD="${STAGE}/guest_cmd.sh"
{
cat <<GEOF
#!/bin/bash
# Generated by harness/run_afmctp.sh on $(date -u +%Y-%m-%dT%H:%M:%SZ).
# Archived into the run directory: this file and the thing that ran are one.
set -u
OUT=/run/out
MCTP=${MCTP_CLI}
BRIDGE=\$OUT/mctp_bridge
CAPTURE=\$OUT/mctp_capture.py
BIN=${BIN}
EID_A=${EID_A}
EID_B=${EID_B}
NET=${MCTP_NET}
LENGTHS="${LENGTHS}"
COMMON="${COMMON[*]}"
GEOF
cat <<'GEOF'

rc_total=0
note() { printf '\n======== %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*"; rc_total=1; }

note "kernel"
uname -srm

note "does this kernel have MCTP"
if ! $MCTP link show > "$OUT/mctp-initial.txt" 2>&1; then
    fail "mctp link show failed - no MCTP in this kernel"
    exit 3
fi
cat "$OUT/mctp-initial.txt"

# ── build the link ────────────────────────────────────────────────────────
#
# socat gives two ptys wired together. Attaching each to the MCTP serial line
# discipline turns each into an MCTP interface, and doing so from inside a
# network namespace registers the interface in that namespace. Two namespaces,
# because a socket bound to MCTP_ADDR_ANY matches any local EID: with both ends
# in one namespace the responder and the requester sockets would both be
# candidates for every inbound message.
note "socat pty pair"
socat -d -d pty,raw,echo=0 pty,raw,echo=0 > "$OUT/socat.log" 2>&1 &
SOCAT=$!
PTS=()
for _ in $(seq 60); do
    mapfile -t PTS < <(grep -o '/dev/pts/[0-9]*' "$OUT/socat.log" | head -2)
    [ "${#PTS[@]}" -ge 2 ] && break
    sleep 0.1
done
if [ "${#PTS[@]}" -lt 2 ]; then
    fail "socat did not report two ptys"
    cat "$OUT/socat.log"
    exit 3
fi
echo "ptys: ${PTS[0]} and ${PTS[1]}"

ip netns add A || fail "netns A"
ip netns add B || fail "netns B"
ip netns exec A ip link set lo up
ip netns exec B ip link set lo up

# ★ The line discipline is attached from the INITIAL namespace, and the
# interfaces are moved afterwards. That is not a stylistic choice; the first
# version of this script did it the obvious way, from inside each namespace,
# and no interface ever appeared. drivers/net/mctp/mctp-serial.c:
#
#     ndev = alloc_netdev(sizeof(*dev), name, NET_NAME_ENUM, mctp_serial_setup);
#     ...
#     rc = register_netdev(ndev);
#
# There is no dev_net_set() between those two lines, so the netdev is created
# in init_net whatever namespace the process setting TIOCSETD is in. It is
# movable — mctp_serial_setup does not set NETIF_F_NETNS_LOCAL — so the fix is
# to create both here and hand each one to the namespace it belongs in.
note "attach the line discipline (init namespace: see the comment)"
$MCTP link serial "${PTS[0]}" > "$OUT/linkA.log" 2>&1 &
LA=$!
$MCTP link serial "${PTS[1]}" > "$OUT/linkB.log" 2>&1 &
LB=$!

wait_ifaces() {
    local i n
    for i in $(seq 80); do
        n=$(ls /sys/class/net | grep -c '^mctpserial')
        [ "$n" -ge 2 ] && return 0
        sleep 0.1
    done
    return 1
}
if ! wait_ifaces; then
    fail "the serial line discipline produced fewer than two MCTP interfaces"
    cat "$OUT/linkA.log" "$OUT/linkB.log"
    ls /sys/class/net
    exit 3
fi

mapfile -t IFS_ALL < <(ls /sys/class/net | grep '^mctpserial' | sort)
IF_A="${IFS_ALL[0]}"
IF_B="${IFS_ALL[1]}"
echo "created in init namespace: ${IFS_ALL[*]}"

ip link set "$IF_A" netns A || { fail "could not move $IF_A into namespace A"; exit 3; }
ip link set "$IF_B" netns B || { fail "could not move $IF_B into namespace B"; exit 3; }
echo "A: $IF_A    B: $IF_B"

ip netns exec A $MCTP link set "$IF_A" up        || fail "link up A"
ip netns exec A $MCTP address add $EID_A dev "$IF_A" || fail "addr A"
ip netns exec A $MCTP route add $EID_B via "$IF_A"   || fail "route A"
ip netns exec B $MCTP link set "$IF_B" up        || fail "link up B"
ip netns exec B $MCTP address add $EID_B dev "$IF_B" || fail "addr B"
ip netns exec B $MCTP route add $EID_A via "$IF_B"   || fail "route B"

# ★ The independent variable of the whole fragmentation measurement is the
# transmission unit, and it is read back from the interface rather than
# asserted. mctp-serial fixes it: drivers/net/mctp/mctp-serial.c sets
# ndev->mtu = ndev->max_mtu = ndev->min_mtu = MCTP_SERIAL_MTU, which is 68,
# "base mtu (64) + mctp header". So 64 bytes of payload per packet, and no
# other value is reachable on this binding. That is not a limitation of the
# experiment; 64 is DSP0236's baseline and the only value guaranteed routable.
note "the link, as the kernel reports it"
{
    echo "### namespace A"
    ip netns exec A $MCTP link show
    ip netns exec A $MCTP address show
    ip netns exec A $MCTP route show
    echo "### namespace B"
    ip netns exec B $MCTP link show
    ip netns exec B $MCTP address show
    ip netns exec B $MCTP route show
    echo "### sysfs mtu"
    echo "A $IF_A mtu $(ip netns exec A cat /sys/class/net/$IF_A/mtu)"
    echo "B $IF_B mtu $(ip netns exec B cat /sys/class/net/$IF_B/mtu)"
} | tee "$OUT/link-state.txt"

# ── experiment one: calibration ───────────────────────────────────────────
#
# Messages of chosen lengths, so the formula is tested where the candidates
# disagree instead of only where the handshake happens to land.
# Wait for the capture to be draining, not for a number of seconds. See the
# comment in harness/mctp_capture.py about what a sleep bought on 2026-09-18.
wait_ready() {
    local f=$1 i
    for i in $(seq 600); do
        [ -e "$f" ] && return 0
        sleep 0.1
    done
    return 1
}

note "calibration replay"
NLEN=$(echo "$LENGTHS" | tr ',' '\n' | grep -c .)
ip netns exec B $BRIDGE --role sink --net $NET --expect "$NLEN" > "$OUT/sink.log" 2>&1 &
SINK=$!
sleep 0.3
rm -f "$OUT/replay.stop" "$OUT/replay.ready"
ip netns exec A python3 $CAPTURE --iface "$IF_A" --out "$OUT/replay.link.pcap" \
    --stop-file "$OUT/replay.stop" --ready-file "$OUT/replay.ready" \
    --expect-eids "$EID_A,$EID_B" \
    > "$OUT/replay.capture.log" 2>&1 &
CAP=$!
wait_ready "$OUT/replay.ready" || { fail "the replay capture never became ready"; exit 3; }
ip netns exec A $BRIDGE --role replay --net $NET --peer-eid $EID_B \
    --lengths "$LENGTHS" > "$OUT/replay.txt" 2>&1
rp=$?
sleep 0.7
touch "$OUT/replay.stop"
wait $CAP
kill $SINK 2>/dev/null
cat "$OUT/replay.txt"
[ $rp -eq 0 ] || fail "replay returned $rp"

# ── experiment two: the handshake ─────────────────────────────────────────
GEOF
cat <<GEOF
ARMS=(
GEOF
for spec in "${SELECTED[@]}"; do
    IFS='|' read -r label aflags _expect <<<"$spec"
    printf '"%s|%s"\n' "$label" "$aflags"
done
cat <<'GEOF'
)

for spec in "${ARMS[@]}"; do
    label="${spec%%|*}"
    aflags="${spec#*|}"
    note "arm $label  ($aflags)"

    ( cd "$BIN" && ip netns exec B ./spdm_responder_emu --trans MCTP $COMMON $aflags ) \
        > "$OUT/$label.responder.log" 2>&1 &
    RSP=$!

    # Wait for the listening socket rather than sleeping: lib/handshake.sh
    # documents why, and the reason does not change inside a VM.
    for _ in $(seq 100); do
        grep -q ':2323' <<<"$(ip netns exec B ss -ltnH 2>/dev/null)" && break
        sleep 0.1
    done

    ip netns exec B $BRIDGE --role responder --net $NET --tcp-port 2323 \
        > "$OUT/$label.bridgeB.log" 2>&1 &
    BB=$!
    ip netns exec A $BRIDGE --role requester --net $NET --tcp-port 2323 \
        --peer-eid $EID_B > "$OUT/$label.bridgeA.log" 2>&1 &
    BA=$!
    for _ in $(seq 100); do
        grep -q ':2323' <<<"$(ip netns exec A ss -ltnH 2>/dev/null)" && break
        sleep 0.1
    done

    rm -f "$OUT/$label.stop" "$OUT/$label.ready"
    ip netns exec A python3 $CAPTURE --iface "$IF_A" --out "$OUT/$label.link.pcap" \
        --stop-file "$OUT/$label.stop" --ready-file "$OUT/$label.ready" \
        --expect-eids "$EID_A,$EID_B" \
        > "$OUT/$label.capture.log" 2>&1 &
    CAP=$!
    wait_ready "$OUT/$label.ready" || { fail "the $label capture never became ready"; continue; }

    ( cd "$BIN" && ip netns exec A ./spdm_requester_emu --trans MCTP $COMMON $aflags \
        --pcap "$OUT/$label.pcap" ) > "$OUT/$label.requester.log" 2>&1
    rq=$?
    echo "$rq" > "$OUT/$label.requester.status"

    sleep 1
    touch "$OUT/$label.stop"
    wait $CAP
    kill $BA $BB $RSP 2>/dev/null
    wait $BA $BB $RSP 2>/dev/null

    echo "requester exited $rq"
    tail -5 "$OUT/$label.bridgeA.log" 2>/dev/null
    tail -3 "$OUT/$label.bridgeB.log" 2>/dev/null
    # The exit code is recorded and not believed: LOG.md 2026-08-11 is what
    # that costs. The verdict comes from the captures, on the host.
done

note "interface counters at the end"
{
    ip netns exec A cat /sys/class/net/$IF_A/statistics/tx_packets | sed 's/^/A tx_packets /'
    ip netns exec A cat /sys/class/net/$IF_A/statistics/rx_packets | sed 's/^/A rx_packets /'
    ip netns exec B cat /sys/class/net/$IF_B/statistics/tx_packets | sed 's/^/B tx_packets /'
    ip netns exec B cat /sys/class/net/$IF_B/statistics/rx_packets | sed 's/^/B rx_packets /'
    ip netns exec A cat /sys/class/net/$IF_A/statistics/rx_errors  | sed 's/^/A rx_errors  /'
    ip netns exec A cat /sys/class/net/$IF_A/statistics/tx_dropped | sed 's/^/A tx_dropped /'
} | tee "$OUT/ifstats-final.txt"

kill $LA $LB $SOCAT 2>/dev/null
sync
exit $rc_total
GEOF
} > "$GUEST_CMD"
chmod +x "$GUEST_CMD"
cp "$GUEST_CMD" "${PROV_RUN_DIR}/guest_cmd.sh"

# ── boot ───────────────────────────────────────────────────────────────────
APPEND="root=/dev/root rootfstype=9p"
APPEND="${APPEND} rootflags=trans=virtio,version=9p2000.L,cache=loose,msize=262144"
APPEND="${APPEND} ro console=ttyS0 panic=5 init=${STAGE}/init.sh"

log "booting the guest (timeout ${TIMEOUT}s)"
prov_cmd qemu-system-x86_64 "${KVM_ARGS[@]}" -smp 2 -m 2048 -nodefaults \
    -kernel "$BZIMAGE" -append "$APPEND" \
    -fsdev "local,id=fsroot,path=/,security_model=none,readonly=on,multidevs=remap" \
    -device virtio-9p-pci,fsdev=fsroot,mount_tag=/dev/root \
    -fsdev "local,id=fsout,path=${STAGE},security_model=none" \
    -device virtio-9p-pci,fsdev=fsout,mount_tag=w9out \
    -display none -monitor none -no-reboot -serial "file:${STAGE}/console.log"

timeout "$TIMEOUT" qemu-system-x86_64 "${KVM_ARGS[@]}" -smp 2 -m 2048 -nodefaults \
    -kernel "$BZIMAGE" -append "$APPEND" \
    -fsdev "local,id=fsroot,path=/,security_model=none,readonly=on,multidevs=remap" \
    -device virtio-9p-pci,fsdev=fsroot,mount_tag=/dev/root \
    -fsdev "local,id=fsout,path=${STAGE},security_model=none" \
    -device virtio-9p-pci,fsdev=fsout,mount_tag=w9out \
    -display none -monitor none -no-reboot -serial "file:${STAGE}/console.log"
QRC=$?
prov_note qemu_exit "$QRC"

GUEST_STATUS="$(cat "${STAGE}/guest_status" 2>/dev/null || echo "none")"
prov_note guest_status "$GUEST_STATUS"
if [ "$QRC" -ne 0 ]; then
    warn "qemu exited ${QRC} (124 means the timeout fired)"
fi
log "guest payload status: ${GUEST_STATUS}"

# ── collect ────────────────────────────────────────────────────────────────
for f in "${STAGE}"/*.pcap "${STAGE}"/*.json "${STAGE}"/*.log "${STAGE}"/*.txt \
         "${STAGE}"/*.status; do
    [ -e "$f" ] || continue
    cp "$f" "${PROV_RUN_DIR}/" 2>/dev/null
done

# ── analysis, on the host, with the tools that already exist ───────────────
SPDM_DUMP="${WORK_DIR}/spdm-dump/build/bin/spdm_dump"
RESULTS="${PROV_RUN_DIR}/arms.tsv"
printf 'arm\treq_exit\tspdm_msgs\tspdm_bytes\tlink_packets\tverdict\tnegotiated\n' > "$RESULTS"
FAILED=0
[ "$GUEST_STATUS" = "0" ] || FAILED=1

for spec in "${SELECTED[@]}"; do
    IFS='|' read -r label _aflags expect <<<"$spec"
    prefix="${PROV_RUN_DIR}/${label}"
    rq="$(cat "${prefix}.requester.status" 2>/dev/null || echo "-")"
    msgs=0; bytes=0; lpkts=0; verdict="no-capture"; negotiated=""

    if [ -s "${prefix}.pcap" ]; then
        read -r msgs bytes < <(python3 "${REPO_ROOT}/harness/pcapcount.py" \
            "${prefix}.pcap" --json 2>/dev/null | python3 -c '
import json, sys
try:
    s = json.load(sys.stdin)["summary"]
    print(s["packets"], s["captured_bytes_total"])
except Exception:
    print(0, 0)')
        if [ -x "$SPDM_DUMP" ]; then
            "$SPDM_DUMP" -r "${prefix}.pcap" > "${prefix}.decode.txt" 2>&1
            python3 "${REPO_ROOT}/harness/fields.py" "${prefix}.decode.txt" --json \
                > "${prefix}.fields.json" 2>/dev/null || rm -f "${prefix}.fields.json"
        fi
    fi
    if [ -s "${prefix}.link.pcap" ]; then
        lpkts="$(python3 "${REPO_ROOT}/harness/pcapcount.py" "${prefix}.link.pcap" \
                 --json 2>/dev/null | python3 -c '
import json, sys
try:
    print(json.load(sys.stdin)["summary"]["packets"])
except Exception:
    print(0)')"
    fi

    # ── the two captures have to reconcile ────────────────────────────────
    #
    # One handshake, recorded twice by two programs that share no code: the
    # emulator writes one record per SPDM message, and mctp_capture.py writes
    # one per MCTP packet off an AF_PACKET socket in a virtual machine. The
    # relationship between them is arithmetic and exact --
    #
    #     emulator capture bytes  =  SPDM bytes  +  5 x messages
    #
    # -- because every record the emulator writes is a four-byte synthesised
    # MCTP header plus the message-type byte plus the message, which is the
    # same five bytes harness/verify_repo.sh already cross-checks on every
    # socket-line capture.
    #
    # If this holds, the link capture reassembled the same conversation the
    # emulator thought it had. If it does not, one of the two is lying and the
    # packet count is worthless -- so it is checked rather than assumed.
    if [ -s "${prefix}.link.pcap" ] && [ -s "${prefix}.pcap" ]; then
        read -r lmsgs lbytes < <(python3 "${REPO_ROOT}/bench/exp04_fragmentation.py" \
            --observed "${prefix}.link.pcap" --json 2>/dev/null | python3 -c '
import json, sys
try:
    o = json.load(sys.stdin)
    print(o["spdm_messages"], o["spdm_bytes"])
except Exception:
    print(0, 0)')
        expect_bytes=$(( lbytes + 5 * lmsgs ))
        if [ "$lmsgs" -gt 0 ] && [ "$expect_bytes" -eq "$bytes" ]; then
            ok "${label}: the two captures reconcile — ${lbytes} SPDM bytes + 5x${lmsgs} framing = ${bytes}"
            prov_note "arm_${label//-/_}_reconciles" "yes"
        else
            FAILED=1
            warn "${label}: the two captures do NOT reconcile"
            warn "  link capture: ${lbytes} SPDM bytes in ${lmsgs} messages -> expected ${expect_bytes}"
            warn "  emulator capture: ${bytes} bytes"
            prov_note "arm_${label//-/_}_reconciles" "no (${expect_bytes} vs ${bytes})"
        fi
    fi

    # ★ The independent variable, read back off the wire. Identical check to
    # the one run_pair.sh applies to the socket-line arms, which is the point:
    # an arm that negotiated something else is not a transport result.
    if [ -f "${prefix}.fields.json" ]; then
        out="$(python3 "${REPO_ROOT}/harness/lib/check_negotiated.py" \
               "${prefix}.fields.json" "$expect" 2>&1)"
        vrc=$?
        negotiated="$(printf '%s' "$out" | head -1)"
        if [ "$vrc" -eq 0 ]; then
            verdict="as-declared"
            ok "${label}: ${msgs} SPDM messages, ${bytes} bytes, ${lpkts} MCTP packets"
        else
            verdict="NEGOTIATION-MISMATCH"
            FAILED=1
            warn "${label}: the wire disagrees with the flags"
            printf '%s\n' "$out" | sed 's/^/      /'
        fi
    else
        FAILED=1
        warn "${label}: no decodable capture"
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$label" "$rq" "$msgs" "$bytes" "$lpkts" "$verdict" "$negotiated" >> "$RESULTS"
done

hdr "measured against the model"
for f in "${PROV_RUN_DIR}"/*.link.pcap; do
    [ -e "$f" ] || continue
    python3 "${REPO_ROOT}/bench/exp04_fragmentation.py" --observed "$f" \
        | tee "${f%.pcap}.frag.txt"
    [ "${PIPESTATUS[0]}" -eq 0 ] || FAILED=1
done

printf '\n'
column -t -s "$(printf '\t')" < "$RESULTS" | sed 's/^/  /'
printf '\n'

prov_note verdict "$([ "$FAILED" -eq 0 ] && echo pass || echo fail)"
prov_finish

if [ "$FAILED" -eq 0 ]; then
    ok "Gate 5: a handshake completed over a transport that is not a TCP socket"
    exit 0
fi
warn "something did not hold — the evidence is kept in ${PROV_RUN_DIR}"
exit 1

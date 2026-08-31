#!/usr/bin/env bash
#
# harness/capture.sh — take the week's canonical captures, with provenance.
#
#     bash harness/capture.sh                     # the full matrix, ~4 minutes
#     bash harness/capture.sh --name w2-baseline
#
# What this produces, and why each arm exists
# -------------------------------------------
# Four handshakes into one run directory, because the questions they answer are
# only answerable against each other:
#
#   classical         pqc build, stock algorithms. The comparison arm.
#   pqc               pqc build, ML-DSA-65 + ML-KEM-768, BOTH directions pinned.
#   classical-stable  stable build, stock algorithms. The control: it says
#                     whether the classical arm above can stand in for the
#                     released pair, or whether the two builds differ.
#   walkthrough       pqc build, stock algorithms, --meas_op ALL. The capture
#                     the field-by-field annotation is written against.
#
# ── why the post-quantum arm pins --req_pqc_asym as well ────────────────────
#
# On 2026-08-11 the post-quantum run set --pqc_asym ML_DSA_65 and left
# --req_pqc_asym at its default, which offers ML_DSA_44, ML_DSA_65 and
# ML_DSA_87. The responder picked ML_DSA_87 for the requester's own signature.
# That capture therefore holds a responder authenticating with ML-DSA-65 and a
# requester authenticating with ML-DSA-87, while the classical arm's requester
# used RSAPSS-3072. Two arms whose requester-side algorithm differs cannot be
# subtracted from each other, and nothing in the run said so.
#
# SPDM authenticates in two directions and negotiates each independently. Every
# arm here pins both, and the decode is what proves it — not the flags.
#
# ── why --meas_op matters more than --exe_conn ──────────────────────────────
#
# The stock flow spends 526 of its 554 packets walking measurement indices 1
# through 0xFE, twice. That is not a protocol requirement, and it is not
# laziness either: from SPDM 1.2 onward the L1/L2 measurement transcript is
# reset when a MEASUREMENT request errors, so a requester that wants a signed
# transcript has to learn which indices exist BEFORE it starts building one.
# The sample responder's eight measurements are sparse and the last sits at
# 0xFE, so the "stop once you have them all" exit never fires early.
# (spdm_emu/spdm_requester_emu/spdm_requester_measurement.c, the comment above
# step 3.)
#
# --meas_op ALL asks for every block in one message and skips both passes. That
# is the capture a person can read, which is what the annotation needs. The
# stock arms are kept because the annotation is of the reference
# implementation's real behaviour, not of a configuration invented to look tidy.

set -uo pipefail
_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${_HERE}/lib/common.sh"
. "${_HERE}/lib/provenance.sh"
. "${_HERE}/lib/handshake.sh"
set +e          # arms are expected to fail sometimes; each is judged on evidence

RUN_NAME="w2-baseline"
while [ $# -gt 0 ]; do
    case "$1" in
        --name)    RUN_NAME="${2:?--name needs a value}"; shift 2 ;;
        -h|--help) sed -n '3,20p' "$0"; exit 0 ;;
        *)         die "unknown argument '$1'" ;;
    esac
done

# The four operations that constitute an attestation flow, and the session flag
# that stops fourteen more from running inside an encrypted session a
# connection-phase flow does not need. See LOG.md, 2026-08-11.
CONN="DIGEST,CERT,CHAL,MEAS"
SESSION="NO_END"

for f in pqc stable; do
    [ -d "$(flavor_bin "$f")" ] || die "no build for flavor '${f}'
  build it first:  bash harness/build_spdm_emu.sh ${f}"
done

SPDM_DUMP=""
if command -v spdm_dump >/dev/null 2>&1; then
    SPDM_DUMP="$(command -v spdm_dump)"
elif [ -x "${WORK_DIR}/spdm-dump/build/bin/spdm_dump" ]; then
    SPDM_DUMP="${WORK_DIR}/spdm-dump/build/bin/spdm_dump"
fi
[ -n "$SPDM_DUMP" ] || die "spdm_dump not built — run: bash harness/build_spdm_dump.sh
  Without it nothing can be read back out of a capture, and a capture whose
  negotiated algorithms are unknown is not evidence of anything."

pcap_field() {   # pcap_field <file> <key>
    python3 "${REPO_ROOT}/harness/pcapcount.py" "$1" --json 2>/dev/null \
        | python3 -c "import json,sys; print(json.load(sys.stdin)['summary']['$2'])" \
          2>/dev/null || printf '0'
}

hdr "capture  ·  ${RUN_NAME}"

prov_begin "$RUN_NAME" pqc
prov_pin  stable  BUILD_PIN.stable.txt
prov_pin_file "${WORK_DIR}/spdm-dump/BUILD_PIN.txt" BUILD_PIN.spdm-dump.txt spdm_dump

RESULTS="${PROV_RUN_DIR}/arms.tsv"
printf 'arm\tflavor\texit\tpackets\tbytes\tnote\n' > "$RESULTS"

# arm_in <bin_dir> <label> <flavor> <note> [emulator args...]
#
# The directory is a parameter because it is the independent variable of one of
# the arms below. libspdm's sample device-secret library opens its certificates
# by relative path, so which certificates an emulator serves is decided by the
# directory it runs from and by nothing else — no flag selects them.
arm_in() {
    local bin="$1" label="$2" flavor="$3" note="$4"; shift 4
    local prefix="${PROV_RUN_DIR}/${label}"
    local rc=0 pkts bytes

    log "arm '${label}'  (flavor=${flavor})"
    dim "    cwd ${bin}"
    dim "    --exe_conn ${CONN} --exe_session ${SESSION} $*"
    hs_run "$bin" "$prefix" \
        --exe_conn "$CONN" --exe_session "$SESSION" "$@" || rc=$?

    pkts="$(pcap_field "${prefix}.pcap" packets)"
    bytes="$(pcap_field "${prefix}.pcap" captured_bytes_total)"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$label" "$flavor" "$rc" "$pkts" "$bytes" "$note" >> "$RESULTS"

    if [ "$rc" -eq 0 ]; then
        ok "${label}: exit 0, ${pkts} packets, ${bytes} bytes"
    else
        warn "${label}: exit ${rc}, ${pkts} packets — see ${label}.req.log"
    fi

    # Decode immediately. An undecoded capture is a file, not evidence.
    #
    # Two decodes are kept, because they answer different questions. The
    # summary says what each message MEANT; the hex says how many bytes it
    # OCCUPIED, which the summary never states and which every later cost
    # comparison is built on.
    if [ -s "${prefix}.pcap" ]; then
        prov_cmd "$SPDM_DUMP" -r "${prefix}.pcap"
        "$SPDM_DUMP" -r "${prefix}.pcap" > "${prefix}.decode.txt" 2>&1
        prov_cmd "$SPDM_DUMP" -r "${prefix}.pcap" -x
        "$SPDM_DUMP" -r "${prefix}.pcap" -x > "${prefix}.hex.txt" 2>&1
    fi
}

# arm <label> <flavor> <note> [emulator args...] — from the flavor's own build.
arm() {
    local label="$1" flavor="$2" note="$3"; shift 3
    arm_in "$(flavor_bin "$flavor")" "$label" "$flavor" "$note" "$@"
}

# ---------------------------------------------------------------------------

arm classical pqc "stock algorithms, pqc build" \
    --meas_op ONE_BY_ONE

arm pqc pqc "ML-DSA-65 + ML-KEM-768, both directions pinned" \
    --asym NONE --dhe NONE \
    --pqc_asym ML_DSA_65 --req_pqc_asym ML_DSA_65 \
    --kem ML_KEM_768 --pqc_first TRUE \
    --meas_op ONE_BY_ONE

arm classical-stable stable "stock algorithms, stable build — the control" \
    --meas_op ONE_BY_ONE

arm walkthrough pqc "stock algorithms + --meas_op ALL — the annotated capture" \
    --meas_op ALL

# One algorithm per group instead of the stock two to four, everything else
# identical to `classical`. The question it answers is a common assumption:
# does offering more algorithms make NEGOTIATE_ALGORITHMS bigger? The fields
# that carry them are fixed-width bitmasks, so the arithmetic says no — but an
# argument from a header file is not a measurement, and the alternative (that a
# group set to NONE drops its whole AlgStructure table) would change the size
# for a different reason. Two captures settle it.
arm single-algo pqc "one algorithm per group — does offering more cost bytes?" \
    --hash SHA_384 --asym ECDSA_P384 --dhe SECP_384_R1 --aead AES_256_GCM \
    --req_asym RSAPSS_3072 --meas_hash SHA_512 \
    --meas_op ALL

# ── the self-signed chain, and the control it is subtracted from ────────────
#
# These two arms differ in exactly one thing: whose certificates the responder
# serves from slot 0. Same build, same flags, same slot count, same negotiated
# algorithms. Everything the pair is used to say is a difference between them,
# so anything else varying would be a second explanation nobody could rule out.
#
# --slot_count 1 was added believing it would leave only this project's own
# certificates on the wire. THAT IS WRONG, and the first capture taken with it
# said so: the responder's DIGESTS still reports ProvisionedSlotMask=0x13 and
# still serves slot 4 from DMTF's chain. What the flag actually moves is the
# REQUESTER's own provisioned slots, 0x07 to 0x01 — visible only in the DIGESTS
# that travels encapsulated the other way.
#
# The flag is kept, because what it does is worth measuring and both arms carry
# it identically, so the pair is still a one-variable comparison. But the reason
# written here was a claim that nothing in that commit could check, and it was
# the one thing in it that was false. See LOG.md, 2026-08-31.
#
# What the pair measures:
#   * a chain N bytes larger costs 2N on the wire, because this flow fetches the
#     responder's chain twice;
#   * dropping two of the requester's slots costs 2 x (48 + 4) = 104 bytes of
#     DIGESTS, which fields.py reconstructs rather than asserts;
#   * and the self-signed capture carries THREE distinct roots — this project's
#     on responder slot 0, DMTF's ecp384 root on responder slot 4, and DMTF's
#     rsa3072 root for the requester, whose chain is selected by ReqAsym and so
#     was never in the directory that was replaced.

arm sample-1slot pqc "upstream chain, one slot — the control for 'selfsigned'" \
    --meas_op ALL --slot_count 1

SELFSIGNED_DIR=""
if [ -f "${REPO_ROOT}/certs/out/bundle_responder.certchain.der" ] \
   && [ -f "${REPO_ROOT}/certs/out/end_responder.key" ]; then
    if SELFSIGNED_DIR="$(bash "${REPO_ROOT}/certs/stage_chain.sh" pqc 2>/dev/null)"; then
        prov_note selfsigned_sandbox "$SELFSIGNED_DIR"
        prov_note selfsigned_chain_sha256 \
            "$(sha256sum "${REPO_ROOT}/certs/out/bundle_responder.certchain.der" | cut -d' ' -f1)"
        arm_in "$SELFSIGNED_DIR" selfsigned pqc \
            "this project's own three-layer chain in slot 0" \
            --meas_op ALL --slot_count 1
    else
        warn "could not stage certs/out — the selfsigned arm is skipped"
        printf 'selfsigned\tpqc\t-\t0\t0\tSKIPPED: staging failed\n' >> "$RESULTS"
    fi
else
    # Private keys are not committed, so this is the normal state of a fresh
    # clone. Say so in the run's own record rather than leaving a gap that
    # looks like a failure.
    warn "certs/out has no chain with a private key — the selfsigned arm is skipped"
    warn "  bash certs/gen_chain.sh --force   (produces a DIFFERENT chain; see RUNBOOK §11)"
    printf 'selfsigned\tpqc\t-\t0\t0\tSKIPPED: no private key in certs/out\n' >> "$RESULTS"
    prov_note selfsigned_skipped "certs/out holds no private key on this machine"
fi

# ---------------------------------------------------------------------------

hdr "arms"
awk -F'\t' '{printf "  %-18s %-8s %-6s %-9s %-9s %s\n", $1, $2, $3, $4, $5, $6}' "$RESULTS"

printf '\n'
log "extracting protocol fields from each decode"
for d in "${PROV_RUN_DIR}"/*.decode.txt; do
    [ -e "$d" ] || continue
    label="$(basename "$d" .decode.txt)"
    if python3 "${REPO_ROOT}/harness/fields.py" "$d" \
            --json > "${PROV_RUN_DIR}/${label}.fields.json" 2>/dev/null; then
        ok "${label}.fields.json"
    else
        warn "could not extract fields from ${label}.decode.txt"
        rm -f "${PROV_RUN_DIR}/${label}.fields.json"
    fi
done

prov_finish

hdr "done  ·  ${PROV_RUN_ID}"
printf '  run dir : %s\n' "$PROV_RUN_DIR"
printf '  read it : python3 harness/fields.py %s/walkthrough.decode.txt\n' "$PROV_RUN_DIR"

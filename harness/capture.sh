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

# arm <label> <flavor> <note> [emulator args...]
arm() {
    local label="$1" flavor="$2" note="$3"; shift 3
    local prefix="${PROV_RUN_DIR}/${label}"
    local rc=0 pkts bytes

    log "arm '${label}'  (flavor=${flavor})"
    dim "    --exe_conn ${CONN} --exe_session ${SESSION} $*"
    hs_run "$(flavor_bin "$flavor")" "$prefix" \
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
    if [ -s "${prefix}.pcap" ]; then
        prov_cmd "$SPDM_DUMP" -r "${prefix}.pcap"
        "$SPDM_DUMP" -r "${prefix}.pcap" > "${prefix}.decode.txt" 2>&1
    fi
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

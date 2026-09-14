#!/usr/bin/env bash
#
# harness/run_pair.sh — the post-quantum A/B, with every other variable pinned
# and the independent variable read back off the wire.
#
#     bash harness/run_pair.sh                      # four arms, ~2 minutes
#     bash harness/run_pair.sh --name w7-pqc-ab
#     bash harness/run_pair.sh --only A0-all
#
# What this measures
# ------------------
# Two algorithm sets at the same NIST security level, and nothing else
# different:
#
#   A0   ECDSA P-384 + ECDHE P-384        the classical baseline
#   P2   ML-DSA-65   + ML-KEM-768         the post-quantum one
#
# Each is run through two measurement flows, because the flow is part of the
# claim and reporting one ratio without saying which flow produced it is how a
# table becomes unfalsifiable:
#
#   -all   --meas_op ALL          one request, one response, one signature
#   -obo   --meas_op ONE_BY_ONE   the emulator's default: walk every index
#
# On 2026-09-14 the two flows differed by 9,108 bytes out of 20,549 in an
# existing capture — 44% of the total, spent walking measurement indices that
# are byte-identical between the two algorithm sets. That traffic is a constant
# across the A/B, so it does not corrupt the DIFFERENCE, and it dilutes the
# RATIO by almost half. Both numbers are true and they are not the same number.
#
# ── why the flag list is this long ─────────────────────────────────────────
#
# Single-variable does not mean "I only changed one flag". It means "I can show
# nothing else moved", and the emulator's defaults move plenty. Read out of
# spdm_emu/spdm_emu_common/key.c rather than out of --help, at the commit in
# third_party/spdm-emu-pqc.pin:
#
#   m_use_mut_auth        = MUT_AUTH_REQUESTED_WITH_ENCAP_REQUEST   (on)
#   m_use_basic_mut_auth  = 1                                       (on)
#   m_support_req_asym_algo  = RSAPSS_3072|RSAPSS_2048|RSASSA_3072|RSASSA_2048
#   m_support_req_pqc_asym_algo = ML_DSA_44|ML_DSA_65|ML_DSA_87
#   m_use_slot_count      = 3        (not 1)
#   m_support_hash_algo   = SHA_384|SHA_256
#   m_support_measurement_hash_algo = SHA_512|SHA_384|SHA_256
#   m_support_dhe_algo    = SECP_384_R1|SECP_256_R1|FFDHE_3072|FFDHE_2048
#   m_support_aead_algo   = AES_256_GCM|CHACHA20_POLY1305
#   m_support_other_params_support = OPAQUE_FMT_1|MULTI_KEY_CONN
#
# Left alone, mutual authentication is ON and the requester authenticates with
# RSA-PSS 3072, so both arms carry a requester certificate chain the experiment
# never asked for. In the 2026-08-28 baseline that chain is 4,460 bytes of
# DELIVER_ENCAPSULATED_RESPONSE — 22% of the capture — identical in both arms,
# and therefore invisible in the difference and corrosive to the ratio.
#
# ── the part that is not a flag ────────────────────────────────────────────
#
# ★ Requesting an algorithm and negotiating it are different events. If the
# responder does not support what was asked for, SPDM does not fail — it
# selects something else, and a table built on the flags would be wrong with no
# symptom. So every arm declares what it EXPECTS to be negotiated, in all
# eleven groups the protocol negotiates separately, and this script reads the
# ALGORITHMS response back through harness/fields.py and REFUSES THE RUN when
# they differ. docs/roadmap.md standing rule 8, and 2026-08-17 in LOG.md is
# what taking the flag's word for it cost the first time.
#
# Exit codes
#   0  every arm completed and negotiated exactly what it declared
#   1  an arm's negotiated algorithms are not what it asked for, or an arm
#      produced no capture. The captures are KEPT either way: a run that went
#      wrong is evidence about the tooling and deleting it loses the reason.

set -uo pipefail
_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${_HERE}/lib/common.sh"
. "${_HERE}/lib/provenance.sh"
. "${_HERE}/lib/handshake.sh"
set +e          # an arm may fail; each is judged on its evidence, not on $?

RUN_NAME="w7-pqc-ab"
FLAVOR="pqc"
ONLY=""

while [ $# -gt 0 ]; do
    case "$1" in
        --name)    RUN_NAME="${2:?--name needs a value}"; shift 2 ;;
        --flavor)  FLAVOR="${2:?--flavor needs a value}"; shift 2 ;;
        --only)    ONLY="${2:?--only needs an arm label}"; shift 2 ;;
        -h|--help) sed -n '3,60p' "$0"; exit 0 ;;
        *)         die "unknown argument '$1'" ;;
    esac
done

BIN="$(flavor_bin "$FLAVOR")"
[ -d "$BIN" ] || die "no build for flavor '${FLAVOR}'
  build it first:  bash harness/build_spdm_emu.sh ${FLAVOR}"

SPDM_DUMP=""
if command -v spdm_dump >/dev/null 2>&1; then
    SPDM_DUMP="$(command -v spdm_dump)"
elif [ -x "${WORK_DIR}/spdm-dump/build/bin/spdm_dump" ]; then
    SPDM_DUMP="${WORK_DIR}/spdm-dump/build/bin/spdm_dump"
fi
[ -n "$SPDM_DUMP" ] || die "spdm_dump not built — run: bash harness/build_spdm_dump.sh
  A capture whose negotiated algorithms cannot be read back is not evidence of
  anything, and reading them back is the whole point of this script."

# ── the controlled set ─────────────────────────────────────────────────────
#
# Eighteen flags, every one of which is identical in every arm. Anything the
# emulator negotiates or sizes a message by is in here; what is NOT in here is
# in the per-arm lists below, and that difference is the experiment.
#
# SC2054 fires on the commas inside --exe_conn's value. They are the
# emulator's own separator for a list of operations, not array syntax.
# shellcheck disable=SC2054
COMMON=(
    --ver            1.4
    --sec_ver        1.2
    --hash           SHA_384
    --meas_hash      SHA_384
    --aead           AES_256_GCM
    --other_param    OPAQUE_FMT_1
    --key_schedule   HMAC_HASH
    --meas_att       HASH
    --meas_sum       ALL
    --slot_count     1
    --slot_id        0
    --exe_conn       DIGEST,CERT,CHAL,MEAS
    --exe_session    NO_END
    # Mutual authentication off — the FLOW, which is what puts a requester
    # certificate chain on the wire. Measured, not assumed: harness/lib/
    # check_negotiated.py requires the capture to carry no encapsulated
    # exchange and zero requester chain bytes.
    --basic_mut_auth NO
    --mut_auth       NO
    # ── and the requester's OWN signature algorithm, which cannot be off ───
    #
    # plan/W07 said --req_asym NONE --req_pqc_asym NONE. That combination
    # makes the handshake impossible on this build, and the symptom is six
    # packets and `ERROR: libspdm_init_connection - 0x8001000a` with nothing
    # naming a flag. libspdm/library/spdm_responder_lib/libspdm_rsp_algorithms.c:
    #
    #     if (MUT_AUTH_CAP supported || requester advertises EP_INFO_CAP_SIG) {
    #         algo_size     = libspdm_get_req_asym_signature_size(...);
    #         pqc_algo_size = libspdm_get_req_pqc_asym_signature_size(...);
    #         if (((algo_size == 0) && (pqc_algo_size == 0)) ||
    #             ((algo_size != 0) && (pqc_algo_size != 0))) {
    #             return INVALID_REQUEST;   /* exactly one, never zero or two */
    #         }
    #     }
    #
    # --mut_auth and --basic_mut_auth are FLOW policy. They do not clear
    # MUT_AUTH_CAP or EP_INFO_CAP_SIG out of m_use_requester_capability_flags,
    # so the responder still requires the requester to name exactly one
    # signature algorithm for itself.
    #
    # So it is pinned rather than removed, to the SAME classical value in both
    # arms. Nothing signs with it — no encapsulated exchange happens — and the
    # only thing it puts on the wire is one 4-byte AlgStructure entry that is
    # byte-identical in every arm. Reported as upstream candidate 6 in
    # docs/upstream/README.md.
    --req_asym       ECDSA_P384
    --req_pqc_asym   NONE
)

# ── the arms ───────────────────────────────────────────────────────────────
#
# label | meas_op | arm-only flags | expected negotiation
#
# The expectation is written out independently of the flags rather than derived
# from them. Deriving it would make the check circular: it would compare the
# flags with themselves and pass on a capture where the responder chose
# something else entirely.
ARMS=(
"A0-all|ALL|--asym ECDSA_P384 --dhe SECP_384_R1 --pqc_asym NONE --kem NONE|Hash=SHA_384;MeasHash=SHA_384;AEAD=AES_256_GCM;KeySchedule=HMAC_HASH;Asym=ECDSA_P384;DHE=SECP_384_R1;PqcAsym=;KEM=;ReqAsym=ECDSA_P384;ReqPqcAsym=;MutAuth=off;ReqChain=0"
"P2-all|ALL|--asym NONE --dhe NONE --pqc_asym ML_DSA_65 --kem ML_KEM_768 --pqc_first TRUE|Hash=SHA_384;MeasHash=SHA_384;AEAD=AES_256_GCM;KeySchedule=HMAC_HASH;Asym=;DHE=;PqcAsym=ML_DSA_65;KEM=ML_KEM_768;ReqAsym=ECDSA_P384;ReqPqcAsym=;MutAuth=off;ReqChain=0"
"A0-obo|ONE_BY_ONE|--asym ECDSA_P384 --dhe SECP_384_R1 --pqc_asym NONE --kem NONE|Hash=SHA_384;MeasHash=SHA_384;AEAD=AES_256_GCM;KeySchedule=HMAC_HASH;Asym=ECDSA_P384;DHE=SECP_384_R1;PqcAsym=;KEM=;ReqAsym=ECDSA_P384;ReqPqcAsym=;MutAuth=off;ReqChain=0"
"P2-obo|ONE_BY_ONE|--asym NONE --dhe NONE --pqc_asym ML_DSA_65 --kem ML_KEM_768 --pqc_first TRUE|Hash=SHA_384;MeasHash=SHA_384;AEAD=AES_256_GCM;KeySchedule=HMAC_HASH;Asym=;DHE=;PqcAsym=ML_DSA_65;KEM=ML_KEM_768;ReqAsym=ECDSA_P384;ReqPqcAsym=;MutAuth=off;ReqChain=0"
)

hdr "post-quantum A/B  ·  ${RUN_NAME}"

prov_begin "$RUN_NAME" "$FLAVOR"
prov_pin_file "${WORK_DIR}/spdm-dump/BUILD_PIN.txt" BUILD_PIN.spdm-dump.txt spdm_dump
prov_note controlled_flags "${COMMON[*]}"

RESULTS="${PROV_RUN_DIR}/arms.tsv"
printf 'arm\tmeas_op\texit\tpackets\tbytes\tnegotiated\tverdict\n' > "$RESULTS"

FAILED=0

for spec in "${ARMS[@]}"; do
    IFS='|' read -r label meas_op extra expect <<<"$spec"
    [ -z "$ONLY" ] || [ "$ONLY" = "$label" ] || continue

    prefix="${PROV_RUN_DIR}/${label}"
    read -r -a extra_arr <<<"$extra"
    argv=("${COMMON[@]}" --meas_op "$meas_op" "${extra_arr[@]}")

    log "arm '${label}'  (--meas_op ${meas_op})"
    dim "    ${extra}"

    # ★ The command line, recorded before the run rather than reconstructed
    # after it. Two arms' copies of this file differ in exactly the lines that
    # are the independent variable, and that diff is printed at the end.
    {
        printf '# %s — flavor %s, build %s\n' "$label" "$FLAVOR" "$(flavor_emu_ref "$FLAVOR")"
        printf '# controlled (identical in every arm):\n'
        printf '#   %s\n' "${COMMON[*]}"
        printf 'responder: ./spdm_responder_emu %s\n' "${argv[*]}"
        printf 'requester: ./spdm_requester_emu %s --pcap %s.pcap\n' "${argv[*]}" "$label"
    } > "${prefix}.cmdline.txt"

    # Cleared per arm rather than once, so a case that forgets to set one
    # cannot inherit the previous case's. Both are read by lib/handshake.sh,
    # which the linter cannot see from here -- and a comment beginning with
    # the linter's own name is parsed as a directive, which is how the first
    # version of this note turned SC2034 into SC1072.
    # shellcheck disable=SC2034
    HS_RESPONDER_ENV=()
    # shellcheck disable=SC2034
    HS_REQUESTER_EXTRA=()
    hs_run "$BIN" "$prefix" "${argv[@]}"
    rc=$?

    pkts=0; bytes=0
    if [ -s "${prefix}.pcap" ]; then
        read -r pkts bytes < <(python3 "${REPO_ROOT}/harness/pcapcount.py" \
            "${prefix}.pcap" --json 2>/dev/null | python3 -c '
import json, sys
try:
    s = json.load(sys.stdin)["summary"]
    print(s["packets"], s["captured_bytes_total"])
except Exception:
    print(0, 0)')
        prov_cmd "$SPDM_DUMP" -r "${prefix}.pcap"
        "$SPDM_DUMP" -r "${prefix}.pcap" > "${prefix}.decode.txt" 2>&1
        prov_cmd "$SPDM_DUMP" -r "${prefix}.pcap" -x
        "$SPDM_DUMP" -r "${prefix}.pcap" -x > "${prefix}.hex.txt" 2>&1
        python3 "${REPO_ROOT}/harness/fields.py" "${prefix}.decode.txt" --json \
            > "${prefix}.fields.json" 2>/dev/null \
            || rm -f "${prefix}.fields.json"
    fi

    # ── the independent variable, read back ───────────────────────────────
    verdict="?"
    negotiated=""
    if [ -f "${prefix}.fields.json" ]; then
        out="$(python3 "${REPO_ROOT}/harness/lib/check_negotiated.py" \
               "${prefix}.fields.json" "$expect" 2>&1)"
        vrc=$?
        negotiated="$(printf '%s' "$out" | head -1)"
        if [ "$vrc" -eq 0 ]; then
            verdict="as-declared"
            ok "${label}: exit ${rc}, ${pkts} packets, ${bytes} bytes — ${negotiated}"
        else
            verdict="NEGOTIATION-MISMATCH"
            FAILED=1
            warn "${label}: the wire disagrees with the flags"
            printf '%s\n' "$out" | sed 's/^/      /' >&2
        fi
    else
        verdict="NO-DECODE"
        FAILED=1
        warn "${label}: exit ${rc}, no fields could be read — see ${label}.req.log"
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$label" "$meas_op" "$rc" "$pkts" "$bytes" "$negotiated" "$verdict" >> "$RESULTS"
    prov_note "arm_${label//-/_}_verdict" "$verdict"
done

# ── the independent variable, as a diff ────────────────────────────────────

for flow in all obo; do
    a="${PROV_RUN_DIR}/A0-${flow}.cmdline.txt"
    b="${PROV_RUN_DIR}/P2-${flow}.cmdline.txt"
    if [ -f "$a" ] && [ -f "$b" ]; then
        printf '\n'
        hdr "A0 vs P2  (--meas_op ${flow})  — everything that differs"
        diff "$a" "$b" | grep -E '^[<>]' | sed 's/^/  /'
    fi
done

printf '\n'
hdr "arms"
awk -F'\t' 'NR>1 {printf "  %-8s %-11s %-5s %-7s %-9s %s\n", $1, $2, $3, $4, $5, $7}' "$RESULTS"

prov_finish

if [ "$FAILED" -ne 0 ]; then
    printf '\n'
    warn "at least one arm did not negotiate what it asked for."
    warn "  The captures are kept. A table built on these numbers would be"
    warn "  reporting the flags rather than the handshake."
    exit 1
fi

printf '\n'
ok "every arm negotiated exactly what it declared, in all groups"
printf '  run dir : %s\n' "$PROV_RUN_DIR"
printf '  compare : python3 bench/pcapstat.py %s/A0-all.pcap --json\n' "$PROV_RUN_DIR"

#!/usr/bin/env bash
#
# harness/run_pair.sh — the post-quantum A/B matrix, with every other variable
# pinned and the independent variable read back off the wire.
#
#     bash harness/run_pair.sh                        # the week-8 matrix, ~6 min
#     bash harness/run_pair.sh --set ab               # the original four arms
#     bash harness/run_pair.sh --set dts --flavor pqc-dts
#     bash harness/run_pair.sh --only P2-all
#     bash harness/run_pair.sh --list                 # what each set contains
#
# The name says "pair" and it now runs up to twenty arms. It keeps the name
# because every arm in it IS one half of a pair — §"the three comparisons" below
# — and because eight dated entries in LOG.md name this path. A file renamed for
# tidiness takes its own history with it.
#
# ── the three comparisons ───────────────────────────────────────────────────
#
# Six algorithm groups, arranged so that each one is the other half of exactly
# one question. NIST security categories are FIPS 203/204's, not this project's.
#
#   A0  ECDSA P-384  + ECDHE P-384        sig cat 3   kex cat 3
#   A1  ECDSA P-521  + ECDHE P-521        sig cat 5   kex cat 5
#   P1  ML-DSA-44    + ML-KEM-512         sig cat 2   kex cat 1
#   P2  ML-DSA-65    + ML-KEM-768         sig cat 3   kex cat 3
#   P3  ML-DSA-87    + ML-KEM-1024        sig cat 5   kex cat 5
#   S1  SLH-DSA-SHA2-128s + ML-KEM-512    sig cat 1   kex cat 1
#
#   A0 ↔ P2   classical against post-quantum at MATCHED category 3.
#   A1 ↔ P3   the same question at MATCHED category 5 — so "the gap" can be
#             shown to be a function of the level rather than one anecdote.
#   P1 ↔ S1   lattice against hash-based signatures, SAME KEM, so the only
#             thing that moves is the signature family.
#
#   P1 → P2 → P3 is the within-family scaling, which is what decides whether
#   65 is a knee point or just the middle row.
#
# ★ S1 is paired with ML-KEM-512 and not ML-KEM-768. plan/W08 specified 768; at
# 768 the S1↔P1 comparison would move the KEM and the signature family at once
# and answer neither question.
#
# ── the flows ──────────────────────────────────────────────────────────────
#
#   -all   --meas_op ALL          one request, one response, one signature
#   -obo   --meas_op ONE_BY_ONE   the emulator's default: walk every index
#   -vca   --exe_conn VCA         Version-Capabilities-Algorithms and stop
#
# Reporting one ratio without saying which flow produced it is how a table
# becomes unfalsifiable: on 2026-09-14 the SAME A0/P2 pair gave 8.99x over ALL
# and 6.01x over ONE_BY_ONE. A constant added to both sides leaves a DIFFERENCE
# alone and pulls a RATIO toward 1, and ONE_BY_ONE adds about nine kilobytes of
# index walking to both.
#
# ★ -vca needs no extra flag beyond --exe_conn. --exe_session stays NO_END in
# every arm, and NO_END alone does not include EXE_SESSION_KEY_EX, so no arm in
# this script has ever established a secure session. Checked against the
# captures rather than assumed: no KEY_EXCHANGE appears in any of them.
#
# ── why the controlled flag list is this long ──────────────────────────────
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
# RSA-PSS 3072, so every arm carries a requester certificate chain the
# experiment never asked for. In the 2026-08-28 baseline that chain is 4,460
# bytes of DELIVER_ENCAPSULATED_RESPONSE — 22% of the capture — identical in
# both arms, and therefore invisible in the difference and corrosive to the
# ratio.
#
# ── the part that is not a flag ────────────────────────────────────────────
#
# ★ Requesting an algorithm and negotiating it are different events. If the
# responder does not support what was asked for, SPDM does not fail — it
# selects something else, and a table built on the flags would be wrong with no
# symptom. So every arm declares what it EXPECTS to be negotiated, in all
# twelve groups the protocol negotiates separately, plus four derived facts
# (MutAuth, ReqChain, Chunk, DTS), and this script reads it back through
# harness/fields.py and REFUSES THE RUN when they differ. docs/roadmap.md
# standing rule 8, and 2026-08-17 in LOG.md is what taking the flag's word for
# it cost the first time.
#
# Exit codes
#   0  every arm completed and negotiated exactly what it declared
#   1  an arm's negotiated algorithms are not what it asked for, or an arm
#      produced no capture. The captures are KEPT either way: a run that went
#      wrong is evidence about the tooling and deleting it loses the reason.
#   2  a set was asked for that this flavor cannot run

set -uo pipefail
_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${_HERE}/lib/common.sh"
. "${_HERE}/lib/provenance.sh"
. "${_HERE}/lib/handshake.sh"
set +e          # an arm may fail; each is judged on its evidence, not on $?

RUN_NAME=""
FLAVOR="pqc"
ONLY=""
SETS="matrix,vca,nochunk"
LIST_ONLY=0

while [ $# -gt 0 ]; do
    case "$1" in
        --name)    RUN_NAME="${2:?--name needs a value}"; shift 2 ;;
        --flavor)  FLAVOR="${2:?--flavor needs a value}"; shift 2 ;;
        --only)    ONLY="${2:?--only needs an arm label}"; shift 2 ;;
        --set)     SETS="${2:?--set needs one or more of ab,matrix,vca,nochunk,dts}"; shift 2 ;;
        --list)    LIST_ONLY=1; shift ;;
        -h|--help) sed -n '3,14p' "$0"; exit 0 ;;
        *)         die "unknown argument '$1'" ;;
    esac
done

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
    # So it is pinned rather than removed, to the SAME classical value in every
    # arm. Nothing signs with it — no encapsulated exchange happens — and the
    # only thing it puts on the wire is one 4-byte AlgStructure entry that is
    # byte-identical in every arm. Reported as upstream candidate 6 in
    # docs/upstream/README.md.
    --req_asym       ECDSA_P384
    --req_pqc_asym   NONE
)

# Everything the negotiation must produce that is NOT the independent variable.
# Written out rather than derived from COMMON: deriving it would compare the
# flags with themselves and pass on a capture where the responder chose
# something else entirely.
EXPECT_FIXED="Hash=SHA_384;MeasHash=SHA_384;AEAD=AES_256_GCM;KeySchedule=HMAC_HASH;ReqAsym=ECDSA_P384;ReqPqcAsym=;MutAuth=off;ReqChain=0"

# ── the six algorithm groups ───────────────────────────────────────────────
#
#   label | arm-only flags | expected negotiation for the four groups that move
ALGO_GROUPS=(
"A0|--asym ECDSA_P384 --dhe SECP_384_R1 --pqc_asym NONE --kem NONE|Asym=ECDSA_P384;DHE=SECP_384_R1;PqcAsym=;KEM="
"A1|--asym ECDSA_P521 --dhe SECP_521_R1 --pqc_asym NONE --kem NONE|Asym=ECDSA_P521;DHE=SECP_521_R1;PqcAsym=;KEM="
"P1|--asym NONE --dhe NONE --pqc_asym ML_DSA_44 --kem ML_KEM_512 --pqc_first TRUE|Asym=;DHE=;PqcAsym=ML_DSA_44;KEM=ML_KEM_512"
"P2|--asym NONE --dhe NONE --pqc_asym ML_DSA_65 --kem ML_KEM_768 --pqc_first TRUE|Asym=;DHE=;PqcAsym=ML_DSA_65;KEM=ML_KEM_768"
"P3|--asym NONE --dhe NONE --pqc_asym ML_DSA_87 --kem ML_KEM_1024 --pqc_first TRUE|Asym=;DHE=;PqcAsym=ML_DSA_87;KEM=ML_KEM_1024"
"S1|--asym NONE --dhe NONE --pqc_asym SLH_DSA_SHA2_128S --kem ML_KEM_512 --pqc_first TRUE|Asym=;DHE=;PqcAsym=SLH_DSA_SHA2_128S;KEM=ML_KEM_512"
)

# The responder capability list for the -nochunk arms: the twenty-three flags it
# advertises by default, minus CHUNK.
#
# ★ Derived from a CAPTURE, not transcribed from key.c. The names come from
# bench/data/w7-pqc-ab-*/A0-all.fields.json's capabilities.responder.flags,
# mapped to the emulator's own CLI spellings in
# m_spdm_responder_capabilities_string_table. A hand-copied list of twenty-three
# flags is twenty-three chances to change a second variable, and this arm's whole
# claim is that exactly one moved — which check_negotiated.py's Chunk clause and
# the per-message byte table then have to confirm.
NOCHUNK_CAPS="CACHE,CERT,CHAL,MEAS_SIG,MEAS_FRESH,ENCRYPT,MAC,MUT_AUTH,KEY_EX,PSK_WITH_CONTEXT,ENCAP,HBEAT,KEY_UPD,HANDSHAKE_IN_CLEAR,SET_CERT,CSR,EP_INFO_SIG,MEL,MULTI_KEY_NEG,GET_KEY_PAIR_INFO,SET_KEY_PAIR_INFO,LARGE_RESP"

# The DataTransferSize sweep. 4608 is the unpatched build's compile-time value
# and is the CONTROL: the patched build told to use it must reproduce the
# unpatched build's capture, or the patch is not inert and the sweep measures
# the patch instead of the parameter.
DTS_POINTS=(1024 2048 4608 8192 16384 32768)

# ── build the arm list ─────────────────────────────────────────────────────
#
# label | responder-extra | arm flags | expectation
ARMS=()

add_arm() { ARMS+=("$1|$2|$3|$4"); }

set_wanted() { case ",${SETS}," in *",$1,"*) return 0 ;; *) return 1 ;; esac; }

for spec in "${ALGO_GROUPS[@]}"; do
    IFS='|' read -r g extra expect <<<"$spec"

    is_ab=0
    [ "$g" = "A0" ] || [ "$g" = "P2" ] && is_ab=1

    if set_wanted matrix || { set_wanted ab && [ "$is_ab" -eq 1 ]; }; then
        add_arm "${g}-all" "" "--meas_op ALL ${extra}"         "${EXPECT_FIXED};${expect}"
        add_arm "${g}-obo" "" "--meas_op ONE_BY_ONE ${extra}"  "${EXPECT_FIXED};${expect}"
    fi
    if set_wanted vca; then
        add_arm "${g}-vca" "" "--meas_op ALL --exe_conn VCA ${extra}" \
                "${EXPECT_FIXED};${expect}"
    fi
    if set_wanted nochunk && [ "$is_ab" -eq 1 ]; then
        add_arm "${g}-nochunk" "--cap ${NOCHUNK_CAPS}" "--meas_op ALL ${extra}" \
                "${EXPECT_FIXED};${expect};Chunk=off"
    fi
    if set_wanted dts && [ "$is_ab" -eq 1 ]; then
        for d in "${DTS_POINTS[@]}"; do
            add_arm "${g}-dts${d}" "" "--meas_op ALL --data_transfer_size ${d} ${extra}" \
                    "${EXPECT_FIXED};${expect};DTS=${d}"
        done
    fi
done

[ "${#ARMS[@]}" -gt 0 ] || die "--set '${SETS}' selected no arms (have: ab, matrix, vca, nochunk, dts)"

# --list is a query and answers without a build tree, so the gate below does not
# apply to it.
if [ "$LIST_ONLY" -eq 0 ] && set_wanted dts && [ -z "$(flavor_patch "$FLAVOR")" ]; then
    warn "--set dts needs a flavor carrying transport/data-transfer-size.patch."
    warn "  Flavor '${FLAVOR}' does not, so --data_transfer_size would be an"
    warn "  unknown argument and the emulator exits 0 without speaking SPDM."
    warn "  Try: bash harness/run_pair.sh --set dts --flavor pqc-dts"
    exit 2
fi

if [ "$LIST_ONLY" -eq 1 ]; then
    hdr "arms selected by --set ${SETS}"
    for spec in "${ARMS[@]}"; do
        IFS='|' read -r label rextra aflags _ <<<"$spec"
        printf '  %-14s %s%s\n' "$label" "$aflags" \
               "${rextra:+   [responder only: ${rextra}]}"
    done
    exit 0
fi

# The run name says which sets produced it, so a directory in bench/data is
# self-describing without opening its manifest.
[ -n "$RUN_NAME" ] || RUN_NAME="w8-pqc-$(printf '%s' "$SETS" | tr ',' '-')"

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

hdr "post-quantum A/B  ·  ${RUN_NAME}  ·  ${#ARMS[@]} arms  ·  flavor ${FLAVOR}"

prov_begin "$RUN_NAME" "$FLAVOR"
prov_pin_file "${WORK_DIR}/spdm-dump/BUILD_PIN.txt" BUILD_PIN.spdm-dump.txt spdm_dump
prov_note controlled_flags "${COMMON[*]}"
prov_note arm_sets "$SETS"

RESULTS="${PROV_RUN_DIR}/arms.tsv"
printf 'arm\tflow\texit\tpackets\tbytes\tdts\tchunk_rsp\tnegotiated\tverdict\n' > "$RESULTS"

FAILED=0

for spec in "${ARMS[@]}"; do
    IFS='|' read -r label rextra aflags expect <<<"$spec"
    [ -z "$ONLY" ] || [ "$ONLY" = "$label" ] || continue

    prefix="${PROV_RUN_DIR}/${label}"
    arm_arr=(); rsp_arr=()
    read -r -a arm_arr   <<<"$aflags"
    [ -z "$rextra" ] || read -r -a rsp_arr <<<"$rextra"
    argv=("${COMMON[@]}" "${arm_arr[@]}")
    flow="${label##*-}"

    log "arm '${label}'"
    dim "    ${aflags}${rextra:+   [responder: ${rextra}]}"

    # ★ The command line, recorded before the run rather than reconstructed
    # after it. Two arms' copies of this file differ in exactly the lines that
    # are the independent variable, and that diff is printed at the end.
    {
        printf '# %s — flavor %s, build %s\n' "$label" "$FLAVOR" "$(flavor_emu_ref "$FLAVOR")"
        printf '# controlled (identical in every arm):\n'
        printf '#   %s\n' "${COMMON[*]}"
        printf '# declared negotiation: %s\n' "$expect"
        printf 'responder: ./spdm_responder_emu %s%s\n' "${argv[*]}" \
               "${rextra:+ ${rextra}}"
        printf 'requester: ./spdm_requester_emu %s --pcap %s.pcap\n' "${argv[*]}" "$label"
    } > "${prefix}.cmdline.txt"

    # Cleared per arm rather than once, so a case that forgets to set one
    # cannot inherit the previous case's. All three are read by lib/handshake.sh,
    # which the linter cannot see from here -- and a comment beginning with
    # the linter's own name is parsed as a directive, which is how the first
    # version of this note turned SC2034 into SC1072.
    # shellcheck disable=SC2034
    HS_RESPONDER_ENV=()
    # shellcheck disable=SC2034
    HS_REQUESTER_EXTRA=()
    # shellcheck disable=SC2034
    HS_RESPONDER_EXTRA=("${rsp_arr[@]}")
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

    # Two transport facts straight off the wire, for the results table. Read
    # from the capture by pcapstat.py rather than from the decode, so the
    # sweep's independent variable does not depend on a decoder that truncates.
    dts="-"; chunk_rsp="-"
    if [ -s "${prefix}.pcap" ]; then
        read -r dts chunk_rsp < <(python3 "${REPO_ROOT}/bench/pcapstat.py" \
            "${prefix}.pcap" --json 2>/dev/null | python3 -c '
import json, sys
try:
    s = json.load(sys.stdin)["summary"]
    print((s["capabilities"]["responder"] or {}).get("data_transfer_size") or "-",
          (s["chunking"]["messages"] or {}).get("SPDM_CHUNK_GET", 0))
except Exception:
    print("-", "-")')
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
            ok "${label}: exit ${rc}, ${pkts} packets, ${bytes} bytes, DTS ${dts} — ${negotiated}"
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

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$label" "$flow" "$rc" "$pkts" "$bytes" "$dts" "$chunk_rsp" \
        "$negotiated" "$verdict" >> "$RESULTS"
    prov_note "arm_${label//-/_}_verdict" "$verdict"
done

# ── the independent variable, as a diff ────────────────────────────────────
#
# One pair per comparison the matrix was designed around. Everything a reader
# has to take on trust about "single variable" is in these three diffs.
#
# ★ Compared FLAG BY FLAG and not line by line. `diff` on these files reports
# that the whole `responder:` line changed, because it did — it is one line of
# four hundred characters — so the output was six enormous lines that a reader
# cannot extract anything from, which is worse than no diff at all: it looks
# like evidence and carries none. Splitting into --flag/value pairs prints the
# count that is identical and the short list that is not, and for P1 vs S1 that
# list is one entry long.
for pair in A0:P2 A1:P3 P1:S1; do
    a="${PROV_RUN_DIR}/${pair%%:*}-all.cmdline.txt"
    b="${PROV_RUN_DIR}/${pair##*:}-all.cmdline.txt"
    if [ -f "$a" ] && [ -f "$b" ]; then
        printf '\n'
        hdr "${pair%%:*} vs ${pair##*:}  (--meas_op ALL)  — flag by flag"
        python3 - "$a" "$b" <<'PYDIFF'
import sys

def flags(path):
    for line in open(path, encoding="utf-8").read().split("\n"):
        if line.startswith("responder:"):
            argv = line.split(None, 2)[2].split()
            out, i = {}, 0
            while i < len(argv):
                if argv[i].startswith("--"):
                    if i + 1 < len(argv) and not argv[i + 1].startswith("--"):
                        out[argv[i]] = argv[i + 1]; i += 2
                    else:
                        out[argv[i]] = ""; i += 1
                else:
                    i += 1
            return out
    return {}

a, b = flags(sys.argv[1]), flags(sys.argv[2])
same = sum(1 for k in a if k in b and a[k] == b[k])
print(f"  {same} flags identical. The difference, in full:")
for k in sorted(set(a) | set(b)):
    va, vb = a.get(k, "<absent>"), b.get(k, "<absent>")
    if va != vb:
        print(f"    {k:<16} {va:<20} -> {vb}")
PYDIFF
    fi
done

printf '\n'
hdr "arms"
awk -F'\t' 'NR>1 {printf "  %-14s %-13s %-4s %-6s %-9s %-7s %-5s %s\n",
                         $1, $2, $3, $4, $5, $6, $7, $9}' "$RESULTS"

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

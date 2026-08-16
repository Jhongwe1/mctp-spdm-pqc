#!/usr/bin/env bash
#
# harness/healthcheck.sh — ten checks that decide what this project can do.
#
#   bash harness/healthcheck.sh pqc
#   bash harness/healthcheck.sh pqc --write-baseline    # also refresh docs/env-baseline.md
#   bash harness/healthcheck.sh stable
#
# Checks 4 and 7 are the ones that matter:
#
#   #4  minimal handshake — if this fails nothing downstream is possible
#   #7  post-quantum handshake — decides whether the PQC half of the project
#       is a measurement or a paper exercise
#
# Everything else is recorded so that in three months there is a written answe
# to "what was your environment", which is a question that gets asked.
#
# Exit code: 0 when check 4 passes, 1 when it does not. Check 7 failing on the
# `stable` flavor is expected and is not an error.
#
# ── three things fixed relative to a naive version of this script ───────────
#
#   1. It cd's into the binary directory before running anything. spdm-emu
#      opens its sample certificates by RELATIVE path (ecp384/..., rsa3072/...),
#      so running the binary by absolute path from elsewhere fails with an
#      unhelpful error about a missing certificate chain.
#   2. It waits for the responder to actually be listening instead of
#      sleeping a fixed number of seconds. A fixed sleep is a race that passes
#      on an idle laptop and fails in CI.
#   3. Every child process is killed on exit, including on Ctrl-C. A stray
#      responder holding port 2323 makes the next run fail for a reason that
#      has nothing to do with the code.

set -uo pipefail

_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${_HERE}/lib/common.sh"
. "${_HERE}/lib/provenance.sh"
. "${_HERE}/lib/handshake.sh"

FLAVOR="${1:-pqc}"
WRITE_BASELINE=0
[ "${2:-}" = "--write-baseline" ] && WRITE_BASELINE=1

BIN="$(flavor_bin "$FLAVOR")"

# ── the two flags that define "minimal", and why both are needed ────────────
#
# MIN_CONN cuts the connection phase from the ten operations spdm-emu runs by
# default down to the four that constitute an attestation flow.
#
# MIN_SESSION is the one that is easy to miss, and it is the more important of
# the two. `--exe_session` defaults to FOURTEEN operations —
#   KEY_EX,PSK,KEY_UPDATE,HEARTBEAT,MEAS,MEL,DIGEST,CERT,GET_CSR,SET_CERT,
#   GET_KEY_PAIR_INFO,SET_KEY_PAIR_INFO,EP_INFO,APP
# — and they run inside an encrypted session that the connection-phase
# attestation flow does not need at all. Leaving it at the default costs a
# handshake that is twice the size, twice the duration, and that exits non-zero
# because SET_CERT inside the session fails on the sample key material.
#
# Measured on this build (libspdm 4.0.0-rc), same --exe_conn either way:
#   default --exe_session : 1116 packets, 61807 bytes, 53 s, exit 1
#   --exe_session NO_END  :  554 packets, 20549 bytes, 24 s, exit 0
#
# NO_END is used because the flag parser has no token meaning "nothing", and
# NO_END (0x4) sets neither KEY_EX (0x1) nor PSK (0x2) — and those two are the
# only flags that cause spdm_requester_emu to establish a session at all. The
# name is about END_SESSION, so this is a side effect rather than the flag's
# purpose; if a future release changes it, check the two `if` statements in
# spdm_emu/spdm_requester_emu/spdm_requester_emu.c that gate do_session_via_spdm.
MIN_CONN="DIGEST,CERT,CHAL,MEAS"
MIN_SESSION="NO_END"

[ -d "$BIN" ] || die "no build for flavor '${FLAVOR}' at ${BIN}
  build it first:  bash harness/build_spdm_emu.sh ${FLAVOR}"

prov_begin "healthcheck-${FLAVOR}" "$FLAVOR"
VERDICTS="${PROV_RUN_DIR}/verdicts.tsv"
: > "$VERDICTS"

# --------------------------------------------------------------- helpers ----

verdict() {   # verdict <PASS|FAIL|INFO> <id> <description>
    printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$VERDICTS"
    printf '  [%s] %s\n' "$1" "$3"
}

# grep -c prints "0" AND exits 1 when there are no matches. Writing
# `$(grep -c ... || echo 0)` therefore yields "0\n0", which then fails every
# numeric test with "integer expression expected". Swallow the status instead
# of supplying a replacement value.
count_matches() {   # count_matches <pattern> <file>
    local n
    n="$(grep -c "$1" "$2" 2>/dev/null || true)"
    printf '%s' "${n:-0}"
}

# Pull one field out of a capture summary, or 0 if anything at all goes wrong.
pcap_field() {   # pcap_field <file> <key>
    python3 "${REPO_ROOT}/harness/pcapcount.py" "$1" --json 2>/dev/null \
        | python3 -c "import json,sys; print(json.load(sys.stdin)['summary']['$2'])" \
          2>/dev/null || printf '0'
}

section() { printf '\n=== %s ===\n' "$*"; }

# Starting a responder, waiting for it to actually listen, running a requester
# at it and cleaning up afterwards lives in harness/lib/handshake.sh, because
# harness/capture.sh needs exactly the same sequence. Two copies of a
# four-failure-mode procedure is two places for it to be wrong differently —
# the same argument .github/workflows/ci.yml makes for shelling out to
# verify_repo.sh instead of restating its checks.
trap hs_cleanup EXIT INT TERM

# do_handshake <label> <extra args...>
# Leaves <label>.{rsp,req}.log and <label>.pcap in the run directory.
do_handshake() {
    local label="$1"; shift
    hs_run "$BIN" "${PROV_RUN_DIR}/${label}" \
        --exe_conn "$MIN_CONN" --exe_session "$MIN_SESSION" "$@"
}

# ------------------------------------------------------------------ body ----

body() {

printf 'SPDM attestation lab — environment baseline\n'
printf 'flavor : %s\n' "$FLAVOR"
printf 'binary : %s\n' "$BIN"
printf 'run    : %s\n' "$PROV_RUN_ID"
printf 'date   : %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

section "0. version pins (the caption source for every table in this repo)"
if [ -f "$(flavor_pin "$FLAVOR")" ]; then
    cat "$(flavor_pin "$FLAVOR")"
    verdict PASS 0 "BUILD_PIN.txt present"
else
    verdict FAIL 0 "BUILD_PIN.txt missing — results cannot be attributed"
fi

section "1. which algorithms the CLI exposes (decides which experiments exist)"
HELP="$("${BIN}/spdm_requester_emu" --help 2>&1 || true)"
printf '%s\n' "$HELP" | grep -oE '\-\-(pqc_asym|kem|pqc_first|asym|hash|dhe|aead|ver)[^]]*' \
    | sed 's/^/  /' | head -40 || true
if printf '%s\n' "$HELP" | grep -q -- '--pqc_asym'; then
    verdict PASS 1 "--pqc_asym exposed by this build"
else
    verdict INFO 1 "--pqc_asym absent (expected for flavor=stable)"
fi

section "2. SPDM versions this build negotiates"
printf '%s\n' "$HELP" | grep -oE '\-\-ver[^]]*' | sed 's/^/  /' || echo "  (not advertised in --help)"

section "3. sample certificates and keys (make copy_sample_key)"
if ls -d "${BIN}"/*/ >/dev/null 2>&1; then
    ls -d "${BIN}"/*/ | sed 's#.*/\([^/]*\)/$#  \1/#' | head -30
    KEYDIRS="$(ls -d "${BIN}"/*/ 2>/dev/null | wc -l)"
    verdict PASS 3 "${KEYDIRS} sample key directories present"
else
    verdict FAIL 3 "no sample key directories — 'make copy_sample_key' did not run before 'make'"
fi

section "4. minimal handshake  ★ go / no-go for the whole project"
printf '  --exe_conn %s  --exe_session %s\n' "$MIN_CONN" "$MIN_SESSION"
if do_handshake minimal; then
    # An exit status of 0 is necessary but not sufficient. spdm_requester_emu
    # does more than the handshake, and a stage that fails without aborting
    # would leave the status at 0 while the capture is not what it claims to
    # be. Check the evidence as well: no error lines, and a capture that
    # actually contains a certificate-sized exchange.
    ERRS="$(count_matches 'ERROR' "${PROV_RUN_DIR}/minimal.req.log")"
    PKTS="$(pcap_field "${PROV_RUN_DIR}/minimal.pcap" packets)"
    printf '  exit=0  error lines=%s  packets=%s\n' "$ERRS" "$PKTS"
    prov_note minimal_packets "$PKTS"
    prov_note minimal_bytes   "$(pcap_field "${PROV_RUN_DIR}/minimal.pcap" captured_bytes_total)"
    if [ "$ERRS" -eq 0 ] && [ "$PKTS" -ge 10 ]; then
        verdict PASS 4 "minimal handshake completed (DIGEST, CERT, CHALLENGE, MEASUREMENTS)"
        HANDSHAKE_OK=1
    else
        verdict FAIL 4 "requester exited 0 but the evidence disagrees (errors=${ERRS}, packets=${PKTS})"
        HANDSHAKE_OK=0
        grep 'ERROR' "${PROV_RUN_DIR}/minimal.req.log" 2>/dev/null | head -10 | sed 's/^/  | /'
    fi
else
    rc=$?
    case $rc in
        90) verdict FAIL 4 "could not enter binary directory ${BIN}" ;;
        91) verdict FAIL 4 "responder never listened on port ${HS_PORT} — see minimal.rsp.log" ;;
        124) verdict FAIL 4 "requester timed out after ${HS_TIMEOUT}s — see minimal.req.log" ;;
        *)  verdict FAIL 4 "requester exited ${rc} — see minimal.req.log" ;;
    esac
    HANDSHAKE_OK=0
    printf '  --- last 15 lines of responder log ---\n'
    tail -15 "${PROV_RUN_DIR}/minimal.rsp.log" 2>/dev/null | sed 's/^/  | /'
    printf '  --- last 15 lines of requester log ---\n'
    tail -15 "${PROV_RUN_DIR}/minimal.req.log" 2>/dev/null | sed 's/^/  | /'
fi

section "5. capture file produced, and how many packets are in it"
if [ -s "${PROV_RUN_DIR}/minimal.pcap" ]; then
    python3 "${REPO_ROOT}/harness/pcapcount.py" "${PROV_RUN_DIR}/minimal.pcap" | sed 's/^/  /'
    verdict PASS 5 "pcap written and parsed by harness/pcapcount.py"
else
    verdict FAIL 5 "no pcap produced — nothing downstream can be measured"
fi

section "6. spdm_dump (offline capture decoding — the only way to read a negotiation)"
SPDM_DUMP=""
if command -v spdm_dump >/dev/null 2>&1; then
    SPDM_DUMP="$(command -v spdm_dump)"
elif [ -x "${WORK_DIR}/spdm-dump/build/bin/spdm_dump" ]; then
    SPDM_DUMP="${WORK_DIR}/spdm-dump/build/bin/spdm_dump"
fi
if [ -n "$SPDM_DUMP" ]; then
    verdict PASS 6 "spdm_dump available: ${SPDM_DUMP}"
else
    verdict INFO 6 "spdm_dump not built yet — run: bash harness/build_spdm_dump.sh"
fi

section "7. post-quantum handshake  ★ decides whether PQC is measured or estimated"
printf '  --pqc_asym ML_DSA_65  --kem ML_KEM_768  --pqc_first TRUE  --asym NONE --dhe NONE\n'
if do_handshake pqc \
        --asym NONE --dhe NONE \
        --pqc_asym ML_DSA_65 --kem ML_KEM_768 --pqc_first TRUE; then
    PQC_ERRS="$(count_matches 'ERROR' "${PROV_RUN_DIR}/pqc.req.log")"
    if [ "$PQC_ERRS" -eq 0 ]; then
        verdict PASS 7 "post-quantum handshake completed with no errors"
    else
        verdict FAIL 7 "exit 0 but ${PQC_ERRS} error lines in pqc.req.log"
    fi
    grep -E '^(asym|dhe|pqc_asym|kem|pqc_first) ' "${PROV_RUN_DIR}/pqc.req.log" \
        2>/dev/null | sed 's/^/  requested: /'

    # The values printed above are what the requester was ASKED for. What was
    # actually NEGOTIATED is checked in section 11, from the capture.
else
    rc=$?
    if [ "$FLAVOR" = "stable" ]; then
        verdict INFO 7 "PQC handshake failed on flavor=stable — expected, 3.8.0 has no ML-DSA"
    else
        verdict FAIL 7 "PQC handshake failed (rc=${rc}) — see pqc.req.log"
        tail -15 "${PROV_RUN_DIR}/pqc.req.log" 2>/dev/null | sed 's/^/  | /'
    fi
fi

section "8. system OpenSSL — only affects signing our own certificate chain (W03)"
openssl version 2>&1 | sed 's/^/  /'
if openssl list -signature-algorithms 2>/dev/null | grep -qi 'ml-dsa'; then
    verdict PASS 8 "system OpenSSL offers ML-DSA"
else
    verdict INFO 8 "system OpenSSL has no ML-DSA (needs >= 3.5) — affects W03 only, not the handshake"
fi

section "9. QEMU with an SPDM-capable device (W09 transport work)"
if command -v qemu-system-x86_64 >/dev/null 2>&1; then
    qemu-system-x86_64 -device nvme,help 2>&1 | grep -i spdm | sed 's/^/  /' \
        && verdict PASS 9 "QEMU exposes an spdm_port property" \
        || verdict INFO 9 "QEMU present but no spdm_port — W09 falls back"
else
    verdict INFO 9 "no QEMU installed — W09 transport path degrades, main line unaffected"
fi

section "10. kernel MCTP support (W09 AF_MCTP path)"
if zcat /proc/config.gz 2>/dev/null | grep -qE '^CONFIG_MCTP=[ym]' \
   || grep -qE '^CONFIG_MCTP=[ym]' "/boot/config-$(uname -r)" 2>/dev/null; then
    verdict PASS 10 "CONFIG_MCTP enabled in this kernel"
else
    ( zcat /proc/config.gz 2>/dev/null || cat "/boot/config-$(uname -r)" 2>/dev/null ) \
        | grep -E 'CONFIG_MCTP' | sed 's/^/  /' || echo "  (no kernel config readable)"
    verdict INFO 10 "no AF_MCTP in this kernel — W09 transport path degrades, main line unaffected"
fi

section "11. what the captures actually contain  ★ verified, not requested"
#
# Everything above this line reports what the emulator was told to do. This
# section reports what it did, by decoding the captures. The distinction is the
# whole discipline: an independent variable that is asserted rather than
# verified is not a variable, it is a hope.
if [ -z "$SPDM_DUMP" ]; then
    verdict INFO 11 "no spdm_dump — negotiated algorithms cannot be verified"
else
    for cap in minimal pqc; do
        [ -s "${PROV_RUN_DIR}/${cap}.pcap" ] || continue
        DEC="${PROV_RUN_DIR}/${cap}.decode.txt"
        "$SPDM_DUMP" -r "${PROV_RUN_DIR}/${cap}.pcap" > "$DEC" 2>&1
        prov_cmd "$SPDM_DUMP" -r "${PROV_RUN_DIR}/${cap}.pcap"

        printf '\n  --- %s.pcap ---\n' "$cap"
        printf '  decoded %s messages of %s packets\n' \
            "$(count_matches 'MCTP(' "$DEC")" "$(pcap_field "${PROV_RUN_DIR}/${cap}.pcap" packets)"

        VERS="$(grep -m1 -oE 'SPDM_VERSION \([^)]*\)' "$DEC" || true)"
        [ -n "$VERS" ] && printf '  %s\n' "$VERS"

        # The ALGORITHMS response, not the NEGOTIATE_ALGORITHMS request.
        NEG="$(grep -m1 -oE ' SPDM_ALGORITHMS \(.*' "$DEC" || true)"
        if [ -n "$NEG" ]; then
            for k in Hash MeasHash Asym PqcAsym DHE KEM AEAD; do
                v="$(printf '%s' "$NEG" | grep -oE "${k}=[^,)]*\([^)]*\)" | head -1 || true)"
                [ -n "$v" ] && printf '    negotiated %s\n' "$v"
            done
        fi

        # Certificate chain length, straight out of the decoded field. This is
        # the honest post-quantum cost number: same protocol field, both runs.
        CERTLEN="$(grep -m1 -oE 'SPDM_CERTIFICATE \([^)]*PortLen=0x[0-9a-f]+' "$DEC" \
                   | grep -oE 'PortLen=0x[0-9a-f]+' | cut -d= -f2 || true)"
        if [ -n "$CERTLEN" ]; then
            printf '    certificate chain: %s bytes (%s)\n' "$((CERTLEN))" "$CERTLEN"
            prov_note "${cap}_cert_chain_bytes" "$((CERTLEN))"
        fi

        # Chunking is triggered when a response exceeds DataTransferSize. A
        # post-quantum certificate does; a classical one does not. That is a
        # change in message flow, not only in size.
        CHUNKS="$(count_matches 'SPDM_CHUNK_GET' "$DEC")"
        printf '    chunk round trips: %s\n' "$CHUNKS"
        prov_note "${cap}_chunk_get_count" "$CHUNKS"

        ERRS_PROTO="$(count_matches 'SPDM_ERROR' "$DEC")"
        printf '    SPDM_ERROR responses: %s' "$ERRS_PROTO"
        if [ "$ERRS_PROTO" -gt 0 ]; then
            printf ' — %s\n' "$(grep -m1 -oE 'SPDM_ERROR \(ErrCode=[^,]*' "$DEC" | head -1)"
        else
            printf '\n'
        fi
        prov_note "${cap}_spdm_error_count" "$ERRS_PROTO"

        # spdm_dump has a compile-time LIBSPDM_MAX_CERT_CHAIN_SIZE. A
        # post-quantum chain exceeds it, and the decode stops there. Say so
        # rather than reporting a short decode as a short handshake.
        if grep -q 'cert_chain is too larger' "$DEC"; then
            printf '    ⚠ decode TRUNCATED: spdm_dump hit LIBSPDM_MAX_CERT_CHAIN_SIZE.\n'
            printf '      The handshake is not short; the decoder stopped. Counts above\n'
            printf '      cover only the decoded prefix.\n'
            prov_note "${cap}_decode_truncated" "true (spdm_dump LIBSPDM_MAX_CERT_CHAIN_SIZE)"
        else
            prov_note "${cap}_decode_truncated" "false"
        fi
    done

    MIN_CERT="$(grep -m1 -oE 'PortLen=0x[0-9a-f]+' "${PROV_RUN_DIR}/minimal.decode.txt" 2>/dev/null | cut -d= -f2 || true)"
    PQC_CERT="$(grep -m1 -oE 'PortLen=0x[0-9a-f]+' "${PROV_RUN_DIR}/pqc.decode.txt"     2>/dev/null | cut -d= -f2 || true)"
    if [ -n "$MIN_CERT" ] && [ -n "$PQC_CERT" ]; then
        printf '\n  certificate chain, classical vs post-quantum: %s vs %s bytes (%s)\n' \
            "$((MIN_CERT))" "$((PQC_CERT))" \
            "$(awk -v a="$((PQC_CERT))" -v b="$((MIN_CERT))" 'BEGIN{printf "%.1fx", a/b}')"
        printf '  Both read from the same decoded protocol field, with the negotiated\n'
        printf '  algorithm confirmed above. This one is a measurement.\n'
        verdict PASS 11 "negotiated algorithms and certificate sizes read back from the captures"
    else
        verdict INFO 11 "captures decoded, but no certificate length field found"
    fi
fi

# ---------------------------------------------------------------- summary ---
section "summary"
awk -F'\t' '{printf "  %-4s #%-3s %s\n", $1, $2, $3}' "$VERDICTS"
printf '\n'
printf '  PASS=%s  FAIL=%s  INFO=%s\n' \
    "$(grep -c '^PASS' "$VERDICTS" || true)" \
    "$(grep -c '^FAIL' "$VERDICTS" || true)" \
    "$(grep -c '^INFO' "$VERDICTS" || true)"

if [ "${HANDSHAKE_OK:-0}" -eq 1 ]; then
    printf '\n  GATE 0 (minimal handshake): PASS — the project can proceed.\n'
else
    printf '\n  GATE 0 (minimal handshake): FAIL — stop and fix this before anything else.\n'
    printf '  See RUNBOOK.md §9 (symptom -> cause -> fix).\n'
fi

}

# ------------------------------------------------------------------ run -----

OUT_TXT="${PROV_RUN_DIR}/healthcheck.txt"
body 2>&1 | tee "$OUT_TXT"

prov_note gate0_handshake "$(grep -q '^PASS	4' "$VERDICTS" && echo pass || echo fail)"
prov_note gate0_pqc       "$(grep -q '^PASS	7' "$VERDICTS" && echo pass || echo fail)"
prov_finish

if [ "$WRITE_BASELINE" -eq 1 ]; then
    BASELINE="${REPO_ROOT}/docs/env-baseline.md"
    mkdir -p "$(dirname "$BASELINE")"
    {
        echo "# Environment baseline"
        echo
        echo "Verbatim output of \`harness/healthcheck.sh\`. This file is generated;"
        echo "do not hand-edit it. Regenerate with:"
        echo
        echo '```bash'
        echo "bash harness/healthcheck.sh ${FLAVOR} --write-baseline"
        echo '```'
        echo
        echo "Run: \`${PROV_RUN_ID}\` · captured $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "Full artifacts and SHA-256 manifest: \`bench/data/${PROV_RUN_ID}/\`"
        echo
        echo '```text'
        cat "$OUT_TXT"
        echo '```'
    } > "$BASELINE"
    printf 'baseline  : %s\n' "$BASELINE"
fi

grep -q '^PASS	4' "$VERDICTS"

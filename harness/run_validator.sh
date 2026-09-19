#!/usr/bin/env bash
#
# harness/run_validator.sh — DMTF's own conformance suite, run at this
# project's responder, four times, so that the result can be read.
#
#     bash harness/run_validator.sh                    # all four arms, ~4 min
#     bash harness/run_validator.sh --list
#     bash harness/run_validator.sh --only caps-default
#     bash harness/run_validator.sh --flavor stable    # a different device
#
# What this runs
# --------------
# spdm-emu builds spdm_device_validator_sample, which drives
# DMTF/SPDM-Responder-Validator against whatever is listening on the platform
# port. The suite is written to DSP-IS0023 and records one PASS, FAIL or
# NOT_TESTED per assertion. It is not this project's code and nothing here
# patches it; what this project adds is the four arms below and the reading.
#
# -- the four arms, and why a single run would not be a measurement ----------
#
# A conformance report that says PASS everywhere carries no information about
# the suite, only about the device -- and docs/roadmap.md standing rule 11 says
# a check is worth what it rejects. So three of these four arms exist to make
# the suite say something other than PASS, on purpose, and to require that what
# it says changes in exactly the expected place.
#
#   caps-default      the responder's shipped capability set, untouched. The
#                     baseline, and the only arm whose numbers are quoted as
#                     "what this responder scores".
#
#   caps-no-mut-auth  the same responder with ONE capability bit cleared. It is
#                     here because the baseline's failures are not distributed
#                     across the suite: four of eight land on
#                     KEY_EXCHANGE_RSP.MutAuthRequested, and every group that
#                     needs a session is NOT_TESTED behind them. This arm turns
#                     "a capability bit shapes the result" from a sentence into
#                     a count of assertions.
#
#   proxy-inert       the validator reaches the responder through
#                     harness/tamper_proxy.py in --passthrough mode. Nothing is
#                     changed. Its whole job is to make the next arm readable:
#                     without it, a FAIL in proxy-flip-sig could as easily mean
#                     "the proxy cannot forward a handshake" as "the suite
#                     noticed". The control comes first, as it did in W05.
#
#   proxy-flip-sig    the same proxy, flipping the last byte of the FIRST
#                     MEASUREMENTS signature it can parse. This is the
#                     calibration: a suite that has only ever been observed
#                     passing has not been shown able to fail. The requirement
#                     is not merely that something turns red -- it is that
#                     exactly the assertion named "response signature" moves,
#                     and that the arm is otherwise identical to proxy-inert.
#                     harness/validator_report.py --compare asserts that.
#
# -- what the caller must not read ------------------------------------------
#
# spdm_device_validator_sample exits 0 unconditionally
# (spdm_device_validator_sample.c, end of main). Every assertion can fail and
# the status is still 0. It also writes nothing to stdout but four lines of
# banner: the verdict goes to test.log in the current working directory, opened
# with fopen(..., "w+") in
# common_test_framework/library/common_test_utility_lib/common_test_utility_lib.c.
#
# So this script judges an arm by the parsed contents of test.log and by
# nothing else, and it fails loudly when the file is absent -- which is the
# only way "it did not run" and "it ran and everything failed" can be told
# apart. CLAUDE.md red line 2, met for the third time in this repository.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
. "${REPO_ROOT}/harness/lib/provenance.sh"
. "${REPO_ROOT}/harness/lib/handshake.sh"

FLAVOR="pqc"
ONLY=""
LIST=0

# The responder's shipped capability set, minus MUT_AUTH, written in the names
# spdm_emu's own --cap parser accepts
# (m_spdm_responder_capabilities_string_table in spdm_emu_common/spdm_emu.c).
#
# This list is TRANSCRIBED from m_use_responder_capability_flags in
# spdm_emu_common/key.c, and a transcription is exactly the kind of fact that
# rots. It is NOT trusted: caps-default passes no --cap at all and gets the
# binary's own default, and after both arms have run,
# validator_report.py --caps-delta reads the Flags word out of each capture and
# requires the two to differ in the MUT_AUTH_CAP bit and in nothing else. If a
# bit is missing from this line, that check fails and names it.
#
# It is deliberately not sourced from the --help text, which is wrong about
# three of these: CHUNK, EP_INFO_SIG and MEL are set by default and absent from
# the help string. That is upstream candidate 2 in docs/upstream/README.md, and
# this project has already believed that help text once.
CAPS_NO_MUT_AUTH="CACHE,CERT,CHAL,MEAS_SIG,MEL,MEAS_FRESH,ENCRYPT,MAC,KEY_EX,PSK_WITH_CONTEXT,ENCAP,HBEAT,KEY_UPD,HANDSHAKE_IN_CLEAR,CHUNK,SET_CERT,CSR,MULTI_KEY_NEG,GET_KEY_PAIR_INFO,SET_KEY_PAIR_INFO,EP_INFO_SIG,LARGE_RESP"

# arm | proxy mode | responder --cap value (empty = the binary's default)
ARMS=(
    "caps-default|none|"
    "caps-no-mut-auth|none|${CAPS_NO_MUT_AUTH}"
    "proxy-inert|passthrough|"
    "proxy-flip-sig|flip-signature|"
)

usage() {
    sed -n '3,9p' "${BASH_SOURCE[0]}" | sed 's/^#\{1,\} \{0,1\}//'
    printf '\narms:\n'
    local row name mode
    for row in "${ARMS[@]}"; do
        IFS='|' read -r name mode _ <<<"$row"
        printf '  %-18s proxy: %s\n' "$name" "$mode"
    done
}

while [ $# -gt 0 ]; do
    case "$1" in
        --flavor) FLAVOR="${2:?--flavor needs a value}"; shift 2 ;;
        --only)   ONLY="${2:?--only needs an arm name}"; shift 2 ;;
        --list)   LIST=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown argument '$1' (try --help)" ;;
    esac
done

if [ "$LIST" -eq 1 ]; then usage; exit 0; fi

need python3 ss

BIN="$(flavor_bin "$FLAVOR")"
[ -x "${BIN}/spdm_device_validator_sample" ] || \
    die "no spdm_device_validator_sample in ${BIN} -- build the ${FLAVOR} flavor first (RUNBOOK section 3)"
[ -x "${BIN}/spdm_responder_emu" ] || \
    die "no spdm_responder_emu in ${BIN}"

# ------------------------------------------------------------------ proxy ---
#
# Same shape as harness/tamper.sh, and deliberately not shared with it: that
# file starts the proxy per tamper arm with a tamper-point argument this one
# never uses, and the two would have to grow a mode flag to stay one function.

PROXY="${REPO_ROOT}/harness/tamper_proxy.py"
PROXY_PORT="${SPDM_PROXY_PORT:-2324}"
PROXY_PID=""

proxy_cleanup() {
    if [ -n "$PROXY_PID" ] && kill -0 "$PROXY_PID" 2>/dev/null; then
        kill "$PROXY_PID" 2>/dev/null || true
        sleep 0.2
        kill -9 "$PROXY_PID" 2>/dev/null || true
    fi
    PROXY_PID=""
}
trap 'proxy_cleanup; hs_cleanup' EXIT

proxy_wait_listening() {
    local waited=0
    while [ "$waited" -lt 100 ]; do
        kill -0 "$PROXY_PID" 2>/dev/null || return 1
        if command -v ss >/dev/null 2>&1; then
            grep -qE "[:.]${PROXY_PORT}[[:space:]]" \
                <<<"$(ss -ltn 2>/dev/null || true)" && return 0
        else
            sleep 1; return 0
        fi
        sleep 0.1
        waited=$((waited + 1))
    done
    return 1
}

# ------------------------------------------------------------------- run ----

hdr "SPDM-Responder-Validator against the ${FLAVOR} responder"

prov_begin w10-validator "$FLAVOR"
prov_note validator_submodule \
    "$(git -C "$(flavor_dir "$FLAVOR")" submodule status SPDM-Responder-Validator 2>/dev/null \
       | awk '{print $1}' || echo unknown)"
prov_note caps_no_mut_auth_flag "$CAPS_NO_MUT_AUTH"
prov_note client spdm_device_validator_sample
prov_note client_exit_status_is_meaningless \
    "main() returns 0 unconditionally; the verdict is test.log"

# The suite runs every case at the version that case targets, so the responder
# must keep offering 1.0 through 1.4. --ver is therefore NOT in this run, and
# that is a decision rather than an omission: pinning the responder to 1.4, as
# every other experiment in this repository does, would make the suite's
# SUCCESS_10, SUCCESS_11 and SUCCESS_12 cases unreachable and the report would
# be a page of skips.
prov_note version_pinned no
prov_note version_pinned_why \
    "the suite selects a version per case; pinning --ver would make most cases unreachable"

SPDM_HS_TIMEOUT="${SPDM_HS_TIMEOUT:-600}"
HS_TIMEOUT="$SPDM_HS_TIMEOUT"
HS_CLIENT="./spdm_device_validator_sample"

ran=0
for row in "${ARMS[@]}"; do
    IFS='|' read -r name mode caps <<<"$row"
    [ -z "$ONLY" ] || [ "$ONLY" = "$name" ] || continue
    ran=$((ran + 1))

    log "arm ${name} (proxy: ${mode})"

    HS_RESPONDER_ENV=()
    HS_RESPONDER_EXTRA=()
    HS_REQUESTER_EXTRA=()
    [ -z "$caps" ] || HS_RESPONDER_EXTRA=(--cap "$caps")

    proxy_report="${PROV_RUN_DIR}/${name}.proxy.json"
    if [ "$mode" != "none" ]; then
        # --once, and it is not an optimisation.
        #
        # Without it tamper_proxy.py's run() loops on accept() forever, and the
        # `wait` below never returns: the arm's handshake completes, its
        # capture is written, and the script hangs with nothing wrong in any
        # artifact. The validator opens exactly ONE platform socket for the
        # whole suite -- init_client in platform_client_routine, before any
        # test group starts -- so one connection is the right number and the
        # proxy can be told to expect it. Cost of finding that out the other
        # way: one aborted run on 2026-10-12, recorded in LOG.md.
        proxy_args=(--listen "$PROXY_PORT" --forward "$HS_PORT"
                    --once --report "$proxy_report")
        case "$mode" in
            passthrough)    proxy_args+=(--passthrough) ;;
            flip-signature) proxy_args+=(--flip-signature -1) ;;
            *) die "unknown proxy mode '$mode'" ;;
        esac
        prov_cmd python3 "$PROXY" "${proxy_args[@]}"
        python3 "$PROXY" "${proxy_args[@]}" \
            >"${PROV_RUN_DIR}/${name}.proxy.log" 2>&1 &
        PROXY_PID=$!
        proxy_wait_listening || die "the proxy never listened on ${PROXY_PORT}"
        HS_REQUESTER_EXTRA=(--port "$PROXY_PORT")
    fi

    rm -f "${BIN}/test.log"
    rc=0
    hs_run "$BIN" "${PROV_RUN_DIR}/${name}" || rc=$?
    prov_note "${name}_client_status" "$rc"

    proxy_rc="n/a"
    if [ "$mode" != "none" ]; then
        # The proxy exits 1 when it was asked to change a byte and did not, and
        # that status is the only thing that distinguishes "the suite did not
        # notice" from "there was nothing to notice".
        proxy_rc=0
        wait "$PROXY_PID" || proxy_rc=$?
        PROXY_PID=""
        prov_note "${name}_proxy_status" "$proxy_rc"
    fi

    if [ -f "${BIN}/test.log" ]; then
        cp "${BIN}/test.log" "${PROV_RUN_DIR}/${name}.test.log"
        rm -f "${BIN}/test.log"
    else
        die "arm ${name}: no test.log -- the suite did not run. The client exit status was ${rc} and it means nothing; see ${PROV_RUN_DIR}/${name}.req.log"
    fi

    prov_run python3 "${REPO_ROOT}/harness/validator_report.py" \
        --parse "${PROV_RUN_DIR}/${name}.test.log" \
        --json  "${PROV_RUN_DIR}/${name}.assertions.json" \
        --label "$name" | tee "${PROV_RUN_DIR}/${name}.summary.txt"
    printf '  proxy status: %s\n' "$proxy_rc"
done

[ "$ran" -gt 0 ] || die "no arm matched --only '${ONLY}'"

# ------------------------------------------------------ the three assertions -
#
# None of these is a summary. Each one can fail, and each one is the reason its
# pair of arms was run rather than one of them.
#
# A failing assertion must NOT take the manifest down with it. Four captures
# and four parsed logs were produced before any of these ran; if the
# calibration comes out wrong, that is a finding about the calibration and the
# evidence for it is the run directory. Exiting under `set -e` before
# prov_finish would leave that directory without a manifest.json, which
# harness/verify_repo.sh correctly refuses, and the run would have to be
# repeated to be looked at. So each check's status is recorded and the script
# carries it to the end.

assert_rc=0

check() {
    local what="$1"; shift
    local rc=0
    prov_run "$@" || rc=$?
    prov_note "assert_${what}" "$rc"
    [ "$rc" -eq 0 ] || assert_rc=1
    return 0
}

if [ -z "$ONLY" ]; then
    hdr "the capability bit, and what it costs"
    check caps_delta_is_one_bit \
        python3 "${REPO_ROOT}/harness/validator_report.py" \
        --caps-delta "${PROV_RUN_DIR}/caps-default.pcap" \
                     "${PROV_RUN_DIR}/caps-no-mut-auth.pcap" \
        --expect-only MUT_AUTH_CAP
    check caps_effect_on_assertions \
        python3 "${REPO_ROOT}/harness/validator_report.py" \
        --compare "${PROV_RUN_DIR}/caps-default.assertions.json" \
                  "${PROV_RUN_DIR}/caps-no-mut-auth.assertions.json" \
        --json "${PROV_RUN_DIR}/compare-mut-auth.json"

    hdr "the calibration -- the suite has to be able to say FAIL"
    check calibration_flip_signature \
        python3 "${REPO_ROOT}/harness/validator_report.py" \
        --compare "${PROV_RUN_DIR}/proxy-inert.assertions.json" \
                  "${PROV_RUN_DIR}/proxy-flip-sig.assertions.json" \
        --json "${PROV_RUN_DIR}/compare-flip-sig.json" \
        --require-regressed-message "response signature"
fi

prov_note assertions_all_held "$([ "$assert_rc" -eq 0 ] && echo yes || echo NO)"
prov_finish

[ "$assert_rc" -eq 0 ] || die "an assertion above did not hold; the run directory
and its manifest are complete and say so"

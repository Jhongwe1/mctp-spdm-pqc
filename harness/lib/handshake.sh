# shellcheck shell=bash
#
# harness/lib/handshake.sh — run one SPDM handshake and leave the evidence behind.
#
# Source this, do not execute it. It needs lib/common.sh to have been sourced
# first (for REPO_ROOT and die), and it will use prov_cmd if provenance.sh is
# also loaded.
#
# Why this is a library rather than a copy in each script:
#   healthcheck.sh and capture.sh both need "start a responder, wait until it
#   is actually listening, run a requester at it, capture a pcap, and make sure
#   nothing is left holding the port". That sequence has four failure modes that
#   are easy to get subtly wrong, and a second copy is a second place for them
#   to be wrong differently:
#
#     1. spdm-emu opens its sample certificates by RELATIVE path (ecp384/...),
#        so the binary has to be run from its own directory or it dies with an
#        unhelpful message about a missing certificate chain.
#     2. `sleep 3` after starting the responder is a race. It passes on an idle
#        laptop and fails under load. Wait for the listening socket instead.
#     3. A responder that outlives the script holds the port, and the next run
#        fails for a reason that has nothing to do with the change being tested.
#     4. The requester's exit status answers a broader question than "did the
#        handshake work" — it also covers session setup, certificate
#        provisioning and anything else --exe_session turned on. The caller has
#        to look at the evidence too, so this library returns the raw status and
#        deliberately does not interpret it.
#
# Usage:
#     . "$(dirname "$0")/lib/handshake.sh"
#     hs_run <bin_dir> <out_prefix> [emulator args...]
#     rc=$?
#
# Three arrays change what hs_run does, and all are cleared by their callers
# rather than by this file, so that a case which forgets to set one cannot
# inherit the previous case's:
#     HS_RESPONDER_ENV     NAME=VALUE strings, applied to the responder only
#     HS_REQUESTER_EXTRA   arguments appended to the requester only
#     HS_RESPONDER_EXTRA   arguments appended to the responder only
#     HS_CLIENT            the program run at the responder; default
#                          ./spdm_requester_emu, and week ten also runs
#                          ./spdm_device_validator_sample through it
#
# Leaves <out_prefix>.rsp.log, <out_prefix>.req.log and <out_prefix>.pcap.
#
# Return value: the requester's exit status, or one of
#     90  could not enter the binary directory
#     91  the responder never listened
#    124  the requester timed out (from timeout(1))

HS_PORT="${SPDM_EMU_PORT:-2323}"
HS_TIMEOUT="${SPDM_HS_TIMEOUT:-120}"

HS_RESPONDER_PID=""

# Environment applied to the RESPONDER only, as NAME=VALUE strings. Empty by
# default, so every existing caller is unaffected.
#
# Why not simply export the variable around hs_run: both emulators link the
# same device secret library, so an exported SPDM_MEASUREMENTS_FILE would be
# read by the requester too. Nothing in the flows this project runs asks the
# requester for a measurement, so the capture would very probably be identical
# — and "very probably" is the wrong standard for the independent variable of
# a tamper experiment. The claim being made is that ONE side's measurements
# came from a file, so only one side is given the file.
HS_RESPONDER_ENV=()

# Arguments appended to the REQUESTER's command line only. Empty by default.
#
# Every existing caller passes one argument list to both sides, which is right
# for everything that has to be negotiated: an arm where the two disagree about
# --asym is not an arm, it is a bug. Exactly one thing is legitimately different
# between them, and it arrived with the tamper proxy: the requester connects to
# a port the responder is not listening on, because something else is. --port is
# parsed by the shared argument parser in spdm_emu_common/spdm_emu.c:785, so
# passing it to both would move the responder too and the proxy would forward
# into an empty port.
#
# It is deliberately not a general "requester options" hook. Anything else that
# differs between the two sides should be justified in the caller first, and
# this comment is where the justification for the one that exists lives.
HS_REQUESTER_EXTRA=()

# Arguments appended to the RESPONDER's command line only. Empty by default.
#
# It exists for exactly one flag, and like --port above the asymmetry is imposed
# by the tool rather than chosen. Two things about `--cap`, both read out of
# spdm_emu at the commit in third_party/spdm-emu-pqc.pin on 2026-09-14:
#
#   1. It is RESPONDER-ONLY IN EFFECT. The parser stores it in
#      m_use_capability_flags, and only spdm_responder_spdm.c:174 reads that
#      variable back. spdm_requester_spdm.c never mentions it. So the requester
#      parses --cap, prints `cap - 0x...` as confirmation, and ignores it.
#
#   2. Its value names are validated against a DIFFERENT TABLE per program —
#      m_spdm_requester_capabilities_string_table for one binary and
#      m_spdm_responder_capabilities_string_table for the other. The responder's
#      own advertised set contains MEAS_SIG, MEL, CACHE and CSR, none of which
#      exist in the requester's table. So passing one responder capability list
#      to both sides does not merely waste a flag on the requester: the
#      requester rejects it.
#
# ★ And rejects it by `print_usage(); exit(0)`, so a mistake here leaves a
# process that exited SUCCESSFULLY without speaking SPDM. What catches it is
# hs_wait_for_responder returning 91 and the caller finding no capture — not the
# exit status, which is the same 0 a good run gives. Upstream candidates 14 and
# 15 in docs/upstream/README.md.
#
# Only sides that genuinely cannot share a flag belong here. Anything that both
# ends must agree on — an algorithm, a version, a flow — must stay in the shared
# list, because an arm where the two disagree about --asym is not an arm.
HS_RESPONDER_EXTRA=()

# The program run against the responder, relative to the binary directory.
#
# It defaults to the requester emulator, which is what every caller before
# 2026-09-20 ran and what all of them still run. Week ten added a second
# client: DMTF's own conformance suite, `spdm_device_validator_sample`, which
# is a different program driving the same socket at the same responder.
#
# ★ It is a variable here rather than a second copy of this file because the
# four failure modes listed at the top are properties of "start a responder and
# point something at it", not of the requester. The validator hits three of
# them unchanged — relative certificate paths, the listening race, and the
# orphaned responder — and it makes the fourth worse rather than better:
# spdm_device_validator_sample.c's main() ends in an unconditional `return 0`,
# so its exit status is 0 whether every assertion passed, every assertion
# failed, or it never spoke SPDM at all. Its verdict is in a file called
# test.log, written to the CURRENT WORKING DIRECTORY, and this library's `cd
# "$bin"` is what decides where that lands. Callers collect it from there.
HS_CLIENT="${HS_CLIENT:-./spdm_requester_emu}"

hs_cleanup() {
    if [ -n "$HS_RESPONDER_PID" ] && kill -0 "$HS_RESPONDER_PID" 2>/dev/null; then
        kill "$HS_RESPONDER_PID" 2>/dev/null || true
        sleep 0.3
        kill -9 "$HS_RESPONDER_PID" 2>/dev/null || true
    fi
    HS_RESPONDER_PID=""
}

# The listener check, captured rather than piped, and it matters here more
# than anywhere else in the repository.
#
# `ss -ltn | grep -q PORT` returns the pipeline's status, and under
# `set -o pipefail` — which lib/common.sh turns on — grep -q exiting at the
# first match can leave `ss` writing into a closed pipe. SIGPIPE makes the
# pipeline 141, so "the port IS listening" is reported as "it is not", the
# caller keeps waiting, and the run fails ten seconds later with `return 91`
# and no explanation. It is a race that gets more likely as the machine gets
# busier, which is the worst possible property for a check whose whole job is
# to replace a `sleep 3` race.
hs_port_is_listening() {
    local listening
    if command -v ss >/dev/null 2>&1; then
        listening="$(ss -ltn 2>/dev/null || true)"
    elif command -v netstat >/dev/null 2>&1; then
        listening="$(netstat -ltn 2>/dev/null || true)"
    else
        return 2      # cannot tell; caller falls back to a sleep
    fi
    grep -qE "[:.]${HS_PORT}[[:space:]]" <<<"$listening"
}

# hs_wait_for_responder <pid> <timeout_s>
hs_wait_for_responder() {
    local pid="$1" limit="$2" waited=0 rc
    while [ "$waited" -lt "$((limit * 10))" ]; do
        kill -0 "$pid" 2>/dev/null || return 1        # it died
        hs_port_is_listening && return 0
        rc=$?
        [ "$rc" -eq 2 ] && { sleep 3; return 0; }     # no ss/netstat: best effort
        sleep 0.1
        waited=$((waited + 1))
    done
    return 1
}

# Record a command line if provenance.sh is loaded; otherwise do nothing. The
# library is usable from a throwaway script that does not want a run directory.
hs_note_cmd() {
    if declare -F prov_cmd >/dev/null 2>&1; then
        prov_cmd "$@"
    fi
}

# hs_run <bin_dir> <out_prefix> [args...]
hs_run() {
    local bin="$1" prefix="$2"; shift 2
    local rsp_log="${prefix}.rsp.log"
    local req_log="${prefix}.req.log"
    local pcap="${prefix}.pcap"
    local rc waited

    cd "$bin" || return 90

    if [ "${#HS_RESPONDER_ENV[@]}" -gt 0 ]; then
        hs_note_cmd env "${HS_RESPONDER_ENV[@]}" "./spdm_responder_emu" "$@" \
            "${HS_RESPONDER_EXTRA[@]}"
        env "${HS_RESPONDER_ENV[@]}" ./spdm_responder_emu "$@" \
            "${HS_RESPONDER_EXTRA[@]}" >"$rsp_log" 2>&1 &
    else
        hs_note_cmd "./spdm_responder_emu" "$@" "${HS_RESPONDER_EXTRA[@]}"
        ./spdm_responder_emu "$@" "${HS_RESPONDER_EXTRA[@]}" >"$rsp_log" 2>&1 &
    fi
    HS_RESPONDER_PID=$!

    if ! hs_wait_for_responder "$HS_RESPONDER_PID" 10; then
        HS_RESPONDER_PID=""
        return 91
    fi

    hs_note_cmd "$HS_CLIENT" "$@" "${HS_REQUESTER_EXTRA[@]}" \
        --pcap "$pcap"
    timeout "$HS_TIMEOUT" "$HS_CLIENT" "$@" "${HS_REQUESTER_EXTRA[@]}" \
        --pcap "$pcap" >"$req_log" 2>&1
    rc=$?

    # The requester normally shuts the responder down. Give it a moment so the
    # responder can flush its own log, then make sure either way.
    waited=0
    while kill -0 "$HS_RESPONDER_PID" 2>/dev/null && [ "$waited" -lt 30 ]; do
        sleep 0.1; waited=$((waited + 1))
    done
    hs_cleanup
    cd "$REPO_ROOT" || true
    return "$rc"
}

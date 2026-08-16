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
# Leaves <out_prefix>.rsp.log, <out_prefix>.req.log and <out_prefix>.pcap.
#
# Return value: the requester's exit status, or one of
#     90  could not enter the binary directory
#     91  the responder never listened
#    124  the requester timed out (from timeout(1))

HS_PORT="${SPDM_EMU_PORT:-2323}"
HS_TIMEOUT="${SPDM_HS_TIMEOUT:-120}"

HS_RESPONDER_PID=""

hs_cleanup() {
    if [ -n "$HS_RESPONDER_PID" ] && kill -0 "$HS_RESPONDER_PID" 2>/dev/null; then
        kill "$HS_RESPONDER_PID" 2>/dev/null || true
        sleep 0.3
        kill -9 "$HS_RESPONDER_PID" 2>/dev/null || true
    fi
    HS_RESPONDER_PID=""
}

hs_port_is_listening() {
    if command -v ss >/dev/null 2>&1; then
        ss -ltn 2>/dev/null | grep -qE "[:.]${HS_PORT}[[:space:]]"
    elif command -v netstat >/dev/null 2>&1; then
        netstat -ltn 2>/dev/null | grep -qE "[:.]${HS_PORT}[[:space:]]"
    else
        return 2      # cannot tell; caller falls back to a sleep
    fi
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

    hs_note_cmd "./spdm_responder_emu" "$@"
    ./spdm_responder_emu "$@" >"$rsp_log" 2>&1 &
    HS_RESPONDER_PID=$!

    if ! hs_wait_for_responder "$HS_RESPONDER_PID" 10; then
        HS_RESPONDER_PID=""
        return 91
    fi

    hs_note_cmd "./spdm_requester_emu" "$@" --pcap "$pcap"
    timeout "$HS_TIMEOUT" ./spdm_requester_emu "$@" --pcap "$pcap" >"$req_log" 2>&1
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

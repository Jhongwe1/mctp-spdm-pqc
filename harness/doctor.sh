#!/usr/bin/env bash
#
# harness/doctor.sh — "can this machine build the project, and check it?"
#
#   bash harness/doctor.sh
#
# Run this before anything else. It checks prerequisites only; it builds
# nothing and downloads nothing. Every failure it reports comes with the exact
# command that fixes it, because a runbook that says "install the dependencies"
# is a runbook that does not work.
#
# Exit code 0 = ready. Non-zero = fix what it printed, then re-run.
#
# "And check it" was added on 2026-09-12 along with the opa section, because the
# two are not the same question any more and pretending they were would have
# made this file contradict itself. A machine with no `opa` builds everything
# and runs every experiment; what it cannot do is evaluate rats/policy.rego,
# which is where "a tampered measurement must be rejected" lives.
#
# The first version of this comment said verify_repo.sh would skip that check
# and still pass, which is why a missing opa had to be a FAIL here. Removing
# opa from PATH on 2026-09-13 showed that claim was wrong: verify_repo.sh is
# already RED without it, because rats/appraise.py's self-test refuses to run
# without an engine rather than passing by not running. The FAIL here is
# therefore not a warning about a silent gap; it is this script agreeing with
# the one it exists to run before.

set -uo pipefail

_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${_HERE}/lib/common.sh"
set +e

FAILED=0
note() { printf '  %-22s %s\n' "$1" "$2"; }
pass() { printf '  \033[32m ok \033[0m %-18s %s\n' "$1" "$2"; }
fail() { printf '  \033[31mFAIL\033[0m %-18s %s\n' "$1" "$2"; FAILED=1; }
info() { printf '  \033[33m--  \033[0m %-18s %s\n' "$1" "$2"; }

hdr "harness/doctor.sh — prerequisite check"

# ------------------------------------------------------------ platform -----
printf '\n-- platform --\n'
if [ -r /etc/os-release ]; then
    . /etc/os-release
    note "os" "$PRETTY_NAME"
else
    note "os" "$(uname -sr)"
fi
note "kernel"  "$(uname -r)"
note "arch"    "$(uname -m)"
note "cores"   "$(nproc 2>/dev/null || echo unknown)"
note "memory"  "$(free -h 2>/dev/null | awk '/^Mem:/{print $2" total, "$7" available"}' || echo unknown)"

case "$(uname -s)" in
    Linux) pass "platform" "Linux — supported" ;;
    *)     fail "platform" "this project builds on Linux. On Windows use WSL2 or Docker; see RUNBOOK.md" ;;
esac

if grep -qi microsoft /proc/version 2>/dev/null; then
    info "wsl" "running under WSL2 — remember to keep the build tree on the Linux filesystem, not /mnt/c"
fi

# --------------------------------------------------------------- tools -----
printf '\n-- required tools --\n'
check_tool() {   # check_tool <name> <version-cmd> <apt-package>
    if command -v "$1" >/dev/null 2>&1; then
        pass "$1" "$(eval "$2" 2>&1 | head -1)"
    else
        fail "$1" "missing — sudo apt-get install -y $3"
    fi
}
check_tool git     'git --version'                          git
check_tool cmake   'cmake --version | head -1'              cmake
check_tool make    'make --version | head -1'               build-essential
check_tool gcc     'gcc --version | head -1'                build-essential
check_tool python3 'python3 --version'                      python3
check_tool perl    'perl --version | sed -n 2p'             perl

# ------------------------------------------------- tools the CHECKS need ----
#
# A third category, and it exists because the second one was the wrong home for
# opa. "Optional" is true of the build and false of the thing this repository is
# for: rats/policy.rego is where "a tampered measurement must be rejected"
# lives, and without an engine to evaluate it, harness/verify_repo.sh fails.
#
# So this is a FAIL with the fix beside it rather than an INFO somebody scrolls
# past — and the point of saying it here is that this script runs FIRST, before
# anything is built. Finding out at the end of a forty-minute build that the
# most important check cannot run is the avoidable version.
printf '\n-- tools the checks need --\n'
OPA_PIN="${REPO_ROOT}/third_party/opa.pin"
if command -v opa >/dev/null 2>&1; then
    OPA_VER="$(opa version 2>/dev/null | awk '/^Version:/{print $2}')"
    OPA_REGO="$(opa version 2>/dev/null | awk '/^Rego Version:/{print $3}')"
    pass "opa" "$OPA_VER, Rego $OPA_REGO"
    if [ -f "$OPA_PIN" ]; then
        WANT_REGO="$(awk -F= '/^rego-version=/{print $2}' "$OPA_PIN")"
        if [ -n "$WANT_REGO" ] && [ "$OPA_REGO" != "$WANT_REGO" ]; then
            fail "opa rego version" "this opa speaks Rego $OPA_REGO; third_party/opa.pin records $WANT_REGO. The policy language changed incompatibly at OPA 1.0 and rats/policy.rego is written for one of them."
        fi
    fi
else
    fail "opa" "missing — the appraisal cannot be evaluated, and harness/verify_repo.sh fails without it. Install: curl -L -o /tmp/opa https://openpolicyagent.org/downloads/v1.20.2/opa_linux_amd64_static && sudo install -m 0755 /tmp/opa /usr/local/bin/opa"
fi

printf '\n-- optional tools --\n'
for t in shellcheck jq ss qemu-system-x86_64; do
    if command -v "$t" >/dev/null 2>&1; then
        pass "$t" "present"
    else
        case "$t" in
            shellcheck)         info "$t" "absent — only needed to lint scripts (apt: shellcheck)" ;;
            jq)                 info "$t" "absent — not required; manifests are written by python3" ;;
            ss)                 info "$t" "absent — healthcheck falls back to a fixed wait (apt: iproute2)" ;;
            qemu-system-x86_64) info "$t" "absent — W09 transport work degrades, main line unaffected" ;;
        esac
    fi
done

# --------------------------------------------------------------- cmake -----
printf '\n-- versions that matter --\n'
if command -v cmake >/dev/null 2>&1; then
    CMAKE_VER="$(cmake --version | head -1 | awk '{print $3}')"
    if [ "$(printf '%s\n3.10\n' "$CMAKE_VER" | sort -V | head -1)" = "3.10" ]; then
        pass "cmake >= 3.10" "$CMAKE_VER"
    else
        fail "cmake >= 3.10" "found $CMAKE_VER"
    fi
fi
if command -v gcc >/dev/null 2>&1; then
    pass "gcc" "$(gcc -dumpfullversion -dumpversion)"
fi
if command -v openssl >/dev/null 2>&1; then
    OSSL="$(openssl version | awk '{print $2}')"
    # Captured, not piped: grep -q exits at the first match, openssl dies
    # writing the rest, and pipefail turns "found it" into 141. This branch
    # would report "no ML-DSA" on exactly the machines that have it.
    OSSL_ALGS="$(openssl list -signature-algorithms 2>/dev/null || true)"
    if grep -qi 'ml-dsa' <<<"$OSSL_ALGS"; then
        pass "openssl (system)" "$OSSL — has ML-DSA"
    else
        info "openssl (system)" "$OSSL — no ML-DSA (needs >= 3.5). The W03 chain is ECDSA-P384 and did not need it; a post-quantum chain (W07-W08) will."
        info "" "libspdm builds its OWN OpenSSL, so the handshake and PQC work are unaffected."
    fi
fi

# ---------------------------------------------------------------- disk -----
printf '\n-- disk --\n'
AVAIL_KB="$(df -Pk "$HOME" 2>/dev/null | awk 'NR==2{print $4}')"
AVAIL_GB=$(( ${AVAIL_KB:-0} / 1024 / 1024 ))
if [ "$AVAIL_GB" -ge 25 ]; then
    pass "free space" "${AVAIL_GB} GB available under \$HOME"
elif [ "$AVAIL_GB" -ge 15 ]; then
    info "free space" "${AVAIL_GB} GB — enough for one flavor, tight for two, short for all three"
else
    fail "free space" "${AVAIL_GB} GB — need ~25 GB for two flavors and ~35 for all three. Each vendors OpenSSL twice over."
fi
note "lab dir" "$LAB_DIR"
note "repo"    "$REPO_ROOT"

# ------------------------------------------------------------- network -----
printf '\n-- network --\n'
for url in https://github.com/DMTF/spdm-emu.git https://github.com/DMTF/spdm-dump.git; do
    if timeout 20 git ls-remote --heads "$url" >/dev/null 2>&1; then
        pass "reachable" "$url"
    else
        fail "unreachable" "$url — check proxy / DNS"
    fi
done

# ---------------------------------------------------------------- port -----
printf '\n-- port --\n'
PORT="${SPDM_EMU_PORT:-2323}"
LISTENING="$(ss -ltn 2>/dev/null || true)"
if command -v ss >/dev/null 2>&1 && grep -qE "[:.]${PORT}[[:space:]]" <<<"$LISTENING"; then
    fail "port ${PORT}" "already in use — stop the process or set SPDM_EMU_PORT"
else
    pass "port ${PORT}" "free"
fi

# --------------------------------------------------------------- result ----
printf '\n'
if [ "$FAILED" -eq 0 ]; then
    hdr "ready — next: bash harness/build_spdm_emu.sh pqc"
else
    hdr "not ready — fix the FAIL lines above, then re-run this script"
fi
exit "$FAILED"

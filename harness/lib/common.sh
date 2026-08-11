# shellcheck shell=bash
#
# harness/lib/common.sh — shared helpers for every script in harness/.
#
# Source this, do not execute it:
#     . "$(dirname "$0")/lib/common.sh"
#
# What it guarantees to its callers:
#   * REPO_ROOT  — absolute path to this git repo, wherever it was cloned
#   * LAB_DIR    — where heavy upstream source + build trees live (NEVER in git)
#   * strict mode, consistent logging, and a `need` gate for missing tools
#
# Why LAB_DIR is separate from REPO_ROOT:
#   libspdm builds its own OpenSSL from a submodule. That tree is several GB and
#   tens of thousands of small files. On this project's primary host the repo
#   lives on an NTFS drive reached through /mnt/c, where small-file I/O is one to
#   two orders of magnitude slower than native ext4. Keeping the build tree on
#   the Linux filesystem is the difference between a 12-minute and a 90-minute
#   build. It is also simply correct: vendor build trees are not our source.

set -euo pipefail

# ---------------------------------------------------------------- paths -----

# Resolve the repo root from THIS FILE's location, never from the caller's cwd.
# Scripts here cd into build trees; a cwd-relative answer would silently change
# meaning halfway through a script.
_COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$_COMMON_DIR" rev-parse --show-toplevel 2>/dev/null \
             || (cd "${_COMMON_DIR}/../.." && pwd))"
export REPO_ROOT

# Everything heavy goes here. Override with LAB_DIR=... for a scratch build.
LAB_DIR="${LAB_DIR:-$HOME/spdm-lab}"
export LAB_DIR
WORK_DIR="${LAB_DIR}/work"
export WORK_DIR

# --------------------------------------------------------------- output -----

# Colour only when stdout is a terminal, so redirected logs stay clean.
if [ -t 1 ]; then
    _C_RESET=$'\033[0m'; _C_RED=$'\033[31m'; _C_GRN=$'\033[32m'
    _C_YEL=$'\033[33m'; _C_BLU=$'\033[34m'; _C_DIM=$'\033[2m'
else
    _C_RESET=''; _C_RED=''; _C_GRN=''; _C_YEL=''; _C_BLU=''; _C_DIM=''
fi

log()   { printf '%s[ %s ]%s %s\n' "$_C_BLU" "$(date -u +%H:%M:%S)" "$_C_RESET" "$*"; }
ok()    { printf '%s  ok  %s %s\n' "$_C_GRN" "$_C_RESET" "$*"; }
warn()  { printf '%s warn %s %s\n' "$_C_YEL" "$_C_RESET" "$*" >&2; }
die()   { printf '%s FAIL %s %s\n' "$_C_RED" "$_C_RESET" "$*" >&2; exit 1; }
dim()   { printf '%s%s%s\n' "$_C_DIM" "$*" "$_C_RESET"; }

hdr() {
    printf '\n%s========================================================%s\n' "$_C_BLU" "$_C_RESET"
    printf '%s %s%s\n' "$_C_BLU" "$*" "$_C_RESET"
    printf '%s========================================================%s\n' "$_C_BLU" "$_C_RESET"
}

# Echo a command, then run it. Every build step in this repo is visible.
run() { dim "\$ $*"; "$@"; }

# --------------------------------------------------------------- guards -----

need() {
    local missing=0 t
    for t in "$@"; do
        command -v "$t" >/dev/null 2>&1 || { warn "missing required tool: $t"; missing=1; }
    done
    [ "$missing" -eq 0 ] || die "install the tools above and re-run (see RUNBOOK.md §2)"
}

# Number of parallel jobs; overridable so a laptop sharing RAM with another
# build can dial it down (JOBS=4 ./harness/build_spdm_emu.sh pqc).
jobs_default() {
    local n; n="$(nproc 2>/dev/null || echo 4)"
    echo "${JOBS:-$n}"
}

# ------------------------------------------------------------- flavors ------
#
# Two build flavors. See docs/decisions/0001-two-build-flavors.md for why this
# project carries both.
#
# What is pinned is the SPDM-EMU tag, and libspdm follows that tag's submodule
# pointer. This is the opposite of the obvious approach — pin libspdm, take
# whatever spdm-emu is current — and the obvious approach does not build.
#
# Upstream releases the two together, and the tags correspond exactly:
#
#     spdm-emu 3.7.0     -> libspdm 3.7.0      (2025-04-03)
#     spdm-emu 3.8.0     -> libspdm 3.8.0      (2025-07-10)
#     spdm-emu 4.0.0-rc  -> libspdm 4.0.0-rc   (2026-08-04)
#
# Checking out libspdm 3.8.2 underneath a current spdm-emu fails to compile:
# libspdm changed the signature of libspdm_vendor_send_request_receive_response
# between 3.8.x and 4.0.0-rc, and spdm-emu's PCI DOE requester library calls the
# new one. Verified 2026-08-11; see LOG.md. Pinning the pair upstream tests
# together is both more likely to build and more honest about what was run.

flavor_emu_ref() {
    case "$1" in
        stable) echo "3.8.0"   ;;   # released pair; the baseline for every table
        pqc)    echo "4.0.0-rc";;   # 2026-08-04 RC; the only pair with ML-DSA/ML-KEM
        *)      die "unknown flavor '$1' (expected: stable | pqc)" ;;
    esac
}

flavor_dir()      { echo "${WORK_DIR}/spdm-emu-$1"; }
flavor_bin()      { echo "$(flavor_dir "$1")/build/bin"; }
flavor_pin()      { echo "$(flavor_dir "$1")/BUILD_PIN.txt"; }

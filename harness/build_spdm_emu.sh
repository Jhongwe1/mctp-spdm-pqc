#!/usr/bin/env bash
#
# harness/build_spdm_emu.sh — build one flavor of DMTF spdm-emu + libspdm.
#
#   ./harness/build_spdm_emu.sh pqc        # libspdm 4.0.0-rc  (ML-DSA / ML-KEM)
#   ./harness/build_spdm_emu.sh stable     # libspdm 3.8.2     (baseline)
#   ./harness/build_spdm_emu.sh pqc --force        # wipe and rebuild
#   JOBS=4 ./harness/build_spdm_emu.sh pqc         # cap parallelism
#   LAB_DIR=/tmp/lab ./harness/build_spdm_emu.sh pqc
#
# Idempotent: safe to re-run. It only re-clones when the tree is missing.
#
# Three things here are load-bearing and are the usual reasons a first build
# fails. They are marked TRAP in the code:
#
#   TRAP 1  --recurse-submodules on the clone. spdm-emu carries libspdm and
#           SPDM-Responder-Validator as submodules; without them cmake cannot
#           find libspdm and the error message does not say why.
#   TRAP 2  `make copy_sample_key` must run BEFORE `make`. It generates the
#           sample certificates and keys into the build tree. Run it after and
#           the responder starts, then dies looking for certificates.
#   TRAP 3  -DCRYPTO=openssl. The mbedtls backend compiles fine and then simply
#           has no ML-DSA / ML-KEM / SLH-DSA. You would not find out until you
#           try to use --pqc_asym, weeks later.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

FLAVOR="${1:-}"
shift || true
FORCE=0
LIBSPDM_REF_OVERRIDE=""
EMU_REF_OVERRIDE=""
SEED_FROM=""

while [ $# -gt 0 ]; do
    case "$1" in
        --force)        FORCE=1 ;;
        --emu-ref)      EMU_REF_OVERRIDE="${2:?--emu-ref needs a value}"; shift ;;
        --libspdm-ref)  LIBSPDM_REF_OVERRIDE="${2:?--libspdm-ref needs a value}"; shift ;;
        --seed-from)    SEED_FROM="${2:?--seed-from needs a flavor}"; shift ;;
        *)              die "unknown option: $1" ;;
    esac
    shift
done

[ -n "$FLAVOR" ] || die \
"usage: $0 <stable|pqc> [--force] [--seed-from FLAVOR] [--emu-ref REF] [--libspdm-ref REF]

  --emu-ref REF      pin spdm-emu to REF instead of the flavor default
  --libspdm-ref REF  force libspdm to REF instead of following spdm-emu's
                     submodule pointer. Rarely correct — see the comment in
                     harness/lib/common.sh about why the pair is pinned
                     together — but available for testing a hypothesis."

EMU_REF="${EMU_REF_OVERRIDE:-$(flavor_emu_ref "$FLAVOR")}"
LIBSPDM_REF="${LIBSPDM_REF_OVERRIDE:-}"
SRC="$(flavor_dir "$FLAVOR")"
PIN="$(flavor_pin "$FLAVOR")"
NJOBS="$(jobs_default)"

UPSTREAM_EMU="https://github.com/DMTF/spdm-emu.git"

need git cmake make gcc

hdr "build spdm-emu · flavor=${FLAVOR} · spdm-emu=${EMU_REF} · -j${NJOBS}"
log "repo   : ${REPO_ROOT}"
log "lab    : ${LAB_DIR}   (build tree lives here, never in git)"
log "target : ${SRC}"

mkdir -p "$WORK_DIR" "${LAB_DIR}/logs"

if [ "$FORCE" -eq 1 ] && [ -d "$SRC" ]; then
    log "--force given, removing ${SRC}"
    rm -rf "$SRC"
fi

# ------------------------------------------------------------- 1. clone -----
#
# A note on how big this is, because it looks like a hang the first time.
# spdm-emu carries libspdm as a submodule, and separately carries
# SPDM-Responder-Validator, which carries its OWN copy of libspdm. libspdm in
# turn vendors OpenSSL, and OpenSSL vendors its test tooling (tlsfuzzer,
# tlslite-ng, pyca-cryptography, python-ecdsa). Net effect: a fresh clone pulls
# OpenSSL twice plus several test repositories, several GB in total, and spends
# a long while printing "Cloning into ..." lines. That is expected.
#
# --seed-from <flavor> avoids paying it twice. The two flavors differ only in
# which libspdm tag is checked out, so the second build can copy the first
# tree and re-point the submodule. Same result, no second download.
if [ ! -d "${SRC}/.git" ]; then
    if [ -n "$SEED_FROM" ]; then
        SEED_DIR="$(flavor_dir "$SEED_FROM")"
        [ -d "${SEED_DIR}/.git" ] || die "--seed-from ${SEED_FROM}: no tree at ${SEED_DIR}"
        log "seeding from ${SEED_FROM} (copying source tree, no network)"
        mkdir -p "$SRC"
        # Copy everything except the other flavor's build/ directory — that is
        # several GB of object files that are about to be regenerated anyway.
        shopt -s dotglob
        for _entry in "$SEED_DIR"/*; do
            [ -e "$_entry" ] || continue
            [ "$(basename "$_entry")" = "build" ] && continue
            cp -a "$_entry" "${SRC}/"
        done
        shopt -u dotglob
    else
        log "cloning spdm-emu with submodules (TRAP 1) — several GB, be patient"
        run git clone --recurse-submodules "$UPSTREAM_EMU" "$SRC"
    fi
else
    ok "source tree already present, reusing it (pass --force to start clean)"
fi

cd "$SRC" || die "cannot enter source tree ${SRC}"

# --------------------------------------------------- 2. pin the version ------
# Pin spdm-emu to a tag, then let its submodule pointer decide libspdm. Upstream
# releases and tests the two together; forcing a mismatched pair is how the
# stable build failed on 2026-08-11 (see LOG.md).
log "pinning spdm-emu to ${EMU_REF}"
run git fetch --tags --force origin
run git checkout --detach "$EMU_REF"
run git submodule update --init --recursive

if [ -n "$LIBSPDM_REF" ]; then
    warn "forcing libspdm to ${LIBSPDM_REF}, overriding spdm-emu ${EMU_REF}'s pointer"
    warn "this pair is not one upstream tests together; expect API mismatches"
    run git -C libspdm fetch --tags --force origin
    run git -C libspdm checkout --detach "$LIBSPDM_REF"
    run git -C libspdm submodule update --init --recursive
fi
ok "libspdm at $(git -C libspdm describe --tags --always 2>/dev/null || echo unknown)"

# ------------------------------------------------------- 3. version pin ------
# BUILD_PIN.txt is the provenance root. Every table caption in this project
# quotes these hashes; harness/lib/provenance.sh copies them into each run's
# manifest.json automatically.
LIBSPDM_VERSION="$(tr -d '\r\n' < libspdm/VERSION.md 2>/dev/null || echo unknown)"
{
    echo "flavor=${FLAVOR}"
    echo "spdm-emu=$(git rev-parse HEAD)"
    echo "spdm-emu-short=$(git rev-parse --short HEAD)"
    echo "spdm-emu-ref=${EMU_REF}"
    echo "libspdm=$(git -C libspdm rev-parse HEAD)"
    echo "libspdm-short=$(git -C libspdm rev-parse --short HEAD)"
    echo "libspdm-ref=$(git -C libspdm describe --tags --always 2>/dev/null || echo unknown)"
    echo "libspdm-pinned-by=$([ -n "$LIBSPDM_REF" ] && echo override || echo "spdm-emu submodule pointer")"
    echo "libspdm-version=${LIBSPDM_VERSION}"
    echo "crypto=openssl"
    echo "arch=x64"
    echo "target=Release"
    echo "toolchain=GCC"
    echo "cc=$(gcc -dumpfullversion -dumpversion 2>/dev/null | head -1)"
    echo "cmake=$(cmake --version | head -1 | awk '{print $3}')"
    echo "host=$(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || uname -sr)"
    echo "kernel=$(uname -r)"
    echo "built-at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$PIN"
ok "wrote $(realpath --relative-to="$LAB_DIR" "$PIN" 2>/dev/null || echo "$PIN")"
dim "$(sed 's/^/      /' "$PIN")"

# ------------------------------------------------------------- 4. build -----
BUILD_LOG="${LAB_DIR}/logs/build-${FLAVOR}-$(date -u +%Y%m%dT%H%M%SZ).log"
mkdir -p build && cd build || die "cannot enter ${SRC}/build"

log "cmake configure (TRAP 3: CRYPTO must be openssl, not mbedtls)"
run cmake -DARCH=x64 -DTOOLCHAIN=GCC -DTARGET=Release -DCRYPTO=openssl .. >>"$BUILD_LOG" 2>&1 \
    || { tail -40 "$BUILD_LOG" >&2; die "cmake configure failed — full log: $BUILD_LOG"; }
ok "cmake configured"

log "make copy_sample_key (TRAP 2: must precede make)"
run make copy_sample_key >>"$BUILD_LOG" 2>&1 \
    || { tail -40 "$BUILD_LOG" >&2; die "copy_sample_key failed — full log: $BUILD_LOG"; }
ok "sample keys generated"

log "make -j${NJOBS}  (libspdm builds its own OpenSSL; expect 10-25 min the first time)"
log "tailing progress to: ${BUILD_LOG}"
if ! make -j"$NJOBS" >>"$BUILD_LOG" 2>&1; then
    tail -60 "$BUILD_LOG" >&2
    die "build failed — full log: $BUILD_LOG"
fi
ok "build complete"

# ------------------------------------------------------------ 5. verify -----
hdr "verify"
BIN="$(flavor_bin "$FLAVOR")"
for b in spdm_requester_emu spdm_responder_emu; do
    [ -x "${BIN}/${b}" ] || die "expected binary missing: ${BIN}/${b}"
    ok "binary present: ${b}"
done

# The single fact that decides whether the PQC half of this project is possible.
if "${BIN}/spdm_requester_emu" --help 2>&1 | grep -qE '\-\-pqc_asym'; then
    ok "--pqc_asym present  -> PQC experiments are possible with this build"
else
    warn "--pqc_asym ABSENT  -> this build cannot run PQC (expected for flavor=stable)"
fi

# The file W04 has to modify. Confirm it exists before depending on it.
MEAS="libspdm/os_stub/spdm_device_secret_lib_sample/meas.c"
if [ -f "${SRC}/${MEAS}" ]; then
    ok "$(basename "$MEAS") present ($(stat -c%s "${SRC}/${MEAS}") bytes) -> W04 target exists"
else
    warn "${MEAS} not found — W04's plan assumes this path; re-check upstream layout"
fi

hdr "done · flavor=${FLAVOR}"
echo "  binaries : ${BIN}"
echo "  pin      : ${PIN}"
echo "  log      : ${BUILD_LOG}"
echo
echo "  next     : ./harness/healthcheck.sh ${FLAVOR}"

#!/usr/bin/env bash
#
# harness/build_spdm_emu.sh — build one flavor of DMTF spdm-emu + libspdm.
#
#   bash harness/build_spdm_emu.sh pqc     # spdm-emu 4.0.0-rc -> libspdm 4.0.0-rc
#   bash harness/build_spdm_emu.sh stable  # spdm-emu 3.8.0    -> libspdm 3.8.0
#   bash harness/build_spdm_emu.sh pqc --force        # wipe and rebuild
#   JOBS=4 bash harness/build_spdm_emu.sh pqc         # cap parallelism
#   LAB_DIR=/tmp/lab bash harness/build_spdm_emu.sh pqc
#
#   bash harness/build_spdm_emu.sh pqc-dts --seed-from pqc   # the third flavor
#   bash harness/build_spdm_emu.sh pqc --pin-only            # rewrite the pin only
#
# --pin-only exists because BUILD_PIN.txt is the provenance root and it can be
# WRONG WITHOUT BEING STALE. On 2026-09-14 two fields were found missing from
# every pin this project had ever written: the vendored OpenSSL that computes
# every signature, and the compiler flags a flavor is defined by. Backfilling
# them by rebuilding would have replaced the binaries that produced the
# published captures, so --pin-only reads the tree as it stands, writes the pin,
# and touches nothing else. It does not fetch, check out, patch or compile.
#
# Invoked as `bash harness/...`, never `./harness/...`: the working tree is
# often on NTFS, which does not carry the executable bit, and core.filemode is
# off so git records these as 100644. See docs/decisions/0002.
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
PIN_ONLY=0
LIBSPDM_REF_OVERRIDE=""
EMU_REF_OVERRIDE=""
SEED_FROM=""

while [ $# -gt 0 ]; do
    case "$1" in
        --force)        FORCE=1 ;;
        --pin-only)     PIN_ONLY=1 ;;
        --emu-ref)      EMU_REF_OVERRIDE="${2:?--emu-ref needs a value}"; shift ;;
        --libspdm-ref)  LIBSPDM_REF_OVERRIDE="${2:?--libspdm-ref needs a value}"; shift ;;
        --seed-from)    SEED_FROM="${2:?--seed-from needs a flavor}"; shift ;;
        *)              die "unknown option: $1" ;;
    esac
    shift
done

[ -n "$FLAVOR" ] || die \
"usage: $0 <stable|pqc|pqc-dts> [--force] [--pin-only] [--seed-from FLAVOR]
          [--emu-ref REF] [--libspdm-ref REF]

  --pin-only         rewrite BUILD_PIN.txt from the tree as it stands, and do
                     nothing else: no fetch, no checkout, no patch, no compile
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
CFLAGS_EXTRA="$(flavor_cflags "$FLAVOR")"
FLAVOR_PATCH="$(flavor_patch "$FLAVOR")"

UPSTREAM_EMU="https://github.com/DMTF/spdm-emu.git"

need git cmake make gcc

# ------------------------------------------------------------- the pin -------
#
# BUILD_PIN.txt is the provenance root. Every table caption in this project
# quotes these hashes; harness/lib/provenance.sh copies them into each run's
# manifest.json automatically.
#
# Written by a function so --pin-only can reach it without the build. Run from
# inside $SRC.
write_pin() {
    local libspdm_version ossl
    libspdm_version="$(tr -d '\r\n' < libspdm/VERSION.md 2>/dev/null || echo unknown)"
    ossl="libspdm/os_stub/openssllib/openssl"
    {
        echo "flavor=${FLAVOR}"
        echo "spdm-emu=$(git rev-parse HEAD)"
        echo "spdm-emu-short=$(git rev-parse --short HEAD)"
        echo "spdm-emu-ref=${EMU_REF}"
        echo "libspdm=$(git -C libspdm rev-parse HEAD)"
        echo "libspdm-short=$(git -C libspdm rev-parse --short HEAD)"
        echo "libspdm-ref=$(git -C libspdm describe --tags --always 2>/dev/null || echo unknown)"
        echo "libspdm-pinned-by=$([ -n "$LIBSPDM_REF" ] && echo override || echo "spdm-emu submodule pointer")"
        echo "libspdm-version=${libspdm_version}"
        echo "crypto=openssl"
        # ★ WHICH openssl. Not the system `openssl` binary — libspdm builds and
        # statically links its own from a submodule, and on this host the two
        # are 3.0.13 and 3.5.5. ML-DSA, ML-KEM and SLH-DSA arrived in OpenSSL
        # 3.5, so the vendored version is the reason the post-quantum arms run
        # at all, and a reader who took the system one for the backend would
        # conclude the captures are impossible. Absent from every pin this
        # project wrote before 2026-09-14.
        if [ -d "$ossl" ]; then
            echo "crypto-openssl-vendored=$(git -C "$ossl" rev-parse HEAD 2>/dev/null || echo unknown)"
            echo "crypto-openssl-version=$(awk -F= '
                /^MAJOR=/{a=$2} /^MINOR=/{b=$2} /^PATCH=/{c=$2}
                END {print (a == "" ? "unknown" : a"."b"."c)}' "${ossl}/VERSION.dat" 2>/dev/null)"
        else
            echo "crypto-openssl-vendored=absent"
        fi
        echo "arch=x64"
        echo "target=Release"
        echo "toolchain=GCC"
        # What makes this flavor this flavor, beyond the commit. Empty for the
        # two flavors that are plain upstream builds.
        echo "cflags=${CFLAGS_EXTRA}"
        if [ -n "$FLAVOR_PATCH" ]; then
            echo "flavor-patch=${FLAVOR_PATCH}"
            echo "flavor-patch-sha256=$(sha256sum "${REPO_ROOT}/${FLAVOR_PATCH}" 2>/dev/null | cut -d' ' -f1)"
        fi
        echo "cc=$(gcc -dumpfullversion -dumpversion 2>/dev/null | head -1)"
        echo "cmake=$(cmake --version | head -1 | awk '{print $3}')"
        echo "host=$(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || uname -sr)"
        echo "kernel=$(uname -r)"
        echo "built-at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } > "$PIN"
}

if [ "$PIN_ONLY" -eq 1 ]; then
    hdr "rewrite the pin only  ·  flavor=${FLAVOR}"
    [ -d "${SRC}/.git" ] || die "no tree at ${SRC} — nothing to describe"
    cd "$SRC" || die "cannot enter ${SRC}"
    # built-at would otherwise be overwritten with today, which would claim the
    # binaries were compiled now. Carried forward from the pin being replaced.
    #
    # `|| true` is load-bearing. On a flavor with no pin yet, sed exits 2, and
    # lib/common.sh has set -e with set -o pipefail, so the pipeline's status
    # kills the script mid-assignment with nothing printed. That is exactly what
    # it did on 2026-09-14 for the one flavor that had no pin — the only flavor
    # this option existed to give one to.
    PREV_BUILT_AT="$(sed -n 's/^built-at=//p' "$PIN" 2>/dev/null | head -1 || true)"
    write_pin
    if [ -n "$PREV_BUILT_AT" ]; then
        sed -i "s|^built-at=.*|built-at=${PREV_BUILT_AT}|" "$PIN"
        dim "    built-at kept at ${PREV_BUILT_AT} — the binaries were not recompiled"
    fi
    ok "wrote ${PIN}"
    dim "$(sed 's/^/      /' "$PIN")"
    exit 0
fi

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
# which spdm-emu tag is checked out — libspdm follows that tag's submodule
# pointer — so the second build can copy the first tree and re-point the
# submodule. Same result, no second download.
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

# ------------------------------------------------- 3. the flavor's patch ------
#
# A flavor may be defined by more than a commit. pqc-dts is the pqc pair plus
# transport/data-transfer-size.patch, which adds a --data_transfer_size flag so
# one build can sweep the parameter instead of one build per point.
#
# ★ Applied here rather than by harness/apply_device_patch.sh because the two
# are different kinds of thing. The device patch is an OVERLAY that any flavor
# may or may not carry, and it is reversible on a live tree. A flavor patch is
# part of what the flavor IS: a tree without it is not this flavor, and the pin
# says so. ADR 0009.
if [ -n "$FLAVOR_PATCH" ]; then
    log "applying ${FLAVOR_PATCH} (this flavor is defined by it)"
    [ -f "${REPO_ROOT}/${FLAVOR_PATCH}" ] \
        || die "flavor '${FLAVOR}' needs ${FLAVOR_PATCH} and this checkout has no such file"
    if git apply --check --reverse "${REPO_ROOT}/${FLAVOR_PATCH}" 2>/dev/null; then
        ok "already applied"
    else
        run git apply --check "${REPO_ROOT}/${FLAVOR_PATCH}" \
            || die "git apply refused ${FLAVOR_PATCH} against spdm-emu ${EMU_REF}.
  Upstream has moved under it. Re-make the patch before trusting a build:
  a patch whose context survived a revision that changed what it means is the
  interesting failure, and --check cannot see it."
        run git apply "${REPO_ROOT}/${FLAVOR_PATCH}"
        ok "applied"
    fi
    git diff --stat | sed 's/^/      /'
fi

# ------------------------------------------------------- 4. version pin ------
write_pin
ok "wrote $(realpath --relative-to="$LAB_DIR" "$PIN" 2>/dev/null || echo "$PIN")"
dim "$(sed 's/^/      /' "$PIN")"

# ------------------------------------------------------------- 5. build -----
BUILD_LOG="${LAB_DIR}/logs/build-${FLAVOR}-$(date -u +%Y%m%dT%H%M%SZ).log"
mkdir -p build && cd build || die "cannot enter ${SRC}/build"

CMAKE_ARGS=(-DARCH=x64 -DTOOLCHAIN=GCC -DTARGET=Release -DCRYPTO=openssl)
if [ -n "$CFLAGS_EXTRA" ]; then
    # spdm-emu and libspdm both set only CMAKE_C_FLAGS_<CONFIG> on the GCC
    # path, so a base CMAKE_C_FLAGS survives; libspdm appends to it rather than
    # replacing it. Verified against the CMakeLists at this commit before
    # relying on it — the buffer sizes are #ifndef-guarded in spdm_emu.h and a
    # -D that quietly failed to reach the compiler would leave the whole sweep
    # measuring one DataTransferSize six times.
    CMAKE_ARGS+=(-DCMAKE_C_FLAGS="$CFLAGS_EXTRA")
    log "flavor cflags: ${CFLAGS_EXTRA}"
fi

log "cmake configure (TRAP 3: CRYPTO must be openssl, not mbedtls)"
run cmake "${CMAKE_ARGS[@]}" .. >>"$BUILD_LOG" 2>&1 \
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

# ------------------------------------------------------------ 6. verify -----
hdr "verify"
BIN="$(flavor_bin "$FLAVOR")"
for b in spdm_requester_emu spdm_responder_emu; do
    [ -x "${BIN}/${b}" ] || die "expected binary missing: ${BIN}/${b}"
    ok "binary present: ${b}"
done

# The single fact that decides whether the PQC half of this project is possible.
EMU_HELP="$("${BIN}/spdm_requester_emu" --help 2>&1 || true)"
if grep -qE '\-\-pqc_asym' <<<"$EMU_HELP"; then
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
echo "  next     : bash harness/healthcheck.sh ${FLAVOR}"

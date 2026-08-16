#!/usr/bin/env bash
#
# harness/build_spdm_dump.sh — build DMTF spdm-dump, the offline capture decoder.
#
#   bash harness/build_spdm_dump.sh
#   JOBS=3 bash harness/build_spdm_dump.sh
#
# Needed from W02 onward: spdm-dump is what turns a .pcap into a field-by-field
# decode of each SPDM message. Building it in W01 means the week that needs it
# does not open with a build problem.
#
# Cost warning: spdm-dump vendors its own libspdm, which vendors OpenSSL. This
# is another multi-GB clone. It is slow, not stuck.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

SRC="${WORK_DIR}/spdm-dump"
NJOBS="$(jobs_default)"
UPSTREAM="https://github.com/DMTF/spdm-dump.git"

need git cmake make gcc

hdr "build spdm-dump  ·  -j${NJOBS}"

mkdir -p "$WORK_DIR" "${LAB_DIR}/logs"

if [ ! -d "${SRC}/.git" ]; then
    log "cloning spdm-dump with submodules (multi-GB, be patient)"
    run git clone --recurse-submodules "$UPSTREAM" "$SRC"
else
    ok "source tree already present"
fi

cd "$SRC" || die "cannot enter source tree ${SRC}"

{
    echo "tool=spdm-dump"
    echo "spdm-dump=$(git rev-parse HEAD)"
    echo "spdm-dump-short=$(git rev-parse --short HEAD)"
    echo "libspdm=$(git -C libspdm rev-parse HEAD 2>/dev/null || echo unknown)"
    echo "libspdm-version=$(tr -d '\r\n' < libspdm/VERSION.md 2>/dev/null || echo unknown)"
    echo "built-at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > BUILD_PIN.txt
ok "wrote BUILD_PIN.txt"

BUILD_LOG="${LAB_DIR}/logs/build-spdm-dump-$(date -u +%Y%m%dT%H%M%SZ).log"
mkdir -p build && cd build || die "cannot enter ${SRC}/build"

log "cmake configure"
run cmake -DARCH=x64 -DTOOLCHAIN=GCC -DTARGET=Release -DCRYPTO=openssl .. >>"$BUILD_LOG" 2>&1 \
    || { tail -40 "$BUILD_LOG" >&2; die "cmake failed — log: $BUILD_LOG"; }

log "make -j${NJOBS}"
make -j"$NJOBS" >>"$BUILD_LOG" 2>&1 \
    || { tail -60 "$BUILD_LOG" >&2; die "build failed — log: $BUILD_LOG"; }

[ -x "${SRC}/build/bin/spdm_dump" ] || die "spdm_dump binary not produced"
ok "spdm_dump built: ${SRC}/build/bin/spdm_dump"

# ── measure the decoder's certificate-chain ceiling ─────────────────────────
#
# spdm_dump gives up partway through a post-quantum capture with "cert_chain is
# too larger. Please increase LIBSPDM_MAX_CERT_CHAIN_SIZE and rebuild." Whether
# that is a hard limit of the tool or a property of how it was configured
# decides whether the post-quantum half of this project can be decoded at all,
# so it is measured rather than assumed — and measured from outside the binary,
# without patching or rebuilding it.
#
# The lever: spdm_dump.c checks the SIZE of a --rsp_cert_chain file against the
# macro before it parses anything. Feeding it files of known size brackets the
# constant. In libspdm 4.0.0-rc the macro can only be one of three values, and
# which one says whether post-quantum signature support was compiled in:
#
#     0x1000   =   4096   no PQC signature support
#     0x8000   =  32768   ML-DSA support
#     0x28000  = 163840   SLH-DSA support
#
# A measured 4096 next to a 16,853-byte ML-DSA chain is the difference between
# "the decoder cannot read this" and "this build of the decoder cannot, and the
# configuration that can is named above".
probe_limit() {
    local bin="${SRC}/build/bin/spdm_dump" tmp lo=1 hi=$((1 << 20))
    tmp="$(mktemp -d)"
    probe() {   # probe <size> — true when the decoder rejects a file that big
        head -c "$1" /dev/zero > "${tmp}/c.bin"
        # No capture is needed: the size check happens during argument parsing.
        "$bin" --rsp_cert_chain "${tmp}/c.bin" 2>&1 | grep -q 'too larger'
    }
    if ! probe "$hi"; then rm -rf "$tmp"; echo "unbounded"; return; fi
    while [ $((hi - lo)) -gt 1 ]; do
        local mid=$(((lo + hi) / 2))
        if probe "$mid"; then hi="$mid"; else lo="$mid"; fi
    done
    rm -rf "$tmp"
    printf '0x%x' "$lo"
}

LIMIT="$(probe_limit)"
{
    echo "# max-cert-chain-size is MEASURED, not read from a header: spdm_dump"
    echo "# rejects a --rsp_cert_chain file larger than LIBSPDM_MAX_CERT_CHAIN_SIZE"
    echo "# before parsing it, so a bisection on file size reads the constant out"
    echo "# of the compiled binary. See the comment in harness/build_spdm_dump.sh."
    echo "max-cert-chain-size=${LIMIT}"
    echo "max-cert-chain-size-measured-at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} >> "${SRC}/BUILD_PIN.txt"      # absolute: cwd is ${SRC}/build by this point
ok "decoder certificate-chain ceiling: ${LIMIT}"

hdr "done"
echo "  binary : ${SRC}/build/bin/spdm_dump"
echo "  log    : ${BUILD_LOG}"
echo
echo "  try it : ${SRC}/build/bin/spdm_dump -r <some>.pcap"

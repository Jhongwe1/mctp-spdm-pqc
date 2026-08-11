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

hdr "done"
echo "  binary : ${SRC}/build/bin/spdm_dump"
echo "  log    : ${BUILD_LOG}"
echo
echo "  try it : ${SRC}/build/bin/spdm_dump -r <some>.pcap"

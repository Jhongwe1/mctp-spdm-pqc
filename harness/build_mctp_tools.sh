#!/usr/bin/env bash
#
# harness/build_mctp_tools.sh — the userspace half of Linux MCTP.
#
#     bash harness/build_mctp_tools.sh
#
# The kernel gives you AF_MCTP and a netdev. It does not give you a way to
# bring that netdev up, give it an endpoint ID, or add a route — iproute2 does
# not speak MCTP, and those operations are rtnetlink messages on AF_MCTP that
# somebody has to send. CodeConstruct's `mctp` is the tool that sends them, and
# it is the same tool OpenBMC machines carry, which is the reason to use it
# rather than to write the netlink by hand: the configuration in
# harness/run_afmctp.sh is then the configuration a BMC would actually have.
#
# What gets built and what is used
# --------------------------------
#   mctp     the CLI. Used: `link serial`, `link set`, `address add`,
#            `route add`, `link show`.
#   mctpd    the daemon that assigns EIDs over the MCTP control protocol.
#            Built and NOT used — see below.
#
# ★ mctpd is deliberately not used, and that is worth stating rather than
# leaving as an absence. Its job is discovery: walking a bus, assigning EIDs,
# publishing endpoints on D-Bus. This experiment assigns both EIDs statically,
# because what is being measured is packetisation, and a discovery protocol in
# the middle would put its own traffic on the link being counted. So the EIDs
# here are real EIDs on a real network and they were not negotiated, and
# docs/transports.md says so in the column where it would otherwise claim more
# than it did.
#
# Exit codes: 0 built (or already built) · 2 a prerequisite is missing

set -uo pipefail
_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "${_HERE}/lib/common.sh"

REF="${MCTP_REF:-v2.6}"
W9="${LAB_DIR}/w9"
SRC="${W9}/mctp"
PIN="${REPO_ROOT}/third_party/mctp-tools.pin"

hdr "CodeConstruct mctp tools (${REF})"
need git meson ninja pkg-config gcc

if [ -x "${SRC}/obj/mctp" ] && [ -f "$PIN" ] && [ -z "${FORCE:-}" ]; then
    ok "already built: ${SRC}/obj/mctp"
    exit 0
fi

mkdir -p "$W9" "${W9}/logs"
if [ ! -d "$SRC" ]; then
    run git clone -q https://github.com/CodeConstruct/mctp.git "$SRC"
fi
cd "$SRC" || die "no source tree"
run git fetch -q --tags origin

# ★ Pinned to a tag, then the exact commit is recorded. A tag can move; the
# commit cannot, and third_party/*.pin is the single source of truth for what
# version a result came from.
if ! git checkout -q "$REF" 2>/dev/null; then
    warn "ref '${REF}' not found; staying on the default branch"
fi
COMMIT="$(git rev-parse HEAD)"
DESCRIBE="$(git describe --tags --always 2>/dev/null || echo unknown)"

log "meson setup"
rm -rf obj
run meson setup obj -Dtests=false > "${W9}/logs/mctp-setup.log" 2>&1 \
    || { tail -20 "${W9}/logs/mctp-setup.log" >&2; die "meson setup failed"; }
log "ninja"
run ninja -C obj > "${W9}/logs/mctp-build.log" 2>&1 \
    || { tail -20 "${W9}/logs/mctp-build.log" >&2; die "build failed"; }

[ -x obj/mctp ] || die "obj/mctp was not produced"
ok "$(./obj/mctp 2>&1 | head -1 || true)"

mkdir -p "$(dirname "$PIN")"
cat > "$PIN" <<PINEOF
# third_party/mctp-tools.pin — the userspace side of Linux MCTP.
#
# Written by harness/build_mctp_tools.sh. Do not edit by hand.
#
# Only the CLI is used. mctpd is built and not run: it does EID assignment by
# the MCTP control protocol, and this experiment assigns EIDs statically so
# that nothing but SPDM is on the link being counted.
repo=https://github.com/CodeConstruct/mctp.git
ref=${REF}
commit=${COMMIT}
describe=${DESCRIBE}
mctp_sha256=$(sha256sum obj/mctp | cut -d' ' -f1)
built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
cc=$(gcc -dumpfullversion -dumpversion 2>/dev/null || echo unknown)
meson=$(meson --version 2>/dev/null || echo unknown)
PINEOF
ok "pin written: third_party/mctp-tools.pin"

#!/usr/bin/env bash
#
# certs/stage_chain.sh — put this project's own chain where the emulator will
# find it, without touching the pinned build tree.
#
#     bash certs/stage_chain.sh pqc          # prints the directory to run from
#
# Why a sandbox rather than overwriting the build tree
# ----------------------------------------------------
# libspdm's sample device-secret library opens its certificates by RELATIVE
# path — "ecp384/bundle_responder.certchain.der", chosen from the negotiated
# algorithm in read_pub_cert.c — so which certificates an emulator uses is
# decided entirely by the directory it is run from. Overwriting the files under
# build/bin would work and would also mean that every later run of
# harness/healthcheck.sh, every re-run of the baseline arms, and the clean-clone
# reproduction in RUNBOOK §10 silently measured this chain instead of the
# upstream one, with nothing recording that they had.
#
# So the build tree stays exactly as build_spdm_emu.sh reconstructed it from
# third_party/*.pin, and a sandbox directory of symlinks is built beside it.
# One real directory in it: ecp384, holding this project's chain.
#
# What is replaced, and what deliberately is not
# ----------------------------------------------
# Nine files: the root and intermediate certificates, both leaves, both private
# keys, and the two bundles. Everything else in ecp384/ — the slot-1 and slot-4
# chains, the alias-model variants, the EKU variants — is copied from upstream
# unchanged, because a run that changed more than one thing could not attribute
# its own failure. Those chains still descend from DMTF's root, which is the
# reason the arm that uses this sandbox runs with --slot_count 1: with one slot
# populated, the only certificates on the wire are ours.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../harness/lib/common.sh
. "${HERE}/../harness/lib/common.sh"

FLAVOR="${1:-pqc}"
SRC_BIN="$(flavor_bin "$FLAVOR")"
DEST="${WORK_DIR}/selfsigned-${FLAVOR}"
CHAIN="${HERE}/out"

[ -d "$SRC_BIN" ] || die "no build for flavor '${FLAVOR}' — bash harness/build_spdm_emu.sh ${FLAVOR}"
[ -f "${CHAIN}/bundle_responder.certchain.der" ] \
    || die "no chain in certs/out — bash certs/gen_chain.sh"

# The private keys are not committed, so a fresh clone reaches this line with
# certificates but no keys. Say which, rather than letting the responder fail
# later with a message about a certificate.
for k in end_responder.key end_requester.key; do
    [ -f "${CHAIN}/${k}" ] || die "certs/out/${k} is missing.
  Private keys are not committed (.gitignore excludes *.key). To take a NEW
  capture you must generate a chain of your own:

      bash certs/gen_chain.sh --force

  which produces different certificates from the committed ones, so its byte
  counts will differ from the ones this repository publishes. See RUNBOOK §11."
done

rm -rf "$DEST"
mkdir -p "${DEST}/ecp384"

# Symlink everything, then make ecp384 the one real directory.
for entry in "${SRC_BIN}"/*; do
    name="$(basename "$entry")"
    [ "$name" = "ecp384" ] && continue
    ln -s "$entry" "${DEST}/${name}"
done
cp -a "${SRC_BIN}/ecp384/." "${DEST}/ecp384/"

for f in ca.cert ca.cert.der \
         inter.cert inter.cert.der \
         end_responder.cert end_responder.cert.der end_responder.key \
         end_requester.cert end_requester.cert.der end_requester.key \
         bundle_responder.certchain.der bundle_requester.certchain.der; do
    cp -f "${CHAIN}/${f}" "${DEST}/ecp384/${f}"
done
chmod 0600 "${DEST}/ecp384/"*.key

printf '%s\n' "$DEST"

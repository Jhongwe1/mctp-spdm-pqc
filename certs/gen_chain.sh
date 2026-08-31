#!/usr/bin/env bash
#
# certs/gen_chain.sh — build this project's own three-layer certificate chain.
#
#     bash certs/gen_chain.sh            # refuses if certs/out/ already exists
#     bash certs/gen_chain.sh --force    # regenerate, invalidating published numbers
#
# Why a chain of our own, when `make copy_sample_key` already produced one
# -----------------------------------------------------------------------
# Two reasons, and the second is the one that matters.
#
# The first is that "I signed this" and "I used the sample" are different
# claims. The second is that Gate 2's third tamper point is *modify the
# intermediate certificate and require the handshake to fail*, and that is only
# possible for someone who holds the intermediate's private key. Using DMTF's
# sample chain means the tampering can only ever be a corruption, never a
# forgery, and those two produce different failures.
#
# What "reproducible" means here, and what it does not
# ----------------------------------------------------
# Running this twice produces two different chains. The keys are fresh, and an
# ECDSA signature is DER-encoded as two integers whose length depends on
# whether their top bit happens to be set — so even the byte COUNT of a
# regenerated certificate moves by a byte or two.
#
# That is why certs/out/*.der is committed and this script refuses to overwrite
# it. The certificates are evidence; regenerating them is the certificate
# equivalent of re-stamping a manifest, and docs/decisions/0004 explains why
# this repository does not do that. What is reproducible is the RELATIONSHIP:
# check_chain.py re-derives every structural fact and the wire arithmetic from
# whatever chain is present, and holds for any chain this script produces.
#
# Private keys are not committed. .gitignore excludes *.key, and it excludes
# them here too even though these protect nothing — a habit that only applies
# to important keys is not a habit. The consequence is stated rather than
# worked around: a fresh clone can verify the committed chain and the committed
# captures, but must run this script (getting a different chain) to take a new
# capture of its own. RUNBOOK §8.7 says so where someone will read it.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${HERE}/out"
CNF="${HERE}/openssl.cnf"
CURVE="secp384r1"          # matches the ecp384 directory the emulator selects
DIGEST="-sha384"           # matches the SHA-384 these captures negotiate
DAYS=3650

FORCE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --force)   FORCE=1; shift ;;
        -h|--help) sed -n '3,8p' "$0"; exit 0 ;;
        *) printf 'unknown argument %s\n' "$1" >&2; exit 2 ;;
    esac
done

if [ -e "${OUT}" ] && [ -n "$(ls -A "${OUT}" 2>/dev/null)" ] && [ "$FORCE" -eq 0 ]; then
    cat >&2 <<'MSG'
certs/out/ already holds a chain, and this script will not overwrite it.

Every byte count this repository publishes about that chain — its certificate
sizes, its length on the wire, the RootHash in the captures — is a property of
THOSE certificates. Regenerating produces different keys and therefore
different bytes, and every one of those numbers would silently become false
while still looking checked.

  to inspect what is there   bash certs/check_chain.sh
  to replace it anyway       bash certs/gen_chain.sh --force

After --force, re-run harness/capture.sh and re-point any document that cites
the old chain. Nothing here edits a published number in place.
MSG
    exit 1
fi

command -v openssl >/dev/null 2>&1 || { echo "openssl not found" >&2; exit 1; }

mkdir -p "${OUT}"
cd "${OUT}"

log() { printf '\033[34m[ %s ]\033[0m %s\n' "$(date -u +%H:%M:%S)" "$*"; }

log "openssl: $(openssl version)"
log "curve  : ${CURVE}, digest ${DIGEST#-}"

# ---------------------------------------------------------------- 1. root ---
#
# Self-signed. In production the holder of this key is the silicon vendor or the
# platform owner, the public key or its hash is burned into fuses, and the key
# itself never comes near a production line.

log "root CA"
openssl ecparam -name "${CURVE}" -out param.pem
openssl req -nodes -x509 -days "${DAYS}" -newkey "ec:param.pem" \
    -keyout ca.key -out ca.cert ${DIGEST} -batch -set_serial 1 \
    -config "${CNF}" -extensions v3_root \
    -subj "/O=Chung-Wei Lan SPDM Lab/CN=SPDM Lab ECP384 Root CA"

# -------------------------------------------------------- 2. intermediate ---
#
# Signed by the root. This layer exists so the root key can stay offline: the
# thing that signs device certificates every day is this one, and if it is
# compromised the trust anchor survives.

log "intermediate CA"
openssl req -nodes -newkey "ec:param.pem" -keyout inter.key -out inter.req \
    ${DIGEST} -batch -config "${CNF}" \
    -subj "/O=Chung-Wei Lan SPDM Lab/CN=SPDM Lab ECP384 Intermediate CA"
openssl x509 -req -in inter.req -out inter.cert \
    -CA ca.cert -CAkey ca.key ${DIGEST} -days "${DAYS}" -set_serial 2 \
    -extfile "${CNF}" -extensions v3_inter

# ------------------------------------------------------------- 3. leaves ---
#
# Signed by the intermediate. In production this key is generated inside the
# device and never leaves it; SPDM's CHALLENGE is the proof that the endpoint
# on the other end of the wire holds it.
#
# Two leaves, because the emulator authenticates in both directions. The
# responder validates the requester's chain against ecp384/ca.cert.der — which
# is about to become OUR root — so a run that replaced only the responder's
# chain would fail mutual authentication for a reason that has nothing to do
# with the chain being tested.

leaf() {   # leaf <role> <serial> <extension-section>
    local role="$1" serial="$2" section="$3"
    log "leaf: ${role}"
    openssl req -nodes -newkey "ec:param.pem" \
        -keyout "end_${role}.key" -out "end_${role}.req" \
        ${DIGEST} -batch -config "${CNF}" \
        -subj "/O=Chung-Wei Lan SPDM Lab/CN=SPDM Lab ECP384 ${role} cert"
    openssl x509 -req -in "end_${role}.req" -out "end_${role}.cert" \
        -CA inter.cert -CAkey inter.key ${DIGEST} -days "${DAYS}" \
        -set_serial "${serial}" -extfile "${CNF}" -extensions "${section}"
}

leaf responder 3 v3_leaf_responder
leaf requester 4 v3_leaf_requester

# --------------------------------------------------------------- 4. bundle --
#
# DSP0274 Table 39: the SPDM certificate chain sent on the wire is
#
#     Length (4 bytes, little endian) ‖ RootHash (H bytes) ‖ Certificates
#
# and Certificates is the DER concatenation below, root first. The emulator
# builds the first two fields itself at run time, which is exactly why they are
# worth checking: the RootHash it computes has to equal the digest of the first
# certificate in this file, and nothing here tells it that.

log "DER and bundles"
for f in ca inter end_responder end_requester; do
    openssl x509 -in "${f}.cert" -outform DER -out "${f}.cert.der"
done
cat ca.cert.der inter.cert.der end_responder.cert.der > bundle_responder.certchain.der
cat ca.cert.der inter.cert.der end_requester.cert.der > bundle_requester.certchain.der

# Intermediate artifacts, deleted rather than ignored. .gitignore excludes
# *.key, and an earlier version of this script also wrote end_responder.key.pem
# — which that rule does not match, because it matches the END of a name. A
# private key would have been committed by a rule that looked like it covered
# it. The keys keep exactly one spelling now, and verify_repo.sh greps every
# tracked file for a private-key header rather than trusting the pattern.
rm -f -- *.req param.pem

# ------------------------------------------------------------ 5. check it ---
#
# A generator that can emit a broken chain and say nothing is not a tool. This
# is the same check CI runs, run here so a mistake is found in the second it was
# made rather than in a handshake log twenty minutes later.

log "checking what was just generated"
python3 "${HERE}/check_chain.py" "${OUT}"

printf '\n'
log "done — ${OUT}"
printf '  the private keys are NOT committed (.gitignore *.key); the certificates are.\n'
printf '  next: bash harness/capture.sh --name w3-baseline\n'

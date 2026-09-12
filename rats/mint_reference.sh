#!/usr/bin/env bash
#
# rats/mint_reference.sh — the publisher's side: turn a capture into a signed
# reference value.
#
#     bash rats/mint_reference.sh                       # from the clean capture
#     bash rats/mint_reference.sh --from <decode.txt> --out rats/ref/x.corim
#     bash rats/mint_reference.sh --genkey              # first time only
#
# Who does this in a real system
# ------------------------------
# Not the verifier. RFC 9334 calls this role the **Reference Value Provider**,
# and in a machine full of attested devices it is the firmware vendor: whoever
# built the image knows what its measurement should be, signs a manifest saying
# so, and publishes it. The BMC that later appraises a device has the manifest
# and the vendor's public key, and nothing else.
#
# This project plays both roles, which is the honest limitation to state beside
# the result rather than at the end of it: the reference values here are minted
# from a capture of the very device they will appraise, so they cannot catch a
# device that was compromised before the reference was taken. What they DO
# catch — and what docs/tamper.md row 1 shows nothing else catching — is a
# device that changed after it. See docs/rats-pipeline.md, "who plays what".
#
# The key
# -------
# ES256, P-256, generated here and kept out of git: `.gitignore` excludes
# `*.key` and harness/verify_repo.sh reads every tracked file looking for a PEM
# private-key header rather than trusting the pattern. The PUBLIC half is
# committed, because a verifier needs it and because a signed reference value
# nobody can check is decoration.
#
# Consequence, stated because it will surprise somebody: a fresh clone cannot
# re-mint these reference values, for the same reason certs/ cannot regenerate
# its chain — the private key is not there. It can VERIFY them, which is what
# CI does and what matters. ADR 0005 is the same argument for the certificate
# chain.

set -uo pipefail
_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${_HERE}/../harness/lib/common.sh"

RUN="${REPO_ROOT}/bench/data/w5-tamper-20260910T092621Z"
FROM="${RUN}/t0_clean.decode.txt"
OUT="${REPO_ROOT}/rats/ref/clean.corim"
KEY="${REPO_ROOT}/rats/keys/ref-signer.key"
PUB="${REPO_ROOT}/rats/keys/ref-signer.pub"
KID="42"
GENKEY=0

while [ $# -gt 0 ]; do
    case "$1" in
        --from)   FROM="$2"; shift 2 ;;
        --out)    OUT="$2"; shift 2 ;;
        --kid)    KID="$2"; shift 2 ;;
        --genkey) GENKEY=1; shift ;;
        -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
done

need python3 openssl
mkdir -p "$(dirname "$OUT")" "$(dirname "$KEY")"

if [ "$GENKEY" -eq 1 ] || [ ! -f "$KEY" ]; then
    if [ -f "$KEY" ]; then
        # Overwriting a signing key silently invalidates every reference value
        # already published under it, and the failure appears later, somewhere
        # else, as "the endorsement did not verify".
        die "$KEY exists. Remove it deliberately if you mean to replace it — every committed .corim stops verifying when you do."
    fi
    log "generating an ES256 reference-signing key"
    run openssl ecparam -name prime256v1 -genkey -noout -out "$KEY"
    run openssl ec -in "$KEY" -pubout -out "$PUB" 2>/dev/null
    ok "$(basename "$KEY") (untracked) and $(basename "$PUB") (committed)"
fi

[ -f "$KEY" ] || die "no signing key at $KEY — run with --genkey"

TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT

log "reference values, from the measurement record in $(basename "$FROM")"
run python3 "${REPO_ROOT}/rats/appraise.py" reference "$FROM" \
    -o "${TMPD}/reference.json" || die "could not build the reference document"

log "JSON -> CBOR"
run python3 "${REPO_ROOT}/rats/appraise.py" to-cbor \
    -i "${TMPD}/reference.json" -o "${TMPD}/reference.cbor" || die "encoding failed"

log "COSE_Sign1, wrapped as a signed CoRIM"
run python3 "${REPO_ROOT}/rats/cose.py" sign -i "${TMPD}/reference.cbor" \
    --key "$KEY" --kid "$KID" --corim -o "$OUT" || die "signing failed"

# Never publish a reference value without checking it verifies. The signer and
# the verifier are different code paths in this project, and an unverifiable
# manifest discovered at appraisal time looks like a bad device.
log "verifying what was just written, with the public half"
run python3 "${REPO_ROOT}/rats/cose.py" verify -i "$OUT" --key "$PUB" \
    -o "${TMPD}/recovered.cbor" || die "the reference value does not verify against $PUB"
cmp -s "${TMPD}/recovered.cbor" "${TMPD}/reference.cbor" \
    || die "the payload recovered from the signature is not the document that was signed"
ok "payload recovered byte for byte"

# And the copy of the reference document, beside the signed one. It is not what
# the verifier reads — it reads the signed CBOR — but a reference value nobody
# can read is a reference value nobody will review.
cp "${TMPD}/reference.json" "${OUT%.corim}.json"

hdr "published"
printf '  %s  %s bytes\n' "$(realpath --relative-to="$REPO_ROOT" "$OUT")" "$(stat -c%s "$OUT")"
printf '  %s  %s bytes (the same document, readable)\n' \
    "$(realpath --relative-to="$REPO_ROOT" "${OUT%.corim}.json")" \
    "$(stat -c%s "${OUT%.corim}.json")"
printf '  kid %s, ES256, signed with %s\n' "$KID" "$(realpath --relative-to="$REPO_ROOT" "$KEY")"

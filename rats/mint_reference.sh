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

    # ★ And the case the guard above does NOT cover, found by cloning this
    # repository somewhere else and running this script: the private key is not
    # tracked, so in a FRESH CLONE it is absent while the published reference
    # values are present. "Generate one because there isn't one" then silently
    # replaces the key that every committed .corim was signed with, and the
    # damage surfaces three checks later as "rats/cose.py no longer verifies
    # CoRimTool.py's signature" — which is true, and says nothing about either
    # tool.
    #
    # The two conditions are not the same shape. The first is "do not overwrite
    # something that exists". This is "do not create something whose absence is
    # load-bearing", and it is the one that fires on the machine of anybody who
    # is not the author.
    if ls "$(dirname "$OUT")"/*.corim >/dev/null 2>&1; then
        die "no signing key at $KEY, but reference values are already published in $(dirname "$OUT"). The private half is deliberately untracked (see rats/README.md), so this is what a fresh clone looks like: you can VERIFY these, and only the machine that minted them can re-mint them. Generating a key here would replace the one they were signed with and they would all stop verifying. If you really mean to publish a NEW set, delete them first and pass --genkey."
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

# ECDSA signatures carry a random nonce, so signing the same document twice
# produces two different files. That makes a re-run of this script a change to
# a committed binary with no change to its meaning, which is diff noise at best
# and, at worst, somebody wondering what moved. Idempotence is free here: if
# the existing reference value verifies and carries exactly the document about
# to be signed, nothing needs to happen.
if [ -f "$OUT" ] \
   && python3 "${REPO_ROOT}/rats/cose.py" verify -i "$OUT" --key "$PUB" \
        -o "${TMPD}/existing.cbor" >/dev/null 2>&1 \
   && cmp -s "${TMPD}/existing.cbor" "${TMPD}/reference.cbor"; then
    ok "$(realpath --relative-to="$REPO_ROOT" "$OUT") already carries this exact document, signed and verifying — not re-signed"
    cp "${TMPD}/reference.json" "${OUT%.corim}.json"
    hdr "unchanged"
    printf '  %s  %s bytes\n' "$(realpath --relative-to="$REPO_ROOT" "$OUT")" "$(stat -c%s "$OUT")"
    printf '  a fresh signature over the same bytes would differ (ECDSA is randomised) and mean nothing\n'
    exit 0
fi

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

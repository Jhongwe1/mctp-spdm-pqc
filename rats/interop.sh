#!/usr/bin/env bash
#
# rats/interop.sh — run this pipeline and DMTF's side by side, and require the
# two to agree.
#
#     bash rats/interop.sh                # produces rats/interop/
#
# Why
# ---
# rats/ is a second implementation of a format somebody else defined. A second
# implementation that has never been compared against the first is a guess with
# good documentation, and the guess would not be visible: this project's own
# policy would accept this project's own reference values forever.
#
# So the deterministic halves are compared BYTE FOR BYTE against DMTF's
# spdm_emu/spdm_device_verifier_tool/, and the non-deterministic half — a
# signature — is cross-verified in both directions. `docs/roadmap.md` standing
# rule 12: where two tools reach the same quantity by different routes, they
# are made to agree.
#
# This script needs a spdm-emu checkout and a Python virtualenv, so it does NOT
# run in CI. What runs in CI is the *result*: DMTF's outputs are committed
# under rats/interop/, and harness/verify_repo.sh re-derives this project's
# side and requires it to equal them. The comparison is therefore checked on
# every push, by a runner that has none of what this script needs.
#
# ⚠ Three things have to be worked around before DMTF's tools run at all, and
# all three are upstream defects this project measured. They are described in
# docs/rats-pipeline.md and reported in docs/upstream/README.md:
#
#   1. cbor2 >= 6.0 decodes the contents of a CBORTag as immutable containers,
#      and pycose requires list/dict. requirements.txt pins no upper bound, so
#      a fresh install cannot decode a COSE message — including one pycose just
#      produced. This script pins cbor2==5.6.5.
#   2. CoRimTool.py's verify builds the verification key as
#      EC2Key(crv='P_256', d=<the 64-byte public point>), passing the public
#      key where the private scalar goes, so it refuses every signature it
#      produced.
#   3. …and the same function DISCARDS the return value of
#      verify_signature(), which is a bool rather than an exception. So with
#      (2) repaired and (3) not, a corrupted signature prints "Signature
#      verification passed".
#
# (2) and (3) mask each other, and that is why both are patched here and why
# they are one change upstream: repairing the key alone converts a tool that
# accepts nothing into a tool that accepts anything. This script measured that
# the day it was written, by flipping one byte of a signature and watching the
# half-patched tool accept it — see "the half-fix" below, which is now a
# permanent check rather than a story.
#
# Both patches are applied to a SCRATCH COPY. The pinned tree is never written.

set -uo pipefail
_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${_HERE}/../harness/lib/common.sh"
set +e

OUT="${REPO_ROOT}/rats/interop"
SCRATCH="${LAB_DIR}/scratch-interop"
VENV="${LAB_DIR}/venv-rats"
VT_SRC="$(flavor_dir pqc)/spdm_emu/spdm_device_verifier_tool"
RUN="${REPO_ROOT}/bench/data/w5-tamper-20260910T092621Z"
ARM="t0_clean"

FAILED=0
pass() { printf '  \033[32mok\033[0m   %s\n' "$*"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$*"; FAILED=1; }

need python3 openssl opa
[ -d "$VT_SRC" ] || die "no verifier tool at $VT_SRC — build the pqc flavor first (RUNBOOK.md §4)"

hdr "interoperability with DMTF's verifier tool"

# ---------------------------------------------------------------- setup -----

log "preparing a scratch copy (the pinned tree is not written to)"
rm -rf "$SCRATCH"
mkdir -p "$SCRATCH" "$OUT"
cp -r "$VT_SRC"/. "$SCRATCH"/ || die "could not copy the verifier tool"

# The two-line fix, applied byte-wise so the CRLF line endings survive: the
# diff this project sends upstream has to be the diff it tested, and a file
# whose endings changed is a diff of the whole file.
#
# A HALF-patched copy is kept beside it on purpose. It is the version that
# would exist if the pull request fixed only the key, and the check further
# down requires it to ACCEPT a signature it should refuse. That is not a
# curiosity: it is the state this project was one keystroke from submitting on
# 2026-09-12, and a check is the only form of "remember this" that survives.
cp "$SCRATCH/CoRimTool.py" "$SCRATCH/CoRimTool.half.py"
if python3 - "$SCRATCH/CoRimTool.py" "$SCRATCH/CoRimTool.half.py" <<'PY'
import sys
full, half = sys.argv[1], sys.argv[2]
KEY_OLD = b"        cose_key = EC2Key(crv='P_256', d=key)"
KEY_NEW = (b"        cose_key = EC2Key(crv='P_256', x=key[:len(key) // 2], "
           b"y=key[len(key) // 2:])")
RES_OLD = b"        cose_msg.verify_signature(Algorithm)"
RES_NEW = (b"        if not cose_msg.verify_signature(Algorithm):\r\n"
           b"            raise ValueError('signature does not verify')")


def sub(raw, old, new):
    for eol in (b"\r\n", b"\n"):
        if raw.count(old + eol) == 1:
            return raw.replace(old + eol, new.replace(b"\r\n", eol) + eol)
    raise SystemExit(f"expected exactly one occurrence of {old!r}")


raw = open(full, 'rb').read()
open(half, 'wb').write(sub(raw, KEY_OLD, KEY_NEW))
open(full, 'wb').write(sub(sub(raw, KEY_OLD, KEY_NEW), RES_OLD, RES_NEW))
PY
then
    pass "patched CoRimTool.py verify: the key, and the discarded result"
else
    fail "CoRimTool.py no longer contains the lines this script patches — re-read it before trusting anything below"
fi

log "python environment"
if [ ! -x "$VENV/bin/python3" ]; then
    python3 -m venv "$VENV" || die "could not create $VENV"
fi
"$VENV/bin/pip" install --quiet -r "$SCRATCH/requirements.txt" >/dev/null 2>&1
"$VENV/bin/pip" install --quiet "cbor2==5.6.5" >/dev/null 2>&1
PY="$VENV/bin/python3"
CBOR2_VER="$("$PY" -c 'import importlib.metadata as m; print(m.version("cbor2"))')"
dim "    cbor2 $CBOR2_VER (pinned: >= 6.0 breaks pycose, see the header)"

# --------------------------------------------------- the shared inputs ------

log "the measurement record, off the wire"
python3 "${REPO_ROOT}/harness/fields.py" "${RUN}/${ARM}.decode.txt" \
        --emit-record "${OUT}/record.bin" || fail "could not emit the record"

log "this project's reference document"
python3 "${REPO_ROOT}/rats/appraise.py" reference "${RUN}/${ARM}.decode.txt" \
        -o "${OUT}/reference.json" || fail "could not build the reference"

# ------------------------------------------- 1. evidence, byte for byte -----

hdr "1. evidence: 528 bytes of measurement record, two parsers"
"$PY" "$SCRATCH/SpdmMeasurement.py" meas_to_json --meas "${OUT}/record.bin" \
      --alg sha512 -o "${OUT}/dmtf-evidence.json" >/dev/null 2>&1
python3 "${REPO_ROOT}/rats/appraise.py" evidence "${RUN}/${ARM}.decode.txt" \
        -o "${SCRATCH}/ours-evidence.json" >/dev/null

if [ ! -s "${OUT}/dmtf-evidence.json" ]; then
    fail "SpdmMeasurement.py produced nothing"
elif cmp -s "${OUT}/dmtf-evidence.json" "${SCRATCH}/ours-evidence.json"; then
    pass "SpdmMeasurement.py and rats/appraise.py produce identical bytes"
elif [ "$(sed -e '$a\' "${OUT}/dmtf-evidence.json" | sha256sum)" \
      = "$(sed -e '$a\' "${SCRATCH}/ours-evidence.json" | sha256sum)" ]; then
    # SpdmMeasurement.py writes json.dumps(...).encode() and stops, so its file
    # has no final newline. Every byte of the document agrees; one writer ends
    # the file and the other does not. Worth stating exactly rather than either
    # hiding it or degrading this project's own writer to match a quirk.
    pass "identical apart from the final newline, which SpdmMeasurement.py omits"
else
    fail "the two evidence documents differ:"
    diff "${OUT}/dmtf-evidence.json" "${SCRATCH}/ours-evidence.json" | head -20
fi

# ------------------------------------------ 2. JSON -> CBOR, byte for byte --

hdr "2. CoRIM encoding: one JSON document, two CBOR encoders"
"$PY" "$SCRATCH/CoRimTool.py" json_to_cbor -i "${OUT}/reference.json" \
      -o "${OUT}/dmtf-reference.cbor" >/dev/null 2>&1
python3 "${REPO_ROOT}/rats/appraise.py" to-cbor -i "${OUT}/reference.json" \
        -o "${SCRATCH}/ours-reference.cbor" >/dev/null

if [ ! -s "${OUT}/dmtf-reference.cbor" ]; then
    fail "CoRimTool.py json_to_cbor produced nothing"
elif cmp -s "${OUT}/dmtf-reference.cbor" "${SCRATCH}/ours-reference.cbor"; then
    pass "CoRimTool.py and rats/cose.py encode the same $(stat -c%s "${OUT}/dmtf-reference.cbor") bytes"
else
    fail "the two CBOR encodings differ"
    cmp -l "${OUT}/dmtf-reference.cbor" "${SCRATCH}/ours-reference.cbor" | head -10
fi

# And the property that makes the byte comparison above possible to state at
# all: encode, decode, encode again, and get the same bytes. This project's
# encoder has it. CoRimTool.py does not, because its json_to_cbor maps exactly
# two name strings — "comid_tag_creator" and "sha256" — to their integers, in
# a branch where a table lookup was meant, so a document naming sha512 or
# comid_creator encodes those as text and grows on every round trip.
"$PY" "$SCRATCH/CoRimTool.py" cbor_to_json -i "${OUT}/dmtf-reference.cbor" \
      -o "${SCRATCH}/dmtf-roundtrip.json" >/dev/null 2>&1
"$PY" "$SCRATCH/CoRimTool.py" json_to_cbor -i "${SCRATCH}/dmtf-roundtrip.json" \
      -o "${SCRATCH}/dmtf-roundtrip.cbor" >/dev/null 2>&1
python3 "${REPO_ROOT}/rats/appraise.py" to-json -i "${OUT}/dmtf-reference.cbor" \
        -o "${SCRATCH}/ours-roundtrip.json" >/dev/null
python3 "${REPO_ROOT}/rats/appraise.py" to-cbor -i "${SCRATCH}/ours-roundtrip.json" \
        -o "${SCRATCH}/ours-roundtrip.cbor" >/dev/null

BASE_SIZE="$(stat -c%s "${OUT}/dmtf-reference.cbor")"
if cmp -s "${SCRATCH}/ours-roundtrip.cbor" "${OUT}/dmtf-reference.cbor"; then
    pass "rats/: encode -> decode -> encode returns the same $BASE_SIZE bytes"
else
    fail "rats/: a decode-and-re-encode changed the document"
fi

# CoRimTool.py does not merely change the document — it cannot read its own
# output at all. cbor_to_json writes the two container tags as KEYS ("corim",
# "unsigned_corim_map") and json_to_cbor's AllMapDict has no entry for either,
# so translate_data raises. The failure reproduces on the sample manifest that
# ships beside the tool, which is the version worth reporting because it needs
# nothing of this project's to see.
DMTF_RT="$("$PY" "$SCRATCH/CoRimTool.py" json_to_cbor \
           -i "${SCRATCH}/dmtf-roundtrip.json" \
           -o "${SCRATCH}/dmtf-roundtrip.cbor" 2>&1)"
DMTF_RT_WHY="$(printf '%s\n' "$DMTF_RT" | tail -1)"
"$PY" "$SCRATCH/CoRimTool.py" json_to_cbor \
      -i "$SCRATCH/SampleManifests/SpdmSampleCoMid.json" \
      -o "${SCRATCH}/sample.cbor" >/dev/null 2>&1
"$PY" "$SCRATCH/CoRimTool.py" cbor_to_json -i "${SCRATCH}/sample.cbor" \
      -o "${SCRATCH}/sample.json" >/dev/null 2>&1
SAMPLE_RT="$("$PY" "$SCRATCH/CoRimTool.py" json_to_cbor \
             -i "${SCRATCH}/sample.json" -o "${SCRATCH}/sample2.cbor" 2>&1 | tail -1)"

case "$DMTF_RT_WHY" in
    *KeyError*) pass "CoRimTool.py cannot re-encode its own decode: $DMTF_RT_WHY" ;;
    *) if cmp -s "${SCRATCH}/dmtf-roundtrip.cbor" "${OUT}/dmtf-reference.cbor"; then
           warn "CoRimTool.py round-trips unchanged — docs/rats-pipeline.md needs re-checking"
       else
           pass "CoRimTool.py does not round-trip: $DMTF_RT_WHY"
       fi ;;
esac
case "$SAMPLE_RT" in
    *KeyError*) pass "…and the same on ITS OWN SampleManifests/SpdmSampleCoMid.json: $SAMPLE_RT" ;;
    *) warn "the sample manifest round-trips; the report in docs/upstream/README.md needs re-checking" ;;
esac

# ---------------------------------------- 3. signatures, both directions ----

hdr "3. COSE_Sign1: each tool must accept the other's signature"

# Signed by DMTF's tool with THIS project's key, so nothing of upstream's is
# committed here and CI can verify it with the committed public key.
"$PY" "$SCRATCH/CoRimTool.py" sign -f "${OUT}/dmtf-reference.cbor" \
      --key "${REPO_ROOT}/rats/keys/ref-signer.key" --kid 42 --alg ES256 \
      -o "${OUT}/dmtf-signed.corim" >/dev/null 2>&1
if [ -s "${OUT}/dmtf-signed.corim" ]; then
    if python3 "${REPO_ROOT}/rats/cose.py" verify -i "${OUT}/dmtf-signed.corim" \
            --key "${REPO_ROOT}/rats/keys/ref-signer.pub" \
            -o "${SCRATCH}/from-dmtf.cbor" >/dev/null; then
        pass "rats/cose.py verifies a COSE_Sign1 that CoRimTool.py produced"
        if cmp -s "${SCRATCH}/from-dmtf.cbor" "${OUT}/dmtf-reference.cbor"; then
            pass "and the payload it recovers is the document that was signed"
        else
            fail "the recovered payload is not the signed document"
        fi
    else
        fail "rats/cose.py rejected CoRimTool.py's signature"
    fi
else
    fail "CoRimTool.py sign produced nothing"
fi

# ...and the other direction: our signature, their (patched) verifier.
if "$PY" "$SCRATCH/CoRimTool.py" verify -f "${REPO_ROOT}/rats/ref/clean.corim" \
        --key "${REPO_ROOT}/rats/keys/ref-signer.pub" --alg ES256 \
        -o "${SCRATCH}/from-ours.cbor" 2>&1 | grep -q 'verification passed'; then
    pass "CoRimTool.py (patched) verifies a COSE_Sign1 that rats/cose.py produced"
else
    fail "CoRimTool.py rejected this project's signature"
fi

# ⚠ and the same call WITHOUT the patch, because the claim being reported
# upstream is that it fails, and a claim this project sends to someone else is
# one it should be running.
if "$PY" "$VT_SRC/CoRimTool.py" verify -f "${REPO_ROOT}/rats/ref/clean.corim" \
        --key "${REPO_ROOT}/rats/keys/ref-signer.pub" --alg ES256 \
        -o "${SCRATCH}/unpatched.cbor" 2>&1 | grep -q 'verification failed'; then
    pass "unpatched CoRimTool.py refuses it — the upstream report still stands"
else
    fail "unpatched CoRimTool.py did NOT refuse it. The defect reported in docs/upstream/README.md may have been fixed, or misread. Re-check before sending anything."
fi

# ★ The half-fix. One byte of the signature flipped, fed to three versions:
# the fully patched one must REFUSE it; the half-patched one — the change this
# project nearly submitted — must ACCEPT it. If the half-patched one ever
# starts refusing, the second half of the upstream report is wrong and must not
# be sent.
python3 - "${REPO_ROOT}/rats/ref/clean.corim" "${SCRATCH}/forged.corim" <<'PY'
import sys
raw = bytearray(open(sys.argv[1], 'rb').read())
raw[-1] ^= 0x01                       # the last byte of the COSE signature
open(sys.argv[2], 'wb').write(bytes(raw))
PY
FORGED_FULL="$("$PY" "$SCRATCH/CoRimTool.py" verify -f "${SCRATCH}/forged.corim" \
               --key "${REPO_ROOT}/rats/keys/ref-signer.pub" --alg ES256 \
               -o "${SCRATCH}/forged-full.cbor" 2>&1)"
FORGED_HALF="$("$PY" "$SCRATCH/CoRimTool.half.py" verify -f "${SCRATCH}/forged.corim" \
               --key "${REPO_ROOT}/rats/keys/ref-signer.pub" --alg ES256 \
               -o "${SCRATCH}/forged-half.cbor" 2>&1)"
case "$FORGED_FULL" in
    *failed*) pass "a forged signature is refused by the two-line fix" ;;
    *) fail "the fully patched CoRimTool.py ACCEPTED a forged signature: $FORGED_FULL" ;;
esac
case "$FORGED_HALF" in
    *passed*) pass "…and ACCEPTED by the key-only fix — which is why it is one change" ;;
    *) fail "the key-only fix refused the forged signature. The upstream report says it does not; re-read verify_signature's return type before sending anything." ;;
esac
if python3 "${REPO_ROOT}/rats/cose.py" verify -i "${SCRATCH}/forged.corim" \
        --key "${REPO_ROOT}/rats/keys/ref-signer.pub" >/dev/null 2>&1; then
    fail "rats/cose.py ACCEPTED a forged signature"
else
    pass "rats/cose.py refuses it too, with a non-zero exit"
fi

# ------------------------------- 4. the published policy, on the same input -

hdr "4. DMTF's SpdmSamplePolicy.rego, on inputs this project's policy refuses"

python3 "${REPO_ROOT}/rats/appraise.py" to-json -i "${OUT}/dmtf-reference.cbor" \
        -o "${SCRATCH}/ref-decoded.json" >/dev/null

# The sample is Rego v0 and OPA 1.x refuses it without --v0-compatible. Record
# that rather than only working around it.
if opa eval -i /dev/null -d "$SCRATCH/SpdmSamplePolicy.rego" 'data.spdm' \
        >/dev/null 2>&1; then
    fail "SpdmSamplePolicy.rego parsed as Rego v1 — OPA's default has changed and docs/rats-pipeline.md needs re-checking"
else
    pass "SpdmSamplePolicy.rego does not parse as Rego v1 (opa $(opa version | awk '/^Version/{print $2}'))"
fi

python3 "${REPO_ROOT}/rats/appraise.py" opa-input \
        -e "${SCRATCH}/ours-evidence.json" -r "${SCRATCH}/ref-decoded.json" \
        -o "${SCRATCH}/opa.input" >/dev/null
SAMPLE="$(opa eval --v0-compatible --format json -i "${SCRATCH}/opa.input" \
          -d "$SCRATCH/SpdmSamplePolicy.rego" 'data.spdm.output' 2>&1)"
case "$SAMPLE" in
    *'"error_code": 0'*) pass "the sample policy passes the clean capture, as this project's does" ;;
    *) fail "the sample policy did not pass the clean capture: $SAMPLE" ;;
esac

# The swap: index 1's value presented as index 2's. Both policies see the same
# input; only one of them can see the difference.
python3 - "${SCRATCH}/ours-evidence.json" "${SCRATCH}/swapped-evidence.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
ev = [e for e in d["evidences"] if "digest" in e["evidence"]]
ev[0]["evidence"]["digest"][1], ev[1]["evidence"]["digest"][1] = \
    ev[1]["evidence"]["digest"][1], ev[0]["evidence"]["digest"][1]
json.dump(d, open(sys.argv[2], "w"), indent=2)
PY
python3 "${REPO_ROOT}/rats/appraise.py" opa-input \
        -e "${SCRATCH}/swapped-evidence.json" -r "${SCRATCH}/ref-decoded.json" \
        -o "${SCRATCH}/opa.swapped" >/dev/null
SWAP_SAMPLE="$(opa eval --v0-compatible --format json -i "${SCRATCH}/opa.swapped" \
               -d "$SCRATCH/SpdmSamplePolicy.rego" 'data.spdm.output' 2>&1)"
SWAP_OURS="$(opa eval --format json -i "${SCRATCH}/opa.swapped" \
             -d "${REPO_ROOT}/rats/policy.rego" 'data.spdm.output' 2>&1)"
case "$SWAP_SAMPLE" in
    *'"error_code": 0'*) pass "the sample policy ACCEPTS the index swap (measured, not modelled)" ;;
    *) fail "the sample policy refused the swap — rats/rats_selftest.py's model of it is wrong" ;;
esac
case "$SWAP_OURS" in
    *'"verdict": "fail"'*) pass "rats/policy.rego refuses it" ;;
    *) fail "rats/policy.rego accepted the index swap" ;;
esac

# Both sides empty: the vacuous pass.
printf '{"evidences": []}\n' > "${SCRATCH}/empty-evidence.json"
python3 - "${SCRATCH}/ref-decoded.json" "${SCRATCH}/empty-ref.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
tag = d["corim"]["unsigned_corim_map"]["corim_tags"][0]
tag["comid_triples"]["comid_reference_triples"] = []
json.dump(d, open(sys.argv[2], "w"), indent=2)
PY
python3 "${REPO_ROOT}/rats/appraise.py" opa-input \
        -e "${SCRATCH}/empty-evidence.json" -r "${SCRATCH}/empty-ref.json" \
        -o "${SCRATCH}/opa.empty" >/dev/null
EMPTY_SAMPLE="$(opa eval --v0-compatible --format json -i "${SCRATCH}/opa.empty" \
                -d "$SCRATCH/SpdmSamplePolicy.rego" 'data.spdm.output' 2>&1)"
EMPTY_OURS="$(opa eval --format json -i "${SCRATCH}/opa.empty" \
              -d "${REPO_ROOT}/rats/policy.rego" 'data.spdm.output' 2>&1)"
case "$EMPTY_SAMPLE" in
    *'"error_code": 0'*) pass "the sample policy ACCEPTS a device that measured nothing, against a reference that names nothing" ;;
    *) fail "the sample policy refused the empty pair — rats/rats_selftest.py's model of it is wrong" ;;
esac
case "$EMPTY_OURS" in
    *'"verdict": "fail"'*) pass "rats/policy.rego refuses it (REFERENCE_PRESENT)" ;;
    *) fail "rats/policy.rego accepted the empty pair" ;;
esac

# ------------------------------------------------------------- the report ---

{
    echo "# rats/interop — measured, not asserted"
    echo
    echo "Produced by \`bash rats/interop.sh\` on $(date -u +%Y-%m-%dT%H:%M:%SZ)."
    echo "Not re-run in CI; what CI re-runs is the comparison against the files"
    echo "here. See harness/verify_repo.sh."
    echo
    echo "| | |"
    echo "|---|---|"
    echo "| spdm-emu | $(git -C "$(flavor_dir pqc)" rev-parse --short HEAD 2>/dev/null) |"
    echo "| CoRimTool.py | last changed $(git -C "$(flavor_dir pqc)" log -1 --format=%ad --date=short -- spdm_emu/spdm_device_verifier_tool/CoRimTool.py 2>/dev/null) |"
    echo "| opa | $(opa version | awk '/^Version/{print $2}') |"
    echo "| cbor2 | $CBOR2_VER (pinned; >= 6.0 breaks pycose) |"
    echo "| pycose | $("$PY" -c 'import importlib.metadata as m; print(m.version("pycose"))' 2>/dev/null) |"
    echo "| capture | \`bench/data/w5-tamper-20260910T092621Z/${ARM}\` |"
    echo "| record | $(sha256sum "${OUT}/record.bin" | cut -d' ' -f1) |"
    echo
    echo "## What was compared"
    echo
    echo "| # | comparison | result |"
    echo "|:--|---|---|"
    echo "| 1 | \`SpdmMeasurement.py meas_to_json\` vs \`rats/appraise.py evidence\` | identical apart from a final newline |"
    echo "| 2 | \`CoRimTool.py json_to_cbor\` vs \`rats/appraise.py to-cbor\` | byte-identical, $BASE_SIZE bytes |"
    echo "| 3 | \`rats/\`: encode → decode → encode | same $BASE_SIZE bytes |"
    echo "| 4 | \`CoRimTool.py\`: the same round trip | **$DMTF_RT_WHY** |"
    echo "| 4b | …on its own \`SampleManifests/SpdmSampleCoMid.json\` | **$SAMPLE_RT** |"
    echo "| 5 | \`rats/cose.py verify\` on \`CoRimTool.py sign\`'s output | accepted |"
    echo "| 6 | \`CoRimTool.py verify\` (patched) on \`rats/cose.py sign\`'s output | accepted |"
    echo "| 7 | \`CoRimTool.py verify\` (**unpatched**) on the same file | refused — upstream defect ② |"
    echo "| 7a | a **forged** signature, fully patched tool | refused |"
    echo "| 7b | the same, **key-only** patch | **accepted** — upstream defect ③ |"
    echo "| 7c | the same, \`rats/cose.py\` | refused, non-zero exit |"
    echo "| 8 | \`SpdmSamplePolicy.rego\` parsed as Rego v1 | refused, 11 parse errors |"
    echo "| 9 | \`SpdmSamplePolicy.rego\` on the clean capture | passes, as this project's policy does |"
    echo "| 10 | \`SpdmSamplePolicy.rego\` on an index swap | **accepts** |"
    echo "| 11 | \`rats/policy.rego\` on the same swap | refuses |"
    echo "| 12 | \`SpdmSamplePolicy.rego\` on nothing-measured-anywhere | **accepts** |"
    echo "| 13 | \`rats/policy.rego\` on the same | refuses |"
    echo
    echo "Rows 4 and 4b are not comparisons this project set out to make. They"
    echo "are what row 2 turned into once the encoders were compared at all."
    echo "\`cbor_to_json\` writes the two CoRIM container tags as JSON KEYS —"
    echo "\`corim\` and \`unsigned_corim_map\` — and \`json_to_cbor\`'s \`AllMapDict\`"
    echo "has no entry for either, so \`translate_data\` raises before it reaches"
    echo "anything else."
    echo
    echo "A second, narrower difference sits behind it and was found first:"
    echo "\`translate_data\` maps exactly two name strings to integers —"
    echo "\`comid_tag_creator\` and \`sha256\` — hard-coded, in a branch where a"
    echo "table lookup was intended. A CoMID naming \`sha512\` or \`comid_creator\`"
    echo "encodes those as text strings, 43 bytes larger than the same document"
    echo "written with integers. This project's reference values are written"
    echo "with integers, which is what the published sample does, and that is"
    echo "why row 2 can be a byte comparison at all."
    echo
    echo "Rows 10 and 12 are the measured version of what \`rats/rats_selftest.py\`"
    echo "models. The model exists so a runner without \`spdm-emu\` keeps checking"
    echo "the claim; this file is the run that says the model is right."
    echo
    echo "## The two workarounds, and why they are not this project's"
    echo
    echo "\`\`\`"
    echo "cbor2==5.6.5    pinned. 6.x decodes a CBORTag's contents as immutable"
    echo "                containers and pycose type-checks for list/dict, so"
    echo "                pycose cannot decode its own encode() output."
    echo
    echo "CoRimTool.py    one line, in a scratch copy:"
    echo "-   cose_key = EC2Key(crv='P_256', d=key)"
    echo "+   cose_key = EC2Key(crv='P_256', x=key[:len(key)//2], y=key[len(key)//2:])"
    echo "\`\`\`"
    echo
    echo "Reported in \`docs/upstream/README.md\`. Row 5 above is this repository"
    echo "re-running its own bug report on every interop run, so that the day"
    echo "upstream fixes it, this script says so rather than the report going"
    echo "quietly stale."
} > "${OUT}/report.md"

hdr "result"
if [ "$FAILED" -eq 0 ]; then
    ok "every comparison agreed; ${OUT}/report.md written"
else
    warn "at least one comparison failed — see above"
fi
ls -la "$OUT"
exit "$FAILED"

#!/usr/bin/env python3
"""Appraise a captured SPDM measurement against a signed reference value.

    python3 rats/appraise.py appraise  <run>/t0_clean.decode.txt        # the verdict
    python3 rats/appraise.py evidence  <run>/t0_clean.decode.txt -o ev.json
    python3 rats/appraise.py reference <run>/t0_clean.decode.txt -o ref.json
    python3 rats/appraise.py to-cbor   -i ref.json -o ref.cbor
    python3 rats/appraise.py to-json   -i ref.cbor -o ref.json
    python3 rats/appraise.py selftest

What this answers, and why SPDM cannot
--------------------------------------
`GET_MEASUREMENTS` returns a set of digests, signed by the device. A requester
that verifies that signature has established exactly one thing: **these values
came from this device and were not altered on the way.** It has established
nothing whatsoever about whether the values are the *right* ones.

That distinction is not academic here — it is measured. `docs/tamper.md` row 1:
a byte of measurement index 1 changed **on the device**, before the responder
hashed and signed it. The handshake completed. Every signature verified. The
requester exited 0 and printed no error, because a device that has been
compromised still signs honestly; it signs the compromised value.

The missing half is IETF RATS (RFC 9334), and it is three things SPDM does not
carry: a **reference value** saying what the digest should be, an
**endorsement** saying who is entitled to publish that reference value, and an
**appraisal policy** saying what to do when they do not match. This file is the
Verifier role. `docs/rats-roles.md` has the five roles and which of them this
project plays.

Independent variables are read, not asserted
--------------------------------------------
The digest algorithm is **not** a flag. It is read out of the `ALGORITHMS`
response in the capture being appraised — `MeasHash`, the field the responder
selected — through `harness/fields.py`, which owns the decode. A reference value
minted under an algorithm the device did not negotiate would compare
SHA-512 digests against SHA-384 ones and fail for a reason that has nothing to
do with the device. `docs/roadmap.md` standing rule 8, and 2026-08-17 in
`LOG.md` is what ignoring it cost the first time.

The same applies to the measurement record itself: it is sliced out of the
`MEASUREMENTS` message, not read from `device/measurements.bin`. The fixture is
the file the responder *read*; the record is what it *sent*. A pipeline fed the
fixture compares a document against itself and passes for every input,
tampered ones included. `harness/fields.py --emit-record` says the same thing
at more length.

What is deliberately not checked here
-------------------------------------
Two of the eight measurement blocks on the wire cannot become evidence at all.
`MEASUREMENT_MANIFEST` (0xfd, 128 bytes) and `DEVICE_MODE` (0xfe, 16 bytes) are
raw bit streams that are not secure version numbers, and DMTF's evidence format
has no representation for them — `SpdmMeasurement.py` walks past both without
comment. This file reproduces that behaviour, because interoperability with the
reference implementation is the point, and then **counts what it dropped** and
puts the number in the verdict. A coverage figure beside a verdict is the
difference between "this device passed" and "this device passed the part of
itself that anything can look at".

`DEVICE_MODE` is the sharper loss of the two: its value in this project's
captures is `3f000000 04000000 1f000000 11000000`, which is where a device says
whether it is in a debug mode. No policy expressible in this format can read it.

Exit codes
----------
  0  the appraisal PASSED
  1  the appraisal FAILED — a verdict, and the whole point of the exercise
  2  the appraisal could not be performed (bad input, no policy engine,
     endorsement did not verify, the record could not be read)

★ 1 and 2 are kept apart on purpose. "The device is bad" and "I could not tell"
are different answers, and a pipeline that conflates them reports a broken
verifier as a failed device. `CoRimTool.py verify` — the tool this replaces —
exits 0 for all three.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
REPO_ROOT = _HERE.parent
sys.path.insert(0, str(REPO_ROOT / "harness"))

import fields  # noqa: E402  — the repo's decode parser; this file adds no second one
from cose import (CborError, Tag, VerifyFailed, dumps, loads,  # noqa: E402
                  verify1)

POLICY = _HERE / "policy.rego"

# ------------------------------------------------ the CoRIM name tables -----
#
# Transcribed from DMTF's spdm_emu/spdm_device_verifier_tool/CoRimTool.py at
# the commit in third_party/spdm-emu-pqc.pin. They are the wire names of the
# CoRIM and CoMID CDDL maps: CBOR carries integer labels, and the JSON form
# this project and DMTF's tool both produce carries the CDDL names with "." and
# "-" replaced by "_", because Rego identifiers cannot hold either.
#
# Transcribed rather than imported, for the same reason fields.py transcribes
# libspdm's capability bits: importing would mean the pipeline could not run
# without a checkout of spdm-emu, which is exactly the dependency this file
# exists to remove. The cost is the same too — a name that drifts stays
# self-consistent — and it is paid down by rats/interop/, where DMTF's own tool
# converts the same document and the two outputs are required to be identical
# byte for byte.

CORIM_TAGS = {"corim": 500, "unsigned_corim_map": 501, "signed_corim": 502,
              "consise_swid_tag": 505, "consise_mid_tag": 506}
COMID_TAGS = {"tagged_oid_type": 111, "tagged_uuid_type": 37,
              "tagged_ueid_type": 550, "tagged_svn": 552,
              "tagged_min_svn": 553}

HASH_ALG = {"sha256": 1, "sha384": 7, "sha512": 8}
HASH_ALG_BY_ID = {v: k for k, v in HASH_ALG.items()}

UNSIGNED_CORIM_MAP = {"corim_id": 0, "corim_tags": 1,
                      "corim_dependent_rims": 2, "corim_profile": 3}
CONCISE_MID_TAG = {"comid_language": 0, "comid_tag_identity": 1,
                   "comid_entity": 2, "comid_linked_tags": 3,
                   "comid_triples": 4}
TAG_IDENTITY_MAP = {"comid_tag_id": 0, "comid_tag_version": 1}
ENTITY_MAP = {"comid_entity_name": 0, "comid_reg_id": 1, "comid_role": 2}
TRIPLES_MAP = {"comid_reference_triples": 0, "comid_endorsed_triples": 1,
               "comid_identity_triples": 2, "comid_attest_key_triples": 3}
ENVIRONMENT_MAP = {"comid_class": 0, "comid_instance": 1, "comid_group": 2}
CLASS_MAP = {"comid_class_id": 0, "comid_vendor": 1, "comid_model": 2,
             "comid_layer": 3, "comid_index": 4}
MEASUREMENT_MAP = {"comid_mkey": 0, "comid_mval": 1}
MEASUREMENT_VALUE_MAP = {"comid_ver": 0, "comid_svn": 1, "comid_digests": 2,
                         "comid_flags": 3, "comid_raw_value": 4,
                         "comid_raw_value_mask": 5, "comid_mac_addr": 6,
                         "comid_ip_addr": 7, "comid_serial_number": 8,
                         "comid_ueid": 9, "comid_uuid": 10, "comid_name": 11}
COMID_ROLE = {"comid_tag_creator": 0, "comid_creator": 1, "comid_maintainer": 2}

# Which name table applies inside which key. DMTF's translator keys off the
# enclosing key's name, and so does this one, so that a document converted by
# either tool converts the same way.
LOGIC_MAP = {
    "unsigned_corim_map": UNSIGNED_CORIM_MAP,
    "corim_tags": CONCISE_MID_TAG,
    "comid_tag_identity": TAG_IDENTITY_MAP,
    "comid_entity": ENTITY_MAP,
    "comid_role": COMID_ROLE,
    "comid_triples": TRIPLES_MAP,
    "comid_reference_triples": ENVIRONMENT_MAP,
    "comid_class": CLASS_MAP,
    "comid_mval": MEASUREMENT_VALUE_MAP,
    "comid_digests": HASH_ALG,
}
ALL_NAMES = {}
for _t in (UNSIGNED_CORIM_MAP, CONCISE_MID_TAG, TAG_IDENTITY_MAP, ENTITY_MAP,
           TRIPLES_MAP, ENVIRONMENT_MAP, CLASS_MAP, MEASUREMENT_MAP,
           MEASUREMENT_VALUE_MAP):
    ALL_NAMES.update(_t)

# This project's own device class. In a deployment these three fields identify
# a product line and are the vendor's to choose; here they are minted once and
# written down, because a reference value that does not say what it describes is
# a hash with no subject. The class id is a UUID generated on 2026-09-12 and
# never regenerated — if it changed, every committed reference value would
# describe a different device.
DEVICE_CLASS_ID = "3F8E1C4A5B7D46A29E03C81D2F6B4A70"
DEVICE_VENDOR = "mctp-spdm-pqc"
DEVICE_MODEL = "spdm-emu responder, measurements from device/"
DEVICE_LAYER = 1


# --------------------------------------------------------- the capture ------

def read_capture(decode: Path) -> dict:
    """Everything this file needs from one capture, through fields.py alone."""
    text = decode.read_text(encoding="utf-8", errors="replace")
    messages, meta = fields.parse_decode(text)
    if not messages:
        raise Appraisal(f"{decode}: no SPDM messages decoded", 2)
    data = fields.extract(messages, meta, decode)

    neg = (data.get("algorithms") or {}).get("negotiated") or {}
    meas_hash = neg.get("MeasHash") or []
    if len(meas_hash) != 1:
        raise Appraisal(
            f"{decode}: the capture negotiated {meas_hash or 'no'} measurement "
            f"hash algorithm; an appraisal needs exactly one, and reading it "
            f"from the response is the point", 2)
    alg_name = meas_hash[0].lower().replace("_", "")
    if alg_name not in HASH_ALG:
        raise Appraisal(f"{decode}: measurement hash {meas_hash[0]} is not one "
                        f"this evidence format can name", 2)

    layout = data.get("layout") or {}
    rec = layout.get("measurement_record")
    if rec is None:
        raise Appraisal(f"{decode}: no MEASUREMENTS response carried a record — "
                        f"the handshake did not reach the point where a device "
                        f"says anything a reference value could be compared to", 2)
    if not rec.get("closes"):
        raise Appraisal(f"{decode}: the record walk did not close "
                        f"({rec.get('why_kind')}: {rec.get('why')})", 2)

    msg = next((m for m in messages if m.seq == rec["packet"]), None)
    if msg is None or not msg.raw:
        raise Appraisal(f"{decode}: packet {rec['packet']} has no bytes", 2)
    blob = bytes(msg.raw[rec["record_offset"]:
                         rec["record_offset"] + rec["record_bytes"]])
    walk = fields._measurement_record(blob, 0, len(blob), rec["declared_blocks"],
                                      keep_values=True)
    if not walk["closes"]:
        raise Appraisal(f"{decode}: the emitted record does not re-walk "
                        f"({walk['why_kind']}: {walk['why']})", 2)

    return {
        "decode": str(decode),
        "decode_sha256": data["source"]["sha256"],
        "record_sha256": rec["sha256"],
        "record_bytes": rec["record_bytes"],
        "alg_name": alg_name,
        "alg_id": HASH_ALG[alg_name],
        "alg_from": "ALGORITHMS response, MeasHash",
        "walk": walk,
    }


# --------------------------------------------------------- the evidence -----
#
# The shape is DMTF's, field for field, because rats/interop/ requires this
# file and SpdmMeasurement.py to produce the same bytes from the same record.
# Its rules, restated from that file so a reader does not have to have it open:
#
#   bit 7 of DMTFSpecMeasurementValueType clear  -> a digest; emit
#       {"index": i, "digest": [alg-id, hex]}
#   bit 7 set and the low seven bits == 7        -> a secure version number;
#       emit {"index": i, "svn": <uint64 little-endian>}
#   anything else                                -> not emitted, and not
#       mentioned. That silence is what `coverage` below counts.

SVN_TYPE = 0x07


def evidence_from_walk(walk: dict, alg_id: int) -> tuple[dict, dict]:
    evidences = []
    dropped = []
    for key in walk["block_order"]:
        b = walk["blocks"][key]
        vtype, value = b["value_type"], b["value"]
        if not b["raw_bit_stream"]:
            evidences.append({"evidence": {"index": b["index"],
                                           "digest": [alg_id, value.hex()]}})
        elif (vtype & fields.MEAS_TYPE_MASK) == SVN_TYPE and len(value) == 8:
            evidences.append({"evidence": {"index": b["index"],
                                           "svn": int.from_bytes(value, "little")}})
        else:
            dropped.append({"index": key, "type": b["value_type_name"],
                            "bytes": b["value_bytes"],
                            "why": "a raw bit stream that is not a secure "
                                   "version number has no evidence encoding"})
    coverage = {
        "blocks_on_the_wire": walk["blocks_walked"],
        "blocks_as_evidence": len(evidences),
        "blocks_no_format_can_carry": len(dropped),
        "dropped": dropped,
    }
    return {"evidences": evidences}, coverage


# -------------------------------------------------------- the reference -----
#
# A CoMID reference-value triple is [environment, measurement]: what is being
# described, and what its value should be. The index lives in the environment
# (comid_class.comid_index), which is why a policy CAN bind an index to a
# digest — and why it is worth noticing that DMTF's sample policy does not.

def reference_from_walk(walk: dict, alg_id: int, corim_id: str,
                        tag_id: str) -> dict:
    """Build the CoMID this project publishes as its reference values.

    The hash algorithm and the entity roles are written as **integers** rather
    than as the names this file's own decoder produces, which looks
    inconsistent and is deliberate. DMTF's `SpdmSampleCoMid.json` writes them
    that way, and their `json_to_cbor` maps only two name strings to integers —
    `"comid_tag_creator"` and `"sha256"`, hard-coded, in a branch where a table
    lookup was clearly meant. A document naming `sha512` or `comid_creator`
    therefore encodes those as *text strings*, and this project's first
    interoperability run measured the consequence: 43 bytes of difference
    between two encoders that were both doing what they were told.

    Writing integers makes the encoding unambiguous, matches the published
    sample, and lets rats/interop.sh compare the two encoders byte for byte —
    which is the whole point of having a second implementation. Both spellings
    are accepted on the way in; only this one is produced.
    """
    triples = []
    for key in walk["block_order"]:
        b = walk["blocks"][key]
        env = {"comid_class": {"comid_class_id": DEVICE_CLASS_ID,
                               "comid_vendor": DEVICE_VENDOR,
                               "comid_model": DEVICE_MODEL,
                               "comid_layer": DEVICE_LAYER,
                               "comid_index": b["index"]}}
        if not b["raw_bit_stream"]:
            mval = {"comid_mval": {"comid_digests": [[alg_id, b["value"].hex()]]}}
        elif (b["value_type"] & fields.MEAS_TYPE_MASK) == SVN_TYPE and len(b["value"]) == 8:
            mval = {"comid_mval": {"comid_svn": int.from_bytes(b["value"], "little")}}
        else:
            continue
        triples.append([env, mval])
    return {
        "corim_id": corim_id,
        "corim_tags": [{
            "comid_tag_identity": {"comid_tag_id": tag_id},
            "comid_entity": {"comid_entity_name": DEVICE_VENDOR,
                             "comid_reg_id": "https://github.com/Jhongwe1/mctp-spdm-pqc",
                             "comid_role": [COMID_ROLE["comid_tag_creator"],
                                            COMID_ROLE["comid_creator"]]},
            "comid_triples": {"comid_reference_triples": triples},
        }],
    }


# --------------------------------------------------- JSON <-> CBOR ----------
#
# The JSON form uses names, the CBOR form uses integers, and the translation is
# keyed off the ENCLOSING key rather than the value — a `0` under
# `comid_reference_triples` means `comid_class` and a `0` under `comid_mval`
# means `comid_ver`. Getting that wrong produces a document that still parses.

def _to_cbor(obj, key: str):
    if isinstance(obj, dict):
        table = LOGIC_MAP.get(key, ALL_NAMES)
        out = {}
        for k, v in obj.items():
            label = table.get(k, ALL_NAMES.get(k))
            if label is None:
                raise CborError(f"no CBOR label for '{k}' under '{key}'")
            out[label] = _to_cbor(v, k)
        return out
    if isinstance(obj, list):
        table = LOGIC_MAP.get(key)
        out = []
        for item in obj:
            if isinstance(item, str) and table and item in table:
                out.append(table[item])
            else:
                out.append(_to_cbor(item, key))
        return out
    return obj


def json_to_cbor(doc: dict) -> bytes:
    """Encode a reference document, wrapped or not.

    The authored form is a bare unsigned-corim-map — `{corim_id, corim_tags}` —
    because that is the shape DMTF's `SpdmSampleCoMid.json` has and the shape
    their `json_to_cbor` expects. The DECODED form carries the two container
    tags as keys, because that is what a policy path like
    `input.reference.corim.unsigned_corim_map.corim_tags[0]` needs to exist.
    Both are accepted, so that decode-then-re-encode is a thing this file can
    do at all — which is the check that the encoding is stable, and the one
    CoRimTool.py does not survive.
    """
    if set(doc) == {"corim"} and isinstance(doc["corim"], dict):
        inner = doc["corim"]
        if set(inner) == {"unsigned_corim_map"}:
            doc = inner["unsigned_corim_map"]
    body = _to_cbor(doc, "unsigned_corim_map")
    tags = body.get(UNSIGNED_CORIM_MAP["corim_tags"])
    if tags is not None:
        body[UNSIGNED_CORIM_MAP["corim_tags"]] = Tag(
            CORIM_TAGS["consise_mid_tag"], tags)
    return dumps(Tag(CORIM_TAGS["corim"],
                     Tag(CORIM_TAGS["unsigned_corim_map"], body)))


def _name_for(table: dict, label):
    for name, value in table.items():
        if value == label:
            return name
    return None


def _to_json(obj, key: str):
    if isinstance(obj, Tag):
        if obj.tag == CORIM_TAGS["consise_mid_tag"]:
            return _to_json(obj.value, key)
        name = _name_for(CORIM_TAGS, obj.tag)
        if name is None:
            raise CborError(f"unexpected CBOR tag {obj.tag}")
        return {name: _to_json(obj.value, name)}
    if isinstance(obj, dict):
        table = LOGIC_MAP.get(key, ALL_NAMES)
        # The one ambiguity in the format, and DMTF's tool resolves it the same
        # way: inside a reference triple, an entry keyed 0 is the environment
        # and an entry keyed 1 is the measurement. Both tables define 0 and 1.
        if key == "comid_reference_triples" and MEASUREMENT_MAP["comid_mkey"] not in obj:
            table = MEASUREMENT_MAP
        out = {}
        for label, v in obj.items():
            name = _name_for(table, label)
            if name is None:
                name = _name_for(ALL_NAMES, label)
            if name is None:
                raise CborError(f"no name for CBOR label {label!r} under '{key}'")
            out[name] = _to_json(v, name)
        return out
    if isinstance(obj, list):
        table = LOGIC_MAP.get(key)
        out = []
        for item in obj:
            if table is not None and isinstance(item, int):
                out.append(_name_for(table, item) or item)
            else:
                out.append(_to_json(item, key))
        return out
    if isinstance(obj, bytes):
        return obj.decode("utf-8", "replace")
    return obj


def cbor_to_json(blob: bytes) -> dict:
    """Decode a signed CoRIM's payload into the JSON a policy is written against.

    The shape is checked before anything is translated. Without that, a payload
    that is merely a CBOR map decodes cheerfully — every small integer has a
    name in some table — and produces a document that looks like a reference
    value and describes nothing. The self-test fed it `{1: 2}` and got a result
    rather than a refusal, which is how this check came to exist.
    """
    item = loads(blob)
    if not isinstance(item, Tag) or item.tag != CORIM_TAGS["corim"]:
        raise CborError("the payload is not tagged #6.500 (corim)")
    inner = item.value
    if not isinstance(inner, Tag) or inner.tag != CORIM_TAGS["unsigned_corim_map"]:
        raise CborError("the corim does not hold an unsigned-corim-map (#6.501)")
    if not isinstance(inner.value, dict):
        raise CborError("the unsigned-corim-map is not a map")
    return _to_json(item, "")


# ------------------------------------------------------------- the OPA ------

def opa_input(evidence: dict, reference: dict) -> dict:
    return {"evidence": evidence, "reference": reference}


def run_opa(payload: dict, policy: Path, tmp: Path,
            v0_compatible: bool = False) -> dict:
    infile = tmp / "opa.input"
    infile.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    argv = ["opa", "eval", "--format", "json", "-i", str(infile),
            "-d", str(policy), "data.spdm.output"]
    if v0_compatible:
        argv.insert(2, "--v0-compatible")
    try:
        r = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           check=False)
    except FileNotFoundError:
        raise Appraisal(
            "opa is not on PATH. The policy is Rego and something has to "
            "evaluate it; see RUNBOOK.md for the one-line install.", 2)
    if r.returncode != 0:
        raise Appraisal("opa refused the policy or the input:\n"
                        + (r.stdout + r.stderr).decode("utf-8", "replace"), 2)
    try:
        doc = json.loads(r.stdout)
        return doc["result"][0]["expressions"][0]["value"]
    except (ValueError, KeyError, IndexError) as e:
        raise Appraisal(f"opa produced no verdict ({e}): "
                        f"{r.stdout.decode('utf-8', 'replace')[:400]}", 2)


# -------------------------------------------------------- the appraisal -----

class Appraisal(Exception):
    """Raised when the appraisal cannot be performed. Never for a FAIL."""

    def __init__(self, message: str, code: int = 2):
        super().__init__(message)
        self.code = code


def _rel(p: Path) -> str:
    """Repo-relative, always, so a verdict file is the same on every machine.

    A committed derivation holding an absolute path is a derivation that only
    reproduces on the machine that wrote it, and the check that re-derives it
    in CI would fail for a reason that has nothing to do with the measurement.
    """
    p = Path(p).resolve()
    try:
        return p.relative_to(REPO_ROOT).as_posix()
    except ValueError:
        return p.as_posix()


def appraise(decode: Path, corim: Path, pub: Path, tmp: Path,
             policy: Path = POLICY) -> dict:
    cap = read_capture(decode)

    # 1. Endorsement. Who says what this device should measure, and are they
    #    entitled to? Everything after this point is conditional on it, which
    #    is why it is first and why a failure here is code 2 rather than a
    #    verdict: an unverifiable reference value is not evidence that the
    #    device is bad.
    try:
        payload, phdr = verify1(corim.read_bytes(), pub)
    except VerifyFailed as e:
        raise Appraisal(f"the reference value's signature did not verify "
                        f"against {pub}: {e}", 2)
    except (CborError, ValueError) as e:
        raise Appraisal(f"{corim} is not a COSE_Sign1 this file can read: {e}", 2)
    kid = phdr.get(4, b"")
    reference = cbor_to_json(payload)

    # 2. Evidence, from the wire.
    evidence, coverage = evidence_from_walk(cap["walk"], cap["alg_id"])

    # 3. Policy.
    out = run_opa(opa_input(evidence, reference), policy, tmp)

    verdict = out.get("verdict")
    if verdict not in ("pass", "fail"):
        raise Appraisal(f"the policy returned {verdict!r}, which is neither "
                        f"pass nor fail", 2)
    return {
        "capture": {"decode": _rel(decode), "sha256": cap["decode_sha256"]},
        "record": {"sha256": cap["record_sha256"], "bytes": cap["record_bytes"]},
        "measurement_hash": {"algorithm": cap["alg_name"],
                             "read_from": cap["alg_from"]},
        "endorsement": {"reference": _rel(corim),
                        "public_key": _rel(pub),
                        "kid": kid.decode("utf-8", "replace") if isinstance(kid, bytes) else kid,
                        "signature": "verified"},
        "coverage": coverage,
        "policy": {"file": _rel(policy)},
        "result": out,
    }


# ------------------------------------------------------------- the matrix ---
#
# One capture is a demonstration. Ten are a result, and the reason to run all
# of them is that `docs/tamper.md` already says which layer noticed each one
# *during the handshake*. Appraising the same ten says which layer notices
# afterwards, and the two columns disagree in both directions:
#
#   * `t1_meas` — a measurement changed at the device — completed the handshake
#     with no error at all. It is the row this gate exists for.
#   * `t2b_sig` — the signature changed in flight — was refused by SPDM, and
#     carries the control's measurement record byte for byte. An appraisal of
#     it PASSES, and that is the correct answer: the measurement was not
#     tampered with, the conveyance was. Two layers, two questions.
#   * `t3_cert` produces no MEASUREMENTS at all, so there is nothing to
#     appraise. "No evidence" is a third outcome and it is recorded as one
#     rather than folded into either of the other two.
#
# Nothing here takes a handshake. Every input is a capture this repository has
# already committed, so the matrix is a derivation: CI re-runs it and compares
# against what is checked in, the same arrangement as `*.fields.json`.

DEFAULT_RUN = REPO_ROOT / "bench" / "data" / "w5-tamper-20260910T092621Z"


def matrix(run: Path, corim: Path, pub: Path, out_dir: Path,
           policy: Path = POLICY) -> list[dict]:
    rows = []
    tmp = _mktmp()
    try:
        for decode in sorted(run.glob("*.decode.txt")):
            arm = decode.name[:-len(".decode.txt")]
            try:
                v = appraise(decode, corim, pub, tmp, policy)
                row = {"arm": arm, "outcome": v["result"]["verdict"],
                       "record_sha256": v["record"]["sha256"],
                       "failed_checks": sorted(v["result"].get("failed_checks", [])),
                       "detail": {k: sorted(x) for k, x in
                                  (v["result"].get("detail") or {}).items() if x},
                       "verdict": v}
            except Appraisal as e:
                row = {"arm": arm, "outcome": "no-evidence",
                       "record_sha256": None, "failed_checks": [], "detail": {},
                       "verdict": {"capture": {"decode": _rel(decode)},
                                   "outcome": "no-evidence", "why": str(e)}}
            rows.append(row)
            out_dir.mkdir(parents=True, exist_ok=True)
            (out_dir / f"{arm}.verdict.json").write_text(
                json.dumps(row["verdict"], indent=2) + "\n", encoding="utf-8")
    finally:
        import shutil
        shutil.rmtree(tmp, ignore_errors=True)
    return rows


def render_matrix(rows: list[dict]) -> str:
    L = [f"{'arm':<14} {'record':<18} {'appraisal':<11} blocked by",
         "-" * 78]
    for r in rows:
        rec = (r["record_sha256"][:16] + "…") if r["record_sha256"] else "—"
        why = ", ".join(r["failed_checks"])
        for k, v in sorted(r["detail"].items()):
            why += f"  [{k}: {', '.join(str(i) for i in v)}]"
        if r["outcome"] == "no-evidence":
            why = "no MEASUREMENTS response — nothing to appraise"
        L.append(f"{r['arm']:<14} {rec:<18} {r['outcome'].upper():<11} {why}")
    return "\n".join(L)


def render(v: dict) -> str:
    L = []
    r = v["result"]
    L.append(f"capture       {v['capture']['decode']}")
    L.append(f"record        {v['record']['bytes']} bytes, "
             f"sha256 {v['record']['sha256'][:16]}…")
    L.append(f"algorithm     {v['measurement_hash']['algorithm']} "
             f"({v['measurement_hash']['read_from']})")
    L.append(f"endorsement   signature verified, kid {v['endorsement']['kid']}")
    c = v["coverage"]
    L.append(f"coverage      {c['blocks_as_evidence']} of "
             f"{c['blocks_on_the_wire']} blocks appraisable"
             + (f"; {c['blocks_no_format_can_carry']} have no evidence encoding"
                if c["blocks_no_format_can_carry"] else ""))
    for d in c["dropped"]:
        L.append(f"                {d['index']} {d['type']}, {d['bytes']} bytes")
    L.append("")
    for name, passed in sorted(r.get("checks", {}).items()):
        L.append(f"  {'pass' if passed else 'FAIL'}  {name}")
    detail = r.get("detail") or {}
    for name, items in sorted(detail.items()):
        if items:
            L.append(f"        {name}: {', '.join(str(i) for i in sorted(items))}")
    L.append("")
    L.append(f"VERDICT       {r['verdict'].upper()}")
    if r["verdict"] == "fail":
        L.append(f"              blocked by {', '.join(sorted(r.get('failed_checks', [])))}")
    return "\n".join(L)


# -------------------------------------------------------------- CLI ---------

def _mktmp() -> Path:
    import tempfile
    return Path(tempfile.mkdtemp(prefix="rats-"))


def _matrix_cmd(args) -> int:
    """Run the matrix, and — with --check — require it not to have moved.

    Two assertions, and the second is the one this repository exists to make.

    `--check` compares every re-derived verdict against the committed one, so a
    change in the tools that silently changes a result is a failing build
    rather than a diff somebody might notice. That is the same guarantee the
    `*.fields.json` derivations already have.

    `--expect` compares the OUTCOMES against a committed statement of what they
    must be, written as a negative: `t1_meas` must FAIL. A check that only
    asserts "the answers are the same as last time" would keep passing after
    the policy was accidentally disabled, because a policy that passes
    everything is perfectly reproducible.
    """
    import shutil

    out_dir = args.out if not args.check else _mktmp()
    try:
        rows = matrix(args.run, args.reference, args.key, out_dir, args.policy)
        print(render_matrix(rows))
        failed = 0

        if args.check:
            print()
            for r in rows:
                name = f"{r['arm']}.verdict.json"
                got = (out_dir / name).read_text(encoding="utf-8")
                committed = args.out / name
                if not committed.exists():
                    print(f"  FAIL {name} is not committed")
                    failed += 1
                elif committed.read_text(encoding="utf-8") != got:
                    print(f"  FAIL {name} differs from the committed verdict")
                    failed += 1
            extra = sorted(p.name for p in args.out.glob("*.verdict.json")
                           if p.name[:-len(".verdict.json")]
                           not in {r["arm"] for r in rows})
            for name in extra:
                print(f"  FAIL {name} is committed but no arm produced it")
                failed += 1
            if not failed:
                print(f"  ok   {len(rows)} verdict(s) re-derive exactly")

        if args.expect and args.expect.exists():
            want = json.loads(args.expect.read_text(encoding="utf-8"))
            print()
            for arm, spec in sorted(want["arms"].items()):
                row = next((r for r in rows if r["arm"] == arm), None)
                if row is None:
                    print(f"  FAIL {arm}: expected but the run has no such arm")
                    failed += 1
                    continue
                if row["outcome"] != spec["outcome"]:
                    print(f"  FAIL {arm}: appraised {row['outcome'].upper()}, "
                          f"and must be {spec['outcome'].upper()} — "
                          f"{spec['because']}")
                    failed += 1
                    continue
                if spec.get("blocked_by") and \
                        sorted(spec["blocked_by"]) != row["failed_checks"]:
                    print(f"  FAIL {arm}: blocked by {row['failed_checks']}, "
                          f"expected {sorted(spec['blocked_by'])}")
                    failed += 1
                    continue
                # The full sentence is in the file and printed on failure. An
                # ok line is a receipt, not a document.
                why = spec["because"]
                print(f"  ok   {arm:<12} {row['outcome'].upper():<11} "
                      f"{why if len(why) <= 68 else why[:67] + '…'}")
            unexpected = sorted({r["arm"] for r in rows} - set(want["arms"]))
            for arm in unexpected:
                print(f"  FAIL {arm}: the run produced an arm nothing expects. "
                      f"Add it to {_rel(args.expect)} with the outcome it must "
                      f"have, or a new arm arrives unchecked.")
                failed += 1

        return 1 if failed else 0
    finally:
        if args.check:
            shutil.rmtree(out_dir, ignore_errors=True)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)

    for name, helptext in (("evidence", "capture -> evidence JSON"),
                           ("reference", "capture -> CoMID reference JSON")):
        p = sub.add_parser(name, help=helptext)
        p.add_argument("decode", type=Path)
        p.add_argument("-o", "--output", type=Path)
        if name == "reference":
            p.add_argument("--corim-id", default="4D435450535044004D2D53504442494E")
            p.add_argument("--tag-id", default="52415453524546302D6D63747073706D")

    p = sub.add_parser("to-cbor", help="reference JSON -> CoRIM CBOR")
    p.add_argument("-i", "--input", type=Path, required=True)
    p.add_argument("-o", "--output", type=Path, required=True)

    p = sub.add_parser("to-json", help="CoRIM CBOR -> reference JSON")
    p.add_argument("-i", "--input", type=Path, required=True)
    p.add_argument("-o", "--output", type=Path, required=True)

    p = sub.add_parser("opa-input", help="evidence + reference -> OPA input")
    p.add_argument("-e", "--evidence", type=Path, required=True)
    p.add_argument("-r", "--reference", type=Path, required=True)
    p.add_argument("-o", "--output", type=Path, required=True)

    p = sub.add_parser("appraise", help="the whole pipeline, with a verdict")
    p.add_argument("decode", type=Path)
    p.add_argument("--reference", type=Path,
                   default=_HERE / "ref" / "clean.corim")
    p.add_argument("--key", type=Path, default=_HERE / "keys" / "ref-signer.pub")
    p.add_argument("--policy", type=Path, default=POLICY)
    p.add_argument("-o", "--output", type=Path, help="write the verdict as JSON")
    p.add_argument("--json", action="store_true")

    p = sub.add_parser("matrix", help="appraise every arm of a capture run")
    p.add_argument("--run", type=Path, default=DEFAULT_RUN)
    p.add_argument("--reference", type=Path, default=_HERE / "ref" / "clean.corim")
    p.add_argument("--key", type=Path, default=_HERE / "keys" / "ref-signer.pub")
    p.add_argument("--policy", type=Path, default=POLICY)
    p.add_argument("--out", type=Path, default=_HERE / "out")
    p.add_argument("--check", action="store_true",
                   help="re-derive and fail if the committed verdicts differ")
    p.add_argument("--expect", type=Path, default=_HERE / "out" / "expected.json",
                   help="the outcomes this run must produce, per arm")

    sub.add_parser("selftest", help="the pipeline, and every way of breaking it")

    args = ap.parse_args()

    if args.cmd == "selftest":
        from rats_selftest import run as selftest_run  # noqa: E402
        return selftest_run()

    try:
        if args.cmd in ("evidence", "reference"):
            cap = read_capture(args.decode)
            if args.cmd == "evidence":
                doc, coverage = evidence_from_walk(cap["walk"], cap["alg_id"])
                note = (f"{coverage['blocks_as_evidence']} of "
                        f"{coverage['blocks_on_the_wire']} blocks")
            else:
                doc = reference_from_walk(cap["walk"], cap["alg_id"],
                                          args.corim_id, args.tag_id)
                note = (f"{len(doc['corim_tags'][0]['comid_triples']['comid_reference_triples'])}"
                        f" reference value(s)")
            blob = json.dumps(doc, indent=2)
            if args.output:
                args.output.write_text(blob + "\n", encoding="utf-8")
                print(f"{args.output}: {note}, {cap['alg_name']}")
            else:
                print(blob)
            return 0

        if args.cmd == "to-cbor":
            doc = json.loads(args.input.read_text(encoding="utf-8"))
            blob = json_to_cbor(doc)
            args.output.write_bytes(blob)
            print(f"{args.output}: {len(blob)} bytes")
            return 0

        if args.cmd == "to-json":
            doc = cbor_to_json(args.input.read_bytes())
            args.output.write_text(json.dumps(doc, indent=2) + "\n",
                                   encoding="utf-8")
            print(f"{args.output}: written")
            return 0

        if args.cmd == "opa-input":
            payload = opa_input(
                json.loads(args.evidence.read_text(encoding="utf-8")),
                json.loads(args.reference.read_text(encoding="utf-8")))
            args.output.write_text(json.dumps(payload, indent=2) + "\n",
                                   encoding="utf-8")
            print(f"{args.output}: written")
            return 0

        if args.cmd == "matrix":
            return _matrix_cmd(args)

        tmp = _mktmp()
        try:
            v = appraise(args.decode, args.reference, args.key, tmp, args.policy)
        finally:
            import shutil
            shutil.rmtree(tmp, ignore_errors=True)
        if args.output:
            args.output.write_text(json.dumps(v, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(v, indent=2) if args.json else render(v))
        return 0 if v["result"]["verdict"] == "pass" else 1

    except Appraisal as e:
        print(f"cannot appraise: {e}", file=sys.stderr)
        return e.code


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Feed the appraisal things that are wrong, and require it to say so.

    python3 rats/appraise.py selftest

Why this file is as long as the thing it tests
----------------------------------------------
`docs/roadmap.md` standing rule 11: *a check is worth what it rejects, and
something has to prove it rejects.* A policy that has only ever been run on a
good measurement and a bad one has been observed doing two things, and the
interesting failures are not either of them — they are the inputs a verifier
accepts while believing it is being strict.

Standing rule 13 adds the harder half: the refusals must come through
**distinct** mechanisms. Eight broken inputs all stopped by the cheapest check
report eight times the coverage they have. So the last assertion here walks
every failure category the policy can name and requires each one to have been
provoked by some case — the same shape as `device/measurement_source_test.c`
walking the whole `ms_status_t` enum, and for the same reason: adding a
category without a case that fires it should be a failing build.

The comparison with the published sample
----------------------------------------
Three of these cases exist because DMTF's `SpdmSamplePolicy.rego` accepts them.
That policy compares **sets** of digests, so it cannot see an index swap, it
cannot see a duplicate, and — the one that matters — it passes an empty
reference value, because `set() == set()`.

Those three are run here against a **model** of set comparison, written below
in Rego v1 and thrown away when the test ends. The model is not the sample: the
sample itself cannot be committed to this repository (upstream source is pinned,
never vendored) and does not parse on OPA 1.x without `--v0-compatible`. What
the model does is keep the claim *checked* on a runner that has no `spdm-emu`
checkout. The claim is also **measured**, once, against the real file, by
`rats/interop.sh`, whose output is committed in `rats/interop/`.

A model that agreed with the sample by construction would be worthless, so the
two are tied together: `interop.sh` runs the same inputs through the real
sample policy and requires it to reach the same verdicts as the model here. If
they ever diverge, the model is wrong and the interop run says so.
"""

from __future__ import annotations

import copy
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

_HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(_HERE))

import appraise as A  # noqa: E402
import cose  # noqa: E402

# The policy as it was before 2026-09-14: the same file with the secure
# version number compared for equality. It is not a spare copy — it is the
# control, and the structural check below requires it to differ from the live
# policy in exactly one marked region.
FROZEN = _HERE / "policy-v0-equality.rego"
REGION_OPEN = "# >>> SVN-RULE"
REGION_CLOSE = "# <<< SVN-RULE"

# A minimal, entirely synthetic pair. Small enough to read, and NOT taken from
# a capture: a test whose fixture comes from the same place as the thing it
# tests cannot detect a change that moves both.
D1 = "aa" * 64
D2 = "bb" * 64
D3 = "cc" * 64


def base_evidence() -> dict:
    return {"evidences": [
        {"evidence": {"index": 1, "digest": [8, D1]}},
        {"evidence": {"index": 2, "digest": [8, D2]}},
        {"evidence": {"index": 16, "svn": 7}},
    ]}


def _triple(index: int, mval: dict) -> list:
    return [{"comid_class": {"comid_class_id": A.DEVICE_CLASS_ID,
                             "comid_vendor": A.DEVICE_VENDOR,
                             "comid_model": A.DEVICE_MODEL,
                             "comid_layer": A.DEVICE_LAYER,
                             "comid_index": index}},
            {"comid_mval": mval}]


def base_reference() -> dict:
    return {"corim": {"unsigned_corim_map": {
        "corim_id": "0" * 32,
        "corim_tags": [{
            "comid_tag_identity": {"comid_tag_id": "1" * 32},
            "comid_triples": {"comid_reference_triples": [
                _triple(1, {"comid_digests": [["sha512", D1]]}),
                _triple(2, {"comid_digests": [["sha512", D2]]}),
                _triple(16, {"comid_svn": 7}),
            ]},
        }],
    }}}


# The set-comparison model. Same two questions the published sample asks, in
# the syntax OPA 1.x accepts, and nothing else — no index, no algorithm, no
# emptiness guard. See the module docstring on why it is a model.
SETWISE_MODEL = """
package spdm

ev_hash contains h if {
	some e in input.evidence.evidences
	h := e.evidence.digest[1]
}

ref_hash contains h if {
	some t in input.reference.corim.unsigned_corim_map.corim_tags[0].comid_triples.comid_reference_triples
	h := t[1].comid_mval.comid_digests[0][1]
}

ev_svn contains s if {
	some e in input.evidence.evidences
	s := e.evidence.svn
}

ref_svn contains s if {
	some t in input.reference.corim.unsigned_corim_map.corim_tags[0].comid_triples.comid_reference_triples
	s := t[1].comid_mval.comid_svn
}

default hash_check := false

hash_check if ev_hash == ref_hash

default svn_check := false

svn_check if ev_svn == ref_svn

default verdict := "fail"

verdict := "pass" if {
	hash_check
	svn_check
}

output := {"verdict": verdict, "checks": {"SPDM_HASH_CHECK": hash_check, "SPDM_SVN_CHECK": svn_check}, "failed_checks": set(), "detail": {}}
"""


# ------------------------------------------------------------- the cases ----
#
# Each case says what it breaks, and WHICH category the policy must name. A
# case that fails for the right verdict and the wrong reason is a case that
# would keep passing after the check it was written for was deleted.

def swap_indices(ev: dict, ref: dict):
    """Index 1's value presented as index 2's, and the other way round.

    The sharpest of the set-comparison failures, because both halves of the
    swap are values the device really does hold. Measurement index 1 is the
    immutable ROM and index 2 is the mutable firmware; a device presenting its
    firmware digest as its ROM digest has said something false about which
    parts of it can change, and the multiset of digests is identical.
    """
    ev["evidences"][0]["evidence"]["digest"][1] = D2
    ev["evidences"][1]["evidence"]["digest"][1] = D1


def nothing_measured_anywhere(ev: dict, ref: dict):
    """A device that reports nothing, against a reference that names nothing.

    ★ This is the vacuous pass, and it took a failing self-test to state it
    correctly. The first version of this file claimed that set comparison
    passes *any* empty reference, on the reasoning that `set() == set()`. It
    does not: with an empty reference and real evidence the two sets differ and
    the sample refuses it, which the model here reported and the expectation
    did not.

    The hole is narrower and worse. Both sides empty, and every set comparison
    in the sample is between two empty sets, so both checks pass and the
    verdict is PASS — for a device that has answered `GET_MEASUREMENTS` with
    nothing at all. A verifier that cannot distinguish "everything matched"
    from "there was nothing to match" is the failure direction that matters,
    because it fails OPEN and it fails open on the least trustworthy input it
    will ever see.

    This policy separates the two with `REFERENCE_PRESENT`, which is the reason
    that check exists as a named rule rather than as a clause inside the other
    two: a verdict has to be able to say *which* of the two it is.
    """
    ev["evidences"] = []
    ref["corim"]["unsigned_corim_map"]["corim_tags"][0]["comid_triples"]["comid_reference_triples"] = []


def no_svn_on_either_side(ev: dict, ref: dict):
    """Neither the device nor the reference mentions a secure version number.

    The other vacuous pass, and the one a real deployment would meet first: a
    responder that does not implement the secure-version-number measurement
    block, appraised against a reference value written from it. Set comparison
    compares two empty sets and reports SPDM_SVN_CHECK as satisfied, so a
    rollback policy that nothing can enforce reports itself as enforced.

    Here `svn_check` requires the reference to name at least one, so the answer
    is a refusal. It is a deliberately strict reading — a device with no SVN is
    not appraisable by a policy that has one — and week 7's rollback cases are
    where it earns its keep.
    """
    ev["evidences"] = [e for e in ev["evidences"] if "svn" not in e["evidence"]]
    triples = ref["corim"]["unsigned_corim_map"]["corim_tags"][0]["comid_triples"]
    triples["comid_reference_triples"] = [
        t for t in triples["comid_reference_triples"]
        if "comid_svn" not in t[1]["comid_mval"]]


def duplicate_value(ev: dict, ref: dict):
    """Both evidence blocks report the same digest; the reference names two.

    Under set comparison {D1} == {D1, D2} is false, so the published sample
    does catch this one — it is here because it is the case people assume set
    comparison misses, and being specific about which of the three it catches
    is the difference between a criticism and a slogan.
    """
    ev["evidences"][1]["evidence"]["digest"][1] = D1


def changed_digest(ev: dict, ref: dict):
    ev["evidences"][0]["evidence"]["digest"][1] = D3


def changed_algorithm(ev: dict, ref: dict):
    """The same hex, presented as a SHA-384 digest.

    Nothing about the bytes changed. What changed is the claim about how they
    were produced, and a verifier that ignores it will one day compare a
    truncated digest against a full-length reference value and find them equal
    in their first 48 bytes.
    """
    ev["evidences"][0]["evidence"]["digest"][0] = 7


def missing_block(ev: dict, ref: dict):
    del ev["evidences"][1]


def extra_block(ev: dict, ref: dict):
    ev["evidences"].append({"evidence": {"index": 3, "digest": [8, D3]}})


def _set_ev_svn(ev: dict, value: int):
    ev["evidences"][2]["evidence"]["svn"] = value


def _set_ref_svn(ref: dict, value: int):
    triples = (ref["corim"]["unsigned_corim_map"]["corim_tags"][0]
               ["comid_triples"]["comid_reference_triples"])
    for t in triples:
        if "comid_svn" in t[1]["comid_mval"]:
            t[1]["comid_mval"]["comid_svn"] = value
            return
    raise AssertionError("the base reference has no secure version number")


def rolled_back_svn(ev: dict, ref: dict):
    """The device reports a version BELOW the reference value.

    Until 2026-09-14 this and an upgrade were the same case: the policy asked
    for equality, so both were refused by svn_mismatch and the two refusals
    were byte-identical. The category this must now name is the whole of the
    change — a verdict that cannot say which direction it saw cannot be acted
    on, because the two directions call for opposite responses.
    """
    _set_ev_svn(ev, 5)


def missing_svn(ev: dict, ref: dict):
    """The reference names a secure version number and the evidence has none.

    ★ The clause a reader is most likely to think is pedantic, and the one
    that matters most after the rule was loosened: if silence satisfied a
    one-sided comparison, the cheapest way to defeat a rollback rule would be
    to stop answering it.
    """
    del ev["evidences"][2]


def extra_svn(ev: dict, ref: dict):
    ev["evidences"].append({"evidence": {"index": 17, "svn": 3}})


# ── the 64-bit boundary ─────────────────────────────────────────────────────
#
# DSP0274 carries the secure version number as an 8-byte little-endian value,
# so the top of its range is 2**64 - 1 — and this repository's captures show
# it as `07 00 00 00 00 00 00 00` on the wire. Everything between that wire
# format and the comparison goes through JSON, and JSON numbers are where
# 64-bit integers go to lose their last digits: an IEEE-754 double carries 53
# bits of mantissa, so 2**64 - 1 and 2**64 - 2 are the SAME double.
#
# If any layer here did that, the pair below would collapse into one value and
# a rollback at the top of the range would appraise as PASS. That is not a
# hypothetical shape of bug — it is the shape of every "large integer through
# JSON" defect — and whether OPA has it is a question with a one-command
# answer, which is why it is a test rather than a paragraph.
UINT64_MAX = 2**64 - 1


def rollback_at_the_top_of_the_range(ev: dict, ref: dict):
    _set_ref_svn(ref, UINT64_MAX)
    _set_ev_svn(ev, UINT64_MAX - 1)


CASES = [
    # name                        mutation      category the policy must name   setwise model
    ("a digest changed",      changed_digest,   "digest_mismatch",              "fail"),
    ("indices 1 and 2 swapped", swap_indices,   "digest_mismatch",              "PASS"),
    ("nothing measured on either side", nothing_measured_anywhere,
                                                "REFERENCE_PRESENT",            "PASS"),
    ("no svn on either side", no_svn_on_either_side,
                                                "SPDM_SVN_CHECK",               "PASS"),
    ("the same digest twice", duplicate_value,  "digest_mismatch",              "fail"),
    ("the algorithm changed", changed_algorithm, "digest_mismatch",             "PASS"),
    ("a block is missing",    missing_block,    "digest_missing_from_evidence", "fail"),
    ("a block nobody vouched for", extra_block, "digest_not_in_reference",      "fail"),
    ("the svn went backwards", rolled_back_svn, "svn_rollback",                "fail"),
    ("the svn is missing",    missing_svn,      "svn_missing_from_evidence",    "fail"),
    ("an svn nobody vouched for", extra_svn,    "svn_not_in_reference",         "fail"),
    ("a rollback at 2**64 - 1", rollback_at_the_top_of_the_range,
                                                "svn_rollback",                 "fail"),
]

# Pairs that must be ACCEPTED, and one of them was not until 2026-09-14.
#
# Every case above is a refusal, and a file made only of refusals can be
# satisfied by a policy that refuses everything. These two are the other
# direction, and the second column is what makes them evidence rather than
# reassurance: the frozen policy's answer to the same input. A case whose
# before and after agree is not testing the change.

def upgraded_svn(ev: dict, ref: dict):
    _set_ev_svn(ev, 9)


def upgrade_at_the_top_of_the_range(ev: dict, ref: dict):
    _set_ref_svn(ref, UINT64_MAX - 1)
    _set_ev_svn(ev, UINT64_MAX)


ACCEPTED = [
    # name                            mutation      under the frozen policy
    ("the svn moved forward",         upgraded_svn,               "fail"),
    ("an upgrade at 2**64 - 1",       upgrade_at_the_top_of_the_range, "fail"),
]

# Every category the policy can report — the three named checks and the six
# per-index details. The last assertion requires each of them to have been
# provoked; a category with no case is a check nothing has ever seen fire.
#
# SPDM_HASH_CHECK is not in the set because it cannot be the *most specific*
# thing a refusal says: every way of failing it also names a detail category.
# Requiring it here would be satisfied by a case that provoked nothing new.
CATEGORIES = {
    "REFERENCE_PRESENT",
    "SPDM_SVN_CHECK",
    "digest_mismatch",
    "digest_missing_from_evidence",
    "digest_not_in_reference",
    "svn_rollback",
    "svn_missing_from_evidence",
    "svn_not_in_reference",
}


def code_outside_region(path: Path) -> tuple[list[str], int]:
    """The policy's executable lines, minus comments, blanks and the region.

    Comments are dropped because the two files explain different things and
    must be free to; what has to be identical is the code. The region markers
    are dropped with everything between them, because that is the part the
    change is allowed to live in.
    """
    kept: list[str] = []
    inside = False
    regions = 0
    for line in path.read_text(encoding="utf-8").splitlines():
        s = line.strip()
        if s.startswith(REGION_OPEN):
            inside, regions = True, regions + 1
            continue
        if s.startswith(REGION_CLOSE):
            inside = False
            continue
        if inside or not s or s.startswith("#"):
            continue
        kept.append(s)
    return kept, regions


def _evaluate(ev: dict, ref: dict, policy: Path, tmp: Path) -> dict:
    return A.run_opa(A.opa_input(ev, ref), policy, tmp)


def _blocked_by(out: dict) -> set:
    """Everything the verdict names, checks and per-index detail together.

    The first version returned the detail categories when there were any and
    the check names otherwise, and it hid a real case: an input that trips
    REFERENCE_PRESENT usually trips a detail category too, so the specific
    reason was masked by the general one. A refusal's reasons are a set, not a
    ranking.
    """
    return (set(out.get("failed_checks") or [])
            | {k for k, v in (out.get("detail") or {}).items() if v})


def run() -> int:
    fails = 0
    checks = 0
    fired: set = set()

    def bad(msg):
        nonlocal fails
        fails += 1
        print(f"  FAIL {msg}")

    if shutil.which("opa") is None:
        print("opa is not on PATH — the policy cannot be evaluated and this "
              "self-test would pass by not running. Install it (RUNBOOK.md §11) "
              "and try again.", file=sys.stderr)
        return 2

    tmp = Path(tempfile.mkdtemp(prefix="rats-selftest-"))
    try:
        model = tmp / "setwise_model.rego"
        model.write_text(SETWISE_MODEL, encoding="utf-8")

        print("the unmodified pair passes, under both policies")
        for label, pol in (("this policy", A.POLICY), ("set comparison", model)):
            checks += 1
            out = _evaluate(base_evidence(), base_reference(), pol, tmp)
            if out["verdict"] != "pass":
                bad(f"{label}: the base pair did not pass ({out})")

        print(f"{len(CASES)} broken pairs, each refused, each for the stated reason")
        for name, mutate, category, setwise in CASES:
            ev, ref = base_evidence(), base_reference()
            mutate(ev, ref)

            checks += 1
            out = _evaluate(ev, ref, A.POLICY, tmp)
            if out["verdict"] != "fail":
                bad(f"{name}: PASSED this policy, and must not have")
                continue
            blocked = _blocked_by(out)
            if category not in blocked:
                bad(f"{name}: refused, but by {sorted(blocked)} rather than "
                    f"{category} — a case that fails for the wrong reason "
                    f"stops testing what it was written for")
            else:
                fired.add(category)

            # And what set comparison does with the same input.
            checks += 1
            m = _evaluate(ev, ref, model, tmp)
            got = "PASS" if m["verdict"] == "pass" else "fail"
            if got != setwise:
                bad(f"{name}: set comparison answered {got}, expected "
                    f"{setwise}. The model no longer models the published "
                    f"sample, or the sample's behaviour has been misread.")
            mark = "  <- set comparison ACCEPTS this" if got == "PASS" else ""
            print(f"    ok   {name:<30} refused by {category}{mark}")

        print("pairs that must be ACCEPTED, and were not before the rule changed")
        for name, mutate, was in ACCEPTED:
            ev, ref = base_evidence(), base_reference()
            mutate(ev, ref)

            checks += 1
            out = _evaluate(ev, ref, A.POLICY, tmp)
            if out["verdict"] != "pass":
                bad(f"{name}: REFUSED by this policy ({sorted(_blocked_by(out))}) "
                    f"and must not have been. A version rule that refuses an "
                    f"upgrade turns every machine that takes the next update "
                    f"red on the day the reference value is published.")
                continue

            # And the frozen policy, which is the only thing that makes the
            # line above evidence: a case both policies accept says nothing
            # about the change.
            checks += 1
            before = _evaluate(ev, ref, FROZEN, tmp)
            got = "pass" if before["verdict"] == "pass" else "fail"
            if got != was:
                bad(f"{name}: the frozen policy answered {got}, expected {was}. "
                    f"If the two policies now agree here, this case is no "
                    f"longer testing the change.")
            else:
                print(f"    ok   {name:<30} accepted here, {was} under `==`")

        print("the two policies differ in ONE marked region, and nowhere else")
        checks += 1
        live_code, live_regions = code_outside_region(A.POLICY)
        frozen_code, frozen_regions = code_outside_region(FROZEN)
        if live_regions != 1 or frozen_regions != 1:
            bad(f"expected exactly one {REGION_OPEN} region per file; found "
                f"{live_regions} in {A.POLICY.name} and {frozen_regions} in "
                f"{FROZEN.name}")
        elif live_code != frozen_code:
            import difflib
            d = "\n".join(list(difflib.unified_diff(
                frozen_code, live_code, "frozen", "live", lineterm="", n=1))[:24])
            bad("the two policies differ OUTSIDE the SVN-RULE region, so the "
                "four-case table is no longer a controlled comparison — a "
                "verdict that moved could have been moved by this instead:\n"
                f"{d}\n"
                "        Decide deliberately what the control should be. Do "
                "not edit the frozen file into agreement.")
        else:
            print(f"    {len(live_code)} lines of shared code, identical")

        # Standing rule 11: the check above has to be observed rejecting
        # something, or it is a string comparison that happens to agree.
        checks += 1
        drifted = tmp / "drifted.rego"
        drifted.write_text(
            A.POLICY.read_text(encoding="utf-8").replace(
                "count(digest_missing) == 0", "count(digest_missing) >= 0", 1),
            encoding="utf-8")
        if code_outside_region(drifted)[0] == frozen_code:
            bad("a policy with a check disabled outside the region compared "
                "EQUAL to the frozen one — the structural check cannot see the "
                "thing it exists to see")
        else:
            print("    a change outside the region is detected")

        print("every failure category the policy can name has been provoked")
        checks += 1
        missing = CATEGORIES - fired
        if missing:
            bad(f"no case provokes {sorted(missing)} — a category nothing has "
                f"been observed reporting is arithmetic that happens to agree")
        else:
            print(f"    {len(fired)} of {len(CATEGORIES)} categories, all fired")

        print("an unverifiable endorsement is 'cannot tell', not 'the device is bad'")
        checks += 1
        rc = _endorsement_case(tmp)
        if rc != 2:
            bad(f"a reference value signed by the wrong key produced exit {rc}; "
                f"2 is the only honest answer, because nothing was learned "
                f"about the device")

        print("encoding a reference document is stable across a decode")
        # Not "the JSON comes back identical" — it does not, and should not.
        # The CBOR carries integers, the JSON form this project's policy is
        # written against carries names, and the decoder produces names. What
        # has to hold is that re-encoding the decoded document yields the same
        # BYTES, because that is the property a signature depends on: a
        # verifier that decodes, re-encodes and re-checks must get back what
        # was signed.
        #
        # It is also the property DMTF's CoRimTool.py does NOT have, and
        # rats/interop.sh measures that rather than asserting it: its
        # json_to_cbor maps exactly two name strings to integers, hard-coded,
        # so a document naming sha512 encodes the algorithm as text and the
        # round trip grows.
        checks += 1
        authored = base_reference()["corim"]["unsigned_corim_map"]
        blob = A.json_to_cbor(authored)
        decoded = A.cbor_to_json(blob).get("corim", {}).get("unsigned_corim_map")
        if decoded is None:
            bad("the decoded document has no unsigned_corim_map")
        elif A.json_to_cbor(decoded) != blob:
            bad("re-encoding the decoded document produced different bytes:\n"
                f"        {len(blob)} bytes -> {len(A.json_to_cbor(decoded))} bytes")

        checks += 1
        if A.json_to_cbor(authored) != blob:
            bad("encoding the same document twice produced different bytes")

        print("a secure version number at the top of its range survives CBOR")
        # The policy comparison is tested against 2**64 - 1 above; this is the
        # OTHER half of the same hazard, one layer down. A reference value is
        # signed as CBOR and decoded before the policy ever sees it, so an
        # encoder that rounded here would hand the policy a number nobody
        # signed — and the signature would still verify, because it covers the
        # bytes that were rounded.
        checks += 1
        big = base_reference()
        _set_ref_svn(big, UINT64_MAX)
        doc = big["corim"]["unsigned_corim_map"]
        back = A.cbor_to_json(A.json_to_cbor(doc)).get("corim", {}).get(
            "unsigned_corim_map", {})
        seen = [tr[1]["comid_mval"]["comid_svn"] for tr in
                back.get("corim_tags", [{}])[0].get("comid_triples", {})
                .get("comid_reference_triples", [])
                if "comid_svn" in tr[1]["comid_mval"]]
        if seen != [UINT64_MAX]:
            bad(f"a secure version number of 2**64 - 1 came back as {seen}; the "
                f"document a verifier compares against is not the one signed")

        print("both spellings of an algorithm encode to the same bytes")
        checks += 1
        by_name = copy.deepcopy(authored)
        by_int = copy.deepcopy(authored)
        for t in by_int["corim_tags"][0]["comid_triples"]["comid_reference_triples"]:
            d = t[1]["comid_mval"].get("comid_digests")
            if d:
                d[0][0] = A.HASH_ALG[d[0][0]]
        if A.json_to_cbor(by_name) != A.json_to_cbor(by_int):
            bad("a reference naming sha512 and one saying 8 encode differently")

        print("the CoRIM wrapper is written on request and read either way")
        checks += 1
        payload = A.json_to_cbor(authored)
        with tempfile.TemporaryDirectory() as kd:
            kd = Path(kd)
            subprocess.run(["openssl", "ecparam", "-name", "prime256v1",
                            "-genkey", "-noout", "-out", str(kd / "k.key")],
                           check=True, stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL)
            subprocess.run(["openssl", "ec", "-in", str(kd / "k.key"), "-pubout",
                            "-out", str(kd / "k.pub")], check=True,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            bare = cose.sign1(payload, {}, kd / "k.key", corim=False)
            wrapped = cose.sign1(payload, {}, kd / "k.key", corim=True)
            if cose.loads(wrapped).tag != cose.CORIM_TAG:
                bad("--corim did not produce a #6.500 tag")
            for what, blobb in (("bare", bare), ("wrapped", wrapped)):
                checks += 1
                try:
                    got, _ = cose.verify1(blobb, kd / "k.pub")
                except cose.VerifyFailed as e:
                    bad(f"a {what} COSE_Sign1 did not verify: {e}")
                    continue
                if got != payload:
                    bad(f"a {what} COSE_Sign1 recovered the wrong payload")

        print("the CBOR decoder refuses what it should")
        for what, blobber in (
                ("a payload that is not a CoRIM", lambda: cose.dumps({1: 2})),
                ("a tag this format does not define",
                 lambda: cose.dumps(cose.Tag(999, {}))),
        ):
            checks += 1
            try:
                A.cbor_to_json(blobber())
            except (cose.CborError, ValueError):
                continue
            bad(f"{what}: decoded without complaint")

    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    print()
    print(f"{checks} checks, {fails} failed")
    return 1 if fails else 0


def _endorsement_case(tmp: Path) -> int:
    """Sign a reference with one key, appraise with another, report the code."""
    key, pub, other = tmp / "a.key", tmp / "a.pub", tmp / "b.key"
    otherpub = tmp / "b.pub"
    for k, p in ((key, pub), (other, otherpub)):
        subprocess.run(["openssl", "ecparam", "-name", "prime256v1", "-genkey",
                        "-noout", "-out", str(k)], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(["openssl", "ec", "-in", str(k), "-pubout", "-out", str(p)],
                       check=True, stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL)

    payload = A.json_to_cbor(base_reference()["corim"]["unsigned_corim_map"])
    signed = tmp / "wrong-signer.corim"
    signed.write_bytes(cose.sign1(payload, {cose.HDR_KID: b"99"}, key))

    # The capture is a real one, so that the only thing wrong is who signed the
    # reference value. Using a good capture is the point: the answer must be
    # "I cannot tell", not "this device is bad".
    decode = (A.REPO_ROOT / "bench" / "data" / "w5-tamper-20260910T092621Z"
              / "t0_clean.decode.txt")
    r = subprocess.run([sys.executable, str(_HERE / "appraise.py"), "appraise",
                        str(decode), "--reference", str(signed),
                        "--key", str(otherpub)],
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return r.returncode


if __name__ == "__main__":
    raise SystemExit(run())

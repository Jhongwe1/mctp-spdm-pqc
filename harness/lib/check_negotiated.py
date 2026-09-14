#!/usr/bin/env python3
"""Require a capture's negotiated algorithms to be the ones an arm asked for.

    python3 harness/lib/check_negotiated.py <arm>.fields.json "Asym=ECDSA_P384;KEM=;MutAuth=off"

Exit 0 when every declared expectation holds, 1 when any does not. Line 1 of
stdout is a compact summary of what was actually negotiated, suitable for a
column in a results table; anything after it names a disagreement.

Why this exists
---------------
Requesting an algorithm and negotiating one are different events. SPDM
negotiates each group independently and a responder that cannot do what was
asked does not fail the handshake — it selects something else. A cost table
built from the flags would then be wrong with no symptom anywhere: the
handshake completes, the requester exits 0, and the number in the table
describes a configuration that never ran.

2026-08-17 in LOG.md is what that costs. A post-quantum arm pinned --pqc_asym
and left --req_pqc_asym at its default of three algorithms; the responder chose
ML_DSA_87 for the requester's own signature, so the capture held two different
post-quantum signature algorithms and nothing in the run said so.

So every group is checked, not the interesting one. `docs/roadmap.md` standing
rule 8: independent variables are verified, not assumed, and ENUMERATED rather
than spot-checked. Confirming one field of a pair is not confirming the
variable.

The expectation syntax
----------------------
Semicolon-separated `Key=Value`, where Key is either one of the algorithm
groups in `algorithms.negotiated` or one of the two derived facts below, and
Value is a comma-separated list. An EMPTY value means "nothing was negotiated
in this group", which is a real and checkable state — it is what `--asym NONE`
must produce, and leaving it out of the expectation would be the one omission
that lets a classical algorithm survive into a post-quantum arm.

    MutAuth=off   the capture must carry no encapsulated exchange at all
    ReqChain=0    no requester certificate chain bytes on the wire

Those two are not algorithm groups; they are the observable consequence of
--mut_auth, --basic_mut_auth, --req_asym and --req_pqc_asym being off, and they
are checked separately because four flags that each independently switch the
same traffic back on is four chances to have written the list from memory.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

# Everything the ALGORITHMS response negotiates separately. A key missing from
# an expectation string is NOT checked — deliberately, so an arm can decline to
# constrain something — but the summary prints all of them, so an unconstrained
# group that moved is still visible to a reader.
GROUPS = ["Hash", "MeasHash", "Asym", "PqcAsym", "DHE", "KEM", "AEAD",
          "ReqAsym", "ReqPqcAsym", "KeySchedule", "MeasSpec", "OtherParam"]

DERIVED = {"MutAuth", "ReqChain"}


def as_list(v) -> list[str]:
    """Normalise a negotiated field.

    Three spellings mean "nothing": absent, null and []. They are not the same
    observation — null is the field never appearing in the response at all,
    while [] is the field appearing with no bits set — so the summary keeps
    them apart and only the comparison folds them together.
    """
    if v is None:
        return []
    if isinstance(v, list):
        return [str(x) for x in v]
    return [str(v)]


def summarise(neg: dict, mutual: dict) -> str:
    parts = []
    for g in GROUPS:
        if g not in neg:
            continue
        got = as_list(neg[g])
        parts.append(f"{g}={','.join(got) if got else '-'}")
    if mutual.get("encapsulated_exchange"):
        parts.append("MutAuth=ON")
    return " ".join(parts)


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__.strip().splitlines()[2], file=sys.stderr)
        return 2

    doc = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    neg = (doc.get("algorithms") or {}).get("negotiated") or {}
    mutual = doc.get("mutual_auth") or {}
    cert = doc.get("certificate") or {}

    print(summarise(neg, mutual))

    problems: list[str] = []
    for clause in sys.argv[2].split(";"):
        clause = clause.strip()
        if not clause:
            continue
        if "=" not in clause:
            problems.append(f"malformed expectation {clause!r} — want Key=Value")
            continue
        key, want_raw = clause.split("=", 1)
        key = key.strip()
        want = [x for x in (w.strip() for w in want_raw.split(",")) if x]

        if key == "MutAuth":
            on = bool(mutual.get("encapsulated_exchange"))
            if want_raw.strip() == "off" and on:
                problems.append(
                    "MutAuth: the capture carries an encapsulated exchange of "
                    f"{mutual.get('encapsulated_message_count')} messages and "
                    f"{mutual.get('requester_chain_bytes')} bytes of requester "
                    "certificate chain. Four flags switch this on independently "
                    "(--mut_auth, --basic_mut_auth, --req_asym, --req_pqc_asym); "
                    "at least one of them is not what this arm declared")
            elif want_raw.strip() == "on" and not on:
                problems.append("MutAuth: no encapsulated exchange, and this "
                                "arm declared one")
            continue

        if key == "ReqChain":
            got_n = cert.get("requester_slot0_bytes") or 0
            if str(got_n) != want_raw.strip():
                problems.append(f"ReqChain: {got_n} bytes of requester chain on "
                                f"the wire, expected {want_raw.strip()}")
            continue

        if key not in GROUPS:
            problems.append(f"{key}: not an algorithm group this capture reports "
                            f"(have: {', '.join(GROUPS)})")
            continue
        if key not in neg:
            problems.append(f"{key}: the decode has no negotiated value for this "
                            f"group at all")
            continue

        got = as_list(neg[key])
        if sorted(got) != sorted(want):
            shown_got = ",".join(got) if got else (
                "<absent>" if neg[key] is None else "<empty>")
            shown_want = ",".join(want) if want else "<nothing>"
            problems.append(
                f"{key}: negotiated {shown_got}, asked for {shown_want}"
                + ("  — a flag was requested and something else was selected; "
                   "the number this arm produces describes the wrong "
                   "configuration" if got and want else ""))

    for p in problems:
        print(p)
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())

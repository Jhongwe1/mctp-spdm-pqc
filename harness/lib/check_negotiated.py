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
    Chunk=off|on  whether SPDM's chunking layer carried anything
    DTS=4608      the DataTransferSize BOTH ends advertised, in bytes

The first two are not algorithm groups; they are the observable consequence of
--mut_auth, --basic_mut_auth, --req_asym and --req_pqc_asym being off, and they
are checked separately because four flags that each independently switch the
same traffic back on is four chances to have written the list from memory.

`Chunk` and `DTS` arrived on 2026-09-14 for the DataTransferSize sweep, and they
are the same rule applied to the transport. DataTransferSize is the sweep's
independent variable, `--data_transfer_size` is a flag, and a flag is a request:
if a build ignores it — which every unpatched build does, since upstream has no
such flag — the sweep silently becomes six identical runs. So the value is read
back out of the GET_CAPABILITIES and CAPABILITIES messages and required to be
the one asked for, on BOTH ends, which additionally catches the case where the
flag reached one binary and not the other.
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

DERIVED = {"MutAuth", "ReqChain", "Chunk", "DTS"}

# Every message type SPDM's chunking layer uses. Counted rather than inspected:
# whether the layer ran at all is the question, and one message of any of the
# four answers it.
CHUNK_COUNTS = ("chunk_get_count", "chunk_response_count",
                "chunk_send_count", "chunk_send_ack_count")


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
    chunking = doc.get("chunking") or {}
    caps = doc.get("capabilities") or {}

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

        if key == "Chunk":
            present = [k for k in CHUNK_COUNTS if k in chunking]
            if not present:
                problems.append(
                    "Chunk: the decode reports none of "
                    f"{', '.join(CHUNK_COUNTS)} — nothing was checked, which is "
                    "the failure mode this clause exists to avoid")
                continue
            total = sum(int(chunking.get(k) or 0) for k in present)
            asked = want_raw.strip()
            if asked == "off" and total:
                problems.append(
                    f"Chunk: the capture carries {total} chunking messages and "
                    "this arm declared none. Chunking needs CHUNK_CAP at BOTH "
                    "ends, so an arm that removed it from one end and still "
                    "chunked did not remove what it thought it did")
            elif asked == "on" and not total:
                problems.append(
                    "Chunk: no chunking messages, and this arm declared some. "
                    "Either the message fit inside DataTransferSize after all, "
                    "or CHUNK_CAP is missing from an end")
            elif asked not in ("off", "on"):
                problems.append(f"Chunk: want off or on, got {asked!r}")
            continue

        if key == "DTS":
            # Both ends, because the flag is passed to both and a build that
            # honoured it in one binary only would otherwise pass.
            asked = want_raw.strip()
            for side in ("requester", "responder"):
                got_n = (caps.get(side) or {}).get("data_transfer_size")
                if got_n is None:
                    problems.append(f"DTS: the decode has no {side} "
                                    "DataTransferSize to check")
                elif str(got_n) != asked:
                    problems.append(
                        f"DTS: the {side} advertised {got_n} bytes, and this arm "
                        f"asked for {asked}. --data_transfer_size is a request; "
                        "a build without transport/data-transfer-size.patch "
                        "parses nothing and advertises its compile-time value")
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

#!/usr/bin/env python3
"""Read protocol fields back out of a decoded SPDM capture.

    python3 harness/fields.py <run>/walkthrough.decode.txt            # table
    python3 harness/fields.py <run>/walkthrough.decode.txt --json     # machine
    python3 harness/fields.py --check docs/handshake-walkthrough.md   # assert

Why this exists
---------------
Two lessons from this repository's own log, one week apart, are the same
lesson: a fact that is only ever *stated* has nothing checking it, while a fact
that is *computed* is checked every run — and where the two overlap, the stated
one is the one that rots. A field-by-field walkthrough is nothing but stated
facts. Left as prose it is a document that will disagree with its own capture
within a month and give no sign of it.

So the numbers in `docs/handshake-walkthrough.md` are not typed in. They are
marked up, and `--check` re-derives each one from the decode file the document
names. `harness/verify_repo.sh` runs that check, which means the same job that
guards the scope statement also guards every byte count in the walkthrough. A
wrong number is now a red build rather than a thing a reader might notice.

What it reads, and what that costs
----------------------------------
Input is the SUMMARY output of DMTF's `spdm_dump -r` (one line per packet), not
the pcap. That is a deliberate boundary:

  * `spdm_dump` already knows how to parse SPDM. Re-implementing that here
    would be a second parser to keep correct, and the second one would be the
    wrong one.
  * `harness/pcapcount.py` owns the pcap layer — packet counts, byte counts,
    capture-file structure. This file never opens a pcap.

The cost is that this file inherits `spdm_dump`'s decode, including its
compile-time limits. Where the decode stops early the report says so instead of
reporting the prefix as if it were the whole capture: `decode_truncated` is a
first-class field, not a footnote.

The capability-bit tables below are transcribed from
`libspdm/include/industry_standard/spdm.h` at the commit pinned in
`third_party/spdm-emu-pqc.pin` (libspdm 4.0.0-rc, 8a92317). They are
transcribed rather than parsed because a header parser is a third thing to keep
correct; the trade is stated here so a reader knows to re-check them against the
header after a version bump. `--check` will not catch that: a bit name that
drifts stays self-consistent.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

# --------------------------------------------------------------- tables -----
#
# bit value -> (name, SPDM version whose mask in spdm.h first contains it)
#
# The requester has no 1.0 mask: in SPDM 1.0 GET_CAPABILITIES carried no flags
# from the requester at all, which is why the requester table starts at 1.1.

REQ_FLAGS = [
    (0x00000002, "CERT_CAP", "1.1"),
    (0x00000004, "CHAL_CAP", "1.1"),
    (0x00000040, "ENCRYPT_CAP", "1.1"),
    (0x00000080, "MAC_CAP", "1.1"),
    (0x00000100, "MUT_AUTH_CAP", "1.1"),
    (0x00000200, "KEY_EX_CAP", "1.1"),
    (0x00000400, "PSK_CAP_REQUESTER", "1.1"),
    (0x00000800, "PSK_CAP_RESERVED", "1.1"),
    (0x00001000, "ENCAP_CAP", "1.1"),
    (0x00002000, "HBEAT_CAP", "1.1"),
    (0x00004000, "KEY_UPD_CAP", "1.1"),
    (0x00008000, "HANDSHAKE_IN_THE_CLEAR_CAP", "1.1"),
    (0x00010000, "PUB_KEY_ID_CAP", "1.1"),
    (0x00020000, "CHUNK_CAP", "1.2"),
    (0x00400000, "EP_INFO_CAP_NO_SIG", "1.3"),
    (0x00800000, "EP_INFO_CAP_SIG", "1.3"),
    (0x02000000, "EVENT_CAP", "1.3"),
    (0x04000000, "MULTI_KEY_CAP_ONLY", "1.3"),
    (0x08000000, "MULTI_KEY_CAP_NEG", "1.3"),
    (0x80000000, "LARGE_RESP_CAP", "1.4"),
]

RSP_FLAGS = [
    (0x00000001, "CACHE_CAP", "1.0"),
    (0x00000002, "CERT_CAP", "1.0"),
    (0x00000004, "CHAL_CAP", "1.0"),
    (0x00000008, "MEAS_CAP_NO_SIG", "1.0"),
    (0x00000010, "MEAS_CAP_SIG", "1.0"),
    (0x00000020, "MEAS_FRESH_CAP", "1.0"),
    (0x00000040, "ENCRYPT_CAP", "1.1"),
    (0x00000080, "MAC_CAP", "1.1"),
    (0x00000100, "MUT_AUTH_CAP", "1.1"),
    (0x00000200, "KEY_EX_CAP", "1.1"),
    (0x00000400, "PSK_CAP_RESPONDER", "1.1"),
    (0x00000800, "PSK_CAP_RESPONDER_WITH_CONTEXT", "1.1"),
    (0x00001000, "ENCAP_CAP", "1.1"),
    (0x00002000, "HBEAT_CAP", "1.1"),
    (0x00004000, "KEY_UPD_CAP", "1.1"),
    (0x00008000, "HANDSHAKE_IN_THE_CLEAR_CAP", "1.1"),
    (0x00010000, "PUB_KEY_ID_CAP", "1.1"),
    (0x00020000, "CHUNK_CAP", "1.2"),
    (0x00040000, "ALIAS_CERT_CAP", "1.2"),
    (0x00080000, "SET_CERT_CAP", "1.2.1"),
    (0x00100000, "CSR_CAP", "1.2.1"),
    (0x00200000, "CERT_INSTALL_RESET_CAP", "1.2.1"),
    (0x00400000, "EP_INFO_CAP_NO_SIG", "1.3"),
    (0x00800000, "EP_INFO_CAP_SIG", "1.3"),
    (0x01000000, "MEL_CAP", "1.3"),
    (0x02000000, "EVENT_CAP", "1.3"),
    (0x04000000, "MULTI_KEY_CAP_ONLY", "1.3"),
    (0x08000000, "MULTI_KEY_CAP_NEG", "1.3"),
    (0x10000000, "GET_KEY_PAIR_INFO_CAP", "1.3"),
    (0x20000000, "SET_KEY_PAIR_INFO_CAP", "1.3"),
    (0x40000000, "SET_KEY_PAIR_RESET_CAP", "1.4"),
    (0x80000000, "LARGE_RESP_CAP", "1.4"),
]

# --------------------------------------------------------------- parsing ----

# 3 (1786441235) MCTP(5) REQ->RSP SPDM(14, 0xe1) SPDM_GET_CAPABILITIES (Flags=0x...)
LINE_RE = re.compile(
    r"^\s*(?P<seq>\d+)\s+\((?P<ts>\d+)\)\s+"
    r"(?P<transport>\w+)\((?P<tport>\d+)\)\s+"
    r"(?P<dir>REQ->RSP|RSP->REQ)\s+"
    r"(?P<rest>.*)$"
)

# SPDM(14, 0xe1) SPDM_GET_CAPABILITIES (...)   — a line may hold two of these
MSG_RE = re.compile(r"SPDM\((?P<hdrver>[0-9a-f]{2}),\s*0x(?P<code>[0-9a-f]{2})\)\s+(?P<name>SPDM_[A-Z_0-9]+)")

FIELD_RE = re.compile(r"(?P<key>[A-Za-z][A-Za-z0-9_]*)=(?P<val>0x[0-9a-fA-F]+|[0-9]+)(?:\((?P<ann>[^)]*)\))?")


def hdr_version(raw: str) -> str:
    """'14' -> '1.4'. The version byte of the SPDM header, as printed."""
    return f"{int(raw[0], 16)}.{int(raw[1], 16)}"


def decode_flags(value: int, table) -> tuple[list[str], list[str]]:
    """Return (set bit names, names of bits that are set but not in the table)."""
    named, unknown = [], []
    covered = 0
    for bit, name, _ver in table:
        if value & bit:
            named.append(name)
        covered |= bit
    leftover = value & ~covered
    if leftover:
        unknown = [f"0x{leftover:08x}"]
    return named, unknown


class Message:
    __slots__ = ("seq", "direction", "name", "code", "hdr_version", "fields",
                 "encapsulated", "reassembled", "carrier")

    def __init__(self, seq, direction, name, code, ver, fields):
        self.seq = seq
        self.direction = direction
        self.name = name
        self.code = code
        self.hdr_version = ver
        self.fields = fields
        self.encapsulated = None    # a separate request travelling the other way
        self.reassembled = None     # this same message, delivered in chunks
        self.carrier = None

    def field(self, key):
        return self.fields.get(key, {}).get("value")


def parse_decode(text: str) -> tuple[list[Message], dict]:
    messages: list[Message] = []
    meta = {"decode_truncated": False, "truncation_reason": None,
            "link_type": None, "pcap_datalink": None, "tool": None}

    for line in text.splitlines():
        if line.startswith("spdm_dump version"):
            meta["tool"] = line.strip()
            continue
        if line.startswith("PcapFile:"):
            m = re.search(r"DataLink\s*-\s*(\d+)\s*\(([^)]*)\)", line)
            if m:
                meta["pcap_datalink"] = int(m.group(1))
                meta["link_type"] = m.group(2)
            continue
        if "cert_chain is too larger" in line:
            meta["decode_truncated"] = True
            meta["truncation_reason"] = "spdm_dump LIBSPDM_MAX_CERT_CHAIN_SIZE"
            # The sentence is appended to the last decoded line, so fall through
            # and parse whatever preceded it.

        m = LINE_RE.match(line)
        if not m:
            continue

        rest = m.group("rest")
        found = list(MSG_RE.finditer(rest))
        if not found:
            continue

        built = []
        for i, mm in enumerate(found):
            start = mm.end()
            end = found[i + 1].start() if i + 1 < len(found) else len(rest)
            body = rest[start:end]
            fields = {}
            for f in FIELD_RE.finditer(body):
                fields[f.group("key")] = {
                    "raw": f.group("val"),
                    "value": int(f.group("val"), 0),
                    "annotation": f.group("ann"),
                }
            built.append(Message(int(m.group("seq")), m.group("dir"),
                                 mm.group("name"), int(mm.group("code"), 16),
                                 hdr_version(mm.group("hdrver")), fields))

        primary = built[0]
        if len(built) > 1:
            # Two messages on one line mean one of two different things, and
            # conflating them costs a certificate chain.
            #
            #   ENCAPSULATED_REQUEST / DELIVER_ENCAPSULATED_RESPONSE /
            #   ENCAPSULATED_RESPONSE_ACK carry a SEPARATE request in the
            #   opposite direction — this is mutual authentication.
            #
            #   CHUNK_RESPONSE carries the REASSEMBLED message it was
            #   delivering in pieces. That is the same message, finally whole,
            #   not a second one.
            #
            # Counting a chunk-reassembled CERTIFICATE as "encapsulated" makes
            # the responder's own certificate chain show up as the requester's.
            for extra in built[1:]:
                extra.carrier = primary.name
            if primary.name.startswith("SPDM_CHUNK"):
                primary.reassembled = built[1:]
            else:
                primary.encapsulated = built[1:]
        messages.append(primary)

    return messages, meta


# ------------------------------------------------------------- extraction ---

def first(messages, name):
    for msg in messages:
        if msg.name == name:
            return msg
    return None


def all_of(messages, name):
    return [m for m in messages if m.name == name]


def alg_list(msg, key):
    """NEGOTIATE_ALGORITHMS prints Hash=0x00000003(SHA_256,SHA_384)."""
    if not msg or key not in msg.fields:
        return None
    ann = msg.fields[key]["annotation"]
    if ann in (None, "", "<Unknown>"):
        return []
    return [a.strip() for a in ann.split(",") if a.strip()]


def extract(messages, meta, source: Path) -> dict:
    out: dict = {}

    out["source"] = {
        "decode_file": str(source),
        "sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
        "tool": meta["tool"],
        "decode_truncated": meta["decode_truncated"],
        "truncation_reason": meta["truncation_reason"],
    }
    out["transport"] = {"link_type": meta["link_type"],
                        "pcap_datalink": meta["pcap_datalink"]}

    by_type: dict[str, int] = {}
    inner_by_type: dict[str, int] = {}
    inner_all: list[Message] = []
    reassembled_all: list[Message] = []
    for m in messages:
        by_type[m.name] = by_type.get(m.name, 0) + 1
        for e in (m.encapsulated or []):
            inner_by_type[e.name] = inner_by_type.get(e.name, 0) + 1
            inner_all.append(e)
        for r in (m.reassembled or []):
            reassembled_all.append(r)
    out["messages"] = {
        "decoded": len(messages),
        "encapsulating": sum(1 for m in messages if m.encapsulated),
        "by_type": dict(sorted(by_type.items(), key=lambda kv: (-kv[1], kv[0]))),
        # Nothing is silently dropped. A GET_CERTIFICATE that travels inside an
        # ENCAPSULATED_RESPONSE_ACK is still a GET_CERTIFICATE on the wire, and
        # counting only the outer message is how the requester's own
        # certificate chain disappears from a byte total.
        "encapsulated_by_type": dict(sorted(inner_by_type.items(),
                                            key=lambda kv: (-kv[1], kv[0]))),
    }

    # -- version ------------------------------------------------------------
    ver_rsp = first(messages, "SPDM_VERSION")
    offered = []
    if ver_rsp is not None:
        # SPDM_VERSION (1.0.0.0, 1.1.0.0, ...) — the only message whose payload
        # spdm_dump prints without key=value, so it is read from the raw line.
        pass
    for line in source.read_text(encoding="utf-8", errors="replace").splitlines():
        if "SPDM_VERSION (" in line:
            inner = line.split("SPDM_VERSION (", 1)[1].rsplit(")", 1)[0]
            offered = [v.strip() for v in inner.split(",") if v.strip()]
            break
    get_ver = first(messages, "SPDM_GET_VERSION")
    out["version"] = {
        "offered": offered,
        "offered_count": len(offered),
        "get_version_header": get_ver.hdr_version if get_ver else None,
        "post_negotiation_header": (
            first(messages, "SPDM_GET_CAPABILITIES").hdr_version
            if first(messages, "SPDM_GET_CAPABILITIES") else None
        ),
    }

    # -- capabilities -------------------------------------------------------
    caps = {}
    for role, name, table in (("requester", "SPDM_GET_CAPABILITIES", REQ_FLAGS),
                              ("responder", "SPDM_CAPABILITIES", RSP_FLAGS)):
        msg = first(messages, name)
        if msg is None:
            caps[role] = None
            continue
        flags = msg.fields.get("Flags", {}).get("value", 0)
        named, unknown = decode_flags(flags, table)
        caps[role] = {
            "flags_raw": msg.fields.get("Flags", {}).get("raw"),
            "flags": named,
            "flags_unrecognised": unknown,
            "ct_exponent": msg.fields.get("CTExponent", {}).get("value"),
            "data_transfer_size": msg.fields.get("DataTransSize", {}).get("value"),
            "max_spdm_msg_size": msg.fields.get("MaxSpdmMsgSize", {}).get("value"),
        }
    both = None
    if caps["requester"] and caps["responder"]:
        both = sorted(set(caps["requester"]["flags"]) & set(caps["responder"]["flags"]))
    caps["common"] = both
    out["capabilities"] = caps

    # -- algorithms ---------------------------------------------------------
    neg = first(messages, "SPDM_NEGOTIATE_ALGORITHMS")
    sel = first(messages, "SPDM_ALGORITHMS")
    keys = ["Hash", "MeasHash", "Asym", "PqcAsym", "DHE", "KEM", "AEAD",
            "ReqAsym", "ReqPqcAsym", "KeySchedule", "MeasSpec", "OtherParam"]
    out["algorithms"] = {
        "offered": {k: alg_list(neg, k) for k in keys},
        "offered_counts": {k: (len(v) if v is not None else None)
                           for k, v in ((k, alg_list(neg, k)) for k in keys)},
        "negotiated": {k: alg_list(sel, k) for k in keys},
    }

    # -- certificates -------------------------------------------------------
    #
    # PortionLength is the size of THIS response's slice, not of the chain.
    # RemainderLength is what is still owed after it. So the chain's total size
    # is the first response's PortionLength + RemainderLength — one message,
    # two fields, no assumption about how many slices follow.
    #
    # Reading PortionLength as the chain size happens to be right whenever the
    # chain arrives in one piece, which is why it survives on a build that asks
    # for the whole chain at once and is wrong by 61% on a build that asks for
    # it 1024 bytes at a time. Both are in this repository's own captures.
    #
    # Whose chain is it: direction decides. A CERTIFICATE travelling RSP->REQ is
    # the responder proving its identity. One travelling REQ->RSP is inside the
    # encapsulated flow — the requester answering the responder's challenge.
    def chain_of(direction):
        certs = [m for m in messages
                 if m.name == "SPDM_CERTIFICATE" and m.direction == direction]
        certs += [e for e in inner_all + reassembled_all
                  if e.name == "SPDM_CERTIFICATE" and e.direction == direction]
        certs.sort(key=lambda m: m.seq)

        by_slot: dict = {}
        for c in certs:
            by_slot.setdefault(c.field("SlotID"), []).append(c)

        result = {}
        for slot, parts in sorted(by_slot.items(), key=lambda kv: (kv[0] is None, kv[0])):
            # A fetch ENDS when RemainderLength reaches zero. That is the
            # protocol's own statement that nothing is still owed, so it is the
            # only reliable boundary — and it is needed, because spdm-emu
            # fetches the same chain more than once per connection. Treating
            # every CERTIFICATE for a slot as one fetch reports a 1,655-byte
            # chain as 3,310 bytes in two portions, which is two wrong numbers
            # from one wrong assumption.
            fetches, current = [], []
            for c in parts:
                current.append(c)
                if (c.field("RemLen") or 0) == 0:
                    fetches.append(current)
                    current = []
            if current:                     # capture ended mid-fetch
                fetches.append(current)

            sizes, portion_counts, complete = [], [], []
            for f in fetches:
                head = f[0]
                declared = (head.field("PortLen") or 0) + (head.field("RemLen") or 0)
                observed = sum(p.field("PortLen") or 0 for p in f)
                sizes.append(declared)
                portion_counts.append(len(f))
                complete.append(declared == observed)

            result[slot] = {
                "bytes": sizes[0] if sizes else None,
                "portions": portion_counts[0] if portion_counts else None,
                "fetches": len(fetches),
                "bytes_per_fetch": sizes,
                "portions_per_fetch": portion_counts,
                # Every completed fetch must declare the same chain size, and
                # its portions must add up to that. If not, the capture holds a
                # truncated fetch and no size read from it is the chain's size.
                "consistent": all(complete) and len(set(sizes)) <= 1,
            }
        return result

    gets = [m for m in messages if m.name == "SPDM_GET_CERTIFICATE"]
    gets_encap = [e for e in inner_all if e.name == "SPDM_GET_CERTIFICATE"]
    responder_chains = chain_of("RSP->REQ")
    requester_chains = chain_of("REQ->RSP")

    out["certificate"] = {
        "get_certificate_count": len(gets),
        "get_certificate_encapsulated": len(gets_encap),
        "requested_length": gets[0].field("Length") if gets else None,
        "responder_chains": responder_chains,
        "responder_slot0_bytes": (responder_chains.get(0) or {}).get("bytes"),
        "responder_slot0_portions": (responder_chains.get(0) or {}).get("portions"),
        "responder_slot0_fetches": (responder_chains.get(0) or {}).get("fetches"),
        "requester_chains": requester_chains,
        "requester_slot0_bytes": (requester_chains.get(0) or {}).get("bytes"),
        "requester_slot0_portions": (requester_chains.get(0) or {}).get("portions"),
        "requester_slot0_fetches": (requester_chains.get(0) or {}).get("fetches"),
        "all_chains_consistent": all(
            c["consistent"] for c in list(responder_chains.values()) + list(requester_chains.values())
        ) if (responder_chains or requester_chains) else None,
    }

    # -- mutual authentication ---------------------------------------------
    #
    # spdm-emu ships with --basic_mut_auth BASIC and --mut_auth W_ENCAP on by
    # default, so a run nobody configured for it still authenticates in BOTH
    # directions. The responder challenges the requester through the
    # encapsulated-request flow, and the requester's own certificate chain —
    # a different algorithm, a different size — ends up inside the capture.
    #
    # This is the field that makes a "total handshake bytes" comparison honest
    # or dishonest. Both directions are negotiated separately, so an experiment
    # that varies only the responder's algorithm is varying one of two.
    ch_auth = first(messages, "SPDM_CHALLENGE_AUTH")
    out["mutual_auth"] = {
        "encapsulated_exchange": bool(inner_all),
        "encapsulated_message_count": len(inner_all),
        "encapsulated_by_type": dict(sorted(inner_by_type.items())),
        "requester_chain_bytes": out["certificate"]["requester_slot0_bytes"],
        "challenge_auth_attr": (ch_auth.fields.get("Attr", {}).get("raw") if ch_auth else None),
        "challenge_auth_attr_meaning": (ch_auth.fields.get("Attr", {}).get("annotation")
                                        if ch_auth else None),
    }

    # -- chunking -----------------------------------------------------------
    chunk_gets = all_of(messages, "SPDM_CHUNK_GET")
    errors = all_of(messages, "SPDM_ERROR")
    large = [e for e in errors
             if (e.fields.get("ErrCode", {}).get("annotation") or "") == "LargeResponse"]
    out["chunking"] = {
        "chunk_get_count": len(chunk_gets),
        "chunk_response_count": len(all_of(messages, "SPDM_CHUNK_RESPONSE")),
        "large_response_errors": len(large),
        "large_msg_size": next(
            (m.fields["LargeMsgSize"]["value"]
             for m in all_of(messages, "SPDM_CHUNK_RESPONSE") if "LargeMsgSize" in m.fields),
            None),
    }

    # -- measurements -------------------------------------------------------
    #
    # Two shapes, and the flag that chooses between them is --meas_op:
    #
    #   ONE_BY_ONE (the default): ask for the total, then walk indices 1..0xFE
    #     to find out which exist, then walk them again to build the signed
    #     transcript. The second walk is not redundancy — from SPDM 1.2 the
    #     L1/L2 transcript is reset when a MEASUREMENT request errors, so the
    #     existing indices have to be known before the signed pass starts.
    #   ALL: one request, one response, every block, one signature.
    #
    # The responder reports its count in TotalMeasIndex under the first, and in
    # NumOfBlocks under the second, so both are read.
    gm = all_of(messages, "SPDM_GET_MEASUREMENTS")
    ms = all_of(messages, "SPDM_MEASUREMENTS")
    total = next((m.field("TotalMeasIndex") for m in ms if "TotalMeasIndex" in m.fields), None)
    blocks = next((m.field("NumOfBlocks") for m in ms if "NumOfBlocks" in m.fields), None)
    record_len = next((m.field("MeasRecordLen") for m in ms if "MeasRecordLen" in m.fields), None)
    invalid = [e for e in errors
               if (e.fields.get("ErrCode", {}).get("annotation") or "") == "InvalidRequset"]
    # Which indices the responder actually answered: a GET at index N answered
    # by a MEASUREMENTS rather than an ERROR. The decode is in order, so pair by
    # position within the request/response alternation.
    existing = []
    for i, g in enumerate(gm):
        op = g.fields.get("MeasOp", {}).get("value")
        if op in (None, 0, 0xFF):
            continue
        nxt = next((m for m in messages if m.seq > g.seq), None)
        if nxt is not None and nxt.name == "SPDM_MEASUREMENTS" and op not in existing:
            existing.append(op)
    out["measurements"] = {
        "blocks_reported": total if total is not None else blocks,
        "total_index_reported": total,
        "num_of_blocks": blocks,
        "measurement_record_bytes": record_len,
        "get_measurements_count": len(gm),
        "measurements_count": len(ms),
        "invalid_request_errors": len(invalid),
        "existing_indices": existing,
        "existing_indices_hex": [f"0x{i:02x}" for i in existing],
        "operation": ("ALL" if any(g.field("MeasOp") == 0xFF for g in gm)
                      else "ONE_BY_ONE" if gm else None),
    }

    # -- errors -------------------------------------------------------------
    by_code: dict[str, int] = {}
    for e in errors:
        code = e.fields.get("ErrCode", {}).get("annotation") or "unnamed"
        by_code[code] = by_code.get(code, 0) + 1
    out["errors"] = {"total": len(errors), "by_code": by_code}

    return out


# ----------------------------------------------------------------- output ---

def flatten(obj, prefix="") -> dict:
    flat = {}
    if isinstance(obj, dict):
        for k, v in obj.items():
            flat.update(flatten(v, f"{prefix}.{k}" if prefix else k))
    elif isinstance(obj, list):
        flat[prefix] = ",".join(str(x) for x in obj)
        flat[f"{prefix}#"] = str(len(obj))
    else:
        flat[prefix] = "" if obj is None else str(obj)
    return flat


def render(data: dict) -> str:
    L = []
    src = data["source"]
    L.append(f"decode      : {src['decode_file']}")
    L.append(f"sha256      : {src['sha256'][:16]}…")
    L.append(f"tool        : {src['tool']}")
    if src["decode_truncated"]:
        L.append(f"TRUNCATED   : {src['truncation_reason']}")
        L.append("              the handshake is not short; the decoder stopped.")
    L.append(f"transport   : {data['transport']['link_type']} "
             f"(pcap DLT {data['transport']['pcap_datalink']})")
    L.append("")
    m = data["messages"]
    L.append(f"messages    : {m['decoded']} decoded, {m['encapsulating']} carrying an encapsulated message")
    for name, n in list(m["by_type"].items())[:8]:
        L.append(f"              {n:>5}  {name}")
    L.append("")
    v = data["version"]
    L.append(f"version     : offered {', '.join(v['offered']) or '—'}")
    L.append(f"              GET_VERSION header {v['get_version_header']}, "
             f"after negotiation {v['post_negotiation_header']}")
    L.append("")
    for role in ("requester", "responder"):
        c = data["capabilities"][role]
        if not c:
            continue
        L.append(f"{role:<12}: Flags {c['flags_raw']}  CTExponent {c['ct_exponent']}  "
                 f"DataTransferSize {c['data_transfer_size']}")
        L.append(f"              {', '.join(c['flags'])}")
        if c["flags_unrecognised"]:
            L.append(f"              UNRECOGNISED BITS: {', '.join(c['flags_unrecognised'])}")
    L.append("")
    a = data["algorithms"]
    L.append("algorithms  : offered -> negotiated")
    for k in ("Hash", "MeasHash", "Asym", "PqcAsym", "DHE", "KEM", "AEAD", "ReqAsym", "ReqPqcAsym"):
        off, neg = a["offered"].get(k), a["negotiated"].get(k)
        if not off and not neg:
            continue
        L.append(f"              {k:<11} {', '.join(off or ['—']):<52} -> {', '.join(neg or ['—'])}")
    L.append("")
    c = data["certificate"]
    L.append(f"certificate : {c['get_certificate_count']} GET_CERTIFICATE "
             f"(+{c['get_certificate_encapsulated']} encapsulated), "
             f"requested Length {c['requested_length']}")
    L.append(f"              responder slot 0 : {c['responder_slot0_bytes']} bytes, "
             f"{c['responder_slot0_portions']} portion(s) per fetch, "
             f"fetched {c['responder_slot0_fetches']}x")
    L.append(f"              requester slot 0 : {c['requester_slot0_bytes']} bytes, "
             f"{c['requester_slot0_portions']} portion(s) per fetch, "
             f"fetched {c['requester_slot0_fetches']}x")
    if c["all_chains_consistent"] is False:
        L.append("              ⚠ a chain fetch is incomplete or two fetches disagree on the")
        L.append("                size — no chain length read from this capture is reliable")
    ma = data["mutual_auth"]
    if ma["encapsulated_exchange"]:
        L.append(f"mutual auth : yes — {ma['encapsulated_message_count']} encapsulated messages")
        L.append(f"              CHALLENGE_AUTH Attr {ma['challenge_auth_attr']} "
                 f"({ma['challenge_auth_attr_meaning']})")
    k = data["chunking"]
    L.append(f"chunking    : {k['chunk_get_count']} CHUNK_GET, "
             f"{k['large_response_errors']} LargeResponse error(s)")
    ms = data["measurements"]
    L.append(f"measurements: operation {ms['operation']}, responder reports "
             f"{ms['blocks_reported']} block(s)"
             + (f", record {ms['measurement_record_bytes']} bytes"
                if ms["measurement_record_bytes"] else ""))
    L.append(f"              {ms['get_measurements_count']} GET_MEASUREMENTS, "
             f"{ms['measurements_count']} MEASUREMENTS, "
             f"{ms['invalid_request_errors']} InvalidRequset")
    if ms["existing_indices_hex"]:
        L.append(f"              indices that exist: {', '.join(ms['existing_indices_hex'])}")
    return "\n".join(L)


# ------------------------------------------------------------------ check ---

CAPTURE_RE = re.compile(r"<!--\s*capture:\s*(?P<path>\S+)\s*-->")
CLAIM_RE = re.compile(r"<!--\s*claim\s+(?P<key>[A-Za-z0-9_.#]+)\s*=\s*(?P<val>.*?)\s*-->")


def normalise(value: str) -> str:
    v = value.strip()
    if re.fullmatch(r"0x[0-9a-fA-F]+", v):
        return str(int(v, 16))
    return v


def check(doc_path: Path, repo_root: Path) -> int:
    text = doc_path.read_text(encoding="utf-8")
    flat: dict[str, str] = {}
    capture_name = None
    failures = 0
    checked = 0

    print(f"  document: {doc_path}")
    for lineno, line in enumerate(text.splitlines(), 1):
        cap = CAPTURE_RE.search(line)
        if cap:
            capture_name = cap.group("path")
            target = repo_root / capture_name
            if not target.exists():
                print(f"  FAIL line {lineno}: capture not found: {capture_name}")
                failures += 1
                flat = {}
                continue
            messages, meta = parse_decode(target.read_text(encoding="utf-8", errors="replace"))
            flat = flatten(extract(messages, meta, target))
            print(f"  capture : {capture_name}  ({len(messages)} messages decoded)")
            continue

        for claim in CLAIM_RE.finditer(line):
            key, want = claim.group("key"), claim.group("val")
            checked += 1
            if capture_name is None:
                print(f"  FAIL line {lineno}: claim '{key}' before any <!-- capture: ... --> directive")
                failures += 1
                continue
            if key not in flat:
                print(f"  FAIL line {lineno}: '{key}' is not a field this tool computes")
                failures += 1
                continue
            got = flat[key]
            if normalise(got) != normalise(want):
                print(f"  FAIL line {lineno}: {key}")
                print(f"        document says : {want}")
                print(f"        capture says  : {got}")
                failures += 1

    if checked == 0:
        print("  FAIL no claims found — the document asserts nothing against its capture")
        return 1
    print(f"  {checked - failures}/{checked} claims match the capture")
    return 1 if failures else 0


# ------------------------------------------------------------------- main ---

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("decode", nargs="?", type=Path,
                    help="a spdm_dump -r summary decode (*.decode.txt)")
    ap.add_argument("--json", action="store_true", help="machine-readable output")
    ap.add_argument("--check", type=Path, metavar="DOC",
                    help="verify every <!--claim k=v--> in DOC against the capture it names")
    ap.add_argument("--list-keys", action="store_true",
                    help="print every claimable key for this decode")
    args = ap.parse_args()

    repo_root = Path(__file__).resolve().parent.parent

    if args.check:
        return check(args.check, repo_root)

    if args.decode is None:
        ap.error("give a decode file, or --check DOC")
    if not args.decode.exists():
        print(f"no such file: {args.decode}", file=sys.stderr)
        return 2

    messages, meta = parse_decode(args.decode.read_text(encoding="utf-8", errors="replace"))
    if not messages:
        print(f"no SPDM messages decoded from {args.decode}", file=sys.stderr)
        return 2
    data = extract(messages, meta, args.decode)

    if args.list_keys:
        for k, v in sorted(flatten(data).items()):
            print(f"{k} = {v}")
    elif args.json:
        print(json.dumps(data, indent=2))
    else:
        print(render(data))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

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
                 "encapsulated", "reassembled", "carrier", "raw")

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
        self.raw = None             # this message's bytes, if a hex dump was kept

    def field(self, key):
        return self.fields.get(key, {}).get("value")


HEX_ROW_RE = re.compile(r"^\s*[0-9a-f]{4}:\s+((?:[0-9a-f]{2}\s*)+)$")
HEX_BLOCK_RE = re.compile(r"^\s*(?P<label>[A-Za-z ]*SPDM Message):\s*$")


def parse_hex_blocks(text: str) -> dict[int, list[tuple[str, bytes]]]:
    """Every hex block of a `spdm_dump -x` dump, as raw bytes, by packet number.

    Message SIZE is not in the summary decode — spdm_dump prints the fields it
    understood, not how many bytes they occupied — and it is the primitive every
    later cost comparison is built on. The hex dump has it, so it is read from
    there rather than estimated from the pcap record, which would also include
    the transport framing.

        5 (...) MCTP(5) REQ->RSP SPDM(14, 0xe3) SPDM_NEGOTIATE_ALGORITHMS (...)
          SPDM Message:
            0000: 14 e3 06 00 38 00 01 12 ...

    A packet carrying mutual authentication prints TWO blocks, and the inner one
    is printed FIRST:

        21 (...) REQ->RSP SPDM(14, 0xeb) SPDM_DELIVER_ENCAPSULATED_RESPONSE (...)
                                         SPDM(14, 0x03) SPDM_CHALLENGE_AUTH (...)
          Encapsulated SPDM Message:
            0000: 14 03 00 07 ...        <- the CHALLENGE_AUTH
          SPDM Message:
            0000: 14 eb 03 00 14 03 ...  <- the carrier, which CONTAINS it

    So the blocks are returned with their labels rather than summed. The carrier
    already holds the encapsulated message byte for byte; adding the two is
    counting the same bytes twice, and `attach_raw` proves the containment
    rather than assuming it.
    """
    out: dict[int, list[tuple[str, bytes]]] = {}
    seq: int | None = None
    label: str | None = None
    acc: list[int] = []

    def flush():
        if seq is not None and label is not None and acc:
            out.setdefault(seq, []).append((label, bytes(acc)))

    for line in text.splitlines():
        head = LINE_RE.match(line)
        if head:
            flush()
            acc, label = [], None
            seq = int(head.group("seq"))
            out.setdefault(seq, [])
            continue
        block = HEX_BLOCK_RE.match(line)
        if block:
            flush()
            acc, label = [], block.group("label").strip()
            continue
        row = HEX_ROW_RE.match(line)
        if row and label is not None:
            acc.extend(int(b, 16) for b in row.group(1).split())
    flush()
    return out


def attach_raw(messages, blocks) -> dict:
    """Give every decoded message its bytes, and report what could not be paired.

    The pairing rule is the wire, not the print order: byte 1 of an SPDM message
    is its `RequestResponseCode`, so a block belongs to the message whose code it
    carries. Pairing by position instead gives the carrier's bytes to the message
    it carries — which is how a 466-byte CHALLENGE_AUTH becomes a 482-byte one,
    silently, in the direction that flatters the number.
    """
    report = {"packets_with_multiple_blocks": 0, "encapsulated_blocks": 0,
              "contained": 0, "not_contained": [], "unpaired": [], "wire_bytes": {}}

    for msg in messages:
        found = blocks.get(msg.seq, [])
        if not found:
            continue
        if len(found) > 1:
            report["packets_with_multiple_blocks"] += 1

        outer = [raw for label, raw in found if label == "SPDM Message"]
        inner = [raw for label, raw in found if label != "SPDM Message"]
        report["encapsulated_blocks"] += len(inner)

        # The carrier is the block on the wire. Its length is the packet's cost.
        if len(outer) == 1:
            report["wire_bytes"][msg.seq] = len(outer[0])
        else:
            report["unpaired"].append(f"packet {msg.seq}: {len(outer)} carrier blocks")
            report["wire_bytes"][msg.seq] = sum(len(r) for _, r in found)

        def take(candidates, code):
            for raw in candidates:
                if len(raw) >= 2 and raw[1] == code:
                    return raw
            return None

        msg.raw = take(outer, msg.code)
        if msg.raw is None and len(outer) == 1 and not inner:
            # One block, one message, and the code disagrees: say so rather than
            # accept it, because everything downstream reads offsets off this.
            report["unpaired"].append(
                f"packet {msg.seq}: {msg.name} expects code 0x{msg.code:02x}, "
                f"block starts 0x{outer[0][1]:02x}")

        for carried in (msg.encapsulated or []) + (msg.reassembled or []):
            carried.raw = take(inner, carried.code) or take(outer, carried.code)
            if carried.raw is None:
                report["unpaired"].append(
                    f"packet {msg.seq}: no block for carried {carried.name}")
            elif outer and carried.raw is not outer[0]:
                if carried.raw in outer[0]:
                    report["contained"] += 1
                else:
                    report["not_contained"].append(
                        f"packet {msg.seq}: {carried.name} is not a substring of its carrier")
    return report


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


# ----------------------------------------------------------------- layout ---
#
# Everything above reads values. This section reads OFFSETS, and it exists
# because the walkthrough's §10 says the offsets are the part nothing checks:
# they are transcribed from the struct definitions in `spdm.h`, so a wrong
# offset printed next to a right value passes every test in this file.
#
# The way out is that an SPDM response is exactly reconstructible. Every field
# is one of four things — a constant size, a size fixed by something negotiated
# several messages earlier, a size the message itself carries, or the remainder
# — so the whole layout can be rebuilt and then FALSIFIED, twice over:
#
#   closure   the bytes left after placing everything up to the signature must
#             equal the signature size implied by the negotiated algorithm. The
#             total comes from the hex dump, the signature size from ALGORITHMS.
#             Neither is in the document being checked.
#
#   echo      RequesterContext is chosen by the requester and returned
#             unchanged. Reading it back at the offset the reconstruction
#             predicts, hundreds of bytes in, and comparing it against the
#             request is a second equation on the same unknowns — and it uses
#             no constant from this file at all.
#
# Two independent equations, one free variable. That is enough to settle a
# question the document could not: whether CHALLENGE_AUTH's
# MeasurementSummaryHash is sized by BaseHashAlgo or by MeasurementHashAlgo.
# Here they are SHA-384 and SHA-512, so the two hypotheses differ by 16 bytes
# and exactly one of them closes.
#
# The two tables below are transcribed from DSP0274 and FIPS 204/186-5. Unlike
# the capability-bit tables at the top of this file, they are not taken on
# trust: a wrong entry makes the residue miss, so every closure that succeeds is
# also a check on the number it used.

HASH_BYTES = {
    "SHA_256": 32, "SHA_384": 48, "SHA_512": 64,
    "SHA3_256": 32, "SHA3_384": 48, "SHA3_512": 64,
    "SM3_256": 32,
}

SIG_BYTES = {
    "ECDSA_P256": 64, "ECDSA_P384": 96, "ECDSA_P521": 132,
    "RSASSA_2048": 256, "RSAPSS_2048": 256,
    "RSASSA_3072": 384, "RSAPSS_3072": 384,
    "RSASSA_4096": 512, "RSAPSS_4096": 512,
    "SM2_ECC_P256": 64, "EDDSA_ED25519": 64, "EDDSA_ED448": 114,
    "ML_DSA_44": 2420, "ML_DSA_65": 3309, "ML_DSA_87": 4627,
}

SPDM_CHALLENGE = 0x83
SPDM_CHALLENGE_AUTH = 0x03
SPDM_GET_MEASUREMENTS = 0xE0
SPDM_MEASUREMENTS = 0x60
CONTEXT_BYTES = 8       # RequesterContext, SPDM 1.3 and later


def _u16le(raw, off):
    return raw[off] | raw[off + 1] << 8


def _u24le(raw, off):
    return raw[off] | raw[off + 1] << 8 | raw[off + 2] << 16


def _sized(names, table):
    """One negotiated algorithm's size, or None if zero or several were chosen."""
    picked = [n for n in (names or []) if n in table]
    return table[picked[0]] if len(picked) == 1 else None


def on_the_wire(messages):
    """Every message in wire order, carried ones before their carrier."""
    for msg in messages:
        for carried in (msg.encapsulated or []) + (msg.reassembled or []):
            yield carried
        yield msg


def _request_before(ordered, index, code):
    for msg in reversed(ordered[:index]):
        if msg.code == code and msg.raw:
            return msg
    return None


def _context_span(request, fixed):
    """RequesterContext exists from SPDM 1.3. Derive its size from the request's
    own length rather than from the version byte, and refuse anything else."""
    span = len(request.raw) - fixed
    return span if span in (0, CONTEXT_BYTES) else None


def _place_challenge_auth(rsp, req, hashes, sig):
    """Reconstruct CHALLENGE_AUTH. `hashes` is (BaseHashAlgo, MeasurementHashAlgo)."""
    raw = rsp.raw
    ctx = _context_span(req, 4 + 32)
    if ctx is None:
        return None, f"packet {req.seq}: CHALLENGE is {len(req.raw)} bytes, expected 36 or 44"

    # HashType 0 means the requester asked for no measurement summary, and the
    # field is then absent — which the mutual-authentication exchange uses.
    hash_type = req.raw[3]
    if hash_type == 0:
        hypotheses = [(0, "absent (HashType 0)")]
    else:
        hypotheses = [(hashes[0], "BaseHashAlgo"), (hashes[1], "MeasurementHashAlgo")]

    closed = []
    chain = hashes[0]          # CertChainHash is always the negotiated BaseHashAlgo
    for summary, source in hypotheses:
        if chain is None or summary is None:
            continue
        off = 4
        placed = {"cert_chain_hash_offset": off, "cert_chain_hash_bytes": chain}
        off += chain
        placed["nonce_offset"] = off
        off += 32
        placed["summary_hash_offset"] = off if summary else None
        placed["summary_hash_bytes"] = summary
        placed["summary_hash_sized_by"] = source
        off += summary
        if off + 2 > len(raw):
            continue
        placed["opaque_length_offset"] = off
        placed["opaque_length"] = _u16le(raw, off)
        off += 2 + placed["opaque_length"]
        if off + ctx > len(raw):
            continue
        placed["requester_context_offset"] = off if ctx else None
        off += ctx
        placed["signature_offset"] = off
        placed["signature_bytes"] = len(raw) - off
        placed["total_bytes"] = len(raw)
        if placed["signature_bytes"] == sig:
            closed.append(placed)

    return _settle(closed, rsp, req, ctx, sig, "CHALLENGE_AUTH", 4 + 32)


def _place_measurements(rsp, req, sig):
    raw = rsp.raw
    gensig = bool(req.raw[2] & 0x01)
    # Nonce and SlotIDParam are both present only when a signature was asked
    # for. Without one there is no transcript to freshen and no key to name.
    ctx = _context_span(req, 4 + (32 + 1 if gensig else 0))
    if ctx is None:
        return None, (f"packet {req.seq}: GET_MEASUREMENTS is {len(req.raw)} bytes, "
                      f"expected {4 + (33 if gensig else 0)} or "
                      f"{12 + (33 if gensig else 0)}")

    off = 4
    placed = {"blocks": raw[off], "blocks_offset": off}
    off += 1
    placed["record_length_offset"] = off
    placed["record_bytes"] = _u24le(raw, off)
    off += 3
    placed["record_offset"] = off
    off += placed["record_bytes"]
    if off + 32 + 2 > len(raw):
        return None, f"packet {rsp.seq}: MEASUREMENTS record length runs past the message"
    placed["nonce_offset"] = off
    off += 32
    placed["opaque_length_offset"] = off
    placed["opaque_length"] = _u16le(raw, off)
    off += 2 + placed["opaque_length"]
    if off + ctx > len(raw):
        return None, f"packet {rsp.seq}: MEASUREMENTS OpaqueData runs past the message"
    placed["requester_context_offset"] = off if ctx else None
    off += ctx
    placed["signature_offset"] = off if gensig else None
    placed["signature_bytes"] = len(raw) - off
    placed["signature_requested"] = gensig
    placed["total_bytes"] = len(raw)

    want = sig if gensig else 0
    closed = [placed] if placed["signature_bytes"] == want else []
    return _settle(closed, rsp, req, ctx, want, "MEASUREMENTS",
                   4 + (33 if gensig else 0))


def _settle(closed, rsp, req, ctx, sig, what, req_context_offset):
    """Accept a reconstruction only if exactly one closes and the echo agrees."""
    if not closed:
        return None, (f"packet {rsp.seq}: {what} does not close — "
                      f"{len(rsp.raw)} bytes, expected residue {sig}")
    if len(closed) > 1:
        return None, (f"packet {rsp.seq}: {what} closes under "
                      f"{len(closed)} hypotheses; the capture cannot separate them")

    placed = closed[0]
    if ctx:
        want = req.raw[req_context_offset:req_context_offset + ctx]
        got = rsp.raw[placed["requester_context_offset"]:
                      placed["requester_context_offset"] + ctx]
        placed["requester_context"] = got.hex(" ")
        placed["context_echoes_request"] = (got == want)
        if not placed["context_echoes_request"]:
            return None, (f"packet {rsp.seq}: {what} closes, but RequesterContext at "
                          f"{placed['requester_context_offset']} is {got.hex(' ')} "
                          f"and the request sent {want.hex(' ')}")
    else:
        placed["requester_context"] = None
        placed["context_echoes_request"] = None
    placed["closes"] = True
    placed["packet"] = rsp.seq
    return placed, None


def reconstruct(messages, negotiated) -> dict:
    """Rebuild the layout of every signed response, and report what did not."""
    out = {
        "hash_bytes": _sized(negotiated.get("Hash"), HASH_BYTES),
        "measurement_hash_bytes": _sized(negotiated.get("MeasHash"), HASH_BYTES),
        "responder_signature_bytes": (_sized(negotiated.get("Asym"), SIG_BYTES)
                                      or _sized(negotiated.get("PqcAsym"), SIG_BYTES)),
        "requester_signature_bytes": (_sized(negotiated.get("ReqAsym"), SIG_BYTES)
                                      or _sized(negotiated.get("ReqPqcAsym"), SIG_BYTES)),
        "attempted": 0, "closed": 0, "unexplained": [],
        "challenge_auth": None, "challenge_auth_requester": None,
        "measurements": None, "measurements_unsigned": None,
    }
    hashes = (out["hash_bytes"], out["measurement_hash_bytes"])

    ordered = [m for m in on_the_wire(messages)]
    for i, msg in enumerate(ordered):
        if msg.code not in (SPDM_CHALLENGE_AUTH, SPDM_MEASUREMENTS) or not msg.raw:
            continue
        # Whoever sent the response signed it, so the direction on the wire —
        # not the encapsulation — chooses which half of the negotiation applies.
        sig = (out["responder_signature_bytes"] if msg.direction == "RSP->REQ"
               else out["requester_signature_bytes"])
        if sig is None:
            out["unexplained"].append(
                f"packet {msg.seq}: no single signature algorithm was negotiated "
                f"for the {'responder' if msg.direction == 'RSP->REQ' else 'requester'}")
            continue

        want = SPDM_CHALLENGE if msg.code == SPDM_CHALLENGE_AUTH else SPDM_GET_MEASUREMENTS
        req = _request_before(ordered, i, want)
        if req is None:
            out["unexplained"].append(f"packet {msg.seq}: no request precedes it")
            continue

        out["attempted"] += 1
        if msg.code == SPDM_CHALLENGE_AUTH:
            placed, why = _place_challenge_auth(msg, req, hashes, sig)
            slot = ("challenge_auth" if msg.direction == "RSP->REQ"
                    else "challenge_auth_requester")
        else:
            placed, why = _place_measurements(msg, req, sig)
            slot = ("measurements" if placed and placed["signature_requested"]
                    else "measurements_unsigned")
        if placed is None:
            out["unexplained"].append(why)
            continue
        out["closed"] += 1
        if out[slot] is None:
            out[slot] = placed

    return out


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
    record_by_index: dict[int, int] = {}
    for g in gm:
        op = g.field("MeasOp")
        if op in (None, 0, 0xFF):
            continue
        nxt = next((m for m in messages if m.seq > g.seq), None)
        if nxt is not None and nxt.name == "SPDM_MEASUREMENTS":
            if op not in existing:
                existing.append(op)
            record_by_index.setdefault(op, nxt.field("MeasRecordLen") or 0)
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
        # The sum of every distinct index's MeasurementRecordLength. Under
        # --meas_op ALL the same total arrives as one record, so these two
        # numbers are the same measurement fetched two ways — and asserting
        # both is what turns "the round trips are the emulator's choice, not
        # the protocol's" from an argument into a check.
        "record_bytes_by_index": {f"0x{k:02x}": v for k, v in sorted(record_by_index.items())},
        "record_bytes_sum": sum(record_by_index.values()) if record_by_index else None,
        "operation": ("ALL" if any(g.field("MeasOp") == 0xFF for g in gm)
                      else "ONE_BY_ONE" if gm else None),
    }

    # -- errors -------------------------------------------------------------
    by_code: dict[str, int] = {}
    for e in errors:
        code = e.fields.get("ErrCode", {}).get("annotation") or "unnamed"
        by_code[code] = by_code.get(code, 0) + 1
    out["errors"] = {"total": len(errors), "by_code": by_code}

    # -- message sizes, if the hex dump was kept beside the decode ----------
    #
    # `total` is what went down the socket: the carrier's bytes, once. A packet
    # carrying mutual authentication prints its encapsulated message as a second
    # block, and that message is already inside the carrier — summing both
    # inflated this figure by 40% in the walkthrough capture. `carried_by_type`
    # keeps those bytes visible without adding them twice, and `consistent`
    # asserts the split: the per-type totals must add back up to `total`.
    hexfile = source.with_name(source.name.replace(".decode.txt", ".hex.txt"))
    if hexfile.exists() and hexfile != source:
        blocks = parse_hex_blocks(hexfile.read_text(encoding="utf-8", errors="replace"))
        pairing = attach_raw(messages, blocks)
        # Not `first` — that is the name of the message lookup helper above, and
        # binding it here would shadow it for the whole function.
        first_bytes: dict[str, int] = {}
        total_bytes: dict[str, int] = {}
        carried_bytes: dict[str, int] = {}
        for m in messages:
            if m.raw is None:
                continue
            first_bytes.setdefault(m.name, len(m.raw))
            total_bytes[m.name] = total_bytes.get(m.name, 0) + len(m.raw)
            for c in (m.encapsulated or []) + (m.reassembled or []):
                if c.raw is not None:
                    carried_bytes[c.name] = carried_bytes.get(c.name, 0) + len(c.raw)
        wire_total = sum(len(m.raw) for m in messages if m.raw is not None)
        out["message_bytes"] = {
            "source": hexfile.name,
            "total": wire_total,
            "consistent": wire_total == sum(total_bytes.values()),
            "carried_total": sum(carried_bytes.values()),
            "carried_verified_inside_carrier": pairing["contained"],
            "carried_not_inside_carrier": pairing["not_contained"],
            "unpaired": pairing["unpaired"],
            "first_by_type": dict(sorted(first_bytes.items())),
            "total_by_type": dict(sorted(total_bytes.items(), key=lambda kv: -kv[1])),
            "carried_by_type": dict(sorted(carried_bytes.items(), key=lambda kv: -kv[1])),
        }
        out["layout"] = reconstruct(messages, out["algorithms"]["negotiated"])
    else:
        out["message_bytes"] = None
        out["layout"] = None

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
    mb = data.get("message_bytes")
    if mb:
        L.append("")
        L.append(f"bytes       : {mb['total']} in SPDM messages "
                 f"(transport framing excluded), from {mb['source']}")
        for name, n in list(mb["total_by_type"].items())[:6]:
            L.append(f"              {n:>7}  {name}")
        if mb["carried_total"]:
            L.append(f"              {mb['carried_total']} more bytes travelled inside "
                     f"those messages, encapsulated;")
            L.append(f"              {mb['carried_verified_inside_carrier']} of them "
                     f"confirmed byte for byte inside their carrier, so not added twice")
        if not mb["consistent"]:
            L.append("              ⚠ the per-type totals do not add up to the total")
        for problem in mb["carried_not_inside_carrier"] + mb["unpaired"]:
            L.append(f"              ⚠ {problem}")

    lay = data.get("layout")
    if lay:
        L.append("")
        L.append(f"layout      : {lay['closed']}/{lay['attempted']} signed responses "
                 f"reconstructed and closed")
        L.append(f"              hash {lay['hash_bytes']} B, responder signature "
                 f"{lay['responder_signature_bytes']} B, requester signature "
                 f"{lay['requester_signature_bytes']} B")
        for slot, label in (("challenge_auth", "CHALLENGE_AUTH"),
                            ("challenge_auth_requester", "CHALLENGE_AUTH (requester)"),
                            ("measurements", "MEASUREMENTS"),
                            ("measurements_unsigned", "MEASUREMENTS (unsigned)")):
            p = lay[slot]
            if not p:
                continue
            echo = ("context echoes the request" if p["context_echoes_request"]
                    else "no RequesterContext" if p["context_echoes_request"] is None
                    else "CONTEXT DOES NOT MATCH")
            L.append(f"              {label:<27} packet {p['packet']:>4}  "
                     f"{p['total_bytes']:>6} B  nonce at {p['nonce_offset']}, "
                     f"signature {p['signature_bytes']} B — {echo}")
            if slot == "challenge_auth":
                L.append(f"              {'':<27} MeasurementSummaryHash "
                         f"{p['summary_hash_bytes']} B, sized by {p['summary_hash_sized_by']}")
        for problem in lay["unexplained"]:
            L.append(f"              ⚠ {problem}")
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
    in_fence = False
    for lineno, line in enumerate(text.splitlines(), 1):
        # A document that explains this markup has to be able to show it. Text
        # inside a fenced code block is an example, not an assertion.
        if line.lstrip().startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence:
            continue

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

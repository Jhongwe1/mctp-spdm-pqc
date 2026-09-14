#!/usr/bin/env python3
"""Count SPDM messages out of a capture, without asking a decoder.

    python3 bench/pcapstat.py <run>/walkthrough.pcap
    python3 bench/pcapstat.py <run>/walkthrough.pcap --json
    python3 bench/pcapstat.py <run>/walkthrough.pcap --list
    python3 bench/pcapstat.py <run>/walkthrough.pcap --check     # against fields.py

Why a third tool, and what it is allowed to own
-----------------------------------------------
`docs/roadmap.md` standing rule 12: one tool per input, and where two tools can
reach the same quantity by different routes they are made to agree.

  * `harness/pcapcount.py` owns the capture FILE — its header, its records,
    how many packets and how many bytes. It knows nothing about SPDM, and this
    file does not reimplement it; it imports it.
  * `harness/fields.py` owns the DECODE — `spdm_dump`'s summary and hex output.
    It never opens a capture.
  * this file owns the SPDM MESSAGE LAYER INSIDE the capture: the framing in
    front of each message and the `RequestResponseCode` byte that says what the
    message is. It never reads a decode.

So there are now two independent answers to "how many bytes did each kind of
SPDM message cost": one derived from `spdm_dump`'s hex output, and one derived
from the capture file directly. `--check` requires them to be equal. Two
parsers that agree, having shared no input, is a much stronger statement than
one parser that is careful — and it is the point of writing this rather than
parsing `spdm_dump -x` a second time.

What is deliberately not here yet
---------------------------------
This does not decode message BODIES, with one exception argued for below.
Reporting `MEASUREMENTS is 674 bytes` is this file's job; reporting what is
inside those 674 bytes is `fields.py`'s, and duplicating it would create a
second parser to keep correct — which is the thing rule 12 exists to prevent.

The certificate chain, and why it is the exception
--------------------------------------------------
`GET_CERTIFICATE` is the one message whose *transport* is interesting rather
than its contents. A chain does not arrive in one message: the responder sends
as much as it can and says how much is left, so the number of round trips is a
property of the exchange, not of the certificates. Two quantities follow, and
neither is a body field:

  * `cert_roundtrips` — how many `GET_CERTIFICATE` requests it took. This is
    the number week eight needs, because a post-quantum chain is several times
    larger and the round trips are what a slow bus charges for.
  * `chain_bytes` — the reassembled chain length, from the `PortionLength` of
    each response.

That gives a **third** independent route to a number this repository already
has two of. `certs/check_chain.py` computes it from the DER files on disk and
never opens a capture; `harness/fields.py` reads it out of `spdm_dump`'s
decode and never opens a certificate; this file walks the capture and reads
neither. `harness/verify_repo.sh` requires all three to agree.

Two equations have to close before the number is reported, and if either fails
the chain is reported as not closing rather than as a length:

    sum of every PortionLength   ==  first response's Portion + Remainder
    the chain's own Length field ==  that same total

The second is the chain's own opinion of its size, carried in the first four
bytes of the reassembled bytes, and it comes from the responder rather than
from the framing. `verify_repo.sh` feeds this a chain one byte short and
requires it to say so.

The framing
-----------
Every record in these captures is

    00 00 00 c0   05   10 84 00 00 ...
    └─ MCTP hdr ┘  └┬┘  └─ SPDM message ─┘
                    │
                    MCTP message type: 0x05 SPDM, 0x06 secured

four bytes of MCTP header that `spdm_emu` synthesises purely so the pcap has
one (`send_platform_data`, taken apart in `docs/transports.md`), then the MCTP
message type, then the SPDM message starting at its own four-byte header:
version, `RequestResponseCode`, `Param1`, `Param2`.

A secured message (type 0x06) is counted and reported as secured. Its contents
are encrypted, so nothing else can honestly be said about it, and guessing is
how a byte total starts flattering itself.

Exit codes: 0 ok · 1 --check found a disagreement · 2 unreadable capture
"""

from __future__ import annotations

import argparse
import json
import struct
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "harness"))

from pcapcount import NotAPcap, Truncated, read_pcap  # noqa: E402

# Transcribed from the pinned libspdm's include/industry_standard/spdm.h
# (8a92317, lines 29-106) and include/industry_standard/mctp.h lines 49-55.
# Transcribed rather than parsed for the same reason fields.py's capability
# tables are: a header parser is a third thing to keep correct. The trade is
# stated so a reader knows to re-read them after a version bump — and unlike a
# byte count, --check cannot catch a name that drifts, because a wrong name
# stays self-consistent.
LINKTYPE_MCTP = 291
LINKTYPE_PCI_DOE = 292

MCTP_HEADER_BYTES = 4
MCTP_TYPE_SPDM = 0x05
MCTP_TYPE_SECURED = 0x06

SPDM_CODES = {
    0x01: "SPDM_DIGESTS",
    0x02: "SPDM_CERTIFICATE",
    0x03: "SPDM_CHALLENGE_AUTH",
    0x04: "SPDM_VERSION",
    0x05: "SPDM_CHUNK_SEND_ACK",
    0x06: "SPDM_CHUNK_RESPONSE",
    0x07: "SPDM_ENDPOINT_INFO",
    0x08: "SPDM_SLOT_MANAGEMENT_RESP",
    0x60: "SPDM_MEASUREMENTS",
    0x61: "SPDM_CAPABILITIES",
    0x63: "SPDM_ALGORITHMS",
    0x64: "SPDM_KEY_EXCHANGE_RSP",
    0x65: "SPDM_FINISH_RSP",
    0x66: "SPDM_PSK_EXCHANGE_RSP",
    0x67: "SPDM_PSK_FINISH_RSP",
    0x68: "SPDM_HEARTBEAT_ACK",
    0x69: "SPDM_KEY_UPDATE_ACK",
    0x6A: "SPDM_ENCAPSULATED_REQUEST",
    0x6B: "SPDM_ENCAPSULATED_RESPONSE_ACK",
    0x6C: "SPDM_END_SESSION_ACK",
    0x6D: "SPDM_CSR",
    0x6E: "SPDM_SET_CERTIFICATE_RSP",
    0x6F: "SPDM_MEASUREMENT_EXTENSION_LOG",
    0x71: "SPDM_EVENT_ACK",
    0x7E: "SPDM_VENDOR_DEFINED_RESPONSE",
    0x7F: "SPDM_ERROR",
    0x81: "SPDM_GET_DIGESTS",
    0x82: "SPDM_GET_CERTIFICATE",
    0x83: "SPDM_CHALLENGE",
    0x84: "SPDM_GET_VERSION",
    0x85: "SPDM_CHUNK_SEND",
    0x86: "SPDM_CHUNK_GET",
    0x87: "SPDM_GET_ENDPOINT_INFO",
    0x88: "SPDM_SLOT_MANAGEMENT",
    0xE0: "SPDM_GET_MEASUREMENTS",
    0xE1: "SPDM_GET_CAPABILITIES",
    0xE3: "SPDM_NEGOTIATE_ALGORITHMS",
    0xE4: "SPDM_KEY_EXCHANGE",
    0xE5: "SPDM_FINISH",
    0xE6: "SPDM_PSK_EXCHANGE",
    0xE7: "SPDM_PSK_FINISH",
    0xE8: "SPDM_HEARTBEAT",
    0xE9: "SPDM_KEY_UPDATE",
    0xEA: "SPDM_GET_ENCAPSULATED_REQUEST",
    0xEB: "SPDM_DELIVER_ENCAPSULATED_RESPONSE",
    0xEC: "SPDM_END_SESSION",
    0xED: "SPDM_GET_CSR",
    0xEE: "SPDM_SET_CERTIFICATE",
    0xEF: "SPDM_GET_MEASUREMENT_EXTENSION_LOG",
    0xF1: "SPDM_SEND_EVENT",
    0xFE: "SPDM_VENDOR_DEFINED_REQUEST",
    0xFF: "SPDM_RESPOND_IF_READY",
}

# spdm.h:468-478. Only the size matters here, and it is the digest length of
# the algorithm rather than a table of names, because the only use is skipping
# the RootHash field to find where the certificates start.
BASE_HASH = {
    0x00000001: ("SHA_256", 32),
    0x00000002: ("SHA_384", 48),
    0x00000004: ("SHA_512", 64),
    0x00000008: ("SHA3_256", 32),
    0x00000010: ("SHA3_384", 48),
    0x00000020: ("SHA3_512", 64),
    0x00000040: ("SM3_256", 32),
}

# spdm.h:714-760, and libspdm_rsp_certificate.c:212-229 for what the responder
# actually writes. Bit 7 of Param1 selects between two layouts of the same
# response, and this repository's own captures use BOTH: the 4.0.0-rc pair sets
# it whenever LARGE_RESP_CAP was negotiated, the 3.8.0 pair never does.
#
#   small (bit clear)   PortionLength u16 @4, RemainderLength u16 @6, chain @8
#   large (bit set)     both u16 fields written as ZERO, then
#                       LargePortionLength u32 @8, LargeRemainderLength u32 @12,
#                       chain @16
#
# The trap is that the small fields are still present in the large layout and
# are zero, so a parser that reads offset 4 unconditionally gets a chain of
# length nought and reports it as an empty chain rather than as an error. That
# is what this file did on its first run against a 4.0.0-rc capture, and the
# only reason it was noticed is that the arm taken with the 3.8.0 build
# reconstructed its chains and the 4.0.0-rc arms did not.
SPDM_CERT_LARGE_CHAIN = 0x80
SPDM_CERT_SLOT_ID_MASK = 0x0F
CERT_SMALL_HEADER_BYTES = 8
CERT_LARGE_HEADER_BYTES = 16


# A response code has bit 7 clear, a request code has it set. That is the
# convention the table above obeys without exception, so direction is derived
# rather than stored twice.
def is_request(code: int) -> bool:
    return bool(code & 0x80)


def spdm_version(byte: int) -> str:
    return f"{byte >> 4}.{byte & 0x0F}"


def framing_bytes(linktype: int) -> int | None:
    """How many bytes sit in front of the SPDM message, for this link type."""
    if linktype == LINKTYPE_MCTP:
        return MCTP_HEADER_BYTES + 1        # header + message type
    return None                             # PCI DOE has its own; not measured here


def messages(path: Path) -> tuple[dict, list[dict]]:
    summary, packets = read_pcap(path)
    raw = path.read_bytes()
    framing = framing_bytes(summary["linktype"])

    out: list[dict] = []
    for p in packets:
        body = raw[p["file_offset"]:p["file_offset"] + p["captured_bytes"]]
        entry = {
            "packet": p["index"] + 1,       # spdm_dump numbers from 1
            "captured_bytes": p["captured_bytes"],
            "framing_bytes": framing,
            "spdm_bytes": None,
            "code": None,
            "name": None,
            "direction": None,
            "version": None,
            "why": None,
        }
        if framing is None:
            entry["why"] = f"link type {summary['linktype']} is not one this tool frames"
        elif len(body) < framing + 4:
            entry["why"] = (f"{len(body)} bytes is too few for {framing} of framing "
                            f"plus a 4-byte SPDM header")
        else:
            mtype = body[MCTP_HEADER_BYTES]
            spdm = body[framing:]
            if mtype == MCTP_TYPE_SECURED:
                entry["name"] = "SECURED_MESSAGE"
                entry["spdm_bytes"] = len(spdm)
                entry["why"] = "encrypted; contents are not readable from a capture"
            elif mtype != MCTP_TYPE_SPDM:
                entry["why"] = f"MCTP message type 0x{mtype:02x} is neither SPDM nor secured"
            else:
                code = spdm[1]
                entry["spdm_bytes"] = len(spdm)
                entry["code"] = code
                entry["name"] = SPDM_CODES.get(code, f"UNKNOWN_0x{code:02x}")
                entry["direction"] = "REQ->RSP" if is_request(code) else "RSP->REQ"
                entry["version"] = spdm_version(spdm[0])
                # Kept for the certificate walk and stripped before any output.
                # A JSON file carrying every message twice would be a capture
                # with extra steps.
                entry["_spdm"] = spdm
        out.append(entry)

    by_type: dict[str, dict] = {}
    for e in out:
        if e["name"] is None:
            continue
        slot = by_type.setdefault(e["name"], {"count": 0, "bytes": 0})
        slot["count"] += 1
        slot["bytes"] += e["spdm_bytes"] or 0

    parsed = [e for e in out if e["spdm_bytes"] is not None]
    stats = {
        "file": str(path),
        "linktype": summary["linktype"],
        "linktype_label": summary["linktype_label"],
        "packets": summary["packets"],
        "captured_bytes_total": summary["captured_bytes_total"],
        "framing_bytes_each": framing,
        "messages_parsed": len(parsed),
        "messages_unparsed": len(out) - len(parsed),
        "spdm_bytes_total": sum(e["spdm_bytes"] for e in parsed),
        "by_type": dict(sorted(by_type.items(), key=lambda kv: (-kv[1]["bytes"], kv[0]))),
    }
    # ★ The independent variable, and the threshold that decides how many
    # messages a given number of bytes takes. Both are read from the capture's
    # own bytes; harness/fields.py reaches the same two from spdm_dump's
    # rendering, and --check requires them to agree.
    stats["algorithms"] = algorithms(out)
    stats["capabilities"] = capabilities(out)
    stats["errors"] = errors(out)
    stats["chunking"] = chunking(stats["by_type"], stats["errors"])

    # ── the capture as the two endpoints saw it ─────────────────────────────
    #
    # Everything above this line counts what went over the wire and is left
    # alone: by_type, spdm_bytes_total and the chunking counts are wire facts,
    # bench/claims.json asserts several of them at a tolerance of zero, and a
    # reassembled view would make them count some bytes twice.
    #
    # The certificate walk is the one thing that wants the other view, because
    # a chain larger than DataTransferSize is never in a CERTIFICATE message at
    # all. Before 2026-09-14 that made this tool report zero chains for every
    # post-quantum arm while the whole chain sat in the file.
    logical, stats["chunking"]["reassembled"] = dechunk(out)

    # ── the same by-type table, over the logical view ───────────────────────
    #
    # ★ `by_type` is the wire and `logical_by_type` is what the two endpoints
    # exchanged. For an unchunked capture they are identical. For a chunked one
    # `by_type` has SPDM_CHUNK_RESPONSE where `logical_by_type` has
    # SPDM_CERTIFICATE, and the second is the only one a question like "how big
    # is a CHALLENGE_AUTH at ML-DSA-87" can be asked of — at that algorithm the
    # message exceeds DataTransferSize and there IS no single CHALLENGE_AUTH
    # message on the wire to measure.
    #
    # Both are published because a reader needs both and they answer different
    # questions. Addressing a reassembled message by its type rather than by its
    # position in the chunk sequence is also what keeps bench/claims.json from
    # breaking when a flow gains a message.
    logical_by_type: dict[str, dict] = {}
    for e in logical:
        if e.get("name") is None or e.get("spdm_bytes") is None:
            continue
        slot = logical_by_type.setdefault(e["name"], {"count": 0, "bytes": 0})
        slot["count"] += 1
        slot["bytes"] += e["spdm_bytes"]
    stats["logical_by_type"] = dict(sorted(logical_by_type.items(),
                                           key=lambda kv: (-kv[1]["bytes"], kv[0])))
    # The identity harness/verify_repo.sh already asserts between pcapcount.py
    # and fields.py, restated here from this tool's own numbers so that it is
    # checked against the thing it is derived from rather than against a
    # remembered constant.
    stats["certificates"] = certificates(logical)
    stats["framing_accounts_for_the_difference"] = (
        framing is not None
        and stats["captured_bytes_total"]
        == stats["spdm_bytes_total"] + framing * len(parsed)
        + sum(e["captured_bytes"] for e in out if e["spdm_bytes"] is None)
    )
    for e in out:
        e.pop("_spdm", None)
    return stats, out


# ── the negotiated result, read out of the ALGORITHMS response itself ──────
#
# Transcribed from the pinned libspdm's spdm.h, lines 448-524 and 862. Same
# trade as the message-code table above: a header parser would be a third thing
# to keep correct, and --check cannot catch a name that drifts because a wrong
# name stays self-consistent. Re-read after a version bump.
#
# Why this is here at all, when harness/fields.py already reports the same
# twelve values: because it is the INDEPENDENT VARIABLE of every cost number
# this repository publishes, and standing rule 12 says that where two tools can
# reach the same quantity by different routes they are made to agree. fields.py
# reads spdm_dump's rendering of the message; this reads the message. `--check`
# requires the two to produce the same answer, which turns "the responder
# negotiated ML-DSA-65" from one parser's opinion into two parsers that share
# no input agreeing.

BASE_ASYM = {
    0x00000001: "RSASSA_2048", 0x00000002: "RSAPSS_2048",
    0x00000004: "RSASSA_3072", 0x00000008: "RSAPSS_3072",
    0x00000010: "ECDSA_P256", 0x00000020: "RSASSA_4096",
    0x00000040: "RSAPSS_4096", 0x00000080: "ECDSA_P384",
    0x00000100: "ECDSA_P521", 0x00000200: "SM2_P256",
    0x00000400: "EDDSA_25519", 0x00000800: "EDDSA_448",
}

PQC_ASYM = {
    0x00000001: "ML_DSA_44", 0x00000002: "ML_DSA_65", 0x00000004: "ML_DSA_87",
    0x00000008: "SLH_DSA_SHA2_128S", 0x00000010: "SLH_DSA_SHAKE_128S",
    0x00000020: "SLH_DSA_SHA2_128F", 0x00000040: "SLH_DSA_SHAKE_128F",
    0x00000080: "SLH_DSA_SHA2_192S", 0x00000100: "SLH_DSA_SHAKE_192S",
    0x00000200: "SLH_DSA_SHA2_192F", 0x00000400: "SLH_DSA_SHAKE_192F",
    0x00000800: "SLH_DSA_SHA2_256S", 0x00001000: "SLH_DSA_SHAKE_256S",
    0x00002000: "SLH_DSA_SHA2_256F", 0x00004000: "SLH_DSA_SHAKE_256F",
}

DHE_GROUP = {
    0x00000001: "FFDHE_2048", 0x00000002: "FFDHE_3072", 0x00000004: "FFDHE_4096",
    0x00000008: "SECP_256_R1", 0x00000010: "SECP_384_R1",
    0x00000020: "SECP_521_R1", 0x00000040: "SM2_P256",
}

AEAD_SUITE = {0x00000001: "AES_128_GCM", 0x00000002: "AES_256_GCM",
              0x00000004: "CHACHA20_POLY1305", 0x00000008: "AEAD_SM4_GCM"}

KEY_SCHEDULE = {0x00000001: "HMAC_HASH"}

KEM_ALG = {0x00000001: "ML_KEM_512", 0x00000002: "ML_KEM_768",
           0x00000004: "ML_KEM_1024"}

MEAS_HASH = {
    0x00000001: "RAW_BIT", 0x00000002: "SHA_256", 0x00000004: "SHA_384",
    0x00000008: "SHA_512", 0x00000010: "SHA3_256", 0x00000020: "SHA3_384",
    0x00000040: "SHA3_512", 0x00000080: "SM3_256",
}

MEAS_SPEC = {0x01: "DMTF"}
MEL_SPEC = {0x01: "DMTF"}

# OtherParamsSelection is not a plain bitmask: bits 0-3 are an enumerated
# opaque-data format and bit 4 is an independent flag. Decoding it as a mask
# would report OPAQUE_FMT_1 as two separate bits.
OPAQUE_FMT = {0x0: None, 0x1: "OPAQUE_FMT_0", 0x2: "OPAQUE_FMT_1"}
OTHER_MULTI_KEY = 0x10

# AlgType -> (name, table). spdm.h:431-436. Types 6 and 7 arrived in 1.4.
ALG_STRUCT = {
    2: ("DHE", DHE_GROUP),
    3: ("AEAD", AEAD_SUITE),
    4: ("ReqAsym", BASE_ASYM),
    5: ("KeySchedule", KEY_SCHEDULE),
    6: ("ReqPqcAsym", PQC_ASYM),
    7: ("KEM", KEM_ALG),
}

# The fixed part of an ALGORITHMS response, for every version that has
# AlgStructure tables. It is 36 bytes in 1.1 through 1.4: the fields added in
# 1.2, 1.3 and 1.4 each took bytes out of a reserved run rather than extending
# the structure, which is why one offset table serves all of them.
ALGORITHMS_FIXED_BYTES = 36


def bit_names(value: int, table: dict) -> list[str]:
    """Every bit set in value, named. Unknown bits are reported, not dropped.

    A selection field in an ALGORITHMS *response* carries at most one bit, so a
    list of two is itself a finding rather than a formatting problem — and a
    bit with no name is the case that matters after a version bump, which is
    why it comes back as 0x… rather than silently vanishing.
    """
    out = []
    for bit in sorted(table):
        if value & bit:
            out.append(table[bit])
    unknown = value & ~sum(table)
    if unknown:
        out.append(f"0x{unknown:08x}")
    return out


def algorithms(entries: list[dict]) -> dict:
    """The ALGORITHMS response, parsed from its bytes.

    Returns the negotiated selection per group, using the same group names
    harness/fields.py uses, so that --check can compare them directly. Groups
    the response does not carry are absent; groups it carries with nothing
    selected are an empty list. Those are different observations and the
    distinction is the one that says whether a responder declined an algorithm
    or was never offered one.
    """
    out: dict = {"present": False, "negotiated": {}, "alg_struct_count": None,
                 "spdm_version": None, "why": None}
    msg = None
    for e in entries:
        if e.get("name") == "SPDM_ALGORITHMS" and "_spdm" in e:
            msg = e["_spdm"]
            break
    if msg is None:
        out["why"] = "no ALGORITHMS response in this capture"
        return out
    if len(msg) < ALGORITHMS_FIXED_BYTES:
        out["why"] = (f"the ALGORITHMS response is {len(msg)} bytes, fewer than "
                      f"the {ALGORITHMS_FIXED_BYTES}-byte fixed part")
        return out

    out["present"] = True
    out["spdm_version"] = spdm_version(msg[0])
    n_struct = msg[2]
    out["alg_struct_count"] = n_struct

    neg = out["negotiated"]
    neg["MeasSpec"] = bit_names(msg[6], MEAS_SPEC)
    other = msg[7]
    fmt = OPAQUE_FMT.get(other & 0x0F, f"0x{other & 0x0F:x}")
    neg["OtherParam"] = ([fmt] if fmt else []) + \
                        (["MULTI_KEY_CONN"] if other & OTHER_MULTI_KEY else [])
    neg["MeasHash"] = bit_names(int.from_bytes(msg[8:12], "little"), MEAS_HASH)
    neg["Asym"] = bit_names(int.from_bytes(msg[12:16], "little"), BASE_ASYM)
    neg["Hash"] = bit_names(int.from_bytes(msg[16:20], "little"), BASE_HASH_NAMES)
    neg["PqcAsym"] = bit_names(int.from_bytes(msg[20:24], "little"), PQC_ASYM)

    # The AlgStructure tables. Each is two bytes of header plus FixedAlgCount
    # bytes of selection plus four bytes per external algorithm; walking them
    # by length rather than by index is what keeps an unknown AlgType from
    # shifting every table after it.
    off = ALGORITHMS_FIXED_BYTES + 4 * msg[32] + 4 * msg[33]
    for _ in range(n_struct):
        if off + 2 > len(msg):
            out["why"] = (f"an AlgStructure table starts at offset {off}, past "
                          f"the end of a {len(msg)}-byte response")
            break
        alg_type = msg[off]
        fixed = (msg[off + 1] >> 4) & 0x0F
        ext = msg[off + 1] & 0x0F
        body = msg[off + 2:off + 2 + fixed]
        if len(body) < fixed:
            out["why"] = f"AlgStructure {alg_type} is truncated"
            break
        name_table = ALG_STRUCT.get(alg_type)
        if name_table is None:
            neg[f"AlgType_{alg_type}"] = [f"0x{int.from_bytes(body, 'little'):x}"]
        else:
            name, table = name_table
            neg[name] = bit_names(int.from_bytes(body, "little"), table)
        off += 2 + fixed + 4 * ext

    return out


def capabilities(entries: list[dict]) -> dict:
    """DataTransferSize and MaxSPDMmsgSize, from both sides.

    DataTransferSize is the largest single message an endpoint will accept, and
    it is the reason SPDM has a chunking layer at all: a certificate chain
    larger than it cannot be delivered in one response. That threshold is
    invisible in a byte count and decisive for one — an ML-DSA-65 chain is
    several times the emulator's 4,608-byte default, so the same experiment run
    with a larger DataTransferSize would produce the same total in a different
    number of messages.

    spdm.h's spdm_capabilities_response_t: reserved(1) ct_exponent(1)
    ext_flags(2) flags(4) data_transfer_size(4) max_spdm_msg_size(4), the last
    two added in 1.2.
    """
    out: dict = {}
    for want, who in (("SPDM_GET_CAPABILITIES", "requester"),
                      ("SPDM_CAPABILITIES", "responder")):
        side: dict = {"present": False}
        for e in entries:
            if e.get("name") != want or "_spdm" not in e:
                continue
            msg = e["_spdm"]
            side["present"] = True
            side["spdm_version"] = spdm_version(msg[0])
            if len(msg) >= 12:
                side["ct_exponent"] = msg[5]
                side["flags"] = f"0x{int.from_bytes(msg[8:12], 'little'):08x}"
            if len(msg) >= 20:
                side["data_transfer_size"] = int.from_bytes(msg[12:16], "little")
                side["max_spdm_msg_size"] = int.from_bytes(msg[16:20], "little")
            break
        out[who] = side
    return out


# spdm.h:977-1009. Only the codes this project's captures actually produce are
# worth naming individually; the rest come back as 0x…, which is the answer
# that makes an unexpected one visible.
SPDM_ERROR_CODES = {
    0x01: "InvalidRequest", 0x03: "Busy", 0x04: "UnexpectedRequest",
    0x05: "Unspecified", 0x06: "DecryptError", 0x07: "UnsupportedRequest",
    0x08: "RequestInFlight", 0x09: "InvalidResponseCode",
    0x0A: "SessionLimitExceeded", 0x0B: "SessionRequired",
    0x0C: "ResetRequired", 0x0D: "ResponseTooLarge", 0x0E: "RequestTooLarge",
    0x0F: "LargeResponse", 0x10: "MessageLost", 0x11: "InvalidPolicy",
    0x12: "DataTooLarge", 0x41: "VersionMismatch", 0x42: "ResponseNotReady",
    0x43: "RequestResynch", 0x44: "OperationFailed",
    0x45: "NoPendingRequests", 0x46: "RequestSessionTerminated",
    0x47: "InvalidState", 0xFF: "VendorDefined",
}

SPDM_ERROR_LARGE_RESPONSE = 0x0F


def errors(entries: list[dict]) -> dict:
    """Every ERROR response, by the code it carries in Param1.

    Counting ERROR messages is not the same as counting failures, and this
    project has a capture that proves it: walking measurement indices produces
    246 ErrorCode=0x01 responses in a handshake that is working exactly as
    intended, while three ErrorCode=0x0F in a different arm are the responder
    saying "this reply does not fit" and starting the chunking exchange.

    Folding those together — which the first version of chunking() below did —
    reports a healthy index walk as 246 large-response events.
    """
    out: dict[str, int] = {}
    for e in entries:
        if e.get("name") != "SPDM_ERROR" or "_spdm" not in e:
            continue
        msg = e["_spdm"]
        if len(msg) < 3:
            out["truncated"] = out.get("truncated", 0) + 1
            continue
        code = msg[2]
        name = SPDM_ERROR_CODES.get(code, f"0x{code:02x}")
        out[name] = out.get(name, 0) + 1
    return dict(sorted(out.items(), key=lambda kv: (-kv[1], kv[0])))


# ── CHUNK_RESPONSE, reassembled ─────────────────────────────────────────────
#
# DSP0274 1.4.0 §"CHUNK_RESPONSE response message". Offsets, not a guess:
#
#   0  SPDMVersion            4  ChunkSeqNo      (2 bytes)
#   1  RequestResponseCode    6  Reserved        (2 bytes)
#   2  Param1 = attributes    8  ChunkSize       (4 bytes)
#   3  Param2 = Handle       12  LargeMessageSize (4 bytes, FIRST CHUNK ONLY)
#
# so the header is 16 bytes when ChunkSeqNo is 0 and 12 afterwards, and
# SPDMchunk follows it. Checked against the captures before being relied on:
# in bench/data/w8-pqc-matrix-*/P2-all.pcap the first CHUNK_RESPONSE is 4,352
# SPDM bytes with ChunkSize 0x10f0 = 4,336, and 4,352 - 4,336 = 16; the second
# is 4,352 with ChunkSize 0x10f4 = 4,340, and the difference is 12.
CHUNK_RSP_HEADER_BYTES = 12
CHUNK_RSP_FIRST_HEADER_BYTES = 16
CHUNK_ATTR_LAST = 0x01


def dechunk(entries: list[dict]) -> tuple[list[dict], dict]:
    """Put back together the messages SPDM's chunking layer took apart.

    Returns (logical_entries, report). `logical_entries` is the capture as the
    two endpoints saw it: every completed CHUNK_RESPONSE sequence replaced by
    the single message it carried, everything else passed through untouched.

    ★ Why this exists, and why it does not change any existing number.
    ------------------------------------------------------------------
    A certificate chain larger than the negotiated DataTransferSize never
    appears in a CERTIFICATE message at all. The responder answers
    ERROR(LargeResponse) and the chain arrives inside CHUNK_RESPONSE, so
    certificates() — which reads CERTIFICATE — reported zero chains for every
    post-quantum arm while every byte of the chain sat in the capture.
    `docs/pqc-cost.md` §5 said reassembling them was week 8's job; this is it.
    Until then the only tool that could reach the post-quantum chain length was
    spdm_dump, whose LIBSPDM_MAX_CERT_CHAIN_SIZE is a compile-time 0x1000 and
    which therefore truncates its own decode of the thing being measured. One
    tool, one route, and that route is a prefix.
    ★ Standing rule 12: where two tools can reach the same quantity by
    different routes, they are made to agree. This is the second route, and it
    reads the capture's own bytes rather than another program's rendering.
    Nothing above this function is recomputed from the result — by_type,
    spdm_bytes_total and the chunking counts stay exactly what went over the
    wire, because that is what they are for and because bench/claims.json
    asserts several of them at a tolerance of zero.

    What it refuses to do
    ---------------------
    CHUNK_SEND and CHUNK_SEND_ACK carry a large REQUEST the other way, with a
    different tail layout. Not one capture in this repository contains either,
    so there is nothing to test an implementation against, and an untested
    reassembler that silently produced a plausible message would be worse than
    an absent one. They are counted and named as unhandled instead.
    """
    report: dict = {
        "sequences": [],
        "notes": [],
        "messages_recovered": 0,
        "bytes_recovered": 0,
        "unhandled": {},
    }
    logical: list[dict] = []
    open_seq: dict | None = None

    def close(seq: dict, ok: bool, why: str | None = None) -> None:
        rec = {
            "handle": seq["handle"],
            "packets": seq["packets"],
            "chunks": len(seq["packets"]),
            "declared_total": seq["declared_total"],
            "assembled_bytes": len(seq["bytes"]),
            # What the sequence cost on the wire, as against what it carried.
            # The difference is the chunking layer's own overhead, and a figure
            # that attributes every byte of a capture to a phase needs both.
            "wire_bytes": seq["wire_bytes"],
            "complete": ok,
        }
        if why:
            rec["why"] = why
            report["notes"].append(f"packets {seq['packets'][0]}-"
                                   f"{seq['packets'][-1]}: {why}")
        if ok:
            # What the sequence turned out to be carrying. Worth recording: at
            # ML-DSA-87 it is no longer only certificates — a CHALLENGE_AUTH
            # with a 4,627-byte signature also exceeds a 4,608-byte
            # DataTransferSize, and a reader looking at twenty-two chunk round
            # trips needs to know which messages they belong to.
            rec["carried"] = SPDM_CODES.get(seq["bytes"][1],
                                            f"UNKNOWN_0x{seq['bytes'][1]:02x}")
        report["sequences"].append(rec)
        if not ok:
            return
        msg = bytes(seq["bytes"])
        report["messages_recovered"] += 1
        report["bytes_recovered"] += len(msg)
        logical.append({
            "packet": seq["packets"][0],
            "captured_bytes": None,
            "framing_bytes": None,
            "spdm_bytes": len(msg),
            "code": msg[1],
            "name": SPDM_CODES.get(msg[1], f"UNKNOWN_0x{msg[1]:02x}"),
            "direction": "RSP->REQ" if not is_request(msg[1]) else "REQ->RSP",
            "version": spdm_version(msg[0]),
            "why": None,
            "reassembled_from": list(seq["packets"]),
            "_spdm": msg,
        })

    for e in entries:
        name = e.get("name")

        if name in ("SPDM_CHUNK_SEND", "SPDM_CHUNK_SEND_ACK"):
            report["unhandled"][name] = report["unhandled"].get(name, 0) + 1
            logical.append(e)
            continue

        if name != "SPDM_CHUNK_RESPONSE" or "_spdm" not in e:
            # A CHUNK_GET is the request half and carries no payload; it is kept
            # so a reader can still count round trips in the logical view.
            logical.append(e)
            continue

        msg = e["_spdm"]
        if len(msg) < CHUNK_RSP_HEADER_BYTES:
            report["notes"].append(
                f"packet {e['packet']}: CHUNK_RESPONSE is {len(msg)} bytes, too "
                f"few for its {CHUNK_RSP_HEADER_BYTES}-byte header")
            continue
        attr = msg[2]
        handle = msg[3]
        seq_no = int.from_bytes(msg[4:6], "little")
        size = int.from_bytes(msg[8:12], "little")
        first = seq_no == 0
        head = CHUNK_RSP_FIRST_HEADER_BYTES if first else CHUNK_RSP_HEADER_BYTES
        large_total = int.from_bytes(msg[12:16], "little") if first else None
        payload = msg[head:head + size]

        if len(payload) != size:
            report["notes"].append(
                f"packet {e['packet']}: ChunkSize says {size}, the message "
                f"carries {len(payload)} after a {head}-byte header")
            if open_seq is not None:
                close(open_seq, False, "a chunk in this sequence was short")
                open_seq = None
            continue

        if first:
            if open_seq is not None:
                close(open_seq, False,
                      "a new sequence began before this one's LastChunk")
            open_seq = {"handle": handle, "packets": [e["packet"]],
                        "declared_total": large_total, "next_seq": 1,
                        "wire_bytes": len(msg),
                        "bytes": bytearray(payload)}
        else:
            if open_seq is None:
                report["notes"].append(
                    f"packet {e['packet']}: ChunkSeqNo {seq_no} with no "
                    f"sequence open — the first chunk is missing from this "
                    f"capture")
                continue
            if handle != open_seq["handle"]:
                close(open_seq, False,
                      f"handle changed from {open_seq['handle']} to {handle} "
                      f"mid-sequence")
                open_seq = None
                continue
            if seq_no != open_seq["next_seq"]:
                close(open_seq, False,
                      f"ChunkSeqNo jumped from {open_seq['next_seq'] - 1} to "
                      f"{seq_no}; a chunk is missing and the bytes either side "
                      f"of the gap do not join")
                open_seq = None
                continue
            open_seq["packets"].append(e["packet"])
            open_seq["next_seq"] += 1
            open_seq["wire_bytes"] += len(msg)
            open_seq["bytes"] += payload

        if attr & CHUNK_ATTR_LAST:
            total = open_seq["declared_total"]
            got = len(open_seq["bytes"])
            if total is not None and got != total:
                close(open_seq, False,
                      f"LargeMessageSize declared {total} bytes and the chunks "
                      f"add up to {got}")
            else:
                close(open_seq, True)
            open_seq = None

    if open_seq is not None:
        close(open_seq, False,
              "the capture ends before LastChunk — this message was still "
              "arriving")

    return logical, report


def chunking(by_type: dict, by_error: dict) -> dict:
    """How much of this capture is the SPDM-layer chunking of a large message.

    Not a decode: the four chunk message types are counted from the
    RequestResponseCode byte like every other type. What it answers is whether
    a capture's message COUNT is a property of the algorithms or a property of
    DataTransferSize, which is the question a per-message table cannot be read
    without.

    ★ It is also the reason a certificate chain can be missing from
    `certificates` while every byte of it is in the capture: the chain arrives
    inside CHUNK_RESPONSE rather than CERTIFICATE, and the chain walk reads
    CERTIFICATE. The gap is reported rather than papered over — see
    `certificates.notes`.
    """
    names = ("SPDM_CHUNK_GET", "SPDM_CHUNK_RESPONSE",
             "SPDM_CHUNK_SEND", "SPDM_CHUNK_SEND_ACK")
    counts = {n: by_type.get(n, {}).get("count", 0) for n in names}
    total_bytes = sum(by_type.get(n, {}).get("bytes", 0) for n in names)
    return {"messages": counts,
            "chunked": any(counts.values()),
            "chunk_bytes_total": total_bytes,
            "errors_by_code": by_error,
            "large_response_errors": by_error.get("LargeResponse", 0)}


# Kept under its original name because certificates() reads the hash WIDTH
# rather than the name, and the width is the only thing a chain walk needs.
# It now goes through the parser above instead of reaching into the message a
# second time — two readings of one field inside one file is the thing this
# file criticises other tools for.
BASE_HASH_NAMES = {k: v[0] for k, v in BASE_HASH.items()}
BASE_HASH_BYTES = {v[0]: v[1] for v in BASE_HASH.values()}


def negotiated_hash(entries: list[dict]) -> tuple[str | None, int | None]:
    """The base hash algorithm, read out of the ALGORITHMS response.

    Standing rule 8: read the independent variable back rather than assuming
    it. The RootHash field's width is whatever this negotiation settled on, and
    a chain parsed with the wrong width is off by sixteen bytes without
    complaining.
    """
    got = algorithms(entries)["negotiated"].get("Hash") or []
    if len(got) != 1:
        return None, None
    return got[0], BASE_HASH_BYTES.get(got[0])


def certificates(entries: list[dict]) -> dict:
    """Reassemble each slot's certificate chain from the responses that carried it."""
    hash_name, hash_bytes = negotiated_hash(entries)
    out = {
        "roundtrips": 0,
        "base_hash": hash_name,
        "root_hash_bytes": hash_bytes,
        "slots": [],
        "notes": [],
    }

    # A slot is fetched in a burst of request/response pairs, and the same slot
    # can legitimately be fetched twice in one connection (the mutual-auth
    # exchange does exactly that). So chains are cut on the RemainderLength
    # reaching zero rather than on the slot id changing, which would merge two
    # fetches of slot 0 into one impossible chain.
    current: dict | None = None
    for e in entries:
        name = e.get("name")
        if name == "SPDM_GET_CERTIFICATE":
            out["roundtrips"] += 1
            continue
        if name != "SPDM_CERTIFICATE" or "_spdm" not in e:
            continue
        msg = e["_spdm"]
        large = bool(msg[2] & SPDM_CERT_LARGE_CHAIN)
        head = CERT_LARGE_HEADER_BYTES if large else CERT_SMALL_HEADER_BYTES
        if len(msg) < head:
            out["notes"].append(
                f"packet {e['packet']}: CERTIFICATE is {len(msg)} bytes, too "
                f"few for its {head}-byte {'large' if large else 'small'} header")
            continue
        slot = msg[2] & SPDM_CERT_SLOT_ID_MASK
        if large:
            portion = int.from_bytes(msg[8:12], "little")
            remainder = int.from_bytes(msg[12:16], "little")
            # The 16-bit pair must be zero in this layout. Checking it is what
            # tells "the responder used the large form" apart from "this file
            # guessed the wrong form", which otherwise look identical.
            if msg[4:8] != b"\x00\x00\x00\x00":
                out["notes"].append(
                    f"packet {e['packet']}: LargeCertChain is set but the "
                    f"16-bit Portion/Remainder fields are "
                    f"{msg[4:8].hex(' ')} rather than zero")
                continue
        else:
            portion = int.from_bytes(msg[4:6], "little")
            remainder = int.from_bytes(msg[6:8], "little")
        chunk = msg[head:head + portion]
        if len(chunk) != portion:
            out["notes"].append(
                f"packet {e['packet']}: PortionLength says {portion}, the "
                f"message carries {len(chunk)}")
            continue

        if current is None:
            current = {
                "slot": slot,
                "direction": e["direction"],
                "first_packet": e["packet"],
                "declared_total": portion + remainder,
                "large": large,
                # Which route this chain reached the walk by. A chain that came
                # through chunking is the same chain, and a reader who cannot
                # tell the two apart cannot tell why a capture has three
                # CERTIFICATE messages in one arm and none in another.
                "via": "chunking" if e.get("reassembled_from") else "certificate",
                "portions": [],
                "bytes": bytearray(),
            }
        elif e.get("reassembled_from") and current["via"] == "certificate":
            current["via"] = "mixed"
        current["portions"].append(portion)
        current["bytes"] += chunk
        if remainder == 0:
            out["slots"].append(_settle_chain(current, hash_bytes))
            current = None

    if current is not None:
        current["incomplete"] = True
        out["slots"].append(_settle_chain(current, hash_bytes))

    complete = [c for c in out["slots"] if c.get("closes")]
    out["chains"] = len(out["slots"])
    out["chains_that_close"] = len(complete)
    return out


def _settle_chain(chain: dict, hash_bytes: int | None) -> dict:
    """Two equations on one chain: the portions, and the chain's own Length."""
    raw = bytes(chain.pop("bytes"))
    total = sum(chain["portions"])
    settled = {
        "slot": chain["slot"],
        "direction": chain["direction"],
        "first_packet": chain["first_packet"],
        "large_form": chain.get("large"),
        "via": chain.get("via"),
        "messages": len(chain["portions"]),
        "portions": chain["portions"],
        "chain_bytes": total,
        "declared_total": chain["declared_total"],
        "length_field": None,
        "certificates_bytes": None,
        "closes": False,
        "why": None,
    }
    if chain.get("incomplete"):
        settled["why"] = "the last response still declared a non-zero RemainderLength"
        return settled
    if total != chain["declared_total"]:
        settled["why"] = (f"the portions sum to {total}, the first response "
                          f"declared {chain['declared_total']}")
        return settled
    if len(raw) < 4:
        settled["why"] = "too few bytes for the chain's own Length field"
        return settled
    # DSP0274 splits these four bytes into Length(2) and Reserved(2); libspdm
    # declares one uint32 (spdm.h:772-778). With Reserved zero the two readings
    # are the same number, and that is asserted rather than assumed.
    length = int.from_bytes(raw[0:4], "little")
    settled["length_field"] = length
    settled["reserved_is_zero"] = raw[2:4] == b"\x00\x00"
    if length != total:
        settled["why"] = (f"the chain's own Length field says {length}, "
                          f"{total} bytes arrived")
        return settled
    settled["closes"] = True
    if hash_bytes is not None and total >= 4 + hash_bytes:
        settled["certificates_bytes"] = total - 4 - hash_bytes
        settled["root_hash"] = raw[4:4 + hash_bytes].hex()
    return settled


# ── the checks above, as something that can be fed a wrong answer ───────────
#
# docs/roadmap.md standing rule 11: a check is worth what it rejects, and
# something has to prove it rejects. The agreement test is a string comparison
# between two dictionaries, and a string comparison that has only ever been run
# on agreeing inputs is arithmetic that happens to agree.
#
# So the comparison is a function rather than a loop inside cross_check, and
# selftest() hands it a pair that disagrees and requires it to say so.


def compare_negotiated(mine: dict, theirs: dict) -> tuple[list[str], int]:
    """Two readings of the negotiated algorithms, reconciled.

    A group named by only one side is reported and NOT failed: fields.py emits
    a key for every group it knows about, empty when the response carried none,
    while this tool emits a key only for the AlgStructure tables that were
    actually present. Those are the same observation in two spellings, and
    failing it would make the check noisy in the one direction that teaches
    nothing.
    """
    lines: list[str] = []
    fails = 0
    shared = sorted(set(mine) & set(theirs))
    for g in shared:
        a = sorted(mine.get(g) or [])
        b = sorted(theirs.get(g) or [])
        if a != b:
            lines.append(f"FAIL negotiated {g}: capture says {a or ['-']}, "
                         f"decode says {b or ['-']}")
            fails += 1
    if shared and fails == 0:
        lines.append(f"ok    {len(shared)} negotiated algorithm groups agree, "
                     f"read from the message and from the decode")
    for label, only in (("capture", sorted(set(mine) - set(theirs))),
                        ("decode", sorted(set(theirs) - set(mine)))):
        if only:
            lines.append(f"--    named only by the {label}: {', '.join(only)}")
    return lines, fails


def _synthetic_capture(spdm_messages: list[bytes], path: Path) -> Path:
    """A capture built byte by byte, so the parser has something to be wrong about."""
    hdr = struct.pack("<IHHiIII", 0xA1B2C3D4, 2, 4, 0, 0, 65535, LINKTYPE_MCTP)
    body = b""
    for msg in spdm_messages:
        frame = b"\x01\x00\x00\x00" + bytes([MCTP_TYPE_SPDM]) + msg
        body += struct.pack("<IIII", 1700000000, 0, len(frame), len(frame)) + frame
    path.write_bytes(hdr + body)
    return path


def _algorithms_response(base_asym: int = 0x00000080,
                         base_hash: int = 0x00000002,
                         pqc_asym: int = 0x00000000,
                         meas_hash: int = 0x00000004,
                         dhe: int = 0x0010,
                         aead: int = 0x0002,
                         kem: int | None = None) -> bytes:
    """An ALGORITHMS response with a known selection in every group.

    Built from spdm.h's field offsets rather than copied out of a capture: a
    fixture taken from the same place as the thing it tests cannot detect a
    change that moves both.
    """
    structs = [(2, dhe), (3, aead), (5, 0x0001)]
    if kem is not None:
        structs.append((7, kem))
    tables = b""
    for alg_type, value in structs:
        tables += bytes([alg_type, 0x20]) + struct.pack("<H", value)
    fixed = bytearray(ALGORITHMS_FIXED_BYTES)
    fixed[0] = 0x14                       # SPDM 1.4
    fixed[1] = 0x63                       # ALGORITHMS
    fixed[2] = len(structs)               # Param1
    fixed[4:6] = struct.pack("<H", ALGORITHMS_FIXED_BYTES + len(tables))
    fixed[6] = 0x01                       # MeasurementSpecificationSel = DMTF
    fixed[7] = 0x02                       # OtherParamsSelection = OPAQUE_FMT_1
    fixed[8:12] = struct.pack("<I", meas_hash)
    fixed[12:16] = struct.pack("<I", base_asym)
    fixed[16:20] = struct.pack("<I", base_hash)
    fixed[20:24] = struct.pack("<I", pqc_asym)
    return bytes(fixed) + tables


def _error_response(code: int) -> bytes:
    return bytes([0x14, 0x7F, code, 0x00, 0x00])


def _certificate_response(portion: int, slot: int = 0, remainder: int = 0) -> bytes:
    """A small-form CERTIFICATE response whose chain closes.

    The chain body is a Length field the walk has to agree with plus a 48-byte
    root hash plus filler, so that a reassembled message can be checked all the
    way through to `closes` rather than only to its length.
    """
    body = bytearray(portion)
    body[0:4] = struct.pack("<I", portion)          # Length, Reserved zero
    for i in range(4, portion):
        body[i] = (i * 7) & 0xFF
    head = bytes([0x14, 0x02, slot, 0x00]) + struct.pack("<HH", portion, remainder)
    return head + bytes(body)


def _chunked(message: bytes, chunk_size: int) -> list[bytes]:
    """Split one SPDM message into the CHUNK_RESPONSE sequence that carries it.

    Built from DSP0274's field offsets, not copied from a capture: a fixture
    taken from the same place as the parser it tests cannot detect a change that
    moves both. The first chunk carries LargeMessageSize and so has a 16-byte
    header; the rest have 12.
    """
    out: list[bytes] = []
    off = 0
    seq = 0
    while off < len(message):
        piece = message[off:off + chunk_size]
        off += len(piece)
        last = 0x01 if off >= len(message) else 0x00
        head = bytes([0x14, 0x06, last, 0x01]) + struct.pack("<HH", seq, 0)
        head += struct.pack("<I", len(piece))
        if seq == 0:
            head += struct.pack("<I", len(message))
        out.append(head + piece)
        seq += 1
    return out


def selftest() -> int:
    """Feed every parser added for the post-quantum A/B something wrong."""
    import shutil
    import tempfile

    tmp = Path(tempfile.mkdtemp(prefix="pcapstat-selftest-"))
    fails = 0
    checks = 0

    def bad(msg):
        nonlocal fails
        fails += 1
        print(f"  FAIL {msg}")

    try:
        print("the negotiated selection is read from the message, field by field")
        checks += 1
        p = _synthetic_capture([_algorithms_response()], tmp / "a.pcap")
        neg = messages(p)[0]["algorithms"]["negotiated"]
        want = {"Hash": ["SHA_384"], "Asym": ["ECDSA_P384"], "PqcAsym": [],
                "MeasHash": ["SHA_384"], "DHE": ["SECP_384_R1"],
                "AEAD": ["AES_256_GCM"], "KeySchedule": ["HMAC_HASH"],
                "MeasSpec": ["DMTF"], "OtherParam": ["OPAQUE_FMT_1"]}
        for k, v in want.items():
            if neg.get(k) != v:
                bad(f"{k}: parsed {neg.get(k)}, built {v}")

        print("a different selection parses differently")
        # The check the positive case cannot make: a parser returning a
        # hard-coded table would satisfy everything above.
        checks += 1
        p = _synthetic_capture(
            [_algorithms_response(base_asym=0x00000010, pqc_asym=0x00000002,
                                  kem=0x0002)], tmp / "b.pcap")
        neg = messages(p)[0]["algorithms"]["negotiated"]
        if neg.get("Asym") != ["ECDSA_P256"]:
            bad(f"Asym: parsed {neg.get('Asym')}, built ECDSA_P256")
        if neg.get("PqcAsym") != ["ML_DSA_65"]:
            bad(f"PqcAsym: parsed {neg.get('PqcAsym')}, built ML_DSA_65")
        if neg.get("KEM") != ["ML_KEM_768"]:
            bad(f"KEM: parsed {neg.get('KEM')}, built ML_KEM_768")

        print("a bit with no name is reported rather than dropped")
        checks += 1
        p = _synthetic_capture([_algorithms_response(base_asym=0x00100000)],
                               tmp / "c.pcap")
        neg = messages(p)[0]["algorithms"]["negotiated"]
        if neg.get("Asym") != ["0x00100000"]:
            bad(f"an unnamed BaseAsymSel bit came back as {neg.get('Asym')}; "
                f"after a version bump that is a new algorithm, and silence "
                f"about it is the failure mode that outlasts the bump")

        print("a truncated ALGORITHMS response is a refusal, not a guess")
        checks += 1
        short = _algorithms_response()[:30]
        p = _synthetic_capture([short], tmp / "d.pcap")
        alg = messages(p)[0]["algorithms"]
        if alg["present"] or not alg["why"]:
            bad(f"a 30-byte ALGORITHMS response parsed as {alg}")

        print("ERROR codes are counted apart, not together")
        # ★ The companion for a defect this file had for one afternoon on
        # 2026-09-14: chunking() reported every SPDM_ERROR as a large-response
        # event, so a healthy measurement-index walk read as 246 of them.
        checks += 1
        p = _synthetic_capture(
            [_error_response(0x01)] * 3 + [_error_response(0x0F)] * 2,
            tmp / "e.pcap")
        stats = messages(p)[0]
        if stats["errors"] != {"InvalidRequest": 3, "LargeResponse": 2}:
            bad(f"errors by code: {stats['errors']}")
        if stats["chunking"]["large_response_errors"] != 2:
            bad(f"large_response_errors counted "
                f"{stats['chunking']['large_response_errors']} of 5 errors, "
                f"and only 2 of them say the response did not fit")

        # ── the chunk reassembler, and the four ways it must refuse ─────────
        #
        # Standing rule 11: a check is worth what it rejects. A reassembler
        # that concatenated payloads and trusted the result would pass the
        # first of these five and every one of the other four would be a
        # silently wrong certificate chain — which is the exact quantity this
        # was written to measure.
        print("a chunked message comes back byte-identical")
        checks += 1
        carried = _certificate_response(portion=600)
        p = _synthetic_capture(_chunked(carried, chunk_size=256), tmp / "k1.pcap")
        stats = messages(p)[0]
        rep = stats["chunking"]["reassembled"]
        if rep["messages_recovered"] != 1 or rep["bytes_recovered"] != len(carried):
            bad(f"reassembly recovered {rep['messages_recovered']} message(s) "
                f"and {rep['bytes_recovered']} bytes, built 1 and "
                f"{len(carried)}")
        chains = stats["certificates"]["slots"]
        if len(chains) != 1 or chains[0]["chain_bytes"] != 600:
            bad(f"the chain walk saw {len(chains)} chain(s) through the "
                f"reassembled message: {chains}")
        elif chains[0]["via"] != "chunking":
            bad(f"the chain came through chunking and is recorded as "
                f"{chains[0]['via']!r}")

        print("a gap in ChunkSeqNo is refused, not joined")
        checks += 1
        parts = _chunked(carried, chunk_size=256)
        del parts[1]                       # drop ChunkSeqNo 1
        p = _synthetic_capture(parts, tmp / "k2.pcap")
        rep = messages(p)[0]["chunking"]["reassembled"]
        if rep["messages_recovered"] != 0:
            bad("a sequence missing its second chunk was reassembled anyway; "
                "the bytes either side of a gap do not join and the result "
                "would be a chain of the right length and the wrong content")

        print("a lying ChunkSize is refused")
        checks += 1
        parts = _chunked(carried, chunk_size=256)
        bad_chunk = bytearray(parts[1])
        bad_chunk[8:12] = struct.pack("<I", 4096)      # claim far more than is there
        parts[1] = bytes(bad_chunk)
        p = _synthetic_capture(parts, tmp / "k3.pcap")
        rep = messages(p)[0]["chunking"]["reassembled"]
        if rep["messages_recovered"] != 0:
            bad("a chunk claiming 4096 bytes it does not carry was accepted")

        print("a LargeMessageSize that disagrees with the chunks is refused")
        checks += 1
        parts = _chunked(carried, chunk_size=256)
        first = bytearray(parts[0])
        first[12:16] = struct.pack("<I", len(carried) + 8)
        parts[0] = bytes(first)
        p = _synthetic_capture(parts, tmp / "k4.pcap")
        rep = messages(p)[0]["chunking"]["reassembled"]
        if rep["messages_recovered"] != 0:
            bad("a sequence whose declared total exceeds its chunks by 8 bytes "
                "was accepted; the two equations are the only thing that says "
                "the message is whole")

        print("a sequence that never sends LastChunk is refused")
        checks += 1
        parts = _chunked(carried, chunk_size=256)
        last = bytearray(parts[-1])
        last[2] = 0x00                                  # clear LastChunk
        parts[-1] = bytes(last)
        p = _synthetic_capture(parts, tmp / "k5.pcap")
        rep = messages(p)[0]["chunking"]["reassembled"]
        if rep["messages_recovered"] != 0:
            bad("a sequence with no LastChunk was treated as complete")

        print("CHUNK_SEND is named as unhandled rather than mis-parsed")
        # The honest half of rule 11: no capture here contains one, so there is
        # nothing to test a reassembler against, and it says so instead.
        checks += 1
        send = bytearray(_chunked(carried, chunk_size=256)[0])
        send[1] = 0x85                                  # CHUNK_SEND
        p = _synthetic_capture([bytes(send)], tmp / "k6.pcap")
        rep = messages(p)[0]["chunking"]["reassembled"]
        if rep["unhandled"].get("SPDM_CHUNK_SEND") != 1:
            bad(f"a CHUNK_SEND was not reported as unhandled: {rep['unhandled']}")

        print("the agreement test refuses a pair that does not agree")
        checks += 1
        _, n = compare_negotiated({"Asym": ["ECDSA_P384"]}, {"Asym": ["ECDSA_P256"]})
        if n != 1:
            bad("two different algorithms compared equal")
        checks += 1
        _, n = compare_negotiated({"Asym": ["ECDSA_P384"], "KEM": []},
                                  {"Asym": ["ECDSA_P384"]})
        if n != 0:
            bad("a group named by only one side was treated as a disagreement")
        checks += 1
        _, n = compare_negotiated({"PqcAsym": []}, {"PqcAsym": ["ML_DSA_65"]})
        if n != 1:
            bad("an empty selection compared equal to a non-empty one — this is "
                "the exact shape of a post-quantum arm that silently fell back")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    print()
    print(f"{checks} checks, {fails} failed")
    return 1 if fails else 0


def cross_check(path: Path, stats: dict) -> int:
    """Require fields.py, reading the decode, to agree with what was read here.

    Same quantity, two routes: this tool walked the capture file and never saw
    spdm_dump's output; fields.py read spdm_dump's hex dump and never opened the
    capture. Agreement is evidence. Disagreement has been worth 4,512 bytes
    before now — 2026-08-28 in LOG.md.
    """
    decode = path.with_suffix(".decode.txt")
    if not decode.exists():
        decode = path.with_name(path.name.replace(".pcap", ".decode.txt"))
    if not decode.exists():
        print(f"  no decode beside {path.name}; nothing to check against")
        return 0

    here = Path(__file__).resolve().parent.parent / "harness" / "fields.py"
    out = subprocess.run([sys.executable, str(here), str(decode), "--json"],
                         capture_output=True, text=True)
    if out.returncode != 0:
        print(f"  fields.py could not read {decode.name}: {out.stderr.strip()[:200]}")
        return 1
    got = json.loads(out.stdout)
    mb = got.get("message_bytes")
    if not mb:
        print(f"  {decode.name} has no hex dump beside it; nothing to check against")
        return 0

    print(f"  against : {decode.name}")

    # ── the independent variable, first, and before the truncation test ─────
    #
    # Every cost number this repository publishes is conditional on WHICH
    # algorithms were negotiated, so that is the one quantity worth two
    # independent readings. This tool read the ALGORITHMS response's bytes;
    # fields.py read spdm_dump's rendering of the same message. Neither saw the
    # other's input.
    #
    # It is checked ahead of the truncation guard on purpose. ALGORITHMS is the
    # sixth message of a handshake and spdm_dump gives up thousands of bytes
    # later, so the independent variable stays checkable on exactly the capture
    # where the rest of the comparison cannot run — which is the post-quantum
    # arm, which is the one whose algorithms nobody should take on trust.
    lines, early = compare_negotiated(
        (stats.get("algorithms") or {}).get("negotiated") or {},
        (got.get("algorithms") or {}).get("negotiated") or {})
    for line in lines:
        print(f"  {line}")

    # DataTransferSize, which is not an algorithm and decides how many messages
    # a given number of bytes takes. A capture whose chain is chunked and one
    # whose chain is not can carry identical bytes and look nothing alike.
    for who in ("requester", "responder"):
        a = ((stats.get("capabilities") or {}).get(who) or {}).get("data_transfer_size")
        b = ((got.get("capabilities") or {}).get(who) or {}).get("data_transfer_size")
        if a is None and b is None:
            continue
        if a != b:
            print(f"  FAIL {who} DataTransferSize: capture says {a}, decode says {b}")
            early += 1
        else:
            print(f"  ok    {who} DataTransferSize agrees: {a}")

    # A truncated decode is not a disagreement, and treating it as one would
    # make the check useless on the one capture it has the most to say about.
    #
    # spdm_dump stops partway through the post-quantum arm — its
    # LIBSPDM_MAX_CERT_CHAIN_SIZE is 4,096 and the ML-DSA chain is 16,853 — and
    # says so, which fields.py carries through as decode_truncated. So the two
    # tools are not measuring the same capture at that point, and the honest
    # thing is to report the SHORTFALL, which is a number this repository could
    # not previously produce: how much of a capture the reference decoder does
    # not see. Requiring equality here would be requiring a truncated file to
    # equal a whole one.
    # ── the certificate chain, by two routes that share no input ────────────
    #
    # ★ This is the pairing docs/pqc-cost.md §5 could not make until 2026-09-14.
    # The post-quantum chain arrives inside CHUNK_RESPONSE, so there used to be
    # exactly one tool that could state its length: spdm_dump, whose decode of
    # that very capture is truncated. One route, and that route a prefix.
    #
    # Now this tool reassembles the chunk sequence out of the capture's own
    # bytes, and fields.py still reads spdm_dump's rendering. Neither sees the
    # other's input, and a chain length is a number a chain walk can get wrong
    # in a way that looks right — which is why it is checked BEFORE the
    # truncation guard: spdm_dump reassembles the chain and then gives up
    # thousands of bytes later, so this comparison is available on exactly the
    # captures where the by-type totals are not.
    mine_chain = next((c["chain_bytes"] for c in
                       (stats.get("certificates") or {}).get("slots") or []
                       if c.get("closes")), None)
    theirs_chain = ((got.get("certificate") or {}).get("responder_slot0_bytes"))
    if mine_chain is not None and theirs_chain is not None:
        if mine_chain != theirs_chain:
            print(f"  FAIL responder slot 0 chain: capture says {mine_chain}, "
                  f"decode says {theirs_chain}")
            early += 1
        else:
            via = next((c.get("via") for c in stats["certificates"]["slots"]
                        if c.get("closes")), "?")
            print(f"  ok    responder slot 0 chain agrees: {mine_chain} bytes "
                  f"(this tool reached it through {via})")
    elif theirs_chain is not None:
        print(f"  --    the decode reports a {theirs_chain}-byte chain and this "
              "tool reassembled none; see certificates.notes")

    src = got.get("source") or {}
    if src.get("decode_truncated"):
        seen = mb["total"]
        whole = stats["spdm_bytes_total"]
        pct = (100.0 * seen / whole) if whole else 0.0
        print(f"  --    the decode is truncated: {src.get('truncation_reason')}")
        print(f"  --    capture holds {whole} SPDM bytes; the decode accounts for "
              f"{seen} ({pct:.1f}%)")
        print(f"  --    {whole - seen} bytes are in the capture and not in the decode, "
              "so equality is not asserted")
        return 1 if early else 0

    failures = early
    if mb["total"] != stats["spdm_bytes_total"]:
        print(f"  FAIL total SPDM bytes: capture says {stats['spdm_bytes_total']}, "
              f"decode says {mb['total']}")
        failures += 1
    else:
        print(f"  ok    total SPDM bytes agree: {mb['total']}")

    theirs = mb["total_by_type"]
    mine = {k: v["bytes"] for k, v in stats["by_type"].items()}
    for name in sorted(set(theirs) | set(mine)):
        a, b = mine.get(name), theirs.get(name)
        if a != b:
            print(f"  FAIL {name}: capture says {a}, decode says {b}")
            failures += 1
    if failures == 0:
        print(f"  ok    all {len(theirs)} message types agree, byte for byte")
    return 1 if failures else 0


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Count SPDM messages and bytes straight out of a capture.")
    ap.add_argument("pcap", type=Path, nargs="?")
    ap.add_argument("--json", action="store_true", help="machine-readable output")
    ap.add_argument("--list", action="store_true", help="one line per packet")
    ap.add_argument("--check", action="store_true",
                    help="require fields.py, reading the decode, to agree")
    ap.add_argument("--selftest", action="store_true",
                    help="feed the parsers a wrong answer and require a refusal")
    args = ap.parse_args()

    if args.selftest:
        return selftest()
    if args.pcap is None:
        ap.error("a capture is required unless --selftest is given")

    if not args.pcap.exists():
        print(f"error: no such file: {args.pcap}", file=sys.stderr)
        return 2
    try:
        stats, entries = messages(args.pcap)
    except NotAPcap as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 3
    except Truncated as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    if args.json:
        payload = {"summary": stats}
        if args.list:
            payload["messages"] = entries
        print(json.dumps(payload, indent=2))
        return cross_check(args.pcap, stats) if args.check else 0

    print(f"file       : {stats['file']}")
    print(f"linktype   : {stats['linktype']} ({stats['linktype_label']}), "
          f"{stats['framing_bytes_each']} bytes of framing per packet")
    print(f"packets    : {stats['packets']}  "
          f"({stats['messages_parsed']} parsed, {stats['messages_unparsed']} not)")
    print(f"bytes      : {stats['captured_bytes_total']} captured, "
          f"{stats['spdm_bytes_total']} in SPDM messages")
    print(f"accounted  : {'yes' if stats['framing_accounts_for_the_difference'] else 'NO'}"
          "  (captured == SPDM + framing x messages)")
    print()
    print(f"  {'message':<36} {'n':>3} {'bytes':>8}")
    for name, v in stats["by_type"].items():
        print(f"  {name:<36} {v['count']:>3} {v['bytes']:>8}")

    cert = stats["certificates"]
    if cert["roundtrips"] or cert["slots"]:
        print()
        print(f"  certificate chains: {cert['roundtrips']} GET_CERTIFICATE "
              f"round trip(s), {cert['chains_that_close']} of {cert['chains']} "
              f"chain(s) close")
        if cert["base_hash"]:
            print(f"  RootHash is {cert['root_hash_bytes']} bytes "
                  f"({cert['base_hash']}, read from ALGORITHMS)")
        for c in cert["slots"]:
            head = (f"  slot {c['slot']} {c['direction']} from packet "
                    f"{c['first_packet']}: ")
            if not c["closes"]:
                print(head + f"does not close — {c['why']}")
                continue
            portions = " + ".join(str(x) for x in c["portions"])
            print(head + f"{portions} = {c['chain_bytes']} bytes in "
                  f"{c['messages']} message(s), "
                  f"{'large' if c['large_form'] else 'small'} form")
            if c["certificates_bytes"] is not None:
                print(f"      4 + {cert['root_hash_bytes']} + "
                      f"{c['certificates_bytes']} certificates, root "
                      f"{c.get('root_hash', '')[:16]}…")
        if cert["roundtrips"] and not cert["slots"]:
            chunked = stats["by_type"].get("SPDM_CHUNK_RESPONSE")
            if chunked:
                print(f"  --    no chain was reassembled: the responder "
                      f"answered in {chunked['count']} CHUNK_RESPONSE "
                      f"message(s) rather than CERTIFICATE, which is what a "
                      f"chain larger than the negotiated DataTransferSize "
                      f"looks like")
            else:
                print("  --    no chain was reassembled, and no CHUNK_RESPONSE "
                      "explains it")
        for note in cert["notes"]:
            print(f"  --    {note}")

    if args.list:
        print()
        print(f"  {'#':>4}  {'dir':<8} {'ver':<4} {'bytes':>6}  message")
        for e in entries:
            note = f"   ({e['why']})" if e["why"] else ""
            print(f"  {e['packet']:>4}  {e['direction'] or '-':<8} "
                  f"{e['version'] or '-':<4} {e['spdm_bytes'] or 0:>6}  "
                  f"{e['name'] or '-'}{note}")

    if args.check:
        print()
        return cross_check(args.pcap, stats)
    return 0


if __name__ == "__main__":
    sys.exit(main())

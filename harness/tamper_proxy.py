#!/usr/bin/env python3
"""Sit between the two emulators and change one byte after it has been signed.

    python3 harness/tamper_proxy.py --listen 2324 --forward 2323 --passthrough
    python3 harness/tamper_proxy.py --listen 2324 --forward 2323 \
            --flip-record 1:36 --report /tmp/proxy.json --once
    python3 harness/tamper_proxy.py --listen 2324 --forward 2323 \
            --flip-signature -1 --report /tmp/proxy.json --once

Why this exists
---------------
`harness/tamper.sh` can already change a measurement value at the device and a
certificate on the device's disk. Neither reaches a verifier:

  * a measurement changed at the device is signed by the device, so the
    requester receives a self-consistent pair and every check passes;
  * a certificate changed on the device's disk is caught by the device itself
    when it loads the chain, and the bad bytes are never sent.

So after two tamper points the project had measured no successful signature
rejection at all. For a signature check to fail, the bytes that were signed and
the bytes that are verified have to differ, and there are exactly two ways to
arrange that: sign with a key that does not match the presented certificate, or
change the bytes **in flight**. This file is the second one.

It is also a different threat model, and that is most of its value. Changing a
file is an attacker with access to the device. Changing bytes on the wire is an
attacker on the link — an interposer, a compromised switch, a re-flashed
retimer — who never touches the device at all.

What it refuses to do
---------------------
A proxy that flips "the last byte" needs no understanding of the message, and
it can be wrong without anybody noticing: if the flip lands in the wrong field,
the run still fails and the wrong sentence gets written about why. So this one
parses what it is about to change and requires two independent equations to
close before it touches anything:

  1. **The signature length.** Read `BaseAsymSel` out of the `ALGORITHMS`
     response as it goes past, which gives the signature size the connection
     negotiated. Then parse `MEASUREMENTS` forward — blocks, record, nonce,
     opaque data, requester context — and require the bytes left over to equal
     that size exactly. Two routes to one number, sharing no input.

  2. **The block walk.** Walk the measurement record block by block and require
     the walk to land exactly on the record's stated length. A record whose
     blocks do not tile it is a record this file has misunderstood.

If either fails it refuses to flip, says which equation did not close and with
what numbers, and exits non-zero. `docs/roadmap.md` standing rule 11: a check
is worth what it rejects. The equations above rejected the structure this
project's own week-five plan describes, which omits `RequesterContext` — see
`--self-test`, which reproduces that refusal from a synthetic message.

The framing, read from the source rather than from the comment
--------------------------------------------------------------
`spdm_emu/spdm_emu_common/command.h` documents the socket frame as

    command        4 bytes, big endian
    transport_type 4 bytes, big endian
    PayloadSize    4 bytes, big endian
    payload        PayloadSize bytes  ("SPDM message, starting from SPDM_HEADER")

The last line is wrong, and believing it costs one byte of alignment on every
field in the message. For the MCTP transport the payload begins with libspdm's
MCTP message-type byte and the SPDM header starts at payload[1]:

    05 | 10 84 00 00 ...
    └┬┘  └── SPDM header ──┘
     MCTP message type: 0x05 SPDM, 0x06 secured

which is visible in any committed capture, because `send_platform_data` writes
the same buffer to the pcap with a four-byte synthesised MCTP header in front
of it. So a pcap record is four bytes longer than the socket payload, and the
offsets this file reports are given in all three coordinate systems for exactly
that reason.

Endianness: the frame header is big endian and every field inside the payload
is little endian. They are four bytes apart in the same buffer.

Exit codes: 0 ok · 1 asked to tamper and did not · 2 bad arguments or a refusal
"""

from __future__ import annotations

import argparse
import errno
import hashlib
import json
import select
import socket
import struct
import sys
from pathlib import Path

# ------------------------------------------------------------- constants ----
#
# Transcribed from the pinned trees, with the file and the value each came
# from, for the same reason bench/pcapstat.py transcribes its message codes: a
# header parser would be a third thing to keep correct, and the trade is worth
# stating so a reader knows to re-read them after a version bump.
#
#   spdm_emu/spdm_emu_common/command.h          the socket commands
#   libspdm/include/industry_standard/mctp.h    the message types
#   libspdm/include/industry_standard/spdm.h    everything else

FRAME_HEADER_BYTES = 12

SOCKET_SPDM_COMMAND_NORMAL = 0x0001

MCTP_MESSAGE_TYPE_SPDM = 0x05
MCTP_MESSAGE_TYPE_SECURED_MCTP = 0x06

SPDM_ALGORITHMS = 0x63
SPDM_GET_MEASUREMENTS = 0xE0
SPDM_MEASUREMENTS = 0x60

SPDM_MESSAGE_VERSION_13 = 0x13
SPDM_MESSAGE_VERSION_14 = 0x14

SPDM_REQ_CONTEXT_SIZE = 8          # spdm.h:26
SPDM_NONCE_SIZE = 32

# spdm.h:448-461. The signature size beside each is the one libspdm computes in
# libspdm_get_asym_signature_size: for RSA the modulus, for ECDSA twice the
# curve's byte width because the signature is r || s with no DER wrapper.
BASE_ASYM = {
    0x00000001: ("RSASSA_2048", 256),
    0x00000002: ("RSAPSS_2048", 256),
    0x00000004: ("RSASSA_3072", 384),
    0x00000008: ("RSAPSS_3072", 384),
    0x00000010: ("ECDSA_ECC_NIST_P256", 64),
    0x00000020: ("RSASSA_4096", 512),
    0x00000040: ("RSAPSS_4096", 512),
    0x00000080: ("ECDSA_ECC_NIST_P384", 96),
    0x00000100: ("ECDSA_ECC_NIST_P521", 132),
    0x00000200: ("SM2_ECC_SM2_P256", 64),
    0x00000400: ("EDDSA_ED25519", 64),
    0x00000800: ("EDDSA_ED448", 114),
}


# Every reason this file will decline to change a byte, named. A registry
# rather than a set of prose messages, so that `--self-test` can assert it has
# exercised all of them instead of counting distinct string prefixes and
# calling that coverage. docs/roadmap.md standing rule 13: two breaks caught by
# the same check are one check, and a suite that cannot tell which check fired
# reports more coverage than it has.
CHECKS = {
    "no-algorithms": "no ALGORITHMS response was seen before MEASUREMENTS",
    "pqc-unsized": "the signature algorithm is post-quantum and is not sized here",
    "no-context": "the RequesterContext span could not be derived",
    "record-overruns-message": "MeasurementRecordLength runs past the message",
    "no-room-after-record": "no room for a nonce and an opaque length",
    "opaque-overruns-message": "OpaqueData runs past the message",
    "block-header-overruns": "a block header runs past the record",
    "block-size-overruns": "a block's Measurement runs past the record",
    "walk-does-not-tile": "NumberOfBlocks blocks do not tile the record",
    "signature-length": "the bytes left over are not the negotiated signature",
    "no-such-block": "the record carries no block with the requested index",
    "block-not-dmtf-format": "the block is not in the DMTF specification format",
    "offset-outside-field": "the requested offset is outside the field",
}


class Refused(Exception):
    """A change this file will not make, because it cannot show that the byte
    it is about to touch is the byte it was asked to touch.

    Carries the id of the check that fired, so a caller can tell two refusals
    apart without reading their prose.
    """

    def __init__(self, check: str, message: str):
        assert check in CHECKS, f"unregistered check id '{check}'"
        super().__init__(message)
        self.check = check


def _u16le(b: bytes, off: int) -> int:
    return struct.unpack_from("<H", b, off)[0]


def _u24le(b: bytes, off: int) -> int:
    return b[off] | (b[off + 1] << 8) | (b[off + 2] << 16)


def _u32le(b: bytes, off: int) -> int:
    return struct.unpack_from("<I", b, off)[0]


# ----------------------------------------------------------- the framing ----


class Frame:
    """One socket frame: a command, a transport type and a payload.

    The payload is kept as bytes rather than a memoryview because it is
    rewritten in place and then hashed, and an alias into a receive buffer is
    how a "before" digest quietly becomes the "after" one.
    """

    __slots__ = ("command", "transport", "payload")

    def __init__(self, command: int, transport: int, payload: bytes):
        self.command = command
        self.transport = transport
        self.payload = payload

    def encode(self) -> bytes:
        return (struct.pack(">III", self.command, self.transport,
                            len(self.payload)) + self.payload)

    # The SPDM message inside the payload, or None if this frame does not carry
    # one. payload[0] is the MCTP message type; a secured message is opaque and
    # is forwarded untouched rather than guessed at.
    def spdm(self) -> bytes | None:
        if self.command != SOCKET_SPDM_COMMAND_NORMAL:
            return None
        if len(self.payload) < 5:
            return None
        if self.payload[0] != MCTP_MESSAGE_TYPE_SPDM:
            return None
        return self.payload[1:]

    @property
    def code(self) -> int | None:
        msg = self.spdm()
        return msg[1] if msg else None


def recv_exact(sock: socket.socket, want: int) -> bytes | None:
    """Read exactly `want` bytes, or None at a clean end of stream.

    TCP is a byte stream: one recv() returns whatever has arrived, which for a
    1.9 KB certificate message is routinely a fraction of it. Every framing bug
    in a proxy like this one starts by assuming otherwise.
    """
    out = bytearray()
    while len(out) < want:
        try:
            chunk = sock.recv(want - len(out))
        except OSError as exc:
            if exc.errno == errno.ECONNRESET:
                break
            raise
        if not chunk:
            break
        out += chunk
    if not out:
        return None                     # a clean end of stream
    return bytes(out)                   # short means the peer stopped mid-frame


def read_frame(sock: socket.socket) -> Frame | None:
    head = recv_exact(sock, FRAME_HEADER_BYTES)
    if head is None or len(head) < FRAME_HEADER_BYTES:
        return None
    command, transport, size = struct.unpack(">III", head)
    payload = b""
    if size:
        payload = recv_exact(sock, size)
        if payload is None or len(payload) < size:
            return None
    return Frame(command, transport, payload)


# ------------------------------------------------- what the wire says --------


class Conversation:
    """What the proxy has learned by watching, and nothing it was told.

    Every value here is read out of a message that went past. The independent
    variable of a tamper experiment is not what the caller asked for on a
    command line; `docs/roadmap.md` standing rule 8, and 2026-08-11 in `LOG.md`
    is what assuming otherwise cost.
    """

    def __init__(self) -> None:
        self.spdm_version: int | None = None
        self.base_asym_sel: int | None = None
        self.base_asym_name: str | None = None
        self.signature_bytes: int | None = None
        self.pqc_asym_sel: int = 0
        self.context_bytes: int | None = None
        self.signature_requested: bool | None = None
        self.notes: list[str] = []

    # ── ALGORITHMS, response ────────────────────────────────────────────────
    def observe_algorithms(self, msg: bytes) -> None:
        """Read the negotiated asymmetric algorithm, and check the message's
        own Length field agrees with how many bytes actually arrived."""
        if len(msg) < 36:
            self.notes.append(f"ALGORITHMS is {len(msg)} bytes, too short to read")
            return
        self.spdm_version = msg[0]
        declared = _u16le(msg, 4)
        if declared != len(msg):
            self.notes.append(
                f"ALGORITHMS Length says {declared} bytes, {len(msg)} arrived")
            return
        self.base_asym_sel = _u32le(msg, 12)
        # pqc_asym_sel is a 1.4 field. Before 1.4 those four bytes are reserved
        # and read as zero, but reading them only where the version says they
        # exist is the difference between a check and a coincidence.
        if self.spdm_version >= SPDM_MESSAGE_VERSION_14:
            self.pqc_asym_sel = _u32le(msg, 20)
        named = BASE_ASYM.get(self.base_asym_sel)
        if named is None:
            self.notes.append(
                f"BaseAsymSel {self.base_asym_sel:#010x} is not one this file knows")
            return
        self.base_asym_name, self.signature_bytes = named

    # ── GET_MEASUREMENTS, request ───────────────────────────────────────────
    def observe_get_measurements(self, msg: bytes) -> None:
        """Derive the RequesterContext span from the request's own length.

        RequesterContext exists from SPDM 1.3. Taking its size from the version
        byte would be one assumption; taking it from the length of the message
        that carries it is a measurement, and it is the same equation
        `harness/fields.py` closes on a decode rather than on the wire.
        """
        self.signature_requested = bool(msg[2] & 0x01)
        fixed = 4 + (SPDM_NONCE_SIZE + 1 if self.signature_requested else 0)
        span = len(msg) - fixed
        if span in (0, SPDM_REQ_CONTEXT_SIZE):
            self.context_bytes = span
        else:
            self.context_bytes = None
            self.notes.append(
                f"GET_MEASUREMENTS is {len(msg)} bytes; with a signature "
                f"{'' if self.signature_requested else 'not '}requested that "
                f"leaves {span} for RequesterContext, which is neither 0 nor "
                f"{SPDM_REQ_CONTEXT_SIZE}")


# --------------------------------------------------- parsing MEASUREMENTS ----


def walk_record(record: bytes, number_of_blocks: int) -> list[dict]:
    """Tile the measurement record with exactly `number_of_blocks` blocks.

    A DMTF-specification measurement block is

        Index(1) MeasurementSpecification(1) MeasurementSize(2) Measurement[..]

    and the Measurement itself is

        ValueType(1) ValueSize(2) Value[ValueSize]

    so the bytes a verifier would compare against a reference value start seven
    bytes into each block.

    The walk takes its trip count from the message's own NumberOfBlocks field
    and then has to land exactly on the record's stated length — two numbers
    written by the responder in two different places, made to agree here. A
    record whose blocks do not tile it is one this file has misread, and
    flipping a byte inside a structure you have misread is how an experiment
    reports the wrong cause with complete confidence.
    """
    blocks: list[dict] = []
    p = 0
    for _ in range(number_of_blocks):
        if p + 4 > len(record):
            raise Refused(
                "block-header-overruns",
                f"measurement record: a block header at {p} runs past the "
                f"record's {len(record)} bytes")
        index = record[p]
        spec = record[p + 1]
        size = _u16le(record, p + 2)
        if p + 4 + size > len(record):
            raise Refused(
                "block-size-overruns",
                f"measurement record: block {index:#04x} claims {size} bytes at "
                f"{p + 4}, past the record's {len(record)}")
        body = record[p + 4:p + 4 + size]
        entry = {
            "index": index,
            "measurement_specification": spec,
            "measurement_bytes": size,
            "block_offset": p,
            "measurement_offset": p + 4,
        }
        # The DMTF specification format is bit 0 of MeasurementSpecification.
        # Anything else is a vendor format this file will not claim to read,
        # and it says so rather than assuming the layout holds.
        if spec & 0x01 and size >= 3:
            value_size = _u16le(body, 1)
            if 3 + value_size <= size:
                entry["value_type"] = body[0]
                entry["value_bytes"] = value_size
                entry["value_offset"] = p + 4 + 3
            else:
                entry["value_bytes"] = None
                entry["value_offset"] = None
        else:
            entry["value_bytes"] = None
            entry["value_offset"] = None
        blocks.append(entry)
        p += 4 + size
    if p != len(record):
        raise Refused(
            "walk-does-not-tile",
            f"measurement record: NumberOfBlocks says {number_of_blocks}, and "
            f"walking that many ended at {p} of the record's {len(record)} "
            f"bytes")
    return blocks


def parse_measurements(msg: bytes, conv: Conversation) -> dict:
    """Locate every field of a MEASUREMENTS response, or raise.

    The layout is spdm.h:936-949. The plan this project is executed against
    describes it without RequesterContext, which is eight bytes and would put
    the signature eight bytes early — so the closing equation below is not a
    formality, it is the thing that caught that.
    """
    if conv.signature_bytes is None:
        raise Refused(
            "no-algorithms",
            "no ALGORITHMS response was seen before MEASUREMENTS, so the "
            "signature length is unknown and nothing can be checked against it"
            + (f" ({'; '.join(conv.notes)})" if conv.notes else ""))
    if conv.pqc_asym_sel:
        raise Refused(
            "pqc-unsized",
            f"PqcAsymSel is {conv.pqc_asym_sel:#010x}: the responder signs with "
            "a post-quantum algorithm and this file only knows the classical "
            "signature sizes. Add them to BASE_ASYM's sibling table first")
    if conv.context_bytes is None:
        raise Refused(
            "no-context",
            "the RequesterContext span is unknown"
            + (f" ({'; '.join(conv.notes)})" if conv.notes else ""))

    want_sig = conv.signature_bytes if conv.signature_requested else 0

    off = 4
    number_of_blocks = msg[off]
    off += 1
    record_bytes = _u24le(msg, off)
    off += 3
    record_offset = off
    if record_offset + record_bytes > len(msg):
        raise Refused(
            "record-overruns-message",
            f"MeasurementRecordLength {record_bytes} runs past the message's "
            f"{len(msg)} bytes")
    record = msg[record_offset:record_offset + record_bytes]
    off += record_bytes

    if off + SPDM_NONCE_SIZE + 2 > len(msg):
        raise Refused("no-room-after-record",
                      "the record leaves no room for a nonce and an opaque length")
    nonce_offset = off
    off += SPDM_NONCE_SIZE
    opaque_length_offset = off
    opaque_length = _u16le(msg, off)
    off += 2
    opaque_offset = off
    off += opaque_length
    if off + conv.context_bytes > len(msg):
        raise Refused("opaque-overruns-message", "OpaqueData runs past the message")
    context_offset = off if conv.context_bytes else None
    off += conv.context_bytes

    signature_offset = off
    signature_bytes = len(msg) - off

    blocks = walk_record(record, number_of_blocks)

    if signature_bytes != want_sig:
        raise Refused(
            "signature-length",
            f"the layout does not close: {len(msg)} bytes minus a signature "
            f"starting at {signature_offset} leaves {signature_bytes}, but "
            f"{conv.base_asym_name} signs {want_sig}. Something in front of "
            f"the signature is the wrong size")

    return {
        "spdm_bytes": len(msg),
        "number_of_blocks": number_of_blocks,
        "record_bytes": record_bytes,
        "record_offset": record_offset,
        "record_sha256": hashlib.sha256(record).hexdigest(),
        "nonce_offset": nonce_offset,
        "opaque_length_offset": opaque_length_offset,
        "opaque_length": opaque_length,
        "opaque_offset": opaque_offset,
        "requester_context_offset": context_offset,
        "requester_context_bytes": conv.context_bytes,
        "signature_offset": signature_offset,
        "signature_bytes": signature_bytes,
        "closed": True,
        "blocks": blocks,
    }


# ------------------------------------------------------------- the tamper ----


def _coordinates(spdm_offset: int) -> dict:
    """One byte, in the three coordinate systems a reader will meet it in.

    Nothing here is a conversion anybody should have to do by hand while
    reading docs/tamper.md beside a hex dump — and the eight-byte-early
    signature this file refuses to touch is exactly what an off-by-one in a
    coordinate system looks like.
    """
    return {
        "offset_in_spdm_message": spdm_offset,
        "offset_in_socket_payload": spdm_offset + 1,   # the MCTP type byte
        "offset_in_pcap_record": spdm_offset + 5,      # + the synthesised header
    }


def apply_tamper(msg: bytearray, layout: dict, mode: str,
                 block_index: int | None, offset: int) -> dict:
    """Flip one bit of one byte, and report which byte in full."""
    if mode == "record":
        matches = [b for b in layout["blocks"] if b["index"] == block_index]
        if not matches:
            have = ", ".join(f"{b['index']:#04x}" for b in layout["blocks"])
            raise Refused(
                "no-such-block",
                f"no measurement block with index {block_index:#04x} on the "
                f"wire; this record carries {have}")
        blk = matches[0]
        if blk["value_offset"] is None:
            raise Refused(
                "block-not-dmtf-format",
                f"measurement block {block_index:#04x} is not in the DMTF "
                "specification format, so it has no value field to change")
        if not 0 <= offset < blk["value_bytes"]:
            raise Refused(
                "offset-outside-field",
                f"--flip-record offset {offset} is outside measurement "
                f"{block_index:#04x}'s {blk['value_bytes']}-byte value")
        target = layout["record_offset"] + blk["value_offset"] + offset
        what = (f"byte {offset} of the {blk['value_bytes']}-byte value of "
                f"measurement index {block_index:#04x}")
    elif mode == "signature":
        n = layout["signature_bytes"]
        idx = offset if offset >= 0 else n + offset
        if not 0 <= idx < n:
            raise Refused(
                "offset-outside-field",
                f"--flip-signature {offset} is outside the {n}-byte signature")
        target = layout["signature_offset"] + idx
        what = f"byte {idx} of the {n}-byte signature"
    else:
        raise AssertionError(f"unknown tamper mode '{mode}'")

    before = msg[target]
    msg[target] = before ^ 0x01
    record = bytes(msg[layout["record_offset"]:
                       layout["record_offset"] + layout["record_bytes"]])

    out = {
        "applied": True,
        "mode": mode,
        "target": what,
        "byte_before": f"0x{before:02x}",
        "byte_after": f"0x{msg[target]:02x}",
        "record_sha256_before": layout["record_sha256"],
        "record_sha256_after": hashlib.sha256(record).hexdigest(),
    }
    out.update(_coordinates(target))
    return out


# ---------------------------------------------------------------- the pump --


class Proxy:
    def __init__(self, args: argparse.Namespace):
        self.args = args
        self.conv = Conversation()
        self.report: dict = {
            "listen": args.listen,
            "forward": args.forward,
            "mode": args.mode,
            "frames": {"requester_to_responder": 0, "responder_to_requester": 0},
            "negotiated": {},
            "measurements": None,
            "tamper": {"applied": False},
            "refusals": [],
        }

    def note_refusal(self, why: str) -> None:
        self.report["refusals"].append(why)
        print(f"[proxy] REFUSED: {why}", file=sys.stderr, flush=True)

    # ── one message, in the direction it is going ───────────────────────────
    def on_requester_frame(self, frame: Frame) -> Frame:
        self.report["frames"]["requester_to_responder"] += 1
        msg = frame.spdm()
        if msg and msg[1] == SPDM_GET_MEASUREMENTS:
            self.conv.observe_get_measurements(msg)
            print(f"[proxy] GET_MEASUREMENTS {len(msg)} B: signature "
                  f"{'requested' if self.conv.signature_requested else 'not requested'}"
                  f", RequesterContext {self.conv.context_bytes} B",
                  file=sys.stderr, flush=True)
        return frame

    def on_responder_frame(self, frame: Frame) -> Frame:
        self.report["frames"]["responder_to_requester"] += 1
        msg = frame.spdm()
        if not msg:
            return frame

        if msg[1] == SPDM_ALGORITHMS:
            self.conv.observe_algorithms(msg)
            self.report["negotiated"] = {
                "spdm_version": (f"{self.conv.spdm_version >> 4}."
                                 f"{self.conv.spdm_version & 0xf}"
                                 if self.conv.spdm_version else None),
                "base_asym_sel": (f"0x{self.conv.base_asym_sel:08x}"
                                  if self.conv.base_asym_sel is not None else None),
                "base_asym_name": self.conv.base_asym_name,
                "signature_bytes": self.conv.signature_bytes,
                "pqc_asym_sel": f"0x{self.conv.pqc_asym_sel:08x}",
            }
            print(f"[proxy] ALGORITHMS: BaseAsymSel "
                  f"{self.report['negotiated']['base_asym_sel']} "
                  f"{self.conv.base_asym_name} -> signature "
                  f"{self.conv.signature_bytes} B", file=sys.stderr, flush=True)
            return frame

        if msg[1] != SPDM_MEASUREMENTS:
            return frame

        try:
            layout = parse_measurements(msg, self.conv)
        except Refused as why:
            self.note_refusal(str(why))
            return frame
        except (IndexError, struct.error) as why:
            self.note_refusal(f"MEASUREMENTS could not be parsed: {why}")
            return frame

        self.report["measurements"] = layout
        print(f"[proxy] MEASUREMENTS {len(msg)} B: {layout['number_of_blocks']} "
              f"blocks, record {layout['record_bytes']} B at "
              f"{layout['record_offset']}, opaque {layout['opaque_length']} B, "
              f"RequesterContext {layout['requester_context_bytes']} B, "
              f"signature {layout['signature_bytes']} B at "
              f"{layout['signature_offset']}  CLOSED",
              file=sys.stderr, flush=True)

        if self.args.mode == "passthrough":
            return frame
        if self.report["tamper"]["applied"]:
            return frame          # one message, one flip, however many arrive

        buf = bytearray(msg)
        try:
            done = apply_tamper(buf, layout, self.args.mode,
                                self.args.block_index, self.args.offset)
        except Refused as why:
            self.note_refusal(str(why))
            return frame

        self.report["tamper"] = done
        print(f"[proxy] flip {done['target']}: {done['byte_before']} -> "
              f"{done['byte_after']} at SPDM offset "
              f"{done['offset_in_spdm_message']} "
              f"(payload {done['offset_in_socket_payload']}, "
              f"pcap record {done['offset_in_pcap_record']})",
              file=sys.stderr, flush=True)
        return Frame(frame.command, frame.transport,
                     frame.payload[:1] + bytes(buf))

    # ── the connection ──────────────────────────────────────────────────────
    def serve_one(self, client: socket.socket) -> None:
        upstream = socket.create_connection(("127.0.0.1", self.args.forward))
        upstream.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        client.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        try:
            alive = {client, upstream}
            while alive:
                readable, _, _ = select.select(list(alive), [], [], 60)
                if not readable:
                    print("[proxy] idle for 60s, giving up", file=sys.stderr)
                    break
                for sock in readable:
                    frame = read_frame(sock)
                    # Either end of stream ends the conversation, and SHUTDOWN
                    # deliberately does not.
                    #
                    # An earlier version tore the connection down as soon as it
                    # saw SOCKET_SPDM_COMMAND_SHUTDOWN go past, on the theory
                    # that the requester says it and then leaves. It does not:
                    # spdm_requester_emu.c:253 sends SHUTDOWN through
                    # communicate_platform_data, which WAITS for a reply, and
                    # spdm_responder_emu.c:126 sends one back before it stops
                    # looping. Closing early cost the requester that reply and
                    # put "receive_platform_data Error - 2" in the log of the
                    # passthrough arm — the one arm whose whole job is to be
                    # indistinguishable from no proxy at all.
                    #
                    # A transparent proxy does not get to have opinions about
                    # when a conversation is over. The peers close, and it
                    # notices.
                    if frame is None:
                        alive.discard(sock)
                        alive.clear()
                        break
                    if sock is client:
                        out = self.on_requester_frame(frame)
                        upstream.sendall(out.encode())
                    else:
                        out = self.on_responder_frame(frame)
                        client.sendall(out.encode())
        finally:
            for sock in (client, upstream):
                try:
                    sock.shutdown(socket.SHUT_RDWR)
                except OSError:
                    pass
                sock.close()

    def run(self) -> int:
        listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        listener.bind(("127.0.0.1", self.args.listen))
        listener.listen(4)
        print(f"[proxy] listening on 127.0.0.1:{self.args.listen}, forwarding to "
              f"127.0.0.1:{self.args.forward}, mode {self.args.mode}",
              file=sys.stderr, flush=True)
        try:
            while True:
                client, _ = listener.accept()
                self.serve_one(client)
                if self.args.once:
                    break
        except KeyboardInterrupt:
            pass
        finally:
            listener.close()
        return self.finish()

    def finish(self) -> int:
        if self.args.report:
            Path(self.args.report).write_text(
                json.dumps(self.report, indent=2) + "\n", encoding="utf-8")
        if self.args.mode == "passthrough":
            return 0
        if self.report["tamper"]["applied"]:
            return 0
        if not self.report["refusals"]:
            self.note_refusal("no MEASUREMENTS response went past, so nothing "
                              "was changed")
        return 1


# ------------------------------------------------------------- self-test ----


def self_test() -> int:
    """Feed the parser things it must reject, and require every check to fire.

    Standing rule 11: a check is worth what it rejects, and something has to
    prove it rejects. Standing rule 13: two breaks caught by the same check are
    one check. So this does not count refusals — it counts which registered
    check each refusal came through, and fails if any check in CHECKS was never
    exercised. A parser with thirteen guards, five of which have never fired,
    reports more than twice the coverage it has.

    Two of the inputs below are mistakes that were genuinely available to make
    this week: the field list in this project's own week-five plan, which omits
    RequesterContext, and a signature sized by an algorithm nobody negotiated.
    """
    V = SPDM_MESSAGE_VERSION_14

    def algorithms(version=V, asym=0x80, length=None) -> bytes:
        body = bytearray(36)
        body[0:4] = bytes([version, SPDM_ALGORITHMS, 0, 0])
        struct.pack_into("<H", body, 4, 36 if length is None else length)
        struct.pack_into("<I", body, 12, asym)
        return bytes(body)

    def get_measurements(ctx=SPDM_REQ_CONTEXT_SIZE, gensig=True) -> bytes:
        return (bytes([V, SPDM_GET_MEASUREMENTS, 0x01 if gensig else 0x00, 0xFF])
                + b"\x00" * (SPDM_NONCE_SIZE + 1 if gensig else 0)
                + b"\xAB" * ctx)

    def block(index, value, spec=0x01):
        meas = bytes([0x01]) + struct.pack("<H", len(value)) + value
        return bytes([index, spec]) + struct.pack("<H", len(meas)) + meas

    def measurements(record, *, record_len=None, opaque_len=None, opaque=b"",
                     ctx=SPDM_REQ_CONTEXT_SIZE, sig=96, nblocks=1, tail=True):
        declared = len(record) if record_len is None else record_len
        out = bytearray([V, SPDM_MEASUREMENTS, nblocks, 0x00, nblocks])
        out += bytes([declared & 0xFF, (declared >> 8) & 0xFF,
                      (declared >> 16) & 0xFF])
        out += record
        if not tail:
            return bytes(out)
        out += b"\x11" * SPDM_NONCE_SIZE
        out += struct.pack("<H", len(opaque) if opaque_len is None else opaque_len)
        out += opaque
        out += b"\xAB" * ctx
        out += b"\x5A" * sig
        return bytes(out)

    def conversation(asym=0x80, ctx=SPDM_REQ_CONTEXT_SIZE, algs=True, pqc=0):
        c = Conversation()
        if algs:
            c.observe_algorithms(algorithms(asym=asym))
        c.pqc_asym_sel = pqc
        c.observe_get_measurements(get_measurements(ctx=ctx))
        return c

    good = block(0x01, bytes(64))
    fired: dict[str, str] = {}
    rows: list[tuple[str, str, str]] = []
    bad = 0

    def expect(name, want_check, fn):
        nonlocal bad
        try:
            fn()
        except Refused as why:
            if want_check is None:
                rows.append(("FAIL", name, f"refused ({why.check}): {why}"))
                bad += 1
            elif why.check == want_check:
                fired.setdefault(why.check, name)
                rows.append(("ok  ", name, f"{why.check}"))
            else:
                rows.append(("FAIL", name,
                             f"wanted {want_check}, got {why.check}: {why}"))
                bad += 1
            return
        if want_check is not None:
            rows.append(("FAIL", name, f"accepted; {want_check} never fired"))
            bad += 1
            return
        rows.append(("ok  ", name, "accepted"))

    conv = conversation()
    layout: dict = {}

    def parse_good():
        layout.update(parse_measurements(measurements(good), conv))

    expect("an intact MEASUREMENTS", None, parse_good)

    expect("the plan's field list, without RequesterContext", "signature-length",
           lambda: parse_measurements(measurements(good), conversation(ctx=0)))
    expect("a signature sized by an algorithm nobody negotiated",
           "signature-length",
           lambda: parse_measurements(measurements(good), conversation(asym=0x10)))
    expect("no ALGORITHMS before MEASUREMENTS", "no-algorithms",
           lambda: parse_measurements(measurements(good), conversation(algs=False)))
    expect("a post-quantum signature this file cannot size", "pqc-unsized",
           lambda: parse_measurements(measurements(good),
                                      conversation(pqc=0x00000001)))
    expect("a GET_MEASUREMENTS whose length leaves no legal context span",
           "no-context",
           lambda: parse_measurements(measurements(good), conversation(ctx=3)))
    expect("MeasurementRecordLength past the end of the message",
           "record-overruns-message",
           lambda: parse_measurements(measurements(good, record_len=9999), conv))
    expect("a record with no room behind it for a nonce",
           "no-room-after-record",
           lambda: parse_measurements(measurements(good, tail=False), conv))
    expect("an OpaqueDataLength past the end of the message",
           "opaque-overruns-message",
           lambda: parse_measurements(measurements(good, opaque_len=9999), conv))
    expect("blocks that do not tile the record", "walk-does-not-tile",
           lambda: parse_measurements(measurements(good + b"\x00\x00"), conv))
    expect("a block header past the end of the record", "block-header-overruns",
           lambda: parse_measurements(
               measurements(good + b"\x00\x00", nblocks=2), conv))

    overshoot = bytearray(good)
    struct.pack_into("<H", overshoot, 2, len(good))
    expect("a block claiming more bytes than the record holds",
           "block-size-overruns",
           lambda: parse_measurements(measurements(bytes(overshoot)), conv))

    expect("a flip aimed at a block the record does not carry", "no-such-block",
           lambda: apply_tamper(bytearray(measurements(good)), layout,
                                "record", 0x99, 0))
    expect("a flip past the end of the field", "offset-outside-field",
           lambda: apply_tamper(bytearray(measurements(good)), layout,
                                "record", 0x01, 9999))

    vendor = block(0x02, bytes(64), spec=0x02)
    vendor_layout = parse_measurements(measurements(vendor), conv)
    expect("a flip aimed at a block in a vendor format", "block-not-dmtf-format",
           lambda: apply_tamper(bytearray(measurements(vendor)), vendor_layout,
                                "record", 0x02, 0))

    width = max(len(n) for _, n, _ in rows)
    for flag, name, detail in rows:
        print(f"  {flag}  {name.ljust(width)}  {detail}")

    print()
    if layout:
        msg = bytearray(measurements(good))
        done = apply_tamper(msg, layout, "record", 0x01, 36)
        want = layout["record_offset"] + 4 + 3 + 36
        landed = done["offset_in_spdm_message"] == want
        bad += 0 if landed else 1
        print(f"  {'ok  ' if landed else 'FAIL'}  the flip lands where the walk "
              f"says: SPDM offset {done['offset_in_spdm_message']}, payload "
              f"{done['offset_in_socket_payload']}, pcap record "
              f"{done['offset_in_pcap_record']} (expected {want})")
        moved = done["record_sha256_before"] != done["record_sha256_after"]
        bad += 0 if moved else 1
        print(f"  {'ok  ' if moved else 'FAIL'}  and the record digest moves: "
              f"{done['record_sha256_before'][:16]} -> "
              f"{done['record_sha256_after'][:16]}")

    never = sorted(set(CHECKS) - set(fired))
    print(f"\n  {len(rows) - 1} broken input(s) rejected through "
          f"{len(fired)} of {len(CHECKS)} registered check(s)")
    for check in never:
        print(f"  FAIL  never exercised: {check} — {CHECKS[check]}")
        bad += 1
    return 1 if bad else 0


# ----------------------------------------------------------------- main -----


def main() -> int:
    ap = argparse.ArgumentParser(
        description="flip one byte of a MEASUREMENTS response in flight")
    ap.add_argument("--listen", type=int, default=2324,
                    help="port the requester connects to (default 2324)")
    ap.add_argument("--forward", type=int, default=2323,
                    help="port the responder listens on (default 2323)")
    ap.add_argument("--passthrough", action="store_true",
                    help="forward every frame unchanged")
    ap.add_argument("--flip-record", metavar="INDEX:OFFSET",
                    help="flip a byte of one measurement block's value, e.g. 1:36")
    ap.add_argument("--flip-signature", type=int, metavar="N",
                    help="flip byte N of the signature; negative counts back "
                         "from the end, so -1 is the last byte")
    ap.add_argument("--report", metavar="FILE",
                    help="write what happened, as JSON")
    ap.add_argument("--once", action="store_true",
                    help="exit after the first connection closes")
    ap.add_argument("--self-test", action="store_true",
                    help="feed the parser broken messages and require refusals")
    args = ap.parse_args()

    if args.self_test:
        return self_test()

    chosen = [bool(args.passthrough), args.flip_record is not None,
              args.flip_signature is not None]
    if sum(chosen) != 1:
        ap.error("choose exactly one of --passthrough, --flip-record, "
                 "--flip-signature")

    args.block_index = None
    args.offset = 0
    if args.passthrough:
        args.mode = "passthrough"
    elif args.flip_record is not None:
        args.mode = "record"
        try:
            index, offset = args.flip_record.split(":")
            args.block_index = int(index, 0)
            args.offset = int(offset, 0)
        except ValueError:
            ap.error("--flip-record wants INDEX:OFFSET, e.g. 1:36")
    else:
        args.mode = "signature"
        args.offset = args.flip_signature

    try:
        return Proxy(args).run()
    except OSError as exc:
        print(f"[proxy] {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Write the measurement fixture the patched responder reads.

    python3 device/gen_measurements.py --out device/measurements.bin
    python3 device/gen_measurements.py --svn 5 --out device/measurements_svn5.bin
    python3 device/gen_measurements.py --flip-byte 96 --out /tmp/tampered.bin
    python3 device/gen_measurements.py --describe device/measurements.bin

The format is documented once, in device/measurement_source.h, and this file
does not restate it. What it does state is why the DEFAULT output is what it
is, because that is the part a reader will not guess.

Why the default reproduces upstream exactly
-------------------------------------------
With no options this writes the fixture whose contents are identical to what
libspdm's sample secret library synthesises on its own: measurement index i
carries 72 bytes of the byte i, and the secure version number is 7. Those are
`libspdm_set_mem(data, sizeof(data), (uint8_t)(measurements_index))` and
`svn = 0x7` in os_stub/spdm_device_secret_lib_sample/meas.c.

That makes the default fixture a control rather than an input. A responder
reading it must put exactly the same bytes on the wire as a responder reading
nothing at all — and "exactly" is checkable, because the 528-byte measurement
record is deterministic: the same SHA-256, f2a14684e8fae9ff…, appears in six
arms across three capture runs on three different dates. So the plumbing is
verified against a 256-bit target before a single byte is deliberately
changed. If the fixture path were wired up wrongly, that digest would miss.

Blocks 0x10, 0x11, 0xfd and 0xfe are not written
------------------------------------------------
The responder holds eight measurement blocks. This fixture supplies four of
them — the image-hash blocks at indices 1 to 4 — plus the secure version
number, which is a header field. The hash-extend log (0x11), the manifest
(0xfd) and the device-mode block (0xfe) are left to upstream, which still
synthesises them.

That is a decision rather than an omission. Every index this fixture claims is
an index whose value came from this project rather than from DMTF's, and the
smallest set that supports the week's two experiments is four blocks and one
scalar. Extending it is one more line in meas.c and one more descriptor here;
doing that before something needs it would enlarge the diff whose smallness is
the entire argument for trusting the measurements.

Exit codes: 0 ok · 2 bad arguments or a refusal
"""

from __future__ import annotations

import argparse
import hashlib
import struct
import sys
from pathlib import Path

MAGIC = b"MSR1"
FORMAT_VERSION = 1
HEADER_BYTES = 16
DESCRIPTOR_BYTES = 8

# What upstream synthesises, and therefore what this file reproduces by
# default. meas.c: LIBSPDM_MEASUREMENT_RAW_DATA_SIZE is 72, the buffer is
# filled with the measurement index, and the four image-hash blocks are
# indices 1 through LIBSPDM_MEASUREMENT_BLOCK_HASH_NUMBER, which is 4.
VALUE_BYTES = 72
HASH_BLOCK_INDICES = (1, 2, 3, 4)
UPSTREAM_SVN = 7

# The digest of the 528-byte measurement record that upstream produces with
# these values, SHA-512 measurement hashes and --meas_op ALL. Not used to
# validate anything here — this tool never sees a capture — but recorded next
# to the values it is derived from, because a constant with no stated origin is
# the thing this repository keeps finding rotted.
#
#   sha256(record) = f2a14684e8fae9ff0e3ebff2a380f435c0fee5b0c8199d3fdfed31b2252f51d8
#   observed in    = w2-baseline-20260816T172221Z (walkthrough, single-algo),
#                    w2-baseline-20260828T110130Z (both),
#                    w3-baseline-20260831T143123Z (walkthrough, single-algo,
#                    sample-1slot, selfsigned),
#                    w4-baseline-20260901T054208Z (the same four)
#
# Four runs, four dates, two certificate chains, one digest. harness/
# verify_repo.sh asserts that invariant over every committed baseline run
# rather than leaving it as a comment, because a constant in a comment is a
# constant nothing checks.


class Refused(Exception):
    """A request that would produce a fixture whose meaning is not what the
    person asking for it thinks it is."""


def build(svn: int, blocks: dict[int, bytes]) -> bytearray:
    """Header, descriptor table, payload — in that order and nothing else."""
    ordered = sorted(blocks.items())
    table_end = HEADER_BYTES + DESCRIPTOR_BYTES * len(ordered)

    out = bytearray()
    out += MAGIC
    out += struct.pack("<HH", FORMAT_VERSION, len(ordered))
    out += struct.pack("<Q", svn)

    payload = bytearray()
    for index, value in ordered:
        if not 1 <= index <= 0xFE:
            raise Refused(f"index {index:#x} is not a measurement index (1..0xfe)")
        if len(value) > 0xFFFF:
            raise Refused(f"index {index:#x} value is {len(value)} bytes, max 65535")
        out += struct.pack("<BBHI", index, 0, len(value),
                           table_end + len(payload))
        payload += value

    out += payload
    return out


def parse(raw: bytes) -> dict:
    """Read a fixture back. Deliberately a second implementation of the reader.

    device/measurement_source.c is the one that matters and it is written in C;
    this one exists so --describe can explain a file without a compiler, and so
    --flip-byte can say what the byte it is about to change actually means. Two
    readers that disagree is a bug this repository would rather find here than
    in a capture.
    """
    if len(raw) < HEADER_BYTES:
        raise Refused(f"{len(raw)} bytes; the header alone is {HEADER_BYTES}")
    if raw[:4] != MAGIC:
        raise Refused(f"bad magic {raw[:4]!r}, expected {MAGIC!r}")
    version, count = struct.unpack_from("<HH", raw, 4)
    if version != FORMAT_VERSION:
        raise Refused(f"format version {version}, this tool writes {FORMAT_VERSION}")
    (svn,) = struct.unpack_from("<Q", raw, 8)

    table_end = HEADER_BYTES + DESCRIPTOR_BYTES * count
    if table_end > len(raw):
        raise Refused(f"{count} descriptors need {table_end} bytes, file has {len(raw)}")

    blocks = []
    for i in range(count):
        index, reserved, length, offset = struct.unpack_from(
            "<BBHI", raw, HEADER_BYTES + DESCRIPTOR_BYTES * i
        )
        if reserved != 0:
            raise Refused(f"descriptor {i} reserved byte is {reserved}")
        # Same shape as ms_range_ok, and for the same reason: the subtraction
        # cannot be reordered into an addition that overflows.
        if offset > len(raw) or length > len(raw) - offset:
            raise Refused(
                f"descriptor {i} (index {index:#x}) claims {length} bytes at "
                f"offset {offset}; the file is {len(raw)} bytes"
            )
        blocks.append(
            {
                "index": index,
                "length": length,
                "offset": offset,
                "value": raw[offset:offset + length],
                "descriptor_offset": HEADER_BYTES + DESCRIPTOR_BYTES * i,
            }
        )
    return {"svn": svn, "count": count, "table_end": table_end, "blocks": blocks}


def locate(info: dict, offset: int, total: int) -> str:
    """Say what the byte at `offset` is, in words."""
    if offset < 4:
        return f"byte {offset} of the 4-byte magic"
    if offset < 6:
        return f"byte {offset - 4} of format_version"
    if offset < 8:
        return f"byte {offset - 6} of block_count"
    if offset < 16:
        return f"byte {offset - 8} of the 8-byte svn"
    if offset < info["table_end"]:
        i = (offset - HEADER_BYTES) // DESCRIPTOR_BYTES
        field = (offset - HEADER_BYTES) % DESCRIPTOR_BYTES
        name = ("index", "reserved", "length", "length",
                "offset", "offset", "offset", "offset")[field]
        return f"descriptor {i} field {name}"
    for b in info["blocks"]:
        if b["offset"] <= offset < b["offset"] + b["length"]:
            return (f"byte {offset - b['offset']} of the {b['length']}-byte value "
                    f"for measurement index {b['index']:#04x}")
    return f"offset {offset} of {total}, in no block's value"


def describe(path: Path, raw: bytes, info: dict) -> None:
    print(f"file      : {path} ({len(raw)} bytes)")
    print(f"sha256    : {hashlib.sha256(raw).hexdigest()}")
    print(f"svn       : {info['svn']}  (at file offset 8, 8 bytes little-endian)")
    print(f"blocks    : {info['count']}")
    print()
    print(f"  {'index':>5}  {'length':>6}  {'offset':>6}  value")
    for b in info["blocks"]:
        v = b["value"]
        shown = v[:12].hex(" ")
        uniform = len(set(v)) == 1 if v else False
        note = f"  ({len(v)} x {v[0]:#04x})" if uniform else ""
        print(f"  {b['index']:#05x}  {b['length']:>6}  {b['offset']:>6}  "
              f"{shown}{' ...' if len(v) > 12 else ''}{note}")


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Write or inspect the measurement fixture read by the "
                    "patched libspdm sample secret library.",
        epilog="With no options the output is byte-identical in meaning to "
               "what upstream synthesises, which is what makes it a control.",
    )
    ap.add_argument("--out", type=Path, help="file to write")
    ap.add_argument("--svn", type=int, default=UPSTREAM_SVN,
                    help=f"secure version number (default {UPSTREAM_SVN}, "
                         "which is upstream's hard-coded value)")
    ap.add_argument("--flip-byte", type=int, metavar="N",
                    help="XOR 0x01 into the byte at file offset N, and say "
                         "what that byte is")
    ap.add_argument("--flip-block", type=int, metavar="INDEX",
                    help="with --flip-offset, flip a byte of one block's value "
                         "and report the absolute file offset")
    ap.add_argument("--flip-offset", type=int, default=0, metavar="K",
                    help="which byte of that block's value (default 0)")
    ap.add_argument("--force", action="store_true",
                    help="permit a --flip-byte that lands outside a measurement "
                         "value")
    ap.add_argument("--describe", type=Path, metavar="FILE",
                    help="print an existing fixture and exit")
    args = ap.parse_args()

    try:
        if args.describe is not None:
            raw = args.describe.read_bytes()
            describe(args.describe, raw, parse(raw))
            return 0

        if args.out is None:
            ap.error("one of --out or --describe is required")

        if not 0 <= args.svn <= 0xFFFFFFFFFFFFFFFF:
            raise Refused(f"svn {args.svn} does not fit in the 64-bit field")

        blocks = {i: bytes([i]) * VALUE_BYTES for i in HASH_BLOCK_INDICES}
        raw = build(args.svn, blocks)
        info = parse(bytes(raw))

        flipped = None
        if args.flip_block is not None:
            match = [b for b in info["blocks"] if b["index"] == args.flip_block]
            if not match:
                raise Refused(f"no block with index {args.flip_block:#x}")
            b = match[0]
            if not 0 <= args.flip_offset < b["length"]:
                raise Refused(
                    f"--flip-offset {args.flip_offset} is outside the "
                    f"{b['length']}-byte value for index {b['index']:#x}"
                )
            flipped = b["offset"] + args.flip_offset

        if args.flip_byte is not None:
            if flipped is not None:
                raise Refused("give --flip-byte or --flip-block, not both")
            flipped = args.flip_byte

        if flipped is not None:
            if not 0 <= flipped < len(raw):
                raise Refused(f"offset {flipped} is outside the {len(raw)}-byte file")
            where = locate(info, flipped, len(raw))
            in_value = "value for measurement index" in where
            if not in_value and not args.force:
                # A tamper experiment that changed the file's structure instead
                # of a measurement would look identical in the log and would
                # mean something entirely different. Refuse by default, and
                # print what the byte actually is so the mistake is obvious.
                raise Refused(
                    f"offset {flipped} is {where}.\n"
                    "  Flipping it would change how the fixture is READ rather than\n"
                    "  what it SAYS, and the run would record a measurement tamper\n"
                    "  that never happened. Use --flip-block/--flip-offset, or pass\n"
                    "  --force if changing the structure is genuinely the experiment."
                )
            raw[flipped] ^= 0x01

        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_bytes(bytes(raw))

        # Read back what was written, through the parser, always. A generator
        # that can emit a file its own reader refuses is a generator that will
        # eventually do it during an experiment.
        written = args.out.read_bytes()
        info = parse(written)

        describe(args.out, written, info)
        if flipped is not None:
            print()
            print(f"flipped   : file offset {flipped} (0x{flipped:x}), XOR 0x01")
            print(f"            {locate(info, flipped, len(written))}")
            print("            record this offset in docs/tamper.md")
        return 0

    except Refused as exc:
        print(f"refused: {exc}", file=sys.stderr)
        return 2
    except OSError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())

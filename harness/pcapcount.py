#!/usr/bin/env python3
"""Minimal, dependency-free reader for classic libpcap files.

    python3 harness/pcapcount.py capture.pcap
    python3 harness/pcapcount.py capture.pcap --json
    python3 harness/pcapcount.py capture.pcap --list

Why this exists instead of `pip install dpkt`
---------------------------------------------
Two reasons, and the second one matters more.

1. Zero dependencies. Ubuntu 24.04 ships a PEP 668 "externally managed"
   Python, so `pip install dpkt` needs a virtualenv, which needs a step in the
   runbook, which is a step that can fail on someone else's machine. The pcap
   file format is a 24-byte header followed by 16-byte record headers. Taking a
   dependency for that is a bad trade.

2. This file is the seed of the pcap statistics tool this project has to write
   anyway. Counting packets is step one of measuring how many bytes a handshake
   costs, which is the number the whole PQC comparison turns on. Growing it from
   here means every byte reported was counted by code in this repository.

Format reference: the classic libpcap file format is a 24-byte global header
(magic, version, tz, sigfigs, snaplen, link type) followed by records of
(ts_sec, ts_subsec, incl_len, orig_len, payload). Endianness is recovered from
the magic number, which the writer emits in its own native byte order.

Exit codes: 0 ok · 2 truncated or malformed · 3 not a classic pcap file
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path

GLOBAL_HEADER_LEN = 24
RECORD_HEADER_LEN = 16

# magic bytes as they appear on disk -> (endian prefix, timestamp resolution)
MAGICS = {
    b"\xd4\xc3\xb2\xa1": ("<", "microsecond"),
    b"\xa1\xb2\xc3\xd4": (">", "microsecond"),
    b"\x4d\x3c\xb2\xa1": ("<", "nanosecond"),
    b"\xa1\xb2\x3c\x4d": (">", "nanosecond"),
}
PCAPNG_MAGIC = b"\x0a\x0d\x0d\x0a"

# Best-effort labels only. The numeric link type is always reported verbatim;
# the label is a convenience and is NOT evidence.
#
# TODO(W02): confirm which value spdm-emu actually writes by reading
# spdm_emu/spdm_emu_common/pcap.c, then record the finding in LOG.md. Until
# that is done, an unrecognised number is printed as "unknown", never guessed.
LINKTYPE_LABELS = {
    0: "NULL/loopback",
    1: "Ethernet",
    101: "RAW IP",
    147: "USER0",
    228: "IPv4",
}


class NotAPcap(Exception):
    pass


class Truncated(Exception):
    pass


def read_pcap(path: Path):
    """Parse a classic pcap file. Returns (summary dict, list of packet dicts)."""
    raw = path.read_bytes()

    if len(raw) < 4:
        raise NotAPcap(f"file is only {len(raw)} bytes; too short to hold a header")

    magic = raw[:4]
    if magic == PCAPNG_MAGIC:
        raise NotAPcap(
            "this is a pcapng file, not a classic pcap. "
            "Convert it first:  editcap -F pcap in.pcapng out.pcap"
        )
    if magic not in MAGICS:
        raise NotAPcap(f"unrecognised magic {magic.hex()}; not a classic pcap file")

    endian, ts_resolution = MAGICS[magic]

    if len(raw) < GLOBAL_HEADER_LEN:
        raise Truncated(
            f"global header needs {GLOBAL_HEADER_LEN} bytes, file has {len(raw)}"
        )

    _, vmaj, vmin, tz, sigfigs, snaplen, linktype = struct.unpack(
        endian + "IHHiIII", raw[:GLOBAL_HEADER_LEN]
    )

    packets = []
    offset = GLOBAL_HEADER_LEN
    truncated_at = None

    while offset < len(raw):
        if offset + RECORD_HEADER_LEN > len(raw):
            truncated_at = offset
            break

        ts_sec, ts_sub, incl_len, orig_len = struct.unpack(
            endian + "IIII", raw[offset : offset + RECORD_HEADER_LEN]
        )
        offset += RECORD_HEADER_LEN

        if offset + incl_len > len(raw):
            truncated_at = offset
            break

        divisor = 1_000_000_000 if ts_resolution == "nanosecond" else 1_000_000
        packets.append(
            {
                "index": len(packets),
                "timestamp": ts_sec + ts_sub / divisor,
                "captured_bytes": incl_len,
                "original_bytes": orig_len,
                "file_offset": offset,
            }
        )
        offset += incl_len

    summary = {
        "file": str(path),
        "file_bytes": len(raw),
        "byte_order": "little-endian" if endian == "<" else "big-endian",
        "timestamp_resolution": ts_resolution,
        "pcap_version": f"{vmaj}.{vmin}",
        "timezone_offset": tz,
        "sigfigs": sigfigs,
        "snaplen": snaplen,
        "linktype": linktype,
        "linktype_label": LINKTYPE_LABELS.get(linktype, "unknown"),
        "packets": len(packets),
        "captured_bytes_total": sum(p["captured_bytes"] for p in packets),
        "original_bytes_total": sum(p["original_bytes"] for p in packets),
        "truncated": truncated_at is not None,
    }
    if truncated_at is not None:
        summary["truncated_at_offset"] = truncated_at
    if packets:
        summary["first_timestamp"] = packets[0]["timestamp"]
        summary["last_timestamp"] = packets[-1]["timestamp"]
        summary["duration_seconds"] = round(
            packets[-1]["timestamp"] - packets[0]["timestamp"], 6
        )

    return summary, packets


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Count and summarise packets in a classic pcap file."
    )
    ap.add_argument("pcap", type=Path, help="path to a .pcap file")
    ap.add_argument("--json", action="store_true", help="machine-readable output")
    ap.add_argument("--list", action="store_true", help="one line per packet")
    args = ap.parse_args()

    if not args.pcap.exists():
        print(f"error: no such file: {args.pcap}", file=sys.stderr)
        return 2

    try:
        summary, packets = read_pcap(args.pcap)
    except NotAPcap as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 3
    except Truncated as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    if args.json:
        payload = {"summary": summary}
        if args.list:
            payload["packets"] = packets
        print(json.dumps(payload, indent=2))
        return 0

    print(f"file       : {summary['file']} ({summary['file_bytes']} bytes)")
    print(f"format     : classic pcap v{summary['pcap_version']}, "
          f"{summary['byte_order']}, {summary['timestamp_resolution']} timestamps")
    print(f"linktype   : {summary['linktype']} ({summary['linktype_label']})")
    print(f"snaplen    : {summary['snaplen']}")
    print(f"packets    : {summary['packets']}")
    print(f"bytes      : {summary['captured_bytes_total']} captured / "
          f"{summary['original_bytes_total']} on the wire")
    if "duration_seconds" in summary:
        print(f"duration   : {summary['duration_seconds']} s")
    if summary["truncated"]:
        print(f"WARNING    : file is truncated at offset "
              f"{summary['truncated_at_offset']} — the capture did not close cleanly")

    if args.list:
        print()
        print(f"{'#':>4}  {'timestamp':>18}  {'captured':>8}  {'wire':>8}")
        for p in packets:
            print(f"{p['index']:>4}  {p['timestamp']:>18.6f}  "
                  f"{p['captured_bytes']:>8}  {p['original_bytes']:>8}")

    return 0


if __name__ == "__main__":
    sys.exit(main())

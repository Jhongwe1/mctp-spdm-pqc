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
This does not decode message BODIES. Reporting `MEASUREMENTS is 674 bytes` is
this file's job; reporting what is inside those 674 bytes is `fields.py`'s, and
duplicating it would create a second parser to keep correct — which is the
thing rule 12 exists to prevent. Week 5 needs per-message byte counts for
Table 1 and that is exactly what this produces.

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
    # The identity harness/verify_repo.sh already asserts between pcapcount.py
    # and fields.py, restated here from this tool's own numbers so that it is
    # checked against the thing it is derived from rather than against a
    # remembered constant.
    stats["framing_accounts_for_the_difference"] = (
        framing is not None
        and stats["captured_bytes_total"]
        == stats["spdm_bytes_total"] + framing * len(parsed)
        + sum(e["captured_bytes"] for e in out if e["spdm_bytes"] is None)
    )
    return stats, out


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
        return 0

    failures = 0
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
    ap.add_argument("pcap", type=Path)
    ap.add_argument("--json", action="store_true", help="machine-readable output")
    ap.add_argument("--list", action="store_true", help="one line per packet")
    ap.add_argument("--check", action="store_true",
                    help="require fields.py, reading the decode, to agree")
    args = ap.parse_args()

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

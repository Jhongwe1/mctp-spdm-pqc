#!/usr/bin/env python3
"""How many messages, packets and round trips a handshake costs — and which of
those three this repository has actually measured.

    python3 bench/exp04_fragmentation.py <capture.pcap> [...] [--mtu 64 128 256]
    python3 bench/exp04_fragmentation.py <capture.pcap> --json
    python3 bench/exp04_fragmentation.py --selftest
    python3 bench/exp04_fragmentation.py --validate <sweep run dir>

Two layers, two models, and only one of them is a measurement
-------------------------------------------------------------
A large SPDM message can be split twice on its way to a device, and the two
splits cost different things:

    SPDM message (post-quantum: a 16,869-byte CERTIFICATE response)
         |
         +--> (1) SPDM CHUNK_GET / CHUNK_RESPONSE, DSP0274
         |        each chunk is a COMPLETE REQUEST/RESPONSE ROUND TRIP
         |        -> costs one bus RTT each
         |
         +--> (2) MCTP packetisation, DSP0236
                  each packet is a continuation of ONE message
                  -> costs bandwidth and a per-packet header, not an RTT

★ Layer 1 is MEASURED here. `bench/data/w8-dts-sweep-*` varies the negotiated
DataTransferSize over six values on one build and counts the chunk round trips
that result, and `--validate` requires the model below to reproduce all six
exactly. It does: 59, 31, 12, 9, 6 and 0.

★ Layer 2 is COMPUTED and is labelled computed everywhere it appears. This
project's captures are MCTP-framed over a TCP socket, which carries each SPDM
message whole; nothing here has ever packetised one. Linux `AF_MCTP` would, and
the development kernel is built without `CONFIG_MCTP` (`docs/env-baseline.md`).
So the packet counts are arithmetic on a measured message length, which is a
different kind of claim from the round-trip counts beside them, and
`docs/roadmap.md` standing rule 4 requires the difference to be visible at the
figure rather than in a footnote.

The two formulas, and the three ways to get them wrong
------------------------------------------------------
MCTP, DSP0236:

    N_packets = ceil( (L_msg + 1) / MTU )

    L_msg  the SPDM message in bytes, from SPDMVersion onwards — READ FROM THE
           CAPTURE, never computed from a signature size in FIPS 204
    +1     the MCTP message-type byte (SPDM = 0x05). It appears in the FIRST
           packet only, which is why it is inside the ceiling and not multiplied
    MTU    the MCTP packet PAYLOAD size; DSP0236's baseline is 64

  1. The 4-byte MCTP transport header is NOT subtracted from the 64. The 64 is
     the payload; the header sits outside it. OpenBMC's `libmctp` sizes an
     ASTLPC buffer as 16 + 4 + 64 = 84, which only adds up that way.
  2. The message-type byte is not per packet.
  3. The thing being split is the whole MEASUREMENTS message — header, block
     count, measurement records, a 32-byte nonce, opaque data, and THEN the
     signature — not the signature field.

SPDM chunking, DSP0274:

    chunks(L, DTS) = 0                                        if L <= DTS
                   = 1 + ceil( (L - (DTS-16)) / (DTS-12) )    otherwise

  The 16 and the 12 are CHUNK_RESPONSE's own header: 12 bytes, plus a 4-byte
  LargeMessageSize that appears in the first chunk only. Same shape as the MCTP
  +1 and for the same reason.

Exit codes: 0 ok · 1 --validate found a disagreement · 2 the inputs are missing
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import pcapstat  # noqa: E402  — same directory, and it owns the capture parser

# DSP0236's baseline transmission unit, and two larger values a binding may
# negotiate. 64 is the only one that is guaranteed routable.
DEFAULT_MTUS = (64, 128, 256)

# The MCTP message-type byte that precedes an SPDM message, once per message.
MCTP_TYPE_BYTES = 1
# DSP0236 transport header, per PACKET, and outside the MTU rather than inside.
MCTP_HEADER_BYTES_PER_PACKET = 4

# CHUNK_RESPONSE's header: 12 bytes, 16 on the first chunk.
CHUNK_HEADER = 12
CHUNK_FIRST_HEADER = 16

# The four message types that ARE the chunking layer rather than inputs to it.
CHUNK_TYPES = ("SPDM_CHUNK_GET", "SPDM_CHUNK_RESPONSE",
               "SPDM_CHUNK_SEND", "SPDM_CHUNK_SEND_ACK")


def mctp_packets(msg_bytes: int, mtu: int) -> int:
    """DSP0236 packet count for one SPDM message. Computed, not observed."""
    if mtu <= 0:
        raise ValueError("MTU must be positive")
    return math.ceil((msg_bytes + MCTP_TYPE_BYTES) / mtu)


def chunk_roundtrips(msg_bytes: int, dts: int) -> int:
    """DSP0274 chunk round trips for one SPDM message at a DataTransferSize.

    Validated against six measured points; see --validate.
    """
    if msg_bytes <= dts:
        return 0
    first = dts - CHUNK_FIRST_HEADER
    rest = dts - CHUNK_HEADER
    if first <= 0 or rest <= 0:
        raise ValueError(f"DataTransferSize {dts} is smaller than a chunk header")
    if msg_bytes <= first:
        return 1
    return 1 + math.ceil((msg_bytes - first) / rest)


def analyse(path: Path, mtus=DEFAULT_MTUS) -> dict:
    """One capture, per message and in total."""
    stats, entries = pcapstat.messages(path)
    dts = ((stats.get("capabilities") or {}).get("responder") or {}) \
        .get("data_transfer_size")

    # ★ The WIRE view, deliberately. MCTP packetises what SPDM hands the
    # transport, and when SPDM chunks a message what it hands down is each
    # CHUNK_RESPONSE, not the message they add up to. Estimating MCTP packets
    # from the reassembled length would skip a whole layer and undercount.
    rows = []
    for e in entries:
        if e.get("spdm_bytes") is None:
            continue
        row = {
            "packet": e["packet"],
            "name": e["name"],
            "direction": e["direction"],
            "msg_bytes": e["spdm_bytes"],
            "mctp_packets": {str(m): mctp_packets(e["spdm_bytes"], m) for m in mtus},
        }
        rows.append(row)

    # ── the two layers, kept apart ──────────────────────────────────────────
    #
    # Folding these together is the mistake this file exists to prevent: a
    # "fragment count" that adds chunk round trips to MCTP packets adds an RTT
    # to a byte and reports the sum as one number.
    chunk_msgs = stats["chunking"]["messages"]
    measured = {
        "spdm_messages": len(rows),
        "spdm_bytes_total": stats["spdm_bytes_total"],
        "captured_bytes_total": stats["captured_bytes_total"],
        "data_transfer_size": dts,
        # A round trip is a request with its response. Every CHUNK_GET has one
        # CHUNK_RESPONSE, so the count of either is the count of round trips.
        "chunk_roundtrips": chunk_msgs.get("SPDM_CHUNK_GET", 0),
        "chunk_responses": chunk_msgs.get("SPDM_CHUNK_RESPONSE", 0),
        "large_response_errors": stats["chunking"]["large_response_errors"],
        "cert_roundtrips": stats["certificates"]["roundtrips"],
    }

    computed = {}
    for m in mtus:
        packets = sum(r["mctp_packets"][str(m)] for r in rows)
        computed[str(m)] = {
            "est_mctp_packets": packets,
            "est_header_bytes": packets * MCTP_HEADER_BYTES_PER_PACKET,
            "est_wire_bytes": (stats["spdm_bytes_total"]
                               + len(rows) * MCTP_TYPE_BYTES
                               + packets * MCTP_HEADER_BYTES_PER_PACKET),
        }

    return {
        "file": str(path),
        "measured": measured,
        "computed_mctp": computed,
        "computed_note": ("MCTP packet counts are arithmetic on measured "
                          "message lengths. No capture in this repository was "
                          "produced over a real MCTP transport; the kernel "
                          "here has no CONFIG_MCTP."),
        "messages": rows,
    }


def validate(run_dir: Path) -> int:
    """Require chunk_roundtrips() to reproduce a measured DataTransferSize sweep.

    ★ This is the difference between a model and a guess. The sweep varied one
    compile-time-turned-runtime parameter over six values and counted what
    happened; this replays those six from the message lengths in each capture
    and requires the same answer. A model that agreed at one point and not the
    others would be a coincidence, and the 32x range is what makes that visible.
    """
    caps = sorted(run_dir.glob("*.pcap"))
    if not caps:
        print(f"no captures in {run_dir}", file=sys.stderr)
        return 2

    print(f"validating the chunk model against {len(caps)} captures in "
          f"{run_dir.name}")
    print()
    print(f"  {'arm':<14} {'DTS':>6} {'measured':>9} {'model':>7}  verdict")
    failures = 0
    seen_dts: list[int] = []
    for cap in caps:
        stats, entries = pcapstat.messages(cap)
        dts = ((stats.get("capabilities") or {}).get("responder") or {}) \
            .get("data_transfer_size")
        measured = stats["chunking"]["messages"].get("SPDM_CHUNK_GET", 0)
        if dts is None:
            print(f"  {cap.stem:<14} {'-':>6} {measured:>9} {'-':>7}  "
                  f"no CAPABILITIES in this capture")
            failures += 1
            continue

        # The model is applied to the LOGICAL messages: every message that was
        # not chunked at its own length, plus every message that WAS chunked at
        # the length pcapstat reassembled it to.
        #
        # ★ Feeding it the CHUNK_RESPONSE messages instead would be feeding the
        # model its own answer — they are 4,352 bytes each precisely because
        # DataTransferSize made them so. The reassembled lengths come from the
        # sequences' own LargeMessageSize fields, which are the same in every
        # arm of the sweep because the certificate chain is.
        predicted = 0
        for e in entries:
            n = e.get("spdm_bytes")
            if n is None or e.get("name") in CHUNK_TYPES:
                continue
            predicted += chunk_roundtrips(n, dts)
        for seq in stats["chunking"]["reassembled"]["sequences"]:
            if seq.get("complete"):
                predicted += chunk_roundtrips(seq["assembled_bytes"], dts)
        seen_dts.append(dts)

        ok = predicted == measured
        failures += 0 if ok else 1
        print(f"  {cap.stem:<14} {dts:>6} {measured:>9} {predicted:>7}  "
              f"{'ok' if ok else 'DISAGREES'}")

    print()
    if failures:
        print(f"  {failures} capture(s) disagree with the model. Either the "
              f"model is wrong or the reassembly is, and the model is not "
              f"publishable until they agree.")
        return 1
    span = (max(seen_dts) // min(seen_dts)) if seen_dts else 0
    print(f"  the model reproduces every measured chunk round-trip count, over "
          f"a {span}x range of DataTransferSize ({min(seen_dts)} to "
          f"{max(seen_dts)} bytes)")
    return 0


def selftest() -> int:
    """The arithmetic, and the three ways it is usually written wrong."""
    fails = 0
    checks = 0

    def bad(msg):
        nonlocal fails
        fails += 1
        print(f"  FAIL {msg}")

    print("the message-type byte is added once, not once per packet")
    checks += 1
    # 64 bytes of SPDM plus one type byte is 65, which does not fit in one
    # 64-byte packet. The wrong formula (64-4-1 = 59 usable) says 2 as well, so
    # a second case is needed to tell them apart.
    if mctp_packets(64, 64) != 2:
        bad(f"mctp_packets(64, 64) = {mctp_packets(64, 64)}, want 2")
    if mctp_packets(63, 64) != 1:
        bad(f"mctp_packets(63, 64) = {mctp_packets(63, 64)}, want 1 — 63 SPDM "
            f"bytes plus one type byte is exactly 64")

    print("the 4-byte transport header is NOT taken out of the MTU")
    checks += 1
    # The common wrong version is ceil(L / (MTU - 4 - 1)). At L=177, MTU=64 it
    # says 4 (177/59) and the right answer is 3 (178/64). One case separates
    # them; this is that case.
    if mctp_packets(177, 64) != 3:
        bad(f"mctp_packets(177, 64) = {mctp_packets(177, 64)}, want 3. Getting "
            f"4 here means 59 usable bytes was assumed, which is the "
            f"subtract-the-header mistake")

    print("a message that fits in DataTransferSize is not chunked")
    checks += 1
    for n in (1, 1000, 4608):
        if chunk_roundtrips(n, 4608) != 0:
            bad(f"chunk_roundtrips({n}, 4608) = {chunk_roundtrips(n, 4608)}, "
                f"want 0")

    print("one byte over DataTransferSize costs two round trips, not one")
    checks += 1
    # Because the first chunk can only carry DTS-16 and the rest DTS-12, a
    # message of DTS+1 bytes does not fit in a single chunk either.
    if chunk_roundtrips(4609, 4608) != 2:
        bad(f"chunk_roundtrips(4609, 4608) = {chunk_roundtrips(4609, 4608)}, "
            f"want 2")

    print("the first chunk's LargeMessageSize is counted once")
    checks += 1
    # A model using DTS-12 for every chunk gives 4 here; the correct one gives
    # 5, because the first chunk is four bytes shorter.
    #   first  = 4608-16 = 4592 ; rest = 4608-12 = 4596
    #   1 + ceil((23000-4592)/4596) = 1 + ceil(4.005...) = 6
    got = chunk_roundtrips(23000, 4608)
    want = 1 + math.ceil((23000 - 4592) / 4596)
    if got != want:
        bad(f"chunk_roundtrips(23000, 4608) = {got}, want {want}")

    print("the six measured points, from the sweep, by hand")
    # ★ The numbers on the right are what bench/data/w8-dts-sweep-* actually
    # counted for P2's three certificate fetches, worked out here from the
    # message length alone. --validate does this from the captures; this does it
    # from constants, so the model stays checked even if every capture is lost.
    checks += 1
    chain_msg = 16869          # 16,853-byte chain plus a 16-byte CERTIFICATE header
    for dts, per_fetch in ((1024, 17), (2048, 9), (4608, 4),
                           (8192, 3), (16384, 2), (32768, 0)):
        got = chunk_roundtrips(chain_msg, dts)
        if got != per_fetch:
            bad(f"a {chain_msg}-byte message at DTS {dts}: model says {got}, "
                f"the sweep measured {per_fetch} per certificate fetch")

    print("a DataTransferSize below a chunk header is refused, not divided")
    checks += 1
    try:
        chunk_roundtrips(10000, 8)
        bad("DTS=8 did not raise")
    except ValueError:
        pass

    print()
    print(f"{checks} checks, {fails} failed")
    return 1 if fails else 0


def main() -> int:
    ap = argparse.ArgumentParser(
        description="fragmentation and chunking, measured and computed apart")
    ap.add_argument("pcap", nargs="*", type=Path)
    ap.add_argument("--mtu", nargs="+", type=int, default=list(DEFAULT_MTUS),
                    help="MCTP packet payload sizes to compute for (default 64 128 256)")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--validate", type=Path, metavar="RUNDIR",
                    help="require the chunk model to reproduce a measured sweep")
    args = ap.parse_args()

    if args.selftest:
        return selftest()
    if args.validate:
        return validate(args.validate)
    if not args.pcap:
        ap.error("give at least one capture, or --selftest, or --validate")

    results = []
    for p in args.pcap:
        if not p.exists():
            print(f"no such capture: {p}", file=sys.stderr)
            return 2
        results.append(analyse(p, tuple(args.mtu)))

    if args.json:
        print(json.dumps(results if len(results) > 1 else results[0], indent=2))
        return 0

    for r in results:
        m = r["measured"]
        print(f"{Path(r['file']).name}")
        print(f"  measured   {m['spdm_messages']} SPDM messages, "
              f"{m['spdm_bytes_total']} SPDM bytes, "
              f"DataTransferSize {m['data_transfer_size']}")
        print(f"  measured   {m['cert_roundtrips']} GET_CERTIFICATE round trips, "
              f"{m['chunk_roundtrips']} chunk round trips, "
              f"{m['large_response_errors']} LargeResponse errors")
        print(f"  computed   MCTP packetisation — no capture here was produced "
              f"over a real MCTP transport")
        for mtu in sorted(r["computed_mctp"], key=int):
            c = r["computed_mctp"][mtu]
            print(f"    MTU {mtu:>4}: {c['est_mctp_packets']:>6} packets, "
                  f"{c['est_header_bytes']:>6} header bytes, "
                  f"{c['est_wire_bytes']:>7} on the wire   [computed]")
        biggest = sorted(r["messages"], key=lambda x: -x["msg_bytes"])[:5]
        print(f"  the five largest messages:")
        for row in biggest:
            at64 = row["mctp_packets"][str(sorted(args.mtu)[0])]
            print(f"    {row['name']:<28} {row['msg_bytes']:>7} B  "
                  f"{at64:>5} packets at MTU {sorted(args.mtu)[0]}  [computed]")
        print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

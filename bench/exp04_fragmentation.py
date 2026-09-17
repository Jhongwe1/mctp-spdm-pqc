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
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "harness"))
import pcapstat  # noqa: E402  — same directory, and it owns the capture parser
import pcapcount  # noqa: E402  — harness/, and it owns the pcap file format

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


def mctp_packets_subtract_header(msg_bytes: int, mtu: int) -> int:
    """The wrong formula, written down so it can be evaluated.

    `ceil(L / (MTU - 4 - 1))`: the version that reasons the four-byte transport
    header and the message-type byte eat into the transmission unit. It exists
    here for one reason — a claim that two formulas disagree at some length is
    itself a claim, and until 2026-09-18 this file asserted one in a comment
    that was false. See selftest().
    """
    usable = mtu - MCTP_HEADER_BYTES_PER_PACKET - MCTP_TYPE_BYTES
    if usable <= 0:
        raise ValueError(f"MTU {mtu} leaves no room under the wrong formula")
    return math.ceil(msg_bytes / usable)


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
    # ── 2026-09-18: this check used to be wrong about its own point ────────
    #
    # It read: "The common wrong version is ceil(L / (MTU - 4 - 1)). At L=177,
    # MTU=64 it says 4 (177/59) and the right answer is 3 (178/64). One case
    # separates them; this is that case."
    #
    # 59 x 3 = 177 exactly, so ceil(177/59) is 3, and 177 is one of the 300
    # lengths in 1..399 at which the two formulas AGREE. The case chosen to
    # separate them separated nothing. Nothing caught it because the rival was
    # named in a comment and never evaluated — the assertion only ever checked
    # that the right formula gave the right answer, which it would have done
    # just as happily at a length that proved nothing.
    #
    # So the rival is now a function, the separation is computed, and the
    # length that does not separate is pinned as not separating. That is
    # standing rule 11 applied to a claim rather than to a check: something has
    # to demonstrate the difference, or the difference is a belief.
    if mctp_packets(177, 64) != 3:
        bad(f"mctp_packets(177, 64) = {mctp_packets(177, 64)}, want 3")
    if mctp_packets_subtract_header(177, 64) != 3:
        bad("ceil(177/59) is 3; if this fires the rival formula was changed")
    if mctp_packets(177, 64) != mctp_packets_subtract_header(177, 64):
        bad("177 is being treated as a separating case again; it is not")

    # Lengths that do separate them, computed rather than asserted.
    separators = [n for n in range(1, 400)
                  if mctp_packets(n, 64) != mctp_packets_subtract_header(n, 64)]
    if separators[:4] != [60, 61, 62, 63]:
        bad(f"the smallest separating lengths are {separators[:4]}, expected "
            f"60..63")
    for n, want_right, want_wrong in ((63, 1, 2), (127, 2, 3), (16853, 264, 286)):
        got_r = mctp_packets(n, 64)
        got_w = mctp_packets_subtract_header(n, 64)
        if got_r != want_right or got_w != want_wrong:
            bad(f"at L={n}: right {got_r} (want {want_right}), "
                f"wrong {got_w} (want {want_wrong})")

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

    # ── the reassembler, and the three ways a link breaks it ───────────────
    #
    # Standing rule 11: a check is worth what it rejects, and something has to
    # prove it rejects. group_mctp_messages() turns a packet capture into the
    # message lengths the whole observed comparison rests on, so each of its
    # three complaints is fired here deliberately. Two of these are live
    # failure modes on a pty pair, not hypotheticals — nothing between the two
    # ends of that link provides flow control.
    #
    # Rule 13 as well: the three are refused through *different* branches, and
    # a suite where all three came back "never reached EOM" would report three
    # times the coverage it has.

    def pkt(som, eom, seq, payload_len, tag=0, src=8, dest=9, first=0x05):
        body = bytes([first]) + bytes(payload_len - 1) if payload_len else b""
        flags = (0x80 if som else 0) | (0x40 if eom else 0) | ((seq & 3) << 4) | tag
        return parse_mctp_packet(bytes([1, dest, src, flags]) + body)

    print("the reassembler agrees with the model on a clean three-packet message")
    checks += 1
    msgs, probs = group_mctp_messages(
        [pkt(True, False, 0, 64), pkt(False, False, 1, 64), pkt(False, True, 2, 50)]
    )
    if probs:
        bad(f"a clean message produced complaints: {probs}")
    elif len(msgs) != 1 or msgs[0]["packets"] != 3:
        bad(f"clean message: {len(msgs)} messages, {msgs and msgs[0]['packets']} packets")
    else:
        # 64 + 64 + 50 payload bytes, minus the one type byte, is 177 - the
        # length the two candidate formulas disagree about.
        length = msgs[0]["payload_bytes"] - MCTP_TYPE_BYTES
        if length != 177 or mctp_packets(length, 64) != 3:
            bad(f"reassembled {length} bytes, model {mctp_packets(length, 64)}, want 177 and 3")

    print("the reassembler refuses a message that never reaches EOM")
    checks += 1
    _m, probs = group_mctp_messages([pkt(True, False, 0, 64), pkt(False, False, 1, 64)])
    if not any("never reached EOM" in x for x in probs):
        bad(f"a message with no EOM was not reported: {probs}")

    print("the reassembler refuses a gap in the packet sequence")
    checks += 1
    _m, probs = group_mctp_messages(
        [pkt(True, False, 0, 64), pkt(False, True, 2, 20)]  # seq 1 is missing
    )
    if not any("sequence" in x for x in probs):
        bad(f"a dropped packet was not reported: {probs}")

    print("the reassembler refuses a continuation with no start")
    checks += 1
    _m, probs = group_mctp_messages([pkt(False, True, 1, 20)])
    if not any("no SOM" in x for x in probs):
        bad(f"an orphan continuation was not reported: {probs}")

    print("a packet too short to hold a header is refused, not indexed")
    checks += 1
    try:
        parse_mctp_packet(b"\x01\x09\x08")
        bad("a three-byte packet did not raise")
    except ValueError:
        pass

    print()
    print(f"{checks} checks, {fails} failed")
    return 1 if fails else 0


# ── observed: the same arithmetic, against a capture of a real MCTP link ────
#
# Everything above this point is computed. This is not.
#
# harness/run_afmctp.sh boots a guest whose kernel has CONFIG_MCTP, builds an
# mctp-serial link out of a pty pair, and captures the link itself with
# harness/mctp_capture.py. Each record in that capture is one MCTP *packet*:
# a four-byte transport header and up to `mtu - 4` bytes of payload.
#
# The header layout is DSP0236's and is what net/mctp writes:
#
#     byte 0   ver                     always 1 out of mctp_local_output
#     byte 1   dest                    endpoint ID
#     byte 2   src                     endpoint ID
#     byte 3   flags_seq_tag           SOM<<7 | EOM<<6 | seq<<4 | TO<<3 | tag
#
# Grouping those back into messages is what turns a packet count into a
# comparison: the model predicts packets per MESSAGE, so the messages have to
# be recovered before the prediction means anything.

MCTP_HDR_LEN = 4
MCTP_FLAG_SOM = 0x80
MCTP_FLAG_EOM = 0x40
MCTP_FLAG_TO = 0x08
MCTP_SEQ_SHIFT = 4
MCTP_SEQ_MASK = 0x03
MCTP_TAG_MASK = 0x07


def parse_mctp_packet(raw: bytes) -> dict:
    """One captured packet, as its header describes itself."""
    if len(raw) < MCTP_HDR_LEN:
        raise ValueError(f"packet of {len(raw)} bytes cannot hold an MCTP header")
    ver, dest, src, flags = raw[0], raw[1], raw[2], raw[3]
    return {
        "ver": ver,
        "dest": dest,
        "src": src,
        "som": bool(flags & MCTP_FLAG_SOM),
        "eom": bool(flags & MCTP_FLAG_EOM),
        "seq": (flags >> MCTP_SEQ_SHIFT) & MCTP_SEQ_MASK,
        "to": bool(flags & MCTP_FLAG_TO),
        "tag": flags & MCTP_TAG_MASK,
        "payload": raw[MCTP_HDR_LEN:],
    }


def group_mctp_messages(packets: list) -> tuple:
    """Reassemble packets into messages. Returns (messages, problems).

    A message is the run of packets sharing (src, dest, tag, TO) that begins
    with SOM and ends with EOM, with the sequence number advancing by one
    modulo four across it. Every one of those three conditions is checked and
    reported rather than assumed, because each has a failure that would
    otherwise be invisible in the total:

      * a lost SOM makes a message look shorter than it was,
      * a lost EOM merges two messages into one,
      * a sequence gap means a packet was dropped, and the count this whole
        analysis rests on would be an undercount reported as a measurement.

    A pty pair has no flow control worth the name, so these are live failure
    modes on this link, not theoretical ones.
    """
    open_msgs = {}
    messages = []
    problems = []

    for idx, pkt in enumerate(packets):
        key = (pkt["src"], pkt["dest"], pkt["tag"], pkt["to"])
        cur = open_msgs.get(key)

        if pkt["som"]:
            if cur is not None:
                problems.append(
                    f"packet {idx}: SOM for {key} while a message was still open "
                    f"({cur['packets']} packets in, no EOM seen)"
                )
            cur = {
                "first_index": idx,
                "src": pkt["src"],
                "dest": pkt["dest"],
                "tag": pkt["tag"],
                "to": pkt["to"],
                "ver": pkt["ver"],
                "packets": 0,
                "payload_bytes": 0,
                "payload_sizes": [],
                "msg_type": pkt["payload"][0] if pkt["payload"] else None,
                "next_seq": pkt["seq"],
                "complete": False,
            }
            open_msgs[key] = cur
        elif cur is None:
            problems.append(
                f"packet {idx}: continuation for {key} with no SOM before it"
            )
            continue
        else:
            if pkt["seq"] != cur["next_seq"]:
                problems.append(
                    f"packet {idx}: sequence {pkt['seq']}, expected "
                    f"{cur['next_seq']} - a packet was lost or reordered"
                )

        cur["packets"] += 1
        cur["payload_bytes"] += len(pkt["payload"])
        cur["payload_sizes"].append(len(pkt["payload"]))
        cur["next_seq"] = (pkt["seq"] + 1) & MCTP_SEQ_MASK

        if pkt["eom"]:
            cur["complete"] = True
            cur["last_index"] = idx
            messages.append(cur)
            del open_msgs[key]

    for key, cur in open_msgs.items():
        problems.append(
            f"message {key} beginning at packet {cur['first_index']} never "
            f"reached EOM ({cur['packets']} packets)"
        )
        messages.append(cur)

    return messages, problems


def observed(pcap: Path, mtu_payload: int | None = None) -> dict:
    """Read a real MCTP link capture and hold the model to it."""
    summary, records = pcapcount.read_pcap(pcap)
    raw = pcap.read_bytes()

    if summary["linktype"] != 291:
        raise ValueError(
            f"{pcap} has link type {summary['linktype']}, not 291 (MCTP)"
        )

    # ★ The transmission unit is READ, not assumed. harness/mctp_capture.py
    # writes the interface's MTU into a sidecar at capture time; the kernel
    # took it from drivers/net/mctp/mctp-serial.c, which fixes it at 68 - "base
    # mtu (64) + mctp header". Subtracting the header here is the one step that
    # turns an interface MTU into the payload the model divides by, and doing
    # it from the sidecar rather than from a constant is what makes this a
    # measurement of whatever link it was pointed at.
    meta_path = Path(str(pcap) + ".meta.json")
    iface_mtu = None
    ifstats = None
    capture_drops = None
    if meta_path.exists():
        meta = json.loads(meta_path.read_text())
        iface_mtu = meta.get("mtu")
        ifstats = meta.get("ifstats_delta")
        capture_drops = meta.get("socket_tp_drops")
    if mtu_payload is None:
        if iface_mtu is None:
            raise ValueError(
                f"no {meta_path.name} beside the capture, so the link's MTU is "
                f"unknown; pass --mtu to state it"
            )
        mtu_payload = iface_mtu - MCTP_HEADER_BYTES_PER_PACKET

    packets = []
    for rec in records:
        off = rec["file_offset"]
        packets.append(parse_mctp_packet(raw[off : off + rec["captured_bytes"]]))

    messages, problems = group_mctp_messages(packets)

    # ★ Before any of the packets are interpreted: did the capture get all of
    # them? The interface counters and the capture are two independent counts
    # of the same events, and if they disagree the analysis below is arithmetic
    # on a subset. On 2026-09-18 a repeat of the same run captured 920 packets
    # where the interface had moved 953, and the first visible symptom was
    # eighty-six orphaned continuations — a diagnosis of the link, for a fault
    # in the instrument.
    if capture_drops:
        problems.insert(
            0,
            f"the capture socket dropped {capture_drops} packets; every count "
            f"below is an undercount",
        )
    if ifstats:
        moved = (ifstats.get("tx_packets") or 0) + (ifstats.get("rx_packets") or 0)
        if moved and moved != len(packets):
            problems.insert(
                0,
                f"the interface counters moved by {moved} while the capture "
                f"holds {len(packets)} packets",
            )

    rows = []
    disagreements = 0
    for m in messages:
        # The message-type byte is the first byte of the first packet and is
        # not part of the SPDM message, which is exactly the +1 in the model.
        spdm_bytes = m["payload_bytes"] - MCTP_TYPE_BYTES
        predicted = mctp_packets(spdm_bytes, mtu_payload)
        # What the subtract-the-header formula would have said. A capture whose
        # every message length happens to be one the two formulas agree about
        # confirms the arithmetic and discriminates nothing, and a reader
        # cannot tell those two cases apart from a column of ticks.
        rival = mctp_packets_subtract_header(spdm_bytes, mtu_payload)
        agrees = predicted == m["packets"] and m["complete"]
        if not agrees:
            disagreements += 1
        # Every packet but the last should be full. A short one in the middle
        # would mean the sender is not filling the unit, and the model would be
        # right about the arithmetic and wrong about the link.
        interior = m["payload_sizes"][:-1]
        short_interior = [s for s in interior if s != mtu_payload]
        rows.append(
            {
                "type": m["msg_type"],
                "src": m["src"],
                "dest": m["dest"],
                "tag": m["tag"],
                "to": m["to"],
                "msg_bytes": spdm_bytes,
                "packets_observed": m["packets"],
                "packets_model": predicted,
                "packets_rival": rival,
                "separates": rival != predicted,
                "complete": m["complete"],
                "agrees": agrees,
                "short_interior_packets": short_interior,
            }
        )

    spdm_rows = [r for r in rows if r["type"] == 0x05]
    separating = [r for r in spdm_rows if r["separates"]]
    return {
        "separating_messages": len(separating),
        "file": str(pcap),
        "linktype": summary["linktype"],
        "packets_in_capture": len(packets),
        "iface_mtu": iface_mtu,
        "mtu_payload": mtu_payload,
        "ifstats_delta": ifstats,
        "messages": len(messages),
        "spdm_messages": len(spdm_rows),
        "spdm_packets": sum(r["packets_observed"] for r in spdm_rows),
        "spdm_bytes": sum(r["msg_bytes"] for r in spdm_rows),
        "rows": rows,
        "problems": problems,
        "disagreements": disagreements,
    }


def print_observed(o: dict) -> None:
    print(f"{Path(o['file']).name}")
    print(
        f"  observed   link type {o['linktype']}, {o['packets_in_capture']} MCTP "
        f"packets, {o['messages']} messages reassembled"
    )
    print(
        f"  observed   interface MTU {o['iface_mtu']}, "
        f"so {o['mtu_payload']} payload bytes per packet   [read from the link]"
    )
    if o["ifstats_delta"]:
        d = o["ifstats_delta"]
        print(
            f"  observed   the interface counted tx={d.get('tx_packets')} "
            f"rx={d.get('rx_packets')} over the same window, "
            f"tx_dropped={d.get('tx_dropped')} rx_errors={d.get('rx_errors')}"
        )
    print()
    print(
        "    type  src>dst tag  msg_bytes  packets  model  rival  verdict"
    )
    for r in o["rows"]:
        t = "SPDM" if r["type"] == 0x05 else (
            "ctrl" if r["type"] == 0x7E else f"0x{r['type']:02x}"
            if r["type"] is not None else "----")
        mark = "ok" if r["agrees"] else "DISAGREES"
        if not r["complete"]:
            mark = "INCOMPLETE"
        extra = ""
        if r["short_interior_packets"]:
            extra = f"  short interior packets: {r['short_interior_packets']}"
        print(
            f"    {t:<5} {r['src']:>3}>{r['dest']:<3} {r['tag']:>3}  "
            f"{r['msg_bytes']:>9}  {r['packets_observed']:>7}  "
            f"{r['packets_model']:>5}  {r['packets_rival']:>5}"
            f"{'*' if r['separates'] else ' '} {mark}{extra}"
        )
    print()
    if o["problems"]:
        print("  problems on the link:")
        for p in o["problems"]:
            print(f"    {p}")
        print()
    if o["disagreements"] == 0 and not o["problems"]:
        print(
            f"  ★ the model reproduces every observed packet count: "
            f"{o['spdm_messages']} SPDM messages, {o['spdm_bytes']} SPDM bytes, "
            f"{o['spdm_packets']} packets at MTU {o['mtu_payload']}"
        )
        # The rival column is what makes the tick marks mean something. A
        # capture where nothing separates confirms the arithmetic and
        # discriminates nothing, and that is worth saying out loud.
        if o["separating_messages"]:
            print(
                f"  ★ {o['separating_messages']} of {o['spdm_messages']} "
                f"messages (*) are lengths at which the subtract-the-header "
                f"formula would have given a different answer, and it is wrong "
                f"at every one of them"
            )
        else:
            print(
                "  ! no message here is a length at which the two candidate "
                "formulas disagree, so this capture confirms the arithmetic "
                "and discriminates nothing"
            )
    else:
        print(
            f"  {o['disagreements']} message(s) the model did not reproduce, "
            f"{len(o['problems'])} link problem(s)"
        )
    print()


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
    ap.add_argument("--observed", type=Path, metavar="LINKPCAP",
                    help="a capture of a REAL MCTP link; require the packet "
                         "model to reproduce every message in it")
    args = ap.parse_args()

    if args.selftest:
        return selftest()
    if args.validate:
        return validate(args.validate)
    if args.observed:
        if not args.observed.exists():
            print(f"no such capture: {args.observed}", file=sys.stderr)
            return 2
        mtu = args.mtu[0] if args.mtu != list(DEFAULT_MTUS) else None
        try:
            o = observed(args.observed, mtu)
        except ValueError as exc:
            print(f"exp04: {exc}", file=sys.stderr)
            return 2
        if args.json:
            print(json.dumps(o, indent=2))
        else:
            print_observed(o)
        return 0 if (o["disagreements"] == 0 and not o["problems"]) else 1
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

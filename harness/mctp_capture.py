#!/usr/bin/env python3
"""Capture a real MCTP link into a classic pcap, link type 291.

    python3 harness/mctp_capture.py --iface mctpserial0 --out link.pcap \
            --stop-file /out/stop --expect-eids 8,9

Why a capture tool at all
-------------------------
Every pcap in bench/data/ was written by spdm-emu itself: it synthesises a
four-byte MCTP header, hands it to its own pcap writer, and the result is link
type 291.  docs/transports.md shows what those four bytes say — version 0,
destination 0, source 0, tag byte 0xC0, which is SOM and EOM set on every
message and therefore an assertion that nothing was ever split.

This tool writes the same link type from the opposite source: an AF_PACKET
socket on a kernel MCTP interface, where the four bytes are whatever net/mctp
actually put on the wire.  Same format, same analysis path, different witness.
A reader can run harness/pcapcount.py over either.

Two things it deliberately does not do
--------------------------------------
It does not analyse.  Grouping packets into messages and comparing the count
against the model is bench/exp04_fragmentation.py --observed, and keeping the
two apart is standing rule 12: the tool that owns the capture file never also
owns the answer derived from it.

It does not trust that AF_PACKET hands back the link header.  mctp-serial sets
hard_header_len to 0, so whether the four-byte MCTP header appears in the
captured bytes is a property of the kernel tap and not something to assume.
--expect-eids makes the tool check the first packet it sees and fail loudly if
the shape is wrong, because a capture that silently starts one header early is
worse than no capture: it would still parse, and every field would be wrong.

Exit codes: 0 ok · 2 the capture does not look like MCTP · 3 setup failed
"""

from __future__ import annotations

import argparse
import json
import os
import select
import signal
import socket
import struct
import sys
import time
from pathlib import Path

ETH_P_ALL = 0x0003
LINKTYPE_MCTP = 291
SNAPLEN = 262144

# From <linux/if_packet.h>. PACKET_STATISTICS returns struct tpacket_stats,
# two unsigned ints: packets seen and packets DROPPED because the socket
# buffer was full.
#
# ★ This is here because of a run on 2026-09-18. The same experiment, repeated,
# reported 920 packets where the first run reported 953, and the analysis broke
# with eighty-six "continuation with no SOM" complaints — which is what losing a
# start-of-message packet looks like from the far end. The link had not dropped
# anything; `tx_dropped` and `rx_errors` were zero at both interfaces. The
# CAPTURE dropped, because a Python loop doing one select and one recvfrom per
# packet cannot keep up with a burst of nine hundred, and an AF_PACKET socket
# with the default receive buffer discards what it cannot hold.
#
# Two fixes, and the second matters more than the first: ask for a much larger
# buffer, and then READ THE DROP COUNTER and refuse the capture if it moved. An
# instrument that cannot report its own loss turns a measurement into a number.
SOL_PACKET = 263
PACKET_STATISTICS = 6
CAPTURE_RCVBUF = 64 * 1024 * 1024

# From <linux/if_packet.h>. The only one that needs a name here is OUTGOING:
# on the interface that sends, the tap sees the packet on its way out, and a
# reader who assumed every captured packet was received would have the
# direction of the entire conversation backwards.
PACKET_HOST = 0
PACKET_BROADCAST = 1
PACKET_MULTICAST = 2
PACKET_OTHERHOST = 3
PACKET_OUTGOING = 4
PKTTYPE_NAMES = {
    PACKET_HOST: "in",
    PACKET_BROADCAST: "in-bcast",
    PACKET_MULTICAST: "in-mcast",
    PACKET_OTHERHOST: "in-other",
    PACKET_OUTGOING: "out",
}

# Counters worth keeping. rx_errors and tx_dropped are here because a pty pair
# is a lossy thing to build a measurement on, and a packet count is only
# evidence if nothing was dropped while it was taken.
STAT_FIELDS = (
    "rx_packets",
    "tx_packets",
    "rx_bytes",
    "tx_bytes",
    "rx_errors",
    "tx_errors",
    "rx_dropped",
    "tx_dropped",
)


def read_ifstats(iface: str) -> dict:
    base = Path("/sys/class/net") / iface / "statistics"
    out = {}
    for f in STAT_FIELDS:
        try:
            out[f] = int((base / f).read_text().strip())
        except OSError:
            out[f] = None
    return out


def read_mtu(iface: str):
    try:
        return int((Path("/sys/class/net") / iface / "mtu").read_text().strip())
    except OSError:
        return None


def pcap_global_header(linktype: int) -> bytes:
    # native-endian magic, as libpcap writers emit it; harness/pcapcount.py
    # recovers the endianness from it.
    return struct.pack(
        "=IHHiIII", 0xA1B2C3D4, 2, 4, 0, 0, SNAPLEN, linktype
    )


def pcap_record(ts: float, data: bytes) -> bytes:
    sec = int(ts)
    usec = int(round((ts - sec) * 1_000_000))
    if usec >= 1_000_000:  # rounding can carry
        sec += 1
        usec -= 1_000_000
    return struct.pack("=IIII", sec, usec, len(data), len(data)) + data


def looks_like_mctp(pkt: bytes, eids: set[int]) -> tuple[bool, str]:
    """Is the first captured packet a bare MCTP transport header?

    struct mctp_hdr is { ver, dest, src, flags_seq_tag }, and mctp_local_output
    sets ver to 1 unconditionally. So a packet whose first byte is 1 and whose
    next two are the configured endpoint IDs is the header; anything else means
    the tap handed back something other than what was expected, and the caller
    should be told rather than handed a file.
    """
    if len(pkt) < 4:
        return False, f"first packet is {len(pkt)} bytes, shorter than an MCTP header"
    ver, dest, src, _flags = pkt[0], pkt[1], pkt[2], pkt[3]
    if ver != 1:
        return False, (
            f"first byte is 0x{ver:02x}, not the header version 1 that "
            f"mctp_local_output writes - the capture is probably offset"
        )
    if eids and not ({dest, src} <= eids):
        return False, (
            f"header says dest={dest} src={src}, which are not the endpoint "
            f"IDs this link was configured with ({sorted(eids)})"
        )
    return True, f"ver={ver} dest={dest} src={src}"


def main() -> int:
    ap = argparse.ArgumentParser(description="capture an MCTP interface to pcap")
    ap.add_argument("--iface", required=True)
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument(
        "--stop-file",
        type=Path,
        help="stop when this path appears (the orchestrator creates it)",
    )
    ap.add_argument(
        "--ready-file",
        type=Path,
        help="create this path once the socket is bound and draining; the "
        "caller waits for it before generating traffic",
    )
    ap.add_argument("--duration", type=float, default=600.0, help="hard limit, seconds")
    ap.add_argument(
        "--expect-eids",
        default="",
        help="comma-separated EIDs that must appear in the first packet header",
    )
    args = ap.parse_args()

    eids = {int(x) for x in args.expect_eids.split(",") if x.strip()}

    try:
        sock = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(ETH_P_ALL))
        # SO_RCVBUFFORCE ignores the system maximum and needs CAP_NET_ADMIN,
        # which this has; SO_RCVBUF is the fallback and is silently clamped.
        try:
            sock.setsockopt(socket.SOL_SOCKET, 33, CAPTURE_RCVBUF)  # RCVBUFFORCE
        except OSError:
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, CAPTURE_RCVBUF)
        sock.bind((args.iface, 0))
        sock.setblocking(False)
    except OSError as exc:
        print(f"mctp_capture: cannot bind {args.iface}: {exc}", file=sys.stderr)
        return 3
    rcvbuf = sock.getsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF)

    before = read_ifstats(args.iface)
    mtu = read_mtu(args.iface)

    stop = {"now": False}

    def on_signal(_sig, _frm):
        stop["now"] = True

    signal.signal(signal.SIGTERM, on_signal)
    signal.signal(signal.SIGINT, on_signal)

    # ★ Readiness, not a sleep.
    #
    # The guest runs this out of a root filesystem exported over virtio-9p, and
    # the interpreter's own start-up — every import, stat and read — crosses
    # that. On 2026-09-18 a run whose generator slept 0.7 seconds before
    # starting traffic captured 237 packets of a 368-packet replay, and every
    # one of them was mid-message: the first record had SOM clear. The capture
    # had not dropped anything and the link had not lost anything. The
    # measurement simply began two thirds of the way through.
    #
    # A longer sleep would have made it likely to work rather than certain, and
    # the failure mode is a plausible number rather than an error. So the file
    # is created here, after bind(), and the caller blocks on it.
    if args.ready_file is not None:
        args.ready_file.parent.mkdir(parents=True, exist_ok=True)
        args.ready_file.write_text(f"{args.iface}\n")

    args.out.parent.mkdir(parents=True, exist_ok=True)
    index = []
    first_note = None
    shape_ok = None
    deadline = time.time() + args.duration
    n = 0

    with args.out.open("wb") as fh:
        fh.write(pcap_global_header(LINKTYPE_MCTP))
        while not stop["now"] and time.time() < deadline:
            if args.stop_file is not None and args.stop_file.exists():
                break
            try:
                ready, _, _ = select.select([sock], [], [], 0.25)
            except (OSError, InterruptedError):
                break
            if not ready:
                continue
            # Drain rather than take one per select. The socket is
            # non-blocking, so this runs until EAGAIN, and it is the difference
            # between one select per packet and one per burst.
            while True:
                try:
                    pkt, sa = sock.recvfrom(SNAPLEN)
                except BlockingIOError:
                    break
                except OSError:
                    stop["now"] = True
                    break
                ts = time.time()
                pkttype = sa[2] if len(sa) > 2 else -1

                if shape_ok is None:
                    shape_ok, first_note = looks_like_mctp(pkt, eids)

                fh.write(pcap_record(ts, pkt))
                index.append(
                    {
                        "i": n,
                        "ts": round(ts, 6),
                        "len": len(pkt),
                        "dir": PKTTYPE_NAMES.get(pkttype, str(pkttype)),
                    }
                )
                n += 1
        fh.flush()
        os.fsync(fh.fileno())

    # PACKET_STATISTICS is read-and-clear, so it is read exactly once, here.
    tp_packets = tp_drops = None
    try:
        raw = sock.getsockopt(SOL_PACKET, PACKET_STATISTICS, 8)
        tp_packets, tp_drops = struct.unpack("=II", raw)
    except OSError:
        pass

    sock.close()
    after = read_ifstats(args.iface)

    sidecar = args.out.with_suffix(args.out.suffix + ".meta.json")
    sidecar.write_text(
        json.dumps(
            {
                "iface": args.iface,
                "mtu": mtu,
                "linktype": LINKTYPE_MCTP,
                "packets_captured": n,
                "socket_rcvbuf": rcvbuf,
                "socket_tp_packets": tp_packets,
                "socket_tp_drops": tp_drops,
                "header_shape_ok": shape_ok,
                "header_note": first_note,
                "ifstats_before": before,
                "ifstats_after": after,
                "ifstats_delta": {
                    k: (
                        None
                        if before.get(k) is None or after.get(k) is None
                        else after[k] - before[k]
                    )
                    for k in STAT_FIELDS
                },
                "packets": index,
            },
            indent=2,
        )
        + "\n"
    )

    delta = {
        k: (
            None
            if before.get(k) is None or after.get(k) is None
            else after[k] - before[k]
        )
        for k in STAT_FIELDS
    }
    print(f"mctp_capture: {n} packets from {args.iface} (mtu {mtu}) -> {args.out}")
    print(
        "mctp_capture: interface counters moved "
        f"tx={delta['tx_packets']} rx={delta['rx_packets']} "
        f"tx_dropped={delta['tx_dropped']} rx_errors={delta['rx_errors']}"
    )

    if n == 0:
        print("mctp_capture: nothing was captured", file=sys.stderr)
        return 2
    if shape_ok is False:
        print(f"mctp_capture: {first_note}", file=sys.stderr)
        return 2
    print(f"mctp_capture: first packet header {first_note}")

    # The instrument reports its own loss, and a lossy capture is refused here
    # rather than left to produce a plausible-looking undercount downstream.
    if tp_drops:
        print(
            f"mctp_capture: the socket DROPPED {tp_drops} of {tp_packets} "
            f"packets (receive buffer {rcvbuf} bytes) - this capture undercounts",
            file=sys.stderr,
        )
        return 2
    moved = (delta["tx_packets"] or 0) + (delta["rx_packets"] or 0)
    if moved and moved != n:
        print(
            f"mctp_capture: captured {n} packets but the interface counters "
            f"moved by {moved}; the capture and the link disagree",
            file=sys.stderr,
        )
        return 2
    print(
        f"mctp_capture: no drops ({tp_packets} seen by the socket, "
        f"interface counters moved {moved})"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

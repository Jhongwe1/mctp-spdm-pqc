# Two layers of splitting, and only one of them is measured here

> **I did protocol-flow level correctness validation, not a security
> assessment.** This document is arithmetic about message sizes.

A large SPDM message can be split twice on its way to a device, and the two
splits cost different things. Getting them confused is the single most common
error in a post-quantum SPDM cost estimate, because it turns a round trip into a
byte and reports the sum as one number.

```
   SPDM message  (post-quantum: a 16,869-byte CERTIFICATE response)
        │
        ├──▶ ① SPDM chunking — CHUNK_GET / CHUNK_RESPONSE, DSP0274 1.2+
        │       triggered when the message exceeds the peer's DataTransferSize
        │       ★ each chunk is a COMPLETE REQUEST/RESPONSE ROUND TRIP
        │          → costs one bus RTT each
        │
        └──▶ ② MCTP packetisation — DSP0236
                triggered when the message exceeds the MCTP MTU
                each packet is a continuation of ONE message, not a new request
                → costs bandwidth and a per-packet header, not an RTT
```

|  | ① SPDM chunking | ② MCTP packetisation |
|---|---|---|
| who splits | SPDM, in libspdm | the transport binding / kernel |
| what one piece is | a whole request/response exchange | one packet of one message |
| dominant cost | ★ **RTT × pieces** | bandwidth + per-packet header |
| which happens first | this one — it is above MCTP | after chunking has already split |
| how you see it | `CHUNK_GET` / `CHUNK_RESPONSE` in a capture | **only over a real MCTP transport** |
| **status in this repository** | **MEASURED, modelled, and the model validated** | **MEASURED since 2026-09-18** |

That last row was the point of this document, and until 2026-09-18 it read
**COMPUTED**. What replaced it is in §2.4: a real MCTP link, at DSP0236's
baseline transmission unit, carrying the same two handshakes the socket line
carries, with every packet counted off the wire.

---

## 1. Why one was computed for eight weeks, and what changed

Every capture taken before 2026-09-18 is MCTP-*framed* over a TCP socket:
`spdm-emu`'s socket transport prepends the four-byte MCTP transport header and
the message-type byte and then hands the whole SPDM message to TCP, which never
packetises it at 64 bytes. So the message-type byte and the framing are real and
present in every one of those captures — `bench/pcapstat.py` accounts for exactly
five bytes per packet — and the *packetisation* had never happened.

Linux `AF_MCTP` would do it, and this development machine's kernel cannot:

```console
$ zcat /proc/config.gz | grep CONFIG_MCTP
# CONFIG_MCTP is not set
$ ./afmctp_probe
socket(AF_MCTP) -> errno 97 (Address family not supported by protocol)
```

★ **That was never a reason to stop, and treating it as one for eight weeks was
the mistake.** The subsystem does not have to be on the host. It has to be
*somewhere the same binaries can run*, and a virtual machine whose root
filesystem is the host's own — exported over virtio-9p and mounted read-only —
is somewhere the same binaries can run. The `spdm_requester_emu` built in week
one runs inside it unchanged, from the same path, against the same certificates.

So Gate 5 built a guest kernel with `CONFIG_MCTP=y` instead of rebuilding this
one. [ADR 0010](decisions/0010-a-kernel-the-host-does-not-have.md) records why
round that way: `host_kernel` appears in every manifest in `bench/data/`, and
replacing the host kernel would have made every one of those lines name a kernel
that no longer exists on the machine.

The apparatus is in [`transports.md`](transports.md) §"Route ③". What matters
here is that **the packet counts below are counted, not divided**, and that
`bench/exp04_fragmentation.py --observed` is the thing that counts them.

Counts for transmission units other than the one that link has are still
computed, and still say so: `docs/roadmap.md` standing rule 4 requires that to
be visible at the figure rather than in a footnote, and
`bench/exp04_fragmentation.py` still prints `[computed]` beside each one.

---

## 2. The MCTP formula, and the three ways it is usually written wrong

```
N_packets = ceil( (L_msg + 1) / MTU )

  L_msg   the SPDM message in bytes, from the SPDMVersion byte onwards
          ★ READ FROM THE CAPTURE, never computed from a signature size
  +1      the MCTP message-type byte (IC + MsgType; SPDM is 0x05)
          ★ FIRST PACKET ONLY, which is why it is inside the ceiling
  MTU     the MCTP packet PAYLOAD size. DSP0236's baseline is 64, and 64 is the
          only value guaranteed to be routable; larger may be negotiated
```

### ① The 4-byte transport header is not subtracted from the 64

The tempting wrong version is `ceil(L / (MTU - 4 - 1))`, on the reasoning that
the header and the type byte eat into the 64. They do not: **64 is the packet
payload, and the transport header sits outside it.** The two are added, not
subtracted.

The cheapest independent confirmation is OpenBMC's `libmctp`, whose ASTLPC
binding sizes its buffer as `16 + 4 + 64 = 84` — a number that only adds up that
way round.

🔴 **This paragraph used to name the wrong case, and the check that was
supposed to prove it never evaluated the rival.** It read: *"a 177-byte message
at MTU 64 is 3 packets (`ceil(178/64)`), and the subtract-the-header version
says 4 (`ceil(177/59)`)."* `59 x 3 = 177` exactly, so the subtract-the-header
version says **3**, and 177 is one of the 300 lengths in 1..399 at which the two
formulas *agree*. The case chosen to separate them separated nothing.

Nothing caught it for three weeks because the rival was named in a sentence and
never computed: `--selftest` asserted only that the right formula gave the right
answer, which it would have done just as happily at a length that proved
nothing. The rival is now a function —
`mctp_packets_subtract_header()` — the separation is computed, and 177 is pinned
as a length that must **not** discriminate.

The smallest lengths that do separate them are 60 to 63; the next are 119 to
126; and every message above about a kilobyte separates them by a widening
margin. All of those are in the calibration set of §2.4, and 177 stays in it as
the control.

### ② The message-type byte is not per packet

It appears once, in the first packet. A 63-byte SPDM message is one packet
(63 + 1 = 64 exactly); a 64-byte one is two.

### ③ What is being split is the whole message, not the signature field

A `MEASUREMENTS` response is a header, a block count, the measurement records, a
**32-byte nonce**, an opaque-data length, the opaque data, and *then* the
signature. Dividing a signature length from FIPS 204 by an MTU answers a
question nobody asked. Every length in this repository comes off the wire:
P2's `MEASUREMENTS` is 3,807 bytes, of which 3,309 is the signature.

### ④ And on 2026-09-18 the formula stopped being arithmetic

The three ways above are ways of being wrong on paper. Being right on paper is
not the same as being right, so the formula was put on a real link and asked.

`transport/mctp_bridge --role replay` sends messages of stated lengths across a
kernel MCTP link; `--role sink` at the other end acks with the number of bytes
it reassembled; `harness/mctp_capture.py` counts the packets between them off an
`AF_PACKET` socket. The lengths are not a sweep — each one is a boundary the
candidate formulas disagree about.

<!-- capture: bench/data/w9-afmctp-20260917T194210Z/replay.link.pcap -->

| message bytes | packets observed | `ceil((L+1)/64)` | `ceil(L/59)`, the wrong one | separates? |
| ------------: | ---------------: | ---------------: | --------------------------: | :--------- |
| 1 | **1** | 1 | 1 | no |
| 60 | **1** | 1 | 2 | ★ yes |
| 63 | **1** | 1 | 2 | ★ yes |
| 64 | **2** | 2 | 2 | no — a boundary, not a test |
| 65 | **2** | 2 | 2 | no |
| 119 | **2** | 2 | 3 | ★ yes |
| 127 | **2** | 2 | 3 | ★ yes |
| 128 | **3** | 3 | 3 | no |
| 177 | **3** | 3 | 3 | no — see §2① |
| 1,024 | **17** | 17 | 18 | ★ yes |
| 4,352 | **69** | 69 | 74 | ★ yes |
| **16,853** | **264** | **264** | 286 | ★ yes |

**Seven of the twelve are lengths at which the two formulas disagree, and the
subtract-the-header version is wrong at every one of them.** That sentence is
what the table is for; a column of ticks at lengths where both candidates agree
would have looked identical and shown nothing, which is exactly what §2① had
been publishing. `--observed` now prints the rival's answer beside the model's
and marks the separating rows, so a capture that discriminates nothing says so.

The 16,853-byte row is the post-quantum certificate chain of week eight, so the
headline number is a measurement of the real thing rather than of a round number
near it. 177 is kept as the control: it must reproduce, and it must not
discriminate.

Three further things hold, and each is a separate way the table could have been
wrong:

- **The sink reassembled every message to exactly the length that was sent.** A
  packet count with a broken reassembly underneath it would still look like a
  packet count.
- **`tx_dropped` and `rx_errors` were zero**, read from
  `/sys/class/net/<if>/statistics` before and after each capture, and the two
  interfaces' counters are each other's mirror: over the whole run one end
  transmitted 405 and received 1,050 while the other transmitted 1,050 and
  received 405. A pty pair has no flow control worth the name, so this is
  checked rather than assumed.
- **The capture reports its own losses, and refuses itself if it had any.** Two
  runs of this experiment on 2026-09-18 returned different numbers, for two
  different reasons and neither of them the link: an `AF_PACKET` socket that
  dropped 33 packets under the burst, and a capture that began two thirds of the
  way through because a `sleep` was standing in for a synchronisation. Both are
  now detected — the socket's own `PACKET_STATISTICS` drop counter is read and a
  non-zero value fails the capture, and the capture creates a readiness file
  that the traffic generator blocks on. `docs/roadmap.md` standing rule 13
  applies: the two faults are caught by *different* checks, because the
  interface-counter comparison cannot see a late start and the reassembly check
  cannot see a uniform loss.
- **Every packet but the last of each message carries exactly 64 payload bytes.**
  The arithmetic would work out the same if the sender were under-filling and
  the count happened to match; `--observed` reports any short interior packet
  separately for that reason.

What this does *not* license is the other MTUs. `mctp-serial` fixes its
transmission unit — `drivers/net/mctp/mctp-serial.c` sets `ndev->mtu`,
`max_mtu` and `min_mtu` all to `MCTP_SERIAL_MTU`, 68, described in the source as
"base mtu (64) + mctp header" — so 64 payload bytes is the only value reachable
on this binding. It happens to be the only value DSP0236 guarantees is routable,
which is why it is the one worth having; 128 and 256 remain **computed**.

---

## 3. The chunking formula, and why it is not marked computed

```
chunks(L, DTS) = 0                                        if L <= DTS
               = 1 + ceil( (L - (DTS-16)) / (DTS-12) )    otherwise
```

The 16 and the 12 are `CHUNK_RESPONSE`'s own header, from DSP0274's field
layout: 12 bytes of `SPDMVersion`, code, attributes, handle, `ChunkSeqNo`,
reserved and `ChunkSize`, plus a 4-byte `LargeMessageSize` **in the first chunk
only**. Same shape as the MCTP `+1`, for the same reason.

The offsets were checked against the captures before being relied on: in
`P2-all.pcap` the first `CHUNK_RESPONSE` is 4,352 SPDM bytes with `ChunkSize`
0x10f0 = 4,336, and 4,352 − 4,336 = 16; the second is 4,352 with `ChunkSize`
0x10f4 = 4,340, and the difference is 12.

<!-- capture: bench/data/w8-pqc-matrix-20260914T131557Z/P2-all.decode.txt -->
**`L` is not computed either.** The first chunk of a sequence carries
`LargeMessageSize`, which is the length of the message being delivered, and in
this capture it is
<!--claim chunking.large_msg_size=16869-->16,869 bytes — the 16,853-byte
certificate chain plus `CERTIFICATE`'s own 16-byte large-form header. The
DataTransferSize it is being split against is
<!--claim capabilities.responder.data_transfer_size=4608-->4,608. So both inputs
to the formula come off the wire and neither is a spec value.

**This formula is validated against measurement, which is why its outputs are
not labelled computed.** `bench/data/w8-dts-sweep-*` varies the negotiated
DataTransferSize over six values on one build — 1,024 to 32,768, a 32× range —
and counts what actually happened:

```
$ python3 bench/exp04_fragmentation.py --validate bench/data/w8-dts-sweep-*

  arm               DTS  measured   model  verdict
  A0-dts1024       1024         6       6  ok
  A0-dts2048       2048         0       0  ok
  A0-dts4608       4608         0       0  ok
  A0-dts8192       8192         0       0  ok
  A0-dts16384     16384         0       0  ok
  A0-dts32768     32768         0       0  ok
  P2-dts1024       1024        59      59  ok
  P2-dts2048       2048        31      31  ok
  P2-dts4608       4608        12      12  ok
  P2-dts8192       8192         9       9  ok
  P2-dts16384     16384         6       6  ok
  P2-dts32768     32768         0       0  ok

  the model reproduces every measured chunk round-trip count, over a 32x range
  of DataTransferSize (1024 to 32768 bytes)
```

Two details make that a validation rather than a fit.

- **The model is applied to the logical messages, not the chunks.** Feeding it
  the `CHUNK_RESPONSE` lengths would be feeding it its own answer — they are
  4,352 bytes each *because* DataTransferSize made them so. It is applied to the
  unchunked messages at their own lengths and to the chunked ones at the length
  `bench/pcapstat.py` reassembled them to.
- **Twelve points over a 32× range.** A model that agreed at one DataTransferSize
  would be a coincidence. One that agrees at six, on two algorithm sets, while
  the answer moves from 0 to 59, is a model.

And the model is what makes values outside the sweep sayable. `--validate` covers
1,024 to 32,768; a real MCTP-over-SMBus device might advertise the SPDM 1.2
minimum of 42, or 256, and the formula extends there **without another build** —
labelled as extension, not as measurement.

---

## 3a. The two arms, over the link

The calibration says the formula is right. These are what it is right about.
Both arms are the `-all` arms of `harness/lib/arms.sh`, the same controlled
flags the socket-line captures were taken with, run inside the guest by
`harness/run_afmctp.sh`.

<!-- capture: bench/data/w9-afmctp-20260917T194210Z/P2.link.pcap -->

| | A0 classical | P2 post-quantum | ratio |
| --- | ---: | ---: | ---: |
| SPDM messages | 22 | 46 | 2.09x |
| SPDM bytes | 6,449 | 58,736 | 9.11x |
| **MCTP packets, observed** | **115** | **953** | **8.29x** |
| MCTP header bytes | 460 | 3,812 | 8.29x |
| bytes on the wire | 6,931 | 62,594 | 9.03x |
| framing as a share of the wire | 7.0% | 6.2% | |

★ **The packet ratio is smaller than the byte ratio, and that is the transport
result.** Post-quantum costs 9.11 times the bytes and 8.29 times the packets,
because a transmission unit is charged whole: the classical arm has more short
messages, and a four-byte `GET_DIGESTS` occupies one 68-byte packet exactly as a
64-byte one does. Framing is 7.0% of the classical arm's wire bytes and 6.2% of
the post-quantum arm's — **the larger messages amortise the header better**.

That is not a defence of post-quantum. It is a statement about which of two
costs a reader should quote: on a bus where the per-packet cost dominates — and
on SMBus at 100 kHz it does — the ratio that matters is 8.29 and not 9.11, and
nothing in a capture taken over a TCP socket can tell you that.

**The control is what makes the comparison legitimate.** Each arm was recorded
twice, by two programs that share no code: `spdm_requester_emu`'s own `--pcap`,
one record per SPDM message, and `harness/mctp_capture.py`, one record per MCTP
packet. The first is byte-for-byte comparable with the socket-line captures of
week eight, and it matches them exactly — 22 records and 6,559 bytes for A0, 46
and 58,966 for P2, in the same per-message length sequence. **The transport
changed nothing about the protocol.** The second reconciles with the first
through the framing that is known to sit between them, `6,449 + 5 x 22 = 6,559`,
which `harness/run_afmctp.sh` asserts on every run rather than leaving to a
reader.

---

## 4. Which view each layer operates on

Subtle, and easy to get backwards.

- **Chunking** operates on the **logical** message. A 16,869-byte `CERTIFICATE`
  response is what SPDM was asked to deliver, and chunking is how it did.
- **MCTP packetisation** operates on the **wire** message. When SPDM chunks, what
  it hands the transport is each `CHUNK_RESPONSE` separately — so MCTP
  packetises four 4,352-byte messages, not one 16,869-byte one.

`bench/exp04_fragmentation.py` therefore counts MCTP packets from the wire view
and models chunk round trips from the logical view, and says so in the code where
the choice is made. Estimating MCTP packets from a reassembled length would skip
a whole layer and undercount; modelling chunks from the chunk lengths would
assume the answer.

An illustration, `P2-all.pcap` at `--mtu 64`:

```bash
python3 bench/exp04_fragmentation.py \
    bench/data/w8-pqc-matrix-*/P2-all.pcap --mtu 64 128 256
```

The five largest messages are the four `CHUNK_RESPONSE` of each chain fetch, at
4,352 bytes each, which at MTU 64 is 69 packets apiece — **computed**. The same
capture's 12 chunk round trips are **measured**.

---

## 5. What this does not say

- ~~**No packet count here has been observed.**~~ Struck on 2026-09-18, and
  left visible rather than deleted: what a document used to claim is part of
  what it is worth. The counts at a 64-byte transmission unit are observed on a
  real `mctp-serial` link (§2.4, §3a). Counts at any other transmission unit
  are still computed and still labelled.
- **The link was a pty pair inside a virtual machine, not hardware.** The MCTP
  stack, the routing, the tag allocation and the packetisation are the Linux
  kernel's and are real. The medium is not: there is no bus arbitration, no
  clock, no electrical error, and `mctp-serial` frames with DSP0253 byte
  stuffing rather than with SMBus or ASTLPC framing. So the packet *counts*
  transfer to real hardware and the *timings* do not, which is why this document
  reports no timings.
- **The MTUs other than 64 are hypotheses.** 64 is DSP0236's baseline, the only
  guaranteed value, and now the measured one; 128 and 256 are plausible
  negotiated ones. A real binding's MTU is a property of that binding, and the
  tool takes it as an argument for that reason.
- **The EIDs were assigned statically.** `mctpd` was built and not run: its job
  is discovery over the MCTP control protocol, and discovery traffic on the link
  would be traffic in the capture. So the endpoint IDs, routes and tags are real
  and were not negotiated.
- **Per-packet cost is counted as four header bytes and nothing else.** A real
  binding adds its own framing — SMBus a PEC byte and an address, ASTLPC a KCS
  handshake — and those are binding-specific and not modelled.
- **No time.** A round trip is counted, never timed. Turning round trips into
  milliseconds needs a bus RTT, and this project has not measured one.

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
| **status in this repository** | **MEASURED, and modelled, and the model validated** | **COMPUTED** |

That last row is the point of this document.

---

## 1. Why one is measured and the other is not

Every capture here is MCTP-*framed* over a TCP socket: `spdm-emu`'s socket
transport prepends the four-byte MCTP transport header and the message-type byte
and then hands the whole SPDM message to TCP, which never packetises it at 64
bytes. So the message-type byte and the framing are real and present in every
capture — `bench/pcapstat.py` accounts for exactly five bytes per packet — and
the *packetisation* has never happened.

Linux `AF_MCTP` would do it. This development machine's kernel is built without
`CONFIG_MCTP`:

```
$ zcat /proc/config.gz | grep CONFIG_MCTP
# CONFIG_MCTP is not set
```

and there is no `qemu-system-x86_64` installed either. Both are recorded in
[`env-baseline.md`](env-baseline.md) and both are Gate 5's problem, not this
document's. Until one of them works, **every MCTP packet count in this
repository is arithmetic on a measured message length**, and
`docs/roadmap.md` standing rule 4 requires that to be visible at the figure
rather than in a footnote. `bench/exp04_fragmentation.py` prints `[computed]`
beside each one.

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

`bench/exp04_fragmentation.py --selftest` contains the case that separates the
two formulas rather than one they agree on: a 177-byte message at MTU 64 is
**3** packets (`ceil(178/64)`), and the subtract-the-header version says 4
(`ceil(177/59)`). A test at, say, 64 bytes would have passed under both.

### ② The message-type byte is not per packet

It appears once, in the first packet. A 63-byte SPDM message is one packet
(63 + 1 = 64 exactly); a 64-byte one is two.

### ③ What is being split is the whole message, not the signature field

A `MEASUREMENTS` response is a header, a block count, the measurement records, a
**32-byte nonce**, an opaque-data length, the opaque data, and *then* the
signature. Dividing a signature length from FIPS 204 by an MTU answers a
question nobody asked. Every length in this repository comes off the wire:
P2's `MEASUREMENTS` is 3,807 bytes, of which 3,309 is the signature.

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

- **No packet count here has been observed.** §1.
- **The MTUs are hypotheses.** 64 is DSP0236's baseline and the only guaranteed
  value; 128 and 256 are plausible negotiated ones. A real binding's MTU is a
  property of that binding, and the tool takes it as an argument for that reason.
- **Per-packet cost is counted as four header bytes and nothing else.** A real
  binding adds its own framing — SMBus a PEC byte and an address, ASTLPC a KCS
  handshake — and those are binding-specific and not modelled.
- **No time.** A round trip is counted, never timed. Turning round trips into
  milliseconds needs a bus RTT, and this project has not measured one.

# What `--trans MCTP` actually is

`spdm-emu` takes a `--trans MCTP` flag, and the captures in `bench/data/` are
written with pcap link type 291, which is `LINKTYPE_MCTP`. Both are true and
neither means what they appear to mean.

> **`--trans MCTP` selects an encoding, not a network.** It says "wrap the SPDM
> message the way MCTP would", and then sends the result down an ordinary
> **TCP socket on localhost**. There is no MCTP network anywhere in this
> project's main line: no endpoint IDs, no routing, no fragmentation, no
> physical medium. It has nothing to do with Linux's `AF_MCTP` socket family or
> with `mctpd`.

That is worth establishing precisely, because the natural next thought — "then
I will just point it at a real MCTP interface" — sends you looking for a flag
that does not exist. The place to find that out is the source, and it takes ten
minutes. Rebuilding to test the theory takes forty.

## Three layers, and only one of them is in the capture

```
  ┌──────────────────────────────────────────────────────────────┐
  │  SPDM message            GET_VERSION, CHALLENGE, ...          │  ← §1 of
  │  little-endian fields                                         │    the walkthrough
  ├──────────────────────────────────────────────────────────────┤
  │  MCTP framing            message type 0x05 + a 4-byte header  │  ← in the pcap
  ├──────────────────────────────────────────────────────────────┤
  │  socket framing          12 bytes, BIG-endian                 │  ← NOT in the pcap
  │  TCP to 127.0.0.1:2323                                        │
  └──────────────────────────────────────────────────────────────┘
```

### The socket framing — `spdm_emu_common/command.c`

```c
bool send_platform_data(const SOCKET socket, uint32_t command,
                        const uint8_t *send_buffer, size_t bytes_to_send)
{
    write_data32(socket, command);                 /* 4 bytes */
    write_data32(socket, m_use_transport_layer);   /* 4 bytes */
    write_multiple_bytes(socket, send_buffer, bytes_to_send);  /* 4-byte length + payload */
```

Twelve bytes ahead of every message, and `command.h` states their byte order:

```c
/* Client->Server/Server->Client
 *   command/response: 4 bytes (big endian)
 *   transport_type: 4 bytes (big endian)
 *   PayloadSize (excluding command and PayloadSize): 4 bytes (big endian)
 *   payload (SPDM message, starting from SPDM_HEADER): PayloadSize (little endian)*/

#define DEFAULT_SPDM_PLATFORM_PORT 2323
#define TCP_SPDM_PLATFORM_PORT     4194

#define SOCKET_TRANSPORT_TYPE_NONE    0x00
#define SOCKET_TRANSPORT_TYPE_MCTP    0x01
#define SOCKET_TRANSPORT_TYPE_PCI_DOE 0x02
#define SOCKET_TRANSPORT_TYPE_TCP     0x03
```

**A big-endian header wrapping a little-endian payload, in one connection.** Not
a mistake — the framing is a network protocol and the payload is a
memory-layout-defined structure — but it is exactly the situation where a
program that assumes one byte order throughout works on the machine it was
written on and fails elsewhere. It is also why `c-drills/d5` is an endianness
drill.

### The MCTP framing — synthesised for the capture, not received from anything

`send_platform_data` builds a four-byte MCTP header **purely so the pcap has
one**:

```c
case SOCKET_SPDM_COMMAND_NORMAL:
    if (m_use_transport_layer == SOCKET_TRANSPORT_TYPE_MCTP) {
        /* Append mctp_header_t for PCAP*/
        mctp_header_t mctp_header;
        mctp_header.header_version = 0;
        mctp_header.destination_id = 0;
        mctp_header.source_id      = 0;
        mctp_header.message_tag    = 0xC0;
        append_pcap_packet_data(&mctp_header, sizeof(mctp_header),
                                send_buffer, bytes_to_send);
```

Those four bytes are the first four of every record in every capture this
project has taken. Record 1 of `w2-baseline`'s `walkthrough.pcap`:

```
00 00 00 c0  05  10 84 00 00
```

Read them against `mctp_header_t` and the emulation's boundaries are legible in
the bytes themselves:

| byte | field | value | what it says |
|--:|---|---|---|
| 0 | `header_version` | `0x00` | |
| 1 | `destination_id` | `0x00` | **no endpoint ID** — a real MCTP network assigns these |
| 2 | `source_id` | `0x00` | likewise |
| 3 | `message_tag` | `0xC0` | bits 7 and 6 set: `start_of_message` **and** `end_of_message` |
| 4 | MCTP message type | `0x05` | SPDM (from `mctp.h`) |
| 5… | SPDM message | | |

**Byte 3 is the interesting one.** `0xC0` marks every message as both the first
and the last packet of itself, with `packet_sequence_number` zero. On real MCTP
hardware a message larger than the negotiated transmission unit — 64 bytes is
the baseline — must be split across several packets carrying sequence numbers,
with `start_of_message` on the first and `end_of_message` on the last. In these
captures **nothing is ever split**, including the 16,853-byte post-quantum
certificate chain of the walkthrough's §9.3.

So the fragmentation that a real transport would perform is not merely absent
from the capture. It is asserted not to have happened, in a field, on every
message.

## What that means this project has and has not exercised

| | in the main line | where it would come from |
|---|---|---|
| SPDM message flow and field encoding | **yes** | this is what the captures hold |
| SPDM-layer chunking (`CHUNK_GET`) | **yes** — 4 round trips in the post-quantum arm | triggered by `DataTransferSize` |
| MCTP message-type framing | as a synthesised header only | |
| MCTP endpoint IDs, discovery, routing | **no** | `mctpd`, or a real fabric |
| MCTP packet fragmentation and reassembly | **no** — see `0xC0` above | a real transmission unit |
| Physical medium (I²C/SMBus, PCIe VDM, serial) | **no** | hardware, or QEMU |
| MCTP control protocol | **no** | |

**SPDM chunking and MCTP fragmentation are different mechanisms at different
layers, and this project exercises exactly one of them.** SPDM chunking is
negotiated through `CHUNK_CAP` and bounded by `DataTransferSize`, which the
post-quantum capture crosses. MCTP fragmentation is bounded by the transmission
unit of the physical link and is not reached here at all. A statement like "the
post-quantum certificate had to be split up" is true of the first and says
nothing about the second — and on a real BMC talking to an ERoT over I²C, the
second is where a 16 KB chain is actually felt.

This is what Gate 5 exists to close, and it is why the scope note in `README.md`
says everything is emulator-based unless a result says otherwise.

## Getting to a real transport, and what each route costs

| route | what it adds | blocked by |
|---|---|---|
| `AF_MCTP` + `mctpd` over a virtual link | real EIDs, real routing, real fragmentation | this kernel has no `CONFIG_MCTP` (`docs/env-baseline.md`) |
| QEMU with an SPDM-capable device | a real PCIe DOE path | `qemu-system-x86_64` not installed, and the build needs `spdm_port` |
| `--trans PCI_DOE` | a second *encoding*, still over the same socket | nothing — but it does not add a network either |

The third is worth naming because it is the trap in miniature: changing
`--trans` changes how the message is wrapped and nothing about how it travels.
The transport in `--trans` and the transport in "real transport" are two senses
of one word.

## How this was established

Read in this order, and each step was cheap enough to do before forming the next
hypothesis:

1. `spdm_emu/spdm_emu_common/command.h` — the port numbers, the transport-type
   constants, and the byte-order comment. Ten minutes, and it is decisive: a
   header that defines `SOCKET_TRANSPORT_TYPE_MCTP` as a value in a framing
   protocol is not describing a network stack.
2. `spdm_emu/spdm_emu_common/command.c`, `send_platform_data` — confirms the
   twelve bytes are written as three `uint32_t`s, and that the MCTP header is
   constructed only to be handed to the pcap writer.
3. `spdm_emu/spdm_emu_common/pcap.c` — `LINKTYPE_MCTP` (291) is chosen by
   `--trans`, and the per-record data is exactly `mctp_header + SPDM message`.
4. The bytes of an actual capture, which is what turned "no fragmentation" from
   an inference into `0xC0`.

Steps 1 to 3 are reading. Step 4 is the one that made the claim checkable, and
it is the order the evidence should always end in.

---

*Verified against `spdm-emu` 4.0.0-rc (`third_party/spdm-emu-pqc.pin`) and the
captures in `bench/data/w2-baseline-20260828T110130Z/`. The socket framing was
read from source and is **not** observed on the wire here — nothing in this
repository captures the TCP stream itself, only what the emulator writes to the
pcap. If that ever matters, it is one `tcpdump -i lo port 2323` away.*

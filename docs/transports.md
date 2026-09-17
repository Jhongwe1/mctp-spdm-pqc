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

> 🔴 **The last line of that comment is wrong for the default transport, and
> this document quoted it without saying so until 2026-09-10.** For
> `SOCKET_TRANSPORT_TYPE_MCTP` the payload is what libspdm's MCTP transport
> encoded, so it begins with the MCTP **message-type byte** and the SPDM header
> starts at `payload[1]`. The comment is accurate only for
> `SOCKET_TRANSPORT_TYPE_NONE`, which is not the default.
>
> The refutation is four paragraphs below, in this same section: every pcap
> record starts `00 00 00 c0 05 10 84 …`, and the `05` is that byte. So the
> repository has been carrying the evidence against the sentence it quoted,
> next to the sentence, for a month.
>
> It cost about ten minutes while writing `harness/tamper_proxy.py`, which
> reads `payload[1]` and `payload[2]`; a reader who trusts the comment reads
> `payload[0]` and `payload[1]`, gets `0x05` and `0x10`, and is one byte out on
> every field in the message. Filed as upstream candidate five —
> [`docs/upstream/README.md`](upstream/README.md) — as two lines of comment.

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

This is what Gate 5 existed to close, and on 2026-09-18 it did: the next section
is two more routes, one of which packetises for real. **Everything above this
line still describes route** ①, which is where the tamper cases, the RATS
pipeline and the post-quantum cost tables were measured and where they stay.

## Three routes, and what each one exercised

Everything above describes route ①, which is the line every capture from weeks
one to eight was taken on. On 2026-09-18 two more were built. Each cell below
says whether the thing in that row was *exercised* on that route — not whether
it exists.

| | ① spdm-emu socket | ② QEMU NVMe, PCIe DOE | ③ Linux `AF_MCTP` |
| --- | :---: | :---: | :---: |
| SPDM message flow and field encoding | **yes**, all seven pairs | one message pair | **yes**, all seven pairs |
| A complete handshake end to end | **yes** | no — `GET_VERSION` only | **yes**, both arms |
| Transport-layer *encoding* | yes | yes | yes |
| A transport the OS enumerated | no | **yes** — `lspci` sees the device | **yes** — a netdev with an MTU |
| Endpoint addressing | no — the EID fields are zero | n/a for DOE | **yes** — EID 8 and EID 9 |
| Routing | no | n/a | **yes** — a route table per namespace |
| Tag allocation / request-response pairing | no — the tag byte is a constant | n/a | **yes** — the kernel allocates |
| **Packetisation and reassembly** | **no** — SOM and EOM on every message | no — one object, no fragmentation | **YES — measured, §"Route ③"** |
| Register-level device access | no | **yes** — config space, a mailbox | no |
| Physical medium | no | no — the mailbox is QEMU's | no — a pty pair, not a bus |
| Runs with only packaged software | yes | no — needs QEMU >= 9.1 built | yes — the distribution's QEMU |

`--trans PCI_DOE` on route ① is worth naming because it is the trap in
miniature: changing `--trans` changes how the message is wrapped and nothing
about how it travels. The transport in `--trans` and the transport in "real
transport" are two senses of one word — and route ② is what the second sense
looks like.

### What both new routes have underneath them

A guest, because the host cannot host either one. Its kernel has `CONFIG_MCTP`
and this one does not; it can be given a PCIe device with a DOE capability and
this one has none.

The guest is not a distribution image and there is no root filesystem to build:
**its root is the host's own, exported over virtio-9p and mounted read-only**,
so the `spdm_requester_emu` and `spdm_responder_emu` built in week one run
inside it unchanged, from the same paths, against the same certificates. That
is the whole reason this was affordable. The kernel is built by
`harness/build_guest_kernel.sh` with everything needed compiled in and no
initramfs — 9p has to work before any userspace exists — and
`third_party/linux.pin` records its version and the SHA-256 of the source
tarball, the config and the image.

Why a guest rather than a new host kernel is
[ADR 0010](decisions/0010-a-kernel-the-host-does-not-have.md): `host_kernel` is
in every manifest in `bench/data/`, and rebuilding the host kernel would have
made every one of those lines name a kernel that no longer exists.

---

## Route ② — a real PCIe DOE mailbox

```text
  spdm_responder_emu --trans PCI_DOE            (host)
           ^  TCP 127.0.0.1:2323, the same twelve-byte socket protocol
           |
      qemu-system-x86_64 -device nvme,...,spdm_port=2323
           |  a DOE extended capability in the guest's config space
           v
      transport/doe_probe --device 0000:00:03.0   (guest, userspace)
```

QEMU's NVMe model registers two DOE protocols and forwards both to the SPDM
socket, so **the responder at the far end is the same emulator every other
capture in this repository was taken against** — `hw/nvme/ctrl.c`:

```c
static DOEProtocol doe_spdm_prot[] = {
    { PCI_VENDOR_ID_PCI_SIG, PCI_SIG_DOE_CMA,         pcie_doe_spdm_rsp },
    { PCI_VENDOR_ID_PCI_SIG, PCI_SIG_DOE_SECURED_CMA, pcie_doe_spdm_rsp },
};
```

**The guest enumerates the capability out of config space.** `lspci -vvv`, in
the guest, on a device the kernel has bound its ordinary NVMe driver to:

<!-- capture: bench/data/w9-doe-20260917T193247Z/lspci-vvv.txt -->

```text
Capabilities: [100 v1] Data Object Exchange
        DOECap: IntSup+
                Interrupt Message Number 000
        DOECtl: IntEn-
        DOESta: Busy- IntSta- Error- ObjectReady-
Kernel driver in use: nvme
```

That line is the demo, and on its own it proves only that QEMU wrote a
capability header. So `transport/doe_probe` drives the mailbox — DWORD writes to
the write mailbox, `GO` in the control register, a poll of `DATA OBJECT READY`,
and a read mailbox that has to be *popped* by writing back to it — and asks two
questions.

**DOE Discovery**, protocol zero, which answers entirely inside QEMU and so
separates "the mailbox is wrong" from "the socket is wrong":

<!-- capture: bench/data/w9-doe-20260917T193247Z/doe-discovery.txt -->

```text
  index 0   vendor 0x0001  protocol 0x00  (Discovery)
  index 1   vendor 0x0001  protocol 0x01  (CMA-SPDM)
  index 2   vendor 0x0001  protocol 0x02  (Secured CMA-SPDM)
```

**And then one SPDM message.** `GET_VERSION` is four bytes, carries no state,
and has a fixed-format reply, so a correct answer cannot be explained away as a
missing transcript:

<!-- capture: bench/data/w9-doe-20260917T193247Z/doe-spdm.txt -->

```text
  request payload (4 bytes)
    0000  10 84 00 00
  response payload (16 bytes)
    0000  10 04 00 00 00 05 00 10 00 11 00 12 00 13 00 14
  ★ VERSION: SPDMVersion 0x10, code 0x04, 5 entries
     versions advertised: 1.0 1.1 1.2 1.3 1.4
```

Five versions, which is what libspdm 4.0.0-rc supports, arriving through config
space rather than through a socket.

**Why userspace.** Linux 6.12 has no in-kernel CMA-SPDM requester, so nothing in
the guest drives this mailbox on its own. Writing the requester was the only way
to make the path carry anything, and it has a second advantage: with no driver
bound to the mailbox there is nobody to race with.

> ### What route ② does not claim
>
> * **The mailbox is emulated.** It is QEMU's, not silicon's. The register
>   protocol is real; the timing means nothing, which is why none is reported.
> * **One message is not a handshake.** State machines, transcripts and
>   signatures live in libspdm and are exercised on routes ① and ③.
> * **No certificate was checked.** The PCIe r6.1 §6.31.3 requirement that a
>   leaf certificate carry an `otherName` of OID `2.23.147` binding it to a
>   device's vendor, device, class and subsystem IDs is a *requester*-side
>   check, and there is no requester here that performs it. This project has not
>   exercised it and does not claim to have.

★ **One correction worth carrying.** The widely repeated invocation for this
feature, including in this project's own week-nine plan, is
`-device nvme,...,spdm_port=2323,spdm_trans=doe`. There is no `spdm_trans`
property on the nvme device in QEMU 9.2 — the transport is implied — and an
unknown property is a realize-time error, which is a confusing way to learn a
version number. `harness/run_doe.sh` therefore checks `-device nvme,help` rather
than the version string, which is the same discipline this repository applies to
every other flag.

---

## Route ③ — a real MCTP network

```text
  netns A                                        netns B
  spdm_requester_emu  --TCP 127.0.0.1:2323-->    <--TCP 127.0.0.1:2323--  spdm_responder_emu
    transport/mctp_bridge  ==== mctpserial0 ====  transport/mctp_bridge
    EID 8                  a real MCTP link            EID 9
                           mtu 68 = 64 + header
```

Two ptys wired together by `socat`, each attached to the kernel's MCTP serial
line discipline, one in each of two network namespaces. Neither emulator is
modified and neither knows: `transport/mctp_bridge` speaks spdm-emu's
twelve-byte socket protocol on one side and `AF_MCTP` on the other.

**Two network namespaces, not one.** A socket bound to `MCTP_ADDR_ANY` matches
any EID local to its namespace, so with both ends in one namespace the
requester's and the responder's sockets would both be candidates for every
inbound message. Separate namespaces also give each side its own loopback, which
is why both emulators can use port 2323.

### Two things that had to be read out of the kernel

**① The message-type byte is not in the buffer.** `net/mctp/af_mctp.c`:

```c
skb_reserve(skb, hlen);
/* set type as fist byte in payload */
*(u8 *)skb_put(skb, 1) = addr->smctp_type;
rc = memcpy_from_msg((void *)skb_put(skb, len), msg, len);
```

The kernel writes the type byte itself, out of `smctp_type`; what you pass to
`send()` is the body after it, and `mctp_recvmsg` is the mirror image. But
spdm-emu's MCTP socket payload *starts* with that byte — its first octet is
`0x05`, which is the fact established at the top of this document. So the bridge
strips one byte outbound and restores one inbound. **This is the same off-by-one
recorded as upstream candidate five, seen from the other side**: there, a reader
who trusts `command.h` reads the SPDM header one byte early; here, a bridge that
forwards the buffer unchanged sends a message whose `SPDMVersion` lands in the
request-code field, and the handshake fails looking like a protocol error rather
than like a bug in the plumbing.

**② The interface is registered in the initial namespace, whatever namespace
attaches the line discipline.** `drivers/net/mctp/mctp-serial.c`:

```c
ndev = alloc_netdev(sizeof(*dev), name, NET_NAME_ENUM, mctp_serial_setup);
...
rc = register_netdev(ndev);
```

There is no `dev_net_set()` between those two lines. The first version of
`harness/run_afmctp.sh` ran `mctp link serial` inside each namespace, the
obvious way, and no interface ever appeared — in either namespace, with no error
from any command. `mctp_serial_setup` does not set `NETIF_F_NETNS_LOCAL`, so the
fix is to create both in the initial namespace and hand each to the namespace it
belongs in with `ip link set <dev> netns`.

### The transmission unit is not a free variable

```c
/* we limit at the fixed MTU, which is also the MCTP-standard
 * baseline MTU, so is also our minimum
 */
ndev->mtu = MCTP_SERIAL_MTU;      /* 68 = 64 payload + 4 header */
ndev->max_mtu = MCTP_SERIAL_MTU;
ndev->min_mtu = MCTP_SERIAL_MTU;
```

So 64 payload bytes per packet and no other value is reachable on this binding.
That is not a limitation of the experiment: 64 is DSP0236's baseline and the
only value guaranteed routable, so it is the one worth having. Counts at other
transmission units stay **computed** and stay labelled, and
`harness/run_afmctp.sh` reads the MTU back off the interface rather than
assuming it.

### What it measured

<!-- capture: bench/data/w9-afmctp-20260917T194210Z/P2.link.pcap -->

| | A0 classical | P2 post-quantum | ratio |
| --- | ---: | ---: | ---: |
| SPDM messages | 22 | 46 | 2.09x |
| SPDM bytes | 6,449 | 58,736 | 9.11x |
| **MCTP packets, observed** | **115** | **953** | **8.29x** |
| MCTP header bytes on the wire | 460 | 3,812 | 8.29x |
| framing as a share of the wire | 7.0% | 6.2% | |

★ **The packet ratio is smaller than the byte ratio**, because a transmission
unit is charged whole and the classical arm has more short messages. The full
argument, the calibration that separates the right formula from the plausible
wrong one, and what none of it licenses, are in
[`fragmentation.md`](fragmentation.md) §2.4 and §3a.

**The control.** Each arm was recorded twice, by two programs that share no
code: the requester's own `--pcap`, one record per SPDM message, and
`harness/mctp_capture.py`, one record per MCTP packet. The first is
byte-for-byte comparable with week eight's socket-line captures and matches them
exactly — 22 records and 6,559 bytes for A0, 46 and 58,966 for P2, in the same
per-message length sequence. **The transport changed nothing about the
protocol.** The second reconciles with the first through the framing known to
sit between them, `6,449 + 5 x 22 = 6,559`, which the harness asserts on every
run.

> ### What route ③ does not claim
>
> * **The medium is a pty pair, not a bus.** The MCTP stack, the routing, the
>   tags and the packetisation are the Linux kernel's and are real. There is no
>   arbitration, no clock and no electrical error, and `mctp-serial` frames with
>   DSP0253 byte stuffing rather than with SMBus or ASTLPC framing. Packet
>   *counts* transfer to hardware; *timings* do not, so none are reported.
> * **The endpoint IDs were assigned statically.** `mctpd` is built and not run:
>   its job is discovery over the MCTP control protocol, and discovery traffic
>   on the link would be traffic in the capture. The EIDs, routes and tags are
>   real and were not negotiated.
> * **The emulators were bridged, not ported.** Nothing here is a libspdm
>   transport binding. What crossed the link is exactly the MCTP-encoded SPDM
>   messages libspdm produced, which is what makes the capture comparable — but
>   a device shipping this would register its own send/receive callbacks
>   instead.

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

*Verified against `spdm-emu` 4.0.0-rc (`third_party/spdm-emu-pqc.pin`), first
against the captures in `bench/data/w2-baseline-20260828T110130Z/` and since
2026-09-01 against `bench/data/w4-baseline-20260901T054208Z/`, where the same
five bytes of framing per record are what makes `harness/verify_repo.sh`'s
`pcap bytes == SPDM bytes + 5 x messages` cross-check close. The socket framing was
read from source and is **not** observed on the wire here — nothing in this
repository captures the TCP stream itself, only what the emulator writes to the
pcap. If that ever matters, it is one `tcpdump -i lo port 2323` away.*

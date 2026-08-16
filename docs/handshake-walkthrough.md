# The handshake, field by field

Every SPDM message of one complete attestation exchange, read out of a capture
taken by this repository, with the offsets that produced each value.

The point of writing this out is not that the fields are hard to look up. It is
that a message flow you have only read about and a message flow you have taken
apart are different kinds of knowing, and the difference shows up in the
questions each one lets you answer. Most of the entries below therefore carry
three lines that a specification does not: what problem the message solves,
what breaks if it is removed, and what is still unclear.

## The numbers here are not typed in

A document like this is made almost entirely of stated facts, and this project
has twice caught itself getting stated facts wrong — a version number that
contradicted its own build pin, and a security claim carried out of a decision
record without ever being checked. The lesson both times was the same: a fact
that is only ever *stated* has nothing checking it, while a fact that is
*computed* is checked on every run.

So each value below is marked up in the source of this file with a claim
comment, invisible when rendered:

```markdown
<!-- capture: bench/data/<run>/walkthrough.decode.txt -->

| `DataTransferSize` | <!--claim capabilities.requester.data_transfer_size=4608--> 4,608 |
```

`harness/fields.py --check` re-derives every one of them from the decode named
above it. `harness/verify_repo.sh` runs that check, and CI runs
`verify_repo.sh`. A number here that stops matching its capture is a red build,
not something a reader might happen to notice.

```bash
python3 harness/fields.py --check docs/handshake-walkthrough.md
```

A claim whose key is not something the tool computes fails too, so the markup
cannot be satisfied by inventing a field name.

What that mechanism does **not** cover is stated beside it in §10, because a
check that is trusted beyond its reach is worse than no check.

---

<!-- capture: bench/data/w2-baseline-20260816T172221Z/walkthrough.decode.txt -->

## 0. The capture this describes

| | |
|---|---|
| run | `bench/data/w2-baseline-20260816T172221Z/`, arm `walkthrough` |
| build | `spdm-emu` 4.0.0-rc → `libspdm` 4.0.0-rc (`third_party/spdm-emu-pqc.pin`) |
| decoder | `spdm-dump` `9d91f21` (`third_party/spdm-dump.pin`) |
| transport | pcap link type <!--claim transport.pcap_datalink=291--> 291 (MCTP) |
| messages decoded | <!--claim messages.decoded=30--> 30 |
| protocol errors | <!--claim errors.total=0--> 0 |
| decode complete | <!--claim source.decode_truncated=False--> yes |

```bash
./spdm_responder_emu --exe_conn DIGEST,CERT,CHAL,MEAS --exe_session NO_END --meas_op ALL &
./spdm_requester_emu --exe_conn DIGEST,CERT,CHAL,MEAS --exe_session NO_END --meas_op ALL \
                     --pcap walkthrough.pcap
```

**Why this capture and not the default one.** Left at its defaults the same
exchange is 554 packets, of which 526 are one behaviour explained in §7. Thirty
packets is what a person can actually read, and every field below is identical
in both — §9 is the comparison that shows it.

### Where the SPDM message starts in a capture record

Every offset below is relative to the start of the **SPDM message**, and it is
worth being exact about where that is, because it is not the start of the pcap
record. Record 1 of this capture, all nine bytes of it:

```
00 00 00 c0  05  10 84 00 00
^^^^^^^^^^^  ^^  ^^^^^^^^^^^
     |        |   SPDM message: SPDMVersion 0x10, GET_VERSION, Param1, Param2
     |        MCTP message type 5 = SPDM
     4-byte MCTP pseudo-header (pcap link type 291)
```

So **SPDM offset 0 is record offset 5**. `spdm_dump -x` prints the SPDM message
alone, without the five leading bytes, which is what the offsets here match.

Note what is *not* there. `spdm-emu` talks to itself over a TCP socket wrapped
in a 12-byte header of its own, and none of those twelve bytes are in the
capture — the pcap holds MCTP-framed SPDM. That distinction is
[`docs/transports.md`](transports.md), and it matters because the socket header
is big-endian while everything inside it is little-endian.

Three flags were needed to get here, and only one of them is famous:

| flag | default | what the default costs |
|---|---|---|
| `--exe_conn` | 10 operations | log runs to hundreds of lines |
| `--exe_session` | **14 operations** | 1116 packets, 53 s, exit 1 — see `LOG.md`, 2026-08-11 |
| `--meas_op` | `ONE_BY_ONE` | **526 of 554 packets** — see §7 |

---

## 1. `GET_VERSION` (0x84) / `VERSION` (0x04)

### Request — packet 1

| offset | field | size | observed | meaning |
|--:|---|--:|---|---|
| 0 | `SPDMVersion` | 1 | `0x10` | **1.0**, always, see below |
| 1 | `RequestResponseCode` | 1 | `0x84` | `GET_VERSION` |
| 2 | `Param1` | 1 | `0x00` | reserved |
| 3 | `Param2` | 1 | `0x00` | reserved |

### Response — packet 2

| offset | field | size | observed | meaning |
|--:|---|--:|---|---|
| 0 | `SPDMVersion` | 1 | `0x10` | 1.0 |
| 1 | `RequestResponseCode` | 1 | `0x04` | `VERSION` |
| 2–3 | `Param1`, `Param2` | 2 | `0x00` | reserved |
| 4 | `Reserved` | 1 | | |
| 5 | `VersionNumberEntryCount` | 1 | `0x05` | five versions offered |
| 6… | `VersionNumberEntry[]` | 2 each | 1.0, 1.1, 1.2, 1.3, 1.4 | |

Versions offered: <!--claim version.offered_count=5--> **5** — 1.0, 1.1, 1.2,
1.3, 1.4.

**The first observation of the whole exchange is the header byte.** `GET_VERSION`
and `VERSION` both carry <!--claim version.get_version_header=1.0--> **1.0** in
`SPDMVersion`, while every later message in this capture carries
<!--claim version.post_negotiation_header=1.4--> **1.4**. That is not a mistake
in the emulator. It cannot be anything else: version negotiation is the message
that decides which version to speak, so it has to be expressible by a requester
that does not yet know. 1.0 is the fixed entry point, and the header value
changes exactly once, immediately after this exchange.

**What problem it solves.** Two endpoints agreeing which dialect to speak before
anything else is sent.

**What breaks if it is removed.** Nothing about *this* exchange — but its
removal is not the interesting question. The interesting one is what happens if
an attacker rewrites the response to advertise only 1.0. Every endpoint would
fall back to the weakest version both support, and neither would notice. That
is a **downgrade attack**, and the defence is not in this message: it is that
`GET_VERSION`/`VERSION` are folded into the transcript that the `CHALLENGE_AUTH`
signature later covers. A version list that was tampered with produces a
signature that does not verify — one message protecting another, several steps
later. This is the pattern the whole handshake is built out of, and §6 is where
it pays off.

**What I am not sure about.** Whether the version negotiated is the highest
common one, or the highest the *responder* lists that the requester also
supports. This capture cannot tell them apart, because both endpoints are the
same build and offer the same five. §9's `classical-stable` arm offers four and
lands on 1.3, which is consistent with both rules.

---

## 2. `GET_CAPABILITIES` (0xE1) / `CAPABILITIES` (0x61)

Layout is the same in both directions:

| offset | field | size | requester | responder |
|--:|---|--:|---|---|
| 0 | `SPDMVersion` | 1 | `0x14` | `0x14` |
| 1 | `RequestResponseCode` | 1 | `0xE1` | `0x61` |
| 2–3 | `Param1`, `Param2` | 2 | reserved | reserved |
| 4 | `Reserved` | 1 | | |
| 5 | `CTExponent` | 1 | `0x00` | `0x00` |
| 6–7 | `ExtFlags` | 2 | `0x0000` | `0x0000` |
| 8–11 | `Flags` | 4 | `0x8882F7C6` | `0xB99AFBF7` |
| 12–15 | `DataTransferSize` | 4 | `0x00001200` | `0x00001200` |
| 16–19 | `MaxSPDMmsgSize` | 4 | `0x00028000` | `0x00028000` |

- requester `Flags` <!--claim capabilities.requester.flags_raw=0x8882f7c6--> `0x8882F7C6`
  — <!--claim capabilities.requester.flags#=15--> **15** capability bits set
- responder `Flags` <!--claim capabilities.responder.flags_raw=0xb99afbf7--> `0xB99AFBF7`
  — <!--claim capabilities.responder.flags#=23--> **23** bits set
- bits set on **both** sides: <!--claim capabilities.common#=14--> **14**
- `CTExponent` <!--claim capabilities.requester.ct_exponent=0--> `0`
- `DataTransferSize` <!--claim capabilities.requester.data_transfer_size=4608--> **4,608** bytes (`0x1200`)
- `MaxSPDMmsgSize` <!--claim capabilities.requester.max_spdm_msg_size=163840--> **163,840** bytes (`0x28000`)

The table above is not read off a header file. Here is the request, all
<!--claim message_bytes.first_by_type.SPDM_GET_CAPABILITIES=20--> 20 bytes of
it, from `spdm_dump -r walkthrough.pcap -x`:

```
       0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 16 17 18 19
      14 e1 00 00 00 00 00 00 c6 f7 82 88 00 12 00 00 00 80 02 00
      ^^ ^^ ^^^^^ ^^ ^^ ^^^^^ ^^^^^^^^^^^ ^^^^^^^^^^^ ^^^^^^^^^^^
      |  |  |     |  |  |     Flags        DataXferSz  MaxSPDMmsg
      |  |  |     |  |  ExtFlags
      |  |  |     |  CTExponent
      |  |  |     Reserved
      |  |  Param1, Param2
      |  0xE1 GET_CAPABILITIES
      0x14 SPDM 1.4
```

`c6 f7 82 88` is `0x8882F7C6` — **the multi-byte fields are little-endian**, and
that is worth seeing once rather than being told, because §0 shows the socket
header that carries these bytes is big-endian. Two byte orders, one connection.

### The three fields worth carrying forward

**`CTExponent`.** The responder's cryptographic timeout, as `2^CTExponent`
microseconds. Here it is 0, so 1 µs — an emulator on loopback. On a real ERoT
signing with ML-DSA it is not 0, and a requester with no timeout basis either
gives up on a device that was working or waits forever on one that is not.
CVE-2023-32690 is this field going unvalidated.

**`DataTransferSize` = 4,608.** The largest single message either side will
accept. This is the number that decides whether §5 runs at all: a certificate
chain under it arrives in one response, and a chain over it forces the exchange
into SPDM's chunking mechanism. 1,655 bytes is under it. 16,853 is not, and §9
shows what happens then.

**`Flags`, and a claim in the week's plan that this capture refutes.** The plan
this week is worked against states, marked as re-checked, that `CHUNK` is not in
either side's default capabilities. Both flag words above have bit 17 set, which
is `CHUNK_CAP`. The plan is wrong, and so is the source of the plan's belief:

```
spdm_emu/spdm_emu_common/spdm_emu.c:115
  "By default, CERT,CHAL,ENCRYPT,MAC,MUT_AUTH,KEY_EX,PSK,ENCAP,HBEAT,
   KEY_UPD,HANDSHAKE_IN_CLEAR,MULTI_KEY_NEG,LARGE_RESP is used for Requester."

spdm_emu/spdm_emu_common/key.c:25
  SPDM_GET_CAPABILITIES_REQUEST_FLAGS_CHUNK_CAP |
```

The `--help` text is a hand-written string. The default is a hand-written
initialiser. They disagree, and they have disagreed about `CHUNK_CAP` and
`EP_INFO_CAP_SIG` on the requester side, and those two plus `MEL_CAP` on the
responder side. The wire agrees with the initialiser, because the wire *is* the
initialiser. This is a candidate upstream change and is tracked in
[`docs/upstream/README.md`](upstream/README.md).

**What breaks if this message is removed.** Two things, and the second is the
one people miss. You would send requests for operations the peer cannot perform.
And you would have **no size limit and no timeout basis**, which means every
later message is being sent on an assumption rather than an agreement.

**What I am not sure about.** `ExtFlags` is `0x0000` here and the header notes it
was reserved before 1.4. What a non-zero value would mean, and whether anything
negotiates it yet, is unread.

---

## 3. `NEGOTIATE_ALGORITHMS` (0xE3) / `ALGORITHMS` (0x63)

### Request — packet 5

| offset | field | size | observed |
|--:|---|--:|---|
| 0–1 | `SPDMVersion`, `Code` | 2 | `0x14`, `0xE3` |
| 2 | `Param1` | 1 | number of `AlgStructure` tables |
| 3 | `Param2` | 1 | reserved |
| 4–5 | `Length` | 2 | whole message length |
| 6 | `MeasurementSpecification` | 1 | `0x01` (DMTF) |
| 7 | `OtherParamsSupport` | 1 | `0x12` (`OPAQUE_FMT_1`, `MULTI_KEY_CONN`) |
| 8–11 | `BaseAsymAlgo` | 4 | `0x00000090` |
| 12–15 | `BaseHashAlgo` | 4 | `0x00000003` |
| 16–19 | **`PQCAsymAlgo`** | 4 | `0x00000007` — **added in 1.4** |
| 20–27 | `Reserved2` | 8 | |
| 28–31 | ext counts, `MELspecification` | 4 | |
| 32… | `AlgStructure[]` | var | DHE, AEAD, ReqBaseAsym, KeySchedule, ReqPQCAsym, KEM |

**Offset 16 is where a version-blind parser goes wrong.** In SPDM 1.3 there is no
`PQCAsymAlgo`; `Reserved2` starts there instead. Read this message without first
knowing the negotiated version and every field after byte 15 is off by four.
That is a concrete reason the version exchange has to come first, and it is
visible by putting §9's 1.3 capture beside this one.

### Response — packet 6, and the asymmetry

| offset | field | size | observed |
|--:|---|--:|---|
| 4–5 | `Length` | 2 | |
| 6 | `MeasurementSpecificationSel` | 1 | `0x01` |
| 7 | `OtherParamsSelection` | 1 | `0x12` |
| 8–11 | **`MeasurementHashAlgo`** | 4 | `0x00000008` — **response only** |
| 12–15 | `BaseAsymSel` | 4 | `0x00000080` |
| 16–19 | `BaseHashSel` | 4 | `0x00000002` |
| 20–23 | `PQCAsymSel` | 4 | `0x00000000` |

The response is **not** the request with fewer bits set. `MeasurementHashAlgo`
appears only in the response and sits where `BaseAsymAlgo` sits in the request,
so the two messages cannot share a parser even though they share a name.

### Offered against selected

| | offered | selected |
|---|--:|---|
| `Hash` | <!--claim algorithms.offered_counts.Hash=2--> 2 | <!--claim algorithms.negotiated.Hash=SHA_384--> `SHA_384` |
| `MeasHash` | — (response only) | <!--claim algorithms.negotiated.MeasHash=SHA_512--> `SHA_512` |
| `Asym` | <!--claim algorithms.offered_counts.Asym=2--> 2 | <!--claim algorithms.negotiated.Asym=ECDSA_P384--> `ECDSA_P384` |
| `PqcAsym` | <!--claim algorithms.offered_counts.PqcAsym=3--> 3 | <!--claim algorithms.negotiated.PqcAsym=--> *none* |
| `DHE` | <!--claim algorithms.offered_counts.DHE=4--> 4 | <!--claim algorithms.negotiated.DHE=SECP_384_R1--> `SECP_384_R1` |
| `KEM` | <!--claim algorithms.offered_counts.KEM=3--> 3 | <!--claim algorithms.negotiated.KEM=--> *none* |
| `AEAD` | <!--claim algorithms.offered_counts.AEAD=2--> 2 | <!--claim algorithms.negotiated.AEAD=AES_256_GCM--> `AES_256_GCM` |
| **`ReqAsym`** | <!--claim algorithms.offered_counts.ReqAsym=4--> 4 | <!--claim algorithms.negotiated.ReqAsym=RSAPSS_3072--> **`RSAPSS_3072`** |

**The row that matters most is the last one.** `ReqAsym` is the algorithm the
*requester* signs with. It is negotiated separately from `Asym`, and nothing
about setting `--asym` touches it. A post-quantum experiment that pins the
responder's algorithm and leaves this at its default is varying one of two
independent variables while reporting one — which is exactly what happened in
this repository on 2026-08-11 and is written up in `LOG.md`. Every arm in §9
pins both.

### Offering four algorithms costs the same as offering one

The week's plan asks how much bigger `NEGOTIATE_ALGORITHMS` gets when several
algorithms are offered per group instead of one, and treats it as obvious that
it does. It does not. Two captures from the same run, identical in everything
except how many algorithms each group offers:

```
stock       14 e3 06 00 38 00 01 12 90 00 00 00 ... 02 20 1b 00 03 20 06 00 ...
one each    14 e3 06 00 38 00 01 12 80 00 00 00 ... 02 20 10 00 03 20 02 00 ...
                     ^^ ^^ ^^^^^      ^^^^^^^^^^^      ^^^^^          ^^^^^
                     |  |  Length     BaseAsymAlgo     DHE mask       AEAD mask
                     |  6 AlgStructure tables
                     Param1
```

| | `NEGOTIATE_ALGORITHMS` | `ALGORITHMS` |
|---|--:|--:|
| stock — 2 hash, 2 asym, 4 DHE, 2 AEAD, 4 req-asym | <!--claim message_bytes.first_by_type.SPDM_NEGOTIATE_ALGORITHMS=56--> **56 B** | <!--claim message_bytes.first_by_type.SPDM_ALGORITHMS=60--> 60 B |
| one of each (§9.4) | **56 B** | 60 B |

**Zero difference.** `BaseAsymAlgo`, `BaseHashAlgo` and `PQCAsymAlgo` are
fixed-width 32-bit bitmasks, and each `AlgStructure` table's `AlgSupported` is a
fixed 16-bit bitmask. Adding an algorithm sets a bit. The `Length` field reads
`0x0038` in both.

So the cost of offering everything you support is not bandwidth. It is that
**you do not know what you will be using until you read the response back** —
which is a correctness cost, not a byte cost, and it is the reason every result
in this repository confirms the algorithm from `ALGORITHMS` rather than from the
flags that were passed in.

Two things *do* change the size, and both are measured in §9:

| change | size | why |
|---|--:|---|
| stock, SPDM 1.4 | 56 B | 32-byte fixed part + 6 `AlgStructure` tables |
| `--dhe NONE` (§9.3) | 52 B | one fewer table; `Param1` goes 6 → 5 |
| SPDM 1.3 (§9.2) | 48 B | four tables — 1.4 added `ReqPQCAsym` and `KEM` |

The 1.3 → 1.4 growth is **entirely** those two new tables. `PQCAsymAlgo`, the
field that carries post-quantum signature support, was carved out of
`Reserved2[12]` and cost nothing: the fixed part is 32 bytes in both versions.
A protocol extension that fits in reserved space is free, and one that needs a
new table is 4 bytes — that is the actual shape of extension cost here, and it
is not what "post-quantum makes messages bigger" would lead you to expect.

**What problem this message solves.** Choosing one algorithm per role out of the
sets both sides support.

**What breaks if it is removed.** The same shape as §1 and for the same reason:
an attacker who edits the offered set down to the weakest common option gets a
downgrade neither side can see. And the same defence — these two messages are in
the signed transcript.

**What I am not sure about.** Whether the responder is required to pick the
strongest option in the intersection or is free to pick any. This capture is
consistent with "strongest" (SHA-384 over SHA-256, P-384 over P-256), but one
sample is not a rule, and the answer decides whether a downgrade needs a
tampered *request* or a merely lazy responder.

---

## 4. `GET_DIGESTS` (0x81) / `DIGESTS` (0x01)

The request is a bare four-byte header. The response carries its information in
the header's parameter bytes:

| offset | field | size | observed | meaning |
|--:|---|--:|---|---|
| 0–1 | `SPDMVersion`, `Code` | 2 | `0x14`, `0x01` | |
| 2 | `Param1` = `SupportedSlotMask` | 1 | `0x13` | slots 0, 1, 4 exist |
| 3 | `Param2` = `ProvisionedSlotMask` | 1 | `0x13` | all three hold a key |
| 4… | `Digest[]` | 48 each | | one SHA-384 per populated slot |
| … | `KeyPairID[]` | 1 each | `0x05, 0x05, 0x11` | 1.3+, two slots share a key pair |
| … | `CertificateInfo[]` | 1 each | `DEVICE` ×3 | |
| … | `KeyUsageBitMask[]` | 2 each | `KEY_EX, CHALL, MEAS, EP_INFO` | |

`0x13` is `0b0001_0011`, so slots 0, 1 and 4. **The slots are not contiguous**,
and that recurs — §7 has the same shape with measurement indices.

**Note the digest size is not in the message.** It is 48 bytes because `Hash`
negotiated to SHA-384 in §3. Nothing in `DIGESTS` says so. A parser that has not
kept the negotiation result cannot find the end of this message, let alone the
fields after it.

**What problem it solves.** Bandwidth and time. A certificate chain is kilobytes
and may take several round trips; a digest is 48 bytes. A requester that already
holds a chain compares the digest and skips fetching it again.

**What breaks if it is removed.** Nothing, in correctness terms — this is an
optimisation, and §1's `PUB_KEY_ID_CAP` path skips it entirely. It stops being
merely an optimisation under post-quantum algorithms: §9 measures the responder's
chain at 1,655 bytes classically and 16,853 with ML-DSA-65, so the cost of *not*
having a cache rises tenfold while the cost of checking it stays at 48 bytes.
**Certificate caching moves from an optimisation to a requirement, and this is
the message that makes caching possible.**

**What I am not sure about.** Two slots report `KeyPairID` `0x05`. Whether that
means they genuinely share one private key, and what a verifier should conclude
from two slots that do, is unread — and it looks like the kind of thing that
matters for what a slot's identity actually asserts.

---

## 5. `GET_CERTIFICATE` (0x82) / `CERTIFICATE` (0x02)

### Request — packet 9

| offset | field | size | observed | meaning |
|--:|---|--:|---|---|
| 0–1 | `SPDMVersion`, `Code` | 2 | `0x14`, `0x82` | |
| 2 | `Param1` | 1 | `0x80` | bits 0–3 slot = 0; **bit 7 = `LargeCertChain`, new in 1.4** |
| 3 | `Param2` | 1 | `0x00` | request attribute |
| 4–5 | `Offset` | 2 | | 16-bit — superseded when bit 7 is set |
| 6–7 | `Length` | 2 | | |
| 8–11 | `LargeOffset` | 4 | `0x00000000` | present only when `LargeCertChain` |
| 12–15 | `LargeLength` | 4 | `0x00027FF0` | |

Requested length: <!--claim certificate.requested_length=163824--> **163,824**
bytes.

That number is `MaxSPDMmsgSize` (163,840) minus 16. The requester is asking for
"everything that could fit in one message, less the response's own header and
length fields". It is not a guess, and it is not the chain's size — it is the
largest answer the requester could accept.

### Response — packet 10

| offset | field | size | observed |
|--:|---|--:|---|
| 2 | `Param1` | 1 | `0x80` — slot 0, `LargeCertChain` |
| 3 | `Param2` | 1 | `0x01` (`DEVICE`) |
| 8–11 | `LargePortionLength` | 4 | `0x00000677` = 1,655 |
| 12–15 | `LargeRemainderLength` | 4 | `0x00000000` |
| 16… | `CertChain` | 1,655 | |

| | |
|---|---|
| responder slot 0 chain | <!--claim certificate.responder_slot0_bytes=1655--> **1,655** bytes |
| portions per fetch | <!--claim certificate.responder_slot0_portions=1--> 1 |
| times the same chain is fetched | <!--claim certificate.responder_slot0_fetches=2--> **2** |
| responder slot 4 chain | <!--claim certificate.responder_chains.4.bytes=1660--> 1,660 bytes |
| `GET_CERTIFICATE` messages | <!--claim certificate.get_certificate_count=3--> 3 |
| …of which encapsulated | <!--claim certificate.get_certificate_encapsulated=1--> 1 |

### `PortionLength` is not the chain's length

It is the size of *this slice*. `RemainderLength` is what is still owed. The
chain's size is the first response's `PortionLength + RemainderLength`, and a
fetch is finished when `RemainderLength` reaches zero.

Reading `PortionLength` as the chain size is right whenever the chain arrives
whole — which it does here, and does not in §9's `classical-stable` arm, where
the same field reads 1,024 against a 1,591-byte chain. The tool that produced
this table made exactly that mistake on first contact with the second capture,
and the fix is in `harness/fields.py`. **Two fields exist because one of them
could not have been enough, and any code that ignores the second is correct only
by luck.**

The other consequence of using the right boundary: this capture fetches the same
slot-0 chain **twice**, once before `CHALLENGE` and once after the mutual
authentication in §8. Lumping every `CERTIFICATE` for a slot together would have
reported a 1,655-byte chain as 3,310 bytes in two portions — two wrong numbers
from one wrong assumption.

**What problem it solves.** Getting the responder's certificate chain so its
signature can be checked against a trust anchor.

**What breaks if it is removed.** You are talking to something that can sign, and
you have no idea what. The signature in §6 would verify against a key with no
provenance, which is arithmetic, not identity.

**What I am not sure about.** Whether the double fetch is deliberate — exercising
the cache path — or an artefact of `spdm_requester_authentication.c` running its
digest-and-certificate sequence twice. The source suggests the second, but
"suggests" is the honest word.

---

## 6. `CHALLENGE` (0x83) / `CHALLENGE_AUTH` (0x03)

### Request — packet 13

| offset | field | size | observed |
|--:|---|--:|---|
| 0–1 | `SPDMVersion`, `Code` | 2 | `0x14`, `0x83` |
| 2 | `Param1` = slot ID | 1 | `0x00` |
| 3 | `Param2` = `HashType` | 1 | `0xFF` (`AllHash`) |
| **4–35** | **`Nonce`** | **32** | random |
| 36–43 | `RequesterContext` | 8 | 1.3+ |

**The requester's nonce is at offset 4, and always at offset 4.** Nothing before
it varies.

### Response — packet 14

| offset | field | size | note |
|--:|---|--:|---|
| 2 | `Param1` | 1 | `0x80` — slot 0, **`BasicMutAuth`** |
| 3 | `Param2` = `SlotMask` | 1 | `0x13` |
| 4–51 | `CertChainHash` | **48** | = the negotiated hash size |
| **52–83** | **`Nonce`** | 32 | |
| 84–131 | `MeasurementSummaryHash` | **48** | |
| 132–133 | `OpaqueLength` | 2 | |
| … | `OpaqueData`, `RequesterContext`, `Signature` | var | |

`CHALLENGE_AUTH` `Param1`: <!--claim mutual_auth.challenge_auth_attr=0x80--> `0x80`.

### The two nonces are not at the same kind of offset

The requester's is at a **fixed** offset. The responder's is at
**4 + digest_size** — offset 52 here because §3 negotiated SHA-384, and offset 36
had SHA-256 been chosen.

That is the sharpest single lesson in this document. **You cannot parse
`CHALLENGE_AUTH` without knowing what was negotiated three messages earlier.**
Message boundaries in SPDM are not self-describing; they are a function of state
established earlier in the same connection. Every argument in this repository
about reading the negotiated result back rather than asserting it is usually
made about honest measurement. It is also, quite literally, about being able to
find the bytes.

**What problem it solves.** Proving the peer holds the private key for the chain
it just sent.

**What breaks if it is removed.** Replay. Record one successful exchange and
play it back and you are that device — the nonce is what makes each exchange
unrepeatable.

**But the signature does not cover only the nonce.** It covers the whole
transcript: `GET_VERSION`/`VERSION`, `GET_CAPABILITIES`/`CAPABILITIES`,
`NEGOTIATE_ALGORITHMS`/`ALGORITHMS`, the digests, the certificate, and this
challenge. So one signature verifying proves three separate things at once:

1. the peer holds the private key,
2. this exchange is fresh,
3. **and none of the negotiation in §1 through §5 was altered in flight.**

Which is why §1 and §3 can say "the defence is elsewhere" and be precise about
where.

**What I am not sure about.** `MeasurementSummaryHash` is a digest over the
measurements, present here because `HashType` was `0xFF`. Whether a verifier
that has this summary still needs `GET_MEASUREMENTS`, or whether the summary is
only an integrity anchor for measurements fetched separately, is a question §7
raises and does not answer.

---

## 7. `GET_MEASUREMENTS` (0xE0) / `MEASUREMENTS` (0x60)

### Request — packet 29

| offset | field | size | observed | meaning |
|--:|---|--:|---|---|
| 2 | `Param1` = `Attributes` | 1 | `0x01` | `GenerateSignature` |
| 3 | `Param2` = `MeasurementOperation` | 1 | `0xFF` | **all measurements** |
| 4–35 | `Nonce` | 32 | | |
| 36 | `SlotIDParam` | 1 | `0x00` | 1.1+ |
| 37–44 | `RequesterContext` | 8 | | 1.3+ |

`MeasurementOperation` has two reserved values and 254 ordinary ones:
`0x00` asks how many measurements exist, `0xFF` asks for all of them, and
`0x01`–`0xFE` ask for one by index.

### Response — packet 30

| offset | field | size | observed |
|--:|---|--:|---|
| 2 | `Param1` | 1 | `TotalNumberOfMeasurements`, or reserved when `MeasOp` ≠ 0 |
| 3 | `Param2` | 1 | `0x20` — slot 0, `ContentChanged = NoChange` |
| 4 | `NumberOfBlocks` | 1 | `0x08` |
| **5–7** | **`MeasurementRecordLength`** | **3** | `0x000210` = 528 |
| 8… | `MeasurementRecord` | 528 | |
| … | `Nonce` | 32 | |
| … | `OpaqueLength`, `OpaqueData`, `RequesterContext` | var | |
| … | `Signature` | var | |

| | |
|---|---|
| operation | <!--claim measurements.operation=ALL--> `ALL` |
| blocks returned | <!--claim measurements.num_of_blocks=8--> **8** |
| measurement record | <!--claim measurements.measurement_record_bytes=528--> **528** bytes |
| `GET_MEASUREMENTS` sent | <!--claim measurements.get_measurements_count=1--> **1** |

**`MeasurementRecordLength` is three bytes.** Not two, not four. A 24-bit
little-endian integer, and the field after it is not aligned to anything. Cast a
received buffer to a struct and this is where it goes wrong — which is the same
hazard `c-drills/d6` exists for.

**`MEASUREMENTS` is not "a signature".** It is a header, a block count, a 24-bit
length, the record itself, a 32-byte nonce, opaque data, a requester context,
*and then* a signature. Any calculation that divides a message size by a
signature size to count something will be wrong, and wrong by an amount that
changes with the negotiated algorithm.

### The 526 packets, and why they are not the protocol's fault

Left at its default this capture is 554 packets. 526 of them are here. The
default is `--meas_op ONE_BY_ONE`, and what that does is not one pass but two:

```c
/* spdm_emu/spdm_requester_emu/spdm_requester_measurement.c */

/* 1. query the total number of measurements available. */
/* 2. get the existing measurement list */
for (index = 1; index < ..._ALL_MEASUREMENTS; index++) { ... }   /* 1 .. 0xFE */

/** 3. query measurement one by one
 *
 * In SPDM 1.2 spec, the L1/L2 will be reset in case of MEASUREMENT error.
 * That impacts 1-by-1 calculation. For example, if a device supports
 * Measurement 1 and Measurement 3, then our current mechanism will cause
 * Measurement 1 NOT included in final transcript, because Measurement 2 is
 * missing.
 *
 * The soultion is: get the existing measurement list, then query measurement
 * one by one.
 **/
```

Both loops carry `if (received == number_of_blocks) break;`. The responder holds
eight measurements, so both should stop after eight — except the eight indices
are `0x01, 0x02, 0x03, 0x04, 0x10, 0x11, 0xFD, 0xFE`, and the last one is
`0xFE`. The early exit never fires. Two passes over 254 indices, 246 of them
answered `InvalidRequset`.

So the answer to the question this repository left open in `LOG.md` on
2026-08-11 — whether the per-block round trips are the emulator's choice or the
protocol's — is **both, in different parts**:

- **the two-pass structure is forced by the specification.** From SPDM 1.2 an
  errored `MEASUREMENT` resets the L1/L2 transcript hash, so a requester
  building a signed transcript has to know which indices exist *before* it
  starts. Discovering that costs a pass, and that pass must be the one that
  eats the errors.
- **walking the index space is the emulator's choice.** `MeasOp = 0xFF` fetches
  every block in one message, and the emulator uses it when told to.
- **the sparse indices are the sample responder's choice**, and they are what
  makes the early exit useless.

### The part that makes this checkable rather than arguable

Under `ONE_BY_ONE`, summing `MeasurementRecordLength` over the eight indices
that exist gives **528 bytes**. Under `ALL`, one response carries a record of
**528 bytes**. Same measurements, same bytes, 263 requests against 1.

Both numbers are claimed against their own captures in §9, so the identity is
checked by CI rather than asserted here.

**What problem this message solves.** Reporting what the device is currently
running, signed, so it cannot be forged or replayed.

**What breaks if it is removed.** You know *who* the device is and nothing about
*what it is running* — which is the whole point of attestation. §1–§6 establish
identity. This is the first message that carries state.

**And what SPDM still does not do.** It delivers `a3f9…` and proves it came from
this device unmodified. It says nothing about whether `a3f9…` is the *right*
value. That comparison is the verifier's, it is out of scope for the
specification, and it is what `rats/` is for.
See [`docs/rats-roles.md`](rats-roles.md).

**What I am not sure about.** Whether `Nonce` is present in `GET_MEASUREMENTS`
when `GenerateSignature` is clear. The libspdm struct has it unconditionally;
whether DSP0274 makes it conditional is unread, and it changes where
`SlotIDParam` sits.

---

## 8. What else is in the capture, that nobody asked for

Six of the thirty messages belong to an exchange that appears in no tutorial of
the seven-step handshake:

| | |
|---|---|
| encapsulated messages | <!--claim mutual_auth.encapsulated_message_count=6--> **6** |
| `CHALLENGE_AUTH` `Param1` | `0x80` — `BasicMutAuth` |
| requester's own chain | <!--claim certificate.requester_slot0_bytes=3794--> **3,794** bytes |

Packets 15–22 are the **responder challenging the requester**. `spdm-emu` ships
with `--basic_mut_auth BASIC` and `--mut_auth W_ENCAP`, so a run nobody
configured for mutual authentication does it anyway, wrapped in
`ENCAPSULATED_REQUEST` / `DELIVER_ENCAPSULATED_RESPONSE` — the mechanism for
sending a request backwards down a connection whose direction is already fixed.

The requester's chain is **3,794 bytes**, more than twice the responder's 1,655,
because §3 negotiated `ReqAsym = RSAPSS_3072` for it while the responder uses
ECDSA-P384. An RSA-3072 chain is simply bigger than an EC one.

**Why this matters beyond being a curiosity.** Any "total handshake bytes" figure
from a default `spdm-emu` run includes 3,794 bytes of RSA that have nothing to
do with the responder's algorithm. Change `--pqc_asym` and that half does not
move. This is the concrete reason the post-quantum arm in §9 pins
`--req_pqc_asym` too, and the reason the byte totals in §9 are labelled as
whole-exchange numbers rather than as the cost of one algorithm.

---

## 9. The same handshake on three configurations

Everything above is one capture. These are the other three arms of the same run,
each checked against its own decode.

### 9.1 Classical, `--meas_op ONE_BY_ONE` — the stock flow

<!-- capture: bench/data/w2-baseline-20260816T172221Z/classical.decode.txt -->

| | |
|---|---|
| messages decoded | <!--claim messages.decoded=554--> **554** |
| `GET_MEASUREMENTS` sent | <!--claim measurements.get_measurements_count=263--> **263** |
| `InvalidRequset` responses | <!--claim measurements.invalid_request_errors=246--> **246** |
| indices that exist | <!--claim measurements.existing_indices_hex=0x01,0x02,0x03,0x04,0x10,0x11,0xfd,0xfe--> `0x01, 0x02, 0x03, 0x04, 0x10, 0x11, 0xFD, 0xFE` |
| **sum of their record lengths** | <!--claim measurements.record_bytes_sum=528--> **528 bytes** |
| responder slot 0 chain | <!--claim certificate.responder_slot0_bytes=1655--> 1,655 bytes |

528 here, 528 in §7. **263 round trips and 1 round trip deliver the same
measurement bytes**, and both halves of that sentence are re-derived from
captures by CI.

### 9.2 Classical on the released pair — the control

<!-- capture: bench/data/w2-baseline-20260816T172221Z/classical-stable.decode.txt -->

Identical flags, `spdm-emu` 3.8.0 → `libspdm` 3.8.0 instead of 4.0.0-rc. This arm
exists to answer whether the classical arm above can stand in for the baseline
build. It cannot:

| | 4.0.0-rc (§9.1) | 3.8.0 |
|---|--:|--:|
| SPDM version negotiated | 1.4 | <!--claim version.post_negotiation_header=1.3--> **1.3** |
| requester `Flags` | `0x8882F7C6` | <!--claim capabilities.requester.flags_raw=0x0882f7c6--> **`0x0882F7C6`** |
| `NEGOTIATE_ALGORITHMS` | 56 B | <!--claim message_bytes.first_by_type.SPDM_NEGOTIATE_ALGORITHMS=48--> **48 B** |
| `GET_CERTIFICATE` `Length` requested | 163,824 | <!--claim certificate.requested_length=1024--> **1,024** |
| responder slot 0 chain | 1,655 B | <!--claim certificate.responder_slot0_bytes=1591--> **1,591 B** |
| …in portions | 1 | <!--claim certificate.responder_slot0_portions=2--> **2** |
| requester chain | 3,794 B | <!--claim certificate.requester_slot0_bytes=3728--> **3,728 B** |
| …in portions | 1 | <!--claim certificate.requester_slot0_portions=4--> **4** |
| messages decoded | 554 | <!--claim messages.decoded=566--> **566** |

The single bit of difference in `Flags` is bit 31, `LARGE_RESP_CAP`, which SPDM
1.4 introduced — and with it the 32-bit `LargeOffset`/`LargeLength` fields of
§5. Without them 3.8.0 asks for 1,024 bytes at a time and needs four round trips
for a chain 4.0.0-rc takes in one.

**`CHUNK_CAP` is set on this build too**, which is worth saying because it means
the plan's claim in §2 is wrong on both builds, not only the newer one.

So a "classical baseline" is not a build-independent thing. Which flavor produced
a number belongs in its caption, and `manifest.json` records it whether or not
anyone writes it down.

### 9.3 Post-quantum — ML-DSA-65 both directions

<!-- capture: bench/data/w2-baseline-20260816T172221Z/pqc.decode.txt -->

| | |
|---|---|
| responder signature | <!--claim algorithms.negotiated.PqcAsym=ML_DSA_65--> **`ML_DSA_65`** |
| **requester signature** | <!--claim algorithms.negotiated.ReqPqcAsym=ML_DSA_65--> **`ML_DSA_65`** |
| key encapsulation | <!--claim algorithms.negotiated.KEM=ML_KEM_768--> `ML_KEM_768` |
| responder slot 0 chain | <!--claim certificate.responder_slot0_bytes=16853--> **16,853 bytes** |
| `NEGOTIATE_ALGORITHMS` | <!--claim message_bytes.first_by_type.SPDM_NEGOTIATE_ALGORITHMS=52--> **52 B** — one table fewer, `--dhe NONE` |
| `LargeResponse` errors | <!--claim chunking.large_response_errors=1--> **1** |
| `CHUNK_GET` round trips | <!--claim chunking.chunk_get_count=4--> **4** |
| decode complete | <!--claim source.decode_truncated=True--> **no — see below** |
| messages decoded before it stopped | <!--claim messages.decoded=18--> 18 |

**Post-quantum does not only cost bytes. It changes the message flow.** 16,853
exceeds the negotiated `DataTransferSize` of 4,608, so `GET_CERTIFICATE` is
answered with `SPDM_ERROR(LargeResponse)` and the exchange falls into chunking:
four `CHUNK_GET`/`CHUNK_RESPONSE` round trips to deliver one certificate. **The
classical path never executes that code**, which is why §2's `CHUNK_CAP` finding
is not a footnote. On a real BMC speaking MCTP over I²C, where the transfer unit
is smaller again, this is the part that would be felt.

**And this decode is incomplete, which is a fact about the decoder, not the
handshake.** `spdm_dump` stops at message 18 with `cert_chain is too larger`. The
handshake itself completed: 584 packets against the classical arm's 554, exit 0.
The decoder's `LIBSPDM_MAX_CERT_CHAIN_SIZE` is **4,096 bytes**, measured out of
the compiled binary by bisection — see `third_party/spdm-dump.pin`. The emulator
that produced the capture is built from the *same libspdm commit* and handles the
chain without complaint, so this is a build-configuration difference, not a
version difference: the same header selects 32,768 when ML-DSA support is
compiled in, and 16,853 would fit.

Until that is rebuilt, no post-quantum number that depends on messages after the
certificate can come from this decode. **That is why §9.3 is short, and it is
short on purpose.**

### 9.4 One algorithm per group — the control for §3

<!-- capture: bench/data/w2-baseline-20260816T172221Z/single-algo.decode.txt -->

Identical to the `walkthrough` arm except that `--hash`, `--asym`, `--dhe`,
`--aead`, `--req_asym` and `--meas_hash` are each pinned to a single value
instead of being left at their two-to-four defaults.

| | offered | negotiated |
|---|--:|---|
| `Hash` | <!--claim algorithms.offered_counts.Hash=1--> 1 | <!--claim algorithms.negotiated.Hash=SHA_384--> `SHA_384` |
| `Asym` | <!--claim algorithms.offered_counts.Asym=1--> 1 | <!--claim algorithms.negotiated.Asym=ECDSA_P384--> `ECDSA_P384` |
| `DHE` | <!--claim algorithms.offered_counts.DHE=1--> 1 | <!--claim algorithms.negotiated.DHE=SECP_384_R1--> `SECP_384_R1` |
| `AEAD` | <!--claim algorithms.offered_counts.AEAD=1--> 1 | <!--claim algorithms.negotiated.AEAD=AES_256_GCM--> `AES_256_GCM` |
| `ReqAsym` | <!--claim algorithms.offered_counts.ReqAsym=1--> 1 | <!--claim algorithms.negotiated.ReqAsym=RSAPSS_3072--> `RSAPSS_3072` |

`NEGOTIATE_ALGORITHMS`
<!--claim message_bytes.first_by_type.SPDM_NEGOTIATE_ALGORITHMS=56--> **56
bytes**, against 56 for the stock arm. `ALGORITHMS`
<!--claim message_bytes.first_by_type.SPDM_ALGORITHMS=60--> **60**, against 60.
The whole exchange comes to <!--claim messages.decoded=30--> 30 messages either
way, and the two captures are the same size on the wire.

Everything negotiated to the same value the stock arm negotiated to, which is
the second half of the point: the defaults were not costing bytes *and* were not
changing the outcome here. What they cost is knowing the outcome in advance —
and §9.3 is the case where that mattered, since leaving `--req_pqc_asym` at its
default is how a run ends up signing with two different ML-DSA parameter sets.

---

## 10. What this document's checking does not cover

Stated here because a check trusted beyond its reach is worse than none.

1. **The capability-bit names are transcribed, not parsed.** `harness/fields.py`
   carries the bit tables from `libspdm/include/industry_standard/spdm.h` by
   hand. If upstream renames a bit or adds one, `--check` will keep passing on a
   stale name, because a wrong name is still self-consistent. Re-read the header
   after a version bump. Bits the table does not know about are reported as
   `flags_unrecognised` rather than dropped, so a *new* bit is visible; a
   *renamed* one is not.

2. **Most of the offsets are read from headers, not from the wire.** The offset
   columns come from the struct definitions in `spdm.h`. The values beside them
   come from the capture and are checked, but a wrong offset next to a right
   value would still pass.

   Three messages have been confirmed byte for byte against `spdm_dump -x` and
   are shown that way above: `GET_VERSION` (§0), `GET_CAPABILITIES` (§2) and
   `NEGOTIATE_ALGORITHMS` (§3). The rest have not. The two that would repay it
   most are `CHALLENGE_AUTH` — because §6 claims the nonce sits at
   `4 + digest_size` and that is the document's sharpest claim — and
   `MEASUREMENTS`, for the 24-bit length field.

3. **Sizes marked as computed are computed.** Where a length is derived from the
   negotiated hash size (§6's offset 52, §4's 48-byte digests) it is arithmetic
   from the specification, not a measured byte count.

4. **One run per arm.** Byte counts here are deterministic and were identical
   across three separate executions of `harness/capture.sh`. Nothing timing-
   related is reported, because one run cannot support it.

5. **`TODO(me)`** — the open questions at the end of §1, §2, §3, §4, §5, §6 and
   §7 are mine as of 2026-08-17. When one is answered, the answer goes here with
   the date, and the question stays. A document in which every question was
   always answered is not a record of learning anything.

---

*Written against `bench/data/w2-baseline-20260816T172221Z/`. Regenerate with
`bash harness/capture.sh --name w2-baseline`; re-check with
`python3 harness/fields.py --check docs/handshake-walkthrough.md`.*

# Table 1 — five tampers, and which layer notices

**This project performs protocol-level correctness validation. It is not a
security assessment.** Everything below is a description of how DMTF's
reference implementation behaves when it is fed inputs the author chose. It is
not a claim about SPDM's security, about libspdm's security, or about any
product. Where a result looks like a weakness, the section says precisely whose
behaviour it is and what the specification actually requires.

Every number on this page is marked up and re-derived from the capture named
above it by `harness/fields.py --check`, which `harness/verify_repo.sh` runs.
The captures are in
[`bench/data/w5-tamper-20260910T092621Z/`](../bench/data/w5-tamper-20260910T092621Z/),
with a `manifest.json` recording the upstream commits, the patch digest, the
command lines and a SHA-256 of every artifact including the fixtures and the
proxy's own reports.

Reproduce with:

```bash
bash harness/apply_device_patch.sh pqc --build
bash harness/tamper.sh
```

---

## 1. Table 1

Ten arms, one control, five of them tampers. Every arm runs the same binaries,
the same flags, the same certificate chain and the same slot count; what
differs is named in the row and nothing else.

<!-- capture: bench/data/w5-tamper-20260910T092621Z/t0_clean.decode.txt -->

| # | what changed | where | who could notice | **what happened** | status the requester printed |
|:--|---|---|---|---|---|
| — | *nothing* (`t0_clean`) | — | — | handshake completed | none |
| — | *nothing, through the proxy* (`t0_proxy`) | on the wire | — | handshake completed, record byte-identical | none |
| **1** | the measurement value on the **device** | before the signature | **nobody, in SPDM** | **handshake completed** | **none** |
| **2a** | the measurement record **in flight** | after the signature | the measurement signature | refused after `MEASUREMENTS` | `80020001` `VERIF_FAIL` |
| **2b** | the **signature** in flight | the signature itself | the measurement signature | refused after `MEASUREMENTS` | `80020001` `VERIF_FAIL` |
| **3** | a certificate the **device serves** | before it is sent | **the device itself** | no `CERTIFICATE` was ever sent | `8001000a` `ERROR_PEER` |
| 3b | *whose* chain it is, not its bytes | before it is sent | the requester's authority check | **handshake completed** | none — it is a **warning** |

**Caption.** `spdm-emu` `5f01d2f` / `libspdm` `8a92317` (`4.0.0-rc`), plus
[`device/meas-from-file.patch`](../device/meas-from-file.patch); SPDM **1.4**;
`ECDSA_ECC_NIST_P384` with `SECP_384_R1`, read back from the `ALGORITHMS`
response rather than from the flags; measurement hash `SHA_384`, also read
back. Every arm:

```
spdm_responder_emu --exe_conn DIGEST,CERT,CHAL,MEAS --exe_session NO_END \
                   --meas_op ALL --slot_count 1
spdm_requester_emu  ... the same, plus --pcap <case>.pcap
```

and for rows 2a and 2b, with `--port 2324` on the requester and
`harness/tamper_proxy.py --listen 2324 --forward 2323` in between. Ubuntu
24.04.4, gcc 13.3.0, x86_64. Run `w5-tamper-20260910T092621Z`.

### The three sentences this table exists to support

**One.** *Rows 2a and 2b are indistinguishable from the requester's side and
have opposite causes.* In 2a the signature is untouched and the bytes it covers
were changed. In 2b the bytes are untouched and the signature was changed. Both
print `80020001`, from the same function, from the same layer. **An integrator
triaging from a log line cannot tell a corrupted device from a corrupted link**,
and the two have completely different responses: one is a supply-chain and
update-path problem, the other is a cable, an interposer, a re-flashed retimer.

> SPDM tells you *that* something is wrong. It does not tell you *which layer*
> is wrong. Separating them needs information the protocol does not carry —
> whether the failure repeats, whether it moves with the cable, whether a whole
> batch of machines fails together. That is diagnostic engineering, not
> cryptography.

**Two.** *Row 1 is the dangerous one, and it is the row where nothing happened.*
The measurement value on the device was changed, the responder hashed the new
value, signed the record it had just built, and every check passed. That is
correct behaviour, and §4 works through why. It is also the entire argument for
Gate 3.

**Three.** *Row 3 failed earlier than "the requester rejected it", and the
capture is what says so.* There is no `CERTIFICATE` message in that arm at all.
The device validates its own chain when it loads it, could not, and stopped
advertising the slot. §7.

---

## 2. What is being changed, and where

The five tampers are not variations of each other. They are at three different
points relative to one signature, and that position is the only thing that
decides the outcome.

```
   the device's stored measurement  ──►  1   nothing in SPDM checks this
                    │
            [ the responder hashes, assembles, and SIGNS ]
                    │
   the bytes in flight  ──► 2a record ──►  the signature checks this
                        └─► 2b signature ──►  and so does this
                    │
   the certificate on the device's disk  ──► 3   the DEVICE checks it, at load
   whose certificate it is               ──► 3b  the requester — as a warning
```

| # | one byte? | changed by | reaches a verifier? |
|:--|:--:|---|:--:|
| 1 | yes | `device/gen_measurements.py --flip-block 1 --flip-offset 36` | yes, correctly signed |
| 2a | yes | `harness/tamper_proxy.py --flip-record 1:36` | yes, with the old signature |
| 2b | yes | `harness/tamper_proxy.py --flip-signature -1` | yes, with the right record |
| 3 | yes | `certs/check_chain.py --locate`, then one XOR | **no** — never sent |
| 3b | no | a different chain, internally perfect | yes, and accepted |

Cases 2a and 2b were not in this project's own week-five plan, which predicted
that points 1 and 2 would produce the same message from different causes. Point
1 produces no message at all, so the pair that demonstrates it had to be found
somewhere else — and it turned out to be inside point 2, which is a stronger
pair, because both halves reach a verifier and the only difference between them
is which side of the signature the byte was on.

Case 3b was also not planned. It exists because case 3 measured something other
than what it was built to measure, and §8 is that story.

---

## 3. The control, and why it was taken before the code existed

The change made in week four adds two lines to libspdm's sample device secret
library so that measurement values can come from a file. The load-bearing claim
is that **the added lines do nothing when no file is named** — and that claim
cannot be checked against a capture taken afterwards by the person who wants it
to be true.

It does not have to be. The 528-byte measurement record is deterministic: no
nonce, no timestamp, nothing that varies between runs. The same SHA-256 appears
in arms across capture runs on 2026-08-16, 08-28, 08-31, 09-01 and 09-10. So
the control is a capture committed **before this code was written**, and
`harness/tamper.sh` reads the digest out of it rather than carrying a copy:

<!-- capture: bench/data/w4-baseline-20260901T054208Z/selfsigned.decode.txt -->

| | |
|---|---|
| control capture | `w4-baseline-20260901T054208Z/selfsigned` |
| record bytes | <!--claim layout.measurement_record.record_bytes=528-->528 |
| blocks | <!--claim layout.measurement_record.blocks_walked=8-->8, walked and closed exactly |
| record SHA-256 | <!--claim layout.measurement_record.sha256=f2a14684e8fae9ff0e3ebff2a380f435c0fee5b0c8199d3fdfed31b2252f51d8-->`f2a14684e8fae9ff…` |
| secure version number | <!--claim layout.measurement_record.secure_version_number=7-->7 |

Three arms then have to reproduce that digest exactly — a 256-bit target that a
mis-wired fixture path, or a proxy that corrupts what it forwards, would miss:

<!-- capture: bench/data/w5-tamper-20260910T092621Z/t0_none.decode.txt -->

**`t0_none`** — patched binary, `SPDM_MEASUREMENTS_FILE` unset, so no file is
opened at all:
<!--claim layout.measurement_record.sha256=f2a14684e8fae9ff0e3ebff2a380f435c0fee5b0c8199d3fdfed31b2252f51d8-->`f2a14684e8fae9ff…`,
<!--claim messages.decoded=30-->30 messages.

<!-- capture: bench/data/w5-tamper-20260910T092621Z/t0_clean.decode.txt -->

**`t0_clean`** — the fixture is present and holds exactly what upstream
synthesises (72 bytes of the index for indices 1–4, secure version number 7):
<!--claim layout.measurement_record.sha256=f2a14684e8fae9ff0e3ebff2a380f435c0fee5b0c8199d3fdfed31b2252f51d8-->`f2a14684e8fae9ff…`,
<!--claim messages.decoded=30-->30 messages,
<!--claim layout.measurement_record.secure_version_number=7-->svn 7.

<!-- capture: bench/data/w5-tamper-20260910T092621Z/t0_proxy.decode.txt -->

**`t0_proxy`** — the same fixture, forwarded through the tamper proxy with
nothing changed:
<!--claim layout.measurement_record.sha256=f2a14684e8fae9ff0e3ebff2a380f435c0fee5b0c8199d3fdfed31b2252f51d8-->`f2a14684e8fae9ff…`,
<!--claim messages.decoded=30-->30 messages,
<!--claim messages.by_type.SPDM_CERTIFICATE=3-->3 `CERTIFICATE` messages
carrying 1,897 bytes of chain each.

The third of those is the one the proxy earns its place with, and it is not a
formality. A proxy that mishandled a 1.9 KB `CERTIFICATE` — a short `recv`, a
byte order, a length read from the wrong offset — would break every arm it
touched, and **"the tamper was detected" is exactly what that looks like from
an exit code.** Rows 2a and 2b are only readable because this row is boring.

---

## 4. Point 1 — the measurement at the device, and the layer that does not exist

`device/gen_measurements.py --flip-block 1 --flip-offset 36` changes **one
byte** of the 72-byte value the responder hashes for measurement index 1. Not
the hash on the wire — the pre-image. Upstream then computes the SHA-512 of the
changed input, assembles the block, sizes the record and signs the transcript,
all with code this project did not touch.

Exactly which byte, so the input is stated rather than described:

| | |
|---|---|
| file | `t1_meas.measurements.bin`, 336 bytes, `sha256 04c0f6dd…` |
| offset | **84** (`0x54`), XOR `0x01` |
| what it is | byte 36 of the 72-byte value for measurement index `0x01` |
| the clean file | `t0_clean.measurements.bin`, `sha256 8844b46e…` — identical but for that byte |

Both are committed in the run directory and hashed into its `manifest.json`,
with the generator's own output beside them as `t1_meas.fixture.txt`. The tool
refuses a `--flip-byte` that would land outside a measurement value: offset 12,
the example in this project's own week-four plan, is inside the secure version
number, and flipping it would change how the fixture is *read* rather than what
it *says* — while looking identical in a log.

The prediction written down before the run was that the handshake would
**succeed**. It did.

<!-- capture: bench/data/w5-tamper-20260910T092621Z/t1_meas.decode.txt -->

| | `t0_clean` | `t1_meas` |
|---|---|---|
| messages | 30 | <!--claim messages.decoded=30-->30 |
| `CHALLENGE_AUTH` | 1 | <!--claim messages.by_type.SPDM_CHALLENGE_AUTH=1-->1 |
| `MEASUREMENTS` | 1 | <!--claim messages.by_type.SPDM_MEASUREMENTS=1-->1 |
| record bytes | 528 | <!--claim layout.measurement_record.record_bytes=528-->528 |
| blocks | 8 | <!--claim layout.measurement_record.blocks_walked=8-->8 |
| record SHA-256 | `f2a14684…` | <!--claim layout.measurement_record.sha256=21ae49f9b66835f6d2cdefe34d14d05991c86c8527cc2cb672dc4d9b841406a1-->`21ae49f9b66835f6…` |
| index 1 value | `5ba8569b…` | <!--claim layout.measurement_record.blocks.0x01.value_sha256=62f6b527048a88b212dee2519ebbd9a5f23e99e9e3824403745af3879327f11f-->`62f6b527048a88b2…` |
| index 2 value | `ac61d8b1…` | <!--claim layout.measurement_record.blocks.0x02.value_sha256=ac61d8b19a01e1c984658119c4baead5c4a0b87100eb31864d4b17f9a744a9db-->`ac61d8b19a01e1c9…` — unchanged |
| **requester exit** | 0 | **0** |
| **status printed** | none | **none** |

**Exactly one of the eight blocks moved**, the one whose pre-image was changed,
and its type is <!--claim layout.measurement_record.blocks.0x01.value_type_name=IMMUTABLE_ROM-->`IMMUTABLE_ROM`.
Every length on the wire is identical — the whole exchange is
<!--claim messages.decoded=30-->30 messages and 11,671 SPDM bytes in both arms,
because a bit flip does not change a size. The handshake completed, and every
signature in it verified.

### Why that is correct rather than broken

Ask who signs what, with which key. The responder signs the transcript of the
messages **it just sent**, with its own private key. Change what it reads and it
computes a new measurement record — and then signs *that*. The requester
receives a self-consistent (record, signature) pair and verifies it.

For a signature check to fail, the bytes that were signed and the bytes that
were verified have to differ. There are exactly two ways to arrange that:
change them in flight (§5), or sign with a key that does not match the presented
certificate. Changing the source is neither.

The certificate chain is different because the requester holds an **independent
anchor**: a root certificate it was given out of band. There is no equivalent
for a measurement. The requester has no idea what this device's firmware hash
*should* be.

> **SPDM proves that a measurement genuinely came from this device. It does not
> prove that the measurement is correct.** The first is a signature. The second
> needs reference values, and reference values are not in the protocol.

That division is RATS: the Attester reports, the Verifier compares against
Reference Values, and SPDM is the transport and the authenticity of the report.
[`docs/rats-roles.md`](rats-roles.md) has the roles. Gate 3 is where the
comparison gets built, and **this row is the reason it has to be** — the only
tamper in Table 1 that nothing refuses is the one a reference value would catch.

---

## 5. Point 2 — the same measurement, on the other side of the signature

`harness/tamper_proxy.py` listens on 2324, forwards to 2323, and changes one
byte of the `MEASUREMENTS` response as it goes past. That is a different threat
model from §4 and it is most of the value: changing a file is an attacker with
access to the device; changing bytes on the wire is an attacker on the link,
who never touches the device at all.

### What the proxy refuses to do

A proxy that flips "the last byte" needs no understanding of the message, and it
can be wrong without anybody noticing: if the flip lands in the wrong field, the
arm still fails and the wrong sentence gets written about why. So this one
parses what it is about to change and requires two independent equations to
close first.

**The signature length**, read off the wire rather than taken from the flags.
The proxy reads `BaseAsymSel` out of the `ALGORITHMS` response as it passes —
<!--claim messages.by_type.SPDM_ALGORITHMS=1-->one message, `0x00000080`,
`ECDSA_ECC_NIST_P384`, 96 bytes — and then parses `MEASUREMENTS` forward and
requires what is left over to equal that:

```
     4  SPDM header
   + 1  NumberOfBlocks
   + 3  MeasurementRecordLength
   + 528  the record          <- 8 blocks, walked, tiling it exactly
   + 32  Nonce
   + 2  OpaqueDataLength (0)
   + 8  RequesterContext
   ————
   578  where the signature starts
   674 - 578  =  96           ==  what ECDSA P-384 signs.  Closed.
```

**That equation refused this project's own plan.** `plan/W05.md` lists the
`MEASUREMENTS` fields without `RequesterContext`, which is eight bytes and would
put the signature at 570 — leaving 104 where 96 was required. The proxy declines
to flip anything and says which number did not match. `spdm.h:936-949` is where
the field is, and SPDM 1.3 is where it arrived;
`harness/tamper_proxy.py --self-test` reproduces the refusal from a synthetic
message, along with twelve others, and fails if any of its thirteen registered
checks was never exercised.

**The block walk.** `NumberOfBlocks` says 8; walking eight blocks has to land
exactly on 528. The eight are indices `0x01`–`0x04` (64-byte values), `0x10`
(the 8-byte secure version number), `0x11` (64), `0xfd` (128) and `0xfe` (16).

### 2a — the record changed, the signature untouched

<!-- capture: bench/data/w5-tamper-20260910T092621Z/t2a_record.decode.txt -->

The proxy's report, committed as `t2a_record.proxy.json` and hashed into the
manifest:

| | |
|---|---|
| target | byte **36** of the 64-byte value of measurement index `0x01` |
| offset in the SPDM message | **51** |
| offset in the socket payload | 52 — one more, the MCTP message-type byte |
| offset in a pcap record | 56 — four more, the header `spdm_emu` synthesises |
| the byte | `0x7f` → `0x7e` |
| record before | `f2a14684e8fae9ff…` — **the control's** |
| record after | `4519f14eddf4fab4…` |

Note that this is byte 36 of the value **on the wire**, which is the SHA-512
digest, where §4 changed byte 36 of the 72-byte **pre-image** the responder
hashes. Same index, same offset, two different objects on two different sides of
the signature. That is the whole experiment: the difference in outcome cannot be
attributed to *what* was changed, only to *when*.

| | `t0_clean` | `t2a_record` |
|---|---|---|
| messages | 30 | <!--claim messages.decoded=30-->30 |
| `MEASUREMENTS` | 1 | <!--claim messages.by_type.SPDM_MEASUREMENTS=1-->1 |
| record bytes | 528 | <!--claim layout.measurement_record.record_bytes=528-->528 |
| blocks | 8 | <!--claim layout.measurement_record.blocks_walked=8-->8 |
| record SHA-256 | `f2a14684…` | <!--claim layout.measurement_record.sha256=4519f14eddf4fab47d53e0720427a7f22592ae0e53307f9e8313e2c06b99bc8c-->`4519f14eddf4fab4…` |
| index 1 value | `5ba8569b…` | <!--claim layout.measurement_record.blocks.0x01.value_sha256=ce5dea03475fdf73fa645ac2865d866a7e1aa6afae38be25c4b6f1525e3d0dc8-->`ce5dea03475fdf73…` |
| **requester exit** | 0 | **1** |
| **status** | none | **`80020001` `VERIF_FAIL`** |

Two witnesses that never saw each other: the proxy reported reading
`f2a14684…` and writing `4519f14e…` while the connection was open;
`harness/fields.py` read `4519f14e…` out of the requester's capture file
afterwards. `verify_repo.sh` requires both halves — that the responder sent the
control's record, and that what the proxy wrote is what the capture holds.

### 2b — the signature changed, the record untouched

<!-- capture: bench/data/w5-tamper-20260910T092621Z/t2b_sig.decode.txt -->

| | |
|---|---|
| target | byte **95** of the 96-byte signature |
| offset in the SPDM message | **673** — the last byte of the message |
| the byte | `0x88` → `0x89` |
| record before and after | `f2a14684e8fae9ff…` — **identical**, it was not touched |

| | `t0_clean` | `t2b_sig` |
|---|---|---|
| messages | 30 | <!--claim messages.decoded=30-->30 |
| record bytes | 528 | <!--claim layout.measurement_record.record_bytes=528-->528 |
| record SHA-256 | `f2a14684…` | <!--claim layout.measurement_record.sha256=f2a14684e8fae9ff0e3ebff2a380f435c0fee5b0c8199d3fdfed31b2252f51d8-->`f2a14684e8fae9ff…` — **the control's** |
| index 1 value | `5ba8569b…` | <!--claim layout.measurement_record.blocks.0x01.value_sha256=5ba8569b56df00a71210b749a79c4c8347d22659e29b98292d5e8c6036f0f9dc-->`5ba8569b56df00a7…` — unchanged |
| **requester exit** | 0 | **1** |
| **status** | none | **`80020001` `VERIF_FAIL`** |

### The comparison, which is the point

| | `t1_meas` | `t2a_record` | `t2b_sig` |
|---|---|---|---|
| record on the wire | **differs** | **differs** | **the control's** |
| signature on the wire | recomputed | the old one | **one bit changed** |
| status | none | `80020001` | `80020001` |
| verdict | **completed** | rejected | rejected |

Read across the bottom two rows. `t2a_record` and `t2b_sig` are the same
outcome and the same number from opposite causes, and nothing the requester
prints separates them. Read across the top row instead and they separate
immediately — one carries the control's record and one does not.

> **The wire tells them apart. The error message does not.** That is not a
> criticism of libspdm: `LIBSPDM_STATUS_VERIF_FAIL` is severity `ERROR`, source
> `CRYPTO`, code `0x0001`, and "the signature over this transcript did not
> verify" is the whole of what the crypto layer knows. Everything that would
> distinguish the two lives outside it.

`t1_meas` completes with a record that differs from the control just as much as
`t2a_record`'s does. Three arms, three different values for measurement index 1
(`62f6b527…`, `ce5dea03…`, and the control's `5ba8569b…`), and only two of them
are refused.

---

## 6. What the byte counts say, which is nothing

Worth stating because it is a negative result and negative results are the ones
that get left out:

| | `t0_clean` | `t0_proxy` | `t1_meas` | `t2a_record` | `t2b_sig` |
|---|--:|--:|--:|--:|--:|
| packets | 30 | 30 | 30 | 30 | 30 |
| SPDM bytes | 11,671 | 11,671 | 11,671 | 11,671 | 11,671 |
| `MEASUREMENTS` bytes | 674 | 674 | 674 | 674 | 674 |
| `GET_CERTIFICATE` round trips | 3 | 3 | 3 | 3 | 3 |

Identical, to the byte, across a clean run, a proxied run and three tampers.
`bench/pcapstat.py` produces these by walking the capture file; `fields.py`
reaches the same per-type totals from `spdm_dump`'s decode; CI requires them to
agree. **No byte count in this table detects anything**, and a size-based
anomaly detector would see five identical exchanges. Detection here is
cryptographic or it is nothing.

---

## 7. Point 3 — the certificate, and a failure earlier than expected

`certs/check_chain.py --locate` returns the byte to change and says what it is:

```
  #  name            offset  bytes  sig at   sig  flip
  0  ca                   0    504     401   103  479
  1  inter              504    573     974   103  1053
  2  end_responder     1077    768    1742   103  1821

  inter: flipping bundle byte 1053 changes byte 24 of the 48-byte ECDSA s
         value in the certificate's own signature
```

Byte **1053** is chosen rather than found by eye, and the choice is the
experiment. A byte of a DER length field stops the certificate parsing; a byte
of the subject public key breaks the leaf's signature as well as the root's; a
byte of the `tbsCertificate` changes the certificate's contents as well as its
signature. Byte 1053 is inside the intermediate's own ECDSA `s`: the certificate
still parses, every field still says what it said, and exactly one link — the
root's signature over the intermediate — stops verifying.

<!-- capture: bench/data/w5-tamper-20260910T092621Z/t3_cert.decode.txt -->

| | `t0_clean` | `t3_cert` |
|---|---|---|
| messages | 30 | <!--claim messages.decoded=10-->10 |
| `CERTIFICATE` messages | 3 | **none** |
| certificate chains on the wire | 4 | <!--claim layout.chains#=0-->0 |
| measurement records | 1 | <!--claim layout.measurement_records#=0-->0 |
| `SPDM_ERROR` | 0 | <!--claim messages.by_type.SPDM_ERROR=1-->1 |
| `ProvisionedSlotMask` | `0x13` | <!--claim layout.digests.provisioned_slot_mask=0x12-->**`0x12`** |
| requester exit | 0 | 1 |
| status | none | `8001000a` `ERROR_PEER` |

The failure is **earlier** than any other row's, and the capture proves it
rather than the log: `t3_cert` carries no `CHALLENGE_AUTH` and no
`MEASUREMENTS`, while every other arm carries both.

**But the mechanism is not the one that was expected, and the pcap is what
says so.** The obvious sentence to write is "the requester rejected the tampered
certificate chain". The capture refutes it: there is no `CERTIFICATE` message at
all. Nothing bad was ever sent.

One bit tells the story. In the clean run `ProvisionedSlotMask` is `0x13`; here
it is `0x12`. **Slot 0 is gone.** Reading upstream rather than guessing:

- `libspdm_read_responder_public_certificate_chain` calls
  `libspdm_verify_cert_chain_data` on the file it just read and returns false if
  it does not verify (`read_pub_cert.c:447`);
- `spdm_responder_emu` then reads slots 1 and 4, **assigning to the same `res`
  variable each time**, and tests only the last one
  (`spdm_responder_spdm.c:495-553`);
- so the slot-0 failure produces no message anywhere. `data` stays `NULL`,
  `libspdm_set_data(LOCAL_PUBLIC_CERT_CHAIN, slot 0, NULL, 0)` leaves the slot
  unprovisioned, and the requester's `GET_CERTIFICATE` for slot 0 is answered
  `SPDM_ERROR(InvalidRequest)`.

The status is `8001000a` — severity `ERROR`, source **`CORE`**, code `0x000a`,
`LIBSPDM_STATUS_ERROR_PEER`, which means "the peer returned an SPDM error". Note
what it is *not*: it is not `INVALID_CERT` and not `VERIF_FAIL`. **The requester
never formed an opinion about the certificate**, because it never saw one. The
source field alone separates this row from 2a and 2b, and it is the only row
where it does.

The device refused to serve a chain it could not itself validate. That is good
behaviour and it is not the certificate-chain *verification* that point 3 was
meant to exercise — **a byte flipped on the device's disk cannot reach the
requester's verifier at all**, because the device checks first.

The silently-discarded return value is filed as an upstream candidate in
[`docs/upstream/README.md`](upstream/README.md).

---

## 8. Case 3b — the chain the device could validate, and the verifier accepted

If the bytes cannot be wrong, make the *authority* wrong. The responder serves
DMTF's own `ecp384` chain, signing with DMTF's leaf key, while the requester
keeps this project's root as its trust anchor — it reads that anchor from
`ecp384/ca.cert.der`, a different file, left untouched
(`libspdm_read_responder_root_public_certificate`).

This is the counterfeit-part shape rather than the corrupted-file shape: a
well-formed chain from an authority nobody told the verifier to trust.

<!-- capture: bench/data/w5-tamper-20260910T092621Z/t3b_foreign.decode.txt -->

| | `t0_clean` | `t3b_foreign` |
|---|---|---|
| slot-0 chain | 1,897 bytes, root `df0ee8f9…` (ours) | **1,655 bytes, root `ed79ce9a…` (DMTF's)** |
| distinct roots in the capture | 3 | <!--claim layout.distinct_root_hashes=2-->2 |
| `CERTIFICATE` messages | 3 | <!--claim messages.by_type.SPDM_CERTIFICATE=3-->3 |
| `CHALLENGE_AUTH` | 1 | <!--claim messages.by_type.SPDM_CHALLENGE_AUTH=1-->1 |
| `MEASUREMENTS` | 1 | <!--claim messages.by_type.SPDM_MEASUREMENTS=1-->1 |
| messages | 30 | <!--claim messages.decoded=30-->30 |
| **requester exit** | 0 | **0** |
| **status** | none | **none** |

**The handshake completed.** A full mutually-authenticated exchange, every
signature verified, against a device whose entire certificate chain descends
from a CA the requester was never given.

`harness/tamper.sh` reports this as `anchor: MISMATCH` in its own table, by
hashing the file the requester was configured to trust and comparing it with the
root hash reconstructed from the capture — two things it knows independently.

### Why, exactly

libspdm detects it. It does not treat it as an error:

```c
/* Provided cert is valid but is not authoritative(mismatch the root cert). */
#define LIBSPDM_STATUS_VERIF_NO_AUTHORITY \
    LIBSPDM_STATUS_CONSTRUCT(LIBSPDM_SEVERITY_WARNING, LIBSPDM_SOURCE_CRYPTO, 0x0003)
```

`libspdm_verify_peer_cert_chain_buffer_authority` walks every provisioned root,
finds no hash match, and returns false. `libspdm_try_get_certificate` then does

```c
result = libspdm_verify_peer_cert_chain_buffer_authority(...);
if (!result) {
    status = LIBSPDM_STATUS_VERIF_NO_AUTHORITY;
}
```

— with **no `goto done`**, unlike the integrity check three lines above it,
which does. The status survives to the return
(`libspdm_req_get_certificate.c:483-541`). `spdm_requester_emu` calls the
`libspdm_get_certificate` form that discards the trust anchor, tests
`LIBSPDM_STATUS_IS_ERROR`, and a `SEVERITY_WARNING` is not an error.

The number makes the point on its own: `0x40020003` against `0x80020001`. The
top nibble is the entire difference between a row that stops the connection and
a row that does not, and `harness/spdm_status.py` computes severity from the
value rather than looking it up, so the distinction is arithmetic and not a
table someone maintained.

**This is a design decision, not a defect.** libspdm returns a distinct status
and an out-parameter naming the anchor precisely so an integrator can apply
policy — a device may legitimately present a chain from a CA the verifier learns
about by other means. What the sample application does with it is what a sample
does.

The transferable part is the one worth saying out loud:

> An integrator who checks only `LIBSPDM_STATUS_IS_ERROR` has silently accepted
> every certificate chain that parses. On a real BMC that is the difference
> between "this device is genuine" and "this device presented well-formed
> papers".

### It was already in a capture from two weeks earlier

This behaviour is not an artifact of the change made in week four. In the
`selfsigned` arm committed on 2026-08-31, the requester's two provisioned
`ecp384` roots are this project's `ca.cert.der` (`df0ee8f9…`) and upstream's
`ca1.cert.der` (`e8d668ef…`). Packet 12 carries slot 4's chain, root
`ed79ce9a…`, which is neither — and the connection continued.

Week 3 found that a single handshake carries **three** trust anchors. Week 4
found that the requester was never provisioned with one of them and did not
mind. `t3b_foreign` is what makes it decisive: slot 4 is fetched but not used
for `CHALLENGE`, whereas slot 0 is the slot whose leaf key signs it.

The `t3b_foreign` capture is also the reason to be careful with the previous
sentence's scope. It shows the acceptance for **this requester application**
under **these flags**. It does not establish anything about SPDM, and it does
not establish that any product behaves this way.

---

## 9. The other axis — a version number that can now be more than one value

Upstream hard-codes the secure version number to `0x7`, in one line of
`libspdm_fill_measurement_svn_block`. That is entirely reasonable for sample
code and it makes a rollback policy untestable: a rule of the form
`evidence_svn >= reference_svn` fed one value has never been tested, whichever
way it is written.

Two arms differ from `t0_clean` in the fixture's 8-byte header field and in
nothing else:

<!-- capture: bench/data/w5-tamper-20260910T092621Z/svn5.decode.txt -->

**`svn5`**: on the wire, measurement index `0x10` carries
<!--claim layout.measurement_record.blocks.0x10.value_hex=0500000000000000-->`05 00 00 00 00 00 00 00`,
which `fields.py` decodes as
<!--claim layout.measurement_record.secure_version_number=5-->5. Record
<!--claim layout.measurement_record.sha256=985df8524b6d0e08f8b13c2f2fc944def43b5c66eb99af922975a4c3cfd7d529-->`985df8524b6d0e08…`.

<!-- capture: bench/data/w5-tamper-20260910T092621Z/svn9.decode.txt -->

**`svn9`**: <!--claim layout.measurement_record.blocks.0x10.value_hex=0900000000000000-->`09 00 00 00 00 00 00 00`,
decoded as <!--claim layout.measurement_record.secure_version_number=9-->9.
Record
<!--claim layout.measurement_record.sha256=cda33be106e759c35d6deef2116029ff1cec0c1e194a45e02352d3d738a83fab-->`cda33be106e759c3…`,
still <!--claim layout.measurement_record.record_bytes=528-->528 bytes and
<!--claim layout.measurement_record.blocks_walked=8-->8 blocks.

In both, **only block `0x10` differs** from the clean record; indices 1–4, the
hash-extend log, the manifest and the device-mode block are byte-identical.
Three values — 5, 7 and 9 — now exist on the wire, which is the prerequisite for
Gate 3's rollback cases.

Note that the field is eight bytes, not four. `spdm.h:934` declares
`spdm_measurements_secure_version_number_t` as a `uint64_t`, and this project's
own week-four plan described it as a `uint32`. The proxy's block walk reports it
as 8 bytes from the wire, which is a third source agreeing with the header.

---

## 10. What the device-mode block already says

Not a tamper case, but it is measured here and it is the field that decides
whether the other rows matter. Measurement index `0xfe`, value type
`DEVICE_MODE`, is four little-endian `uint32`s:

<!-- capture: bench/data/w5-tamper-20260910T092621Z/t0_clean.decode.txt -->

<!--claim layout.measurement_record.blocks.0xfe.value_hex=3f000000040000001f00000011000000-->`3f 00 00 00 · 04 00 00 00 · 1f 00 00 00 · 11 00 00 00`

| field | value | meaning |
|---|---|---|
| `OperationalModeCapabilities` | `0x3f` | all six operational modes supported |
| `OperationalModeState` | `0x04` | `NORMAL_MODE` |
| `DeviceModeCapabilities` | `0x1f` | five debug-mode bits supported |
| `DeviceModeState` | `0x11` | **non-invasive debug active**, and **invasive debug has been active since manufacturing** |

The sample device reports that its debug interfaces are open. That is the
correct thing for a sample to report and it is exactly the field a verifier
should refuse on: OCP's S.O.L.I.D. FW002 requires that measurements cover
"everything that affects the security of the product, such as configuration,
mutable code and enablement of debug/recovery modes."

Which makes §4 concrete rather than abstract. A device can report
`DeviceModeState = 0x11`, sign it correctly, and every SPDM check in Table 1
will pass. Only a verifier comparing against a reference value refuses it.

---

## 11. What is not claimed

- **No timing is reported.** Every number here is a byte count, a message
  count, a digest or a status code, all deterministic. Nothing on this page
  needs a median. The measurement environment is two local processes over a
  TCP socket with a Python proxy between them for three of the arms; the
  dominant term in any latency measured there is scheduling and I/O, not
  cryptography.
- **One responder, one requester, one transport.** All of this is
  `spdm_requester_emu` against `spdm_responder_emu` over a TCP socket, at the
  commits in `third_party/spdm-emu-pqc.pin` plus
  [`device/meas-from-file.patch`](../device/meas-from-file.patch). Real hardware
  is not involved and no result here transfers to a product without being
  re-measured on it.
- **The tamper cases are the author's**, not an adversary's. They are chosen to
  isolate one mechanism each, which is the opposite of what an attacker does.
  In particular, rows 2a and 2b change one byte where an attacker would change
  as many as necessary and would not stop at the ones that make the outcome
  legible.
- **The proxy is an attacker with an implausible amount of cooperation.** It
  reads the connection's negotiated algorithm out of `ALGORITHMS` in the clear,
  which is true of these arms because no session is established. A real
  interposer against an encrypted session sees far less, and rows 2a and 2b say
  nothing about that case.
- **Case 3b describes an application, not a protocol.** DSP0274 does not
  require a requester to reject an unprovisioned root; deciding that is the
  integrator's job, which is why libspdm hands it back as a warning.
- **Row 1 is a property of SPDM's scope, not a defect anywhere.** No layer in
  this table is failing to do its job. The verifier that would refuse it did
  not exist when this table was taken; it does now, and
  [`rats-pipeline.md`](rats-pipeline.md) Table 3 appraises these same ten
  captures. Row 1 is judged **FAIL**, blocked by `SPDM_HASH_CHECK` at
  measurement index 1, and CI turns red if it stops being.

  Two rows of that table are worth reading back against this one. **Row 2b
  passes the appraisal**, and correctly: the signature was altered and the
  measurement record is this row's control byte for byte, so the right answer
  is that the conveyance broke and the device is fine — which is the
  distinction the identical `80020001` in rows 2a and 2b could not make. And
  **row 3b passes too**, which is also correct and still not reassuring: the
  measurements really are the reference values, and what is wrong is whose
  device produced them.

---

## 12. How this page is kept true

| what | by what |
|---|---|
| every number above | `harness/fields.py --check docs/tamper.md`, recomputed from the named capture on every CI run |
| the record digests | four tools that share no input: `fields.py` (the decode), `pcapstat.py` (the capture file), `tamper_proxy.py` (the live socket), `gen_measurements.py` (the fixture) |
| the chain's 1,897 bytes | three routes: `check_chain.py` from the DER files, `fields.py` from the decode, `pcapstat.py` from the capture |
| **that tampering is still refused** | `verify_repo.sh` re-derives rows 1, 2a and 2b from the requester's own logs and the committed `fields.json`, and **fails the build** if an in-flight tamper stops being rejected, if the two stop sharing a status, or if the device-side one starts being rejected |
| the proxy's parse | `tamper_proxy.py --self-test`: thirteen registered refusals, all of which must fire |
| the status names | `spdm_status.py --self-test`: severity and source computed, names checked against the pinned header |

The fourth row is the one that matters. A table can be anything. A build that
turns red when a tampered measurement is *not* rejected is why this one can be
believed, and it is written as a negative on purpose.

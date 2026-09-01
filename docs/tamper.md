# Three points, and which layer notices

**This project performs protocol-level correctness validation. It is not a
security assessment.** Everything below is a description of how DMTF's
reference implementation behaves when it is fed inputs the author chose. It is
not a claim about SPDM's security, about libspdm's security, or about any
product. Where a result looks like a weakness, the section says precisely whose
behaviour it is and what the specification actually requires.

Every number on this page is marked up and re-derived from the capture named
above it by `harness/fields.py --check`, which `harness/verify_repo.sh` runs.
The captures are in
[`bench/data/w4-tamper-20260901T054403Z/`](../bench/data/w4-tamper-20260901T054403Z/),
with a `manifest.json` recording the upstream commits, the patch digest, the
command lines and a SHA-256 of every artifact including the fixtures.

Reproduce with:

```bash
bash harness/apply_device_patch.sh pqc --build
bash harness/tamper.sh
```

---

## 1. What is being changed, and where

SPDM defends three different things by three independent mechanisms. The point
of changing one byte in three places is that the three failures are not
variations of each other: they happen at different times, are detected by
different parties, and two of them do not happen at all.

```
   the device's stored measurement  ──►  1  ── nothing in SPDM checks this
   the certificate the device holds ──►  3  ── the DEVICE checks it, at load
   the bytes between the two        ──►  2  ── the signature checks this
```

| # | what changes | one byte? | who could notice | measured here |
|:--|---|:--:|---|:--:|
| **1** | the measurement value on the device | yes | **nobody, in SPDM** — only a verifier holding reference values | ✅ |
| **2** | the message bytes in flight | yes | the measurement signature | ✗ — needs a proxy (G2, week 5) |
| **3** | a certificate in the chain the device serves | yes | the device itself, before it advertises the slot | ✅ |
| 3b | *whose* chain it is, rather than its bytes | no | the requester's authority check — **which is a warning** | ✅ |

Point 2 is absent rather than sketched. It needs a process between the two
emulators that recognises `MEASUREMENTS` (0x60) and flips a bit inside the
signature field; adding it is one entry in `harness/tamper.sh`'s case list.

Case 3b was not planned. It exists because case 3 measured something other than
what it was built to measure, and §4 is that story.

---

## 2. The control, and why it was taken before the code existed

The change this week adds two lines to libspdm's sample device secret library
so that measurement values can come from a file. The load-bearing claim is that
**the added lines do nothing when no file is named** — and that claim cannot be
checked against a capture taken afterwards by the person who wants it to be
true.

It does not have to be. The 528-byte measurement record is deterministic: no
nonce, no timestamp, nothing that varies between runs. The same SHA-256 appears
in six arms across three capture runs on 2026-08-16, 08-28 and 08-31, on both
certificate chains. So the control is a capture committed **before this code was
written**, and `harness/tamper.sh` reads the digest out of it rather than
carrying a copy:

<!-- capture: bench/data/w4-baseline-20260901T054208Z/selfsigned.decode.txt -->

| | |
|---|---|
| control capture | `w4-baseline-20260901T054208Z/selfsigned` |
| record bytes | <!--claim layout.measurement_record.record_bytes=528-->528 |
| blocks | <!--claim layout.measurement_record.blocks_walked=8-->8, walked and closed exactly |
| record SHA-256 | <!--claim layout.measurement_record.sha256=f2a14684e8fae9ff0e3ebff2a380f435c0fee5b0c8199d3fdfed31b2252f51d8-->`f2a14684e8fae9ff…` |
| secure version number | <!--claim layout.measurement_record.secure_version_number=7-->7 |

Two arms then have to reproduce that digest exactly — a 256-bit target that a
mis-wired fixture path would miss:

<!-- capture: bench/data/w4-tamper-20260901T054403Z/t0_none.decode.txt -->

**`t0_none`** — patched binary, `SPDM_MEASUREMENTS_FILE` unset, so no file is
opened at all:
<!--claim layout.measurement_record.sha256=f2a14684e8fae9ff0e3ebff2a380f435c0fee5b0c8199d3fdfed31b2252f51d8-->`f2a14684e8fae9ff…`,
<!--claim messages.decoded=30-->30 messages,
<!--claim layout.measurement_record.closes=True-->the record closes.

<!-- capture: bench/data/w4-tamper-20260901T054403Z/t0_clean.decode.txt -->

**`t0_clean`** — the fixture is present and holds exactly what upstream
synthesises (72 bytes of the index for indices 1–4, secure version number 7):
<!--claim layout.measurement_record.sha256=f2a14684e8fae9ff0e3ebff2a380f435c0fee5b0c8199d3fdfed31b2252f51d8-->`f2a14684e8fae9ff…`,
<!--claim messages.decoded=30-->30 messages,
<!--claim layout.measurement_record.secure_version_number=7-->svn 7.

Identical. The second is the stronger of the two: it says the fixture is not
merely being ignored, it is being read and is landing in exactly the place
upstream's own value landed. `device/gen_measurements.py` writes that fixture by
default, which is why its default output is a control rather than an input.

---

## 3. Point 1 — the measurement, and the layer that does not exist

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

<!-- capture: bench/data/w4-tamper-20260901T054403Z/t1_meas.decode.txt -->

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

**Exactly one of the eight blocks moved**, the one whose pre-image was changed,
and its type is <!--claim layout.measurement_record.blocks.0x01.value_type_name=IMMUTABLE_ROM-->`IMMUTABLE_ROM`.
Every length on the wire is identical. The handshake completed, and every
signature in it verified.

### Why that is correct rather than broken

Ask who signs what, with which key. The responder signs the transcript of the
messages **it just sent**, with its own private key. Change what it reads and it
computes a new measurement record — and then signs *that*. The requester
receives a self-consistent (record, signature) pair and verifies it.

For a signature check to fail, the bytes that were signed and the bytes that
were verified have to differ. There are two ways to arrange that: change them
in flight (point 2), or sign with a key that does not match the presented
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
comparison gets built, and **this capture is the reason it has to be** — a
tampered measurement passes everything this repository currently owns.

The plan for this week predicted that point 1 would fail at measurement
signature verification. It does not, and the plan's own diagram says why: it
draws reference-value comparison outside SPDM. Both predictions were written
down before the run; `LOG.md` for 2026-09-01 records which one the capture
chose.

---

## 4. Point 3 — the certificate, and a failure earlier than expected

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

<!-- capture: bench/data/w4-tamper-20260901T054403Z/t3_cert.decode.txt -->

| | `t0_clean` | `t3_cert` |
|---|---|---|
| messages | 30 | <!--claim messages.decoded=10-->10 |
| `CERTIFICATE` messages | 3 | **none** |
| certificate chains on the wire | 4 | <!--claim layout.chains#=0-->0 |
| measurement records | 1 | <!--claim layout.measurement_records#=0-->0 |
| `SPDM_ERROR` | 0 | <!--claim messages.by_type.SPDM_ERROR=1-->1 |
| `ProvisionedSlotMask` | `0x13` | <!--claim layout.digests.provisioned_slot_mask=0x12-->**`0x12`** |
| requester exit | 0 | 1 |

The week's stated goal is met: the failure is **earlier** than point 1's, and
the capture proves it rather than the log — `t3_cert` carries no
`CHALLENGE_AUTH` and no `MEASUREMENTS`, while `t1_meas` carries both. The
requester's log says `ERROR: do_authentication_via_spdm - 8001000a`.

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
  `SPDM_ERROR(InvalidRequset)`.

The device refused to serve a chain it could not itself validate. That is good
behaviour and it is not the certificate-chain *verification* that point 3 was
meant to exercise — **a byte flipped on the device's disk cannot reach the
requester's verifier at all**, because the device checks first. Reaching that
verifier with corrupted bytes requires corrupting them after the device has
loaded them, which is point 2.

The silently-discarded return value is filed as an upstream candidate in
[`docs/upstream/README.md`](upstream/README.md).

---

## 5. Case 3b — the chain the device could validate, and the verifier accepted

If the bytes cannot be wrong, make the *authority* wrong. The responder serves
DMTF's own `ecp384` chain, signing with DMTF's leaf key, while the requester
keeps this project's root as its trust anchor — it reads that anchor from
`ecp384/ca.cert.der`, a different file, left untouched
(`libspdm_read_responder_root_public_certificate`).

This is the counterfeit-part shape rather than the corrupted-file shape: a
well-formed chain from an authority nobody told the verifier to trust.

<!-- capture: bench/data/w4-tamper-20260901T054403Z/t3b_foreign.decode.txt -->

| | `t0_clean` | `t3b_foreign` |
|---|---|---|
| slot-0 chain | 1,897 bytes, root `df0ee8f9…` (ours) | **1,655 bytes, root `ed79ce9a…` (DMTF's)** |
| distinct roots in the capture | 3 | <!--claim layout.distinct_root_hashes=2-->2 |
| `CERTIFICATE` messages | 3 | <!--claim messages.by_type.SPDM_CERTIFICATE=3-->3 |
| `CHALLENGE_AUTH` | 1 | <!--claim messages.by_type.SPDM_CHALLENGE_AUTH=1-->1 |
| `MEASUREMENTS` | 1 | <!--claim messages.by_type.SPDM_MEASUREMENTS=1-->1 |
| messages | 30 | <!--claim messages.decoded=30-->30 |
| **requester exit** | 0 | **0** |

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

### It was already in a capture from last week

This behaviour is not an artifact of the change made this week. In the
`selfsigned` arm committed on 2026-08-31, the requester's two provisioned
`ecp384` roots are this project's `ca.cert.der` (`df0ee8f9…`) and upstream's
`ca1.cert.der` (`e8d668ef…`). Packet 12 carries slot 4's chain, root
`ed79ce9a…`, which is neither — and the connection continued.

Week 3 found that a single handshake carries **three** trust anchors. Week 4
finds that the requester was never provisioned with one of them and did not
mind. `t3b_foreign` is what makes it decisive: slot 4 is fetched but not used
for `CHALLENGE`, whereas slot 0 is the slot whose leaf key signs it.

The `t3b_foreign` capture is also the reason to be careful with the previous
sentence's scope. It shows the acceptance for **this requester application**
under **these flags**. It does not establish anything about SPDM, and it does
not establish that any product behaves this way.

---

## 6. The other axis — a version number that can now be more than one value

Upstream hard-codes the secure version number to `0x7`, in one line of
`libspdm_fill_measurement_svn_block`. That is entirely reasonable for sample
code and it makes a rollback policy untestable: a rule of the form
`evidence_svn >= reference_svn` fed one value has never been tested, whichever
way it is written.

Two arms differ from `t0_clean` in the fixture's 8-byte header field and in
nothing else:

<!-- capture: bench/data/w4-tamper-20260901T054403Z/svn5.decode.txt -->

**`svn5`**: on the wire, measurement index `0x10` carries
<!--claim layout.measurement_record.blocks.0x10.value_hex=0500000000000000-->`05 00 00 00 00 00 00 00`,
which `fields.py` decodes as
<!--claim layout.measurement_record.secure_version_number=5-->5. Record
<!--claim layout.measurement_record.sha256=985df8524b6d0e08f8b13c2f2fc944def43b5c66eb99af922975a4c3cfd7d529-->`985df8524b6d0e08…`.

<!-- capture: bench/data/w4-tamper-20260901T054403Z/svn9.decode.txt -->

**`svn9`**: <!--claim layout.measurement_record.blocks.0x10.value_hex=0900000000000000-->`09 00 00 00 00 00 00 00`,
decoded as <!--claim layout.measurement_record.secure_version_number=9-->9.
Record
<!--claim layout.measurement_record.sha256=cda33be106e759c35d6deef2116029ff1cec0c1e194a45e02352d3d738a83fab-->`cda33be106e759c3…`,
still <!--claim layout.measurement_record.record_bytes=528-->528 bytes and
<!--claim layout.measurement_record.blocks_walked=8-->8 blocks.

In both, **only block `0x10` differs** from the clean record; indices 1–4, the
hash-extend log, the manifest and the device-mode block are byte-identical.
Three values — 5, 7 and 9 — now exist on the wire, which is the prerequisite for
Gate 3's rollback cases and the reason this was done in week 4 rather than week
7.

---

## 7. What the device-mode block already says

Not a tamper case, but it is measured here and it is the field that decides
whether the other seven matter. Measurement index `0xfe`, value type
`DEVICE_MODE`, is four little-endian `uint32`s:

<!-- capture: bench/data/w4-tamper-20260901T054403Z/t0_clean.decode.txt -->

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

Which makes the point of §3 concrete rather than abstract. A device can report
`DeviceModeState = 0x11`, sign it correctly, and every SPDM check will pass.
Only a verifier comparing against a reference value refuses it.

---

## 8. What is not claimed

- **No timing is reported.** Every number here is a byte count, a message
  count or a digest, all deterministic. Nothing on this page needs a median.
- **One responder, one requester, one transport.** All of this is
  `spdm_requester_emu` against `spdm_responder_emu` over a TCP socket, at the
  commits in `third_party/spdm-emu-pqc.pin` plus
  [`device/meas-from-file.patch`](../device/meas-from-file.patch). Real hardware
  is not involved and no result here transfers to a product without being
  re-measured on it.
- **The tamper cases are the author's**, not an adversary's. They are chosen to
  isolate one mechanism each, which is the opposite of what an attacker does.
- **Point 2 does not exist yet**, so the row of Table 1 that would show a
  signature verification actually failing is absent. Until it exists, this
  document has demonstrated a measurement change that is *not* detected and a
  certificate change that never reaches the wire — and no successful signature
  rejection at all.
- **Case 3b describes an application, not a protocol.** DSP0274 does not
  require a requester to reject an unprovisioned root; deciding that is the
  integrator's job, which is why libspdm hands it back as a warning.

# The RATS pipeline: reference values, a policy, and a verdict

> **Scope.** This document reports protocol-flow validation, not a security
> assessment. Everything below is about whether a comparison behaves as
> specified and what it does and does not cover. No claim is made that any of
> it is sufficient to trust a device.

This is the part of the project that answers the question everything before it
was building up to, and it is a question with an embarrassing answer:

> **I have a measurement. Now what?**

For four weeks the honest answer was *nothing*. Week 4 and week 5 measured the
consequence, and it is the single most useful result this repository has
produced:

<!-- capture: bench/data/w5-tamper-20260910T092621Z/t1_meas.decode.txt -->

> One byte of measurement index 1 was changed **on the device**, before the
> responder hashed it and signed it. The handshake **completed**. Every
> signature verified. The requester exited 0 and printed no error. The record on
> the wire hashes to
> <!--claim layout.measurement_record.sha256=21ae49f9b66835f6d2cdefe34d14d05991c86c8527cc2cb672dc4d9b841406a1-->`21ae49f9b66835f6…`
> where the control's hashes to `f2a14684e8fae9ff…`, and **nothing in SPDM
> looked at either number**.

A device that has been compromised still signs honestly. It signs the
compromised value. SPDM authenticates the *reporter*; it has nothing to say
about the *report*.

The missing layer is IETF RATS, RFC 9334, and it is three things the protocol
does not carry:

| what is missing | what it is called |
|---|---|
| you do not know what the value *should* be | a **reference value** |
| you do not know who is *entitled* to say so | an **endorsement** |
| you do not know what to do when they differ | an **appraisal policy** |

[`rats-roles.md`](rats-roles.md) draws the five roles and which arrow SPDM
covers. This document is the pipeline, the commands, and the results.

---

## 1. Who plays what, here

| RATS role | in a datacentre | in this project |
|---|---|---|
| Attester | the NIC, SSD, GPU or its ERoT | `spdm_responder_emu`, with measurements from [`device/`](../device) |
| Verifier | the BMC | [`rats/appraise.py`](../rats/appraise.py) |
| Reference Value Provider | the firmware publisher | [`rats/mint_reference.sh`](../rats/mint_reference.sh) — **also this project**, which is the limitation below |
| Endorser | the silicon vendor's PKI | the self-signed chain from week 3 |
| Relying Party | the scheduler, or audit | the `rats` job in CI |

> ### ⚠ The limitation that belongs here rather than at the end
>
> **The reference values are minted from a capture of the very device they will
> appraise.** In a real system the firmware publisher knows what a good
> measurement is because they built the image; here the "publisher" took a
> photograph of the device and called it the specification.
>
> The consequence is precise and worth stating precisely: this pipeline
> **cannot** detect a device that was already wrong when the reference value was
> taken. What it detects is a device that changed afterwards — which is what
> [`tamper.md`](tamper.md) row 1 shows nothing else detecting, and it is the
> whole reason the layer exists. A reference value with a better provenance
> would be a better reference value; it would not change a single line of the
> comparison, the policy, or the CI assertion.

---

## 2. The pipeline

Five steps, and the first one is the one people skip.

```
              ┌─────────────────────────── the publisher ───────────────────┐
 capture ──▶ reference values ──▶ CBOR ──▶ COSE_Sign1 ──▶ rats/ref/*.corim
              └────────────────────────────────────────────────────────────┘

              ┌─────────────────────────── the verifier ────────────────────┐
 *.corim ──▶ ① verify the signature          ← the ENDORSEMENT
          ──▶ ② decode to the policy's shape
 capture  ──▶ ③ the measurement record, off the wire ──▶ evidence
          ──▶ ④ opa eval, rats/policy.rego
          ──▶ ⑤ a verdict, and an exit code
              └────────────────────────────────────────────────────────────┘
```

```bash
# the publisher, once
bash rats/mint_reference.sh

# the verifier, per device
python3 rats/appraise.py appraise bench/data/w5-tamper-20260910T092621Z/t0_clean.decode.txt
echo $?     # 0 pass · 1 fail · 2 could not tell

# every arm at once, against what each one must produce
python3 rats/appraise.py matrix --check
```

### Step ① is the one that is easy to leave out

A reference value nobody checked the signature of is a text file. It says the
firmware digest should be `8d53…` and the reason to believe it is that it was
in a directory. **The endorsement is what makes it evidence rather than
configuration**, and the pipeline is ordered so that nothing downstream runs
until it verifies.

`kid` — the key identifier in the COSE protected header — is the field that
matters in a real deployment and the one that looks like decoration in a demo.
A verifier in a machine with a GPU, an SSD and a BMC holds reference values
from three different publishers, and `kid` is how it decides **which public key
to check this manifest with**. Here it is `42` and there is one publisher, which
is exactly why the field is worth explaining rather than showing.

`ES256` is ECDSA over P-256 with SHA-256, COSE algorithm `-7`. It is what
DMTF's sample uses, and matching it is what makes the interoperability
comparison in [§6](#6-two-implementations-made-to-agree) possible.

### Step ③ is where a whole class of mistake lives

<!-- capture: bench/data/w5-tamper-20260910T092621Z/t0_clean.decode.txt -->

The evidence is the
<!--claim layout.measurement_record.record_bytes=528-->528-byte measurement
record sliced out of the `MEASUREMENTS` message —
<!--claim layout.measurement_record.blocks_walked=8-->8 blocks, walked and
closed exactly, hashing to
<!--claim layout.measurement_record.sha256=f2a14684e8fae9ff0e3ebff2a380f435c0fee5b0c8199d3fdfed31b2252f51d8-->`f2a14684e8fae9ff…`.

The obvious alternative is `device/measurements.bin`, and it is wrong in a way
that is invisible:

- it is **this project's own container format** (`MSR1`), not DSP0274's
  measurement-block encoding, so a DMTF tool parsing it reads noise;
- it holds four of the responder's eight blocks;
- and above all, **it is the file the responder read, not the message it
  sent.** A reference value derived from it, compared against evidence derived
  from it, is an identity. It passes for every input, including a tampered one,
  because the tamper is in both halves.

The point of RATS is that evidence *travels*: the Attester produces it, SPDM
conveys it, the Verifier appraises it. A pipeline fed the Attester's input file
has deleted the conveyance and is testing nothing.

### And the independent variable is read, never asserted

<!--claim algorithms.negotiated.MeasHash=SHA_512-->`SHA_512` is what the
responder selected, read out of the `ALGORITHMS` response by
`harness/fields.py`. It is not a `--alg` flag. A reference value minted under an
algorithm the device did not negotiate compares SHA-512 digests against SHA-384
ones and fails for a reason that has nothing to do with the device —
[roadmap standing rule 8](roadmap.md#standing-rules), and 2026-08-17 in
[`LOG.md`](../LOG.md) is what ignoring it cost the first time.

---

## 3. Table 3 — the appraisal, over every arm

Ten controlled arms, one reference value, one policy. The left half is
[`tamper.md`](tamper.md)'s result — what the **handshake** did — and the right
half is what the **appraisal** says about the same captures.

| # | what changed | where | SPDM handshake | appraisal | blocked by |
|:--|---|---|---|:--|---|
| `t0_clean` | nothing | — | completed | **PASS** | |
| `t0_none` | no fixture at all | device | completed | **PASS** | |
| `t0_proxy` | nothing, via the proxy | wire | completed | **PASS** | |
| **`t1_meas`** | **a measurement value** | **device** | **completed, no status** | **FAIL** | `SPDM_HASH_CHECK`, index 1 |
| `t2a_record` | the measurement record | in flight | refused `80020001` | **FAIL** | `SPDM_HASH_CHECK`, index 1 |
| **`t2b_sig`** | **the signature** | in flight | refused `80020001` | **PASS** | |
| `t3_cert` | a certificate | device disk | never sent, `8001000a` | *no evidence* | |
| `t3b_foreign` | *whose* certificate | device disk | completed | **PASS** | |
| `svn5` | secure version number → 5 | device | completed | **FAIL** | `SPDM_SVN_CHECK`, index 16 |
| `svn9` | secure version number → 9 | device | completed | **FAIL** | `SPDM_SVN_CHECK`, index 16 |

Produced by `python3 rats/appraise.py matrix`; every verdict is committed in
[`rats/out/`](../rats/out) and re-derived by CI.

### Row `t1_meas` is the one the gate exists for

Nothing in the handshake refused it and the appraisal names the index. The
device's own value for measurement index 1 hashes to

<!-- capture: bench/data/w5-tamper-20260910T092621Z/t1_meas.decode.txt -->
<!--claim layout.measurement_record.blocks.0x01.value_sha256=62f6b527048a88b212dee2519ebbd9a5f23e99e9e3824403745af3879327f11f-->`62f6b527048a88b2…`

where the reference value says `5ba8569b56df00a7…`. One byte of difference,
one line of verdict, and a non-zero exit code.

### Rows `t2a_record` and `t2b_sig` answer a question the status code could not

Both were refused by SPDM with the **same** status, `80020001` `VERIF_FAIL`.
README.md has said since week five that an integrator triaging from that log
line cannot tell a corrupted device from a corrupted link, and that the two have
completely different responses — one is a supply chain, the other is a cable.

The appraisal separates them, because `t2b_sig`'s measurement record is the
control's **byte for byte**:

<!-- capture: bench/data/w5-tamper-20260910T092621Z/t2b_sig.decode.txt -->
<!--claim layout.measurement_record.sha256=f2a14684e8fae9ff0e3ebff2a380f435c0fee5b0c8199d3fdfed31b2252f51d8-->`f2a14684e8fae9ff…`

Two one-bit answers, three distinguishable states:

| SPDM | appraisal | what it means |
|---|---|---|
| refused | FAIL | the content that arrived is wrong **and** unsigned for |
| refused | PASS | the measurement is right; the **conveyance** broke |
| completed | FAIL | the conveyance is fine; the **device** is wrong |

> ⚠ **What this costs in a real deployment, stated rather than glossed.** A
> requester that rejects a `MEASUREMENTS` message discards it. The middle row
> above is only available here because the capture holds the message the
> requester threw away. Getting that in production means a verifier that is
> handed the record even when the signature check failed — which is a design
> decision with its own risks, not a free consequence of this table.

### Row `t3b_foreign` passes, and that is the right answer

A well-formed certificate chain from an authority the requester was never given,
serving **correct** measurements. The handshake completed and the appraisal
passes, and both are right: the measurements really are the reference values.

What is wrong is *whose device it is*, and that is an identity question. Neither
layer here answers it. libspdm does compute the answer —
`LIBSPDM_STATUS_VERIF_NO_AUTHORITY` — and hands it to the application, and the
sample application does not look
([`upstream/README.md`](upstream/README.md)). Putting the trust anchor into the
appraisal is a natural extension and is not done: this policy appraises
measurements, and saying so is better than a policy that half-appraises
identity.

### Rows `svn5` and `svn9` are both wrong on purpose

Both fail, with the same check and the same message. A rollback to 5 and an
upgrade to 9 are the same answer, which is exactly what a rollback rule exists
to distinguish. The policy compares the secure version number for **equality**,
which is what DMTF's sample does, and week 7 changes it to
`evidence >= reference` with four cases — the fourth of which has to prove that
loosening the version rule did not loosen the integrity rule. This table is the
before.

---

## 4. What the appraisal cannot see

<!-- capture: bench/data/w5-tamper-20260910T092621Z/t0_clean.decode.txt -->

Six of the eight blocks become evidence. Two cannot be represented at all:

| index | what it is | bytes | why not |
|---|---|--:|---|
| `0xfd` | `MEASUREMENT_MANIFEST` | <!--claim layout.measurement_record.blocks.0xfd.value_bytes=128-->128 | a raw bit stream that is not a secure version number |
| `0xfe` | `DEVICE_MODE` | <!--claim layout.measurement_record.blocks.0xfe.value_bytes=16-->16 | the same |

DMTF's evidence format has two encodings — a digest, and a secure version
number — and `SpdmMeasurement.py` walks past anything else without comment.
This project reproduces that behaviour, because interoperability is the point,
and then **counts what it dropped**: every verdict carries a coverage line, and
`6 of 8 blocks appraisable` is printed beside `PASS`.

`DEVICE_MODE` is the sharper loss. Its value here is
<!--claim layout.measurement_record.blocks.0xfe.value_hex=3f000000040000001f00000011000000-->`3f000000 04000000 1f000000 11000000`,
and DSP0274 defines those words as the device's operational and device-mode
capabilities — **including whether it is in a debug mode**. No policy
expressible in this evidence format can read it. "This device passed" and "this
device passed the part of itself anything can look at" are different sentences,
and a coverage number is the difference.

---

## 5. The policy, and what the published sample does not check

DMTF ships `SpdmSamplePolicy.rego` beside the tools. It is 40 lines and it asks
two questions, and the way it asks them is the reason this project wrote its
own. It collects evidence digests into a **set**, reference digests into a
**set**, and compares the two sets.

Measured against the real file, under `--v0-compatible`, by
[`rats/interop.sh`](../rats/interop.sh):

| input | sample policy | [`rats/policy.rego`](../rats/policy.rego) |
|---|---|---|
| the clean capture | pass | pass |
| **indices 1 and 2 swapped** | **PASS** | fail — `digest_mismatch` |
| **a device that measured nothing, against a reference that names nothing** | **PASS** | fail — `REFERENCE_PRESENT` |
| a digest changed | fail | fail |

**The swap is the sharp one.** Index 1 is the immutable ROM and index 2 is the
mutable firmware. Present the firmware digest as the ROM digest and the multiset
of digests is unchanged, so a set comparison sees nothing — while the device has
said something false about which parts of it can change. The index is *in the
CoMID*, as `comid_class.comid_index`; the sample reads it and discards it.

**The empty pair is the one that fails open**, and stating it correctly took a
failing self-test. The first version of `rats/rats_selftest.py` claimed set
comparison passes *any* empty reference, reasoning that `set() == set()`. It
does not: with real evidence the two sets differ and the sample refuses. The
hole is narrower and worse — **both** sides empty, which is a device that
answered `GET_MEASUREMENTS` with nothing, declared good.

Two more, which follow from the same shape:

- **duplicates collapse.** A reference naming two indices is satisfied by
  evidence naming one, if the values coincide. (The sample does catch the
  version of this in the self-test, and saying which of the four it catches is
  the difference between a criticism and a slogan.)
- **the digest algorithm is carried on both sides and compared on neither.**
  Evidence says `[8, "<hex>"]`, the reference says `["sha512", "<hex>"]`, and
  both policies read element `[1]`. This one normalises the identifier and
  requires it to agree.

None of this makes the sample wrong for what it is — a demonstration that three
tools connect. It makes it the wrong thing to ship a verdict from.

### Rego v1

`SpdmSamplePolicy.rego` is Rego **v0**. OPA made v1 the default in 1.0, and on
`opa 1.20.2` the file produces **eleven** `rego_parse_error` messages and
evaluates only under `--v0-compatible`. The readme documents a bare `opa eval`
and mentions no version. `rats/policy.rego` is v1.

Which is why the engine is pinned along with the decoder and the builds:
[`third_party/opa.pin`](../third_party/opa.pin). Every verdict in `rats/out/`
was produced by `opa` evaluating this policy, and a verdict whose producer has
no recorded version has half a provenance. The pinned field that is *checked* is
`rego-version=` rather than the release number — a patch release of OPA is
nobody's problem, and a different policy language is.

### Failing closed

Every check begins `default X := false`, and every rule body that could be
undefined is arranged so undefined means false. An evidence document with no
`evidences` key, a reference whose path does not exist, an algorithm identifier
outside the table: all of them make a check **false** rather than absent. A
policy whose failure mode is "the rule was undefined so nothing was reported" is
the one that says PASS on the day something unexpected arrives.

And the verdict distinguishes three answers, not two:

| exit | meaning |
|:--:|---|
| 0 | the appraisal **passed** |
| 1 | the appraisal **failed** — a verdict |
| 2 | the appraisal could not be performed — bad input, no policy engine, the endorsement did not verify |

1 and 2 are kept apart deliberately. "The device is bad" and "I could not tell"
are different answers, and a pipeline that conflates them reports a broken
verifier as a failed device. The tool this replaced exits 0 for all three.

---

## 6. Two implementations, made to agree

> The decision — use DMTF's tools, write our own, or both required to agree —
> with the three options and what the chosen one costs:
> [`docs/decisions/0007`](decisions/0007-a-second-implementation-made-to-agree.md).

`rats/` is a second implementation of a format somebody else defined, and a
second implementation that has never been compared against the first is a guess
with good documentation — the guess would not be visible, because this project's
policy would accept this project's reference values forever.

So [`rats/interop.sh`](../rats/interop.sh) runs both and requires them to agree.
[`rats/interop/report.md`](../rats/interop/report.md) is the run;
[`harness/verify_repo.sh`](../harness/verify_repo.sh) re-derives this side
against the committed outputs on every push, on a runner that has no `spdm-emu`
checkout.

| comparison | result |
|---|---|
| `SpdmMeasurement.py meas_to_json` vs `appraise.py evidence` | identical, apart from the final newline DMTF's writer omits |
| `CoRimTool.py json_to_cbor` vs `appraise.py to-cbor` | **byte-identical, 1480 bytes** |
| `cose.py verify` on `CoRimTool.py sign`'s output | accepted |
| `CoRimTool.py verify` (patched) on `cose.py sign`'s output | accepted |

Getting there found three differences. Two were this project's:

- **a signed CoRIM is `#6.500(#6.502(COSE_Sign1))`**, per
  draft-ietf-rats-corim, and this project wrote a bare `#6.18`. Each tool
  rejected the other's file before it looked at a signature.
- **the algorithm identifier**: this project wrote `"sha512"` where DMTF's own
  sample manifest writes `8`. Both are readable; only one of them encodes to the
  same bytes through their tool. See below for why that is a difference at all.

The third was not.

---

## 7. What had to be worked around, and what was reported

Running the published example verbatim was the first thing done this week, and
it does not work. The findings are in
[`docs/upstream/README.md`](upstream/README.md) with their reproductions; in
summary, and in the order they block someone:

| # | where | what |
|:--|---|---|
| 1 | `requirements.txt` | no upper bounds. `cbor2` ≥ 6.0 decodes a `CBORTag`'s contents as **immutable** containers; `pycose` type-checks for `list`/`dict`. Measured: **pycose cannot decode its own `encode()` output** — 79 bytes, byte-identical through the round trip, `TypeError`. `cbor2==5.6.5` works |
| **2a** | `CoRimTool.py:209` | `verify` builds the key as `EC2Key(crv='P_256', d=<the 64-byte public point>)` — the public key where the private scalar goes. `EC2Key` raises, the `except` catches it, and the tool reports a verification that never happened. **It has never verified a signature** |
| **2b** | `CoRimTool.py:214` | `verify_signature()` **returns a bool**, and the return value is discarded. With 2a repaired and this left alone, a corrupted signature prints `Signature verification passed` and the payload is written |
| 3 | `CoRimTool.py` | `cbor_to_json` writes the container tags as JSON keys and `json_to_cbor` has no entry for them: `KeyError: 'corim'`. Reproduces on the sample manifest that ships beside the tool |
| 4 | `CoRimTool.py:190` | `translate_data` maps exactly two name strings to integers — `comid_tag_creator` and `sha256` — hard-coded where a table lookup was intended. A CoMID naming `sha512` encodes its algorithm as text, 43 bytes larger |
| 5 | `CoRimTool.py:215` | `verify` prints `Signature verification failed` and **exits 0** |
| 6 | `SpdmSamplePolicy.rego` | Rego v0, eleven parse errors on OPA ≥ 1.0, no version note in the readme |

### 2a and 2b are one change, and that is the most useful thing this week produced

The pull request fixes both, and the reason is not tidiness. **A one-line fix
for 2a was written, committed, signed off, and one keystroke from being sent.**
It was caught by a script written to re-run the `Tested:` claims of a commit
message that already existed — and the last of those claims, *"a corrupted
signature is still refused"*, was false.

With 2a repaired and 2b not, flipping the last byte of a 64-byte signature
still printed `Signature verification passed` and still wrote the payload. The
obviously-correct fix, applied alone, converts a verifier that **accepts
nothing** into one that **accepts anything**.

`rats/interop.sh` now keeps a half-patched copy beside the patched one and
asserts that the half-patched one accepts a forged signature. The story is not
the mechanism; the check is.

**Is this a security issue?** Not as shipped, and the reasoning is the
deliverable rather than the answer. 2a fails **closed** — it refuses valid
signatures and never accepts invalid ones — so no deployed system can be
holding a forged manifest this tool approved. 2b is the direction that would
matter, and it is **not reachable today** precisely because 2a stops execution
first. Number 5 is a third, weaker version of the same concern about the exit
code. All of it is in a tool whose own readme calls it a sample and whose keys
say *do NOT use in any production*, so a public pull request is the right
channel — and the responsible part of that is making sure the change does not
*create* the hole, which is exactly what fixing both lines together is for. If
any of it had been reachable as a fail-open in shipping code, the channel would
have been DMTF's security reporting process and this table would not exist.

Numbers 1, 3, 4, 5 and 6 are recorded with their reproductions and are not
bundled; six unrelated fixes in a first pull request to a repository where
nobody knows you is how a first pull request does not land.

---

## 8. What CI asserts

Stated as a negative, because that is the form that can fail usefully:

> A **tampered** measurement must be **rejected**, and the build must turn red
> if it stops being.

The [`rats` job](../.github/workflows/ci.yml) runs four things:

1. the encoders, against RFC 8949's own vectors — 106 checks;
2. the policy, against eleven broken pairs, each of which must be refused **and
   must name its own reason**, with every one of the eight failure categories
   provoked by some case;
3. the ten-arm matrix against [`rats/out/expected.json`](../rats/out/expected.json);
4. and the exit code, in both directions — clean must exit 0, tampered must
   exit 1.

`expected.json` is deliberately not a snapshot of a previous run. A check that
only says *the same as last time* keeps passing after the policy is accidentally
disabled, because a policy that passes everything reproduces perfectly. Each arm
states the outcome it must have and the sentence that makes it the right one,
and an arm that appears in the run and not in the file is a failure rather than
a skip.

---

## 9. What is still missing

| | |
|---|---|
| the rollback rule | `evidence >= reference`, with four cases including one that proves the integrity half did not loosen. **Week 7** |
| a reference value with independent provenance | see §1. The publisher and the device are the same person here |
| the trust anchor in the appraisal | `t3b_foreign` passes, and an identity check is what would refuse it |
| `MEASUREMENT_MANIFEST` and `DEVICE_MODE` | no evidence encoding exists; §4 |
| freshness | `CHALLENGE`'s nonce proves the device held the key when it signed, not that the firmware did not change one second later |

---

*Every number in this document is marked up and re-derived from the capture it
names by `harness/fields.py --check`, which CI runs. A number here that drifts
from its capture is a failed build.*

# A signature over the wrong bytes — DSP0274 1.4.0, and what 1.4.1 changed

> **This project performs protocol-level correctness validation. It is not a
> security assessment.** This page is a reading of two published specification
> documents and one published advisory, all three fixed and none of them found
> here. What is this project's own is the reading, the diff, and the test that
> encodes the class.

| | |
|---|---|
| advisory | `GHSA-chjj-xvqx-c8w4` = **CVE-2026-61810** = DMTF-2026-0003, published 2026-07-03 — [`third_party/dmtf-2026-0003.pin`](../third_party/dmtf-2026-0003.pin) |
| specifications | DSP0274 **1.4.0** ([`dsp0274.pin`](../third_party/dsp0274.pin)) and **1.4.1** ([`dsp0274-1.4.1.pin`](../third_party/dsp0274-1.4.1.pin), sha256 `a5259037e0853913efc0efd07358669a4bcfc630d3a61eb1cf09e3758db057b6`) |
| the class, as a test | [`negative/test_transcript_coverage.c`](../negative/test_transcript_coverage.c) — 8 cases, 6 defect variants |
| why two pins | [ADR 0011](decisions/0011-two-versions-of-one-specification.md) |

---

## 1. What a transcript is, in one paragraph

SPDM messages are not signed one at a time. A signature near the end of a
handshake is computed over a **transcript**: every message exchanged so far,
concatenated in the order it was sent. That is what makes the signature worth
anything — it is not a statement that *this message* is authentic, it is a
statement that **the whole conversation happened the way both ends think it
did**. Change any message an attacker can reach, and the signature stops
verifying, because the bytes that went into it changed.

Which gives the property the whole design rests on, and the sentence to keep:

> **A signature is worth exactly the bytes it covers.**

If a message is accepted into the conversation and **not** appended to the
transcript, then an attacker who changes that message changes nothing any
signature covers. The signature still verifies. The handshake completes. The
verifier is satisfied — and the thing it was satisfied about is not what
happened.

---

## 2. What SPDM 1.4 changed, and what it did not

SPDM 1.4 added two fields to the `FINISH` request (Table 80) and to
`FINISH_RSP` (Table 81), and it put them **before** the trailing signature:

```
  offset 0                              SPDMVersion          ┐
  offset 1                              RequestResponseCode  │  SPDM Header Fields
  offset 2                              Param1               │   — four bytes, and
  offset 3                              Param2               ┘     that is all
  offset 4                              OpaqueDataLength     ← new in 1.4
  offset 6                              OpaqueData           ← new in 1.4
  offset 6 + OpaqueDataLength           Signature            ← signs the transcript
  offset 6 + SigLen + OpaqueDataLength  RequesterVerifyData  ← HMAC over the transcript hash
```

Five transcript definitions were not updated to match. All five ended at *"the
SPDM Header Fields"*, which per DSP0274 is those four bytes and nothing else.

**So under a literal reading, `OpaqueDataLength` and `OpaqueData` are
transmitted before the signature and are not covered by it.** An active
attacker on the bus can change them in flight, and both the signature and the
HMAC still verify.

---

## 3. The five definitions, in both versions

Extracted with `pdftotext -layout` from the two pinned PDFs. The phrase
`[FINISH].SPDM Header Fields` (and its `FINISH_RSP` spelling) occurs **five
times in 1.4.0 and zero times in 1.4.1** — the same count the advisory gives
for affected definitions, arrived at from the documents rather than from the
advisory.

| # | definition (internal anchor) | **1.4.0** — the last step | **1.4.1** — the last step |
|:-:|---|---|---|
| 1 | FINISH signature, mutual auth (`definition_th_fi_req_mut`) | `8. [FINISH] . SPDM Header Fields` | `8. [FINISH] . * except the Signature and RequesterVerifyData fields.` |
| 2 | FINISH HMAC, Responder-only (`definition_th_fi_req_vf`) | `6. [FINISH] . SPDM Header Fields` | `6. [FINISH] . * except the Signature and RequesterVerifyData fields.` |
| 3 | FINISH HMAC, mutual auth (`definition_th_fi_req_vf_mut`) | `8. [FINISH] . SPDM Header Fields`<br>`9. [FINISH] . Signature` | `8. [FINISH] . * except the RequesterVerifyData field.` |
| 4 | FINISH_RSP HMAC, Responder-only (`definition_th_fi_res_vf`) | `7. [FINISH_RSP] . SPDM Header fields` | `7. [FINISH_RSP] . * except the ResponderVerifyData field.` |
| 5 | FINISH_RSP HMAC, mutual auth (`definition_th_fi_res_vf_mut`) | `9. [FINISH_RSP] . SPDM Header fields` | `9. [FINISH_RSP] . * except the ResponderVerifyData field.` |

Definition 3 is worth a second look. In 1.4.0 it enumerates the header, then
skips straight to the *signature* — so the HMAC covered the signature and not
the opaque data that was transmitted between them. **The enumeration was not
even contiguous**, and nothing in the document's own form made that visible.

---

## 4. ★★ The fix is not a field. It is a change of shape.

1.4.0 enumerated what the transcript **includes**. 1.4.1 names what it
**excludes**.

| | |
|---|---|
| **an enumeration** | has to be revisited every time the message changes, and *nothing forces that to happen* |
| **an exclusion** | is correct by construction for a field that does not exist yet |

That is the entire lesson, and it generalises far past SPDM. Any rule of the
form "hash these parts" acquires a maintenance obligation in a different file
from the one that defines the message. Any rule of the form "hash all of it
except the authenticator" does not.

### ★★★ And the enumeration was not wrong when it was written

In SPDM **1.3**, a `FINISH` was a four-byte header followed by its
authenticator. There was nothing in between. *"The SPDM Header Fields"* really
was everything a signature had to cover, and definition 1 was exactly right.

It became wrong when somebody edited **Table 80**.

> **A correct sentence was made false at a distance, by a change in another
> chapter, with no mechanism watching the join.**

That is the class, and it is why this one is the odd member of the three in
[`negative/`](../negative/). The other two are memory safety: a sanitizer finds
them, a fuzzer reaches them, a compiler warning sometimes hints at them. Here
every line executes correctly, nothing is out of bounds, and the result is
wrong — because **the defect is in the specification, so every implementation
that follows it correctly has it**, and no amount of reviewing the
implementation finds it. What has to be reviewed is the document.

Cases 4, 5 and 6 of `test_transcript_coverage.c` are that story, run: the same
1.4.0-shaped rule over a 1.3 message (passes) and a 1.4 message (fails), and
then the 1.4.1-shaped rule over the 1.4 message (passes). **One rule is right
once; the other is right twice.**

---

## 5. Reading the score, and reading the vector

```
CVSS:4.0/AV:A/AC:L/AT:P/PR:N/UI:N/VC:N/VI:H/VA:N/SC:N/SI:N/SA:N     base 6.0
```

The score is looked up. The vector is understood, and it is worth more:

| | |
|---|---|
| `VC:N` / **`VI:H`** / `VA:N` | **integrity only.** Nothing is disclosed and nothing stops working — an attacker rewrites data that both ends believe was authenticated |
| `AV:A` | **adjacent.** The attacker has to be on the same bus, not on the internet |
| `AT:P` | the attack needs a condition the attacker does not control — here, being in the middle at the right moment |
| `PR:N` / `UI:N` | no credentials, no human |

`VI:H` with `AV:A` is why it is 6.0 rather than higher, and it is also why it
matters for a device: the bus is exactly where a management controller lives.

★ And it is the **lowest** score of the three 2026 advisories while being the
only one with a CVE. `docs/advisories.md` §1.1 has that comparison.

---

## 6. What this project did, and what it did not

**Did.** Fetched both specification versions, hashed them, pinned them, read
sections 633–644 of each, and diffed all five definitions. Fetched the advisory
from its primary source, pinned the retrieval, and found that its CVE was not
in NVD or in MITRE's CVE Services. Wrote the class as a test with a
calibration, eight cases and six defect variants, every one of which must move
exactly the cases the file predicts.

**Did not.** Discover it, report it, or implement the fix. It was reported on
`DMTF/libspdm` issue 3633 on 2026-06-02, and the specification was repaired in
1.4.1.

**Could not, until a census found it.** Observe it on the wire. This paragraph
said *"nothing in this project has ever established a secure session, so there
is no `FINISH` here"*, and that was wrong about this repository's own evidence.
`bench/data/healthcheck-pqc-20260811T052725Z/minimal.pcap`, the week-1 run that
left `--exe_session` at its default, holds a **mutually authenticated SPDM 1.4
`FINISH`** between the two libspdm emulators — `SigIncl=1` — and nothing had
decoded it (corrected 2026-09-23; [`advisories.md`](advisories.md) §3.5). Both
ends are libspdm, so the handshake completing shows they agree, not which
definition they follow. libspdm's requester appends the header,
`OpaqueDataLength` and `OpaqueData` before it signs, which is 1.4.1's meaning;
verifying that one signature over both candidate transcripts would turn that
reading into a measurement. `test_transcript_coverage.c` models the rule in
the meantime. The real transcript arithmetic this project does
own is `harness/challenge_verify.py`, which rebuilds `M1M2` from a capture and
hands it to OpenSSL; that tool cannot be this one, because its transcript is
never allowed to be wrong.

---

## 7. The one thing the test asserts that the documents cannot

A transcript with a message missing **must still verify.** Signer and verifier
run the same rule, so they agree; that is precisely why nobody notices.

`test_transcript_coverage.c` prints that before it asserts anything else, and
refuses to continue if it stops being true:

```
  calibration
    the complete transcript, one byte of KEY_EXCHANGE changed:
      53ff89f884bebb4b -> d79b146732b793ab   the signature breaks
    the transcript with KEY_EXCHANGE missing, same change:
      e9e707aecab3bf9b -> e9e707aecab3bf9b   UNCHANGED — it still verifies
```

Without that line, every case below it would be detecting a **broken**
signature rather than an **incomplete** one — which is the difference between
this class and no class at all. It is the same discipline as
`harness/challenge_verify.py`'s calibration, which verifies the nine
connections a conformance suite passes before reporting on the two it fails:
**an instrument answers a known question before it is believed on an unknown
one.**

---

## 8. Reproducing it

```bash
# the two documents, and the count that has to come out five and zero
pdftotext -layout "$LAB_DIR/spec/dsp0274_140.pdf" - | grep -c 'SPDM Header [Ff]ields'   # 5
pdftotext -layout "$LAB_DIR/spec/dsp0274_141.pdf" - | grep -c 'SPDM Header [Ff]ields'   # 0

# the class, with every defect variant
cd negative && make test

# what the file asserts, and what each defect must move
./test_transcript_coverage --list
```

Neither PDF is in this repository — they are not ours to redistribute. Both are
pinned by digest, and `harness/verify_repo.sh` requires this document to carry
the digest of the one it quotes.

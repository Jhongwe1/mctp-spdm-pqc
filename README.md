# SPDM Device Attestation Lab

A measurable, reproducible SPDM device-attestation pipeline built on DMTF's
reference implementations (`libspdm`, `spdm-emu`): a full requester/responder
handshake, three-point tamper detection, RATS reference-value comparison, and a
byte-level cost comparison of post-quantum algorithms against classical ones.

> ### ⚠️ Scope
>
> **This project performs protocol-level correctness validation.**
> **It is not a security assessment.**
>
> It answers questions of the form "does this flow behave as specified, and what
> does it cost in bytes and round trips". It does not answer "is this system
> secure". No threat model is claimed beyond the one written down in
> [`docs/threat-scope.md`](docs/threat-scope.md), no cryptographic review was
> performed, and the tamper cases exercised here are ones the author
> constructed, not ones an adversary chose.
>
> This statement is deliberately placed above the build badge. What a project
> declines to claim is a more reliable signal than what it claims.

![CI](https://github.com/Jhongwe1/mctp-spdm-pqc/actions/workflows/ci.yml/badge.svg)

---

## Current status

This is week 4 of a 14-week programme. The table below is the truth about what
exists today, not what is planned. Planned work is in
[`docs/roadmap.md`](docs/roadmap.md), which carries the same table.

| Gate | Subject | State |
|:--|---|---|
| G0 | environment and version baseline | **complete** — see [`docs/env-baseline.md`](docs/env-baseline.md) |
| G1 | full handshake, field by field | **complete** — seven message pairs annotated against a capture, 164 values asserted by CI, four pairs whose offsets are reconstructed from the wire. What is still transcribed, and the three questions still open, are named in [§10](docs/handshake-walkthrough.md) |
| G2 | certificate chain, three tamper points | **in progress** — the chain, plus a tamper harness and **two of the three points measured** ([`docs/tamper.md`](docs/tamper.md)). Point 2 needs a proxy between the emulators and is absent rather than stubbed, so **Table 1 is incomplete** |
| G3 | RATS verification pipeline | not started — and week 4 measured why it is not optional |
| G4 | post-quantum cost quantification | not started |
| G5 | real transports (QEMU / AF_MCTP) | not started |
| G6 | conformance and negative testing | not started |
| G7 | upstream contribution | agreements and account done; **four** candidate changes with evidence, none submitted — the two newest each carry a committed capture. SPDM 1.5 hybrid-PQC review read and feedback drafted, not sent |
| G8 | delivery and write-up | not started |

Nothing in this repository reports a measurement that has not been made. A
table that does not exist yet is absent rather than sketched.

### What week 4 established

**A byte was changed in a device's own measurement, and SPDM did not notice.**
That is not a defect. It is the boundary of what the protocol claims, and it is
the reason Gate 3 exists.

`libspdm`'s sample device secret library invents its measurements — index 1 is
the SHA-512 of 72 bytes of `0x01`, and the secure version number is the constant
`0x7` — so before anything could be tampered with, the values had to become an
input. [`device/`](device/) does that in **sixteen added lines of upstream, three
of which are code**:

```c
    libspdm_set_mem(data, sizeof(data), (uint8_t)(measurements_index));
+   (void)ms_get_block(measurements_index, data, sizeof(data));

    svn = 0x7;
+   (void)ms_get_svn(&svn);
```

Both sit on the line *after* upstream computes its own value and leave the
buffer alone when they decline, so the diff is purely additive and hashing,
block assembly and signing are untouched. What a capture measures is still
libspdm's behaviour.

Then one byte of measurement index 1's pre-image was flipped:

| | `t0_clean` | `t1_meas` | `t3_cert` | `t3b_foreign` |
|---|--:|--:|--:|--:|
| `CERTIFICATE` messages | 3 | 3 | **0** | 3 |
| `CHALLENGE_AUTH` | 1 | 1 | **0** | 1 |
| measurement record | 528 B | 528 B | — | 528 B |
| blocks that changed | — | **1 of 8** | — | 0 |
| requester exit | 0 | **0** | 1 | **0** |

**`t1_meas` completed.** Every signature verified, because the responder signs
the record it actually sent — change what it reads and it signs the new value.
For a signature check to fail, the bytes signed and the bytes verified have to
differ, and changing the source is not one of the two ways to arrange that. The
certificate chain is different only because the requester holds an anchor it was
given out of band; there is no equivalent for a measurement.

> SPDM proves a measurement came from this device. It does not prove the
> measurement is correct. The second needs reference values, and reference
> values are not in the protocol.

**`t3_cert` failed earlier than expected, and for a different reason than
expected.** One byte inside the intermediate certificate's own ECDSA `s` value —
located by `certs/check_chain.py --locate`, so the certificate still parses and
exactly one link breaks. The obvious sentence is "the requester rejected the
chain". The capture refutes it: there is **no `CERTIFICATE` message at all**, and
`ProvisionedSlotMask` drops from `0x13` to `0x12`. The responder validates its
own chain when it loads it, could not, and stopped advertising the slot. A byte
flipped on the device's disk cannot reach the requester's verifier.

**So a case had to be added, and it is the one that did not fail.**
`t3b_foreign` serves a chain that is internally perfect and belongs to somebody
else — DMTF's own root, while the requester is configured to trust this
project's. The handshake **completed**. libspdm detects it and reports
`LIBSPDM_STATUS_VERIF_NO_AUTHORITY`, which is `SEVERITY_WARNING`; the sample
requester tests `LIBSPDM_STATUS_IS_ERROR` and a warning is not an error. That is
a deliberate hand-off to the integrator, and the transferable half is:

> An integrator who checks only `IS_ERROR` has accepted every certificate chain
> that parses.

The same acceptance is visible in a capture committed a week earlier: slot 4's
chain, root `ed79ce9a…`, is in neither of the two roots the requester was
provisioned with, and nothing minded.

**The secure version number now takes more than one value on the wire** — 5, 7
and 9, each changing exactly one of the eight measurement blocks. Gate 3's
rollback rule cannot be tested against a constant, and until this week it was
one.

Two new tools, and both exist to disagree with something.
[`bench/pcapstat.py`](bench/pcapstat.py) walks the capture file itself and
totals bytes per message type; `fields.py` reaches the same totals from
`spdm_dump`'s output. Neither opens the other's input, and CI requires them to
agree across **43 captures** — eighteen equations on the walkthrough instead of
one. The one capture where they cannot agree measures something new: the
reference decoder sees **12.0%** of the post-quantum capture, 13,441 SPDM bytes
of 111,831.

Full write-up, with every number re-derived from its capture on every CI run:
[`docs/tamper.md`](docs/tamper.md).

### What week 3 established

**A certificate chain that predicted its own size on the wire, before it was
sent.** `certs/gen_chain.sh` builds a three-layer chain — root, intermediate,
leaf — and `certs/check_chain.py` computes what SPDM will carry from the files
on disk:

```
4 + 48 + (504 + 573 + 768)  =  1897 bytes
```

Then the handshake ran, and `harness/fields.py` read **1,897** out of the
capture, recovered **504 + 573 + 768** by walking DER, and confirmed that the
48-byte `RootHash` at offset 20 is `sha384` of the root certificate. Neither
tool was told the other's answer: `check_chain.py` never opens a capture,
`fields.py` never opens a certificate.

**`CERTIFICATE` is now over-determined by three equations, not one.** Week 2
rebuilt `CHALLENGE_AUTH` and `MEASUREMENTS` and required each to close on one
spare equation. This message has four, and no two share an input:

| | equation | checked against |
|---|---|---|
| closure | message length = 16 + `LargePortionLength` | the hex dump |
| agreement | chain `Length` = `PortionLength` + `RemainderLength` | three fields the responder wrote separately |
| structure | the certificates parse as DER `SEQUENCE`s consuming the chain exactly | nothing else |
| **digest** | `RootHash` = SHA-384 of the first certificate | computed, from bytes in the same message |

The fourth is the one worth having. Two lengths can agree because both came from
the same wrong assumption; a 48-byte digest cannot. CI breaks the reconstruction
four ways and requires four *different* checks to reject them.

**And the chain found something it was not built to find.** Replacing the
responder's chain replaced one of **three** trust anchors that a single
mutually-authenticating handshake carries:

| packet | direction | slot | bytes | root |
|--:|---|--:|--:|---|
| 10 | RSP→REQ | 0 | 1,897 | mine |
| 12 | RSP→REQ | 4 | 1,660 | upstream's `ecp384` root |
| 19 | REQ→RSP | 0 | 3,794 | upstream's `rsa3072` root |

SPDM negotiates the requester's signature algorithm separately, and libspdm's
sample library picks its certificate directory from the negotiated algorithm —
so a chain installed for `ECDSA_P384` never serves the direction that settled on
`RSAPSS_3072`. The handshake completes, every signature verifies, and nothing in
the flow says which anchor was used. On a reference design, the one still in
place is the reference implementation's, whose private keys are published.

`fields.py` now reports `layout.distinct_root_hashes` so that count is
something CI checks rather than something someone noticed once. The full
write-up is [`docs/certchain.md`](docs/certchain.md).

**Two controlled arms, and both differences fully explained.** `sample-1slot`
and `selfsigned` differ in one thing — whose certificates the responder serves —
and `walkthrough` differs from `sample-1slot` in one flag:

| arm | packets | SPDM bytes | against the arm above |
|---|--:|--:|---|
| `walkthrough` | 30 | 11,291 | — |
| `sample-1slot` | 30 | 11,187 | **−104** = 2 × (48 + 4), two of the requester's slots dropped from `DIGESTS` |
| `selfsigned` | 30 | 11,671 | **+484** = 2 × (1,897 − 1,655), a larger chain fetched twice |

Both deltas are arithmetic the tool re-derives, not observations. `DIGESTS`'s
per-slot size is established by its own length under two hypotheses that differ
by four bytes per slot, exactly one of which can close.

**And the five original arms reproduced a fourth time.** 554/20,549,
584/114,751, 566/20,396, 30/11,441, 30/11,441 — identical on 08-16, 08-28,
08-31 and 09-01, to the packet, the last of those from a binary rebuilt twice in
between. The 528-byte measurement record inside them is identical too, and CI
now asserts that invariant over every baseline run rather than leaving it as a
remark: one SHA-256 across **fourteen arms in five runs**.

### What week 2 established

**The minimal handshake was 554 packets. 526 of them were one default flag, and
they carried the same bytes as a single message.**

| | `--meas_op ONE_BY_ONE` (default) | `--meas_op ALL` |
|---|--:|--:|
| packets | 554 | **30** |
| `GET_MEASUREMENTS` sent | 263 | **1** |
| `SPDM_ERROR(InvalidRequset)` received | 246 | **0** |
| measurement record delivered | **528 bytes** | **528 bytes** |

The last row is the result. Summing `MeasurementRecordLength` over the eight
measurement indices that exist gives 528; the single `ALL` response carries a
528-byte record. Both numbers are re-derived from their own captures by
[`harness/fields.py`](harness/fields.py) and asserted in CI, so the identity is
checked rather than argued.

Why the default behaves that way has three separate causes, and separating them
is the point: the **two-pass structure is required by the specification** (from
SPDM 1.2 an errored `MEASUREMENT` resets the L1/L2 transcript, so a requester
must learn which indices exist before building a signed one), **walking the
index space is the emulator's choice**, and **the early exit never fires**
because the sample responder's eight indices end at `0xFE`. Full derivation in
[`docs/handshake-walkthrough.md`](docs/handshake-walkthrough.md) §7.

**A field-by-field walkthrough whose numbers cannot rot.** Every value in that
document is marked up in its source and re-derived from the capture it cites by
`harness/fields.py --check`, which `harness/verify_repo.sh` and therefore CI
run. 128 claims across five captures at the end of week 2, 164 across seven
today. The mechanism was deliberately broken three
ways — a byte count off by one, a claim naming a field the tool does not
compute, a capture that has moved — and turns red on each.

**And its offsets are measured for two of the seven message pairs.** A value can
be re-derived from a decode; an offset cannot, because the decoder prints fields
rather than positions. So `CHALLENGE_AUTH` and `MEASUREMENTS` are **rebuilt**
instead — every field placed in turn, each size either constant, fixed by
something negotiated several messages earlier, or carried in the message itself
— and the reconstruction has to survive two independent contradictions:

| | |
|---|---|
| **closure** | the bytes left after placing everything up to the signature must equal the signature size the negotiated algorithm implies. The total comes from the hex dump, the size from `ALGORITHMS`; neither is in the document |
| **echo** | `RequesterContext` is chosen by the requester and returned unchanged, so it must be found at the predicted offset holding what the request sent — 130 bytes into the message, using no constant from the tool |

`CHALLENGE_AUTH` is 238 bytes, the nonce is at 52, and 238 − 142 = 96, which is
what ECDSA-P384 signs with. Being over-determined by one equation is the whole
point: CI rebuilds a correct message and three broken ones — a byte short, a
context that does not echo, a different signature algorithm — and requires each
break to be rejected.

The spare equation settled a question the document could not answer by reading:
`MeasurementSummaryHash` is sized by `BaseHashAlgo`, not `MeasurementHashAlgo`.
Both were negotiated here, they differ by 16 bytes, and only one closes.

**A tool checking 84 facts correctly was wrong by 40% in a field nobody quoted.**
`spdm_dump -x` prints a packet carrying mutual authentication as two hex blocks
— the encapsulated message first, then the carrier that already contains it byte
for byte — and `fields.py` summed both. The walkthrough capture's SPDM byte
total read 15,803 against an actual 11,291.

No published number moved, because every `message_bytes` claim in the document
happens to concern a message that is never encapsulated. That is the
uncomfortable part rather than the reassuring one: **the reach of a checking
mechanism is the set of facts someone chose to state, not the set the tool
produces.** Writing more claims would leave the next unquoted field in exactly
the same position, so the answer is a second tool that has to agree.
`harness/pcapcount.py` owns the capture file and never reads a decode;
`fields.py` owns the decode and never opens a capture. CI now requires

```
pcap captured bytes  ==  SPDM message bytes  +  5 × messages
```

— the five being the MCTP framing taken apart in
[`docs/transports.md`](docs/transports.md). Four captures satisfy it exactly;
the post-quantum arm is skipped and says why.

**The walkthrough is checked against a capture it was not written from.** Every
word of it was written on 2026-08-17 against one run. Eleven days later the five
arms were re-taken on the same pins, and all 128 claims of the time verify
against the new
one:

| arm | packets | bytes | reproduced |
|---|--:|--:|:--:|
| `classical` | 554 | 20,549 | ✅ |
| `pqc` | 584 | 114,751 | ✅ |
| `classical-stable` | 566 | 20,396 | ✅ |
| `walkthrough` | 30 | 11,441 | ✅ |
| `single-algo` | 30 | 11,441 | ✅ |

Identical on every arm, to the packet. Nonces and timestamps differ, as they
must; nothing this repository states about sizes, counts or offsets does. That
is why byte counts here are reported as single values rather than ranges — it is
now a measured property of these captures and not a convention.

The re-run happened for an unglamorous reason, and the reason is the more
transferable half. `capture.sh` writes a `*.fields.json` beside each capture and
hashes it into `manifest.json` next to the pcap — but a pcap is *evidence* and a
`fields.json` is a *derivation*, and when the tool that produced it changed, the
committed file became false while its hash still matched. **A digest tells you a
file is unaltered. It does not tell you the file is still true.** There is no
mechanism here for re-stamping a manifest and there should not be, so the repair
was a new run rather than an edited old one. CI now requires every committed
derivation to reproduce from its inputs; the reasoning and the four alternatives
rejected are in
[`docs/decisions/0004`](docs/decisions/0004-derivations-must-reproduce.md).

**A classical baseline is not build-independent.** Identical flags on
`spdm-emu` 3.8.0 and 4.0.0-rc differ in five measurable ways, including a
1,591-byte certificate chain against 1,655 and two round trips to fetch it
against one. Which build produced a number belongs beside the number.

### What week 1 established, revised by week 2

**A post-quantum certificate chain is ten times the size of a classical one,
and that changes the message flow rather than only the byte count.**

| | classical | post-quantum |
|---|---|---|
| negotiated signature algorithm | ECDSA-P384 | **ML-DSA-65** |
| negotiated key encapsulation | none | **ML-KEM-768** |
| certificate chain | 1,655 bytes | **16,853 bytes** |
| chunk round trips to fetch it | **0** | **4** |

Measured on the `pqc` build, which is what makes it a controlled comparison —
both arms from one binary, varying the algorithm. The chain exceeds the
negotiated `DataTransferSize` (4,608 bytes), so `GET_CERTIFICATE` is answered
with `SPDM_ERROR(LargeResponse)` and the exchange falls into SPDM's chunking
mechanism. **The classical path never executes that code.** On a real BMC
speaking MCTP over I²C, where the transfer unit is smaller again, that is the
part that would be felt.

Week 2 found the flaw in the week 1 version of this comparison and fixed it:
only the responder's algorithm had been pinned. SPDM negotiates the requester's
signature separately, and the responder had chosen ML-DSA-87 for it against
RSAPSS-3072 in the classical arm. Both directions are pinned now, in every arm.

**The reference decoder is not configured to read the reference emulator's
post-quantum output.** `spdm_dump` stops partway through with `cert_chain is too
larger`. Week 1 recorded that as its compile-time constant being too small; week
2 measured the constant — **4,096 bytes**, read out of the compiled binary by
bisecting the size of an input it validates before parsing, with no rebuild. The
chain it fails on is 16,853, and the same header selects 32,768 when ML-DSA
support is compiled in. The emulator that produced the capture is built from the
**same libspdm commit**. So this is build configuration, not version — a task
rather than a limitation, and the difference is worth the eight seconds it took
to establish.

Neither of these is Gate 4. They are observations from single runs, recorded
because they were seen, and they are what Gate 4 will have to measure properly.

## Getting started

Read [**RUNBOOK.md**](RUNBOOK.md). It goes from a clean machine to a completed
SPDM handshake with a capture file, and it states what correct output looks
like at every step so that a failure is recognisable as a failure.

The short version, on Ubuntu 24.04 or WSL2:

```bash
git clone https://github.com/Jhongwe1/mctp-spdm-pqc.git
cd mctp-spdm-pqc

bash harness/doctor.sh                     # prerequisites; changes nothing
bash harness/build_spdm_emu.sh pqc         # ~30 min, mostly downloading
bash harness/healthcheck.sh pqc --write-baseline
```

## How results are recorded

Every experiment writes into `bench/data/<run-id>/`, and every run directory
contains a `manifest.json` holding:

- the commit hashes of **every** upstream binary the run depended on — both
  emulator builds and `spdm_dump`, through which each capture is read
- the complete command lines that were executed, as executed
- compiler, OpenSSL, Python and kernel versions
- SHA-256 and byte count of every artifact in the directory
- whether the working tree was clean when the run happened

This is a mechanism rather than a convention. Any script that records a result
calls `prov_begin` and `prov_finish`
([`harness/lib/provenance.sh`](harness/lib/provenance.sh)), so a result cannot
be produced without being attributed. The reason is narrow and practical: a
number in a table is worth exactly as much as the reader's ability to find the
capture file it came from and check it.

Which is why `harness/verify_repo.sh` also checks that every artifact a manifest
attests to is **present and tracked**. It exists because that guarantee was
quietly broken: `.gitignore`'s `*.log` excluded twelve evidence files that three
manifests had already signed for, so a fresh clone received a promise it could
not check — while the mechanism reported success throughout. An ignore rule is
not allowed to outrank a manifest.

## Repository layout

```
harness/       build, capture, health-check and analysis scripts
  capture.sh   take a run's captures, all arms, with provenance
  tamper.sh    the tamper cases, as controlled pairs against a prior baseline
  apply_device_patch.sh   put device/ into the pinned tree, with three guards
  fields.py    read protocol fields out of a decode; assert a document's numbers
  lib/         shared shell helpers; provenance stamping; the handshake runner
docs/          baseline, design notes, decision records, roadmap
  handshake-walkthrough.md   every message, field by field, numbers checked by CI
  tamper.md                  what each changed byte did, and which layer noticed
  transports.md              what --trans MCTP is, and what it is not
  decisions/   architecture decision records — why, not what
  upstream/    upstream contribution tracking
bench/data/    experiment runs, one directory each, each with manifest.json
  pcapstat.py  SPDM messages counted from the capture, never from a decode
c-drills/      eight C exercises drawn from problems this project hits
third_party/   upstream commit pins only; no vendored source
certs/         this project's own three-layer chain, and the checker that
               reads it out of DER rather than out of a pretty-printer
device/        where a measurement value comes from: a loader, its file
               format, and a sixteen-line patch to libspdm     (W04)
rats/          reference values and verification policy          (from W06)
transport/     real-transport glue                               (from W09)
negative/      negative and conformance tests                    (from W10)
figures/       generated figures
```

Upstream source is not vendored. `third_party/*.pin` records the exact commits
every result was produced from; `harness/build_spdm_emu.sh` reconstructs the
build trees from those pins on any machine.

## Two build flavors

Two independent builds are maintained, and every result states which one
produced it.

| Flavor | spdm-emu | libspdm | Used for |
|---|---|---|---|
| `stable` | 3.8.0 | 3.8.0 | the released-pair control |
| `pqc` | 4.0.0-rc | 4.0.0-rc | the comparison arms, classical and post-quantum |

**Both arms of a comparison come from one build**, because holding the binary
constant is what makes the algorithm the variable. The `stable` build is run
with identical flags as a control, and week 2 measured what that control is
worth: the two builds differ in SPDM version negotiated (1.3 against 1.4),
requester capability bits, certificate chain size (1,591 against 1,655 bytes)
and the number of round trips to fetch it (2 against 1). So a "classical
baseline" is a property of a build, not of the classical algorithms, and every
table names the flavor that produced it. `manifest.json` records it whether or
not anyone remembers to.

What is pinned is the `spdm-emu` tag; `libspdm` follows that tag's submodule
pointer, because that is the pair upstream releases and tests together. No
`spdm-emu` commit has ever pointed at libspdm 3.8.1 or 3.8.2 — both sit on a
`release-3.8` maintenance branch that `spdm-emu` never followed — so **the
baseline is 3.8.0.**

What that costs was audited against upstream history rather than assumed.
3.8.1 is four commits of build and portability work carrying no security fix;
3.8.2 adds ten more, of which exactly one is a security fix, *Fix security
vulnerability in GET_CSR parsing code*. **That fix is in 4.0.0-rc under a
different hash**, so only the baseline is without it — and `GET_CSR` is not
among the operations these measurements run. What else the baseline predates,
and how this was checked, is in
[`docs/decisions/0001`](docs/decisions/0001-two-build-flavors.md).

Post-quantum support reached the libspdm main line on 2026-08-04 in a release
candidate. A release candidate is not a baseline, so it is not used as one. The
reasoning, and the revision that produced the pinning rule above, are recorded
in [`docs/decisions/0001-two-build-flavors.md`](docs/decisions/0001-two-build-flavors.md).

## What this project does not do

- It does not evaluate the security of SPDM, of `libspdm`, or of any product.
- It does not measure on real hardware. Everything is emulator-based unless a
  result explicitly says otherwise.
- It does not implement SPDM. It uses DMTF's reference implementation and
  studies its behaviour.
- It does not extrapolate. Any figure that is computed from a specification
  rather than observed is labelled as computed, next to the figure itself and
  not only in a footnote.

## Licence and upstream

Original work here is under the licence in [LICENSE](LICENSE). `libspdm`,
`spdm-emu` and `spdm-dump` are DMTF projects under their own licences and are
referenced by commit hash, not copied.

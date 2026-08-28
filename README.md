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

This is week 2 of a 14-week programme. The table below is the truth about what
exists today, not what is planned. Planned work is in
[`docs/roadmap.md`](docs/roadmap.md), which carries the same table.

| Gate | Subject | State |
|:--|---|---|
| G0 | environment and version baseline | **complete** — see [`docs/env-baseline.md`](docs/env-baseline.md) |
| G1 | full handshake, field by field | **in progress** — seven message pairs annotated, 128 values asserted by CI, two pairs reconstructed from the wire |
| G2 | certificate chain, three tamper points | not started |
| G3 | RATS verification pipeline | not started |
| G4 | post-quantum cost quantification | not started |
| G5 | real transports (QEMU / AF_MCTP) | not started |
| G6 | conformance and negative testing | not started |
| G7 | upstream contribution | agreements and account done; two candidate changes with evidence, neither submitted |
| G8 | delivery and write-up | not started |

Nothing in this repository reports a measurement that has not been made. A
table that does not exist yet is absent rather than sketched.

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
run. 128 claims across five captures. The mechanism was deliberately broken three
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
arms were re-taken on the same pins, and all 128 claims verify against the new
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
  fields.py    read protocol fields out of a decode; assert a document's numbers
  lib/         shared shell helpers; provenance stamping; the handshake runner
docs/          baseline, design notes, decision records, roadmap
  handshake-walkthrough.md   every message, field by field, numbers checked by CI
  transports.md              what --trans MCTP is, and what it is not
  decisions/   architecture decision records — why, not what
  upstream/    upstream contribution tracking
bench/data/    experiment runs, one directory each, each with manifest.json
c-drills/      eight C exercises drawn from problems this project hits
third_party/   upstream commit pins only; no vendored source
certs/         certificate chain material                        (from W03)
device/        device secret / measurement modifications         (from W04)
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

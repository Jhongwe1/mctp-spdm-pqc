# Limitations

This is the page to read second, after the scope statement on the README's first
screen. That statement says what kind of thing this project is:

> **This project performs protocol-level correctness validation.
> It is not a security assessment.**

This page says where even that claim runs out. It was started as a skeleton in
week 11 and finished on 2026-09-23. Every entry is one of two kinds, and says
which:

- **Not done** — something this project did not attempt, stated so that nobody
  assumes it was.
- **Limit** — something it did, and the edge beyond which the result stops
  meaning anything.

**Limitations live next to their results** — standing rule 5, and it is not
negotiable here. Each entry is a summary with a pointer; the authoritative
version is beside the number it qualifies. A reader who only reads this page has
read the index, not the caveats.

---

## The six layers

| | layer | the question it answers |
|:-:|---|---|
| 1 | **scope** | what this project set out to do, and what it deliberately did not |
| 2 | **implementation** | what is this project's own work, and what is upstream's |
| 3 | **environment** | what about one laptop makes a number not transfer |
| 4 | **measurement** | what each number is a measurement *of*, and what it is not |
| 5 | **RATS** | what the appraisal decides, and what it has no opinion about |
| 6 | **upstream** | what is claimed about other people's repositories |

---

## 1. Scope

- **Not done. A security assessment.** No adversary was modelled who is not
  written down in [`threat-scope.md`](threat-scope.md), and the tamper cases are
  ones the author constructed rather than ones an adversary chose.
- **Not done. A cryptographic review.** No primitive, construction or parameter
  choice here was examined for soundness. The signature arithmetic that *is*
  checked (`harness/challenge_verify.py`) is checked for **agreement with
  OpenSSL**, which is a different claim.
- **Not done. Side-channel or fault-injection analysis.** Not timing, not power,
  not electromagnetic, and none of the byte counts in
  [`pqc-cost.md`](pqc-cost.md) should be read as saying anything about them.
- **Not done. A production deployment.** Two processes on one host, or one guest
  and one host. [`transports.md`](transports.md) is the closest this gets to a
  real link.
- ★ **Limit. No session is measured, although two exist.** None of the arms a
  published number rests on opens a secure session: they run with
  `--exe_session NO_END`. Two committed captures hold one anyway, and nothing
  here measures either: the week-1 run that left `--exe_session` at its default
  (SPDM 1.4, mutual authentication, 552 encrypted records), and the conformance
  suite's no-mut-auth arm, where the `FINISH_RSP` group passes
  <!--xclaim validator_finish_rsp_passes_without_mut_auth=135-->135 assertions.
  So anything about session keys, key update, heartbeat or encrypted records is
  **unmeasured** here, not unimportant.
  *Corrected 2026-09-23. This entry said "no secure session has ever been
  established; every capture stops at or before `FINISH`". That was true of the
  captures that had been decoded, which were 132 of 152.
  [`harness/census.sh`](../harness/census.sh) decoded the rest.*
- **Limit. ML-KEM is negotiated and never used.** Every post-quantum arm
  negotiates a KEM in `ALGORITHMS`, and no arm performs a key exchange; the only
  two sessions here used ECDHE P-384. The key-establishment column of
  [`pqc-cost.md`](pqc-cost.md) §1 is a negotiation result, not a cost.
- **Limit. "Conformance" means DMTF's suite ran and its failures were explained.
  It does not mean that anything conforms to DSP0274.** A conforming device is a
  claim about a product's whole implementation, across every capability it
  advertises. This project ran one emulator build through a suite whose shipped
  configuration tops out at SPDM 1.2, and whose baseline arm recorded
  <!--xclaim validator_baseline_not_tested=55-->55 assertions as not tested
  ([`validator-report.md`](validator-report.md) §6).

## 2. Implementation — what is this project's, and what is not

★ **This is the section that protects the reader from over-reading the rest.**

| | |
|---|---|
| **upstream's, entirely** | the SPDM handshake, chunking, the post-quantum algorithm support, the responder validator, the fuzz targets, `libspdm`, `spdm-emu`, `spdm-dump` |
| **this project's** | the tamper harness and proxy, the analysers (`pcapstat.py`, `fields.py`, `pcapcount.py`, `challenge_verify.py`), the reference-value → policy → verdict pipeline in `rats/`, the negative suite in `negative/`, the CI that turns red when a tampered measurement stops being rejected, the exposure analysis in `docs/advisories.md`, the census of every capture, and two upstream changes |

The wording that follows from it, and it is exact: **"I quantified it"** and
**"I connected it up"**, never *"I implemented SPDM"* or *"I added post-quantum
support"*.

- **Not done. Any SPDM protocol code.** Upstream's code was changed in exactly
  two places: [`device/`](../device/) changes where a measurement value comes
  from, and [`transport/data-transfer-size.patch`](../transport/data-transfer-size.patch)
  makes one parameter settable in a separate build flavor. Everything else is
  analysis around unmodified binaries.
- **Not done. Any cryptographic primitive.** ML-DSA, ML-KEM, SLH-DSA and ECDSA
  are OpenSSL 3.5.5's, vendored and statically linked by `libspdm`.
- **Limit. The measurement values are fixtures.** The sample device library's
  measurements are not a hash of anything that was executed, and `device/`
  replaces where they come from, not what they mean
  ([`threat-scope.md`](threat-scope.md), assumption 3).
- **Limit. `negative/` is not an audit of libspdm.** It links nothing from
  libspdm and includes no libspdm header, deliberately. Reproducing the *class*
  of an advisory is not auditing an implementation for it.
- **Limit. The three advisories were found by other people**, reported by other
  people, and fixed by other people. What is this project's is checking the
  identifiers, diffing the two specification versions, and the exposure
  verdicts.

The same split for the three directories that look most like this project's own
work:

| | this project's | upstream's |
|---|---|---|
| `device/` | the loader, its file format, and the sixteen-line patch that calls it | the measurement block format (DSP0274) and the sample library the patch goes into |
| `certs/` | the three-level chain, generated here, and the checker that reads it out of DER | the signing, which is OpenSSL's; and the requester's own chains and responder slot 4, which are still DMTF's sample chains ([`certchain.md`](certchain.md)) |
| `figures/` | every figure, generated by `harness/mkfigures.py` from `bench/data/` and never drawn | — |

## 3. Environment

- **Limit. One machine.** Ubuntu 24.04 under WSL2 on a Windows 11 laptop,
  x86-64. [`env-baseline.md`](env-baseline.md) is generated rather than
  written, and every manifest records the host it ran on.
- **Limit. No real SPDM device.** Every responder here is `spdm_responder_emu`,
  including the one answering behind the QEMU NVMe device's DOE mailbox.
- **Limit. No hardware key protection.** Every private key is a file: DMTF's
  published sample keys for the requester and for responder slot 4, and this
  project's own for responder slot 0, generated locally and not committed
  ([`threat-scope.md`](threat-scope.md), assumption 4).
- **Limit. Three build flavors, and no others** (`third_party/spdm-emu-*.pin`,
  ADR 0001 and ADR 0009). `stable` is libspdm 3.8.0, `pqc` is 4.0.0-rc, and
  `pqc-dts` is `pqc` with larger buffers and one patch. Nothing here says anything
  about any other version — ★ including that `stable` is **AFFECTED** by
  DMTF-2026-0002, which is a fact about a deliberately pinned old build and not
  about libspdm today ([`advisories.md`](advisories.md) §3).
- **Limit. One crypto back end for the captures: OpenSSL**, vendored and
  statically linked by libspdm, 3.5.x rather than the host's 3.0.13.
  Post-quantum support exists only there. The fuzz build uses mbedtls, because
  upstream's fuzzing configuration does, so the fuzzed binary and the captured
  one are two different programs.
- **Limit. `TARGET=Release`**, which is why `LIBSPDM_ASSERT` expands to nothing.
  A Debug build is a different program for at least one purpose this project has
  measured.
- **Limit. The MCTP link runs in a guest kernel this host does not have**
  (ADR 0010), and the DOE mailbox is QEMU rather than silicon.
- **Limit. The build trees have to be on a Linux filesystem.** Under WSL2 the
  repository can live on `/mnt/c`, but the upstream trees cannot: across the 9P
  boundary one build took 90 minutes instead of 12 ([`RUNBOOK.md`](../RUNBOOK.md)
  §3A). That is why `LAB_DIR` defaults to `~/spdm-lab`, and a reproduction that
  ignores it is slow rather than wrong.

## 4. Measurement

- **Limit. Byte counts are deterministic and reported as single values.**
  Standing rule 2.
- **Not done. Any latency or timing figure.** Two processes on one host measure
  scheduling and I/O, not cryptography, so none is published. If one ever is, it
  arrives as a median, a p95 and a number of runs. The boot-budget model in
  [`pqc-cost.md`](pqc-cost.md) §11 has two measured terms, and the rest is
  reasoning, labelled as such.
- **Limit. Nothing here transfers to a BMC's CPU.** Everything ran on an x86-64
  laptop, and a BMC is a small ARM part — the AST2600's is a dual-core
  Cortex-A7. Byte and packet counts transfer; how long anything takes does not.
- **Limit. Every ratio is a property of a workload**, not of an algorithm. The
  post-quantum handshake ratio is
  <!--xclaim pqc_handshake_ratio_level3_meas_op_all=8.99-->8.99 with
  `--meas_op ALL` and
  <!--xclaim pqc_handshake_ratio_level3_meas_op_one_by_one=6.01-->6.01 over the
  emulator's default measurement flow, and publishing either without naming the
  flow is what makes a cost table unfalsifiable ([`pqc-cost.md`](pqc-cost.md)
  §6).
- **Limit. A computed figure is labelled computed**, beside the figure. Standing
  rule 4.
- **Limit. The MCTP packet counts come from `mctp-serial` in a QEMU guest.**
  That is DSP0253 byte stuffing, not SMBus or ASTLPC framing, so packet counts
  transfer and link bytes do not, and the MTUs other than 64 are hypotheses
  ([`fragmentation.md`](fragmentation.md)).
- **Limit. A short decode is not a short handshake.** `spdm_dump` stops at a
  certificate chain of 4,096 bytes, a limit measured rather than looked up, and
  the post-quantum chains are longer. The tools report a truncated decode as
  truncated rather than as a short count.
- **Limit. `harness/fields.py`'s capability-bit table is transcribed by hand**
  and pinned. `--check` cannot notice a bit upstream *renamed*, because a wrong
  name stays consistent with itself; [`RUNBOOK.md`](../RUNBOOK.md) §8.6 is the
  re-read after a pin moves.
- **Limit. AddressSanitizer misses an overflow from one struct member into the
  next.** Observed rather than read, and asserted by `negative/asan_demo.sh` so
  that a toolchain change turns the build red.
- ★ **Limit. `docs/negative-tests.md` §2.3 is a claim this project withdrew.**
  The sentence week ten set out to produce — *"my seeds are real messages"* —
  turned out to be false when measured against the alternative, and the losing
  numbers are committed.
- ★ **Limit. The fuzzing is three orders of magnitude short of meaning
  anything.** 11,432 executions at 9.07 per second. "No crashes" is the expected
  result and is reported as such.
- **Limit. Coverage is not correctness.** 69.7% of lines executed is 69.7% of
  lines that did not crash on one input.
- **Limit. Some published numbers are not re-derived by CI.** The fuzzing and
  coverage figures in the two entries above, and the edge counts of
  [`negative-tests.md`](negative-tests.md) §2.2, come from single local runs
  whose logs are committed, and nothing recomputes them. The census counts are
  recomputed only by running `harness/census.sh`, which needs `spdm_dump`; CI
  checks that every capture is covered, not what the census counted. Everything
  in `bench/claims.json`, and every `<!--claim-->` or `<!--xclaim-->` in a
  document, is recomputed on every push.

## 5. RATS

- **Limit. The appraisal decides freshness, integrity and version, and has no
  opinion about identity.** The `t3b_foreign` arm — a correct measurement
  presented with a certificate chain from an authority the requester was never
  told to trust — is judged **PASS** by both layers, because identity is not in
  this policy's job description. That is written beside the verdict.
- **Limit. The reference values are this project's own**, minted here and signed
  here. In a real deployment they come from the firmware publisher, and the
  `kid` field that looks decorative is how a verifier would choose between three
  of them.
- **Limit. They were minted from a capture of the very device they appraise**, so
  they cannot detect a device that was already wrong when the capture was taken,
  and two of the eight measurement blocks have no representation in the evidence
  format at all ([`threat-scope.md`](threat-scope.md)).
- **Limit. The version rule has a direction.** "Not lower than the reference"
  refuses a rollback below the reference value. It accepts a rollback that stays
  above it, and an attacker-built image that simply carries a higher number
  ([`rats-pipeline.md`](rats-pipeline.md)).
- **Limit. The `rats` job asserts that ten specific arms produce ten specific
  verdicts.** It does not assert that the policy catches anything else.
- **Not done. Revocation or rotation of reference values, or of the key that
  signs them.** That is a PKI problem, and nothing here attempts it.
- **Not done. A Relying Party.** The verdict ends as an exit code. A real one
  needs the result signed by the verifier, a bound on how long it stays fresh,
  and a decided action for FAIL and for no evidence at all — quarantine, retry,
  alert. None of them exists here.

## 6. Upstream

- **Limit. Two changes sent, neither merged.** `DMTF/spdm-emu` #524 had no human
  response as of 2026-09-23. `openbmc/spdm` 94773 received a −1 from an owner on
  patchset 1, for reading as AI-generated documentation that costs a reviewer
  more than it saves; patchset 2 is prepared
  ([`upstream/0002-openbmc-readme.md`](upstream/0002-openbmc-readme.md) §11).
- **Not done. Seventeen of the nineteen candidates were not sent.** Each is recorded
  with its evidence and the reason it was held back
  ([`upstream/README.md`](upstream/README.md)). They are evidence of reading
  closely, and are not claimed as contributions.
- **Limit. Each change is against one upstream commit.** #524 against
  `spdm-emu` `16119ea`, and 94773 patchset 2 against `openbmc/spdm` `32e9f8b`.
  Upstream moves, and a gap either change addresses may be closed by someone
  else first.
- **Not done. The SPDM 1.5 public-review feedback was drafted and is not
  recorded as submitted.** The window closed on 2026-08-31
  ([`upstream/spdm15-hybrid-feedback.md`](upstream/spdm15-hybrid-feedback.md)).

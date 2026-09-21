# Limitations

> ### ⚠️ This page is a SKELETON, started 2026-10-25 (W11), to be finished in W12
>
> The layers and the headings are settled. Entries marked **`TODO(W12)`** are
> places where a limitation is known to exist and has not yet been written down
> precisely enough to be useful. **They are left blank rather than filled with
> something plausible**, which is the same rule `LOG.md` uses for
> `TODO(me)` — a limitations page that guesses is worse than one that is short,
> because the whole value of it is that its author did not flatter themselves.
>
> Nothing on this page is claimed as complete. `docs/roadmap.md` lists
> deliverable 13 under **G8**, and G8 is **not started**.

This is the page to read second, after the scope statement on the README's first
screen. That statement says what kind of thing this project is:

> **This project performs protocol-level correctness validation.
> It is not a security assessment.**

This page says where even that claim runs out.

**Limitations live next to their results** — standing rule 5, and it is not
negotiable here. Every section below is a *summary* with a pointer; the
authoritative version of each is beside the number it qualifies. A reader who
only reads this page has read the index, not the caveats.

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

- **No threat model beyond `docs/threat-scope.md`.** No adversary was modelled
  who was not written down there, and the tamper cases are ones the author
  constructed rather than ones an adversary chose.
- **No cryptographic review.** No primitive, construction or parameter choice
  here was examined for soundness. The signature arithmetic that *is* checked
  (`harness/challenge_verify.py`) is checked for **agreement with OpenSSL**,
  which is a different claim.
- ★ **No secure session has ever been established.** Every capture stops at or
  before `FINISH`. `docs/threat-scope.md` level 2 is the entry; the consequence
  runs through this whole page, because anything about session keys, key update,
  heartbeat or encrypted records is **unobserved** here rather than unimportant.
- **No side-channel analysis of any kind.** Not timing, not power, not
  electromagnetic, and none of the byte counts in `docs/pqc-cost.md` should be
  read as saying anything about them.
- **No production deployment.** Two processes on one host, or one guest and one
  host. `docs/transports.md` is the closest this gets to a real link.
- `TODO(W12)` — the difference between "conformance to DSP0274" and "conforming
  device", stated in one paragraph a hiring manager can quote back.

## 2. Implementation — what is this project's, and what is not

★ **This is the section that protects the reader from over-reading the rest.**

| | |
|---|---|
| **upstream's, entirely** | the SPDM handshake, chunking, the post-quantum algorithm support, the responder validator, the fuzz targets, `libspdm`, `spdm-emu`, `spdm-dump` |
| **this project's** | the tamper harness and proxy, the analysers (`pcapstat.py`, `fields.py`, `pcapcount.py`, `challenge_verify.py`), the reference-value → policy → verdict pipeline in `rats/`, the negative suite in `negative/`, the CI that turns red when a tampered measurement stops being rejected, the exposure analysis in `docs/advisories.md`, and one prepared upstream change |

The wording that follows from it, and it is exact: **"I quantified it"** and
**"I connected it up"**, never *"I implemented SPDM"* or *"I added post-quantum
support"*.

- **`negative/` is not an audit of libspdm.** It links nothing from libspdm and
  includes no libspdm header, deliberately. Reproducing the *class* of an
  advisory is not auditing an implementation for it.
- **The three advisories were found by other people**, reported by other
  people, and fixed by other people. What is this project's is the checking of
  the identifiers, the diff of the two specification versions, and the exposure
  verdicts.
- `TODO(W12)` — the same table for `device/`, `certs/` and the figures.

## 3. Environment

- **One machine.** Ubuntu 24.04 under WSL2 on Windows 11, 8 cores, ~8 GB.
  `docs/env-baseline.md` is generated rather than written, and every manifest
  records the host it ran on.
- **Two build flavors and no others** (`third_party/spdm-emu-*.pin`, ADR 0001).
  `stable` is libspdm 3.8.0 and `pqc` is 4.0.0-rc; nothing here says anything
  about any other version — ★ including that `stable` is **AFFECTED** by
  DMTF-2026-0002, which is a fact about a deliberately-pinned old build and not
  about libspdm today (`docs/advisories.md` §3).
- **One crypto back end: OpenSSL**, vendored and statically linked by libspdm,
  3.5.x rather than the host's 3.0.13. Post-quantum support exists only there.
  A different back end is a different attack surface and different numbers.
- **`TARGET=Release`**, which is why `LIBSPDM_ASSERT` expands to nothing. A
  Debug build is a different program for at least one purpose this project has
  measured.
- **The MCTP link is a guest kernel this host does not have** (ADR 0010), and
  the DOE mailbox is QEMU rather than silicon.
- `TODO(W12)` — what the 9P filesystem boundary costs, and why `LAB_DIR` exists.

## 4. Measurement

- **Byte counts are deterministic and reported as single values.** Nothing
  timing-related is published; if it ever is, it arrives as a median, a p95 and
  a stated number of runs. Standing rule 2.
- **Every ratio is a property of a workload**, not of an algorithm. The
  post-quantum handshake ratio is 8.99 with `--meas_op ALL` and 6.01 over the
  emulator's default measurement flow, and publishing either without naming the
  flow is what makes a cost table unfalsifiable (`docs/pqc-cost.md` §6).
- **A computed figure is labelled computed**, beside the figure. Standing rule 4.
- ★ **`docs/negative-tests.md` §2.3 is a claim this project withdrew.** The
  sentence week ten set out to produce — *"my seeds are real messages"* — turned
  out to be false when measured against the alternative, and the losing numbers
  are committed.
- ★ **The fuzzing is three orders of magnitude short of meaning anything.**
  11,432 executions at 9.07 per second. "No crashes" is the expected result and
  is reported as such.
- **Coverage is not correctness.** 69.7% of lines executed is 69.7% of lines
  that did not crash on one input.
- `TODO(W12)` — the list of numbers that are **not** re-derived in CI, with the
  reason for each. §2.2's edge counts are the known one.

## 5. RATS

- **The appraisal decides freshness, integrity and version — and has no opinion
  about identity.** The `t3b_foreign` arm — a correct measurement presented with
  a certificate chain from an authority the requester was never told to trust —
  is judged **PASS** by both layers, because identity is not in this policy's
  job description. That is a limitation and it is written beside the verdict.
- **The reference values are this project's own**, minted here and signed here.
  In a real deployment they come from the firmware publisher, and the
  `kid` field that looks decorative is how a verifier would choose between
  three of them.
- **The `rats` job asserts that ten specific arms produce ten specific
  verdicts.** It does not assert that the policy catches anything else.
- `TODO(W12)` — what a real Relying Party would need that this does not have.

## 6. Upstream

- **Nineteen candidates carry evidence and none has been sent.** G7 is in
  progress and the count of merged changes is **zero**.
- **Two changes are prepared and not sent**, and the freshness check on
  2026-10-19 found that one of their base repositories had moved. The rebase was
  clean; the point is that prepared work expires.
- `TODO(W12)` — if no reviewer has responded by the W12 stop-loss, this section
  becomes *"what I read, what I found, and why I did not send it"*, which is a
  smaller claim and still a true one.

---

## What belongs here and keeps being put somewhere else

`TODO(W12)` — three or four limitations that currently live only in a LOG entry
and should be surfaced here. Candidates already identified:

- `spdm_dump`'s certificate-chain ceiling is 4,096 bytes, **measured**, so a
  short decode is not a short handshake.
- `harness/fields.py`'s capability-bit table is transcribed by hand and pinned;
  `--check` cannot notice a bit upstream *renamed*, because a wrong name stays
  consistent with itself.
- AddressSanitizer does not see an overflow from one struct member into the
  next, which this project has now observed rather than read
  (`negative/asan_demo.sh`).

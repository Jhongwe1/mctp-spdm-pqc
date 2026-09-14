# Roadmap

Fourteen weeks, nine gates, running 2026-08-11 to 2026-11-15. This is the
technical plan the repository is executed against, so that a half-finished
directory reads as scheduled rather than abandoned.

Anything not yet built is absent from the repository rather than sketched in
it. The status column below is the honest one; `README.md` carries the same
table and the two are kept in step.

## Gates

| Gate | Weeks | Subject | Definition of done | Status |
|:--|:--|---|---|---|
| **G0** | 1 | environment and version baseline | two pinned builds; health check passes items 4 and 7; `docs/env-baseline.md` committed | **complete** |
| **G1** | 2–3 | full handshake, field by field | every field of six message pairs annotated from a capture, in my own words | **complete** — seven pairs annotated in `docs/handshake-walkthrough.md`, 164 values asserted against their captures by CI, and four pairs whose *offsets* are reconstructed from the wire rather than transcribed. The three that are not, and why they are harder rather than merely undone, are in §10 |
| **G2** | 3–5 | certificate chain and three tamper points | three-layer self-signed chain accepted by the responder; three tamper points; **Table 1** with captures | **complete** — the chain, a tamper harness running ten controlled arms against a prior baseline, and **Table 1** with all three points measured (`docs/tamper.md`). Point 2 became two arms — the signed content changed in flight, and the signature changed in flight — because they are the pair that fails identically for opposite reasons, which is what the week's plan expected of points 1 and 2 and what point 1 turned out not to do |
| **G3** | 5–7 | RATS verification pipeline | reference values → policy → verdict; clean passes, tampered fails; four version-rollback cases | **complete** — the pipeline exists and is asserted by CI: a capture's measurement record, compared against a COSE-signed reference value under `rats/policy.rego`, over all ten tamper arms (**Table 3**, `docs/rats-pipeline.md`). The arm nothing in SPDM refused is judged FAIL and names the index; the arm where only the *signature* was altered is judged PASS, which separates a damaged link from a damaged device where one status code could not. The fourth clause is closed too: the secure version number is compared per index and one-sided, and four captures — an upgrade, a rollback, an exact match and a correct version beside an altered measurement — are appraised under the new rule **and** under a frozen copy of the equality rule it replaced. Exactly one verdict moves, `rats/test_svn_policy.sh` asserts that it is the only one, and `rats/rats_selftest.py` asserts that the two policies differ in code only inside one marked region. What `>=` still cannot see — a rollback that stays above the reference value — is beside the result in `docs/rats-pipeline.md` §5 |
| **G4** | 7–8 | post-quantum cost | **Table 2** and **Figure 2**: bytes and round trips, classical vs post-quantum, algorithm confirmed from the negotiated result rather than the requested one | **in progress** — two of six algorithm groups measured, at matched NIST level 3, with eighteen control variables pinned and the negotiated result read back off the wire in all twelve groups and asserted per arm (`docs/pqc-cost.md`). The ratio is published twice, once per measurement flow, because the same A/B gives 8.99× and 6.01× and a cost ratio is a property of a workload. The other four groups and **Figure 2** are week 8 |
| **G5** | 9 | real transports | handshake over a transport that is not a TCP socket | not started |
| **G6** | 10–11 | conformance and negative testing | upstream responder validator run with a root cause for every failure; negative tests reproducing three 2026 advisory *classes* | not started |
| **G7** | 1–12 | upstream contribution | a change submitted to an upstream project, with reviewer correspondence | **in progress** — environment prepared; **thirteen candidates with evidence** — `openbmc/spdm` prerequisites, `DMTF/spdm-emu` help text that disagrees with its own defaults, and two found on 2026-09-01 while explaining a tamper capture: a discarded slot-0 certificate read result, and a requester that never inspects `LIBSPDM_STATUS_VERIF_NO_AUTHORITY`. A fifth arrived on 2026-09-10 while writing the tamper proxy: `spdm_emu_common/command.h` documents the socket payload as "SPDM message, starting from SPDM_HEADER" when the MCTP transport puts a message-type byte in front of it, so a reader who trusts the comment is one byte out on every field. Seven more came from running DMTF's own published example on 2026-09-12, and a thirteenth on 2026-09-14 while pinning an A/B's control variables: `--req_asym NONE --req_pqc_asym NONE` parses, echoes back and then makes the handshake impossible, because the responder requires exactly one requester signature algorithm whenever `MUT_AUTH_CAP` is supported and `--mut_auth NO` does not clear that capability bit. Separately, DMTF's SPDM 1.5 hybrid-PQC review was read during its window and feedback drafted; **not sent**, and filed as evidence of timing rather than of contribution |
| **G8** | 12–14 | delivery and write-up | README, limitations, threat scope, demo, one-page summary | not started |

## Dependencies

```mermaid
flowchart LR
    G0[G0 environment] --> G1[G1 handshake]
    G1 --> G2[G2 tamper detection]
    G2 --> G3[G3 RATS pipeline]
    G1 --> G4[G4 PQC cost]
    G0 --> G4
    G2 --> G5[G5 transports]
    G3 --> G6[G6 conformance + CI]
    G4 --> G6
    G6 --> G8[G8 delivery]
    G7[G7 upstream] -.spans W01-W12.-> G8

    style G2 stroke-width:3px
    style G3 stroke-width:3px
    style G7 stroke-width:3px
```

G2, G3 and G7 are load-bearing. If time runs short the order of sacrifice is
G5 first, then the fuzzing half of G6, then the extra algorithm groups in G4.
Those three are not on the list.

## Deliverables

| # | Artifact | Gate | Kind |
|:--|---|:--:|---|
| 1 | field-by-field handshake annotation | G1 | written from captures |
| 2 | three-layer self-signed certificate chain, read from its DER rather than from a pretty-printer | G2 | evidence — [ADR 0005](decisions/0005-generated-inputs-are-evidence.md) says why it is not reproducible |
| 3 | **Table 1** — three tamper points, before/after, with three captures | G2 | measured — two of three; `docs/tamper.md` |
| 4 | `pcapstat.py` — capture statistics, written here, no dependencies | G2 | tool — exists, and CI requires it to agree with `fields.py` per message type |
| 5 | **Table 2** — post-quantum cost at four levels | G4 | measured — two of six groups; `docs/pqc-cost.md`. Every ratio is re-derived from its captures by `harness/check_claims.py` |
| 6 | **Figure 2** — total handshake bytes and certificate round trips | G4 | measured |
| 7 | **Table 3** — reference values, policy, and a verdict per arm | G3 | reproducible — `rats/`, `docs/rats-pipeline.md`, and the four rollback cases beside it under two policies |
| 8 | upstream responder-validator report, root cause per failure | G6 | reproducible |
| 9 | negative test suite reproducing three advisory classes | G6 | reproducible |
| 10 | CI that re-runs the experiments and asserts the published numbers | G6 | mechanism — the `rats` job asserts that a **tampered** measurement is rejected and that the version rule moved exactly one verdict; `harness/check_claims.py` re-derives every published cross-capture ratio from the captures it names, at a tolerance of zero |
| 11 | an upstream change with reviewer correspondence | G7 | external |
| 12 | `docs/threat-scope.md` — what is and is not defended against | G8 | written |
| 13 | `docs/limitations.md` | G8 | written |
| 14 | eight C drills with a compile-error trend | all | separate track |

Deliverable 10 is the one the rest depends on for credibility. A table can be
anything. A CI job that turns red when a tampered measurement is *not* rejected
is the reason a table can be believed, and it is why the assertion is written
as a negative: the pipeline must **fail** on tampered input, and CI checks that
it does.

## Standing rules

1. **Nothing unmeasured is published.** Every number points at a capture and a
   `manifest.json`.
2. **Not the best run.** Byte counts are deterministic and reported as single
   values; anything timing-related is reported as median and p95 over a stated
   number of runs.
3. **Protocol validation is not security assessment**, in those words, wherever
   the distinction could be blurred.
4. **No extrapolation.** A figure computed from a specification rather than
   observed is labelled as computed, beside the figure and not only in a
   footnote.
5. **Limitations sit next to the result**, not in a closing section.
6. **Versions are recorded**, by commit hash, automatically.
7. **Nothing is cited that has not been checked** against the primary source.
8. **Independent variables are verified, not assumed, and enumerated rather
   than spot-checked.** When an algorithm is requested, the result reports what
   was actually negotiated — in *every* direction the protocol negotiates
   separately. Confirming one field of a pair is not confirming the variable;
   2026-08-17 in `LOG.md` is what that costs.
9. **A published number is marked up so a machine can re-derive it.** Prose has
   no equivalent of `prov_begin`, so where a document states a measured value it
   carries a claim comment and `harness/fields.py --check` recomputes it from
   the capture on every CI run. Facts that are only stated are the ones that rot.
10. **An ignore rule does not outrank a manifest.** Every artifact a manifest
    attests to must be present and tracked, and `verify_repo.sh` checks it.
11. **A check is worth what it rejects, and something has to prove it rejects.**
    Every mechanism here has a companion that feeds it something wrong and
    requires it to fail: `pcapcount.py` against a capture built byte by byte,
    `fields.py --check` against a drifted number and an invented field name, the
    layout reconstruction against a message one byte short. A check that has
    never been observed failing is arithmetic that happens to agree.
12. **A number no document quotes is not checked by that document's checker.**
    `--check` guards the values someone chose to state; a tool computing twenty
    fields while seven are quoted is checked on seven, and 2026-08-28 in
    `LOG.md` is what that cost. Where two tools can reach the same quantity by
    different routes, they are made to agree — `pcapcount.py` owns the capture
    file and never reads a decode, `fields.py` owns the decode and never opens
    a capture, `certs/check_chain.py` owns the certificate files and never
    opens either, and CI requires their answers to reconcile.
13. **Two breaks caught by the same check are one check.** Rule 11 requires
    every mechanism to be observed rejecting something. That is not enough on
    its own: a suite where four broken inputs are all refused by the cheapest
    check reports four times the coverage it has, and one of the checks between
    them has still never done anything. So the negative tests assert that the
    rejections come through *distinct* mechanisms, and 2026-08-31 in `LOG.md`
    is the day that assertion found a redundant check in the suite that had
    just been written to demonstrate the rule.
14. **A generated input is evidence, and regenerating it is not reproducing
    it.** Some artifacts are neither captures nor derivations: the certificate
    chain is an *input* the captures depend on, and it cannot be reproduced —
    fresh keys, and an ECDSA signature whose DER length depends on its own
    integers. It is committed, the generator refuses to overwrite it, and what
    has to hold on any machine is the *relationship* rather than the bytes.
    [ADR 0005](decisions/0005-generated-inputs-are-evidence.md).
15. **A drill whose failure mode cannot occur teaches a superstition.** Before a
    C drill is committed, its tests are compiled **three** ways in a scratch
    directory: against the committed stub, which must build and fail; against a
    correct implementation, which must pass; and against the wrong one the
    drill exists to teach, which must be caught. Twice a drill has been written
    whose trap could not fire — 2026-08-28's `d1` and 2026-08-31's first `d6` —
    and both times reasoning about whether it would fire was the same reasoning
    that produced it. The first of the three was added to this rule on
    2026-09-01, after `d4` passed the two interesting compilations and failed
    the boring one: `make` builds every drill, so a stub that does not compile
    turns the badge red on the day it is committed. `c-drills/README.md` had
    described all three from the beginning; this rule had not.
16. **A category is not a prefix of a sentence.** Rule 13 requires distinct
    breaks to be refused by distinct checks, and something has to decide what
    "distinct" means. Comparing the refusal *messages* is not enough: on
    2026-09-01 two broken measurement records were caught by the same length
    test and passed the distinctness check anyway, because the two sentences
    differed in a number they had interpolated. Every mechanism that has to
    report *which* check rejected something returns a stable code beside the
    prose — `ms_status_t` in `device/`, `why_kind` in `fields.py` — and the
    tests compare codes.
17. **A fix is correct in the state it leaves behind, not in isolation.**
    On 2026-09-12 a one-line change to an upstream verifier was written,
    committed, signed off and one keystroke from being sent. It was right: the
    tool passed a public key where a private scalar goes, so it refused every
    signature. Three lines below, the same function discarded the *return
    value* of `verify_signature()`, which is a bool rather than an exception.
    The two defects masked each other, and the correct fix for the first,
    applied alone, would have turned a verifier that accepts **nothing** into
    one that accepts **anything**.
    It was caught by writing a script to re-run the `Tested:` claims of a
    commit message that already existed — and the last claim, *"a corrupted
    signature is still refused"*, was false. So: **before sending a change,
    run its own commit message**, and when a defect is found in a function,
    read the rest of the function rather than the rest of the line.
    `rats/interop.sh` now keeps a half-patched copy of that file and asserts
    that it accepts a forged signature, because the story is not the
    mechanism; the check is.

## External dates that do not wait

| Date | Event | Affects |
|---|---|---|
| 2026-08-04 | `libspdm 4.0.0-rc` — PQC reaches the main line | G0, G4 |
| 2026-08-31 | DMTF SPDM 1.5 hybrid-PQC public review closes | G2 |
| 2026-09-11 | EU CRA reporting obligations take effect | context |
| 2026-11-15 | repository complete | G8 |

The first and second lines are why this project is worth doing in this
particular quarter: large-scale operators have already written SPDM and
post-quantum requirements into procurement baselines, while the standard that
covers the combination is still in review. That gap is temporary.

## This plan will also expire

Its parent was written on 2026-07-27 and was overtaken thirteen days later by
a release. Any version number, date, flag or advisory identifier stated here
should be re-checked against its primary source before being repeated
anywhere it will be examined.

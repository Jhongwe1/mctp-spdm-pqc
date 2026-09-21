# negative

Input the implementation should reject, and proof that it does.

**Status on 2026-10-19 (W11):** all three are written. **24 cases, 21 defect
variants**, every case moved by at least one defect, and two runs that assert
what the sanitizer does and does not see. `make test` runs all of it in about
two seconds and needs no libspdm, no network and no build tree.

```
make          build all three
make list     what each file asserts, and what each defect must move
make test     every test, and every defect variant, and both --asan-demo runs
```

## The two halves of G6, and which one this is

| | |
|---|---|
| **the upstream conformance suite** | DMTF's `SPDM-Responder-Validator`, run four ways, with a root cause for every failure — [`docs/validator-report.md`](../docs/validator-report.md) |
| **fuzzing and coverage** | libspdm's own AFL targets, seeded from this project's captures, against the corpus upstream ships — [`docs/negative-tests.md`](../docs/negative-tests.md) §1–5 |
| **this directory** | three advisory **classes**, written as tests that can fail — [`docs/negative-tests.md`](../docs/negative-tests.md) §6 |

## Why a class and not a payload

The payloads of the 2026 advisories are fixed. Rebuilding one produces a test
that passes on every version of libspdm anybody will run, and a test that
cannot fail is documentation with a build step.

The classes do not get patched:

| file | class | cases × defects | the drill it came from |
|---|---|:-:|---|
| [`test_offset_length.c`](test_offset_length.c) | `Offset + Length` computed in a type that wraps | 9 × 8 | [`c-drills/d2_offset_length`](../c-drills/d2_offset_length.c) |
| [`test_oversized_field.c`](test_oversized_field.c) | a declared length checked against the message rather than against the destination | 7 × 7 | [`c-drills/d8_bounded_copy`](../c-drills/d8_bounded_copy.c) |
| [`test_transcript_coverage.c`](test_transcript_coverage.c) | a signature over a transcript that omits a message the conversation accepted | 8 × 6 | — |

Each file's header comment is its specification: the cases, the status code
each must return, and the deliberately wrong implementations it has to be run
against before it is believed.

## ★ The defect variants, which are the point

Rule 11 says a check is worth what it rejects and that *something has to prove
it rejects*. Here that is not a formality — a suite of assertions about refusals
passes trivially against an implementation that refuses everything.

So every test is compiled more than once. Undefined `NEG_DEFECT` is the version
the file argues is correct; `-DNEG_DEFECT=k` is a specific mistake, and the file
declares **in advance** exactly which cases it must move, and which of those it
must move all the way to `NEG_OK`.

```
DEFECT CAUGHT    exactly the predicted cases moved, in the predicted direction
DEFECT MISSED    the suite cannot see the mistake it exists for       (rule 11)
WRONG DOOR       an unpredicted case moved: two breaks, one check     (rule 13)
WRONG SEVERITY   it moved, but a refusal and an accepted input are different events
```

It has already corrected its author: `test_transcript_coverage.c` defect 3 was
declared to move three cases and moves four, and the fourth is the one it
*accepts*. The comment beside the declaration says which came first.

## Three rules these inherit, and what each one rules out

- **Rule 11 — a check is worth what it rejects.** Above, and mechanised.
- **Rule 13 — two breaks caught by the same check are one check.** A defect
  that moves a case nobody predicted fails the build exactly as loudly as one
  that moves nothing.
- **Rule 16 — a category is not a prefix of a sentence.** Every refusal carries
  a stable code from [`negative.h`](negative.h) and the tests compare codes.
  Comparing messages failed once already, on 2026-09-01, because two sentences
  differed in a number they had interpolated.

## What this directory does not claim

It does **not** audit `libspdm`. It links nothing from libspdm and includes no
libspdm header — deliberately, because a suite that linked the library would
appear to be testing it, and reproducing the class of an advisory is not
auditing an implementation for it. libspdm is on OSS-Fuzz, ships about
sixty-nine AFL targets, and runs CodeQL and Coverity in CI; nothing here
improves on that.

**Whether this project's own builds carry the defects is a different question**,
and it is answered by measurement rather than by these tests:
[`docs/advisories.md`](../docs/advisories.md) §3, from
`harness/check_advisories.py`. The short version is that the `stable` flavor is
**affected** by one of them, on five independent preconditions, and that no
capture in this repository has ever sent the request that reaches it.

## The advisory identifiers, which W10 refused to write down

W10 left them out on purpose — standing rule 7, applied to a security advisory.
W11 checked all three against their primary sources. **All three are correct**,
and checking them found that none is in GitHub's global advisory database, that
two of them have no CVE at all, and that the one CVE was in neither NVD nor
MITRE's CVE Services. Each is now pinned in `third_party/`, quoted in
[`docs/advisories.md`](../docs/advisories.md) §1, and re-fetched weekly by
`harness/check_advisories.py --refresh` so that drift is noticed rather than
assumed away.

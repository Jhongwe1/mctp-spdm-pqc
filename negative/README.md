# negative

Input the implementation should reject, and proof that it does.

**Status on 2026-10-12 (W10):** the three specifications are written, the three
files compile under `-Werror` with AddressSanitizer and UndefinedBehaviorSanitizer,
and `DONE.txt` is empty — so `make test` runs nothing and claims nothing. W11
writes the assertions.

```
make          build all three (skeletons included)
make list     what is present, and what is claimed
make test     run only what DONE.txt names — which is currently nothing
```

## The two halves of G6, and which one this is

| | |
|---|---|
| **the upstream conformance suite** | DMTF's `SPDM-Responder-Validator`, run four ways, with a root cause for every failure — done, [`docs/validator-report.md`](../docs/validator-report.md) |
| **fuzzing and coverage** | libspdm's own AFL targets, seeded from this project's captures, against the corpus upstream ships — done, [`docs/negative-tests.md`](../docs/negative-tests.md) |
| **this directory** | three advisory **classes**, written as tests that can fail — **W11** |

## Why a class and not a payload

The payloads of the 2026 advisories are fixed. Rebuilding one produces a test
that passes on every version of libspdm anybody will run, and a test that
cannot fail is documentation with a build step.

The classes do not get patched:

| file | class | the drill it came from |
|---|---|---|
| [`test_offset_length.c`](test_offset_length.c) | `Offset + Length` computed in a type that wraps | [`c-drills/d2_offset_length`](../c-drills/d2_offset_length.c) |
| [`test_oversized_field.c`](test_oversized_field.c) | a declared length checked against the message rather than against the destination | [`c-drills/d8_bounded_copy`](../c-drills/d8_bounded_copy.c) |
| [`test_transcript_coverage.c`](test_transcript_coverage.c) | a signature over a transcript that omits a message the conversation accepted | — |

Each file's header comment is its specification: the cases to assert, the
status code each must return, and the deliberately wrong implementation the
test has to be run against before it is believed.

## Three rules these inherit, and what each one rules out

- **Rule 11 — a check is worth what it rejects.** Every test is run against an
  implementation written to have the defect, and must catch it. A negative test
  that has never been observed failing is arithmetic that happens to agree.
- **Rule 13 — two breaks caught by the same check are one check.** Feeding a
  parser nine malformed messages and collecting nine refusals demonstrates one
  check nine times if the cheapest one refused them all.
- **Rule 16 — a category is not a prefix of a sentence.** So every refusal
  carries a stable code from [`negative.h`](negative.h), and the tests compare
  codes. Comparing messages failed once already, on 2026-09-01, because two
  sentences differed in a number they had interpolated.

## What this directory does not claim

It does **not** audit `libspdm`. It links nothing from libspdm and includes no
libspdm header — deliberately, because a suite that linked the library would
appear to be testing it, and reproducing the class of an advisory is not
auditing an implementation for it. libspdm is on OSS-Fuzz, ships about sixty-nine
AFL targets, and runs CodeQL and Coverity in CI; nothing here improves on that.

Advisory identifiers are **absent** from these files on purpose. `plan/W11`
names four. None has been checked against its primary source, and
`docs/roadmap.md` standing rule 7 applies to a security advisory more than to
anything else: a wrong identifier attached to a real class invites a reader to
look it up and find something unrelated. W11 fetches them, pins the retrieval
the way `third_party/` pins every other external document, and writes them down
then.

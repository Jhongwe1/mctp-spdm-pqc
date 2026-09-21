# Drill scorecard

One number is tracked here across all eight drills: **how many compile errors
the paper version produced when it was first typed in, unedited.**

That number is the measurement. Everything else in this directory is the
apparatus for producing it. Writing correct C with a compiler one keystroke
away is a different skill from writing it with nothing to ask, and the second
one is the one that decays without ever announcing it. The gap between the two
is invisible unless it is counted.

The expectation is that this column falls from roughly 5–8 at the start to 0–1
by the end. If it does not fall, the drills are being done with the editor
open, and the practice is not practising the thing it is supposed to practise.

## Rules for filling this in

- **Type the paper version in exactly as written.** Do not fix anything on the
  way in. A typo the compiler would normally have caught is a real error here;
  count it.
- Count **errors**, not lines of compiler output — one missing semicolon that
  cascades into nine messages is one error.
- Count warnings separately. `-Werror` is on, so a warning stops the build too,
  but a sign-compare warning and a missing return are different mistakes.
- Record the sanitizer verdict on the first *successful* compile, before any
  debugging. That is where the pointer bugs show up.

## Record

| # | Drill | Date | Paper time | Compile errors | Warnings | First sanitizer result | Error categories |
|:--|-------|------|-----------:|---------------:|---------:|------------------------|------------------|
| D3 | `d3_queue_via_list` | | / 20 min | | | | |
| D1 | `d1_spdm_header` | | / 20 min | | | | |
| D5 | `d5_endian` | | / 15 min | | | | |
| D6 | `d6_packed_struct` | | / 15 min | | | | |
| D4 | BST delete | | / 25 min | | | | |
| D2 | `d2_offset_length` | | / 10 min | | | | ⚠️ **after reference** |
| D7 | ring buffer | | / 20 min | | | | |
| D8 | length-bounded string copy | | / 15 min | | | | ⚠️ **after reference** |

**Error categories** — classify every mistake as one of these three, because
the fix is different for each:

| Category | What it means | What to do about it |
|---|---|---|
| `syntax` | semicolons, braces, declaration form, `struct` vs `typedef` name | rote repetition; it is muscle memory and nothing else |
| `type` | signed/unsigned, pointer-to-pointer, `const` placement, implicit conversion | read the standard's conversion rules once, properly |
| `logic` | the algorithm was wrong on paper | slow down at step 2 — the hand dry-run was skipped or rushed |

A falling total that is entirely `syntax` means one thing. A flat total that is
mostly `logic` means something else and calls for a different response.

## One row that is not about compiling

D2 asks for a second thing, and it is worth more than the number:
**write down which version you reached for first.** `off + len <= total` is
the wrong one and it is the one almost everybody writes, because it reads like
the sentence in your head. If that is what you wrote, say so in
`c-drills/README.md` — it is the only evidence in this repository about what
gets reached for under time pressure, and it is worth more than a passing
test, which only says the second attempt was right.

## ⚠️ D2 and D8 stopped being measurements on 2026-10-19

On that day `negative/test_offset_length.c` and `negative/test_oversized_field.c`
were written, and both contain a worked, commented, correct version of exactly
what D2 and D8 ask for:

```c
/* D2's subject */   if ((size_t)len > total - off) { ... }
/* D8's subject */   if (declared > msg_len) ...; if (declared > dest_size) ...;
                     if (declared == dest_size) ...   /* and dest[declared] = 0 */
```

**So the two rows below are no longer the thing this file exists to measure.**
Writing C with no compiler to ask is one skill; writing it after reading a
correct version is a different and much easier one, and the number this
scorecard tracks cannot tell them apart.

What is lost precisely:

| | |
|---|---|
| **D2's second question** — *which version did you reach for first* | **gone.** `off + len <= total` against `len <= total - off` is now a thing that has been read rather than a thing that was reached for, and that question was worth more than the compile-error count |
| D2 and D8 compile-error counts | still worth recording, and **not comparable** with the other six. Mark them `(after reference)` in the table |
| the other six drills | unaffected |

**It was a deliberate trade and it is recorded as one.** Week 11 had three C
test suites, a five-way exposure analysis, a specification diff and a CI job in
it, and doing the drills first would have been the only way to keep both. The
ordering was the whole fix and it was not taken.

★ **The repair, if it is wanted:** D2 and D8 are the two drills whose *shape*
recurs everywhere in this protocol. A fresh problem in the same class — a ring
buffer's wrap, a length-prefixed field walk — measures the same muscle without
the answer having been published. `mock/` is where an unseen problem belongs.

## Rewrite rounds

Every drill is rewritten from scratch, on paper, at least once more later. The
second attempt is the honest one: the first time, the problem was novel; the
second time, the only variable left is whether it was actually learned.

| Round | When | Drills | Total compile errors | Notes |
|---|---|---|---:|---|
| 1st pass | W01–W08 | D1–D8, one per week | | |
| full rewrite | W10 | all eight, paper only | | |
| timed round 1 | W08 | [`mock/round1.md`](mock/round1.md) — two unseen problems, 45 min | | **paper set 2026-09-14, not yet sat** |
| timed round 2 | W11 | two problems, 45 min | | |
| timed round 3 | W13 | two problems, 45 min | | |

### Timed round 1, per problem

The round is recorded per problem and not just as a total, because "went over
time" has two opposite causes and only the per-problem minutes tell them apart:
thinking too long calls for more paper dry-runs, writing too slowly calls for
rote repetition. `mock/round1.md` §"After the clock stops" is the sheet to fill
in; this is where the numbers land.

| | minutes | inside the box? | compile errors | warnings | first sanitizer | categories |
|---|--:|:--:|--:|--:|---|---|
| P1 · reassemble a numbered sequence | | | | | | |
| P2 · `packet_count` | | | | | | |

★ **The third question on the sheet is the one to answer even if the numbers are
bad.** P2 at `SIZE_MAX` is the same overflow class as `d2_offset_length`, which
is the same class as a real libspdm advisory. If it did not transfer from the
drill to the timed problem, that is a more useful finding than a low error
count, and it belongs in the Notes column above in words.

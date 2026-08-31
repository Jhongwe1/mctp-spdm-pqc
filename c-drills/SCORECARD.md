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
| D2 | offset + length overflow check | | / 10 min | | | | |
| D7 | ring buffer | | / 20 min | | | | |
| D8 | length-bounded string copy | | / 15 min | | | | |

**Error categories** — classify every mistake as one of these three, because
the fix is different for each:

| Category | What it means | What to do about it |
|---|---|---|
| `syntax` | semicolons, braces, declaration form, `struct` vs `typedef` name | rote repetition; it is muscle memory and nothing else |
| `type` | signed/unsigned, pointer-to-pointer, `const` placement, implicit conversion | read the standard's conversion rules once, properly |
| `logic` | the algorithm was wrong on paper | slow down at step 2 — the hand dry-run was skipped or rushed |

A falling total that is entirely `syntax` means one thing. A flat total that is
mostly `logic` means something else and calls for a different response.

## Rewrite rounds

Every drill is rewritten from scratch, on paper, at least once more later. The
second attempt is the honest one: the first time, the problem was novel; the
second time, the only variable left is whether it was actually learned.

| Round | When | Drills | Total compile errors | Notes |
|---|---|---|---:|---|
| 1st pass | W01–W07 | D1–D8, one per week | | |
| full rewrite | W10 | all eight, paper only | | |
| timed round 1 | W08 | two problems, 45 min | | |
| timed round 2 | W11 | two problems, 45 min | | |
| timed round 3 | W13 | two problems, 45 min | | |

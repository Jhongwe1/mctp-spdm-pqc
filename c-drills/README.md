# c-drills

Eight small C exercises, each one lifted out of a problem this project actually
runs into. They are here because the repository and the exercises are testing
different things, and it is easy to mistake the first for the second.

The repository demonstrates that a system was built, measured, and reasoned
about. It does not demonstrate whether C can still be written correctly with no
compiler in the loop to ask. That is a separate skill, it degrades quietly, and
nothing in a normal working day turns red when it does — which is the reason it
is measured here on purpose.

## The four steps

Each drill goes through the same sequence, and the order carries the whole
value:

1. **Paper.** Nothing open — no editor, no reference, no compiler. Inside the
   time box printed at the top of the file.
2. **Dry-run by hand.** Trace two inputs through the paper version with a pen.
   One of the two must be a boundary case, not a happy path.
3. **Type it in unchanged.** Do not fix anything on the way in. Count the
   compile errors and record them in [SCORECARD.md](SCORECARD.md).
4. **`make test` clean**, under `-Werror` and both sanitizers.

Step 3 is the measurement. See SCORECARD.md for why that particular number is
the one worth tracking.

## Usage

```bash
cd c-drills

make                       # compile every drill (catches syntax immediately)
make list                  # which drills exist, which are marked complete
make test                  # run the drills listed in DONE.txt

make d3_queue_via_list && ./d3_queue_via_list      # one drill, directly
make clean
```

Compiled with:

```
-std=c11 -Wall -Wextra -Werror -g -O1 -fsanitize=address,undefined
```

`-Werror` because a warning left unfixed is a bug that has been seen and
ignored. The sanitizers because the two bug classes these drills exist to
teach — use-after-free and leaked allocations — do not reliably show up as a
wrong answer. They show up as a test that passes on this machine and fails on
another one.

## Why `DONE.txt` exists

`make` compiles every drill. `make test` runs only the ones named in
[DONE.txt](DONE.txt).

An unwritten drill is stubbed out, so it compiles but its tests fail. Without
the manifest, CI would be red from the first commit and would stay red for
weeks, which trains everyone to ignore it. With the manifest, CI is honest:
it reports what has been finished and never claims anything else.

## The drills

| # | File | Boundary that breaks it | Where it shows up in the project |
|:--|------|--------------------------|-----------------------------------|
| D3 | `d3_queue_via_list.c` | dequeue the last element, then enqueue again — stale `tail` | transport glue holding received-but-unconsumed messages |
| D1 | `d1_spdm_header.c` | an offset whose bounds check overflows before it is checked | first step of every capture-analysis script here |
| D5 | `d5_endian.c` | a top byte of 0x80 or above, shifted on a signed int | the socket framing is big-endian, the payload little-endian |
| D6 | `d6_packed_struct.c` | one byte of padding that moves a field AND a size | wire formats are byte layouts, not struct layouts |
| D4 | BST delete | deleting a node with two children | not used here — kept for the three-way pointer rewiring it forces |
| D2 | offset + length overflow | `offset + length` wrapping past the end of the buffer | the arithmetic behind a real advisory class |
| D7 | ring buffer | full and empty are indistinguishable by indices alone | proxy and transport buffering |
| D8 | length-bounded string copy | the truncation case, and who writes the terminator | the other real advisory class |

Each file states its own contract, its boundaries, and its time box at the top.
The tests are provided. The implementation is not, and should not be — the
tests are the specification, and writing the implementation is the exercise.

## Every drill's tests are checked against a correct implementation first

The tests are the specification, and a specification has two ways of being
useless: a correct implementation can fail it, or a wrong implementation can
pass it. Both are silent.

So before a drill is committed, its tests are compiled three ways in a scratch
directory outside this repository — against the stub, which must fail; against
a correct implementation, which must pass; and against a deliberately wrong one,
which must be caught. The wrong version is chosen to be the mistake the drill
exists to teach, so if the suite accepts it the drill has no subject.

Those reference implementations are never written into `c-drills/`. They would
delete the only measurement this directory produces.

It is worth saying what this catches, because both drills added in week three
failed it on the first attempt:

- **D5**'s wrong version — shifting a `uint8_t` on a signed `int` — produces the
  *correct value* on every compiler anyone will use. Only
  UndefinedBehaviourSanitizer separates it from the right answer, so a drill
  that checked values alone would have taught nothing.
- **D6** was written against the five-byte MCTP transport framing and the trap
  could not fire. See below.

## Why D6 is not about the transport framing

The obvious subject for a packing drill was `harness/verify_repo.sh`'s

```
pcap captured bytes == SPDM message bytes + 5 x messages
```

where the 5 is a four-byte MCTP header plus a message-type byte, and taking it
from `sizeof` would be the classic mistake. It is not a mistake. Upstream's
`mctp_header_t` is four `uint8_t` members, so its alignment is 1 and `sizeof`
gives exactly 5. There is no padding to be wrong about.

That is the same defect D1 had, eleven days earlier, and it was written a second
time by the same person who documented the first one. A drill whose failure mode
cannot occur teaches a superstition, and a superstition gets repeated with
confidence, so D6 moved to the struct where the padding is real:
`spdm_measurement_block_dmtf_header_t`, a `uint8_t` followed by a `uint16_t`,
three bytes on the wire and four in C — where the padding moves a **field** as
well as a **size**. The common header beside it, `{uint8_t, uint8_t, uint16_t}`,
is identical packed or not, and both are in the drill so the contrast is the
lesson rather than the rule.

The general form, which is the part worth keeping: **before writing a drill,
compile the wrong implementation and confirm it fails.** Reasoning about whether
a trap fires is exactly the kind of reasoning that produced the trap.

## Why D1 has two functions

The lesson normally attached to a header parser is "do not cast the buffer to a
struct pointer, it works on x86 and faults on ARM." With D1's struct that
lesson is **false**, and finding out why was worth more than repeating it:
every member is a `uint8_t`, so `_Alignof(spdm_hdr_t)` is 1 and the cast cannot
be misaligned at any address. There is still a strict-aliasing argument against
it, and padding would bite the moment a `uint16_t` is added, but neither faults
and no sanitizer reports either.

What does fault is reading a **multi-byte** field at an offset you do not
control, which is why D1 also asks for `spdm_read_u32_le`. Its test reads
`DataTransferSize` from an odd address, and `*(const uint32_t *)(buf + off)`
stops there under `-fsanitize=alignment`. Same habit, a version of it that
actually punishes.

That second function overlaps D2 — its bound has to be written so `off + 4`
cannot wrap — and the overlap is deliberate rather than an oversight. The
arithmetic shows up first in a real message and gets its own drill afterwards.
Paper time is 20 minutes rather than 15 for the same reason.

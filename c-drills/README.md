# c-drills

Eight small C exercises, each one lifted out of a problem this project actually
runs into. They are here because the repository and the exercises are testing
different things, and it is easy to mistake the first for the second.

The repository demonstrates that a system was built, measured, and reasoned
about. It does not demonstrate that C can be written on a whiteboard, from
memory, in twenty minutes, with someone watching. That is a separate skill, it
degrades quietly, and it is usually examined first.

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
| D1 | SPDM header parser | a buffer shorter than the header it claims to contain | first step of every capture-analysis script here |
| D5 | endianness conversion | sign extension when widening | the socket framing is big-endian, the payload little-endian |
| D6 | packed struct layout | assuming the compiler laid it out the way it reads | wire formats are byte layouts, not struct layouts |
| D4 | BST delete | deleting a node with two children | classic examined structure |
| D2 | offset + length overflow | `offset + length` wrapping past the end of the buffer | the arithmetic behind a real advisory class |
| D7 | ring buffer | full and empty are indistinguishable by indices alone | proxy and transport buffering |
| D8 | length-bounded string copy | the truncation case, and who writes the terminator | the other real advisory class |

Each file states its own contract, its boundaries, and its time box at the top.
The tests are provided. The implementation is not, and should not be — the
tests are the specification, and writing the implementation is the exercise.

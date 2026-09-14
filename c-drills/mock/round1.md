# Timed round 1 — two problems, forty-five minutes, on paper

**Set 2026-09-14 (week 8). Not yet sat.**

This is not a drill. The eight drills in the directory above are practice with a
known shape and an untimed first read. This is the measurement they are practice
*for*: **two unseen problems, one clock, nothing open.**

The published shape it is calibrated against is a verified one — a hardware
vendor's C screen of **two problems in forty-five minutes**, an array question
and a sorting question. Both problems below are deliberately smaller than they
look, for the same reason a real screen's are: what is being tested is whether
the boundary cases get thought about before the code gets written, not whether
anything clever happens.

---

## The rules, and why each one is there

```
☐ 45 minutes on a clock that does not stop. Set it before reading the problems.
☐ Paper, or a text editor with syntax highlighting and nothing else.
☐ Nothing open. No manual page, no header, no previous drill, no search.
☐ Both problems before any compiling. Not one, compile, then the other.
☐ Write the time each problem took, on the paper, as you finish it.
☐ Only then type them in — unchanged, mistakes included.
```

**Why "nothing open" is the whole point.** Writing correct C with a compiler one
keystroke away is a different skill from writing it with nothing to ask, and the
second is the one that decays without announcing it. If the editor is open the
number this produces is not a measurement of anything.

**Why both before compiling.** A screen does not let you iterate. Compiling
after the first problem turns the second into an easier exercise, and the point
is to find out what happens when you cannot check.

**Why the per-problem time is recorded.** If the forty-five minutes run out,
"thought too long" and "wrote too slowly" call for opposite responses, and
without a per-problem time the log cannot tell them apart.

---

## Problem 1 — reassemble a numbered sequence

You are given an array of fragments. Each fragment carries a sequence number, a
pointer to some bytes, and a length. They may arrive in **any order**, and the
set may be **incomplete**.

```c
struct frag {
    unsigned int  seq;      /* 0, 1, 2, ... */
    const unsigned char *data;
    size_t        len;
};

/* Reassemble frags[0..n-1] into out[0..out_cap-1].
 *
 * Sequence numbers must be exactly 0..n-1 with no gap and no repeat.
 * On success, write the total byte count through *out_len and return 0.
 * On any problem, return non-zero and do not write to out at all.
 */
int reassemble(const struct frag *frags, size_t n,
               unsigned char *out, size_t out_cap, size_t *out_len);
```

**What it must refuse, and this list is the problem:**

- a gap in the sequence numbers — `0, 1, 3`
- a repeat — `0, 1, 1`
- a total length larger than `out_cap`
- `n == 0`
- any fragment with `data == NULL` and `len != 0`

Write it in C. No allocation. Do not modify `frags`.

> **Before you write any code, write down on the paper how you are going to
> detect a gap and a repeat at the same time, and what that costs.** There is an
> obvious way that needs a scratch array you are not allowed to allocate, and a
> less obvious one that does not. Deciding this on paper first is the exercise;
> discovering it halfway through the loop is what a screen is looking for.

---

## Problem 2 — count the pieces a message splits into

```c
/* How many packets a message of msg_len bytes takes over a transport whose
 * packet payload is mtu bytes, given that ONE extra type byte precedes the
 * whole message and appears in the first packet only.
 *
 * Return the packet count, or 0 if the arguments make no sense.
 */
size_t packet_count(size_t msg_len, size_t mtu);
```

**The cases that decide whether it is right:**

| `msg_len` | `mtu` | answer | why |
|--:|--:|--:|---|
| 63 | 64 | 1 | 63 + 1 type byte is exactly 64 |
| 64 | 64 | 2 | one byte over |
| 0 | 64 | ? | **you decide, and write down which and why** |
| 177 | 64 | 3 | ★ see below |
| 10 | 0 | 0 | nonsense |
| `SIZE_MAX` | 64 | ? | ★★ see below |

★ **177 at MTU 64 separates the right answer from the usual wrong one.** The
common mistake subtracts a 4-byte transport header from the MTU and divides by
59, which gives 4. The header is *outside* the payload. If you get 4 here, you
have written the formula almost everybody writes.

★★ **`SIZE_MAX` is the real question.** `msg_len + 1` overflows, and the
ceiling-division idiom you are about to write — `(a + b - 1) / b` — overflows
again. Both are silent. **Write the overflow-safe version.** If you cannot see
how, write the unsafe one and then write underneath it, in words, where it
overflows; naming the bug is most of the credit.

No division-by-zero, no undefined behaviour, no allocation.

---

## After the clock stops

**This half is worth more than the forty-five minutes.** Do not skip it and do
not do it tomorrow.

```
☐ Type both in EXACTLY as written. Fix nothing on the way in.
☐ Compile with the drills' flags:
      gcc -std=c11 -Wall -Wextra -Werror -fsanitize=address,undefined
☐ Count ERRORS, not lines of compiler output. One missing semicolon that
  cascades into nine messages is one error.
☐ Classify every one as syntax / type / logic — the three have different fixes.
☐ For every LOGIC error, answer in writing: "why did I not think of this
  boundary?" That sentence goes in the mistake book, not the error count.
☐ Fill in the row in ../SCORECARD.md, "timed round 1".
```

### The numbers to record

| | P1 reassemble | P2 packet_count |
|---|---|---|
| minutes taken | | |
| finished inside the box? | | |
| compile errors, unedited | | |
| warnings | | |
| first sanitizer result | | |
| `syntax` / `type` / `logic` | | |

### The three questions that matter more than the count

1. **If you went over time: too long thinking, or too slow writing?** The
   per-problem minutes answer this and nothing else does. Thinking too long
   means more paper dry-runs; writing too slowly means rote repetition.
2. **Problem 1: did you decide the gap-and-repeat strategy before writing the
   loop, or during it?** Write down honestly which. Deciding during it is the
   single most expensive habit on a timed screen.
3. **Problem 2 at `SIZE_MAX`: did you see the overflow unprompted?** The drills
   have asked this once already — `d2_offset_length` is the same class, and it
   is the class of a real libspdm advisory. If it did not transfer from there to
   here, that is the finding, and it is more useful than a low error count.

---

## What this is not

- **Not marked out of ten.** There is no score. The output is the numbers above
  and the three answers, and the point of round 1 is to have a baseline at all
  — rounds 2 and 3 (weeks 11 and 13) are what it gets compared against.
- **Not a solution file.** There is none in this repository, deliberately. The
  compiler is the answer key, and it only becomes one after step 3.
- **Not to be attempted twice.** Once it has been seen, it measures memory. If
  it goes badly, the response is to rewrite the failed problem from scratch a
  week later and say so — not to re-sit this paper.

/*
 * d7_ring_buffer.c — head == tail. Is it empty, or is it full?
 *
 * ┌───────────────────────────────────────────────────────────────────────┐
 * │  THE IMPLEMENTATION IS YOURS TO WRITE. Everything below the marker    │
 * │  "YOUR IMPLEMENTATION STARTS HERE" is stubbed out on purpose.         │
 * │                                                                       │
 * │  The ritual, in order, and the order is the point:                    │
 * │    1. On paper, nothing open, 20 minutes.                             │
 * │    2. Dry-run two cases by hand on that paper. One of them MUST be a  │
 * │       write that wraps past the end of the storage — see "the trap".  │
 * │    3. Type it in. Record how many compile errors you got, unedited.   │
 * │       That number is the only quantifiable measure of progress here,  │
 * │       and it goes into SCORECARD.md.                                  │
 * │    4. `make test` clean, sanitizers included.                         │
 * │                                                                       │
 * │  ★ When you have done step 3, write one line into c-drills/README.md  │
 * │    saying WHICH OF THE TWO DESIGNS you chose and why. Not which one   │
 * │    is better — which one you reached for, and what you gave up.       │
 * │    An interviewer will ask exactly that, and the answer you give      │
 * │    three months from now should be the one you actually had.          │
 * └───────────────────────────────────────────────────────────────────────┘
 *
 * Where this connects to the project
 * ----------------------------------
 * harness/tamper_proxy.py sits between two SPDM emulators and rewrites one
 * byte of a message in flight. Writing it ran into the thing every first TCP
 * program runs into: **a stream is not a sequence of messages.** One `recv`
 * can return half a frame, or two frames, or one and a half. The socket does
 * not know or care where your message boundaries are, and the 12-byte header
 * that says how long the payload is can itself arrive split across two reads.
 *
 * So a reader needs somewhere to put bytes that have arrived and cannot be
 * used yet, and to answer "is a whole frame in here" without consuming
 * anything — because if the answer is no, the bytes have to stay put.
 *
 * That is this file. Python hid it behind a bytearray that grows; C does not,
 * and `transport/af_mctp_glue.c` in week 9 is the same pattern against a
 * kernel socket with a fixed buffer.
 *
 * ★ The trap, and it is the whole drill
 * -------------------------------------
 * A ring buffer is `cap` bytes of storage with a write position and a read
 * position that chase each other around it. Both are in [0, cap). Now:
 *
 *     head == tail
 *
 * The buffer is **empty** — nothing has been written that has not been read.
 * Also, the buffer is **full** — the writer has gone all the way round and
 * caught up with the reader. Those are opposite conditions and the indices
 * cannot tell them apart, because there are cap+1 possible occupancies and
 * only cap distinguishable index pairs.
 *
 * There are exactly two honest ways out, and choosing between them is the
 * exercise:
 *
 *   (a) **Leave one slot empty.** Full is `(head + 1) % cap == tail`. Empty
 *       stays `head == tail`. You can store cap-1 bytes in cap bytes of
 *       storage.
 *
 *   (b) **Carry a count.** Keep `count` bytes-in-use alongside the indices.
 *       Empty is `count == 0`, full is `count == cap`. You can store all cap.
 *
 * ★ The answer to "why (a)?" that is worth having:
 *
 *   In the single-producer / single-consumer case — one thread writing, one
 *   reading, which is what a socket reader IS — design (a) needs no
 *   synchronisation at all. `head` is only ever written by the producer and
 *   `tail` only ever by the consumer. Each side reads the other's index and
 *   writes only its own, so there is no shared mutable word.
 *
 *   Design (b)'s `count` is written by BOTH sides. That makes it a shared
 *   counter, which needs an atomic or a lock, and a lock in a receive path is
 *   a lock in the hot path.
 *
 *   The price of (a) is one wasted byte. The price of (b) is a lock.
 *
 * (This drill is single-threaded and neither design is tested for concurrency.
 * The reasoning is the point; do not add atomics.)
 *
 * ⚠ The second trap, which is where the compile-and-run errors actually land:
 *
 *     rb_len() written as `head - tail`
 *
 * is correct exactly half the time. These are `size_t`. When the writer has
 * wrapped and the reader has not, `head < tail`, the subtraction underflows,
 * and the length comes back as roughly 2^64. It is not undefined behaviour —
 * unsigned wraparound is well-defined — so no sanitizer says a word. The
 * caller then asks for that many bytes.
 *
 * This is d2's arithmetic wearing a different hat, and the fact that you have
 * already done d2 is not evidence you will get this one right: d2 is about a
 * sum that wraps UP past the top, this is a difference that wraps DOWN past
 * zero, and they do not feel like the same mistake while you are making them.
 *
 * ⚠ The third: a write that crosses the end of the storage is **two** memcpys,
 * not one. One memcpy that runs past `buf + cap` is exactly what
 * AddressSanitizer exists for, and the test allocates the storage on the heap
 * so that it fires.
 *
 * Boundaries this must survive
 * ----------------------------
 *   (1) empty and full are distinguishable     -> the whole point
 *   (2) a write that wraps                     -> two copies, both bounded
 *   (3) a read that wraps                      -> same, in the other direction
 *   (4) a short write                           -> accept what fits, report it
 *   (5) rb_len() after a wrap                  -> no underflow
 *   (6) rb_peek does not consume               -> called twice, same answer
 *   (7) n == 0 on every function               -> accepted, changes nothing
 *   (8) cap == 1                               -> design (a) can store nothing
 *                                                 and must SAY so rather than
 *                                                 writing a byte it cannot
 *                                                 read back
 *   (9) a full round trip of 3x the capacity   -> indices keep working after
 *                                                 many wraps, not just one
 *
 * ★ Both designs pass these tests. That is deliberate: the tests are written
 * against rb_capacity(), which is whatever YOUR implementation can hold, not
 * against a number this file picked. A drill that only accepted one of two
 * correct answers would be teaching the answer rather than the question.
 *
 * Build and run:
 *     make d7_ring_buffer && ./d7_ring_buffer
 */

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ── the structure ──────────────────────────────────────────────────────────
 *
 * Both designs' fields are here. Which of them you use IS the decision:
 *
 *   design (a), leave one slot empty  -> buf, cap, head, tail. `count` unused.
 *   design (b), carry a count         -> buf, cap, head, tail, count.
 *
 * Nothing outside your implementation reads these fields — the tests go
 * through the functions — so an unused member is not a correctness problem.
 * It is here so that the choice is yours rather than the struct's.
 */
typedef struct {
    uint8_t *buf;
    size_t   cap;    /* bytes of storage at buf, as handed to rb_init */
    size_t   head;   /* next position to write */
    size_t   tail;   /* next position to read */
    size_t   count;  /* design (b) only */
} rb_t;

/* ── contract ───────────────────────────────────────────────────────────────
 *
 * rb_init(rb, storage, cap)
 *     Point the ring at `cap` bytes at `storage`. The buffer starts empty.
 *     `storage` may be NULL only when cap is 0, and such a ring must behave
 *     like one that is permanently full: rb_capacity 0, rb_len 0, every write
 *     accepts 0 bytes, every read returns 0. It must not be a special case
 *     scattered through the other functions — if the arithmetic is right it
 *     falls out.
 *     The ring does not own the storage and never frees it.
 *
 * rb_capacity(rb)
 *     The largest number of bytes this ring can hold at once. This is the
 *     number the tests measure everything against, and it is where your two
 *     designs differ: cap-1 for (a), cap for (b). For cap == 0 it is 0 under
 *     both.
 *     Must not change as bytes move through.
 *
 * rb_len(rb)
 *     Bytes currently in the ring. 0 <= rb_len <= rb_capacity, ALWAYS, and
 *     that is an assertion the tests make after every operation rather than
 *     only at the end — a length that is briefly 2^64 is a length a caller
 *     will use.
 *     No side effects: it is called from inside assertions.
 *
 * rb_write(rb, src, n)
 *     Copy up to n bytes from src into the ring. Returns how many were
 *     ACCEPTED, which is min(n, rb_capacity - rb_len). A partial write is a
 *     success, not an error: the caller's job is to look at the return value
 *     and keep the rest. Returning 0 when the ring is full is correct and is
 *     not distinguishable from — nor does it need to be distinguishable from —
 *     a request for 0 bytes, because in both cases nothing was taken.
 *     src may be NULL only when n is 0.
 *     The bytes must come out of rb_read in the order they went in.
 *
 * rb_read(rb, dst, n)
 *     Move up to n bytes out of the ring into dst and remove them. Returns how
 *     many were moved, which is min(n, rb_len).
 *     dst may be NULL only when n is 0.
 *
 * rb_peek(rb, dst, n)
 *     Exactly rb_read, EXCEPT that the ring is unchanged. Returns the same
 *     count rb_read would have. Calling it twice must give the same bytes and
 *     the same count both times.
 *     This is the one the project actually needs: a frame reader has to look
 *     at a length prefix before it knows whether a whole frame has arrived,
 *     and if it has not, the prefix must still be there next time.
 *     Must NOT be implemented as read-then-write-back. That works and is
 *     wrong: it is not const-correct, it reorders nothing but could, and on
 *     the day two readers exist it is a bug. Write it as a bounded copy that
 *     touches no index.
 */

void   rb_init(rb_t *rb, uint8_t *storage, size_t cap);
size_t rb_capacity(const rb_t *rb);
size_t rb_len(const rb_t *rb);
size_t rb_write(rb_t *rb, const uint8_t *src, size_t n);
size_t rb_read(rb_t *rb, uint8_t *dst, size_t n);
size_t rb_peek(const rb_t *rb, uint8_t *dst, size_t n);

/* ══════════════════ YOUR IMPLEMENTATION STARTS HERE ══════════════════════ */

void rb_init(rb_t *rb, uint8_t *storage, size_t cap)
{
    (void)rb;
    (void)storage;
    (void)cap;
}

size_t rb_capacity(const rb_t *rb)
{
    (void)rb;
    return 0;
}

size_t rb_len(const rb_t *rb)
{
    (void)rb;
    return 0;
}

size_t rb_write(rb_t *rb, const uint8_t *src, size_t n)
{
    (void)rb;
    (void)src;
    (void)n;
    return 0;
}

size_t rb_read(rb_t *rb, uint8_t *dst, size_t n)
{
    (void)rb;
    (void)dst;
    (void)n;
    return 0;
}

size_t rb_peek(const rb_t *rb, uint8_t *dst, size_t n)
{
    (void)rb;
    (void)dst;
    (void)n;
    return 0;
}

/* ══════════════════ YOUR IMPLEMENTATION ENDS HERE ════════════════════════ */

/* ── tests ──────────────────────────────────────────────────────────────────
 *
 * The storage is always heap-allocated and always exactly the requested size,
 * so a copy that runs one byte past the end is an AddressSanitizer report
 * rather than a value that happens to be right.
 */

static int checks = 0;
static int failures = 0;

static void check(bool cond, const char *what)
{
    checks++;
    if (!cond) {
        failures++;
        printf("  FAIL  %s\n", what);
    }
}

static void check_eq(size_t got, size_t want, const char *what)
{
    checks++;
    if (got != want) {
        failures++;
        printf("  FAIL  %s: got %zu, want %zu\n", what, got, want);
    }
}

/* After every operation, in every test. An invariant checked only at the end
 * is an invariant that has already been violated by the time anyone looks. */
static void invariant(const rb_t *rb, const char *where)
{
    checks++;
    if (rb_len(rb) > rb_capacity(rb)) {
        failures++;
        printf("  FAIL  %s: rb_len %zu exceeds rb_capacity %zu\n",
               where, rb_len(rb), rb_capacity(rb));
    }
}

static uint8_t *storage(size_t n)
{
    uint8_t *p = n ? malloc(n) : NULL;
    if (n && !p) {
        printf("  FAIL  out of memory\n");
        exit(1);
    }
    return p;
}

static void test_empty_and_full_are_different(void)
{
    printf("empty and full are distinguishable\n");
    const size_t cap = 8;
    uint8_t *mem = storage(cap);
    rb_t rb;
    rb_init(&rb, mem, cap);

    const size_t usable = rb_capacity(&rb);
    check(usable == cap || usable == cap - 1,
          "rb_capacity is either cap (a count) or cap-1 (one slot spare)");
    check_eq(rb_len(&rb), 0, "a fresh ring is empty");

    uint8_t in[16];
    for (size_t i = 0; i < sizeof in; i++)
        in[i] = (uint8_t)(0xA0 + i);

    /* Fill it exactly. */
    check_eq(rb_write(&rb, in, usable), usable, "a full-capacity write is accepted");
    invariant(&rb, "after filling");
    check_eq(rb_len(&rb), usable, "a full ring reports its capacity");

    /* ★ The drill. head == tail here under design (a)'s predecessor, and an
     * implementation that cannot tell full from empty reports 0 above and
     * accepts the write below. */
    check_eq(rb_write(&rb, in, 1), 0, "a write into a full ring accepts nothing");
    invariant(&rb, "after a refused write");
    check_eq(rb_len(&rb), usable, "and the refused write changed nothing");

    uint8_t out[16];
    memset(out, 0, sizeof out);
    check_eq(rb_read(&rb, out, sizeof out), usable, "everything comes back");
    check(memcmp(out, in, usable) == 0, "and in the order it went in");
    check_eq(rb_len(&rb), 0, "and the ring is empty again");
    invariant(&rb, "after draining");

    free(mem);
}

static void test_a_write_that_wraps(void)
{
    printf("a write that crosses the end of the storage\n");
    const size_t cap = 8;
    uint8_t *mem = storage(cap);
    rb_t rb;
    rb_init(&rb, mem, cap);
    const size_t usable = rb_capacity(&rb);
    /* `usable - 1` below is size_t arithmetic, and a ring that reports a
     * capacity of zero -- which the stub does, and which is the FIRST thing
     * anyone runs this against -- makes it SIZE_MAX. The test would then ask
     * for a write of 2^64 bytes and print a want of 18446744073709551615,
     * which is this drill's own trap turning up inside the test that teaches
     * it. Guarded rather than left as a curiosity. */
    if (usable < 2) {
        free(mem);
        return;
    }

    uint8_t in[32], out[32];
    for (size_t i = 0; i < sizeof in; i++)
        in[i] = (uint8_t)(i + 1);

    /* Push the indices most of the way round, then drain, so that the next
     * write starts near the end and has to split. */
    size_t nudged = usable - 1;
    check_eq(rb_write(&rb, in, nudged), nudged, "a partial fill");
    check_eq(rb_read(&rb, out, nudged), nudged, "drained again");
    check_eq(rb_len(&rb), 0, "empty, with head and tail well away from zero");
    invariant(&rb, "after the nudge");

    /* ★ This one wraps. A single memcpy here runs past the end of `mem`. */
    check_eq(rb_write(&rb, in, usable), usable, "a wrapping write is accepted whole");
    invariant(&rb, "after a wrapping write");
    check_eq(rb_len(&rb), usable, "and the length is right after a wrap");

    memset(out, 0, sizeof out);
    check_eq(rb_read(&rb, out, usable), usable, "a wrapping read returns it all");
    check(memcmp(out, in, usable) == 0, "byte for byte, in order, across the seam");
    invariant(&rb, "after a wrapping read");

    free(mem);
}

static void test_short_writes_and_reads(void)
{
    printf("a request larger than there is room for\n");
    const size_t cap = 8;
    uint8_t *mem = storage(cap);
    rb_t rb;
    rb_init(&rb, mem, cap);
    const size_t usable = rb_capacity(&rb);

    uint8_t in[64], out[64];
    for (size_t i = 0; i < sizeof in; i++)
        in[i] = (uint8_t)(i ^ 0x5Au);

    check_eq(rb_write(&rb, in, sizeof in), usable,
             "an oversized write takes what fits and says how much");
    invariant(&rb, "after an oversized write");
    /* Which bytes it took is checked by reading them back, not by looking at
     * the storage: where rb_init puts head is the implementation's business,
     * and a test that reads `mem` directly is a test of a field the contract
     * does not mention. */

    memset(out, 0, sizeof out);
    check_eq(rb_read(&rb, out, sizeof out), usable,
             "an oversized read takes what there is");
    check(memcmp(out, in, usable) == 0, "and it is the prefix of the input");
    check_eq(rb_read(&rb, out, sizeof out), 0, "a read from an empty ring takes nothing");
    invariant(&rb, "after an empty read");

    free(mem);
}

static void test_peek_does_not_consume(void)
{
    printf("peek looks without taking\n");
    const size_t cap = 8;
    uint8_t *mem = storage(cap);
    rb_t rb;
    rb_init(&rb, mem, cap);
    const size_t usable = rb_capacity(&rb);
    if (usable < 4) {
        free(mem);
        return;
    }

    const uint8_t frame[4] = {0x00, 0x00, 0x00, 0x01};
    check_eq(rb_write(&rb, frame, 4), 4, "four bytes in");

    uint8_t a[4] = {0}, b[4] = {0};
    check_eq(rb_peek(&rb, a, 4), 4, "peek reports four");
    check_eq(rb_len(&rb), 4, "and the ring still holds four");
    check_eq(rb_peek(&rb, b, 4), 4, "peek again reports four");
    check(memcmp(a, b, 4) == 0, "and the same four bytes");
    check(memcmp(a, frame, 4) == 0, "which are the ones written");
    invariant(&rb, "after peeking");

    /* The pattern the project needs: peek a length, decide there is not
     * enough, leave everything where it was. */
    uint8_t big[8] = {0};
    check_eq(rb_peek(&rb, big, 8), 4, "peeking for more than there is returns what there is");
    check_eq(rb_len(&rb), 4, "and still takes nothing");

    check_eq(rb_read(&rb, a, 4), 4, "and the bytes are still there to read");
    check_eq(rb_len(&rb), 0, "now it is empty");
    invariant(&rb, "at the end");

    free(mem);
}

static void test_a_peek_that_wraps(void)
{
    printf("peek across the seam\n");
    const size_t cap = 8;
    uint8_t *mem = storage(cap);
    rb_t rb;
    rb_init(&rb, mem, cap);
    const size_t usable = rb_capacity(&rb);
    if (usable < 3) {
        free(mem);
        return;
    }

    uint8_t in[16], out[16], scratch[16];
    for (size_t i = 0; i < sizeof in; i++)
        in[i] = (uint8_t)(0x10 + i);

    size_t nudged = usable - 1;
    check_eq(rb_write(&rb, in, nudged), nudged, "fill most of it");
    check_eq(rb_read(&rb, scratch, nudged), nudged, "and drain it");
    check_eq(rb_write(&rb, in, usable), usable, "now a wrapping fill");

    memset(out, 0, sizeof out);
    check_eq(rb_peek(&rb, out, usable), usable, "peek returns all of it");
    check(memcmp(out, in, usable) == 0, "in order, across the seam");
    check_eq(rb_len(&rb), usable, "and consumed none of it");
    invariant(&rb, "after a wrapping peek");

    free(mem);
}

static void test_zero_and_degenerate(void)
{
    printf("zero-length requests, and a ring with no room\n");
    const size_t cap = 8;
    uint8_t *mem = storage(cap);
    rb_t rb;
    rb_init(&rb, mem, cap);

    uint8_t byte = 0x7F;
    check_eq(rb_write(&rb, NULL, 0), 0, "a zero-length write is accepted and takes nothing");
    check_eq(rb_read(&rb, NULL, 0), 0, "a zero-length read likewise");
    check_eq(rb_peek(&rb, NULL, 0), 0, "a zero-length peek likewise");
    check_eq(rb_len(&rb), 0, "and none of them changed the ring");
    invariant(&rb, "after zero-length calls");

    check_eq(rb_write(&rb, &byte, 1), 1, "and the ring still works afterwards");
    free(mem);

    /* cap == 0: no storage at all. Under either design this holds nothing, and
     * it must say so rather than writing through a NULL pointer. */
    rb_t none;
    rb_init(&none, NULL, 0);
    check_eq(rb_capacity(&none), 0, "a ring with no storage has no capacity");
    check_eq(rb_len(&none), 0, "and no contents");
    check_eq(rb_write(&none, &byte, 1), 0, "and accepts nothing");
    check_eq(rb_read(&none, &byte, 1), 0, "and returns nothing");
    check_eq(rb_peek(&none, &byte, 1), 0, "and shows nothing");
    invariant(&none, "the empty ring");

    /* cap == 1: design (a) can hold nothing; design (b) can hold one byte.
     * Both are correct and the test asks only that the implementation agrees
     * with itself. */
    uint8_t one[1];
    rb_t tiny;
    rb_init(&tiny, one, 1);
    size_t tcap = rb_capacity(&tiny);
    check(tcap <= 1, "a one-byte ring holds at most one byte");
    check_eq(rb_write(&tiny, &byte, 1), tcap, "and accepts exactly what it says it can");
    check_eq(rb_len(&tiny), tcap, "and then reports that much");
    uint8_t back = 0;
    check_eq(rb_read(&tiny, &back, 1), tcap, "and gives it back");
    if (tcap == 1)
        check(back == byte, "unchanged");
    invariant(&tiny, "the one-byte ring");
}

static void test_many_wraps(void)
{
    printf("three times round, one byte at a time\n");
    const size_t cap = 5;
    uint8_t *mem = storage(cap);
    rb_t rb;
    rb_init(&rb, mem, cap);
    const size_t usable = rb_capacity(&rb);
    if (usable == 0) {
        free(mem);
        return;
    }

    /* A single wrap can be got right by accident. Many cannot, and this is
     * also where an rb_len written as head - tail underflows: it is called
     * after every single step. */
    uint8_t v = 0, got = 0;
    int wrong_order = 0;
    for (size_t i = 0; i < cap * 3 + 2; i++) {
        check_eq(rb_write(&rb, &v, 1), 1, "one byte in");
        invariant(&rb, "mid-loop, after a write");
        check_eq(rb_len(&rb), 1, "one byte held");
        check_eq(rb_read(&rb, &got, 1), 1, "one byte out");
        invariant(&rb, "mid-loop, after a read");
        if (got != v)
            wrong_order++;
        v++;
    }
    check_eq((size_t)wrong_order, 0, "every byte came out as itself");
    check_eq(rb_len(&rb), 0, "and the ring ends empty");

    free(mem);
}

int main(void)
{
    /* Line-buffered, so that when a sanitizer aborts, the check that was
     * being run has already been printed. Learned the hard way in d2:
     * a stack trace with no context is a stack trace you cannot place. */
    setvbuf(stdout, NULL, _IOLBF, 0);

    test_empty_and_full_are_different();
    test_a_write_that_wraps();
    test_short_writes_and_reads();
    test_peek_does_not_consume();
    test_a_peek_that_wraps();
    test_zero_and_degenerate();
    test_many_wraps();

    printf("\n%d checks, %d failed\n", checks, failures);
    return failures ? 1 : 0;
}

/*
 * d2_offset_length.c — the bounds check that is wrong in a way that passes.
 *
 * ┌───────────────────────────────────────────────────────────────────────┐
 * │  THE IMPLEMENTATION IS YOURS TO WRITE. Everything below the marker    │
 * │  "YOUR IMPLEMENTATION STARTS HERE" is stubbed out on purpose.         │
 * │                                                                       │
 * │  The ritual, in order, and the order is the point:                    │
 * │    1. On paper, nothing open, 10 minutes. The shortest drill here.    │
 * │    2. Dry-run two cases by hand on that paper. One of them MUST be    │
 * │       off = SIZE_MAX, len = 2, total = 1 — see "the trap".            │
 * │    3. Type it in. Record how many compile errors you got, unedited.   │
 * │       That number is the only quantifiable measure of progress here,  │
 * │       and it goes into SCORECARD.md.                                  │
 * │    4. `make test` clean, sanitizers included.                         │
 * │                                                                       │
 * │  ★ When you have done step 3, write one line into c-drills/README.md  │
 * │    saying which version you wrote FIRST. If it was the wrong one, say │
 * │    so. That sentence is worth more than a passing test, because it is │
 * │    the only evidence in this repository about what you actually       │
 * │    reach for under time pressure.                                     │
 * └───────────────────────────────────────────────────────────────────────┘
 *
 * Where this connects to the project
 * ----------------------------------
 * This is not a puzzle. It is a CVE class, and it is a CVE class in the
 * library this repository is built on.
 *
 *   GHSA-m4wc-xmvg-369f — libspdm, GET_MEASUREMENT_EXTENSION_LOG. A requester
 *   asks for a slice of the log by offset and length; the responder adds them
 *   together to check the slice fits; the addition wraps; the check passes; the
 *   copy reads outside the buffer. Affected 3.4 through 3.8.1, fixed in 3.8.2.
 *
 *   third_party/libspdm-*.pin says which commit this project builds. The fix
 *   is in it. The class is not.
 *
 * It is also the shape of code this project keeps writing. Every parser here
 * takes a declared length out of a message and then trusts it exactly as far
 * as it has checked it:
 *
 *   harness/tamper_proxy.py     MeasurementRecordLength, OpaqueDataLength, and
 *                               a block's MeasurementSize, all attacker-chosen
 *                               in the threat model the proxy embodies
 *   bench/pcapstat.py           PortionLength, from the responder
 *   harness/fields.py           every reconstruction in it
 *
 * Python raises on a bad slice. C does not, and the difference is this file.
 *
 * ★ The trap, and it is the whole drill
 * -------------------------------------
 * The obvious check is
 *
 *     return off + len <= total;              // <- do not
 *
 * and it is wrong for exactly one reason: `size_t` arithmetic wraps. It is
 * unsigned, so this is not undefined behaviour — it is worse than undefined
 * behaviour, because it is well-defined and silently false.
 *
 *     off   = SIZE_MAX        (0xFFFFFFFFFFFFFFFF on this machine)
 *     len   = 2
 *     total = 1
 *
 *     off + len  ==  SIZE_MAX + 2  ==  1        (mod 2^64)
 *     1 <= 1     ==  true                       -> "the range fits"
 *
 * and the caller then reads two bytes starting at byte SIZE_MAX of a one-byte
 * buffer. Nothing in the arithmetic complained. UndefinedBehaviourSanitizer
 * will not complain either, because unsigned wraparound is legal C.
 *
 * The version that is right:
 *
 *     return off <= total && len <= total - off;
 *
 * `total - off` cannot wrap because the first half already proved off <= total.
 * The order of the two halves is load-bearing and && is a sequence point —
 * write them the other way round and the subtraction happens first.
 *
 * ⚠ There is a third version that looks clever and is not:
 *
 *     return len <= total && off <= total - len;
 *
 * It is also correct. It is not the same check: it answers "is there room for
 * len bytes somewhere" first. Both are fine. What is NOT fine is any version
 * that computes off + len, however it is bracketed, and any version that
 * casts to a signed type on the way — a cast to `long` is the same bug with a
 * different overflow, and that one really is undefined.
 *
 * Boundaries this must survive
 * ----------------------------
 *   (1) off + len wraps               -> must be REFUSED (the CVE)
 *   (2) off == total, len == 0        -> must be ACCEPTED, an empty slice at
 *                                        the end is a legal answer, and the
 *                                        parsers above rely on it to end a walk
 *   (3) off == total, len == 1        -> refused
 *   (4) total == 0                    -> only off == 0, len == 0 is accepted
 *   (5) len == SIZE_MAX               -> refused for any total below it
 *   (6) the exactly-fits case         -> off + len == total is accepted
 *   (7) copy_range bounds BOTH ends   -> a source range that fits does not
 *                                        make room in a destination that does
 *                                        not. Two buffers, two checks.
 *
 * Build and run:
 *     make d2_offset_length && ./d2_offset_length
 */

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

/* ── contract ───────────────────────────────────────────────────────────────
 *
 * range_ok(off, len, total)
 *     True when the half-open range [off, off + len) lies entirely inside a
 *     buffer of `total` bytes. Must be correct for EVERY triple of size_t
 *     values, including ones whose sum wraps. Must not compute off + len.
 *     Must not use any type wider than size_t, and must not cast to a signed
 *     type — "use unsigned __int128" is not the answer being taught, and it is
 *     not available on every target this repository claims to describe.
 *     No side effects: it is called from inside assertions.
 *
 * slice(buf, total, off, len)
 *     Returns a pointer to the first byte of the range if range_ok says it
 *     fits, and NULL otherwise. buf may be NULL only when total is 0, and in
 *     that case the only acceptable range is off == 0, len == 0, for which the
 *     return value must still be NULL — there is no valid pointer to hand back
 *     and inventing one is how a zero-length success becomes a crash later.
 *     For a non-NULL buf and off == total the answer is buf + total, which is
 *     a legal pointer to form and not to dereference (C11 6.5.6p8 allows one
 *     past the end); returning NULL there would make "the walk finished" and
 *     "the walk was refused" the same value.
 *     Must not form the pointer buf + off before deciding: computing an
 *     out-of-bounds pointer is undefined even if it is never dereferenced
 *     (C11 6.5.6p8), and UBSan's pointer-overflow check will say so.
 *
 * copy_range(dst, dst_cap, src, total, off, len)
 *     Copies len bytes from src[off] into dst, and returns the number of bytes
 *     copied, or 0 if it refused. It must refuse unless BOTH
 *         the source range fits in total, and
 *         len fits in dst_cap.
 *     Returning 0 for a genuine zero-length request is not ambiguous here:
 *         nothing was copied either way, and no caller can tell the two apart
 *         because there is nothing to tell apart.
 *     dst and src never overlap.
 */

bool   range_ok(size_t off, size_t len, size_t total);
const uint8_t *slice(const uint8_t *buf, size_t total, size_t off, size_t len);
size_t copy_range(uint8_t *dst, size_t dst_cap,
                  const uint8_t *src, size_t total, size_t off, size_t len);

/* ══════════════════ YOUR IMPLEMENTATION STARTS HERE ═══════════════════════ */

bool range_ok(size_t off, size_t len, size_t total)
{
    (void)off;
    (void)len;
    (void)total;
    /* TODO — and whatever you do, do not write off + len */
    return false;
}

const uint8_t *slice(const uint8_t *buf, size_t total, size_t off, size_t len)
{
    (void)buf;
    (void)total;
    (void)off;
    (void)len;
    /* TODO */
    return NULL;
}

size_t copy_range(uint8_t *dst, size_t dst_cap,
                  const uint8_t *src, size_t total, size_t off, size_t len)
{
    (void)dst;
    (void)dst_cap;
    (void)src;
    (void)total;
    (void)off;
    (void)len;
    /* TODO — two ranges, two checks */
    return 0;
}

/* ══════════════════ YOUR IMPLEMENTATION ENDS HERE ═════════════════════════ */

/* ── tests ────────────────────────────────────────────────────────────────── */

static int g_failures = 0;
static int g_checks   = 0;

#define CHECK(cond, what)                                                     \
    do {                                                                      \
        g_checks++;                                                           \
        if (cond) {                                                           \
            printf("  ok    %s\n", (what));                                   \
        } else {                                                              \
            printf("  FAIL  %s   (%s:%d)\n", (what), __FILE__, __LINE__);     \
            g_failures++;                                                     \
        }                                                                     \
    } while (0)

/* The 528-byte measurement record this project reads out of every capture,
 * and the block inside it that harness/tamper_proxy.py changes. The numbers
 * are the real ones so that the arithmetic in the tests is the arithmetic the
 * project actually does:
 *
 *   record          528 bytes
 *   block 0x01      at 0, four bytes of header, then a 67-byte Measurement
 *   its value       at 7, 64 bytes — the SHA-512 the responder computed
 *   the flipped byte at 7 + 36 = 43
 */
#define RECORD_BYTES   528u
#define BLOCK_VALUE_AT   7u
#define BLOCK_VALUE_LEN 64u

static void test_the_cve(void)
{
    printf("boundary 1 — the addition that wraps, which is the whole drill\n");

    /* SIZE_MAX + 2 == 1 on a 64-bit size_t, so `off + len <= total` says yes.
     * These are called through range_ok rather than slice on purpose: an
     * implementation that forms buf + SIZE_MAX has already committed undefined
     * behaviour before it can return, and a drill that aborts inside the
     * function it is testing cannot report which check failed. */
    CHECK(!range_ok(SIZE_MAX, 2, 1),
          "off = SIZE_MAX, len = 2, total = 1 is refused   <- GHSA-m4wc-xmvg-369f");
    CHECK(!range_ok(SIZE_MAX, 1, 0),
          "off = SIZE_MAX, len = 1, total = 0 is refused");
    CHECK(!range_ok(2, SIZE_MAX, 1),
          "off = 2, len = SIZE_MAX, total = 1 is refused");
    CHECK(!range_ok(SIZE_MAX, SIZE_MAX, SIZE_MAX),
          "off = len = total = SIZE_MAX is refused: the sum wraps to -2");
    CHECK(range_ok(0, SIZE_MAX, SIZE_MAX),
          "off = 0, len = total = SIZE_MAX is accepted: it genuinely fits");
    CHECK(range_ok(SIZE_MAX, 0, SIZE_MAX),
          "off = total = SIZE_MAX, len = 0 is accepted: empty, at the end");
}

static void test_the_end_of_the_buffer(void)
{
    printf("boundaries 2, 3 and 6 — the last byte, and the one after it\n");

    CHECK(range_ok(0, RECORD_BYTES, RECORD_BYTES),
          "the whole record fits in the record");
    CHECK(range_ok(RECORD_BYTES - 1, 1, RECORD_BYTES),
          "the last byte fits");
    CHECK(range_ok(RECORD_BYTES, 0, RECORD_BYTES),
          "an empty range at the very end is accepted   <- a walk ends here");
    CHECK(!range_ok(RECORD_BYTES, 1, RECORD_BYTES),
          "one byte at the very end is refused");
    CHECK(!range_ok(RECORD_BYTES + 1, 0, RECORD_BYTES),
          "an empty range PAST the end is refused");
    CHECK(!range_ok(0, RECORD_BYTES + 1, RECORD_BYTES),
          "one byte more than the record is refused");
}

static void test_empty_buffer(void)
{
    printf("boundary 4 — nothing at all\n");

    CHECK(range_ok(0, 0, 0), "an empty range in an empty buffer is accepted");
    CHECK(!range_ok(0, 1, 0), "one byte in an empty buffer is refused");
    CHECK(!range_ok(1, 0, 0), "an empty range at offset 1 of nothing is refused");
    CHECK(slice(NULL, 0, 0, 0) == NULL,
          "slice of an empty buffer returns NULL rather than a made-up pointer");
}

static void test_slice_returns_the_right_bytes(void)
{
    printf("slice — the pointer, and where it points\n");

    /* A stand-in for one measurement block: four bytes of header, then a
     * Measurement whose value starts three bytes further in. */
    static uint8_t block[4 + 3 + BLOCK_VALUE_LEN];
    for (size_t i = 0; i < sizeof block; i++) {
        block[i] = (uint8_t)i;
    }

    const uint8_t *value = slice(block, sizeof block, BLOCK_VALUE_AT,
                                 BLOCK_VALUE_LEN);
    CHECK(value == block + BLOCK_VALUE_AT,
          "the 64-byte value is found at offset 7");
    CHECK(value != NULL && value[36] == (uint8_t)(BLOCK_VALUE_AT + 36),
          "byte 36 of that value is the byte the proxy flips");

    CHECK(slice(block, sizeof block, 0, sizeof block) == block,
          "the whole buffer slices to its own first byte");
    CHECK(slice(block, sizeof block, sizeof block, 0) == block + sizeof block,
          "an empty slice at the end is one past the end, not NULL");
    CHECK(slice(block, sizeof block, 1, sizeof block) == NULL,
          "a slice one byte too long returns NULL");
    CHECK(slice(block, sizeof block, SIZE_MAX, 2) == NULL,
          "the wrapping slice returns NULL");
}

static void test_copy_bounds_both_ends(void)
{
    printf("boundary 7 — two buffers, and both of them have an end\n");

    static const uint8_t src[16] = {
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
    };
    uint8_t dst[8];

    memset(dst, 0xAA, sizeof dst);
    CHECK(copy_range(dst, sizeof dst, src, sizeof src, 4, 8) == 8,
          "eight bytes from offset 4 into an eight-byte buffer");
    CHECK(dst[0] == 4 && dst[7] == 11, "and they are the right eight bytes");

    memset(dst, 0xAA, sizeof dst);
    CHECK(copy_range(dst, sizeof dst, src, sizeof src, 0, 9) == 0,
          "nine bytes into an eight-byte buffer is refused");
    CHECK(dst[0] == 0xAA,
          "and nothing was written before it decided   <- check, then copy");

    memset(dst, 0xAA, sizeof dst);
    CHECK(copy_range(dst, sizeof dst, src, sizeof src, 12, 8) == 0,
          "eight bytes from offset 12 of a sixteen-byte source is refused");
    CHECK(dst[0] == 0xAA, "and nothing was written");

    CHECK(copy_range(dst, sizeof dst, src, sizeof src, SIZE_MAX, 2) == 0,
          "the wrapping source range is refused");
    CHECK(copy_range(dst, SIZE_MAX, src, sizeof src, 0, SIZE_MAX) == 0,
          "a destination big enough does not make the source big enough");
}

static void test_the_wrong_version_would_be_caught(void)
{
    printf("the trap, stated as a test rather than as a comment\n");

    /* If range_ok were written as `off + len <= total`, exactly these four
     * would return true. They are separated out so that a failing run says
     * "you wrote the CVE" instead of "something is wrong".
     *
     * There is no way for a correct implementation to distinguish this test
     * from the one above; that is fine. Its job is to name the failure. */
    const bool wrote_the_cve =
        range_ok(SIZE_MAX, 2, 1) || range_ok(SIZE_MAX, 1, 0)
        || range_ok(SIZE_MAX - 3, 8, 4) || range_ok(2, SIZE_MAX, 1);

    CHECK(!wrote_the_cve,
          "none of the four wrapping triples is accepted");
    if (wrote_the_cve) {
        printf("        ^ this is `off + len <= total`. It is the bug in\n"
               "          GHSA-m4wc-xmvg-369f. Write off <= total && len <= total - off.\n");
    }
}

int main(void)
{
    /* Line-buffer stdout. Without this, a drill that dies inside a
     * sanitizer prints NOTHING when its output is redirected to a file, and
     * the reader gets a stack trace with no idea which check was reached.
     * The trace says where the bug is; this says how far you got. */
    setvbuf(stdout, NULL, _IOLBF, 0);

    printf("d2 — offset plus length, and the addition that lies\n\n");

    /* The naming test runs second, not last, and the order is deliberate.
     * `off + len <= total` does not merely return the wrong answer: it makes
     * copy_range read two bytes at src + SIZE_MAX, which wraps the address
     * space to src - 1, and AddressSanitizer stops the program there. Anything
     * printed after that point is never printed at all. So the sentence that
     * says WHICH mistake was made has to come before the mistake is acted on. */
    test_the_cve();                        printf("\n");
    test_the_wrong_version_would_be_caught(); printf("\n");
    test_the_end_of_the_buffer();          printf("\n");
    test_empty_buffer();                   printf("\n");
    test_slice_returns_the_right_bytes();  printf("\n");
    test_copy_bounds_both_ends();

    printf("\n%d/%d checks passed\n", g_checks - g_failures, g_checks);
    if (g_failures != 0) {
        printf("\n%d check(s) failed. If every one failed, the implementation\n"
               "is still stubbed out — that is the exercise, go write it.\n",
               g_failures);
        return 1;
    }
    printf("d2 PASS\n");
    return 0;
}

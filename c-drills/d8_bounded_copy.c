/*
 * d8_bounded_copy.c — copying a string into a buffer that may be too small.
 *
 * ┌───────────────────────────────────────────────────────────────────────┐
 * │  THE IMPLEMENTATION IS YOURS TO WRITE. Everything below the marker    │
 * │  "YOUR IMPLEMENTATION STARTS HERE" is stubbed out on purpose.         │
 * │                                                                       │
 * │  The ritual, in order, and the order is the point:                    │
 * │    1. On paper, nothing open, 15 minutes.                             │
 * │    2. Dry-run two cases by hand on that paper. One of them MUST be    │
 * │       dstsz == 0 — see boundary (1); it is the one people write last  │
 * │       and the one the compiler cannot remind you about.               │
 * │    3. Type it in. Record how many compile errors you got. That number │
 * │       is the only quantifiable measure of progress here — write it    │
 * │       into SCORECARD.md, with each error classified syntax/type/logic.│
 * │    4. `make test` clean, sanitizers included.                         │
 * └───────────────────────────────────────────────────────────────────────┘
 *
 * Where this connects to the project
 * ----------------------------------
 * GHSA-j54w-759w-xj3m, libspdm, fixed in 3.8.2 and present from 3.0.
 *
 * `GET_CSR` carries a `RequesterInfo` field whose length is given by the
 * requester. The responder passed it into the mbedTLS backend, which built a
 * certificate-request subject from it in a fixed-size stack buffer. A long
 * enough `RequesterInfo` wrote past the end of that buffer — a stack
 * out-of-bounds write, reachable before authentication, from the wire.
 *
 * The shape is not "someone forgot to check a length". The length WAS checked,
 * against what the specification allows. It was not checked against what the
 * implementation had allocated, and those are two different numbers that a
 * reader assumes are the same one. `negative/test_oversized_field.c` in week 11
 * reproduces the class; this drill is the arithmetic on paper first.
 *
 * ★ Why not `strncpy`, and you have to be able to say it
 * ------------------------------------------------------
 * `strncpy(dst, src, n)` does two surprising things, in opposite directions:
 *
 *   * when src is SHORTER than n, it pads the whole rest of dst with NULs.
 *     Copying a 3-byte name into a 4,096-byte buffer writes 4,096 bytes.
 *   * when src is LONGER than or equal to n, it does NOT write a terminating
 *     NUL. dst is left as a character array that is not a string, and the next
 *     `strlen` on it runs off the end.
 *
 * Both follow from what it was for: it was written for fixed-width record
 * fields — the kind that pad with NULs and have no terminator, like a UNIX v7
 * directory entry — and not for copying strings. Reaching for it because the
 * name has an `n` in it is how the second behaviour gets shipped.
 *
 * ★ The return value is the whole design question
 * -----------------------------------------------
 * There are two candidates and only one of them is usable:
 *
 *   (a) how many characters were COPIED. Then a caller who gets back
 *       `dstsz - 1` cannot tell "it fitted exactly" from "it was truncated",
 *       and truncation is precisely the event the caller has to handle.
 *   (b) how many characters it WANTED to copy — the length of src. Then
 *       `returned >= dstsz` is the truncation test, and it is the same
 *       convention `snprintf` uses, which is why `snprintf` can be checked at
 *       all.
 *
 * ★ This drill requires (b). Not because (a) is wrong in some abstract way,
 * but because a function whose result cannot distinguish success from silent
 * loss has moved the bug to every one of its call sites.
 *
 * `snprintf` has exactly this contract and exactly this trap: it returns the
 * length it WOULD have written, so `if (snprintf(buf, n, ...) >= n)` is the
 * truncation check and `strlen(buf)` after the call is not.
 *
 * Boundaries this must survive
 * ----------------------------
 *   (1) dstsz == 0            -> write NOTHING. Not even a NUL; there is
 *                                nowhere to put one. Still return src's length.
 *   (2) truncation            -> dst is still a valid NUL-terminated string
 *   (3) exact fit             -> strlen(src) == dstsz - 1 is NOT truncation
 *   (4) empty src             -> dst becomes "", return 0
 *   (5) no write past the end -> checked by a canary AND by AddressSanitizer
 *                                against a heap block of exactly dstsz bytes
 *   (6) no read past the data -> ★ the one a memcpy-based version fails.
 *                                safe_copy must not read past src's NUL, and
 *                                safe_copy_n must not read src[srclen] at all,
 *                                because in the case that matters there is no
 *                                byte there
 *
 * dst and src never overlap. Neither is NULL, except that dst may be NULL when
 * dstsz is 0 — which is what a caller measuring a length before allocating
 * does, and boundary (1) has to survive it.
 *
 * Build and run:
 *     make d8_bounded_copy && ./d8_bounded_copy
 */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ── contract ───────────────────────────────────────────────────────────────
 *
 * safe_copy(dst, dstsz, src)
 *     Copies the NUL-terminated string src into dst, which is dstsz bytes.
 *     Writes at most dstsz bytes in total, and when dstsz > 0 the last byte
 *     written is a NUL. When dstsz == 0 nothing is written and dst may be NULL.
 *     RETURNS strlen(src) — what it wanted to copy, not what it managed to.
 *     The caller tests `returned >= dstsz` for truncation.
 *
 * safe_copy_n(dst, dstsz, src, srclen)
 *     ★ The protocol-field version, and the one the advisory is about. src is
 *     srclen bytes of DATA and is NOT NUL-terminated; srclen came off the wire.
 *     Copies as much of it as fits, NUL-terminates when dstsz > 0, and must
 *     never read src[srclen] — in the test that matters, that byte does not
 *     belong to the program.
 *     RETURNS srclen, under the same convention as above.
 *
 * Neither may call the other, and neither may call strncpy, strcpy, strlcpy,
 * stpcpy or snprintf. strlen, memcpy and memchr are fine; the exercise is the
 * arithmetic around them, not their absence.
 */

size_t safe_copy(char *dst, size_t dstsz, const char *src);
size_t safe_copy_n(char *dst, size_t dstsz, const char *src, size_t srclen);

/* ══════════════════ YOUR IMPLEMENTATION STARTS HERE ═══════════════════════ */

size_t safe_copy(char *dst, size_t dstsz, const char *src)
{
    (void)dst;
    (void)dstsz;
    (void)src;
    /* TODO */
    return 0;
}

size_t safe_copy_n(char *dst, size_t dstsz, const char *src, size_t srclen)
{
    (void)dst;
    (void)dstsz;
    (void)src;
    (void)srclen;
    /* TODO */
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

/* A buffer with a guard byte on each side, so that a write one past the end is
 * a failed CHECK with a name rather than only a sanitizer trace. Both are
 * wanted: the sanitizer says where, this says which rule was broken. */
#define GUARD 0x7E
struct guarded {
    unsigned char before;
    char          buf[32];
    unsigned char after;
};

static void guarded_init(struct guarded *g)
{
    g->before = GUARD;
    g->after  = GUARD;
    memset(g->buf, 0x5A, sizeof g->buf);   /* not NUL: an implementation that
                                            * forgets to terminate must not be
                                            * rescued by a zeroed buffer */
}

static int guards_intact(const struct guarded *g)
{
    return g->before == GUARD && g->after == GUARD;
}

static void test_ordinary(void)
{
    printf("the ordinary case\n");

    struct guarded g;
    guarded_init(&g);
    size_t r = safe_copy(g.buf, sizeof g.buf, "ROM");

    CHECK(r == 3, "returns the length of src");
    CHECK(strcmp(g.buf, "ROM") == 0, "dst holds the string");
    CHECK(r < sizeof g.buf, "returned < dstsz, so the caller sees no truncation");
    CHECK(guards_intact(&g), "nothing outside the buffer was touched");
    CHECK(g.buf[4] == 0x5A,
          "nothing past the NUL was written — a strncpy-shaped version pads "
          "the whole buffer here");
}

static void test_empty_source(void)
{
    printf("boundary 4 — an empty source\n");

    struct guarded g;
    guarded_init(&g);
    size_t r = safe_copy(g.buf, sizeof g.buf, "");

    CHECK(r == 0, "returns 0");
    CHECK(g.buf[0] == '\0', "dst is the empty string");
    CHECK(guards_intact(&g), "guards intact");
}

static void test_exact_fit(void)
{
    printf("boundary 3 — an exact fit is not a truncation\n");

    char small[4];
    memset(small, 0x5A, sizeof small);
    size_t r = safe_copy(small, sizeof small, "abc");

    CHECK(r == 3, "returns 3");
    CHECK(r < sizeof small, "3 < 4, so the caller must NOT read this as truncation");
    CHECK(strcmp(small, "abc") == 0, "all three characters and a NUL");
}

static void test_truncation(void)
{
    printf("boundary 2 — truncation leaves a STRING behind\n");

    char small[4];
    memset(small, 0x5A, sizeof small);
    size_t r = safe_copy(small, sizeof small, "abcdefgh");

    CHECK(r == 8, "★ returns 8, the length of src — not 3, the length copied. "
                  "A function returning 3 here cannot be distinguished from "
                  "the exact-fit case above");
    CHECK(r >= sizeof small, "returned >= dstsz, which is the truncation test");
    CHECK(small[3] == '\0', "★ dst is NUL-terminated — this is what strncpy "
                            "does not do");
    CHECK(strcmp(small, "abc") == 0, "and holds the first three characters");
}

static void test_zero_size(void)
{
    printf("boundary 1 — dstsz == 0 writes nothing at all\n");

    struct guarded g;
    guarded_init(&g);
    unsigned char first = (unsigned char)g.buf[0];

    size_t r = safe_copy(g.buf, 0, "anything");

    CHECK(r == 8, "still returns the length of src");
    CHECK((unsigned char)g.buf[0] == first,
          "★ not one byte was written — there is nowhere to put even a NUL");
    CHECK(guards_intact(&g), "guards intact");

    /* The call a caller makes to find out how much to allocate, before it has
     * anything to write into. It must not dereference dst. */
    size_t need = safe_copy(NULL, 0, "measure me");
    CHECK(need == 10, "a NULL destination with size 0 is a length query");
}

static void test_no_write_past_the_end(void)
{
    printf("boundary 5 — the end of the buffer is the end of the buffer\n");

    /* Exactly eight bytes on the heap, so AddressSanitizer owns the ninth. */
    char *tight = malloc(8);
    if (tight == NULL) {
        printf("  SKIP  out of memory\n");
        return;
    }
    memset(tight, 0x5A, 8);
    size_t r = safe_copy(tight, 8, "0123456789abcdef");

    CHECK(r == 16, "returns the full length of src");
    CHECK(tight[7] == '\0', "the last byte of the buffer is the NUL");
    CHECK(memcmp(tight, "0123456", 7) == 0, "and the seven before it are src's");
    free(tight);
}

static void test_no_read_past_the_source(void)
{
    printf("boundary 6 — and the end of the source is the end of the source\n");

    /* "hello" and its NUL, exactly, at the end of a heap block. A version that
     * copies dstsz bytes out of src rather than strlen(src) + 1 reads past the
     * allocation, and ASan stops the program here. That is the intended
     * outcome of a wrong implementation: not a wrong answer, a dead process. */
    char *exact = malloc(6);
    if (exact == NULL) {
        printf("  SKIP  out of memory\n");
        return;
    }
    memcpy(exact, "hello", 6);

    char roomy[64];
    memset(roomy, 0x5A, sizeof roomy);
    size_t r = safe_copy(roomy, sizeof roomy, exact);

    CHECK(r == 5, "returns 5");
    CHECK(strcmp(roomy, "hello") == 0, "and copied exactly the five characters");
    free(exact);
}

/* ── the protocol-field half ──────────────────────────────────────────────── */

static void test_n_ordinary(void)
{
    printf("safe_copy_n — a length-prefixed field that fits\n");

    struct guarded g;
    guarded_init(&g);
    size_t r = safe_copy_n(g.buf, sizeof g.buf, "CN=device", 9);

    CHECK(r == 9, "returns srclen");
    CHECK(strcmp(g.buf, "CN=device") == 0, "dst holds the field and a NUL");
    CHECK(guards_intact(&g), "guards intact");
}

static void test_n_is_not_nul_terminated(void)
{
    printf("boundary 6 — ★ the field has no NUL, and reading for one is the bug\n");

    /* Five bytes on the heap and not one more. There is no terminator to find:
     * this is what a length-prefixed field looks like in memory, and it is the
     * shape GHSA-j54w-759w-xj3m's RequesterInfo has. An implementation that
     * calls strlen on it, or that copies until it sees a NUL, reads memory
     * that does not belong to it and ASan ends the program. */
    char *field = malloc(5);
    if (field == NULL) {
        printf("  SKIP  out of memory\n");
        return;
    }
    memcpy(field, "abcde", 5);

    char out[16];
    memset(out, 0x5A, sizeof out);
    size_t r = safe_copy_n(out, sizeof out, field, 5);

    CHECK(r == 5, "returns 5");
    CHECK(strcmp(out, "abcde") == 0, "five characters and a NUL this function added");
    free(field);
}

static void test_n_truncates(void)
{
    printf("safe_copy_n — a field longer than the buffer\n");

    char small[4];
    memset(small, 0x5A, sizeof small);
    /* 300 bytes is inside what DSP0274 allows a RequesterInfo to be and well
     * outside a four-byte buffer. The two numbers are unrelated, which is the
     * entire advisory. */
    char *big = malloc(300);
    if (big == NULL) {
        printf("  SKIP  out of memory\n");
        return;
    }
    memset(big, 'A', 300);

    size_t r = safe_copy_n(small, sizeof small, big, 300);

    CHECK(r == 300, "★ returns 300, the length the FIELD claimed");
    CHECK(r >= sizeof small, "which the caller reads as truncation");
    CHECK(small[3] == '\0', "dst is still a string");
    CHECK(memcmp(small, "AAA", 3) == 0, "holding the first three bytes");
    free(big);
}

static void test_n_zero_cases(void)
{
    printf("safe_copy_n — the two zeros\n");

    struct guarded g;
    guarded_init(&g);
    unsigned char first = (unsigned char)g.buf[0];

    size_t r = safe_copy_n(g.buf, 0, "anything", 8);
    CHECK(r == 8, "dstsz == 0 still returns srclen");
    CHECK((unsigned char)g.buf[0] == first, "and writes nothing");

    guarded_init(&g);
    /* An empty field. src may legitimately be NULL when srclen is 0, because
     * a zero-length field has no bytes and a caller has no pointer to give. */
    r = safe_copy_n(g.buf, sizeof g.buf, NULL, 0);
    CHECK(r == 0, "srclen == 0 returns 0");
    CHECK(g.buf[0] == '\0', "and leaves an empty string behind");
    CHECK(guards_intact(&g), "guards intact");
}

int main(void)
{
    /* Line-buffer stdout. Without this, a drill that dies inside a sanitizer
     * prints NOTHING when its output is redirected to a file, and the reader
     * gets a stack trace with no idea which check was reached. The trace says
     * where the bug is; this says how far you got. */
    setvbuf(stdout, NULL, _IOLBF, 0);

    printf("d8 — copying into a buffer that may be too small\n\n");

    test_ordinary();                  printf("\n");
    test_empty_source();              printf("\n");
    test_exact_fit();                 printf("\n");
    test_truncation();                printf("\n");
    test_zero_size();                 printf("\n");
    test_no_write_past_the_end();     printf("\n");
    test_no_read_past_the_source();   printf("\n");
    test_n_ordinary();                printf("\n");
    test_n_is_not_nul_terminated();   printf("\n");
    test_n_truncates();               printf("\n");
    test_n_zero_cases();

    printf("\n%d/%d checks passed\n", g_checks - g_failures, g_checks);
    if (g_failures != 0) {
        printf("\n%d check(s) failed. If every one failed, the implementation\n"
               "is still stubbed out — that is the exercise, go write it.\n",
               g_failures);
        return 1;
    }
    printf("d8 PASS\n");
    return 0;
}

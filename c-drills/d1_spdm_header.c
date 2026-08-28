/*
 * d1_spdm_header.c — parse an SPDM message header, and one field behind it.
 *
 * ┌───────────────────────────────────────────────────────────────────────┐
 * │  THE IMPLEMENTATION IS YOURS TO WRITE. Everything below the marker    │
 * │  "YOUR IMPLEMENTATION STARTS HERE" is stubbed out on purpose.         │
 * │                                                                       │
 * │  The ritual, in order, and the order is the point:                    │
 * │    1. On paper, nothing open, 20 minutes.                             │
 * │    2. Dry-run two cases by hand on that paper. One must be a boundary.│
 * │    3. Type it in. Record how many compile errors you got. That number │
 * │       is the only quantifiable measure of progress here — write it    │
 * │       into SCORECARD.md.                                              │
 * │    4. `make test` clean, sanitizers included.                         │
 * └───────────────────────────────────────────────────────────────────────┘
 *
 * Where this connects to the project
 * ----------------------------------
 * Every analysis script here starts by doing exactly this. `harness/fields.py`
 * reads byte 1 of a message to decide which message it is; the layout
 * reconstruction in the same file reads a 32-bit little-endian length out of
 * the middle of a buffer and has to refuse the read when the buffer is too
 * short. Both are below, in C, with nothing to ask.
 *
 * The bytes in the tests are not invented. They are packet 3 of
 * bench/data/w2-baseline-20260816T172221Z/walkthrough.pcap, the 20-byte
 * GET_CAPABILITIES that docs/handshake-walkthrough.md §2 takes apart.
 *
 * Two functions, not one, and why
 * -------------------------------
 * The lesson usually attached to a header parser is "do not cast the buffer to
 * a struct pointer — it works on x86 and faults on ARM." With the struct
 * below that lesson is FALSE, and it is worth knowing why before you repeat
 * it in an interview: every member is one byte, so _Alignof(spdm_hdr_t) is 1,
 * and a cast to it can never be misaligned. (There is still a strict-aliasing
 * argument against it, and padding would bite the moment someone adds a
 * uint16_t. Neither will fault today.)
 *
 * What does fault is reading a MULTI-BYTE field out of a buffer at an offset
 * you do not control. That is spdm_read_u32_le, and the test below hands it a
 * deliberately odd address. Write it as
 *
 *     *out = *(const uint32_t *)(buf + off);          // <- do not
 *
 * and UndefinedBehaviorSanitizer stops the program on a misaligned load. Write
 * it byte by byte and it is correct everywhere. That is the real version of
 * the lesson, and `d6` goes further into it.
 *
 * Four boundaries this must survive
 * ---------------------------------
 *   (1) a buffer shorter than the header      -> report failure, do not read
 *   (2) NULL for either pointer               -> report failure, do not crash
 *   (3) a read that ends exactly at the end    -> must SUCCEED (fencepost)
 *       and one that ends one byte past it     -> must fail
 *   (4) ★ off + 4 overflowing size_t          -> must fail. `off + 4 > len`
 *       wraps to a small number and reports success, and then the read runs
 *       off the end of the buffer. This is a real advisory class, and `d2`
 *       is the whole drill about it.
 *
 * On failure, neither function may modify *out. A caller that checks the
 * return value and a caller that checks whether the output changed must reach
 * the same conclusion.
 *
 * Build and run:
 *     make d1_spdm_header && ./d1_spdm_header
 */

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ── types ──────────────────────────────────────────────────────────────── */

typedef struct {
    uint8_t version;    /* 0x14 = SPDM 1.4, and 0x10 during version negotiation */
    uint8_t code;       /* RequestResponseCode — 0xE1 GET_CAPABILITIES, ...     */
    uint8_t param1;
    uint8_t param2;
} spdm_hdr_t;

#define SPDM_HDR_BYTES 4

/* ── contract ───────────────────────────────────────────────────────────────
 *
 * spdm_parse_header(buf, len, out)
 *     Fills *out from the first four bytes of buf.
 *     Returns 0 on success, -1 if buf is NULL, out is NULL, or len < 4.
 *     Reads no byte of buf beyond index 3. Assumes nothing about buf's
 *     alignment. On failure, *out is not modified.
 *
 * spdm_read_u32_le(buf, len, off, out)
 *     Reads four LITTLE-ENDIAN bytes at buf[off .. off+3] into *out.
 *     Returns 0 on success, -1 if buf is NULL, out is NULL, or those four
 *     bytes are not entirely inside the first len bytes of buf — including
 *     the case where off + 4 does not fit in a size_t.
 *     Assumes nothing about the alignment of buf or of buf + off.
 *     On failure, *out is not modified.
 */

int spdm_parse_header(const uint8_t *buf, size_t len, spdm_hdr_t *out);
int spdm_read_u32_le(const uint8_t *buf, size_t len, size_t off, uint32_t *out);

/* ══════════════════ YOUR IMPLEMENTATION STARTS HERE ═══════════════════════ */

int spdm_parse_header(const uint8_t *buf, size_t len, spdm_hdr_t *out)
{
    (void)buf;
    (void)len;
    (void)out;
    /* TODO */
    return -1;
}

int spdm_read_u32_le(const uint8_t *buf, size_t len, size_t off, uint32_t *out)
{
    (void)buf;
    (void)len;
    (void)off;
    (void)out;
    /* TODO */
    return -1;
}

/* ══════════════════ YOUR IMPLEMENTATION ENDS HERE ═════════════════════════ */

/* ── tests ──────────────────────────────────────────────────────────────────
 *
 * These use a CHECK macro rather than assert() so that one failure does not
 * hide the next five. Every check that fails prints its own line; the exit
 * status is what `make test` and CI read.
 */

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

/* Packet 3 of walkthrough.pcap: GET_CAPABILITIES, 20 bytes, as it was on the
 * wire. Flags 0x8882F7C6, DataTransferSize 4,608, MaxSPDMmsgSize 163,840 —
 * every one of them little-endian, every one of them in §2 of the walkthrough. */
static const uint8_t GET_CAPABILITIES[20] = {
    0x14, 0xE1, 0x00, 0x00,     /*  0  version, code, param1, param2       */
    0x00, 0x00, 0x00, 0x00,     /*  4  Reserved, CTExponent, ExtFlags      */
    0xC6, 0xF7, 0x82, 0x88,     /*  8  Flags            = 0x8882F7C6       */
    0x00, 0x12, 0x00, 0x00,     /* 12  DataTransferSize = 0x00001200       */
    0x00, 0x80, 0x02, 0x00,     /* 16  MaxSPDMmsgSize   = 0x00028000       */
};

#define SENTINEL_HDR ((spdm_hdr_t){ 0xAA, 0xBB, 0xCC, 0xDD })
#define SENTINEL_U32 0xDEADBEEFu

static int same_hdr(spdm_hdr_t a, spdm_hdr_t b)
{
    return a.version == b.version && a.code == b.code
        && a.param1 == b.param1 && a.param2 == b.param2;
}

static void test_header_happy_path(void)
{
    printf("header — the four bytes, and only the four bytes\n");
    spdm_hdr_t h = SENTINEL_HDR;

    CHECK(spdm_parse_header(GET_CAPABILITIES, sizeof GET_CAPABILITIES, &h) == 0,
          "a 20-byte message parses");
    CHECK(h.version == 0x14, "version is 0x14 (SPDM 1.4)");
    CHECK(h.code    == 0xE1, "code is 0xE1 (GET_CAPABILITIES)");
    CHECK(h.param1  == 0x00, "param1 is 0x00");
    CHECK(h.param2  == 0x00, "param2 is 0x00");

    h = SENTINEL_HDR;
    CHECK(spdm_parse_header(GET_CAPABILITIES, SPDM_HDR_BYTES, &h) == 0,
          "exactly four bytes is enough");
    CHECK(h.code == 0xE1, "and gives the same code");
}

static void test_header_boundaries(void)
{
    printf("boundary 1 and 2 — short buffers and null pointers\n");
    spdm_hdr_t h;

    for (size_t len = 0; len < SPDM_HDR_BYTES; len++) {
        h = SENTINEL_HDR;
        char label[64];
        snprintf(label, sizeof label, "len == %zu is rejected", len);
        CHECK(spdm_parse_header(GET_CAPABILITIES, len, &h) == -1, label);
        CHECK(same_hdr(h, SENTINEL_HDR), "  and *out is left untouched");
    }

    h = SENTINEL_HDR;
    CHECK(spdm_parse_header(NULL, 4, &h) == -1, "a NULL buffer is rejected");
    CHECK(same_hdr(h, SENTINEL_HDR),            "  and *out is left untouched");
    CHECK(spdm_parse_header(GET_CAPABILITIES, 4, NULL) == -1,
          "a NULL out pointer is rejected");
}

static void test_header_reads_nothing_extra(void)
{
    /* Four bytes, allocated exactly. Reading buf[4] is now a heap overflow and
     * AddressSanitizer stops the program with a stack trace instead of
     * returning a plausible-looking answer. A buffer on the stack would not
     * catch this: the bytes after it are simply other variables. */
    printf("boundary 1 again — a heap buffer with nothing after it (ASan decides)\n");
    uint8_t *exact = malloc(SPDM_HDR_BYTES);
    if (exact == NULL) {
        printf("  FAIL  allocation failed\n");
        g_failures++;
        return;
    }
    memcpy(exact, GET_CAPABILITIES, SPDM_HDR_BYTES);

    spdm_hdr_t h = SENTINEL_HDR;
    CHECK(spdm_parse_header(exact, SPDM_HDR_BYTES, &h) == 0,
          "parses a buffer with no slack after it");
    CHECK(h.param2 == 0x00, "and reads param2 correctly");
    free(exact);
    printf("  ..    if it read a fifth byte, the sanitizer already stopped us\n");
}

static void test_header_unaligned(void)
{
    /* This one cannot fault — spdm_hdr_t is four bytes with alignment 1, so
     * casting to it is legal at any address. It is here because the NEXT test
     * is the one that punishes the same habit, and seeing them together is
     * the point. */
    printf("alignment — an odd address, which this struct tolerates\n");
    uint8_t arena[32];
    memcpy(arena + 1, GET_CAPABILITIES, sizeof GET_CAPABILITIES);

    spdm_hdr_t h = SENTINEL_HDR;
    CHECK(spdm_parse_header(arena + 1, sizeof GET_CAPABILITIES, &h) == 0,
          "parses from an odd address");
    CHECK(h.version == 0x14 && h.code == 0xE1, "with the same result");
}

static void test_u32_happy_path(void)
{
    printf("u32 — three real fields, all little-endian\n");
    uint32_t v = SENTINEL_U32;

    CHECK(spdm_read_u32_le(GET_CAPABILITIES, sizeof GET_CAPABILITIES, 8, &v) == 0,
          "Flags at offset 8 reads");
    CHECK(v == 0x8882F7C6u, "  and is 0x8882F7C6, not byte-swapped");

    CHECK(spdm_read_u32_le(GET_CAPABILITIES, sizeof GET_CAPABILITIES, 12, &v) == 0,
          "DataTransferSize at offset 12 reads");
    CHECK(v == 4608u, "  and is 4,608");

    CHECK(spdm_read_u32_le(GET_CAPABILITIES, sizeof GET_CAPABILITIES, 16, &v) == 0,
          "MaxSPDMmsgSize at offset 16 reads");
    CHECK(v == 163840u, "  and is 163,840");
}

static void test_u32_unaligned(void)
{
    /* ★ The one that decides whether you cast or shift. arena + 1 is an odd
     * address, so arena + 1 + 12 is odd too, and
     *
     *     *out = *(const uint32_t *)(buf + off);
     *
     * is a misaligned load. -fsanitize=undefined includes -fsanitize=alignment
     * and halts on it. Shifting the four bytes together works everywhere. */
    printf("★ alignment — a 32-bit field at an odd address (UBSan decides)\n");
    uint8_t arena[32];
    memcpy(arena + 1, GET_CAPABILITIES, sizeof GET_CAPABILITIES);

    uint32_t v = SENTINEL_U32;
    CHECK(spdm_read_u32_le(arena + 1, sizeof GET_CAPABILITIES, 12, &v) == 0,
          "reads from an odd base address");
    CHECK(v == 4608u, "  and gets 4,608, the same as from an aligned one");
}

static void test_u32_fenceposts(void)
{
    printf("boundary 3 — a read that ends exactly at the end, and one past it\n");
    uint32_t v;

    v = SENTINEL_U32;
    CHECK(spdm_read_u32_le(GET_CAPABILITIES, 20, 16, &v) == 0,
          "off + 4 == len succeeds");
    CHECK(v == 163840u, "  with the right value");

    v = SENTINEL_U32;
    CHECK(spdm_read_u32_le(GET_CAPABILITIES, 19, 16, &v) == -1,
          "off + 4 == len + 1 is rejected");
    CHECK(v == SENTINEL_U32, "  and *out is left untouched");

    v = SENTINEL_U32;
    CHECK(spdm_read_u32_le(GET_CAPABILITIES, 20, 20, &v) == -1,
          "off == len is rejected");
    CHECK(v == SENTINEL_U32, "  and *out is left untouched");

    v = SENTINEL_U32;
    CHECK(spdm_read_u32_le(GET_CAPABILITIES, 20, 21, &v) == -1,
          "off > len is rejected");

    CHECK(spdm_read_u32_le(NULL, 20, 0, &v) == -1, "a NULL buffer is rejected");
    CHECK(spdm_read_u32_le(GET_CAPABILITIES, 20, 0, NULL) == -1,
          "a NULL out pointer is rejected");
}

static void test_u32_offset_overflow(void)
{
    /* ★ boundary 4. Writing the bound as `off + 4 > len` looks right and is
     * wrong: at off == SIZE_MAX - 2 the sum wraps to 1, 1 > 20 is false, and
     * the function reports success and then reads from somewhere far away.
     * Write the bound so nothing can wrap and this test costs you nothing. */
    printf("★ boundary 4 — an offset that makes off + 4 wrap around\n");
    uint32_t v;

    const size_t nasty[] = { SIZE_MAX, SIZE_MAX - 1, SIZE_MAX - 2, SIZE_MAX - 3 };
    for (size_t i = 0; i < sizeof nasty / sizeof nasty[0]; i++) {
        v = SENTINEL_U32;
        char label[80];
        snprintf(label, sizeof label, "off == SIZE_MAX - %zu is rejected", i);
        CHECK(spdm_read_u32_le(GET_CAPABILITIES, sizeof GET_CAPABILITIES,
                               nasty[i], &v) == -1, label);
        CHECK(v == SENTINEL_U32, "  and *out is left untouched");
    }
}

static void test_u32_reads_nothing_extra(void)
{
    printf("boundary 3 again — exactly four heap bytes (ASan decides)\n");
    uint8_t *exact = malloc(4);
    if (exact == NULL) {
        printf("  FAIL  allocation failed\n");
        g_failures++;
        return;
    }
    memcpy(exact, GET_CAPABILITIES + 12, 4);

    uint32_t v = SENTINEL_U32;
    CHECK(spdm_read_u32_le(exact, 4, 0, &v) == 0, "reads four bytes with no slack");
    CHECK(v == 4608u, "  and gets 4,608");
    free(exact);
}

int main(void)
{
    printf("d1 — SPDM message header, and a little-endian field behind it\n\n");

    test_header_happy_path();          printf("\n");
    test_header_boundaries();          printf("\n");
    test_header_reads_nothing_extra(); printf("\n");
    test_header_unaligned();           printf("\n");
    test_u32_happy_path();             printf("\n");
    test_u32_unaligned();              printf("\n");
    test_u32_fenceposts();             printf("\n");
    test_u32_offset_overflow();        printf("\n");
    test_u32_reads_nothing_extra();

    printf("\n%d/%d checks passed\n", g_checks - g_failures, g_checks);
    if (g_failures != 0) {
        printf("\n%d check(s) failed. If every one failed, the implementation\n"
               "is still stubbed out — that is the exercise, go write it.\n",
               g_failures);
        return 1;
    }
    printf("d1 PASS\n");
    return 0;
}

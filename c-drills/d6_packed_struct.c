/*
 * d6_packed_struct.c — a wire format is a byte layout, not a struct layout.
 *
 * ┌───────────────────────────────────────────────────────────────────────┐
 * │  THE IMPLEMENTATION IS YOURS TO WRITE. Everything below the marker    │
 * │  "YOUR IMPLEMENTATION STARTS HERE" is stubbed out on purpose.         │
 * │                                                                       │
 * │  The ritual, in order, and the order is the point:                    │
 * │    1. On paper, nothing open, 15 minutes.                             │
 * │    2. Dry-run two cases by hand. One must be a record whose last      │
 * │       block declares one byte more than the record has left.          │
 * │    3. Type it in. Record how many compile errors you got. That number │
 * │       is the only quantifiable measure of progress here — write it    │
 * │       into SCORECARD.md.                                              │
 * │    4. `make test` clean, sanitizers included.                         │
 * └───────────────────────────────────────────────────────────────────────┘
 *
 * Three questions you must be able to answer out loud when this is done:
 *
 *   1. What is sizeof(meas_dmtf_t), what is it on the wire, and why do they
 *      differ when sizeof(meas_common_t) does not?
 *   2. Why does casting a captured buffer to a struct pointer fault on some
 *      architectures — and why does it NOT fault for the struct in d1?
 *   3. Why can access through a packed struct be slower than through an
 *      unpacked one, on a machine where both work?
 *
 * Where this connects to the project
 * ----------------------------------
 * docs/handshake-walkthrough.md §7 reports a 528-byte measurement record made
 * of eight blocks. Each block is
 *
 *     index(1) spec(1) MeasurementSize(2) | ValueType(1) ValueSize(2) | value[]
 *     \___ common header, 4 bytes ______/  \_ DMTF header, 3 bytes __/
 *
 * and the two headers behave completely differently when you declare them in C.
 *
 *   meas_common_t  { uint8_t; uint8_t; uint16_t }
 *       The uint16_t already lands on offset 2, which divides its own size. The
 *       compiler has nothing to fix. sizeof is 4 packed or not, and every
 *       offset is the same. #pragma pack here buys nothing.
 *
 *   meas_dmtf_t    { uint8_t; uint16_t }
 *       The uint16_t wants offset 2 and the wire puts it at 1. So the compiler
 *       inserts one byte, sizeof becomes 4 against the wire's 3, and
 *       ValueSize moves. BOTH the size and an offset are now wrong.
 *
 * libspdm knows this: include/industry_standard/spdm.h opens with
 * `#pragma pack(1)` on line 14 and closes it 1,813 lines later. The whole
 * 70 KB header is packed, because a wire format is a byte layout.
 *
 * ★ Why the drill uses this struct and not the transport framing
 * --------------------------------------------------------------
 * The obvious candidate was the five-byte MCTP framing — a four-byte header
 * and a message-type byte — because harness/verify_repo.sh asserts
 *
 *     pcap captured bytes == SPDM message bytes + 5 x messages
 *
 * and getting that 5 from sizeof would be the classic mistake. It is not a
 * mistake: mctp_header_t is four uint8_t members, so its alignment is 1, and
 * sizeof gives exactly 5. There is nothing to get wrong.
 *
 * This drill was written that way first and the trap could not fire. That is
 * the same defect d1 had — a lesson whose failure mode cannot occur teaches a
 * superstition, and a superstition gets repeated with confidence. So the drill
 * moved to the struct where the padding is real and the wire disagrees.
 *
 * ★ The equation that catches it
 * ------------------------------
 * Every block satisfies
 *
 *     MeasurementSize == (size of the DMTF header on the wire) + ValueSize
 *
 * The two blocks below say 11 == 3 + 8 and 19 == 3 + 16. Use sizeof on the
 * unpacked struct and you are testing 11 == 4 + 8, which is false, and the walk
 * stops on the first block instead of quietly reading one byte too far eight
 * times. That is the good outcome, and it is only good because the record
 * carries a length that can disagree with you.
 *
 * The bytes are real: blocks 4 and 7 of the measurement record in
 * bench/data/w3-baseline-20260831T143123Z/walkthrough.pcap, packet 30. Block 4
 * is worth a second look — its eight-byte value is 07 00 00 00 00 00 00 00,
 * the security version number that the sample responder hard-codes and that
 * W04 has to make configurable before any RATS policy can be tested against
 * more than one input.
 *
 * Boundaries this must survive
 * ----------------------------
 *   (1) a record of exactly two whole blocks   -> 2 blocks, all bytes consumed
 *   (2) a record one byte short of its last    -> failure, nothing written
 *   (3) a block declaring a size that runs past the record -> failure
 *   (4) a block whose MeasurementSize disagrees with its ValueSize -> failure
 *   (5) len 0, and NULL for any output pointer -> failure, no crash
 *   (6) an odd address -> must work; records are not aligned
 *   (7) on failure, no output parameter may be modified
 *
 * Build and run:
 *     make d6_packed_struct && ./d6_packed_struct
 */

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

/* ── the four structs, given, because declaring them is not the exercise ──── */

/* The common header. Naturally aligned already — packing it changes nothing,
 * and proving that to yourself is half the drill. */
typedef struct {
    uint8_t  index;
    uint8_t  spec;
    uint16_t size;              /* MeasurementSize */
} meas_common_t;

#pragma pack(push, 1)
typedef struct {
    uint8_t  index;
    uint8_t  spec;
    uint16_t size;
} meas_common_packed_t;
#pragma pack(pop)

/* The DMTF header. Three bytes on the wire, and the one the compiler will
 * quietly make four. */
typedef struct {
    uint8_t  value_type;
    uint16_t value_size;        /* DMTFSpecMeasurementValueSize */
} meas_dmtf_t;

#pragma pack(push, 1)
typedef struct {
    uint8_t  value_type;
    uint16_t value_size;
} meas_dmtf_packed_t;
#pragma pack(pop)

#define MEAS_COMMON_WIRE_BYTES 4

/* ── contract ───────────────────────────────────────────────────────────────
 *
 * meas_header_sizes(out)
 *     Fills out[0..3] with, in order:
 *         sizeof(meas_dmtf_t)
 *         sizeof(meas_dmtf_packed_t)
 *         offsetof(meas_dmtf_t, value_size)
 *         offsetof(meas_dmtf_packed_t, value_size)
 *     Ask the compiler. Do not count on paper and type the answer in — the
 *     compiler is the authority on its own layout and asking it is one macro.
 *     Returns 0, or -1 if out is NULL.
 *
 * meas_dmtf_wire_bytes()
 *     The number of bytes the DMTF header occupies ON THE WIRE. The test
 *     insists this is not sizeof(meas_dmtf_t).
 *
 * meas_walk(rec, len, blocks_out, consumed_out)
 *     Walks a measurement record. For each block:
 *         MeasurementSize is a 16-bit little-endian value at block offset 2;
 *         ValueSize is a 16-bit little-endian value at block offset 5;
 *         the block occupies 4 + MeasurementSize bytes;
 *         and MeasurementSize must equal meas_dmtf_wire_bytes() + ValueSize.
 *     Reads the fields byte by byte. Does not cast rec to any struct pointer
 *     and does not use offsetof on the UNPACKED structs to find them.
 *
 *     On success *blocks_out is the number of blocks and *consumed_out is the
 *     number of bytes they occupied, which must equal len exactly. Returns 0.
 *
 *     Returns -1 if rec is NULL, either output pointer is NULL, len is 0, a
 *     block's header does not fit, a block runs past the end, a block's two
 *     sizes disagree, or the blocks do not consume the record exactly.
 *     On failure neither output is modified.
 */

int meas_header_sizes(size_t out[4]);
size_t meas_dmtf_wire_bytes(void);
int meas_walk(const uint8_t *rec, size_t len, size_t *blocks_out,
              size_t *consumed_out);

/* ══════════════════ YOUR IMPLEMENTATION STARTS HERE ═══════════════════════ */

int meas_header_sizes(size_t out[4])
{
    (void)out;
    /* TODO */
    return -1;
}

size_t meas_dmtf_wire_bytes(void)
{
    /* TODO */
    return 0;
}

int meas_walk(const uint8_t *rec, size_t len, size_t *blocks_out,
              size_t *consumed_out)
{
    (void)rec;
    (void)len;
    (void)blocks_out;
    (void)consumed_out;
    /* TODO */
    return -1;
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

/* Blocks 4 and 7 of the 528-byte measurement record in packet 30 of
 * bench/data/w3-baseline-20260831T143123Z/walkthrough.pcap. Two blocks of
 * different sizes, 38 bytes together, exactly as they were on the wire.
 *
 * Block 4: index 0x10, MeasurementSize 11, ValueType 0x87, ValueSize 8,
 *          value 07 00 00 00 00 00 00 00  <- the hard-coded SVN, see W04.
 * Block 7: index 0xFE, MeasurementSize 19, ValueType 0x85, ValueSize 16. */
static const uint8_t RECORD[38] = {
    0x10, 0x01, 0x0B, 0x00, 0x87, 0x08, 0x00, 0x07,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,

    0xFE, 0x01, 0x13, 0x00, 0x85, 0x10, 0x00, 0x3F,
    0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x1F,
    0x00, 0x00, 0x00, 0x11, 0x00, 0x00, 0x00,
};

static void test_the_two_headers_differ(void)
{
    printf("question 1 — one header the compiler pads, one it does not\n");

    size_t s[4] = { 99, 99, 99, 99 };
    CHECK(meas_header_sizes(s) == 0, "meas_header_sizes fills the array");
    CHECK(s[0] == 4, "sizeof(meas_dmtf_t) is 4");
    CHECK(s[1] == 3, "sizeof(meas_dmtf_packed_t) is 3");
    CHECK(s[2] == 2, "unpacked, value_size is at offset 2");
    CHECK(s[3] == 1, "packed, value_size is at offset 1 — where the wire puts it");
    CHECK(meas_header_sizes(NULL) == -1, "NULL is rejected");

    CHECK(meas_dmtf_wire_bytes() == 3, "the DMTF header is 3 bytes on the wire");
    CHECK(meas_dmtf_wire_bytes() != sizeof(meas_dmtf_t),
          "and that is not sizeof(meas_dmtf_t)");

    printf("       one byte of padding, and it moved a field as well as a size.\n");
}

static void test_the_other_header_does_not_care(void)
{
    printf("★ and the common header is identical either way\n");

    CHECK(sizeof(meas_common_t) == sizeof(meas_common_packed_t),
          "packed and unpacked are the same size");
    CHECK(sizeof(meas_common_t) == MEAS_COMMON_WIRE_BYTES,
          "and both are the 4 bytes the wire uses");
    CHECK(offsetof(meas_common_t, size) == offsetof(meas_common_packed_t, size),
          "MeasurementSize is at the same offset either way");

    printf("       its uint16_t already sat on a boundary that divides its own\n"
           "       size, so there was nothing to pack. Reaching for #pragma pack\n"
           "       on every wire struct is cargo cult; knowing which ones need\n"
           "       it is the skill, and question 3 is what it costs when they\n"
           "       do not.\n");
}

static void test_walk_the_real_record(void)
{
    printf("walking 38 bytes of a real measurement record\n");

    size_t blocks = 99, consumed = 99;
    CHECK(meas_walk(RECORD, sizeof RECORD, &blocks, &consumed) == 0,
          "the record walks");
    CHECK(blocks == 2, "two blocks");
    CHECK(consumed == sizeof RECORD, "consuming all 38 bytes, with none left over");

    printf("       block 4: MeasurementSize 11 == 3 + ValueSize 8\n");
    printf("       block 7: MeasurementSize 19 == 3 + ValueSize 16\n");
    printf("       with sizeof(meas_dmtf_t) instead of 3 the first test reads\n"
           "       11 == 4 + 8, which is false, and the walk stops here rather\n"
           "       than reading one byte too far eight times.\n");
}

static void test_walk_rejects_a_short_record(void)
{
    printf("boundary 2 and 3 — a record that runs out\n");

    size_t blocks = 99, consumed = 99;
    CHECK(meas_walk(RECORD, sizeof RECORD - 1, &blocks, &consumed) == -1,
          "one byte short is rejected");
    CHECK(blocks == 99 && consumed == 99, "  and nothing was written");

    /* The first block alone, with one byte of its value missing. */
    CHECK(meas_walk(RECORD, 14, &blocks, &consumed) == -1,
          "a block that runs past the end is rejected");
    CHECK(blocks == 99 && consumed == 99, "  and nothing was written");

    /* Exactly the first block. */
    blocks = consumed = 99;
    CHECK(meas_walk(RECORD, 15, &blocks, &consumed) == 0,
          "exactly one whole block succeeds");
    CHECK(blocks == 1 && consumed == 15, "  one block, 15 bytes");

    /* Not even a header. */
    for (size_t len = 0; len < 7; len++) {
        blocks = consumed = 99;
        char label[64];
        snprintf(label, sizeof label, "len == %zu is rejected", len);
        CHECK(meas_walk(RECORD, len, &blocks, &consumed) == -1, label);
    }
}

static void test_walk_rejects_disagreeing_sizes(void)
{
    printf("boundary 4 — the two sizes in one block disagree\n");

    uint8_t bad[15];
    size_t blocks = 99, consumed = 99;

    /* MeasurementSize 11, ValueSize 9. 11 != 3 + 9, and no amount of
     * bounds-checking would notice: the block still fits. */
    memcpy(bad, RECORD, sizeof bad);
    bad[5] = 0x09;
    CHECK(meas_walk(bad, sizeof bad, &blocks, &consumed) == -1,
          "MeasurementSize 11 against ValueSize 9 is rejected");
    CHECK(blocks == 99 && consumed == 99, "  and nothing was written");

    /* The same disagreement the other way: ValueSize 7. */
    memcpy(bad, RECORD, sizeof bad);
    bad[5] = 0x07;
    CHECK(meas_walk(bad, sizeof bad, &blocks, &consumed) == -1,
          "MeasurementSize 11 against ValueSize 7 is rejected");
}

static void test_walk_null_and_alignment(void)
{
    printf("boundary 5 and 6 — null pointers, and an odd address\n");

    size_t blocks = 99, consumed = 99;
    CHECK(meas_walk(NULL, 38, &blocks, &consumed) == -1, "NULL record");
    CHECK(meas_walk(RECORD, 38, NULL, &consumed) == -1, "NULL blocks_out");
    CHECK(meas_walk(RECORD, 38, &blocks, NULL) == -1, "NULL consumed_out");
    CHECK(blocks == 99 && consumed == 99, "  and nothing was written");

    /* question 2, made concrete. A measurement record starts eight bytes into
     * a MEASUREMENTS message which starts five bytes into a capture record, so
     * its address is whatever it is. Read MeasurementSize through a uint16_t
     * pointer here and -fsanitize=alignment stops the program. */
    static uint8_t backing[64];
    uint8_t *odd = backing + 1;
    memcpy(odd, RECORD, sizeof RECORD);

    blocks = consumed = 99;
    CHECK(meas_walk(odd, sizeof RECORD, &blocks, &consumed) == 0,
          "an odd address walks");
    CHECK(blocks == 2 && consumed == 38, "  and finds the same two blocks");
}

int main(void)
{
    printf("d6 — a wire format is a byte layout, not a struct layout\n\n");

    test_the_two_headers_differ();        printf("\n");
    test_the_other_header_does_not_care();printf("\n");
    test_walk_the_real_record();          printf("\n");
    test_walk_rejects_a_short_record();   printf("\n");
    test_walk_rejects_disagreeing_sizes();printf("\n");
    test_walk_null_and_alignment();

    printf("\n%d/%d checks passed\n", g_checks - g_failures, g_checks);
    if (g_failures != 0) {
        printf("\n%d check(s) failed. If every one failed, the implementation\n"
               "is still stubbed out — that is the exercise, go write it.\n",
               g_failures);
        return 1;
    }
    printf("d6 PASS\n");
    return 0;
}

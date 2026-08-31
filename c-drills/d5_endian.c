/*
 * d5_endian.c — big-endian and little-endian in the same connection.
 *
 * ┌───────────────────────────────────────────────────────────────────────┐
 * │  THE IMPLEMENTATION IS YOURS TO WRITE. Everything below the marker    │
 * │  "YOUR IMPLEMENTATION STARTS HERE" is stubbed out on purpose.         │
 * │                                                                       │
 * │  The ritual, in order, and the order is the point:                    │
 * │    1. On paper, nothing open, 15 minutes.                             │
 * │    2. Dry-run two cases by hand on that paper. One must be a value    │
 * │       whose top byte is >= 0x80 — see "the trap" below.               │
 * │    3. Type it in. Record how many compile errors you got. That number │
 * │       is the only quantifiable measure of progress here — write it    │
 * │       into SCORECARD.md.                                              │
 * │    4. `make test` clean, sanitizers included.                         │
 * └───────────────────────────────────────────────────────────────────────┘
 *
 * Where this connects to the project
 * ----------------------------------
 * One connection, two byte orders, and nothing announces the boundary.
 *
 * spdm-emu speaks to itself over a TCP socket whose framing — command,
 * transport type, payload size — is BIG-endian, because that is what
 * spdm_emu/spdm_emu_common/command.h writes. Inside that framing sits an SPDM
 * message, and every multi-byte field in it is LITTLE-endian, because that is
 * what DSP0274 says. The reader that gets one of the two backwards does not
 * crash: it gets a number that is wrong by a factor of about sixteen million,
 * and then reports it.
 *
 * That is not hypothetical here. docs/handshake-walkthrough.md §2 states
 * DataTransferSize = 4,608 from the bytes 00 12 00 00. Read big-endian, the
 * same four bytes say 4,608 x 65,536 = 301,989,888, and a capability field of
 * 288 MB is exactly the kind of wrong answer that looks like a units bug.
 *
 * ★ The trap, and it is a real one
 * --------------------------------
 * The obvious big-endian load is
 *
 *     return p[0] << 24 | p[1] << 16 | p[2] << 8 | p[3];      // <- do not
 *
 * and it is undefined behaviour whenever p[0] >= 0x80.
 *
 * p[0] has type uint8_t, so the integer promotions turn it into a SIGNED int
 * before the shift. If p[0] is 0x88 then 0x88 << 24 is 2,281,701,376, which
 * does not fit in a 32-bit int, and C11 6.5.7p4 says the behaviour is
 * undefined. Not implementation-defined — undefined.
 *
 * Everything about that is invisible in testing. The value you get back is
 * correct on every compiler anyone is likely to use. What UndefinedBehaviour-
 * Sanitizer says, and what an optimiser is entitled to assume, are the two
 * places it shows up, and only one of them is a Tuesday afternoon.
 *
 * The fix is one cast: make the operand unsigned BEFORE shifting.
 *
 * The test below uses 0x8882F7C6 for exactly this reason. It is not an invented
 * number — it is the requester's capability Flags word from packet 3 of
 * bench/data/w3-baseline-20260831T143123Z/walkthrough.pcap, and its top byte is
 * 0x88.
 *
 * ★ Two ways to ask which end the machine is, and only one is defensible
 * ---------------------------------------------------------------------
 * You must write both, because the exercise is to be able to say why one of
 * them is worse:
 *
 *     union  { uint32_t u; uint8_t b[4]; } — writing u and reading b[] is
 *            type punning through a union, which C99 TC3 onwards explicitly
 *            permits (6.5.2.3, footnote 95). It is legal C.
 *
 *     pointer: *(const uint8_t *)&u — reading a uint32_t object through a
 *            pointer to unsigned char. Also legal, and for a specific reason:
 *            6.5p7 lets any object be accessed through a character type. It is
 *            the *reverse* — reading a char array through a uint32_t pointer —
 *            that breaks strict aliasing, and that is what memcpy exists for.
 *
 * So both are legal, and the interesting answer is not "one is UB". Write both,
 * then be ready to say which one you would put in a header and why. The honest
 * answer involves the word "constant-folded".
 *
 * Boundaries this must survive
 * ----------------------------
 *   (1) a top byte >= 0x80          -> no UBSan report, correct value
 *   (2) 0xFFFFFFFF and 0x00000000   -> the ends of the range
 *   (3) store then load             -> must round-trip, both orders
 *   (4) an unaligned pointer        -> these take uint8_t*, so this must work
 *   (5) the two detectors must agree with each other on this machine
 *
 * Build and run:
 *     make d5_endian && ./d5_endian
 */

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

/* ── contract ───────────────────────────────────────────────────────────────
 *
 * be32_load(p)   Reads four bytes at p as a big-endian    unsigned 32-bit value.
 * le32_load(p)   Reads four bytes at p as a little-endian unsigned 32-bit value.
 *     p is never NULL and always has at least four readable bytes — bounds are
 *     d1's and d2's problem, not this one. Assume nothing about alignment.
 *     Must be free of undefined behaviour for every input, including one whose
 *     most significant byte is 0x80 or above.
 *
 * be32_store(p, v)   Writes v into four bytes at p, big-endian.
 * le32_store(p, v)   Writes v into four bytes at p, little-endian.
 *     Writes exactly four bytes and touches nothing else.
 *
 * host_is_le_union()     Returns 1 if this machine is little-endian, else 0,
 *                        decided by writing a uint32_t into a union and
 *                        reading its bytes back.
 * host_is_le_pointer()   The same answer, decided by reading a uint32_t
 *                        through a pointer to unsigned char.
 *
 *     Neither may call the other. Neither may use a library byte-order
 *     function — the point of the drill is to not reach for ntohl and hope.
 */

uint32_t be32_load(const uint8_t *p);
uint32_t le32_load(const uint8_t *p);
void be32_store(uint8_t *p, uint32_t v);
void le32_store(uint8_t *p, uint32_t v);
int host_is_le_union(void);
int host_is_le_pointer(void);

/* ══════════════════ YOUR IMPLEMENTATION STARTS HERE ═══════════════════════ */

uint32_t be32_load(const uint8_t *p)
{
    (void)p;
    /* TODO */
    return 0;
}

uint32_t le32_load(const uint8_t *p)
{
    (void)p;
    /* TODO */
    return 0;
}

void be32_store(uint8_t *p, uint32_t v)
{
    (void)p;
    (void)v;
    /* TODO */
}

void le32_store(uint8_t *p, uint32_t v)
{
    (void)p;
    (void)v;
    /* TODO */
}

int host_is_le_union(void)
{
    /* TODO — write a uint32_t into a union, read its bytes back */
    return -1;
}

int host_is_le_pointer(void)
{
    /* TODO — read a uint32_t through a pointer to unsigned char */
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

/* Packet 3 of walkthrough.pcap, bytes 8..19 — the three little-endian words
 * that docs/handshake-walkthrough.md §2 reports as
 * Flags 0x8882F7C6, DataTransferSize 4,608, MaxSPDMmsgSize 163,840. */
static const uint8_t CAPS_TAIL[12] = {
    0xC6, 0xF7, 0x82, 0x88,     /* Flags            = 0x8882F7C6  */
    0x00, 0x12, 0x00, 0x00,     /* DataTransferSize = 4,608       */
    0x00, 0x80, 0x02, 0x00,     /* MaxSPDMmsgSize   = 163,840     */
};

/* A big-endian socket frame header of the shape command.h writes: a command,
 * a transport type, and a payload size, each four bytes, most significant
 * first. 0x00000001 is SOCKET_SPDM_COMMAND_NORMAL. */
static const uint8_t SOCKET_HDR[12] = {
    0x00, 0x00, 0x00, 0x01,     /* command        = 1     */
    0x00, 0x00, 0x00, 0x01,     /* transport type = MCTP  */
    0x00, 0x00, 0x00, 0x14,     /* payload size   = 20    */
};

static void test_little_endian_payload(void)
{
    printf("the SPDM payload — little-endian, and one word with the top bit set\n");

    CHECK(le32_load(CAPS_TAIL + 4) == 4608u,
          "DataTransferSize reads 4,608");
    CHECK(le32_load(CAPS_TAIL + 8) == 163840u,
          "MaxSPDMmsgSize reads 163,840");

    /* ★ The one that matters. If the shift was written on a signed int, the
     * VALUE below is still right and UBSan stops the program before printing
     * it. A green line here means the load is correct AND clean. */
    CHECK(le32_load(CAPS_TAIL) == 0x8882F7C6u,
          "Flags reads 0x8882F7C6 — top byte 0x88, no signed overflow");
}

static void test_big_endian_framing(void)
{
    printf("the socket framing — big-endian, the other convention on the same wire\n");

    CHECK(be32_load(SOCKET_HDR)     == 1u,  "command reads 1");
    CHECK(be32_load(SOCKET_HDR + 4) == 1u,  "transport type reads 1");
    CHECK(be32_load(SOCKET_HDR + 8) == 20u, "payload size reads 20");

    /* The same four bytes, read the other way. This is the bug the drill is
     * about, written down so it has a number attached to it. */
    CHECK(be32_load(CAPS_TAIL + 4) == 0x00120000u,
          "00 12 00 00 read big-endian is 1,179,648, not 4,608");
}

static void test_top_byte_set_both_orders(void)
{
    printf("boundary 1 — a most significant byte of 0x80 or above\n");

    static const uint8_t hi[4] = { 0x80, 0x00, 0x00, 0x00 };
    static const uint8_t ff[4] = { 0xFF, 0xFF, 0xFF, 0xFF };
    static const uint8_t lo[4] = { 0x00, 0x00, 0x00, 0x00 };

    CHECK(be32_load(hi) == 0x80000000u, "big-endian 80 00 00 00");
    CHECK(le32_load(hi) == 0x00000080u, "little-endian 80 00 00 00");
    CHECK(be32_load(ff) == 0xFFFFFFFFu, "big-endian all ones");
    CHECK(le32_load(ff) == 0xFFFFFFFFu, "little-endian all ones");
    CHECK(be32_load(lo) == 0u,          "big-endian all zeroes");
    CHECK(le32_load(lo) == 0u,          "little-endian all zeroes");
}

static void test_round_trip(void)
{
    printf("boundary 3 — store then load, both orders, with a guard either side\n");

    static const uint32_t values[] = {
        0u, 1u, 0x7FFFFFFFu, 0x80000000u, 0x8882F7C6u, 0xFFFFFFFFu, 4608u,
    };

    for (size_t i = 0; i < sizeof values / sizeof values[0]; i++) {
        uint8_t buf[6] = { 0x5A, 0, 0, 0, 0, 0xA5 };
        char label[80];

        be32_store(buf + 1, values[i]);
        snprintf(label, sizeof label, "big-endian round trip of 0x%08X", values[i]);
        CHECK(be32_load(buf + 1) == values[i], label);
        CHECK(buf[0] == 0x5A && buf[5] == 0xA5, "  and wrote exactly four bytes");

        buf[1] = buf[2] = buf[3] = buf[4] = 0;
        le32_store(buf + 1, values[i]);
        snprintf(label, sizeof label, "little-endian round trip of 0x%08X", values[i]);
        CHECK(le32_load(buf + 1) == values[i], label);
        CHECK(buf[0] == 0x5A && buf[5] == 0xA5, "  and wrote exactly four bytes");
    }
}

static void test_store_puts_bytes_where_expected(void)
{
    printf("the two stores disagree, and that is the whole point\n");

    uint8_t be[4] = { 0 };
    uint8_t le[4] = { 0 };
    be32_store(be, 0x11223344u);
    le32_store(le, 0x11223344u);

    CHECK(be[0] == 0x11 && be[1] == 0x22 && be[2] == 0x33 && be[3] == 0x44,
          "big-endian writes 11 22 33 44");
    CHECK(le[0] == 0x44 && le[1] == 0x33 && le[2] == 0x22 && le[3] == 0x11,
          "little-endian writes 44 33 22 11");
}

static void test_unaligned(void)
{
    printf("boundary 4 — an odd address, which is the normal case in a capture\n");

    /* A captured record is transport framing followed by an SPDM message, and
     * the message does not begin on a four-byte boundary. Any loader that only
     * works on aligned addresses is useless here. */
    uint8_t frame[16] = { 0 };
    memcpy(frame + 5, CAPS_TAIL, 8);

    CHECK(le32_load(frame + 5) == 0x8882F7C6u, "little-endian load at offset 5");
    CHECK(le32_load(frame + 9) == 4608u,       "little-endian load at offset 9");
    CHECK(be32_load(frame + 5) == 0xC6F78288u, "big-endian load at offset 5");
}

static void test_host_detection(void)
{
    printf("boundary 5 — two ways of asking, one machine\n");

    int u = host_is_le_union();
    int p = host_is_le_pointer();

    CHECK(u == 0 || u == 1, "the union answer is 0 or 1");
    CHECK(p == 0 || p == 1, "the pointer answer is 0 or 1");
    CHECK(u == p, "the two detectors agree");

    /* Not "this machine is little-endian" — that would be a test of the
     * hardware. What is being checked is that the detector agrees with the
     * loaders, which is a property of the code and holds on any machine. */
    uint32_t v = 0x01020304u;
    uint8_t bytes[4];
    memcpy(bytes, &v, 4);
    CHECK((bytes[0] == 0x04) == (u == 1),
          "the detector agrees with what memcpy of a uint32_t shows");

    printf("       (this machine reports %s-endian)\n", u ? "little" : "big");
}

int main(void)
{
    printf("d5 — two byte orders in one connection\n\n");

    test_little_endian_payload();          printf("\n");
    test_big_endian_framing();             printf("\n");
    test_top_byte_set_both_orders();       printf("\n");
    test_round_trip();                     printf("\n");
    test_store_puts_bytes_where_expected();printf("\n");
    test_unaligned();                      printf("\n");
    test_host_detection();

    printf("\n%d/%d checks passed\n", g_checks - g_failures, g_checks);
    if (g_failures != 0) {
        printf("\n%d check(s) failed. If every one failed, the implementation\n"
               "is still stubbed out — that is the exercise, go write it.\n",
               g_failures);
        return 1;
    }
    printf("d5 PASS\n");
    return 0;
}

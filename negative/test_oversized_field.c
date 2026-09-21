/* negative/test_oversized_field.c - a field longer than the buffer it lands in.
 *
 * Status: IMPLEMENTED, W11. Seven cases, six defect variants, and a separate
 * two-part demonstration of what AddressSanitizer does and does not see.
 *
 * Advisory (pinned, third_party/dmtf-2026-0001.pin):
 *   GHSA-j54w-759w-xj3m - DMTF-2026-0001, published 2026-02-10.
 *   "Stack corruption in cryptlib_mbedtls CSR generation due to out-of-bounds
 *   write". CWE-20 Improper Input Validation. CVSS 4.0 base 6.9.
 *   Affected libspdm 3.0 to 3.8.1; patched in 3.8.2 and 4.0.
 *   NO CVE was issued, and the advisory says why in its own words: "due to the
 *   unlikely chance of implementation in a production device".
 *
 *   ★ Two things about that are worth carrying into an answer. The first is
 *   that it scores 6.9 and has no CVE, while the one advisory here that DOES
 *   have a CVE scores 6.0 - so the score is not the decision, the CNA's
 *   judgement about deployment is. The second is that it reaches only the
 *   mbedTLS back end: the same protocol library has a different attack surface
 *   under a different crypto back end, and this project builds OpenSSL.
 *   docs/advisories.md section 3 turns that from a remark into a verdict.
 *
 * -- the class --------------------------------------------------------------
 *
 * A request carries a variable-length field whose length the sender chooses:
 * a subject name in GET_CSR, an opaque data blob, a vendor-defined payload.
 * The receiver copies it into a fixed buffer. The defect is not the copy; it
 * is checking the WRONG LENGTH before it:
 *
 *     memcpy(dest, src, declared_len);           nothing checked at all
 *     if (declared_len <= message_len) ...       checked against the WRONG object
 *     strncpy(dest, src, sizeof dest);           no terminator on the boundary
 *
 * The second is the interesting one and the one that gets written. It looks
 * like a bounds check and it is: it bounds the READ. The WRITE is unbounded,
 * and when dest is a stack buffer the result is the 2026 GET_CSR class.
 *
 * Two lengths, and a check has to name which one it is about:
 *
 *       declared_len <= message_len        the field fits in the MESSAGE
 *       declared_len <  sizeof dest        the field fits in the BUFFER
 *
 * Both are required and neither implies the other. This is
 * c-drills/d8_bounded_copy, where the same pair appears as "how many bytes are
 * there" against "how many bytes fit".
 *
 * -- ★ and what writing it down actually taught ------------------------------
 *
 * Two things, and both are about the instrument rather than the bug.
 *
 * 1. THE MESSAGE BOUND IS NOT PROTECTED BY THE ALLOCATOR. A responder does not
 *    receive a 32-byte message into a 32-byte allocation; it receives it into
 *    a transport buffer sized for the largest message the link allows. Reading
 *    forty bytes of a thirty-two byte message is therefore inside the
 *    allocation and outside the message, and AddressSanitizer is silent. It is
 *    still a disclosure of whatever the previous message left there. Only the
 *    declared-against-message check catches it, which is defect 4 below.
 *
 * 2. ASAN SEES AN OVERFLOW OUT OF A BARE ARRAY AND NOT ONE INTO THE NEXT
 *    MEMBER OF THE SAME STRUCT. The same overflow, one line apart in how the
 *    destination was declared. `make test` runs both - --asan-demo bare and
 *    --asan-demo member - and requires the first to be reported and the second
 *    not to be, so the claim is observed on the build that is actually running
 *    rather than recalled from documentation.
 *
 *    That is why every case below writes into a struct with a guard region
 *    after the destination and checks the guard by hand. The guard is not
 *    belt-and-braces. It is the only thing watching.
 */

#include "negative.h"

#include <stdio.h>
#include <string.h>

#ifndef NEG_DEFECT
#define NEG_DEFECT 0
#endif

#define CN_MAX      64u     /* the destination: a fixed array in a frame */
#define GUARD       256u    /* what sits after it, and what watches */
#define GUARD_BYTE  0xA5u
#define RX_SIZE     512u    /* the transport buffer a message arrives in */
#define PAST_MSG    0xDDu   /* what is in the transport buffer past the message */

typedef struct {
    char          cn[CN_MAX];
    unsigned char guard[GUARD];
} frame_t;

/* ---------------------------------------------------------------------------
 * The implementation under test.
 *
 * src/msg_len describe the FIELD as it sits in the transport buffer: msg_len
 * is how many bytes of this message are actually present, not how big the
 * buffer is. That distinction is the subject of defect 4.
 * ------------------------------------------------------------------------ */

static neg_status_t copy_field(const uint8_t *src, size_t msg_len,
                               size_t declared, char *dest, size_t dest_size)
{
#if NEG_DEFECT == 7
    /* defect 7: every check is present, correct and in the right order — and
     * all of them run AFTER the copy.
     *
     * ★ This is DMTF-2026-0001's own shape, taken from the published fix
     * rather than from the summary. The defective upstream code wrote the
     * attribute name, then '=', then the value, then ',', decrementing a
     * signed counter as it went, and only then asked `if (buff_len < 0)`. The
     * refusal it returned was the right refusal. The bytes were already there.
     *
     * The status code this produces is therefore CORRECT for cases 2 and 3,
     * and a suite comparing status codes alone would see nothing at all. What
     * sees it is the guard region after the destination, and the code it
     * reports through is NEG_ERR_FIELD_WRITE_ESCAPED_BUFFER, which exists
     * because this defect needed a door and did not have one. */
    if (declared > msg_len) { return NEG_ERR_FIELD_LONGER_THAN_MESSAGE; }
    if (declared > 0) {
        memcpy(dest, src, declared);
    }
    dest[declared] = '\0';
    if (declared > dest_size)  { return NEG_ERR_FIELD_LONGER_THAN_BUFFER; }
    if (declared == dest_size) { return NEG_ERR_FIELD_NOT_TERMINATED; }
    return NEG_OK;
#else

#if NEG_DEFECT == 5
    /* defect 5: the destination is consulted first. It looks harmless and it
     * reverses the only ordering that is safe: until the field is known to be
     * inside the message, there is nothing here that can be trusted, including
     * the reason for the refusal that gets reported. */
    if (declared > dest_size)  { return NEG_ERR_FIELD_LONGER_THAN_BUFFER; }
    if (declared > msg_len)    { return NEG_ERR_FIELD_LONGER_THAN_MESSAGE; }
    if (declared == dest_size) { return NEG_ERR_FIELD_NOT_TERMINATED; }
#elif NEG_DEFECT == 4
    /* defect 4: no check against the message at all. The read stays inside the
     * transport buffer, so nothing complains, and the bytes that come back are
     * whatever the previous message left behind. */
    (void)msg_len;
    if (declared > dest_size)  { return NEG_ERR_FIELD_LONGER_THAN_BUFFER; }
    if (declared == dest_size) { return NEG_ERR_FIELD_NOT_TERMINATED; }
#elif NEG_DEFECT == 1
    /* defect 1: the length is checked against the message, and that check is
     * then mistaken for a bound on the copy. This is the advisory's shape. */
    (void)dest_size;
    if (declared > msg_len)    { return NEG_ERR_FIELD_LONGER_THAN_MESSAGE; }
#elif NEG_DEFECT == 2
    /* defect 2: the bytes are required to fit and the terminator is not. */
    if (declared > msg_len)    { return NEG_ERR_FIELD_LONGER_THAN_MESSAGE; }
    if (declared > dest_size)  { return NEG_ERR_FIELD_LONGER_THAN_BUFFER; }
#else
    if (declared > msg_len)    { return NEG_ERR_FIELD_LONGER_THAN_MESSAGE; }
    if (declared > dest_size)  { return NEG_ERR_FIELD_LONGER_THAN_BUFFER; }
    if (declared == dest_size) { return NEG_ERR_FIELD_NOT_TERMINATED; }
#endif

    if (declared > 0) {
        memcpy(dest, src, declared);
    }

#if NEG_DEFECT == 3
    /* defect 3: nothing is written when the field is empty, so the previous
     * request's subject name is still there and is read out as this one's. */
    if (declared > 0) {
        dest[declared] = '\0';
    }
#elif NEG_DEFECT == 6
    /* defect 6: no terminator at all. The bytes are bounded and the string is
     * not a string. */
#else
    dest[declared] = '\0';
#endif
    return NEG_OK;
#endif /* NEG_DEFECT == 7 */
}

/* ---------------------------------------------------------------------------
 * The cases.
 * ------------------------------------------------------------------------ */

typedef struct {
    size_t declared;
    size_t msg_len;
} input_t;

static const neg_case_t CASES[] = {
    { "fits the buffer, not the message",   NEG_ERR_FIELD_LONGER_THAN_MESSAGE },
    { "fits neither; the message wins",     NEG_ERR_FIELD_LONGER_THAN_MESSAGE },
    { "fits the message, not the buffer",   NEG_ERR_FIELD_LONGER_THAN_BUFFER  },
    { "exactly the message, too big still", NEG_ERR_FIELD_LONGER_THAN_BUFFER  },
    { "exactly the buffer; no room for NUL",NEG_ERR_FIELD_NOT_TERMINATED      },
    { "the largest field that fits",        NEG_OK                            },
    { "an empty field",                     NEG_OK                            },
};

static const input_t INPUTS[] = {
    {  40,  32 },
    { 200, 128 },
    {  70, 128 },
    { 128, 128 },
    {  64, 128 },
    {  63, 128 },
    {   0, 128 },
};

#define NCASES (sizeof CASES / sizeof CASES[0])

static const int m1[] = { 2, 3, 4, -1 };  static const int a1[] = { 2, 3, 4, -1 };
static const int m2[] = { 4, -1 };        static const int a2[] = { 4, -1 };
static const int m3[] = { 6, -1 };
static const int m4[] = { 0, 1, -1 };     static const int a4[] = { 0, -1 };
static const int m5[] = { 1, -1 };
static const int m6[] = { 5, 6, -1 };
static const int m7[] = { 2, 3, 4, -1 };
static const int none[] = { -1 };

static const neg_defect_t DEFECTS[] = {
    { "the message bound is mistaken for a bound on the copy",     m1, a1   },
    { "the bytes are required to fit and the terminator is not",   m2, a2   },
    { "an empty field leaves the previous one in place",           m3, none },
    { "no check against the message; the read leaves it",          m4, a4   },
    { "the destination is checked before the message",             m5, none },
    { "the bytes are bounded and no terminator is written",        m6, none },
    /* ★ Same three cases as defect 1 and a different severity list: defect 1
     * ACCEPTS them, this one REFUSES them and has already written. Neither the
     * status code nor the exit status can tell the two apart. The guard can. */
    { "every check is right, and all of them run after the copy",  m7, none },
};

#define NDEFECTS (sizeof DEFECTS / sizeof DEFECTS[0])

/* ---------------------------------------------------------------------------
 * Running one case.
 * ------------------------------------------------------------------------ */

static uint8_t rxbuf[RX_SIZE];
static size_t  clobbers;   /* guard regions found overwritten, over all cases */

static void fill_rx(size_t msg_len)
{
    for (size_t i = 0; i < RX_SIZE; i++) {
        rxbuf[i] = (i < msg_len) ? (uint8_t)('a' + (i % 26u)) : (uint8_t)PAST_MSG;
    }
}

static neg_status_t run_case(size_t i)
{
    frame_t f;
    neg_status_t st;

    fill_rx(INPUTS[i].msg_len);

    /* The destination is pre-filled with something that is NOT a terminated
     * empty string, so "left as it was" and "cleared" are distinguishable.
     * Case 6 is the only one that can tell them apart and defect 3 is the only
     * thing that moves it. */
    memset(f.cn, 'X', sizeof f.cn);
    memset(f.guard, GUARD_BYTE, sizeof f.guard);

    st = copy_field(rxbuf, INPUTS[i].msg_len, INPUTS[i].declared,
                    f.cn, sizeof f.cn);

    bool escaped = false;
    for (size_t k = 0; k < sizeof f.guard; k++) {
        if (f.guard[k] != (unsigned char)GUARD_BYTE) {
            clobbers++;
            escaped = true;
            break;
        }
    }

    /* Refused, and wrote anyway. The verdict is right and the memory is gone,
     * and the three FIELD_ codes are all verdicts about the request — so this
     * needs a door of its own or it is invisible. Defect 7 is why.
     *
     * When the implementation ACCEPTED and wrote past the destination, the
     * status stays NEG_OK: that is already the loudest thing the report can
     * say about a case that expected a refusal, and collapsing the two would
     * lose the distinction defect 1 and defect 7 exist to draw. */
    if (escaped && st != NEG_OK) {
        return NEG_ERR_FIELD_WRITE_ESCAPED_BUFFER;
    }

    if (st != NEG_OK || CASES[i].expect != NEG_OK) {
        return st;
    }

    /* A success has three obligations and the caller can check all of them.
     * Anything missing is reported as NOT_TERMINATED, because from the
     * caller's side what came back is not the string it asked for. */
    if (memchr(f.cn, '\0', sizeof f.cn) == NULL) {
        return NEG_ERR_FIELD_NOT_TERMINATED;
    }
    if (f.cn[INPUTS[i].declared] != '\0') {
        return NEG_ERR_FIELD_NOT_TERMINATED;
    }
    if (INPUTS[i].declared > 0 &&
        memcmp(f.cn, rxbuf, INPUTS[i].declared) != 0) {
        return NEG_ERR_FIELD_NOT_TERMINATED;
    }
    return NEG_OK;
}

/* ---------------------------------------------------------------------------
 * ★ The two-line experiment about what is actually watching.
 *
 * Both halves write seventy-two bytes into a sixty-four byte destination. They
 * differ only in how the destination was declared, and they are treated
 * differently at BOTH the compile-time and the run-time layer.
 *
 * The first draft of this function did not compile, and that was the first
 * result:
 *
 *   error: '__builtin___memcpy_chk' forming offset [64, 71] is out of the
 *   bounds [0, 64] of object 'cn' with type 'char[64]' [-Werror=array-bounds=]
 *
 * GCC rejected the bare-array version before it ever ran, through
 * _FORTIFY_SOURCE's fortified memcpy. It did NOT reject the struct-member
 * version, because __builtin_object_size of a sub-object reports the size of
 * the object that ENCLOSES it. So the compiler draws exactly the same line the
 * sanitizer draws, one layer earlier, and neither of them draws it where a
 * reader would expect.
 *
 * ★ And the static check only fires because the length is a constant it can
 * see. A firmware length is never a constant: it is a field off the wire. So
 * `demo_len` below is volatile, which is what makes this demonstration honest
 * rather than a compiler exercise -- and it is also the reason the static
 * check is not the thing protecting a responder.
 *
 * `make test` runs both halves and asserts the difference, so this is an
 * observation about the toolchain that is in front of us rather than a
 * recalled fact about sanitizers in general.
 * ------------------------------------------------------------------------ */

static volatile size_t demo_len = 72;

static int asan_demo(const char *which)
{
    size_t n = demo_len;

    fill_rx(128);

    if (strcmp(which, "bare") == 0) {
        char cn[CN_MAX];
        printf("writing %zu bytes into a bare char[%u] on the stack\n", n, CN_MAX);
        fflush(stdout);
        memcpy(cn, rxbuf, n);
        printf("NOT REPORTED, and the first byte is %c\n", cn[0]);
        return 0;
    }
    if (strcmp(which, "member") == 0) {
        frame_t f;
        memset(f.guard, GUARD_BYTE, sizeof f.guard);
        printf("writing %zu bytes into a char[%u] that is a member of a struct\n",
               n, CN_MAX);
        fflush(stdout);
        memcpy(f.cn, rxbuf, n);
        if (f.guard[0] != (unsigned char)GUARD_BYTE) {
            printf("NOT REPORTED by the sanitizer, and the guard byte after the\n"
                   "destination is now 0x%02X. The overflow happened, it stayed\n"
                   "inside the enclosing object, and nothing but this line saw it.\n",
                   f.guard[0]);
            return 0;
        }
        printf("the guard was not touched, which this demonstration did not expect\n");
        return 1;
    }
    printf("--asan-demo takes 'bare' or 'member'\n");
    return 2;
}

int main(int argc, char **argv)
{
    if (argc == 3 && strcmp(argv[1], "--asan-demo") == 0) {
        return asan_demo(argv[2]);
    }
    if (neg_handled_args(argc, argv, CASES, NCASES, DEFECTS, NDEFECTS)) {
        return 0;
    }

    neg_status_t got[NCASES];
    for (size_t i = 0; i < NCASES; i++) {
        got[i] = run_case(i);
    }

    int rc = neg_report("test_oversized_field",
                        "a declared length checked against the wrong object",
                        CASES, got, NCASES, NEG_DEFECT, DEFECTS, NDEFECTS);

    if (clobbers > 0) {
        printf("  ★ the guard after the destination was overwritten in %zu case(s),\n"
               "    and no sanitizer said anything, because the write stayed inside\n"
               "    the enclosing object. ./test_oversized_field --asan-demo member\n",
               clobbers);
    }
#if NEG_DEFECT == 0
    if (clobbers > 0) {
        printf("  FAIL  the implementation this file argues is correct wrote past\n"
               "        its destination. No status code makes that acceptable.\n");
        rc = 1;
    }
#endif
    return rc;
}

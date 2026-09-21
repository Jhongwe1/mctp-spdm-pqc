/* negative/test_transcript_coverage.c - a signature over the wrong bytes.
 *
 * Status: IMPLEMENTED, W11. Eight cases, six defect variants, and a
 * calibration that has to hold before any of them is believed.
 *
 * Advisory (pinned, third_party/dmtf-2026-0003.pin):
 *   GHSA-chjj-xvqx-c8w4 = CVE-2026-61810 - DMTF-2026-0003, published
 *   2026-07-03. "SPDM (DSP0274) FINISH transcript under-specifies the new 1.4
 *   OpaqueData fields". CWE-325 Missing Cryptographic Step. CVSS 4.0 base 6.0,
 *   vector AV:A/AC:L/AT:P/PR:N/UI:N/VC:N/VI:H/VA:N/SC:N/SI:N/SA:N.
 *   Affected product: DSP0274 1.4.0 - the SPECIFICATION, not a library.
 *   Patched in DSP0274 1.4.1.
 *
 *   Both versions are pinned here (third_party/dsp0274.pin and
 *   third_party/dsp0274-1.4.1.pin) and both were read. What changed in the
 *   five definitions is in docs/transcript.md section 3, quoted.
 *
 * -- the class, and why it is the odd one of the three ----------------------
 *
 * The other two files are memory safety: a sanitizer finds them, a fuzzer
 * reaches them, and a compiler warning sometimes hints at them. This one is
 * none of those. Every line executes correctly, nothing is out of bounds, and
 * the result is wrong.
 *
 * A signature is worth exactly the bytes it covers.
 *
 * SPDM signatures are computed over a TRANSCRIPT: a concatenation of the
 * messages exchanged so far. If a message is accepted into the conversation
 * and NOT appended, then an attacker who changes that message changes nothing
 * that any signature covers, and every signature still verifies. The handshake
 * completes. The verifier is satisfied. And the thing it was satisfied about
 * is not what happened.
 *
 * -- ★ what the two specification versions actually say ----------------------
 *
 * DSP0274 1.4 added OpaqueDataLength and OpaqueData to FINISH and FINISH_RSP,
 * BEFORE the trailing signature and HMAC. Five transcript definitions were not
 * updated with them. In 1.4.0 all five end like this:
 *
 *       8.  [FINISH] . SPDM Header Fields
 *
 * and "SPDM Header Fields" is four bytes: SPDMVersion, RequestResponseCode,
 * Param1, Param2. In 1.4.1 the same five read:
 *
 *       8.  [FINISH] . * except the Signature and RequesterVerifyData fields.
 *
 * ★★ THE FIX IS NOT A FIELD. IT IS A CHANGE OF SHAPE. 1.4.0 enumerated what
 * the transcript INCLUDES; 1.4.1 names what it EXCLUDES. An enumeration has to
 * be revisited every time the message changes and nothing forces that to
 * happen; an exclusion is correct by construction for a field that does not
 * exist yet.
 *
 * ★★★ And the enumeration was not wrong when it was written. In SPDM 1.3 a
 * FINISH was a four-byte header followed by the signature, so "the SPDM Header
 * Fields" WAS everything before the authenticator. It became wrong when
 * somebody edited a different paragraph. That is the whole class: a correct
 * sentence made false at a distance, with no mechanism watching the join.
 *
 * Cases 4, 5 and 6 below are that story, run: the same 1.4.0-shaped rule over
 * a 1.3 message and a 1.4 message, and then the 1.4.1-shaped rule over the 1.4
 * message. One rule is right once and the other is right twice.
 *
 * -- what is modelled, and what is not --------------------------------------
 *
 * The signature here is a 64-bit FNV-1a digest, not a signature. That is
 * deliberate: the subject is WHICH BYTES go in, and a real signature would add
 * a key exchange and several hundred lines while changing nothing about the
 * answer. harness/challenge_verify.py does the real arithmetic, against real
 * captures, with OpenSSL - this file is the part that tool cannot be: a place
 * where the transcript is allowed to be WRONG.
 *
 * ★ And the calibration main() prints before anything else is the hinge of the
 * whole file: the incomplete transcript STILL VERIFIES. Signer and verifier
 * agree, because they are running the same defective rule. If that stopped
 * being true, every case below would be detecting a broken signature instead
 * of an incomplete one, which is the difference between this class and no
 * class at all.
 */

#include "negative.h"

#include <stdio.h>
#include <string.h>

#ifndef NEG_DEFECT
#define NEG_DEFECT 0
#endif

/* ---------------------------------------------------------------------------
 * The conversation.
 *
 * The lengths are this project's own: a 96-byte signature is ECDSA-P384 and a
 * 48-byte HMAC is SHA-384, which is what docs/pqc-cost.md's classical arm
 * negotiates. `auth` is the trailing run of bytes that IS the authenticator,
 * and therefore the only part of a message a transcript may legitimately omit.
 * ------------------------------------------------------------------------ */

typedef struct {
    const char *name;
    size_t      len;    /* bytes transmitted */
    size_t      auth;   /* trailing bytes that are the signature/HMAC itself */
} msg_t;

#define SIG_LEN  96u    /* ECDSA-P384 */
#define MAC_LEN  48u    /* SHA-384 */

/* A 1.4 exchange: FINISH carries OpaqueDataLength (2) + OpaqueData (16). */
static const msg_t CONV_14[] = {
    { "GET_VERSION",            4,   0 },
    { "VERSION",               10,   0 },
    { "GET_CAPABILITIES",      12,   0 },
    { "CAPABILITIES",          12,   0 },
    { "NEGOTIATE_ALGORITHMS",  48,   0 },
    { "ALGORITHMS",            52,   0 },
    { "KEY_EXCHANGE",         100,   0 },
    { "KEY_EXCHANGE_RSP",     200,   0 },
    { "FINISH",     4 + 2 + 16 + SIG_LEN + MAC_LEN, SIG_LEN + MAC_LEN },
};

/* The same exchange as SPDM 1.3 had it: FINISH is a header and the
 * authenticator, with nothing in between. */
static const msg_t CONV_13[] = {
    { "GET_VERSION",            4,   0 },
    { "VERSION",               10,   0 },
    { "GET_CAPABILITIES",      12,   0 },
    { "CAPABILITIES",          12,   0 },
    { "NEGOTIATE_ALGORITHMS",  48,   0 },
    { "ALGORITHMS",            52,   0 },
    { "KEY_EXCHANGE",         100,   0 },
    { "KEY_EXCHANGE_RSP",     200,   0 },
    { "FINISH",             4 + SIG_LEN + MAC_LEN, SIG_LEN + MAC_LEN },
};

#define NMSG (sizeof CONV_14 / sizeof CONV_14[0])

typedef struct {
    const msg_t *msg;
    size_t       n;
} conv_t;

/* One appended piece: which message, which bytes of it. */
typedef struct {
    size_t msg;
    size_t off;
    size_t len;
} slice_t;

#define MAX_SLICES 16

typedef struct {
    slice_t s[MAX_SLICES];
    size_t  n;
} transcript_t;

static size_t covered_extent(const msg_t *m)
{
    return m->len - m->auth;
}

/* ---------------------------------------------------------------------------
 * The implementation under test: does this transcript cover this conversation?
 *
 * Three questions, and the ORDER they are asked in is a decision rather than a
 * detail. Presence first, because "a message is missing" explains an
 * out-of-order sequence and the reverse is not true. Extent last, because an
 * extent is only meaningful once the right message is known to be in the right
 * place.
 * ------------------------------------------------------------------------ */

static neg_status_t transcript_check(const conv_t *conv, const transcript_t *tr)
{
#if NEG_DEFECT == 2
    /* defect 2: the transcript is compared by total length. It is the check
     * somebody writes when the transcript is already a blob and pulling it
     * apart again looks like work. */
    {
        size_t want = 0, have = 0;
        for (size_t i = 0; i < conv->n; i++) { want += covered_extent(&conv->msg[i]); }
        for (size_t i = 0; i < tr->n; i++)   { have += tr->s[i].len; }
        return (want == have) ? NEG_OK : NEG_ERR_TRANSCRIPT_LENGTH_MISMATCH;
    }
#else

#if NEG_DEFECT != 5
    /* presence */
    for (size_t i = 0; i < conv->n; i++) {
        if (covered_extent(&conv->msg[i]) == 0) {
            continue;
        }
        bool found = false;
        for (size_t k = 0; k < tr->n; k++) {
            if (tr->s[k].msg == i) { found = true; break; }
        }
        if (!found) {
            return NEG_ERR_TRANSCRIPT_MISSING_MESSAGE;
        }
    }
#endif

#if NEG_DEFECT != 1
    /* order: strictly increasing, so a repeat is as wrong as a swap */
    for (size_t k = 1; k < tr->n; k++) {
        if (tr->s[k].msg <= tr->s[k - 1].msg) {
            return NEG_ERR_TRANSCRIPT_WRONG_ORDER;
        }
    }
#endif

    /* extent */
    for (size_t k = 0; k < tr->n; k++) {
        const msg_t *m = &conv->msg[tr->s[k].msg];
        size_t want = covered_extent(m);

        if (tr->s[k].off != 0) {
            return NEG_ERR_TRANSCRIPT_LENGTH_MISMATCH;
        }
#if NEG_DEFECT == 3
        /* defect 3: the whole message is demanded, authenticator included. A
         * signature cannot cover itself, so this refuses every correct
         * transcript there is. */
        (void)want;
        if (tr->s[k].len != m->len) {
            return NEG_ERR_TRANSCRIPT_LENGTH_MISMATCH;
        }
#elif NEG_DEFECT == 4
        /* defect 4: any prefix counts as covering the message. This is the one
         * the advisory is about: the four-byte header IS a prefix of FINISH,
         * so a checker written this way passes 1.4.0 without complaint. */
        if (tr->s[k].len > want) {
            return NEG_ERR_TRANSCRIPT_LENGTH_MISMATCH;
        }
#elif NEG_DEFECT == 6
        /* defect 6: only a lower bound. Covering MORE than the covered extent
         * is permitted, which would mean signing bytes that do not exist until
         * the signature does. */
        if (tr->s[k].len < want) {
            return NEG_ERR_TRANSCRIPT_LENGTH_MISMATCH;
        }
#else
        if (tr->s[k].len != want) {
            return NEG_ERR_TRANSCRIPT_LENGTH_MISMATCH;
        }
#endif
    }
    return NEG_OK;
#endif /* NEG_DEFECT == 2 */
}

/* ---------------------------------------------------------------------------
 * The transcripts each case feeds in.
 * ------------------------------------------------------------------------ */

/* Every message, covered to the authenticator. This is DSP0274 1.4.1. */
static transcript_t rule_1_4_1(const conv_t *conv)
{
    transcript_t tr = { { { 0, 0, 0 } }, 0 };
    for (size_t i = 0; i < conv->n && tr.n < MAX_SLICES; i++) {
        tr.s[tr.n].msg = i;
        tr.s[tr.n].off = 0;
        tr.s[tr.n].len = covered_extent(&conv->msg[i]);
        tr.n++;
    }
    return tr;
}

/* The same, except that the last message contributes only its four header
 * bytes. This is DSP0274 1.4.0, word for word: "[FINISH].SPDM Header Fields". */
static transcript_t rule_1_4_0(const conv_t *conv)
{
    transcript_t tr = rule_1_4_1(conv);
    tr.s[tr.n - 1].len = 4;
    return tr;
}

/* ---------------------------------------------------------------------------
 * A digest, so that "it still verifies" can be shown rather than asserted.
 * ------------------------------------------------------------------------ */

static uint64_t digest(const transcript_t *tr, unsigned salt)
{
    uint64_t h = 1469598103934665603ULL;
    for (size_t k = 0; k < tr->n; k++) {
        for (size_t b = 0; b < tr->s[k].len; b++) {
            /* Stand-in for the message's actual bytes: a function of which
             * message, which offset, and a salt the tamper demonstration
             * changes. */
            uint8_t byte = (uint8_t)(tr->s[k].msg * 37u + (tr->s[k].off + b) * 11u
                                     + (tr->s[k].msg == 6 ? salt : 0u));
            h ^= byte;
            h *= 1099511628211ULL;
        }
    }
    return h;
}

/* ---------------------------------------------------------------------------
 * The cases.
 * ------------------------------------------------------------------------ */

static const neg_case_t CASES[] = {
    { "1.4.1 rule, every message",          NEG_OK                             },
    { "a message accepted, not appended",   NEG_ERR_TRANSCRIPT_MISSING_MESSAGE },
    { "two messages appended out of order", NEG_ERR_TRANSCRIPT_WRONG_ORDER     },
    { "the signature appended to its own",  NEG_ERR_TRANSCRIPT_LENGTH_MISMATCH },
    { "1.4.0 rule over a 1.3 FINISH",       NEG_OK                             },
    { "1.4.0 rule over a 1.4 FINISH",       NEG_ERR_TRANSCRIPT_LENGTH_MISMATCH },
    { "1.4.1 rule over the same 1.4 FINISH",NEG_OK                             },
    { "one message in place of another",    NEG_ERR_TRANSCRIPT_MISSING_MESSAGE },
};

#define NCASES (sizeof CASES / sizeof CASES[0])

static const int m1[] = { 2, -1 };        static const int a1[] = { 2, -1 };
static const int m2[] = { 1, 2, 7, -1 };  static const int a2[] = { 2, 7, -1 };
/* ★ m3 was written as { 0, 4, 6 } and the runner refused it: case 3 moved too,
 * and nothing had predicted that. It is right and the prediction was wrong.
 * Demanding the WHOLE message does not merely refuse every correct transcript
 * — it also ACCEPTS the one transcript that covers a signature with itself,
 * because that transcript is the only one whose last slice is the whole
 * message. One mistake, in both directions at once, and the half that was
 * missed is the half that opens something. 2026-10-19 in LOG.md. */
static const int m3[] = { 0, 3, 4, 6, -1 };  static const int a3[] = { 3, -1 };
static const int m4[] = { 5, -1 };        static const int a4[] = { 5, -1 };
static const int m5[] = { 1, 7, -1 };     static const int a5[] = { 1, -1 };
static const int m6[] = { 3, -1 };        static const int a6[] = { 3, -1 };

static const neg_defect_t DEFECTS[] = {
    { "the appended messages are compared as a set",              m1, a1   },
    { "the transcript is compared by total length",               m2, a2   },
    { "the whole message is demanded, authenticator included",    m3, a3   },
    { "any prefix counts as covering the message",                m4, a4   },
    { "a message that was sent is allowed to be absent",          m5, a5   },
    { "covering more than the covered extent is permitted",       m6, a6   },
};

#define NDEFECTS (sizeof DEFECTS / sizeof DEFECTS[0])

static const conv_t CONV_A = { CONV_14, NMSG };
static const conv_t CONV_B = { CONV_13, NMSG };

static neg_status_t run_case(size_t i)
{
    transcript_t tr;

    switch (i) {
    case 0:
        tr = rule_1_4_1(&CONV_A);
        return transcript_check(&CONV_A, &tr);
    case 1:
        /* KEY_EXCHANGE, index 6, is accepted and never appended. */
        tr = rule_1_4_1(&CONV_A);
        memmove(&tr.s[6], &tr.s[7], (tr.n - 7) * sizeof tr.s[0]);
        tr.n--;
        return transcript_check(&CONV_A, &tr);
    case 2: {
        slice_t swap;
        tr = rule_1_4_1(&CONV_A);
        swap = tr.s[4]; tr.s[4] = tr.s[5]; tr.s[5] = swap;
        return transcript_check(&CONV_A, &tr);
    }
    case 3:
        /* The last message contributes its signature and HMAC as well. */
        tr = rule_1_4_1(&CONV_A);
        tr.s[tr.n - 1].len = CONV_14[NMSG - 1].len;
        return transcript_check(&CONV_A, &tr);
    case 4:
        tr = rule_1_4_0(&CONV_B);
        return transcript_check(&CONV_B, &tr);
    case 5:
        tr = rule_1_4_0(&CONV_A);
        return transcript_check(&CONV_A, &tr);
    case 6:
        tr = rule_1_4_1(&CONV_A);
        return transcript_check(&CONV_A, &tr);
    case 7:
        /* GET_CAPABILITIES (2) is replaced by a second copy of CAPABILITIES
         * (3). Both are twelve bytes, so a checker that adds up lengths sees
         * nothing at all. */
        tr = rule_1_4_1(&CONV_A);
        tr.s[2] = tr.s[3];
        return transcript_check(&CONV_A, &tr);
    default:
        return NEG_OK;
    }
}

/* ---------------------------------------------------------------------------
 * The calibration, and the demonstration it makes possible.
 * ------------------------------------------------------------------------ */

static int calibrate(void)
{
    transcript_t full = rule_1_4_1(&CONV_A);
    transcript_t gap  = rule_1_4_1(&CONV_A);
    memmove(&gap.s[6], &gap.s[7], (gap.n - 7) * sizeof gap.s[0]);
    gap.n--;

    /* KEY_EXCHANGE is message 6, and `salt` changes one of its bytes. An
     * attacker changed it in flight; both ends then sign and verify. */
    uint64_t full_signed   = digest(&full, 0);
    uint64_t full_tampered = digest(&full, 1);
    uint64_t gap_signed    = digest(&gap,  0);
    uint64_t gap_tampered  = digest(&gap,  1);

    printf("  calibration\n");
    printf("    the complete transcript, one byte of KEY_EXCHANGE changed:\n");
    printf("      %016llx -> %016llx   %s\n",
           (unsigned long long)full_signed, (unsigned long long)full_tampered,
           full_signed == full_tampered ? "UNCHANGED" : "the signature breaks");
    printf("    the transcript with KEY_EXCHANGE missing, same change:\n");
    printf("      %016llx -> %016llx   %s\n",
           (unsigned long long)gap_signed, (unsigned long long)gap_tampered,
           gap_signed == gap_tampered ? "UNCHANGED — it still verifies"
                                      : "the signature breaks");

    if (full_signed == full_tampered) {
        printf("    FAIL  the complete transcript did not notice the change, so\n"
               "          this model cannot distinguish coverage from anything\n");
        return 1;
    }
    if (gap_signed != gap_tampered) {
        printf("    FAIL  the incomplete transcript noticed the change. Every case\n"
               "          below would then be detecting a BROKEN signature rather\n"
               "          than an INCOMPLETE one, which is a different subject\n");
        return 1;
    }
    printf("    ok    an uncovered message can be changed and the signature is\n"
           "          still valid. That is the class, and only the coverage\n"
           "          check below can see it.\n\n");
    return 0;
}

int main(int argc, char **argv)
{
    if (neg_handled_args(argc, argv, CASES, NCASES, DEFECTS, NDEFECTS)) {
        return 0;
    }

    if (calibrate() != 0) {
        return 1;
    }

    neg_status_t got[NCASES];
    for (size_t i = 0; i < NCASES; i++) {
        got[i] = run_case(i);
    }

    return neg_report("test_transcript_coverage",
                      "a signature over a transcript that omits a sent message",
                      CASES, got, NCASES, NEG_DEFECT, DEFECTS, NDEFECTS);
}

/* negative/test_offset_length.c - a window into a larger object.
 *
 * Status: IMPLEMENTED, W11. Nine cases, eight defect variants, and every case
 * is moved by at least one of them. `make test` builds the correct version and
 * all eight defects and requires each to behave exactly as declared below.
 *
 * Advisory (pinned, third_party/dmtf-2026-0002.pin):
 *   GHSA-m4wc-xmvg-369f - DMTF-2026-0002, published 2026-04-03.
 *   "Requester may read unauthorized memory via GET_MEASUREMENT_EXTENSION_LOG"
 *   CWE-680 Integer Overflow to Buffer Overflow. CVSS 4.0 base 6.9.
 *   Affected libspdm 3.4 to 3.8.1; patched in 3.8.2 and 4.0.
 *   NO CVE was issued for it. See docs/advisories.md section 1 for why that
 *   is worth knowing and why the obvious URL for it returns 404.
 *
 * -- the class --------------------------------------------------------------
 *
 * SPDM has several messages that ask for a window into something larger:
 *
 *     GET_CERTIFICATE            Offset (2 B)   Length (2 B)
 *     GET_MEASUREMENT_EXT_LOG    Offset (4 B)   Length (4 B)
 *     CHUNK_GET                  ChunkSeqNo, against a LargeMessageSize
 *
 * Each is "give me bytes [Offset, Offset + Length) of an object of size N",
 * and each is a place where Offset + Length is computed in a fixed-width type.
 *
 * The check that reads correctly in English is the wrong one:
 *
 *       if (off + len <= total)            <-- WRONG
 *
 * because off + len can wrap. The version that cannot wrap subtracts instead:
 *
 *       if (off <= total && len <= total - off)
 *
 * This is exactly c-drills/d2_offset_length, and that is not a coincidence:
 * the drill was pulled out of this message.
 *
 * -- ★ what writing it down actually taught -----------------------------------
 *
 * The wrong expression is not equally wrong at every field width, and the
 * reason is C's integer promotions rather than anything about SPDM.
 *
 *   uint32_t off, len;   off + len   both operands already have the rank of
 *                                    int, so the addition happens in
 *                                    unsigned int and WRAPS modulo 2^32
 *
 *   uint16_t off, len;   off + len   both operands are promoted to int first,
 *                                    because int can represent every uint16_t
 *                                    value, so the sum is 65537 and does NOT
 *                                    wrap
 *
 * So the identical source line is a hole in GET_MEASUREMENT_EXTENSION_LOG and
 * merely a mislabelled refusal in GET_CERTIFICATE - and the advisory is
 * against the 32-bit message. Defects 1 and 2 below differ in exactly this and
 * in nothing else: defect 1 writes the sum in an expression (16-bit path
 * survives), defect 2 stores it back into the field's own type first (both
 * paths fall). The suite ASSERTS that difference rather than describing it,
 * which is standing rule 18: a claim that two things differ has to evaluate
 * both of them.
 *
 * ★ And neither sanitizer finds this. Unsigned overflow is DEFINED behaviour
 * in C, so UBSan is silent by design; AddressSanitizer only speaks when the
 * bad index is actually dereferenced. The check that catches it is the
 * assertion below, and that is the whole argument for writing one.
 *
 * -- what it is NOT ---------------------------------------------------------
 *
 * Not a test of libspdm. It links nothing from libspdm, includes no libspdm
 * header, and says nothing about whether libspdm has this defect. Whether
 * THIS PROJECT'S builds have it is a different question with a different
 * answer, measured rather than argued, in docs/advisories.md section 3.
 */

#include "negative.h"

#include <stdio.h>
#include <string.h>

#ifndef NEG_DEFECT
#define NEG_DEFECT 0
#endif

/* ---------------------------------------------------------------------------
 * The implementation under test, at both of the widths SPDM uses.
 *
 * Both take `total` as size_t because that is what a real responder has: the
 * object's size is a property of the device, not of the message. The message's
 * own fields keep the width the wire gave them, which is the entire point.
 * ------------------------------------------------------------------------ */

/* GET_MEASUREMENT_EXTENSION_LOG: 32-bit Offset and Length. */
static neg_status_t window_u32(uint32_t off, uint32_t len, size_t total,
                               size_t *out_off, size_t *out_len)
{
#if NEG_DEFECT == 3
    /* defect 3: the object is consulted before the request's own form is
     * checked. A zero-length request is malformed whatever it points at, and
     * a responder that has not yet looked the object up cannot answer the
     * other question at all. */
    if (off > total)  { return NEG_ERR_WINDOW_OFFSET_PAST_END; }
    if (len == 0)     { return NEG_ERR_WINDOW_ZERO_LENGTH; }
#elif NEG_DEFECT == 6
    /* defect 6: no zero-length check at all. */
#else
    if (len == 0)     { return NEG_ERR_WINDOW_ZERO_LENGTH; }
#endif

/* Every comparison against `total` casts to size_t AFTER the arithmetic, never
 * before. The cast is there to keep -Wsign-compare quiet about mixing a
 * promoted field with a size_t; moving it inside the parentheses would change
 * the answer, which is the entire subject of this file. The 16-bit function
 * below is written with the identical line so the two can be read side by
 * side: same source, different result. */
#if NEG_DEFECT == 1
    /* defect 1: no overflow check, and the bound is written as the sum. */
    if ((size_t)off > total)         { return NEG_ERR_WINDOW_OFFSET_PAST_END; }
    if ((size_t)(off + len) > total) { return NEG_ERR_WINDOW_LENGTH_PAST_END; }
#elif NEG_DEFECT == 2
    /* defect 2: the same sum, stored back into the field's own type before it
     * is compared. This is the version that loses at BOTH widths. */
    {
        uint32_t end = off + len;
        if ((size_t)off > total)  { return NEG_ERR_WINDOW_OFFSET_PAST_END; }
        if ((size_t)end > total)  { return NEG_ERR_WINDOW_LENGTH_PAST_END; }
    }
#elif NEG_DEFECT == 4
    if ((uint32_t)(UINT32_MAX - off) < len) { return NEG_ERR_WINDOW_SUM_OVERFLOWS; }
    if ((size_t)off > total)          { return NEG_ERR_WINDOW_OFFSET_PAST_END; }
    /* defect 4: off by one. A window that ends exactly at the last byte is
     * legal and this refuses it. */
    if ((size_t)len >= total - off)   { return NEG_ERR_WINDOW_LENGTH_PAST_END; }
#elif NEG_DEFECT == 7
    if ((uint32_t)(UINT32_MAX - off) < len) { return NEG_ERR_WINDOW_SUM_OVERFLOWS; }
    /* defect 7: no offset check. `total - off` then underflows in size_t and
     * the bound becomes enormous, which is the same wrap as the original bug
     * wearing the other sign. */
    if ((size_t)len > total - off)    { return NEG_ERR_WINDOW_LENGTH_PAST_END; }
#elif NEG_DEFECT == 8
    if ((uint32_t)(UINT32_MAX - off) < len) { return NEG_ERR_WINDOW_SUM_OVERFLOWS; }
    if ((size_t)off > total)  { return NEG_ERR_WINDOW_OFFSET_PAST_END; }
    /* defect 8: the length is checked against the OBJECT rather than against
     * what is left of it. This is class 2's mistake -- a bound on the wrong
     * object -- appearing inside class 1. */
    if ((size_t)len > total)  { return NEG_ERR_WINDOW_LENGTH_PAST_END; }
#else
    if ((uint32_t)(UINT32_MAX - off) < len) { return NEG_ERR_WINDOW_SUM_OVERFLOWS; }
    if ((size_t)off > total)          { return NEG_ERR_WINDOW_OFFSET_PAST_END; }
    if ((size_t)len > total - off)    { return NEG_ERR_WINDOW_LENGTH_PAST_END; }
#endif

    *out_off = off;
#if NEG_DEFECT == 5
    /* defect 5: the window returned is what is left of the object rather than
     * what was asked for. Every status code is still right. */
    *out_len = total - off;
#else
    *out_len = len;
#endif
    return NEG_OK;
}

/* GET_CERTIFICATE: 16-bit Offset and Length. Identical in shape, and that is
 * what makes defects 1 and 2 separable. */
static neg_status_t window_u16(uint16_t off, uint16_t len, size_t total,
                               size_t *out_off, size_t *out_len)
{
    if (len == 0) { return NEG_ERR_WINDOW_ZERO_LENGTH; }

#if NEG_DEFECT == 1
    /* The same two lines as the 32-bit function, character for character apart
     * from the names. `off + len` here is computed in int, because int can
     * represent every uint16_t, so it does not wrap and this refuses. */
    if ((size_t)off > total)         { return NEG_ERR_WINDOW_OFFSET_PAST_END; }
    if ((size_t)(off + len) > total) { return NEG_ERR_WINDOW_LENGTH_PAST_END; }
#elif NEG_DEFECT == 2
    /* ...and here it does wrap, because the sum is put back into a uint16_t
     * before anything looks at it. That assignment is the bug, not the width. */
    {
        uint16_t end = (uint16_t)(off + len);
        if ((size_t)off > total)  { return NEG_ERR_WINDOW_OFFSET_PAST_END; }
        if ((size_t)end > total)  { return NEG_ERR_WINDOW_LENGTH_PAST_END; }
    }
#else
    if ((uint16_t)(UINT16_MAX - off) < len) { return NEG_ERR_WINDOW_SUM_OVERFLOWS; }
    if ((size_t)off > total)         { return NEG_ERR_WINDOW_OFFSET_PAST_END; }
    if ((size_t)len > total - off)   { return NEG_ERR_WINDOW_LENGTH_PAST_END; }
#endif

    *out_off = off;
    *out_len = len;
    return NEG_OK;
}

/* ---------------------------------------------------------------------------
 * The cases.
 * ------------------------------------------------------------------------ */

#define OBJ_SIZE 4096u

typedef struct {
    unsigned width;      /* 16 or 32 -- which message's field widths */
    uint32_t off;
    uint32_t len;
    size_t   want_off;   /* only read when the case expects NEG_OK */
    size_t   want_len;
} input_t;

static const neg_case_t CASES[] = {
    { "a legal window inside the object",   NEG_OK                         },
    { "the whole object, off+len == total", NEG_OK                         },
    { "offset one past the end",            NEG_ERR_WINDOW_OFFSET_PAST_END },
    { "window runs past the end",           NEG_ERR_WINDOW_LENGTH_PAST_END },
    { "sum unrepresentable, 32-bit fields", NEG_ERR_WINDOW_SUM_OVERFLOWS   },
    { "sum unrepresentable, 16-bit fields", NEG_ERR_WINDOW_SUM_OVERFLOWS   },
    { "zero length",                        NEG_ERR_WINDOW_ZERO_LENGTH     },
    { "zero length, offset past the end",   NEG_ERR_WINDOW_ZERO_LENGTH     },
    { "the last byte, off+len == total",    NEG_OK                         },
};

static const input_t INPUTS[] = {
    { 32, 1024,       256,        1024, 256  },
    { 32, 0,          OBJ_SIZE,   0,    OBJ_SIZE },
    { 32, OBJ_SIZE+1, 1,          0,    0    },
    { 32, 4000,       200,        0,    0    },
    { 32, 8,          0xFFFFFFF9u, 0,   0    },
    { 16, 8,          0xFFF9u,    0,    0    },
    { 32, 0,          0,          0,    0    },
    { 32, 5000,       0,          0,    0    },
    { 32, OBJ_SIZE-1, 1,          OBJ_SIZE-1, 1 },
};

#define NCASES (sizeof CASES / sizeof CASES[0])

/* The defects, and the exact cases each one must move.
 *
 * Read the two lists together. `must_move` is rule 13 -- if a mistake moves a
 * case nobody predicted, two cases are being caught by one check. `must_accept`
 * is the severity: a case that came back NEG_OK is a hole, one refused through
 * the wrong door is not, and defects 1 and 2 are here to show that the same
 * mistake can be either depending only on the width of the fields it is
 * written against. */
static const int m1[] = { 4, 5, -1 };  static const int a1[] = { 4, -1 };
static const int m2[] = { 4, 5, -1 };  static const int a2[] = { 4, 5, -1 };
static const int m3[] = { 7, -1 };
static const int m4[] = { 1, 8, -1 };
static const int m5[] = { 0, -1 };
static const int m6[] = { 6, 7, -1 };  static const int a6[] = { 6, -1 };
static const int m7[] = { 2, -1 };     static const int a7[] = { 2, -1 };
static const int m8[] = { 3, -1 };     static const int a8[] = { 3, -1 };
static const int none[] = { -1 };

static const neg_defect_t DEFECTS[] = {
    { "no overflow check; the bound is written as the sum",            m1, a1   },
    { "the sum is stored back into the field's own type first",        m2, a2   },
    { "the object is consulted before the request's form is checked",  m3, none },
    { "off by one: a window ending on the last byte is refused",       m4, none },
    { "the window returned is what is left, not what was asked for",   m5, none },
    { "no zero-length check",                                          m6, a6   },
    { "no offset check, so total - off underflows",                    m7, a7   },
    { "the length is bounded by the object, not by what is left",      m8, a8   },
};

#define NDEFECTS (sizeof DEFECTS / sizeof DEFECTS[0])

/* ---------------------------------------------------------------------------
 * Running one case.
 *
 * A window that comes back NEG_OK but is not the window that was asked for is
 * reported as the error it is from the caller's side -- a wrong offset is an
 * offset error and a wrong length is a length error. Defect 5 exists because
 * without that, a status-code-only suite cannot see a responder that returns
 * the right verdict and the wrong bytes.
 * ------------------------------------------------------------------------ */

static uint8_t object[OBJ_SIZE];

static neg_status_t run_case(size_t i)
{
    size_t got_off = SIZE_MAX, got_len = SIZE_MAX;
    neg_status_t st;

    if (INPUTS[i].width == 16) {
        st = window_u16((uint16_t)INPUTS[i].off, (uint16_t)INPUTS[i].len,
                        OBJ_SIZE, &got_off, &got_len);
    } else {
        st = window_u32(INPUTS[i].off, INPUTS[i].len,
                        OBJ_SIZE, &got_off, &got_len);
    }

    if (st != NEG_OK || CASES[i].expect != NEG_OK) {
        return st;
    }
    if (got_off != INPUTS[i].want_off) {
        return NEG_ERR_WINDOW_OFFSET_PAST_END;
    }
    if (got_len != INPUTS[i].want_len) {
        return NEG_ERR_WINDOW_LENGTH_PAST_END;
    }
    /* And the bytes themselves, because a length that agrees is not a window
     * that agrees. */
    for (size_t k = 0; k < got_len; k++) {
        if (object[got_off + k] != (uint8_t)((INPUTS[i].want_off + k) * 31u + 7u)) {
            return NEG_ERR_WINDOW_OFFSET_PAST_END;
        }
    }
    return NEG_OK;
}

int main(int argc, char **argv)
{
    if (neg_handled_args(argc, argv, CASES, NCASES, DEFECTS, NDEFECTS)) {
        return 0;
    }

    for (size_t i = 0; i < OBJ_SIZE; i++) {
        object[i] = (uint8_t)(i * 31u + 7u);
    }

    neg_status_t got[NCASES];
    for (size_t i = 0; i < NCASES; i++) {
        got[i] = run_case(i);
    }

    return neg_report("test_offset_length",
                      "Offset + Length computed in a type that wraps",
                      CASES, got, NCASES, NEG_DEFECT, DEFECTS, NDEFECTS);
}

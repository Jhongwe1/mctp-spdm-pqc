/* negative/test_offset_length.c - a window into a larger object.
 *
 * Status: SKELETON, W10. The assertions W11 has to make are written out below
 * as comments; nothing is implemented, negative/DONE.txt does not name this
 * file, and `make test` therefore does not run it. It does COMPILE, under
 * -Werror and both sanitizers, from the day it was committed - c-drills'
 * standing rule 15, for the same reason: a stub that does not build turns the
 * badge red on the day it lands rather than on the day somebody notices.
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
 * because off + len can wrap. With 16-bit fields and a 16-bit accumulator,
 * Offset = 0xFFFF and Length = 0x0002 sum to 0x0001, which passes a bound of
 * any size, and the read that follows starts 65,535 bytes past the object.
 * The version that cannot wrap subtracts instead:
 *
 *       if (off <= total && len <= total - off)
 *
 * This is exactly c-drills/d2_offset_length, and that is not a coincidence:
 * the drill was pulled out of this message.
 *
 * -- what W11 must assert ---------------------------------------------------
 *
 *   1. off  > total                      -> NEG_ERR_WINDOW_OFFSET_PAST_END
 *   2. off <= total, off + len > total   -> NEG_ERR_WINDOW_LENGTH_PAST_END
 *   3. off + len wraps                   -> NEG_ERR_WINDOW_SUM_OVERFLOWS
 *   4. len == 0                          -> NEG_ERR_WINDOW_ZERO_LENGTH
 *   5. a legal window of every shape     -> NEG_OK, and the right bytes
 *
 * Case 3 is the one the suite exists for, and cases 1 and 2 are what makes it
 * worth something: docs/roadmap.md standing rule 13 says two breaks caught by
 * the same check are one check, so the test asserts that case 3 comes back as
 * WINDOW_SUM_OVERFLOWS and not as WINDOW_LENGTH_PAST_END. A suite that only
 * required "refused" would pass against an implementation that had never
 * considered overflow at all, because the naive bound happens to reject cases
 * 1 and 2.
 *
 * And one more, which rule 11 requires: the test must be run against a
 * DELIBERATELY WRONG implementation - the `off + len <= total` one - and must
 * catch it. A negative test that has never been observed failing is arithmetic
 * that happens to agree. c-drills/README.md's "three ways" is the pattern;
 * this file follows it.
 *
 * -- what it is NOT ---------------------------------------------------------
 *
 * Not a test of libspdm. It links nothing from libspdm, includes no libspdm
 * header, and says nothing about whether libspdm has this defect. It says that
 * the class is understood and that a check written against it here rejects
 * what it should and nothing else.
 */

#include "negative.h"

#include <stdio.h>

int main(void)
{
    /* W11. Until then this file exists to compile, and to hold the
     * specification above where the next person to open the directory will
     * find it rather than in a planning document that is not shipped. */
    printf("negative/test_offset_length: skeleton, not implemented\n");
    printf("  see the header comment for the five assertions W11 must make\n");
    return 0;
}

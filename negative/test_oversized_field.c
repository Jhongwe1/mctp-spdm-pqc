/* negative/test_oversized_field.c - a field longer than the buffer it lands in.
 *
 * Status: SKELETON, W10. Compiles; not implemented; not in DONE.txt.
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
 * -- what W11 must assert ---------------------------------------------------
 *
 *   1. declared > bytes actually present   -> NEG_ERR_FIELD_LONGER_THAN_MESSAGE
 *   2. declared fits the message, not dest -> NEG_ERR_FIELD_LONGER_THAN_BUFFER
 *   3. exactly sizeof dest, no room for NUL-> NEG_ERR_FIELD_NOT_TERMINATED
 *   4. sizeof dest - 1                     -> NEG_OK, and dest is terminated
 *   5. declared == 0                       -> NEG_OK, dest is empty, not stale
 *
 * Cases 1 and 2 must come back as DIFFERENT codes. They are the pair that a
 * single `declared <= message_len` check collapses into one, and collapsing
 * them is the defect. Rule 13 again, and rule 16: the codes are compared, not
 * the sentences.
 *
 * Case 3 is the boundary and it is where the answer is least obvious.
 * AddressSanitizer catches the write; nothing catches a missing terminator
 * except reading the buffer afterwards, so the test must read it.
 *
 * -- and the wrong implementation -------------------------------------------
 *
 * Rule 11: the suite is run against a version that checks only
 * `declared <= message_len` and must catch it on case 2. If it does not, the
 * test is asserting that a copy happened rather than that a bound held.
 */

#include "negative.h"

#include <stdio.h>

int main(void)
{
    printf("negative/test_oversized_field: skeleton, not implemented\n");
    printf("  see the header comment for the five assertions W11 must make\n");
    return 0;
}

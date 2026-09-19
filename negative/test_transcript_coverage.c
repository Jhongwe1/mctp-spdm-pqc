/* negative/test_transcript_coverage.c - a signature over the wrong bytes.
 *
 * Status: SKELETON, W10. Compiles; not implemented; not in DONE.txt.
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
 * messages exchanged so far. For CHALLENGE_AUTH that is
 *
 *     M1M2 = A || B || C
 *       A = GET_VERSION VERSION GET_CAPABILITIES CAPABILITIES
 *           NEGOTIATE_ALGORITHMS ALGORITHMS
 *       B = the digest and certificate exchanges, if any
 *       C = CHALLENGE, and CHALLENGE_AUTH up to its signature
 *
 * If a message is accepted into the conversation and NOT appended, then an
 * attacker who changes that message changes nothing that any signature covers,
 * and every signature still verifies. The handshake completes. The verifier is
 * satisfied. And the thing it was satisfied about is not what happened.
 *
 * This project has already built the machinery for this:
 * harness/challenge_verify.py rebuilds M1M2 from a capture and hands the
 * arithmetic to OpenSSL. It was written in W10 to settle a dispute about a
 * conformance failure - docs/validator-report.md section 5 - and the
 * transcript it builds is exactly the object this test is about.
 *
 * -- what W11 must assert ---------------------------------------------------
 *
 * The test operates on a MODEL transcript, not on real crypto: a list of
 * (message, included?) pairs, a "signature" that is a digest of the included
 * bytes, and a verifier.
 *
 *   1. every message appended, in order   -> NEG_OK
 *   2. one message accepted, not appended -> NEG_ERR_TRANSCRIPT_MISSING_MESSAGE
 *   3. two messages appended out of order -> NEG_ERR_TRANSCRIPT_WRONG_ORDER
 *   4. a message appended with the wrong length (its signature bytes included,
 *      or its header excluded)            -> NEG_ERR_TRANSCRIPT_LENGTH_MISMATCH
 *
 * Case 2 is the class. Cases 3 and 4 are what stops the test from being
 * satisfied by a checksum: a verifier that hashes an unordered SET of messages
 * passes case 2 and fails case 3, and one that hashes only lengths passes both
 * and fails case 4.
 *
 * The hardest part is case 2's SETUP, not its assertion. A transcript with a
 * message missing must still be a transcript that VERIFIES - otherwise the
 * test is detecting a broken signature rather than an incomplete one, which is
 * the difference between this class and no class at all.
 *
 * -- the real-world shape, stated without an identifier ---------------------
 *
 * plan/W11 names a 2026 CVE for this class. It is not written here, and
 * negative/negative.h says why: standing rule 7. W11 fetches it from its
 * primary source, pins the retrieval the way third_party/ pins every other
 * external document, and writes it down then.
 *
 * What can be said now without any identifier: the class is a specification
 * problem rather than an implementation one, which means a correct
 * implementation of a specification that has it is still vulnerable, and no
 * amount of fuzzing the implementation finds it.
 */

#include "negative.h"

#include <stdio.h>

int main(void)
{
    printf("negative/test_transcript_coverage: skeleton, not implemented\n");
    printf("  see the header comment for the four assertions W11 must make\n");
    return 0;
}

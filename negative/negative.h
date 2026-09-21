/* negative/negative.h — the contract the three negative tests share.
 *
 * Status: IMPLEMENTED, W11. All three tests assert their cases, all three are
 * named in negative/DONE.txt, and `make test` runs them and their defect
 * variants.
 *
 * What this suite is, and what it is not
 * --------------------------------------
 * It is NOT an audit of libspdm. Reproducing the class of a published advisory
 * is not auditing an implementation for it, and this repository says so
 * wherever these results appear. libspdm is on OSS-Fuzz, has about sixty-nine
 * AFL targets and CI running CodeQL and Coverity; nothing here improves on
 * that and nothing here should be read as trying.
 *
 * It is a demonstration that three CLASSES of defect are understood well
 * enough to be written down as code, fed a malformed input, and refused --
 * with the refusal identified rather than merely counted.
 *
 * Whether THIS PROJECT'S OWN BUILDS carry the three defects is a separate
 * question, and it is answered separately and by measurement:
 * harness/check_advisories.py --exposure, and docs/advisories.md section 3.
 *
 * Why the class and not the payload
 * ---------------------------------
 * The payloads of the 2026 advisories are fixed. Rebuilding them would produce
 * three tests that pass on every version of libspdm anyone will ever run, and
 * a test that cannot fail is documentation with a build step. The classes do
 * not get patched: offset-plus-length is a shape that recurs in every message
 * that carries a window into a larger object, and SPDM has several.
 *
 * The advisory identifiers, which W10 refused to write down
 * ---------------------------------------------------------
 * W10 left them out on purpose, because docs/roadmap.md standing rule 7 --
 * nothing is cited that has not been checked against its primary source --
 * applies to a security advisory more than to anything else. W11 checked them,
 * and the check found something:
 *
 *   - All three identifiers plan/W11 named are CORRECT.
 *   - All three are REPOSITORY advisories on DMTF/libspdm. None is in GitHub's
 *     global advisory database, so https://github.com/advisories/GHSA-... --
 *     the URL a reader would try first -- returns 404 for every one of them.
 *   - Two of the three have NO CVE. DMTF-2026-0001 says why, in its own words:
 *     "due to the unlikely chance of implementation in a production device, no
 *     CVE has been issued."
 *   - The one that does have a CVE, CVE-2026-61810, was not in NVD or in
 *     MITRE's CVE Services at the time it was looked up.
 *
 * So each identifier below is pinned in third_party/, with the retrieval
 * recorded, and harness/check_advisories.py re-asserts that what this file
 * says still matches what the pins say. docs/advisories.md section 1 carries
 * the whole finding.
 *
 * Why the status codes
 * --------------------
 * docs/roadmap.md standing rule 13: two breaks caught by the same check are
 * one check. A suite that feeds a parser nine malformed messages and collects
 * nine refusals has demonstrated one check nine times if the cheapest one
 * refused them all. And rule 16: comparing refusal MESSAGES is not enough,
 * because two sentences differing only in an interpolated number compare as
 * distinct. So every refusal carries a stable code, the tests assert WHICH
 * code came back, and a refusal through the wrong door is a failure.
 *
 * This is deliberately the same contract as device/measurement_source.h's
 * ms_status_t, which exists for the same reason and was written first.
 */

#ifndef NEGATIVE_H
#define NEGATIVE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef enum {
    NEG_OK = 0,

    /* ---- class 1: a window into a larger object -------------------------
     * GET_CERTIFICATE carries Offset and Length; CHUNK_GET carries a chunk
     * sequence number; GET_MEASUREMENT_EXTENSION_LOG carries an offset and a
     * length. Every one of them is a request for bytes [off, off+len) of
     * something, and every one of them is a place where off + len is computed
     * in a type that can wrap.
     *
     * c-drills/d2_offset_length is the same arithmetic on a whiteboard. The
     * wrong answer that reads correctly in English is `off + len <= total`.
     *
     * Pinned advisory: third_party/dmtf-2026-0002.pin */
    NEG_ERR_WINDOW_OFFSET_PAST_END,
    NEG_ERR_WINDOW_LENGTH_PAST_END,
    NEG_ERR_WINDOW_SUM_OVERFLOWS,     /* off + len wrapped; the two above cannot see it */
    NEG_ERR_WINDOW_ZERO_LENGTH,

    /* ---- class 2: a field longer than the buffer it is copied into ------
     * A request carrying a variable-length field -- a CSR's subject name, an
     * opaque data blob -- whose declared length is not checked against the
     * destination before the copy.
     *
     * c-drills/d8_bounded_copy is the same problem with one buffer. The wrong
     * answers are strncpy without the terminator and strcpy with a length
     * check on the SOURCE.
     *
     * Pinned advisory: third_party/dmtf-2026-0001.pin */
    NEG_ERR_FIELD_LONGER_THAN_MESSAGE,
    NEG_ERR_FIELD_LONGER_THAN_BUFFER,
    NEG_ERR_FIELD_NOT_TERMINATED,

    /* ★ Added in W11, after reading the published fix rather than the advisory
     * summary. DMTF-2026-0001's defective code DID check the remaining space —
     * it checked it after writing, by asking whether a signed counter had gone
     * negative. The refusal it then returned was the right one. The bytes were
     * already in the buffer.
     *
     * The three codes above cannot say that: they are verdicts about a request,
     * and this is a statement about what happened to memory while the verdict
     * was being reached. So a suite that only compared status codes would have
     * passed the real defect. Rule 16 asks for a stable code per distinguishable
     * outcome; this one was distinguishable and had no door.
     *
     * negative/test_oversized_field.c returns it when the guard region after a
     * destination was overwritten AND the implementation refused — because
     * "refused and wrote anyway" is a different event from "accepted and wrote",
     * which is already visible as NEG_OK. */
    NEG_ERR_FIELD_WRITE_ESCAPED_BUFFER,

    /* ---- class 3: a transcript that does not cover what it must ---------
     * A signature is worth exactly the bytes it covers. If a message is
     * accepted into a conversation and not appended to the transcript that a
     * later signature is computed over, an attacker can change it and every
     * signature still verifies.
     *
     * This is a SPECIFICATION-level class rather than a memory-safety one, and
     * it is the only one of the three that no sanitizer would ever find.
     *
     * Pinned advisory: third_party/dmtf-2026-0003.pin
     * Pinned specifications: third_party/dsp0274.pin (1.4.0, where the defect
     * is) and third_party/dsp0274-1.4.1.pin (where it is fixed). The two
     * versions of the five definitions are in docs/transcript.md section 3. */
    NEG_ERR_TRANSCRIPT_MISSING_MESSAGE,
    NEG_ERR_TRANSCRIPT_WRONG_ORDER,
    NEG_ERR_TRANSCRIPT_LENGTH_MISMATCH
} neg_status_t;

/* Never NULL. Stable across releases: the tests compare codes, and this exists
 * for a human reading a failure. */
const char *neg_status_text(neg_status_t status);

/* ---------------------------------------------------------------------------
 * The runner, and why a negative suite needs one
 * ---------------------------------------------------------------------------
 *
 * Standing rule 11 says a check is worth what it rejects, and that something
 * has to PROVE it rejects. For a negative test that is not a formality: a
 * suite of assertions about refusals passes trivially against an
 * implementation that refuses everything, and passes almost as easily against
 * one that refuses nothing if the assertions were written by reading the
 * implementation.
 *
 * So each test here is compiled more than once. Undefined NEG_DEFECT builds
 * the implementation the file argues is correct, and every case must return
 * the code it expects. -DNEG_DEFECT=k builds a DELIBERATELY WRONG one -- the
 * specific mistake the class is about -- and the file declares, in advance,
 * exactly WHICH cases that mistake must move.
 *
 * Both halves matter and they fail for opposite reasons:
 *
 *   a defect that moves NO case          the suite cannot see the bug it
 *                                        exists to demonstrate
 *   a defect that moves MORE cases than  the cases are not discriminating;
 *   it declared                          rule 13, mechanised
 *
 * The second is the one that is easy to miss and the reason the declaration is
 * a SET rather than a count. 2026-08-31 found a redundant check in a suite
 * written to demonstrate exactly this rule, by hand. This does it every build.
 *
 * And one distinction beyond "moved"
 * ----------------------------------
 * A case that was supposed to be REFUSED and came back NEG_OK is not the same
 * event as one refused through the wrong door. The first is the vulnerability;
 * the second is a mislabelled refusal that a reader would never notice and an
 * attacker could never use.
 *
 * The suite needs the distinction because one of its own findings depends on
 * it. `off + len > total`, with no overflow check, is a different bug at
 * different field widths: at 32 bits it ACCEPTS an out-of-range window,
 * because uint32_t arithmetic wraps; at 16 bits it refuses — for the wrong
 * reason, but it refuses — because uint16_t operands are promoted to int
 * before the addition and the sum is representable there. Same expression,
 * same mistake, and only one of them is exploitable.
 *
 * So a defect declares both: every case it must move, and the subset of those
 * it must move all the way to NEG_OK. test_offset_length.c defects 1 and 2
 * differ in exactly that subset and in nothing else.
 */

typedef struct {
    const char   *name;     /* what is fed in, in a few words */
    neg_status_t  expect;   /* the code the correct implementation must return */
} neg_case_t;

typedef struct {
    const char *what;        /* the mistake, in one line */
    const int  *must_move;   /* case indices, terminated by -1 */
    const int  *must_accept; /* the subset of those that must come back NEG_OK */
} neg_defect_t;

/* neg_report — compare what came back against what was expected, print it, and
 * return the process exit status.
 *
 * defect_id is 0 for the correct build and k for -DNEG_DEFECT=k. In both cases
 * the return is 0 when the build behaved as the file says it must, so `make
 * test` runs every binary the same way and does not have to know which is
 * which. What "as it must" means is different in the two directions, and the
 * printed report says which one it is checking.
 */
int neg_report(const char *suite,
               const char *class_name,
               const neg_case_t *cases,
               const neg_status_t *got,
               size_t ncases,
               int defect_id,
               const neg_defect_t *defects,
               size_t ndefects);

/* --defects and --list, so the Makefile does not have to be told how many
 * defect variants a file has or what its cases are called. A number kept in
 * two places is a number that drifts; this repository has caught that four
 * times, and the fix each time was to keep it in one.
 *
 * Returns 1 if it handled the argument and the caller should exit 0, and 0 if
 * the caller should go on and run the suite. */
int neg_handled_args(int argc, char **argv,
                     const neg_case_t *cases, size_t ncases,
                     const neg_defect_t *defects, size_t ndefects);

#endif /* NEGATIVE_H */

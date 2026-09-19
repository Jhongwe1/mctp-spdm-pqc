/* negative/negative.h — the contract the three negative tests share.
 *
 * Status: SKELETON. Written 2026-10-12, to be implemented in W11. Nothing in
 * negative/DONE.txt, so `make test` runs none of it and claims none of it.
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
 * Why the class and not the payload
 * ---------------------------------
 * The payloads of the 2026 advisories are fixed. Rebuilding them would produce
 * three tests that pass on every version of libspdm anyone will ever run, and
 * a test that cannot fail is documentation with a build step. The classes do
 * not get patched: offset-plus-length is a shape that recurs in every message
 * that carries a window into a larger object, and SPDM has several.
 *
 * ! ADVISORY IDENTIFIERS ARE DELIBERATELY ABSENT FROM THIS FILE.
 *   plan/W11 names four of them. None has been checked against its primary
 *   source from this machine, and docs/roadmap.md standing rule 7 -- nothing
 *   is cited that has not been checked -- applies to a security advisory more
 *   than to anything else, because a wrong identifier attached to a real class
 *   is worse than no identifier: it invites a reader to look it up and find
 *   something else. W11 fetches them from the GitHub Security Advisory
 *   database and the CVE record, records the retrieval in
 *   third_party/ pin files the way every other external document here is recorded,
 *   and only then writes them down.
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
     * wrong answer that reads correctly in English is `off + len <= total`. */
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
     * check on the SOURCE. */
    NEG_ERR_FIELD_LONGER_THAN_MESSAGE,
    NEG_ERR_FIELD_LONGER_THAN_BUFFER,
    NEG_ERR_FIELD_NOT_TERMINATED,

    /* ---- class 3: a transcript that does not cover what it must ---------
     * A signature is worth exactly the bytes it covers. If a message is
     * accepted into a conversation and not appended to the transcript that a
     * later signature is computed over, an attacker can change it and every
     * signature still verifies.
     *
     * This is a SPECIFICATION-level class rather than a memory-safety one, and
     * it is the only one of the three that no sanitizer would ever find. */
    NEG_ERR_TRANSCRIPT_MISSING_MESSAGE,
    NEG_ERR_TRANSCRIPT_WRONG_ORDER,
    NEG_ERR_TRANSCRIPT_LENGTH_MISMATCH
} neg_status_t;

/* Never NULL. Stable across releases: the tests compare codes, and this exists
 * for a human reading a failure. */
const char *neg_status_text(neg_status_t status);

#endif /* NEGATIVE_H */

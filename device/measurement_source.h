/* device/measurement_source.h — where a measurement value comes from.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 * Part of https://github.com/Jhongwe1/mctp-spdm-pqc — original work, not DMTF's.
 *
 * What this is for
 * ----------------
 * libspdm's sample device-secret library invents its measurements. Index 1
 * through 4 are the SHA-512 of a 72-byte buffer filled with the index itself,
 * and the secure version number is the constant 0x7. That is entirely correct
 * for sample code, and it makes two experiments impossible:
 *
 *   * a tamper test needs a measurement whose bytes can be changed by one bit;
 *   * a version-rollback policy needs more than one version number to exist,
 *     or the rule `evidence_svn >= reference_svn` is only ever fed one input
 *     and has never actually been tested.
 *
 * So this module supplies the values, and NOTHING ELSE. It does not hash, it
 * does not assemble measurement blocks, it does not sign, and it does not know
 * what SPDM is. Upstream keeps all of that. Two added lines in meas.c ask this
 * module whether it has an opinion, and use upstream's own value when it does
 * not. That boundary is the point: what the captures measure stays upstream's
 * behaviour rather than becoming this project's.
 *
 * How it is turned on
 * -------------------
 * The environment variable SPDM_MEASUREMENTS_FILE names a file. When it is
 * unset, no file is opened, nothing is allocated, every accessor returns false
 * and the emulator behaves exactly as the unpatched build does — which is a
 * claim harness/tamper.sh checks against a capture rather than asserts.
 *
 * The file format (all integers little-endian, as on the SPDM wire)
 * ----------------------------------------------------------------
 *      offset  size  field
 *      0       4     magic          "MSR1"  (4d 53 52 31)
 *      4       2     format_version 1
 *      6       2     block_count
 *      8       8     svn            SPDM SECURE_VERSION_NUMBER, index 0x10
 *      16      8*n   descriptors, one per block:
 *                        +0  u8   index      SPDM measurement index, 1..0xfe
 *                        +1  u8   reserved   must be zero
 *                        +2  u16  length     bytes of value
 *                        +4  u32  offset     absolute offset into this file
 *      ...           payload, addressed by the descriptors
 *
 * The secure version number is a header field rather than a block because that
 * is what it is on the wire: spdm_measurements_secure_version_number_t is a
 * uint64_t scalar, not a buffer, and libspdm_fill_measurement_svn_block
 * assigns rather than copies it. It also puts the single most-edited value in
 * the file at a fixed offset a person can find in a hex dump: byte 8.
 *
 * There is deliberately no checksum over this file
 * ------------------------------------------------
 * A digest here would detect the byte flip that tamper point 1 exists to
 * perform, and would detect it in the wrong layer — inside the device, before
 * anything reached the wire. The whole question this project asks is which
 * layer notices. Integrity of the fixture is handled out of band instead: the
 * run's manifest.json records the SHA-256 of the exact file the responder
 * read, so which bytes went in is always recoverable and never enforced.
 *
 * Why the parser is strict anyway
 * -------------------------------
 * This file is local configuration, not untrusted input. The strictness is not
 * defence against an attacker; it is defence against a silent misparse, and
 * the reason is specific: a fixture that is quietly misread produces a wrong
 * measurement, and in a tamper experiment a wrong measurement is
 * indistinguishable from a successful tamper. The independent variable IS
 * "which bytes went in", so this module must never guess. Every rejection has
 * its own reason code, and measurement_source_test.c requires each of them to
 * be the one that actually fires.
 *
 * Threading: none. libspdm's sample secret library is already single-threaded
 * (it keeps m_libspdm_mel in a global), and this module matches it rather than
 * pretending to be safer than the code it is compiled into.
 */

#ifndef DEVICE_MEASUREMENT_SOURCE_H
#define DEVICE_MEASUREMENT_SOURCE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* Refused above this size. A measurement fixture is kilobytes; anything larger
 * is a mistake, and a bound means the loader needs no allocator at all. */
#define MS_MAX_FILE_BYTES 65536u

#define MS_MAGIC_0 'M'
#define MS_MAGIC_1 'S'
#define MS_MAGIC_2 'R'
#define MS_MAGIC_3 '1'

#define MS_FORMAT_VERSION 1u
#define MS_HEADER_BYTES 16u
#define MS_DESCRIPTOR_BYTES 8u

/* The environment variable that turns this module on. Unset means the emulator
 * runs upstream's path and never opens a file. */
#define MS_ENV_PATH "SPDM_MEASUREMENTS_FILE"

/* Why every failure has its own code, rather than one false:
 *
 * docs/roadmap.md standing rule 13 — two breaks caught by the same check are
 * one check. A suite that feeds this loader eleven malformed files and gets
 * eleven refusals has proved nothing if the cheapest check refused all eleven;
 * ten of them would still be untested. The tests assert WHICH code came back,
 * so a refusal that arrives through the wrong door is a failure. */
typedef enum {
    MS_OK = 0,
    MS_NO_SOURCE,            /* no path configured — not an error */
    MS_ERR_OPEN,             /* named, but could not be read */
    MS_ERR_TOO_LARGE,        /* > MS_MAX_FILE_BYTES */
    MS_ERR_HEADER_SHORT,     /* fewer than MS_HEADER_BYTES bytes */
    MS_ERR_MAGIC,
    MS_ERR_VERSION,
    MS_ERR_TABLE_SHORT,      /* header promises more descriptors than exist */
    MS_ERR_DESC_RESERVED,    /* reserved byte not zero */
    MS_ERR_DESC_INDEX,       /* 0 and 0xff are not measurement indices */
    MS_ERR_DESC_DUPLICATE,   /* two descriptors claiming one index */
    MS_ERR_DESC_OFFSET,      /* payload starts past the end of the file */
    MS_ERR_DESC_LENGTH,      /* payload starts inside but ends past the end */
    MS_ERR_DESC_IN_TABLE     /* payload overlaps the header or the table */
} ms_status_t;

/* Load path, replacing anything already loaded. A failed load leaves nothing
 * loaded: there is no half-parsed state, so a caller cannot read a value out
 * of a file the loader rejected.
 *
 * path may be NULL, which means "no source" and is not a failure. */
bool ms_load(const char *path);

/* Forget everything, as though nothing had ever been loaded. Exists for the
 * tests, which need many loads in one process; the emulator calls it never. */
void ms_reset(void);

/* Why the most recent load attempt (explicit or the implicit one from the
 * environment) answered as it did. The read accessors never change it: one
 * meaning per function, and no hidden global write on a read path. */
ms_status_t ms_last_status(void);

/* A short, stable, human-readable form of a status. Never NULL. */
const char *ms_status_text(ms_status_t status);

/* Copy the value stored for index into out.
 *
 * Returns true only when a block with that index exists AND its stored length
 * is exactly out_len. On false, out IS NOT WRITTEN — not partially, not at
 * all. meas.c depends on that: it lets upstream's own line fill the buffer
 * first and then offers this module the chance to override it, so a refusal
 * has to leave upstream's bytes intact.
 *
 * The length must match exactly rather than merely fit. A shorter value would
 * still be legal SPDM but would change MeasurementRecordLength on the wire,
 * and then a capture would differ from its control in two things instead of
 * one. Holding every length constant is what makes the value bytes the only
 * variable. */
bool ms_get_block(uint8_t index, void *out, size_t out_len);

/* Write the configured secure version number to *out. Returns false, and
 * leaves *out alone, when no file is loaded. */
bool ms_get_svn(uint64_t *out);

/* True when a file is loaded, with *count set to how many blocks it holds.
 * count may be NULL. For diagnostics and for the tests. */
bool ms_loaded(size_t *count);

/* Is [off, off+len) inside [0, total)?
 *
 * Public because it cannot be tested properly from the outside. The arithmetic
 * is deliberately uint32_t — the width the FILE FORMAT declares its offsets in
 * — and not size_t, which is the width this host happens to have. Written the
 * obvious way, off + len <= total, the sum wraps for large off and the check
 * passes on a range that is nowhere near inside the file. On this x86-64 host
 * a size_t version of the same mistake could not wrap and the bug would be
 * invisible; on the 32-bit BMC this code is meant to resemble it is a live
 * out-of-bounds read. So the check is done in the format's width, where the
 * failure is reachable and testable everywhere.
 *
 * This is GHSA-m4wc-xmvg-369f's shape, and c-drills/d2 is the same arithmetic
 * on paper. */
bool ms_range_ok(uint32_t off, uint32_t len, uint32_t total);

#endif /* DEVICE_MEASUREMENT_SOURCE_H */

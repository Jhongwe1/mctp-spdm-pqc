/* device/measurement_source.c — see measurement_source.h for the format and
 * for why this module does so little.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 * Part of https://github.com/Jhongwe1/mctp-spdm-pqc — original work, not DMTF's.
 *
 * Depends on nothing but the C standard library. That is deliberate: it is
 * what lets the same source file be compiled into libspdm's sample device
 * secret library AND compiled on its own by device/Makefile under two
 * sanitizers, with no build tree present. A module that can only be tested
 * inside a thirty-minute build is a module that stops being tested.
 */

#include "measurement_source.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ---------------------------------------------------------------- state --
 *
 * There are 254 legal SPDM measurement indices (1..0xfe; 0 is reserved and
 * 0xff means "all"), and duplicates are refused, so a file can never describe
 * more blocks than this array has room for. The bound is derived from the
 * protocol rather than picked, which is why there is no "too many blocks"
 * error code: the condition cannot arise without first being either an illegal
 * index or a duplicate, and both of those have codes of their own.
 */
typedef struct {
    bool present;
    uint16_t len;
    uint32_t off;
} ms_slot_t;

/* One byte past the cap, so a file of exactly MS_MAX_FILE_BYTES + 1 can be
 * read far enough to know it is too large. */
static uint8_t s_image[MS_MAX_FILE_BYTES + 1u];
static uint32_t s_image_len;

static ms_slot_t s_slot[256];
static uint64_t s_svn;
static size_t s_blocks;

static bool s_attempted;      /* the implicit env-var load has been tried */
static bool s_loaded;
static ms_status_t s_status = MS_NO_SOURCE;

/* ------------------------------------------------------- little-endian ----
 *
 * Read byte by byte rather than casting the buffer to a struct. Two reasons,
 * and both of them have bitten real firmware: a cast assumes the host's
 * endianness matches the file's, and it assumes the buffer is aligned for the
 * type. Neither holds in general, and on the targets this code resembles the
 * second one is a fault rather than a slowdown.
 */
static uint16_t rd16(const uint8_t *p)
{
    return (uint16_t)((uint16_t)p[0] | ((uint16_t)p[1] << 8));
}

static uint32_t rd32(const uint8_t *p)
{
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) |
           ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static uint64_t rd64(const uint8_t *p)
{
    return (uint64_t)rd32(p) | ((uint64_t)rd32(p + 4) << 32);
}

/* --------------------------------------------------------------- bounds --- */

bool ms_range_ok(uint32_t off, uint32_t len, uint32_t total)
{
    /* NOT `off + len <= total`. In uint32 that sum wraps, and a descriptor
     * claiming offset 0xfffffff8 length 16 would pass a check on a 100-byte
     * file. Subtraction cannot wrap once the first clause holds, because then
     * total >= off. */
    return off <= total && len <= total - off;
}

/* --------------------------------------------------------------- status --- */

static bool fail(ms_status_t status, const char *path)
{
    s_loaded = false;
    s_blocks = 0;
    s_image_len = 0;
    s_status = status;

    /* Say so on stderr, which for the emulator is the run's committed .rsp.log.
     *
     * Falling back to upstream's synthetic values silently would be the worst
     * possible behaviour here: a tamper run whose fixture failed to load would
     * produce upstream's own measurements, the handshake would look normal,
     * and the experiment would report "no effect" for a fixture that was never
     * read. harness/tamper.sh greps for this prefix and fails the run. */
    if (status != MS_NO_SOURCE) {
        fprintf(stderr, "measurement_source: %s: %s\n",
                path != NULL ? path : "(null)", ms_status_text(status));
        fflush(stderr);
    }
    return false;
}

ms_status_t ms_last_status(void)
{
    return s_status;
}

const char *ms_status_text(ms_status_t status)
{
    switch (status) {
    case MS_OK:                return "ok";
    case MS_NO_SOURCE:         return "no source configured";
    case MS_ERR_OPEN:          return "cannot read file";
    case MS_ERR_TOO_LARGE:     return "file larger than the 65536-byte cap";
    case MS_ERR_HEADER_SHORT:  return "shorter than the 16-byte header";
    case MS_ERR_MAGIC:         return "bad magic, expected MSR1";
    case MS_ERR_VERSION:       return "unsupported format version";
    case MS_ERR_TABLE_SHORT:   return "descriptor table runs past end of file";
    case MS_ERR_DESC_RESERVED: return "descriptor reserved byte is not zero";
    case MS_ERR_DESC_INDEX:    return "descriptor index 0 or 0xff is not a measurement index";
    case MS_ERR_DESC_DUPLICATE: return "two descriptors claim the same index";
    case MS_ERR_DESC_OFFSET:   return "descriptor offset is past end of file";
    case MS_ERR_DESC_LENGTH:   return "descriptor value runs past end of file";
    case MS_ERR_DESC_IN_TABLE: return "descriptor value overlaps the header or table";
    }
    return "unknown status";
}

/* ----------------------------------------------------------------- load --- */

void ms_reset(void)
{
    memset(s_slot, 0, sizeof(s_slot));
    s_image_len = 0;
    s_svn = 0;
    s_blocks = 0;
    s_attempted = false;
    s_loaded = false;
    s_status = MS_NO_SOURCE;
}

bool ms_load(const char *path)
{
    FILE *f;
    size_t n;
    int read_error;
    uint32_t count;
    uint32_t table_end;
    uint32_t i;

    ms_reset();
    s_attempted = true;

    /* An unset variable and an empty one mean the same thing and are both
     * normal. `SPDM_MEASUREMENTS_FILE=` in a shell script is a way of turning
     * the override off, and reporting it as a failed open would be noise. */
    if (path == NULL || path[0] == '\0') {
        s_status = MS_NO_SOURCE;
        return false;
    }

    f = fopen(path, "rb");
    if (f == NULL) {
        return fail(MS_ERR_OPEN, path);
    }

    /* Read one byte more than the cap. A full buffer therefore means "at least
     * one byte too many" without needing fseek/ftell, whose behaviour on
     * binary streams is not something to build a size check on. */
    n = fread(s_image, 1, sizeof(s_image), f);
    read_error = ferror(f);
    (void)fclose(f);

    if (read_error != 0) {
        return fail(MS_ERR_OPEN, path);
    }
    if (n > MS_MAX_FILE_BYTES) {
        return fail(MS_ERR_TOO_LARGE, path);
    }
    if (n < MS_HEADER_BYTES) {
        return fail(MS_ERR_HEADER_SHORT, path);
    }

    s_image_len = (uint32_t)n;

    if (s_image[0] != MS_MAGIC_0 || s_image[1] != MS_MAGIC_1 ||
        s_image[2] != MS_MAGIC_2 || s_image[3] != MS_MAGIC_3) {
        return fail(MS_ERR_MAGIC, path);
    }
    if (rd16(s_image + 4) != MS_FORMAT_VERSION) {
        return fail(MS_ERR_VERSION, path);
    }

    count = rd16(s_image + 6);
    s_svn = rd64(s_image + 8);

    /* count is at most 65535 and each descriptor is 8 bytes, so this is at
     * most 524296 and cannot overflow uint32. Stated rather than assumed,
     * because it is the arithmetic the check below depends on. */
    table_end = MS_HEADER_BYTES + count * MS_DESCRIPTOR_BYTES;
    if (table_end > s_image_len) {
        return fail(MS_ERR_TABLE_SHORT, path);
    }

    for (i = 0; i < count; i++) {
        const uint8_t *d = s_image + MS_HEADER_BYTES + i * MS_DESCRIPTOR_BYTES;
        uint8_t index = d[0];
        uint8_t reserved = d[1];
        uint16_t len = rd16(d + 2);
        uint32_t off = rd32(d + 4);

        if (reserved != 0u) {
            return fail(MS_ERR_DESC_RESERVED, path);
        }
        if (index == 0u || index == 0xffu) {
            return fail(MS_ERR_DESC_INDEX, path);
        }
        if (s_slot[index].present) {
            return fail(MS_ERR_DESC_DUPLICATE, path);
        }
        if (!ms_range_ok(off, len, s_image_len)) {
            /* Two different faults, and they are told apart here rather than
             * inside the predicate: a start outside the file is a different
             * mistake from a start inside it and an end outside. Reporting
             * both as one code would leave one of them never observed. */
            return fail(off > s_image_len ? MS_ERR_DESC_OFFSET
                                          : MS_ERR_DESC_LENGTH, path);
        }
        /* A zero-length value is permitted and describes nothing; it cannot be
         * returned by ms_get_block, whose caller always asks for a fixed size.
         * Only a value that actually occupies bytes can overlap the table. */
        if (len > 0u && off < table_end) {
            return fail(MS_ERR_DESC_IN_TABLE, path);
        }

        s_slot[index].present = true;
        s_slot[index].len = len;
        s_slot[index].off = off;
        s_blocks++;
    }

    s_loaded = true;
    s_status = MS_OK;

    /* Confirm on stderr, once, that the fixture was read and what it says.
     *
     * This is the positive half of the rule above: harness/tamper.sh asserts
     * that this line is present with the svn it configured, so "the responder
     * used my file" is read back out of the responder's own log rather than
     * inferred from the fact that a variable was exported. Every other
     * independent variable in this repository is confirmed from the far side;
     * this one is no different. */
    fprintf(stderr, "measurement_source: loaded %s (%u bytes, %u blocks, svn=%llu)\n",
            path, (unsigned)s_image_len, (unsigned)s_blocks,
            (unsigned long long)s_svn);
    fflush(stderr);

    return true;
}

/* Load from the environment on first use, exactly once, whatever the outcome.
 *
 * Lazily rather than from an initialiser because meas.c must not grow a call
 * to it: the whole argument of this change is that two added lines in upstream
 * ask a question, and everything else is on this side of the boundary. A
 * failed or absent load is remembered so a missing file is not reopened once
 * per measurement block. */
static void ms_ensure(void)
{
    if (s_attempted) {
        return;
    }
    (void)ms_load(getenv(MS_ENV_PATH));
}

/* ---------------------------------------------------------------- reads --- */

bool ms_loaded(size_t *count)
{
    ms_ensure();
    if (count != NULL) {
        *count = s_loaded ? s_blocks : 0u;
    }
    return s_loaded;
}

bool ms_get_block(uint8_t index, void *out, size_t out_len)
{
    ms_ensure();

    if (!s_loaded || out == NULL) {
        return false;
    }
    if (!s_slot[index].present) {
        return false;
    }
    /* Exactly, not at least. See the header for why a shorter value would make
     * the capture differ from its control in two things instead of one. */
    if ((size_t)s_slot[index].len != out_len) {
        return false;
    }
    /* Re-checked at the point of use even though the loader already refused
     * anything out of range. The cost is two comparisons; what it buys is that
     * this copy is correct on its own terms rather than on the strength of a
     * proof somewhere else in the file. */
    if (!ms_range_ok(s_slot[index].off, s_slot[index].len, s_image_len)) {
        return false;
    }

    memcpy(out, s_image + s_slot[index].off, out_len);
    return true;
}

bool ms_get_svn(uint64_t *out)
{
    ms_ensure();

    if (!s_loaded || out == NULL) {
        return false;
    }
    *out = s_svn;
    return true;
}

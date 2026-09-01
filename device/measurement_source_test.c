/* device/measurement_source_test.c — the companion that proves the loader
 * rejects, and rejects for the right reason.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 *
 *     make -C device test        # -Werror, AddressSanitizer, UBSan
 *
 * What this is checking, and why it is shaped like this
 * -----------------------------------------------------
 * docs/roadmap.md standing rule 11: a check is worth what it rejects, and
 * something has to prove it rejects. Rule 13: two breaks caught by the same
 * check are one check. Rule 15: a test whose failure mode cannot occur teaches
 * a superstition.
 *
 * So this file does three things that a normal unit test does not:
 *
 *   1. Every malformed fixture asserts WHICH status came back, not merely that
 *      the load failed. A file with a bad magic that is refused for being too
 *      short would pass a boolean test and would mean the magic check has
 *      never run.
 *
 *   2. At the end it asserts that every value of ms_status_t was observed at
 *      least once. Adding an error code without a case that provokes it is a
 *      failing build. That is the coverage claim stated as a mechanism instead
 *      of as a habit.
 *
 *   3. The bounds predicate is tested at its own door, side by side with the
 *      wrong version of itself. `off + len <= total` is shown ACCEPTING a
 *      descriptor that points nowhere near the file, so the test demonstrates
 *      the bug rather than asserting the absence of it.
 *
 * Depends on the C standard library plus setenv/unsetenv. Nothing else — no
 * framework, no libspdm, no build tree.
 */

#define _POSIX_C_SOURCE 200809L

#include "measurement_source.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ------------------------------------------------------------ harness ----- */

static int g_checks;
static int g_failures;
static bool g_seen_status[16];

static void check(bool ok, const char *what)
{
    g_checks++;
    if (ok) {
        printf("  ok    %s\n", what);
    } else {
        g_failures++;
        printf("  FAIL  %s\n", what);
    }
}

/* Record every status the module ever reports, so the coverage assertion at
 * the end can insist that each one was reached by something. */
static void note_status(ms_status_t s)
{
    if ((size_t)s < sizeof(g_seen_status) / sizeof(g_seen_status[0])) {
        g_seen_status[(size_t)s] = true;
    }
}

/* --------------------------------------------------------- image builder -- */

#define IMG_CAP 4096u

typedef struct {
    uint8_t b[IMG_CAP];
    uint32_t len;
} img_t;

static void put16(uint8_t *p, uint16_t v)
{
    p[0] = (uint8_t)(v & 0xffu);
    p[1] = (uint8_t)((v >> 8) & 0xffu);
}

static void put32(uint8_t *p, uint32_t v)
{
    p[0] = (uint8_t)(v & 0xffu);
    p[1] = (uint8_t)((v >> 8) & 0xffu);
    p[2] = (uint8_t)((v >> 16) & 0xffu);
    p[3] = (uint8_t)((v >> 24) & 0xffu);
}

static void put64(uint8_t *p, uint64_t v)
{
    put32(p, (uint32_t)(v & 0xffffffffu));
    put32(p + 4, (uint32_t)(v >> 32));
}

/* The canonical fixture: four blocks of 72 bytes, block i filled with the byte
 * i, and svn 7.
 *
 * Those are not arbitrary numbers. They are exactly what libspdm's sample
 * secret library synthesises — `libspdm_set_mem(data, 72, measurements_index)`
 * and `svn = 0x7` — which makes this fixture the one whose presence must not
 * change a single byte on the wire. device/gen_measurements.py writes the same
 * file, and `make -C device interop` requires the two to agree byte for byte:
 * a format with two implementations that were never compared is a format with
 * one implementation and a hope. */
#define VALUE_BYTES 72u
#define HASH_BLOCKS 4u

static void img_valid(img_t *m)
{
    uint32_t table = MS_HEADER_BYTES + HASH_BLOCKS * MS_DESCRIPTOR_BYTES;
    uint32_t i;

    memset(m, 0, sizeof(*m));

    m->b[0] = MS_MAGIC_0;
    m->b[1] = MS_MAGIC_1;
    m->b[2] = MS_MAGIC_2;
    m->b[3] = MS_MAGIC_3;
    put16(m->b + 4, (uint16_t)MS_FORMAT_VERSION);
    put16(m->b + 6, (uint16_t)HASH_BLOCKS);
    put64(m->b + 8, 7u);

    for (i = 0; i < HASH_BLOCKS; i++) {
        uint8_t *d = m->b + MS_HEADER_BYTES + i * MS_DESCRIPTOR_BYTES;
        uint32_t off = table + i * VALUE_BYTES;
        d[0] = (uint8_t)(i + 1u);
        d[1] = 0u;
        put16(d + 2, (uint16_t)VALUE_BYTES);
        put32(d + 4, off);
        memset(m->b + off, (int)(i + 1u), VALUE_BYTES);
    }

    m->len = table + HASH_BLOCKS * VALUE_BYTES;
}

/* A descriptor by ordinal, for the mutators below. */
static uint8_t *desc(img_t *m, uint32_t i)
{
    return m->b + MS_HEADER_BYTES + i * MS_DESCRIPTOR_BYTES;
}

/* ------------------------------------------------------------- file I/O --- */

static const char *g_dir = ".";
static char g_path[512];

static const char *scratch_path(void)
{
    snprintf(g_path, sizeof(g_path), "%s/.ms_case.bin", g_dir);
    return g_path;
}

/* Write `m` to `path`, then pad with zero bytes to `pad_to` if that is larger.
 * Padding is how the oversize case is built without a 64 KiB image_t on the
 * stack. */
static bool write_image_to(const char *path, const img_t *m, uint32_t pad_to)
{
    FILE *f = fopen(path, "wb");
    uint32_t written;
    if (f == NULL) {
        return false;
    }
    if (m->len > 0u && fwrite(m->b, 1, m->len, f) != m->len) {
        (void)fclose(f);
        return false;
    }
    for (written = m->len; written < pad_to; written++) {
        if (fputc(0, f) == EOF) {
            (void)fclose(f);
            return false;
        }
    }
    return fclose(f) == 0;
}

static bool write_image(const img_t *m, uint32_t pad_to)
{
    return write_image_to(scratch_path(), m, pad_to);
}

/* Write the image, load it, and require a specific status. */
static void expect_status(const img_t *m, uint32_t pad_to,
                          ms_status_t want, const char *what)
{
    char msg[256];
    ms_status_t got;

    if (!write_image(m, pad_to)) {
        check(false, "could not write the scratch fixture");
        return;
    }
    (void)ms_load(scratch_path());
    got = ms_last_status();
    note_status(got);

    snprintf(msg, sizeof(msg), "%-28s -> %s", what, ms_status_text(got));
    check(got == want, msg);
    if (got != want) {
        printf("        wanted %s\n", ms_status_text(want));
    }
}

/* ------------------------------------------------------ bounds predicate -- */

/* The mistake this project is trying not to make, written out so the test can
 * watch it fail. Kept in the test rather than the module so there is no chance
 * of calling it by accident. */
static bool range_naive(uint32_t off, uint32_t len, uint32_t total)
{
    return (uint32_t)(off + len) <= total;
}

static void test_range(void)
{
    struct { uint32_t off, len, total; bool want; } cases[] = {
        { 0u,          0u,   0u,   true  },
        { 0u,          1u,   0u,   false },
        { 0u,          100u, 100u, true  },
        { 1u,          100u, 100u, false },
        { 100u,        0u,   100u, true  },   /* empty range at the very end */
        { 101u,        0u,   100u, false },   /* empty range past the end */
        { 50u,         50u,  100u, true  },
        { 50u,         51u,  100u, false },
        { 0xfffffff8u, 16u,  100u, false },   /* the wrap */
        { 0xffffffffu, 1u,   100u, false },
    };
    size_t i;
    char msg[128];

    printf("\n-- bounds predicate --\n");
    for (i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        bool got = ms_range_ok(cases[i].off, cases[i].len, cases[i].total);
        snprintf(msg, sizeof(msg), "ms_range_ok(%u, %u, %u) == %s",
                 cases[i].off, cases[i].len, cases[i].total,
                 cases[i].want ? "true" : "false");
        check(got == cases[i].want, msg);
    }

    /* The demonstration. If this ever stops holding, the drill it teaches has
     * stopped being a real bug and the comment in the header is wrong. */
    check(range_naive(0xfffffff8u, 16u, 100u),
          "off + len <= total ACCEPTS offset 0xfffffff8 length 16 in 100 bytes");
    check(!ms_range_ok(0xfffffff8u, 16u, 100u),
          "off <= total && len <= total - off refuses it");
}

/* ------------------------------------------------------------- the tests -- */

static void test_valid(void)
{
    img_t m;
    uint8_t out[VALUE_BYTES];
    uint8_t expect[VALUE_BYTES];
    uint64_t svn = 0;
    size_t blocks = 0;

    printf("\n-- a fixture that is correct --\n");
    img_valid(&m);
    expect_status(&m, 0u, MS_OK, "four blocks, svn 7");

    check(ms_loaded(&blocks) && blocks == HASH_BLOCKS, "reports four blocks");
    check(ms_get_svn(&svn) && svn == 7u, "svn reads back as 7");

    memset(expect, 2, sizeof(expect));
    memset(out, 0xaa, sizeof(out));
    check(ms_get_block(2u, out, sizeof(out)), "block 2 is present");
    check(memcmp(out, expect, sizeof(out)) == 0, "block 2 holds 72 bytes of 0x02");

    /* Exactly, not at least — and on refusal the buffer must be untouched,
     * because meas.c relies on upstream's own bytes surviving a refusal. */
    memset(out, 0xaa, sizeof(out));
    check(!ms_get_block(2u, out, sizeof(out) - 1u), "a shorter request is refused");
    check(out[0] == 0xaa && out[sizeof(out) - 1u] == 0xaa,
          "a refused short request leaves the buffer untouched");

    memset(out, 0xaa, sizeof(out));
    check(!ms_get_block(2u, out, sizeof(out) + 1u), "a longer request is refused");
    check(out[0] == 0xaa, "a refused long request leaves the buffer untouched");

    memset(out, 0xaa, sizeof(out));
    check(!ms_get_block(9u, out, sizeof(out)), "an absent index is refused");
    check(out[0] == 0xaa, "a refused absent index leaves the buffer untouched");

    check(!ms_get_block(2u, NULL, sizeof(out)), "a NULL destination is refused");
    check(!ms_get_svn(NULL), "a NULL svn destination is refused");
}

static void test_no_source(void)
{
    uint64_t svn = 0xdeadbeefu;
    uint8_t out[VALUE_BYTES];

    printf("\n-- no source configured --\n");

    ms_load(NULL);
    note_status(ms_last_status());
    check(ms_last_status() == MS_NO_SOURCE, "a NULL path is 'no source', not an error");
    check(!ms_loaded(NULL), "nothing is loaded");
    check(!ms_get_svn(&svn) && svn == 0xdeadbeefu,
          "ms_get_svn leaves its destination alone");
    memset(out, 0x5a, sizeof(out));
    check(!ms_get_block(1u, out, sizeof(out)) && out[0] == 0x5a,
          "ms_get_block leaves its destination alone");

    ms_load("");
    note_status(ms_last_status());
    check(ms_last_status() == MS_NO_SOURCE,
          "an empty path is 'no source' too — SPDM_MEASUREMENTS_FILE= turns it off");

    ms_load("./this-file-does-not-exist-and-must-not.bin");
    note_status(ms_last_status());
    check(ms_last_status() == MS_ERR_OPEN, "a named but missing file IS an error");
}

static void test_rejections(void)
{
    img_t m;

    printf("\n-- eleven ways to be wrong, and eleven different refusals --\n");

    /* Larger than the cap. Otherwise a perfectly good file, so nothing else
     * can be the reason it is refused. */
    img_valid(&m);
    expect_status(&m, MS_MAX_FILE_BYTES + 1u, MS_ERR_TOO_LARGE, "65537 bytes");

    img_valid(&m);
    m.len = MS_HEADER_BYTES - 1u;
    expect_status(&m, 0u, MS_ERR_HEADER_SHORT, "15 bytes");

    img_valid(&m);
    m.b[2] = 'X';
    expect_status(&m, 0u, MS_ERR_MAGIC, "magic MSX1");

    img_valid(&m);
    put16(m.b + 4, (uint16_t)(MS_FORMAT_VERSION + 1u));
    expect_status(&m, 0u, MS_ERR_VERSION, "format version 2");

    img_valid(&m);
    put16(m.b + 6, (uint16_t)(HASH_BLOCKS + 1u));
    m.len = MS_HEADER_BYTES + HASH_BLOCKS * MS_DESCRIPTOR_BYTES;
    expect_status(&m, 0u, MS_ERR_TABLE_SHORT, "5 blocks, room for 4");

    img_valid(&m);
    desc(&m, 1u)[1] = 1u;
    expect_status(&m, 0u, MS_ERR_DESC_RESERVED, "reserved byte set");

    img_valid(&m);
    desc(&m, 1u)[0] = 0u;
    expect_status(&m, 0u, MS_ERR_DESC_INDEX, "index 0");

    img_valid(&m);
    desc(&m, 1u)[0] = 0xffu;
    expect_status(&m, 0u, MS_ERR_DESC_INDEX, "index 0xff");

    img_valid(&m);
    desc(&m, 2u)[0] = desc(&m, 1u)[0];
    expect_status(&m, 0u, MS_ERR_DESC_DUPLICATE, "index 2 twice");

    /* The wrap, reached through the front door. A loader using the naive
     * predicate accepts this descriptor and then reads 16 bytes from
     * s_image + 0xfffffff8. */
    img_valid(&m);
    put32(desc(&m, 1u) + 4, 0xfffffff8u);
    put16(desc(&m, 1u) + 2, 16u);
    expect_status(&m, 0u, MS_ERR_DESC_OFFSET, "offset 0xfffffff8");

    img_valid(&m);
    put16(desc(&m, 1u) + 2, 0xffffu);
    expect_status(&m, 0u, MS_ERR_DESC_LENGTH, "length 65535 inside a small file");

    img_valid(&m);
    put32(desc(&m, 1u) + 4, 10u);
    expect_status(&m, 0u, MS_ERR_DESC_IN_TABLE, "value at offset 10");
}

static void test_no_half_state(void)
{
    img_t m;
    uint64_t svn = 0;
    uint8_t out[VALUE_BYTES];

    printf("\n-- a refused file leaves nothing behind --\n");

    img_valid(&m);
    expect_status(&m, 0u, MS_OK, "load a good file first");
    check(ms_get_svn(&svn) && svn == 7u, "svn is readable");

    /* Now break the fourth descriptor. The first three are perfectly valid and
     * were parsed before the failure; none of them may survive it. */
    img_valid(&m);
    desc(&m, 3u)[1] = 1u;
    expect_status(&m, 0u, MS_ERR_DESC_RESERVED, "fourth descriptor is bad");

    svn = 0xabcdu;
    check(!ms_loaded(NULL), "nothing is loaded after a refusal");
    check(!ms_get_svn(&svn) && svn == 0xabcdu, "svn is not readable after a refusal");
    memset(out, 0x33, sizeof(out));
    check(!ms_get_block(1u, out, sizeof(out)) && out[0] == 0x33,
          "block 1 is not readable even though its descriptor was valid");
}

static void test_environment(void)
{
    img_t m;
    uint64_t svn = 0;

    printf("\n-- the environment variable --\n");

    img_valid(&m);
    put64(m.b + 8, 9u);
    if (!write_image(&m, 0u)) {
        check(false, "could not write the scratch fixture");
        return;
    }

    /* ms_reset() puts the module back to never-having-looked, which is the
     * state the emulator starts in. The first accessor call must then find the
     * file through the environment with no explicit load. */
    ms_reset();
    if (setenv(MS_ENV_PATH, scratch_path(), 1) != 0) {
        check(false, "setenv failed");
        return;
    }
    check(ms_get_svn(&svn) && svn == 9u,
          "the first read finds the file through " MS_ENV_PATH);

    ms_reset();
    if (unsetenv(MS_ENV_PATH) != 0) {
        check(false, "unsetenv failed");
        return;
    }
    svn = 0x1234u;
    check(!ms_get_svn(&svn) && svn == 0x1234u,
          "with the variable unset nothing is read and the destination is untouched");
    check(ms_last_status() == MS_NO_SOURCE, "and the status says so");
}

/* Every status must have been produced by something above. A code that no test
 * provokes is a code whose check has never run. */
static void test_status_coverage(void)
{
    static const struct { ms_status_t s; const char *name; } all[] = {
        { MS_OK,                "MS_OK" },
        { MS_NO_SOURCE,         "MS_NO_SOURCE" },
        { MS_ERR_OPEN,          "MS_ERR_OPEN" },
        { MS_ERR_TOO_LARGE,     "MS_ERR_TOO_LARGE" },
        { MS_ERR_HEADER_SHORT,  "MS_ERR_HEADER_SHORT" },
        { MS_ERR_MAGIC,         "MS_ERR_MAGIC" },
        { MS_ERR_VERSION,       "MS_ERR_VERSION" },
        { MS_ERR_TABLE_SHORT,   "MS_ERR_TABLE_SHORT" },
        { MS_ERR_DESC_RESERVED, "MS_ERR_DESC_RESERVED" },
        { MS_ERR_DESC_INDEX,    "MS_ERR_DESC_INDEX" },
        { MS_ERR_DESC_DUPLICATE, "MS_ERR_DESC_DUPLICATE" },
        { MS_ERR_DESC_OFFSET,   "MS_ERR_DESC_OFFSET" },
        { MS_ERR_DESC_LENGTH,   "MS_ERR_DESC_LENGTH" },
        { MS_ERR_DESC_IN_TABLE, "MS_ERR_DESC_IN_TABLE" },
    };
    size_t i;
    char msg[128];

    printf("\n-- every status was reached by something --\n");
    for (i = 0; i < sizeof(all) / sizeof(all[0]); i++) {
        snprintf(msg, sizeof(msg), "%-24s observed", all[i].name);
        check(g_seen_status[(size_t)all[i].s], msg);
    }
}

int main(int argc, char **argv)
{
    /* --emit writes the canonical fixture and stops.
     *
     * `make interop` runs it and byte-compares the result with what
     * device/gen_measurements.py writes for the same defaults. The format now
     * has two independent implementations — one in C that has to parse it and
     * one in Python that has to produce it — and standing rule 12 says that
     * where two tools can reach the same quantity by different routes they are
     * made to agree. Without this they would drift, and the drift would appear
     * as a failed handshake three steps later with no obvious cause. */
    if (argc > 2 && strcmp(argv[1], "--emit") == 0) {
        img_t m;
        img_valid(&m);
        if (!write_image_to(argv[2], &m, 0u)) {
            fprintf(stderr, "could not write %s\n", argv[2]);
            return 1;
        }
        return 0;
    }

    if (argc > 1) {
        g_dir = argv[1];
    }

    printf("measurement_source self-test\n");

    test_range();
    test_valid();
    test_no_source();
    test_rejections();
    test_no_half_state();
    test_environment();
    test_status_coverage();

    (void)remove(scratch_path());

    printf("\n%d checks, %d failed\n", g_checks, g_failures);
    return g_failures == 0 ? 0 : 1;
}

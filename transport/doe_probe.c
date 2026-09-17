/*
 * transport/doe_probe.c — drive a PCIe DOE mailbox from userspace.
 *
 * Why this exists
 * ---------------
 * Gate 5 has two halves. The MCTP half (transport/mctp_bridge.c) puts the
 * whole handshake on a real MCTP network. This is the other half, and it asks
 * a narrower question: can an SPDM message cross a real PCIe Data Object
 * Exchange mailbox, on a device the guest kernel enumerated, and be answered?
 *
 * The apparatus is a QEMU-emulated NVMe controller started with spdm_port=N.
 * QEMU gives that device a DOE extended capability and registers two protocols
 * on it (hw/nvme/ctrl.c):
 *
 *     static DOEProtocol doe_spdm_prot[] = {
 *         { PCI_VENDOR_ID_PCI_SIG, PCI_SIG_DOE_CMA,         pcie_doe_spdm_rsp },
 *         { PCI_VENDOR_ID_PCI_SIG, PCI_SIG_DOE_SECURED_CMA, pcie_doe_spdm_rsp },
 *     };
 *
 * and pcie_doe_spdm_rsp forwards the data object over the *same twelve-byte
 * socket protocol* that spdm-emu speaks, with transport type
 * SPDM_SOCKET_TRANSPORT_TYPE_PCI_DOE. So the responder at the far end is an
 * ordinary `spdm_responder_emu --trans PCI_DOE`, and the thing that is new is
 * everything in between: config-space register writes, a DWORD-at-a-time
 * mailbox, and a busy/ready handshake.
 *
 * WHY USERSPACE. Linux 6.12 has no in-kernel CMA-SPDM requester — PCI/CMA
 * arrived later — so nothing in the guest will drive this mailbox on its own.
 * Writing the requester is therefore the only way to make the DOE path carry
 * anything, and it has a second advantage: with no driver bound to the
 * mailbox there is nobody to race with.
 *
 * WHAT IT IS NOT. This is not an SPDM requester. It sends one message and
 * prints the reply. Everything about state machines, transcripts and
 * signatures lives in libspdm and is exercised over the socket and MCTP paths
 * instead. What is demonstrated here is the transport.
 *
 * Register layout, from include/uapi/linux/pci_regs.h of the guest kernel:
 *
 *     +0x04  DOE Capabilities
 *     +0x08  DOE Control       bit 31 GO, bit 0 ABORT
 *     +0x0c  DOE Status        bit 31 DATA OBJECT READY, bit 2 ERROR, bit 0 BUSY
 *     +0x10  DOE Write Data Mailbox
 *     +0x14  DOE Read Data Mailbox
 *
 * A data object is DWORDs: header 1 is vendor ID in the low 16 bits and type
 * in bits 23:16; header 2 is the length of the WHOLE object in DWORDs, in bits
 * 17:0, where zero means 2^18. Reading is a pop: each read of the read mailbox
 * returns the current DWORD, and writing anything back to that register
 * advances to the next one.
 *
 * Build:  make -C transport
 * Run  :  sudo ./doe_probe --device 0000:00:04.0 --discovery --spdm
 */

#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <getopt.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

/* ── PCIe extended configuration space ──────────────────────────────────── */
#define PCI_CFG_SPACE_SIZE 0x100
#define PCI_CFG_SPACE_EXP_SIZE 0x1000

#define PCI_EXT_CAP_ID(header) ((header) & 0x0000ffffu)
#define PCI_EXT_CAP_VER(header) (((header) >> 16) & 0xfu)
#define PCI_EXT_CAP_NEXT(header) (((header) >> 20) & 0xffcu)

#define PCI_EXT_CAP_ID_DOE 0x2e

#define PCI_DOE_CAP 0x04
#define PCI_DOE_CTRL 0x08
#define PCI_DOE_STATUS 0x0c
#define PCI_DOE_WRITE 0x10
#define PCI_DOE_READ 0x14

#define PCI_DOE_CTRL_ABORT 0x00000001u
#define PCI_DOE_CTRL_GO 0x80000000u

#define PCI_DOE_STATUS_BUSY 0x00000001u
#define PCI_DOE_STATUS_ERROR 0x00000004u
#define PCI_DOE_STATUS_DATA_OBJECT_READY 0x80000000u

/* ── data objects ───────────────────────────────────────────────────────── */
#define PCI_VENDOR_ID_PCI_SIG 0x0001u
#define DOE_TYPE_DISCOVERY 0x00u
#define DOE_TYPE_CMA_SPDM 0x01u
#define DOE_TYPE_SECURED_CMA_SPDM 0x02u

#define DOE_MAX_DW 1024u

static const char *g_dev;
static int g_fd = -1;
static unsigned g_cap;
static bool g_verbose;

static void die(const char *what)
{
    fprintf(stderr, "doe_probe: %s", what);
    if (errno) {
        fprintf(stderr, ": %s", strerror(errno));
    }
    fputc('\n', stderr);
    exit(1);
}

/* ── config-space access ────────────────────────────────────────────────── */
/*
 * Through /sys/bus/pci/devices/<BDF>/config, which is a plain file: pread and
 * pwrite at the register offset. Writes above offset 0x3f need CAP_SYS_ADMIN,
 * which is the only privilege this program needs and the reason it is run as
 * root in the guest rather than given a udev rule.
 */
static uint32_t cfg_read32(unsigned off)
{
    uint32_t v;
    ssize_t n = pread(g_fd, &v, sizeof(v), (off_t)off);

    if (n != (ssize_t)sizeof(v)) {
        fprintf(stderr, "doe_probe: short read at 0x%x (%zd bytes)\n", off, n);
        exit(1);
    }
    return v;
}

static void cfg_write32(unsigned off, uint32_t v)
{
    ssize_t n = pwrite(g_fd, &v, sizeof(v), (off_t)off);

    if (n != (ssize_t)sizeof(v)) {
        fprintf(stderr, "doe_probe: short write at 0x%x (%zd bytes)\n", off, n);
        exit(1);
    }
}

/*
 * Walk the extended capability list. It starts at 0x100 and each entry points
 * at the next; a zero header or a next pointer that does not advance ends it.
 * Bounding the walk matters: a malformed list is a loop, and a loop here is a
 * hang in a program that is meant to be the simple half of the experiment.
 */
static bool find_doe(unsigned *out)
{
    unsigned off = PCI_CFG_SPACE_SIZE;
    unsigned seen = 0;

    while (off >= PCI_CFG_SPACE_SIZE && off < PCI_CFG_SPACE_EXP_SIZE) {
        uint32_t hdr = cfg_read32(off);

        if (hdr == 0 || hdr == 0xffffffffu) {
            return false;
        }
        if (g_verbose) {
            printf("  ext cap 0x%04x v%u at 0x%03x\n", PCI_EXT_CAP_ID(hdr),
                   PCI_EXT_CAP_VER(hdr), off);
        }
        if (PCI_EXT_CAP_ID(hdr) == PCI_EXT_CAP_ID_DOE) {
            *out = off;
            return true;
        }
        if (++seen > 64) {
            fprintf(stderr, "doe_probe: capability list does not terminate\n");
            return false;
        }
        off = PCI_EXT_CAP_NEXT(hdr);
    }
    return false;
}

/* ── one exchange ───────────────────────────────────────────────────────── */

static void doe_abort(void)
{
    cfg_write32(g_cap + PCI_DOE_CTRL, PCI_DOE_CTRL_ABORT);
    usleep(1000);
}

/*
 * Write the request DWORDs, set GO, wait for DATA OBJECT READY, then pop the
 * response a DWORD at a time.
 *
 * The one thing worth stating about the read side: reading the read mailbox
 * does not advance it. Writing to it does. hw/pci/pcie_doe.c:
 *
 *     doe_cap->read_mbox_idx++;
 *     if (doe_cap->read_mbox_idx == doe_cap->read_mbox_len) { ... }
 *
 * happens in the WRITE handler for that register, so a loop that only reads
 * returns the first DWORD forever, which looks exactly like a device that
 * answered with a repeated header.
 */
static unsigned doe_exchange(const uint32_t *req, unsigned req_dw,
                             uint32_t *rsp, unsigned rsp_max_dw)
{
    struct timespec t0, t1;
    unsigned i, len_dw;
    uint32_t status;
    int spins = 0;

    if (req_dw < 2) {
        die("a data object is at least two DWORDs");
    }

    status = cfg_read32(g_cap + PCI_DOE_STATUS);
    if (status & PCI_DOE_STATUS_ERROR) {
        fprintf(stderr, "doe_probe: mailbox is in error, aborting it first\n");
        doe_abort();
    }

    clock_gettime(CLOCK_MONOTONIC, &t0);

    for (i = 0; i < req_dw; i++) {
        cfg_write32(g_cap + PCI_DOE_WRITE, req[i]);
    }
    cfg_write32(g_cap + PCI_DOE_CTRL, PCI_DOE_CTRL_GO);

    for (;;) {
        status = cfg_read32(g_cap + PCI_DOE_STATUS);
        if (status & PCI_DOE_STATUS_ERROR) {
            fprintf(stderr, "doe_probe: DOE Status reports ERROR (0x%08x)\n",
                    status);
            doe_abort();
            return 0;
        }
        if (status & PCI_DOE_STATUS_DATA_OBJECT_READY) {
            break;
        }
        if (++spins > 200000) {
            fprintf(stderr, "doe_probe: no response; status 0x%08x\n", status);
            doe_abort();
            return 0;
        }
        usleep(100);
    }

    /* header 1 and header 2 first, because header 2 carries the length */
    rsp[0] = cfg_read32(g_cap + PCI_DOE_READ);
    cfg_write32(g_cap + PCI_DOE_READ, 0);
    rsp[1] = cfg_read32(g_cap + PCI_DOE_READ);
    cfg_write32(g_cap + PCI_DOE_READ, 0);

    len_dw = rsp[1] & 0x3ffffu;
    if (len_dw == 0) {
        len_dw = 1u << 18; /* the spec's encoding of the maximum */
    }
    if (len_dw > rsp_max_dw) {
        fprintf(stderr, "doe_probe: response of %u DWORDs exceeds the buffer\n",
                len_dw);
        doe_abort();
        return 0;
    }
    for (i = 2; i < len_dw; i++) {
        rsp[i] = cfg_read32(g_cap + PCI_DOE_READ);
        cfg_write32(g_cap + PCI_DOE_READ, 0);
    }

    clock_gettime(CLOCK_MONOTONIC, &t1);
    if (g_verbose) {
        double ms = (double)(t1.tv_sec - t0.tv_sec) * 1000.0 +
                    (double)(t1.tv_nsec - t0.tv_nsec) / 1e6;
        printf("  exchange: %u DWORDs out, %u in, %.1f ms, %d status polls\n",
               req_dw, len_dw, ms, spins);
    }
    return len_dw;
}

static void hexdump(const char *label, const uint8_t *p, size_t n)
{
    size_t i;

    printf("  %s (%zu bytes)\n", label, n);
    for (i = 0; i < n; i++) {
        if (i % 16 == 0) {
            printf("    %04zx  ", i);
        }
        printf("%02x ", p[i]);
        if (i % 16 == 15 || i + 1 == n) {
            putchar('\n');
        }
    }
}

/* ── DOE Discovery ──────────────────────────────────────────────────────── */
/*
 * Protocol zero, which every DOE instance must implement. Ask for index 0 and
 * follow the next-index chain until it returns to zero. This is the cheapest
 * possible proof that the mailbox works end to end, and it answers entirely
 * inside QEMU — no SPDM responder is involved — so a failure here separates
 * "the mailbox is wrong" from "the socket is wrong".
 */
static int do_discovery(void)
{
    uint8_t index = 0;
    int found = 0;

    printf("DOE Discovery (vendor 0x0001, type 0x00)\n");
    for (;;) {
        uint32_t req[3], rsp[DOE_MAX_DW];
        unsigned n;
        uint16_t vid;
        uint8_t proto, next;

        req[0] = PCI_VENDOR_ID_PCI_SIG | ((uint32_t)DOE_TYPE_DISCOVERY << 16);
        req[1] = 3;
        req[2] = index;

        n = doe_exchange(req, 3, rsp, DOE_MAX_DW);
        if (n < 3) {
            fprintf(stderr, "  discovery at index %u returned %u DWORDs\n",
                    index, n);
            return 1;
        }
        vid = (uint16_t)(rsp[2] & 0xffffu);
        proto = (uint8_t)((rsp[2] >> 16) & 0xffu);
        next = (uint8_t)((rsp[2] >> 24) & 0xffu);

        printf("  index %-3u vendor 0x%04x  protocol 0x%02x%s\n", index, vid,
               proto,
               proto == DOE_TYPE_DISCOVERY      ? "  (Discovery)"
               : proto == DOE_TYPE_CMA_SPDM     ? "  (CMA-SPDM)"
               : proto == DOE_TYPE_SECURED_CMA_SPDM ? "  (Secured CMA-SPDM)"
                                                    : "");
        found++;
        if (next == 0 || found > 32) {
            break;
        }
        index = next;
    }
    printf("  %d protocol(s)\n\n", found);
    return 0;
}

/* ── one SPDM message over CMA-SPDM ─────────────────────────────────────── */
/*
 * GET_VERSION is the right message to send and the only one worth sending
 * from here. It is four bytes, it is the first message of every handshake, it
 * carries no state, and its response is fixed-format — so a correct reply is
 * unambiguous evidence that the object reached libspdm and came back, while a
 * wrong one cannot be explained away as a missing transcript.
 *
 *     byte 0  SPDMVersion          0x10  (1.0, which GET_VERSION always uses)
 *     byte 1  RequestResponseCode  0x84  GET_VERSION
 *     byte 2  Param1               0x00
 *     byte 3  Param2               0x00
 */
static int do_spdm_get_version(void)
{
    static const uint8_t get_version[4] = { 0x10, 0x84, 0x00, 0x00 };
    uint32_t req[DOE_MAX_DW], rsp[DOE_MAX_DW];
    unsigned payload_dw = (sizeof(get_version) + 3) / 4;
    unsigned req_dw = 2 + payload_dw;
    unsigned n, body_bytes;
    const uint8_t *body;

    printf("CMA-SPDM (vendor 0x0001, type 0x01): GET_VERSION\n");

    memset(req, 0, sizeof(req));
    req[0] = PCI_VENDOR_ID_PCI_SIG | ((uint32_t)DOE_TYPE_CMA_SPDM << 16);
    req[1] = req_dw;
    memcpy(&req[2], get_version, sizeof(get_version));
    hexdump("request payload", get_version, sizeof(get_version));

    n = doe_exchange(req, req_dw, rsp, DOE_MAX_DW);
    if (n < 3) {
        fprintf(stderr, "  no CMA-SPDM response (%u DWORDs)\n", n);
        return 1;
    }

    body = (const uint8_t *)&rsp[2];
    body_bytes = (n - 2) * 4;
    hexdump("response payload", body, body_bytes);

    if (body[0] != 0x10 && body[0] != 0x11 && body[0] != 0x12 &&
        body[0] != 0x13 && body[0] != 0x14) {
        fprintf(stderr, "  first byte 0x%02x is not an SPDMVersion\n", body[0]);
        return 1;
    }
    if (body[1] != 0x04) {
        /* 0x7F is ERROR; anything else means the object was mangled. */
        fprintf(stderr, "  RequestResponseCode 0x%02x, expected 0x04 VERSION\n",
                body[1]);
        return 1;
    }

    /*
     * VERSION, from libspdm's spdm_version_response_t:
     *
     *     0  SPDMVersion
     *     1  RequestResponseCode (0x04)
     *     2  Param1
     *     3  Param2
     *     4  Reserved                    <-- easy to miss
     *     5  VersionNumberEntryCount
     *     6  VersionNumberEntry[], two bytes each, little endian
     *
     * The reserved byte at offset 4 is why the count is at 5 and not at 4.
     * The first version of this function read it at 4, reported zero entries,
     * and printed nothing -- while the sixteen bytes on the screen plainly
     * had five versions in them. The bytes were right and the reading was
     * wrong, which is the failure mode this whole repository is arranged
     * against, so the layout above is transcribed from the header rather than
     * from memory.
     *
     * Within an entry, SPDM_VERSION_NUMBER_SHIFT_BIT is 8: the major version
     * is bits 15:12 and the minor 11:8, and the low byte is the update and
     * alpha fields, which are not part of version negotiation.
     */
    if (body_bytes < 6) {
        fprintf(stderr, "  VERSION shorter than its own header\n");
        return 1;
    }
    printf("  ★ VERSION: SPDMVersion 0x%02x, code 0x%02x, %u entries\n",
           body[0], body[1], body[5]);
    {
        unsigned i;
        printf("     versions advertised:");
        for (i = 0; i < body[5] && 6 + i * 2 + 1 < body_bytes; i++) {
            uint16_t e = (uint16_t)(body[6 + i * 2] | (body[7 + i * 2] << 8));
            printf(" %u.%u", (e >> 12) & 0xf, (e >> 8) & 0xf);
        }
        putchar('\n');
    }
    return 0;
}

/* ── main ───────────────────────────────────────────────────────────────── */

static void usage(void)
{
    fputs("usage: doe_probe --device <BDF> [--discovery] [--spdm] [--verbose]\n"
          "\n"
          "  --device 0000:00:04.0   the PCI device to drive\n"
          "  --discovery             run the DOE Discovery protocol\n"
          "  --spdm                  send one GET_VERSION over CMA-SPDM\n"
          "  --verbose               print the capability walk and timings\n",
          stderr);
    exit(2);
}

int main(int argc, char **argv)
{
    static const struct option opts[] = {
        { "device", required_argument, NULL, 'd' },
        { "discovery", no_argument, NULL, 'D' },
        { "spdm", no_argument, NULL, 's' },
        { "verbose", no_argument, NULL, 'v' },
        { "help", no_argument, NULL, 'h' },
        { NULL, 0, NULL, 0 },
    };
    char path[256];
    bool want_disc = false, want_spdm = false;
    int c, rc = 0;

    while ((c = getopt_long(argc, argv, "", opts, NULL)) != -1) {
        switch (c) {
        case 'd':
            g_dev = optarg;
            break;
        case 'D':
            want_disc = true;
            break;
        case 's':
            want_spdm = true;
            break;
        case 'v':
            g_verbose = true;
            break;
        default:
            usage();
        }
    }
    if (!g_dev) {
        usage();
    }
    if (!want_disc && !want_spdm) {
        want_disc = want_spdm = true;
    }

    snprintf(path, sizeof(path), "/sys/bus/pci/devices/%s/config", g_dev);
    g_fd = open(path, O_RDWR);
    if (g_fd < 0) {
        die(path);
    }

    printf("device %s\n", g_dev);
    printf("  vendor:device %04x:%04x\n", cfg_read32(0) & 0xffffu,
           (cfg_read32(0) >> 16) & 0xffffu);

    if (!find_doe(&g_cap)) {
        fprintf(stderr,
                "doe_probe: no Data Object Exchange capability on %s\n", g_dev);
        close(g_fd);
        return 1;
    }
    printf("  DOE capability at config offset 0x%03x\n", g_cap);
    printf("  DOE Capabilities 0x%08x, Status 0x%08x\n\n",
           cfg_read32(g_cap + PCI_DOE_CAP), cfg_read32(g_cap + PCI_DOE_STATUS));

    if (want_disc) {
        rc |= do_discovery();
    }
    if (want_spdm) {
        rc |= do_spdm_get_version();
    }

    close(g_fd);
    return rc;
}

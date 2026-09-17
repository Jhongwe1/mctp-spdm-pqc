/*
 * transport/mctp_bridge.c — put the spdm-emu handshake on a real MCTP network.
 *
 * Why this file exists
 * --------------------
 * Every capture in bench/data/ up to week eight was taken on the spdm-emu
 * socket transport, which docs/transports.md establishes is a twelve-byte
 * header on a TCP connection to 127.0.0.1.  `--trans MCTP` selects an
 * *encoding*; it does not put the message on an MCTP network.  There are no
 * endpoint IDs on that path, no routing, no tags, and — the part that matters
 * for the post-quantum cost story — no packetisation.  Every MCTP packet count
 * this repository has published is therefore arithmetic on a measured message
 * length, and docs/fragmentation.md says so in those words.
 *
 * This program is what removes that sentence.  It sits between the two
 * emulators and carries their conversation across a real Linux MCTP link:
 *
 *   spdm_requester_emu --trans MCTP            spdm_responder_emu --trans MCTP
 *          |  TCP 127.0.0.1:2323                        ^  TCP 127.0.0.1:2323
 *          v  (netns A loopback)                        |  (netns B loopback)
 *   mctp_bridge --role requester  ==== AF_MCTP ====  mctp_bridge --role responder
 *        EID 8                       a real link          EID 9
 *
 * Neither emulator is modified and neither knows.  What changes is that the
 * bytes between them now go through net/mctp, which allocates tags, applies a
 * route, and splits anything longer than the transmission unit into numbered
 * packets with SOM and EOM flags — the behaviour this project has until now
 * only been able to compute.
 *
 * Two things had to be read from source before a line of this was written, and
 * guessing either one produces a silently wrong result.
 *
 * (1) THE TYPE BYTE IS NOT IN THE BUFFER.  net/mctp/af_mctp.c, mctp_sendmsg:
 *
 *         skb_reserve(skb, hlen);
 *         [ set type as fist byte in payload ]
 *         *(u8 *)skb_put(skb, 1) = addr->smctp_type;
 *         rc = memcpy_from_msg((void *)skb_put(skb, len), msg, len);
 *
 *     The kernel writes the MCTP message type itself, out of smctp_type, and
 *     what you hand to send() is the body *after* it.  mctp_recvmsg is the
 *     mirror image: it takes the type from the first byte, reports it in the
 *     returned sockaddr, and copies from offset 1, so msglen is skb->len - 1.
 *
 *     The spdm-emu MCTP socket payload starts WITH that byte — its first octet
 *     is 0x05 — because libspdm encoded it and spdm-emu handed the encoded
 *     buffer straight to the socket.  So this bridge strips one byte on the
 *     way out and puts one back on the way in.  That is the same off-by-one
 *     docs/transports.md already records as upstream candidate five, seen from
 *     the other side: there, a reader who trusts command.h reads the SPDM
 *     header one byte early; here, a bridge that forwards the buffer unchanged
 *     sends a message whose first byte is 0x05 and whose SPDMVersion lands in
 *     the request-code field.  The handshake fails, and it fails looking like a
 *     protocol error rather than like a bug in the plumbing.
 *
 * (2) THE EMULATOR CONTROL COMMANDS ARE NOT SPDM.  spdm_requester_emu opens
 *     with SOCKET_SPDM_COMMAND_TEST carrying "Client Hello!" and closes with
 *     SOCKET_SPDM_COMMAND_SHUTDOWN or _CONTINUE; the responder answers each
 *     with its own code, and answers anything it does not recognise with
 *     SOCKET_SPDM_COMMAND_UNKOWN.  Those are spdm-emu plumbing, not SPDM
 *     messages, and putting them on the wire as MCTP message type 0x05 would
 *     put three non-SPDM messages into a capture this project then counts SPDM
 *     packets in.
 *
 *     So they travel as MCTP message type 0x7E (vendor-defined, PCI) with the
 *     four-byte command word in front, and the analysis counts type 0x05 only.
 *     The consequence is worth stating plainly: the type-0x05 traffic on this
 *     link is the SPDM messages and nothing else, which is what makes a packet
 *     count taken from it comparable with the captures already in bench/data/.
 *
 * Roles
 * -----
 *   --role requester   listen on TCP, speak MCTP to --peer-eid
 *   --role responder   listen on MCTP, speak TCP to --tcp-port
 *   --role replay      send messages of stated lengths, await an ack for each
 *   --role sink        receive messages, ack with the length reassembled
 *
 * The last two exist because the message lengths in a handshake are whatever
 * the handshake happens to produce, while the formula in docs/fragmentation.md
 * needs testing at the lengths that *discriminate* it from the plausible wrong
 * version, ceil(L/(64-4-1)). Those are 60 to 63, 119 to 126, and everything
 * large; at 64, 128 and 177 the two agree, and a test run only at those would
 * confirm the arithmetic while discriminating nothing.
 *
 * Build:  make -C transport
 */

#define _GNU_SOURCE
#include <errno.h>
#include <getopt.h>
#include <poll.h>
#include <signal.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include <arpa/inet.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <sys/socket.h>
#include <sys/types.h>

#include <linux/mctp.h>

#ifndef AF_MCTP
#define AF_MCTP 45
#endif

/* ---------------------------------------------------------------------------
 * The spdm-emu socket protocol, from spdm_emu/spdm_emu_common/command.h.
 *
 * Three big-endian uint32 — command, transport type, payload size — and then
 * the payload.  The comment in that header calls the payload "SPDM message,
 * starting from SPDM_HEADER", which holds only for SOCKET_TRANSPORT_TYPE_NONE;
 * see the note on the type byte above.
 * ------------------------------------------------------------------------- */
#define SOCK_CMD_NORMAL   0x0001u
#define SOCK_CMD_CONTINUE 0xFFFDu
#define SOCK_CMD_SHUTDOWN 0xFFFEu
#define SOCK_CMD_UNKNOWN  0xFFFFu
#define SOCK_CMD_TEST     0xDEADu

#define SOCK_TRANS_MCTP   0x01u

/* MCTP message types (DSP0239).  0x05 is SPDM.  0x7E is vendor-defined PCI,
 * used here for the emulator control commands so they stay out of the SPDM
 * packet count. */
#define MCTP_TYPE_SPDM  0x05u
#define MCTP_TYPE_CTRL  0x7Eu

/* Large enough for any message either emulator produces.  The largest observed
 * in this project is a 4,352-byte CHUNK_RESPONSE; the largest possible without
 * chunking is bounded by the emulator buffers, which the pqc-dts flavour
 * raises to 0x8080.  256 KiB is comfortably above both, and it is allocated
 * once and statically, so a long message never lands on a stack. */
#define BUF_MAX (256u * 1024u)

static bool g_verbose;
static const char *g_role = "?";

static void vlog(const char *fmt, ...)
{
    va_list ap;
    struct timespec ts;

    if (!g_verbose) {
        return;
    }
    clock_gettime(CLOCK_MONOTONIC, &ts);
    fprintf(stderr, "[%3ld.%03ld %s] ", (long)ts.tv_sec % 1000,
            ts.tv_nsec / 1000000L, g_role);
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fputc('\n', stderr);
    fflush(stderr);
}

static void die(const char *fmt, ...)
{
    va_list ap;
    int e = errno;

    fprintf(stderr, "mctp_bridge(%s): ", g_role);
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    if (e != 0) {
        fprintf(stderr, ": %s", strerror(e));
    }
    fputc('\n', stderr);
    exit(1);
}

/* ------------------------------------------------------------------ bytes -- */

static uint32_t rd32be(const uint8_t *p)
{
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) |
           ((uint32_t)p[2] << 8) | (uint32_t)p[3];
}

static void wr32be(uint8_t *p, uint32_t v)
{
    p[0] = (uint8_t)(v >> 24);
    p[1] = (uint8_t)(v >> 16);
    p[2] = (uint8_t)(v >> 8);
    p[3] = (uint8_t)v;
}

/* read() until n bytes, or the peer closes.  Returns false on a clean EOF so
 * the caller can tell "the emulator finished" from "the link broke". */
static bool read_exact(int fd, void *buf, size_t n)
{
    uint8_t *p = buf;
    size_t got = 0;

    while (got < n) {
        ssize_t r = read(fd, p + got, n - got);
        if (r == 0) {
            return false;
        }
        if (r < 0) {
            if (errno == EINTR) {
                continue;
            }
            die("read");
        }
        got += (size_t)r;
    }
    return true;
}

static void write_exact(int fd, const void *buf, size_t n)
{
    const uint8_t *p = buf;
    size_t put = 0;

    while (put < n) {
        ssize_t w = write(fd, p + put, n - put);
        if (w < 0) {
            if (errno == EINTR) {
                continue;
            }
            die("write");
        }
        put += (size_t)w;
    }
}

/* --------------------------------------------------------- socket frames -- */

struct frame {
    uint32_t cmd;
    uint32_t trans;
    uint32_t len;
    uint8_t *buf; /* points into a caller-owned BUF_MAX buffer */
};

static bool frame_read(int fd, struct frame *f)
{
    uint8_t hdr[12];

    if (!read_exact(fd, hdr, sizeof(hdr))) {
        return false;
    }
    f->cmd = rd32be(hdr + 0);
    f->trans = rd32be(hdr + 4);
    f->len = rd32be(hdr + 8);
    if (f->len > BUF_MAX) {
        errno = 0;
        die("socket frame payload %u exceeds %u", f->len, BUF_MAX);
    }
    if (f->len && !read_exact(fd, f->buf, f->len)) {
        return false;
    }
    return true;
}

static void frame_write(int fd, uint32_t cmd, uint32_t trans,
                        const uint8_t *payload, uint32_t len)
{
    uint8_t hdr[12];

    wr32be(hdr + 0, cmd);
    wr32be(hdr + 4, trans);
    wr32be(hdr + 8, len);
    write_exact(fd, hdr, sizeof(hdr));
    if (len) {
        write_exact(fd, payload, len);
    }
}

/* ------------------------------------------------------------------ MCTP -- */

/* One datagram socket per MCTP message type.  bind() is what makes a socket
 * eligible to receive: mctp_bind stores bind_type = smctp_type & 0x7f together
 * with bind_addr, and the input path matches on them.  Binding to
 * MCTP_ADDR_ANY means "any EID local to this network namespace", which is the
 * right answer precisely because the two ends of this link are in different
 * namespaces — in one namespace, two sockets bound the same way would both
 * match and the kernel would deliver to whichever it found first. */
static int mctp_open(uint8_t type, unsigned net)
{
    struct sockaddr_mctp addr;
    int fd, bufsz = 1 << 20;

    fd = socket(AF_MCTP, SOCK_DGRAM, 0);
    if (fd < 0) {
        die("socket(AF_MCTP) - is CONFIG_MCTP set in this kernel?");
    }

    /* A 16 KiB certificate chain reassembles into one skb and the receive
     * buffer is charged the whole of it.  Ask for room; SO_RCVBUF is advisory
     * and the kernel doubles what it grants, so this is a floor and not a
     * promise. */
    (void)setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &bufsz, sizeof(bufsz));
    (void)setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &bufsz, sizeof(bufsz));

    memset(&addr, 0, sizeof(addr));
    addr.smctp_family = AF_MCTP;
    addr.smctp_network = net;
    addr.smctp_addr.s_addr = MCTP_ADDR_ANY;
    addr.smctp_type = type;
    addr.smctp_tag = 0; /* bind ignores it; sendmsg is where tags happen */

    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        die("bind(AF_MCTP type 0x%02x)", type);
    }
    return fd;
}

/* Send as a request.  MCTP_TAG_OWNER makes the kernel allocate a tag and set
 * the TO bit, which is what marks the message a request rather than a
 * response.  The tag is held until the matching response arrives or the key
 * expires, and there are eight of them per peer — which is why every role here
 * waits for its reply instead of streaming. */
static void mctp_send_req(int fd, unsigned net, uint8_t eid, uint8_t type,
                          const uint8_t *body, size_t len)
{
    struct sockaddr_mctp to;
    ssize_t rc;

    memset(&to, 0, sizeof(to));
    to.smctp_family = AF_MCTP;
    to.smctp_network = net;
    to.smctp_addr.s_addr = eid;
    to.smctp_type = type;
    to.smctp_tag = MCTP_TAG_OWNER;

    rc = sendto(fd, body, len, 0, (struct sockaddr *)&to, sizeof(to));
    if (rc < 0) {
        die("sendto(eid %u, type 0x%02x, %zu bytes)", eid, type, len);
    }
    if ((size_t)rc != len) {
        errno = 0;
        die("short MCTP send: %zd of %zu", rc, len);
    }
}

/* Reply on the tag the request arrived with, TO cleared.  mctp_sendmsg takes
 * that branch verbatim:  else { tag = req_tag & MCTP_TAG_MASK; } */
static void mctp_send_rsp(int fd, const struct sockaddr_mctp *from,
                          uint8_t type, const uint8_t *body, size_t len)
{
    struct sockaddr_mctp to = *from;
    ssize_t rc;

    to.smctp_type = type;
    to.smctp_tag = from->smctp_tag & MCTP_TAG_MASK; /* clears TO */

    rc = sendto(fd, body, len, 0, (struct sockaddr *)&to, sizeof(to));
    if (rc < 0) {
        die("sendto(reply to eid %u, tag %u)", to.smctp_addr.s_addr,
            to.smctp_tag);
    }
}

static ssize_t mctp_recv(int fd, uint8_t *body, size_t cap,
                         struct sockaddr_mctp *from)
{
    socklen_t alen = sizeof(*from);
    ssize_t rc;

    memset(from, 0, sizeof(*from));
    rc = recvfrom(fd, body, cap, MSG_TRUNC, (struct sockaddr *)from, &alen);
    if (rc < 0) {
        die("recvfrom(AF_MCTP)");
    }
    /* With MSG_TRUNC the return value is the real length, so a message that
     * did not fit is detectable rather than silently short. */
    if ((size_t)rc > cap) {
        errno = 0;
        die("MCTP message of %zd bytes truncated into a %zu-byte buffer", rc,
            cap);
    }
    return rc;
}

/* Wait for whichever of the two sockets answers first.  A NORMAL request can
 * legitimately be answered with SOCKET_SPDM_COMMAND_UNKOWN, which travels on
 * the control type, so the reply type is not implied by the request type. */
static int mctp_wait(int fd_spdm, int fd_ctrl, int timeout_ms)
{
    struct pollfd pf[2];
    int rc;

    pf[0].fd = fd_spdm;
    pf[0].events = POLLIN;
    pf[0].revents = 0;
    pf[1].fd = fd_ctrl;
    pf[1].events = POLLIN;
    pf[1].revents = 0;

    do {
        rc = poll(pf, 2, timeout_ms);
    } while (rc < 0 && errno == EINTR);

    if (rc < 0) {
        die("poll");
    }
    if (rc == 0) {
        errno = 0;
        die("no MCTP reply within %d ms", timeout_ms);
    }
    return (pf[0].revents & POLLIN) ? fd_spdm : fd_ctrl;
}

/* ------------------------------------------------------------------- TCP -- */

static int tcp_listen_accept(uint16_t port)
{
    struct sockaddr_in sa;
    int ls, cs, one = 1;

    ls = socket(AF_INET, SOCK_STREAM, 0);
    if (ls < 0) {
        die("socket(AF_INET)");
    }
    (void)setsockopt(ls, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));

    memset(&sa, 0, sizeof(sa));
    sa.sin_family = AF_INET;
    sa.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    sa.sin_port = htons(port);
    if (bind(ls, (struct sockaddr *)&sa, sizeof(sa)) < 0) {
        die("bind(127.0.0.1:%u)", port);
    }
    if (listen(ls, 1) < 0) {
        die("listen");
    }
    vlog("listening on 127.0.0.1:%u", port);

    cs = accept(ls, NULL, NULL);
    if (cs < 0) {
        die("accept");
    }
    close(ls);
    (void)setsockopt(cs, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));
    vlog("accepted");
    return cs;
}

static int tcp_connect(uint16_t port, int retries)
{
    struct sockaddr_in sa;
    int cs, one = 1;

    memset(&sa, 0, sizeof(sa));
    sa.sin_family = AF_INET;
    sa.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    sa.sin_port = htons(port);

    for (;;) {
        cs = socket(AF_INET, SOCK_STREAM, 0);
        if (cs < 0) {
            die("socket(AF_INET)");
        }
        if (connect(cs, (struct sockaddr *)&sa, sizeof(sa)) == 0) {
            (void)setsockopt(cs, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));
            vlog("connected to 127.0.0.1:%u", port);
            return cs;
        }
        close(cs);
        if (retries-- <= 0) {
            die("connect(127.0.0.1:%u)", port);
        }
        usleep(200 * 1000);
    }
}

/* ----------------------------------------------------------------- roles -- */

static uint8_t g_tcp_buf[BUF_MAX];
static uint8_t g_mctp_buf[BUF_MAX];

/*
 * Requester side.  Owns the TCP listener the emulator connects to, and is the
 * MCTP requester: one sendto with TO set, one recvfrom, per exchange.
 */
static int role_requester(uint16_t tcp_port, unsigned net, uint8_t peer_eid,
                          int timeout_ms)
{
    struct frame f;
    int tcp, fd_spdm, fd_ctrl;
    unsigned long n_spdm = 0, n_ctrl = 0;

    f.buf = g_tcp_buf;
    fd_spdm = mctp_open(MCTP_TYPE_SPDM, net);
    fd_ctrl = mctp_open(MCTP_TYPE_CTRL, net);
    tcp = tcp_listen_accept(tcp_port);

    while (frame_read(tcp, &f)) {
        struct sockaddr_mctp from;
        ssize_t got;
        int ready;

        if (f.cmd == SOCK_CMD_NORMAL) {
            if (f.trans != SOCK_TRANS_MCTP) {
                errno = 0;
                die("frame transport %u is not MCTP(1); run the emulators with "
                    "--trans MCTP",
                    f.trans);
            }
            if (f.len < 1) {
                errno = 0;
                die("NORMAL frame with an empty payload");
            }
            if (f.buf[0] != MCTP_TYPE_SPDM) {
                errno = 0;
                die("NORMAL payload starts 0x%02x, expected 0x05 - the socket "
                    "payload should begin with the MCTP message type",
                    f.buf[0]);
            }
            /* strip the type byte: the kernel supplies it from smctp_type */
            mctp_send_req(fd_spdm, net, peer_eid, MCTP_TYPE_SPDM, f.buf + 1,
                          f.len - 1);
            n_spdm++;
            vlog("-> SPDM frame %u bytes, %u on the wire after the type byte",
                 f.len, f.len - 1);
        } else {
            wr32be(g_mctp_buf, f.cmd);
            if (f.len) {
                memcpy(g_mctp_buf + 4, f.buf, f.len);
            }
            mctp_send_req(fd_ctrl, net, peer_eid, MCTP_TYPE_CTRL, g_mctp_buf,
                          (size_t)f.len + 4);
            n_ctrl++;
            vlog("-> ctrl cmd 0x%04x, %u bytes", f.cmd, f.len);
        }

        ready = mctp_wait(fd_spdm, fd_ctrl, timeout_ms);
        got = mctp_recv(ready, g_mctp_buf, sizeof(g_mctp_buf), &from);

        if (ready == fd_spdm) {
            /* put the type byte back: spdm-emu expects the encoded buffer */
            if ((size_t)got + 1 > BUF_MAX) {
                errno = 0;
                die("reply too large to re-frame");
            }
            memmove(g_tcp_buf + 1, g_mctp_buf, (size_t)got);
            g_tcp_buf[0] = MCTP_TYPE_SPDM;
            frame_write(tcp, SOCK_CMD_NORMAL, SOCK_TRANS_MCTP, g_tcp_buf,
                        (uint32_t)got + 1);
            vlog("<- SPDM %zd bytes", got);
        } else {
            uint32_t cmd;

            if (got < 4) {
                errno = 0;
                die("control reply shorter than its command word");
            }
            cmd = rd32be(g_mctp_buf);
            frame_write(tcp, cmd, SOCK_TRANS_MCTP, g_mctp_buf + 4,
                        (uint32_t)got - 4);
            vlog("<- ctrl cmd 0x%04x, %zd bytes", cmd, got - 4);
            if (cmd == SOCK_CMD_SHUTDOWN) {
                break;
            }
        }
    }

    printf("requester bridge: %lu SPDM exchanges, %lu control exchanges\n",
           n_spdm, n_ctrl);
    close(tcp);
    close(fd_spdm);
    close(fd_ctrl);
    return 0;
}

/*
 * Responder side.  Waits on MCTP, forwards to the emulator over TCP, and sends
 * the answer back on the tag the request carried.
 */
static int role_responder(uint16_t tcp_port, unsigned net)
{
    struct frame f;
    int tcp, fd_spdm, fd_ctrl;
    unsigned long n_spdm = 0, n_ctrl = 0;
    bool done = false;

    f.buf = g_tcp_buf;
    fd_spdm = mctp_open(MCTP_TYPE_SPDM, net);
    fd_ctrl = mctp_open(MCTP_TYPE_CTRL, net);
    /* The emulator may not be listening yet; the same script starts both and
     * the order is not guaranteed. */
    tcp = tcp_connect(tcp_port, 100);

    while (!done) {
        struct sockaddr_mctp from;
        struct pollfd pf[2];
        ssize_t got;
        int rc, ready;

        pf[0].fd = fd_spdm;
        pf[0].events = POLLIN;
        pf[0].revents = 0;
        pf[1].fd = fd_ctrl;
        pf[1].events = POLLIN;
        pf[1].revents = 0;

        do {
            rc = poll(pf, 2, -1);
        } while (rc < 0 && errno == EINTR);
        if (rc < 0) {
            die("poll");
        }
        ready = (pf[0].revents & POLLIN) ? fd_spdm : fd_ctrl;

        got = mctp_recv(ready, g_mctp_buf, sizeof(g_mctp_buf), &from);

        if (ready == fd_spdm) {
            if ((size_t)got + 1 > BUF_MAX) {
                errno = 0;
                die("request too large to re-frame");
            }
            memmove(g_tcp_buf + 1, g_mctp_buf, (size_t)got);
            g_tcp_buf[0] = MCTP_TYPE_SPDM;
            frame_write(tcp, SOCK_CMD_NORMAL, SOCK_TRANS_MCTP, g_tcp_buf,
                        (uint32_t)got + 1);
            n_spdm++;
            vlog("-> emu SPDM %zd bytes", got);
        } else {
            uint32_t cmd;

            if (got < 4) {
                errno = 0;
                die("control request shorter than its command word");
            }
            cmd = rd32be(g_mctp_buf);
            frame_write(tcp, cmd, SOCK_TRANS_MCTP, g_mctp_buf + 4,
                        (uint32_t)got - 4);
            n_ctrl++;
            vlog("-> emu ctrl cmd 0x%04x", cmd);
        }

        if (!frame_read(tcp, &f)) {
            errno = 0;
            die("the responder closed the socket before answering");
        }

        if (f.cmd == SOCK_CMD_NORMAL) {
            if (f.len < 1 || f.buf[0] != MCTP_TYPE_SPDM) {
                errno = 0;
                die("responder NORMAL reply does not start with 0x05");
            }
            mctp_send_rsp(fd_spdm, &from, MCTP_TYPE_SPDM, f.buf + 1, f.len - 1);
        } else {
            wr32be(g_mctp_buf, f.cmd);
            if (f.len) {
                memcpy(g_mctp_buf + 4, f.buf, f.len);
            }
            mctp_send_rsp(fd_ctrl, &from, MCTP_TYPE_CTRL, g_mctp_buf,
                          (size_t)f.len + 4);
            if (f.cmd == SOCK_CMD_SHUTDOWN) {
                done = true;
            }
        }
    }

    printf("responder bridge: %lu SPDM exchanges, %lu control exchanges\n",
           n_spdm, n_ctrl);
    close(tcp);
    close(fd_spdm);
    close(fd_ctrl);
    return 0;
}

/*
 * Replay: send messages of stated lengths and wait for each ack.
 *
 * This is the calibration half of the experiment.  The lengths in a handshake
 * are whatever the handshake produces; these are chosen to sit on the
 * boundaries where the candidate formulas disagree.
 */
static int role_replay(unsigned net, uint8_t peer_eid, const char *lengths,
                       int timeout_ms)
{
    char *spec = strdup(lengths);
    char *save = NULL;
    char *tok;
    int fd_spdm;
    int failures = 0;

    if (!spec) {
        die("strdup");
    }
    fd_spdm = mctp_open(MCTP_TYPE_SPDM, net);

    printf("# length  acked  predicted_packets\n");
    for (tok = strtok_r(spec, ",", &save); tok;
         tok = strtok_r(NULL, ",", &save)) {
        struct sockaddr_mctp from;
        unsigned long len = strtoul(tok, NULL, 10);
        unsigned long acked = 0;
        ssize_t got;
        size_t i;

        if (len < 1 || len > BUF_MAX) {
            errno = 0;
            die("length %lu out of range", len);
        }
        /* A recognisable pattern, so a bad reassembly shows up in the capture
         * as wrong bytes rather than merely as a wrong length. */
        for (i = 0; i < len; i++) {
            g_mctp_buf[i] = (uint8_t)(i & 0xff);
        }
        /* The first byte of an SPDM message is SPDMVersion.  Keeping it at
         * 0x13 means a decoder pointed at this capture sees a plausible header
         * instead of garbage, and nothing measured here depends on it. */
        g_mctp_buf[0] = 0x13;

        mctp_send_req(fd_spdm, net, peer_eid, MCTP_TYPE_SPDM, g_mctp_buf, len);
        (void)mctp_wait(fd_spdm, fd_spdm, timeout_ms);
        got = mctp_recv(fd_spdm, g_tcp_buf, sizeof(g_tcp_buf), &from);
        if (got < 8) {
            errno = 0;
            die("ack shorter than eight bytes");
        }
        for (i = 0; i < 8; i++) {
            acked = (acked << 8) | g_tcp_buf[i];
        }
        /* The prediction is printed beside the measurement so a reader does
         * not have to trust that the analysis used the same formula. */
        printf("%8lu  %5lu  %17lu%s\n", len, acked, (len + 1 + 63) / 64,
               acked == len ? "" : "   <-- MISMATCH");
        fflush(stdout);
        if (acked != len) {
            failures++;
        }
    }
    free(spec);
    close(fd_spdm);
    return failures == 0 ? 0 : 1;
}

/*
 * Sink: receive, and ack with the number of bytes the kernel reassembled.
 *
 * The ack is the second witness.  The capture says how many packets crossed
 * the link; this says the far side put them back together into exactly the
 * message that was sent, which is the half a packet count cannot show.
 */
static int role_sink(unsigned net, unsigned long expect_msgs)
{
    int fd_spdm = mctp_open(MCTP_TYPE_SPDM, net);
    unsigned long n = 0;

    while (expect_msgs == 0 || n < expect_msgs) {
        struct sockaddr_mctp from;
        ssize_t got = mctp_recv(fd_spdm, g_mctp_buf, sizeof(g_mctp_buf), &from);
        uint8_t ack[8];
        size_t i;
        uint64_t v = (uint64_t)got;

        for (i = 0; i < 8; i++) {
            ack[i] = (uint8_t)(v >> (56 - 8 * i));
        }
        mctp_send_rsp(fd_spdm, &from, MCTP_TYPE_SPDM, ack, sizeof(ack));
        printf("sink: reassembled %zd bytes from eid %u\n", got,
               from.smctp_addr.s_addr);
        fflush(stdout);
        n++;
    }
    close(fd_spdm);
    return 0;
}

/* ------------------------------------------------------------------ main -- */

static void usage(void)
{
    fputs("usage: mctp_bridge --role <requester|responder|replay|sink> [opts]\n"
          "\n"
          "  --role requester   --tcp-port N --peer-eid E\n"
          "  --role responder   --tcp-port N\n"
          "  --role replay      --peer-eid E --lengths 1,63,64,177,...\n"
          "  --role sink        [--expect N]\n"
          "\n"
          "  --net N            MCTP network id (default 1)\n"
          "  --timeout MS       reply timeout, default 120000\n"
          "  --verbose\n",
          stderr);
    exit(2);
}

int main(int argc, char **argv)
{
    static const struct option opts[] = {
        { "role", required_argument, NULL, 'r' },
        { "tcp-port", required_argument, NULL, 'p' },
        { "peer-eid", required_argument, NULL, 'e' },
        { "net", required_argument, NULL, 'n' },
        { "lengths", required_argument, NULL, 'l' },
        { "expect", required_argument, NULL, 'x' },
        { "timeout", required_argument, NULL, 't' },
        { "verbose", no_argument, NULL, 'v' },
        { "help", no_argument, NULL, 'h' },
        { NULL, 0, NULL, 0 },
    };
    const char *role = NULL;
    const char *lengths = NULL;
    uint16_t tcp_port = 2323;
    unsigned net = 1;
    unsigned long peer_eid = 9;
    unsigned long expect = 0;
    int timeout_ms = 120000;
    int c;

    while ((c = getopt_long(argc, argv, "", opts, NULL)) != -1) {
        switch (c) {
        case 'r':
            role = optarg;
            break;
        case 'p':
            tcp_port = (uint16_t)strtoul(optarg, NULL, 10);
            break;
        case 'e':
            peer_eid = strtoul(optarg, NULL, 10);
            break;
        case 'n':
            net = (unsigned)strtoul(optarg, NULL, 10);
            break;
        case 'l':
            lengths = optarg;
            break;
        case 'x':
            expect = strtoul(optarg, NULL, 10);
            break;
        case 't':
            timeout_ms = (int)strtol(optarg, NULL, 10);
            break;
        case 'v':
            g_verbose = true;
            break;
        default:
            usage();
        }
    }
    if (!role) {
        usage();
    }
    g_role = role;
    signal(SIGPIPE, SIG_IGN);

    if (peer_eid > 255) {
        errno = 0;
        die("peer eid %lu is not an 8-bit EID", peer_eid);
    }

    if (strcmp(role, "requester") == 0) {
        return role_requester(tcp_port, net, (uint8_t)peer_eid, timeout_ms);
    }
    if (strcmp(role, "responder") == 0) {
        return role_responder(tcp_port, net);
    }
    if (strcmp(role, "replay") == 0) {
        if (!lengths) {
            errno = 0;
            die("--role replay needs --lengths");
        }
        return role_replay(net, (uint8_t)peer_eid, lengths, timeout_ms);
    }
    if (strcmp(role, "sink") == 0) {
        return role_sink(net, expect);
    }
    usage();
    return 2;
}

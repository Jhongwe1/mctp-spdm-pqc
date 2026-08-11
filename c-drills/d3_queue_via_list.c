/*
 * d3_queue_via_list.c — a FIFO queue built on a singly linked list.
 *
 * ┌───────────────────────────────────────────────────────────────────────┐
 * │  THE IMPLEMENTATION IS YOURS TO WRITE. Everything below the marker    │
 * │  "YOUR IMPLEMENTATION STARTS HERE" is stubbed out on purpose.         │
 * │                                                                       │
 * │  The ritual, in order, and the order is the point:                    │
 * │    1. On paper, nothing open, 20 minutes.                             │
 * │    2. Dry-run two cases by hand on that paper. One must be a boundary.│
 * │    3. Type it in. Record how many compile errors you got. That number │
 * │       is the only quantifiable measure of progress here — write it    │
 * │       into SCORECARD.md.                                              │
 * │    4. `make test` clean, sanitizers included.                         │
 * │                                                                       │
 * │  Step 3 is not bookkeeping. Writing correct C in an editor with a     │
 * │  compiler one keystroke away is a different skill from writing it on  │
 * │  a whiteboard with someone watching, and only the second one is being │
 * │  tested when it counts.                                               │
 * └───────────────────────────────────────────────────────────────────────┘
 *
 * Where this connects to the project
 * ----------------------------------
 * The transport glue in W09 has to hold messages that have arrived but are not
 * yet consumed. That is this data structure. The bug that will bite there is
 * the same bug boundary (2) below is built to catch.
 *
 * Three boundaries this must survive
 * ----------------------------------
 *   (1) dequeue from an empty queue        -> report failure, do not crash
 *   (2) dequeue the LAST element           -> head and tail must BOTH be
 *                                             updated. Updating only head
 *                                             leaves tail pointing at freed
 *                                             memory, and the next enqueue
 *                                             writes through it. This is the
 *                                             single most common way to get
 *                                             this wrong, and the test below
 *                                             is built specifically to trip it
 *                                             under AddressSanitizer.
 *   (3) queue_free leaves nothing behind   -> LeakSanitizer decides, not you.
 *
 * Build and run:
 *     make d3_queue_via_list && ./d3_queue_via_list
 */

#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>

/* ── types ──────────────────────────────────────────────────────────────── */

typedef struct node {
    int          value;
    struct node *next;
} node;

typedef struct queue {
    node  *head;    /* dequeue from here */
    node  *tail;    /* enqueue to here   */
    size_t count;
} queue;

/* ── contract ───────────────────────────────────────────────────────────────
 *
 * queue_init(q)          leaves q empty. Must be called before anything else.
 * enqueue(q, v)          appends v. Returns false only if allocation failed;
 *                        on failure q is unchanged and still usable.
 * dequeue(q, out)        removes the oldest element and stores it in *out.
 *                        Returns false if the queue is empty; *out untouched.
 * peek(q, out)           like dequeue but does not remove. Same return rule.
 * queue_free(q)          releases every node and leaves q empty and reusable.
 *                        Calling it twice must be safe.
 */

void queue_init(queue *q);
bool enqueue(queue *q, int value);
bool dequeue(queue *q, int *out);
bool peek(const queue *q, int *out);
void queue_free(queue *q);

/* ══════════════════ YOUR IMPLEMENTATION STARTS HERE ═══════════════════════ */

void queue_init(queue *q)
{
    (void)q;
    /* TODO */
}

bool enqueue(queue *q, int value)
{
    (void)q;
    (void)value;
    /* TODO */
    return false;
}

bool dequeue(queue *q, int *out)
{
    (void)q;
    (void)out;
    /* TODO */
    return false;
}

bool peek(const queue *q, int *out)
{
    (void)q;
    (void)out;
    /* TODO */
    return false;
}

void queue_free(queue *q)
{
    (void)q;
    /* TODO */
}

/* ══════════════════ YOUR IMPLEMENTATION ENDS HERE ═════════════════════════ */

/* ── tests ──────────────────────────────────────────────────────────────────
 *
 * These use a CHECK macro rather than assert() so that one failure does not
 * hide the next five. Every check that fails prints its own line; the exit
 * status is what `make test` and CI read.
 */

static int g_failures = 0;
static int g_checks   = 0;

#define CHECK(cond, what)                                                     \
    do {                                                                      \
        g_checks++;                                                           \
        if (cond) {                                                           \
            printf("  ok    %s\n", (what));                                   \
        } else {                                                              \
            printf("  FAIL  %s   (%s:%d)\n", (what), __FILE__, __LINE__);     \
            g_failures++;                                                     \
        }                                                                     \
    } while (0)

static void test_empty_queue(void)
{
    printf("boundary 1 — dequeue and peek on an empty queue\n");
    queue q;
    queue_init(&q);

    int sentinel = -12345;
    int out      = sentinel;

    CHECK(dequeue(&q, &out) == false, "dequeue on empty returns false");
    CHECK(out == sentinel,            "dequeue on empty leaves *out untouched");
    CHECK(peek(&q, &out) == false,    "peek on empty returns false");
    CHECK(q.count == 0,               "count stays 0");

    queue_free(&q);
    queue_free(&q);                   /* must be safe twice */
    CHECK(q.count == 0,               "queue_free is idempotent");
}

static void test_fifo_order(void)
{
    printf("ordering — first in, first out\n");
    queue q;
    queue_init(&q);

    for (int i = 1; i <= 5; i++) {
        CHECK(enqueue(&q, i * 10), "enqueue succeeds");
    }
    CHECK(q.count == 5, "count is 5 after five enqueues");

    int out = 0;
    CHECK(peek(&q, &out) && out == 10, "peek returns the oldest element");
    CHECK(q.count == 5,                "peek does not remove");

    for (int i = 1; i <= 5; i++) {
        out = 0;
        CHECK(dequeue(&q, &out) && out == i * 10, "dequeue returns them in order");
    }
    CHECK(q.count == 0, "count is 0 after draining");

    queue_free(&q);
}

static void test_drain_and_refill(void)
{
    /* This is the one that matters. Emptying the queue and then enqueueing
     * again is what exposes a stale tail pointer: if dequeue freed the last
     * node without clearing tail, the enqueue below writes into freed memory
     * and AddressSanitizer stops the program with a use-after-free. A test
     * that only drains the queue would pass with that bug still present. */
    printf("boundary 2 — drain to empty, then enqueue again (stale tail)\n");
    queue q;
    queue_init(&q);

    int out = 0;
    CHECK(enqueue(&q, 1),                    "enqueue 1");
    CHECK(dequeue(&q, &out) && out == 1,     "dequeue 1");
    CHECK(q.count == 0,                      "queue is empty again");
    CHECK(dequeue(&q, &out) == false,        "second dequeue reports empty");

    CHECK(enqueue(&q, 2),                    "enqueue 2 after emptying");
    CHECK(enqueue(&q, 3),                    "enqueue 3");
    CHECK(dequeue(&q, &out) && out == 2,     "still FIFO after refill");
    CHECK(dequeue(&q, &out) && out == 3,     "and again");
    CHECK(q.count == 0,                      "drained");

    queue_free(&q);
}

static void test_free_releases_everything(void)
{
    /* Nothing here can fail visibly. LeakSanitizer reports the failure at
     * exit if queue_free missed a node — which is exactly boundary (3). */
    printf("boundary 3 — queue_free on a non-empty queue (LeakSanitizer decides)\n");
    queue q;
    queue_init(&q);
    for (int i = 0; i < 1000; i++) {
        if (!enqueue(&q, i)) {
            printf("  FAIL  allocation failed at %d\n", i);
            g_failures++;
            break;
        }
    }
    CHECK(q.count == 1000, "1000 elements queued");
    queue_free(&q);
    CHECK(q.count == 0,    "queue_free resets count");
    printf("  ..    if 1000 nodes leaked, the sanitizer reports it at exit\n");
}

int main(void)
{
    printf("d3 — queue via singly linked list\n\n");

    test_empty_queue();          printf("\n");
    test_fifo_order();           printf("\n");
    test_drain_and_refill();     printf("\n");
    test_free_releases_everything();

    printf("\n%d/%d checks passed\n", g_checks - g_failures, g_checks);
    if (g_failures != 0) {
        printf("\n%d check(s) failed. If every one failed, the implementation\n"
               "is still stubbed out — that is the exercise, go write it.\n",
               g_failures);
        return 1;
    }
    printf("d3 PASS\n");
    return 0;
}

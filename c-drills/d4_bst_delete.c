/*
 * d4_bst_delete.c — deleting from a binary search tree, including the root.
 *
 * ┌───────────────────────────────────────────────────────────────────────┐
 * │  THE IMPLEMENTATION IS YOURS TO WRITE. Everything below the marker    │
 * │  "YOUR IMPLEMENTATION STARTS HERE" is stubbed out on purpose.         │
 * │                                                                       │
 * │  The ritual, in order, and the order is the point:                    │
 * │    1. On paper, nothing open, 25 minutes. The longest box in the      │
 * │       series, because this is the one with four shapes and one of     │
 * │       them has a sub-case.                                            │
 * │    2. Dry-run two cases by hand. One MUST be deleting a node whose    │
 * │       in-order successor is not its right child and has a right       │
 * │       child of its own. Draw the pointers. That case is the drill.    │
 * │    3. Type it in. Record how many compile errors you got, unedited,   │
 * │       in SCORECARD.md, classified syntax / type / logic.              │
 * │    4. `make test` clean, sanitizers included.                         │
 * └───────────────────────────────────────────────────────────────────────┘
 *
 * Three questions you must be able to answer out loud when this is done:
 *
 *   1. Why does bst_delete RETURN the new root instead of taking `bst_node_t
 *      *root` and fixing it in place? Write down what the caller's variable
 *      holds after `delete_in_place(root, root->value)` — that is the bug.
 *   2. In the two-children case you replace the value with the in-order
 *      successor's. Why is that successor's LEFT child always NULL, and which
 *      of the four shapes does that turn the second deletion into?
 *   3. Where exactly is the use-after-free waiting? Name the line you would
 *      write if you freed the node before deciding what to return.
 *
 * Where this connects to the project
 * ----------------------------------
 * Nowhere, and that is deliberate — it is the one drill in the set that is not
 * lifted out of this repository. It is here because it is a verified question
 * from a real second-round interview, and because the other seven drills are
 * all byte-layout problems. A series that only ever tests one kind of thinking
 * measures one kind of thinking.
 *
 * What it shares with the rest is the failure mode: this is pointer surgery
 * with no compiler in the loop, and the way it goes wrong is silently. A tree
 * that has lost a subtree still prints in sorted order. That is why the tests
 * below count nodes as well as reading them, and why the traversal is compared
 * against the full expected sequence rather than checked for sortedness.
 *
 * ★ The trap, stated plainly so you can watch for it
 * --------------------------------------------------
 * Four shapes, and everyone gets the first three:
 *
 *     leaf              unlink from the parent, free
 *     one child         hand the child to the parent, free
 *     no such value     change nothing
 *     TWO CHILDREN      <- this one
 *
 * With two children the standard move is: find the smallest value in the right
 * subtree (the in-order successor), copy it into this node, then delete THAT
 * node from the right subtree. The bug is in the second half. The successor
 * usually is not the right child — you walk left until you cannot — and it can
 * have a right child of its own. Unlink it without re-parenting that right
 * child and the subtree under it silently disappears.
 *
 * The tree below is built so that case is unavoidable, twice:
 *
 *                       50
 *                   ┌────┴────┐
 *                  30         70
 *                ┌──┴──┐    ┌──┴──┐
 *               20    40   60    80
 *                            └─65   └─90
 *
 *   delete 50 -> successor is 60, which is NOT 50's right child (70) and HAS
 *                a right child (65). Lose it and 65 vanishes.
 *   delete 70 -> successor is 80, which IS 70's right child and HAS a right
 *                child (90). This is the sub-case, and it is the one that
 *                breaks implementations that special-case "successor is the
 *                right child" by writing `node->right = NULL`.
 *
 * A traversal that has lost 65 is still sorted. Only counting catches it.
 *
 * Boundaries this must survive
 * ----------------------------
 *   (1) delete a leaf, a one-child node, and a two-children node
 *   (2) delete the ROOT, repeatedly, until the tree is empty and root is NULL
 *   (3) delete a value that is not in the tree -> tree and count unchanged
 *   (4) delete from an empty tree -> NULL, no crash
 *   (5) every node allocated is freed — LeakSanitizer is on and will say so
 *   (6) no node is read after it is freed — AddressSanitizer will say so
 *   (7) inserting a duplicate changes nothing
 *
 * Build and run:
 *     make d4_bst_delete && ./d4_bst_delete
 */

#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct bst_node {
    int value;
    struct bst_node *left;
    struct bst_node *right;
} bst_node_t;

/* ── contract ───────────────────────────────────────────────────────────────
 *
 * bst_insert(root, value)
 *     Inserts value. Returns the root of the resulting tree, which is `root`
 *     unless the tree was empty. A value already present is not inserted
 *     twice and is not an error. Returns NULL only if allocation fails, and
 *     the tests do not exercise that.
 *
 * bst_delete(root, value, deleted_out)
 *     Removes at most one node holding value. Returns the root of the
 *     resulting tree, which may be NULL and may differ from `root` — that
 *     return value is the whole reason for question 1.
 *
 *     *deleted_out is set to 1 if a node was removed and 0 if the value was
 *     not present. deleted_out may be NULL, in which case nothing is written.
 *
 *     Uses the IN-ORDER SUCCESSOR for the two-children case. The tests check
 *     the resulting shape, so the in-order predecessor — equally correct as an
 *     algorithm — will fail them. The point of pinning one is that a drill
 *     whose expected output depends on a choice you did not write down is a
 *     drill you cannot mark.
 *
 * bst_free(root)
 *     Frees every node. NULL is not an error.
 *
 * bst_inorder(root, out, cap)
 *     Writes the values in ascending order into out. Returns the number
 *     written. Returns (size_t)-1 and writes nothing if out is NULL, or if the
 *     tree holds more than cap values — do not write cap of them and truncate,
 *     because a caller that cannot tell a full buffer from a complete answer
 *     is the bug this repository keeps finding.
 *
 * bst_count(root)
 *     How many nodes. NULL is 0. This exists so the tests can tell "the
 *     traversal is still sorted" from "the tree is still whole", which is the
 *     distinction the trap above hides in.
 */

bst_node_t *bst_insert(bst_node_t *root, int value);
bst_node_t *bst_delete(bst_node_t *root, int value, int *deleted_out);
void        bst_free(bst_node_t *root);
size_t      bst_inorder(const bst_node_t *root, int *out, size_t cap);
size_t      bst_count(const bst_node_t *root);

/* ══════════════════ YOUR IMPLEMENTATION STARTS HERE ═══════════════════════ */

bst_node_t *bst_insert(bst_node_t *root, int value)
{
    (void)root;
    (void)value;
    /* TODO */
    return NULL;
}

bst_node_t *bst_delete(bst_node_t *root, int value, int *deleted_out)
{
    (void)root;
    (void)value;
    (void)deleted_out;
    /* TODO */
    return NULL;
}

void bst_free(bst_node_t *root)
{
    (void)root;
    /* TODO */
}

size_t bst_inorder(const bst_node_t *root, int *out, size_t cap)
{
    (void)root;
    (void)out;
    (void)cap;
    /* TODO */
    return (size_t)-1;
}

size_t bst_count(const bst_node_t *root)
{
    (void)root;
    /* TODO */
    return 0;
}

/* ══════════════════ YOUR IMPLEMENTATION ENDS HERE ═════════════════════════ */

/* ── tests ────────────────────────────────────────────────────────────────── */

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

/* The tree drawn at the top, inserted in an order that produces exactly that
 * shape. Insert order matters here and is part of the fixture. */
static const int SHAPE[] = { 50, 30, 70, 20, 40, 60, 80, 65, 90 };
#define SHAPE_N ((size_t)(sizeof SHAPE / sizeof SHAPE[0]))

static bst_node_t *build(void)
{
    bst_node_t *root = NULL;
    for (size_t i = 0; i < SHAPE_N; i++) {
        root = bst_insert(root, SHAPE[i]);
    }
    return root;
}

/* Compare a traversal against an exact expected sequence. Sortedness alone is
 * not enough: a tree that has silently lost a subtree is still sorted. */
static int inorder_is(const bst_node_t *root, const int *want, size_t n)
{
    /* Pre-filled, and not only to keep -Wmaybe-uninitialized quiet while the
     * implementation below is still a stub. A traversal that writes nothing
     * and reports the right count would compare equal against a buffer that
     * happened to hold the expected values; -1 is not one of them. */
    int got[32];
    for (size_t i = 0; i < sizeof got / sizeof got[0]; i++) {
        got[i] = -1;
    }
    size_t cap = sizeof got / sizeof got[0];
    /* Bound the expectation before anything reads got. Without it, the only
     * way past the guard below while the implementation is still a stub is
     * n == (size_t)-1, and gcc says so: -Wstringop-overread on a memcmp of
     * 18,446,744,073,709,551,612 bytes. It is right, and a helper that cannot
     * state its own limit deserved the warning. */
    if (n > cap) {
        printf("        the expected sequence is %zu values, longer than the "
               "%zu-value buffer\n", n, cap);
        return 0;
    }
    size_t k = bst_inorder(root, got, cap);
    if (k != n) {
        printf("        traversal returned %zu values, expected %zu\n", k, n);
        return 0;
    }
    if (n != 0 && memcmp(got, want, n * sizeof(int)) != 0) {
        printf("        got     :");
        for (size_t i = 0; i < k; i++) printf(" %d", got[i]);
        printf("\n        expected:");
        for (size_t i = 0; i < n; i++) printf(" %d", want[i]);
        printf("\n");
        return 0;
    }
    return 1;
}

static void test_build(void)
{
    printf("the tree, before anything is removed\n");

    bst_node_t *root = build();
    static const int all[] = { 20, 30, 40, 50, 60, 65, 70, 80, 90 };

    CHECK(root != NULL, "the tree is not empty");
    CHECK(root != NULL && root->value == 50, "the root is 50");
    CHECK(bst_count(root) == 9, "nine nodes");
    CHECK(inorder_is(root, all, 9), "in-order is 20 30 40 50 60 65 70 80 90");

    root = bst_insert(root, 40);
    CHECK(bst_count(root) == 9, "inserting a duplicate changes nothing");

    bst_free(root);
}

static void test_the_three_easy_shapes(void)
{
    printf("a leaf, a node with one child, and a value that is not there\n");

    bst_node_t *root = build();
    int done = 99;

    static const int no20[] = { 30, 40, 50, 60, 65, 70, 80, 90 };
    root = bst_delete(root, 20, &done);
    CHECK(done == 1, "deleting the leaf 20 reports success");
    CHECK(bst_count(root) == 8, "  eight nodes remain");
    CHECK(inorder_is(root, no20, 8), "  and 20 is the only thing missing");

    /* 30 now has one child (40). */
    static const int no30[] = { 40, 50, 60, 65, 70, 80, 90 };
    root = bst_delete(root, 30, &done);
    CHECK(done == 1, "deleting 30, which now has one child, reports success");
    CHECK(bst_count(root) == 7, "  seven nodes remain");
    CHECK(inorder_is(root, no30, 7), "  and its child 40 was kept");

    done = 99;
    root = bst_delete(root, 12345, &done);
    CHECK(done == 0, "deleting a value that is not there reports failure");
    CHECK(bst_count(root) == 7, "  and removes nothing");
    CHECK(inorder_is(root, no30, 7), "  and changes nothing");

    root = bst_delete(root, 40, NULL);
    CHECK(bst_count(root) == 6, "a NULL deleted_out is allowed");

    bst_free(root);
}

/* ★ The drill. Both two-children deletions have a successor with a right
 * child, one of them reached by walking left and one of them not. */
static void test_two_children(void)
{
    printf("★ two children — the successor's right subtree must survive\n");

    bst_node_t *root = build();
    int done = 0;

    /* 50's successor is 60: not 50's right child, and 60 has a right child 65.
     * Unlink 60 without re-parenting 65 and 65 disappears — from a tree that
     * still traverses in sorted order. */
    static const int no50[] = { 20, 30, 40, 60, 65, 70, 80, 90 };
    root = bst_delete(root, 50, &done);
    CHECK(done == 1, "deleting the root 50, which has two children");
    CHECK(root != NULL && root->value == 60,
          "  the root now holds 60, the in-order successor");
    CHECK(bst_count(root) == 8, "  EIGHT nodes remain — 65 was not lost");
    CHECK(inorder_is(root, no50, 8), "  and the traversal proves which one");

    /* 70's successor is 80, which IS 70's right child, and 80 has a right
     * child 90. The sub-case that breaks `node->right = NULL`. */
    static const int no70[] = { 20, 30, 40, 60, 65, 80, 90 };
    root = bst_delete(root, 70, &done);
    CHECK(done == 1, "deleting 70, whose successor IS its right child");
    CHECK(bst_count(root) == 7, "  seven nodes remain — 90 was not lost");
    CHECK(inorder_is(root, no70, 7), "  and 90 is still in the traversal");

    bst_free(root);
}

static void test_delete_the_root_until_empty(void)
{
    printf("delete the root nine times — the caller's pointer has to move\n");

    bst_node_t *root = build();
    size_t remaining = 9;

    while (root != NULL) {
        int v = root->value;
        int done = 0;
        root = bst_delete(root, v, &done);
        remaining--;
        if (!done) {
            printf("        deleting the root value %d reported failure\n", v);
            break;
        }
        if (bst_count(root) != remaining) {
            printf("        after deleting %d, %zu nodes remain, expected %zu\n",
                   v, bst_count(root), remaining);
            break;
        }
    }
    CHECK(root == NULL, "the tree is empty");
    CHECK(remaining == 0, "  and exactly nine deletions emptied it");
    CHECK(bst_count(NULL) == 0, "bst_count(NULL) is 0");

    int done = 99;
    bst_node_t *still = bst_delete(NULL, 1, &done);
    CHECK(still == NULL && done == 0, "deleting from an empty tree is not a crash");

    bst_free(NULL);
    bst_free(root);
}

static void test_inorder_refuses_to_truncate(void)
{
    printf("a full buffer is not a complete answer\n");

    bst_node_t *root = build();
    int small[4] = { -1, -1, -1, -1 };

    CHECK(bst_inorder(root, small, 4) == (size_t)-1,
          "nine values into a four-value buffer is refused");
    CHECK(small[0] == -1, "  and nothing was written");
    CHECK(bst_inorder(root, NULL, 9) == (size_t)-1, "a NULL destination is refused");
    CHECK(bst_inorder(NULL, small, 4) == 0, "an empty tree writes nothing and says 0");

    bst_free(root);
}

int main(void)
{
    printf("d4 — deleting from a BST, including the root\n\n");

    test_build();                        printf("\n");
    test_the_three_easy_shapes();        printf("\n");
    test_two_children();                 printf("\n");
    test_delete_the_root_until_empty();  printf("\n");
    test_inorder_refuses_to_truncate();

    printf("\n%d/%d checks passed\n", g_checks - g_failures, g_checks);
    if (g_failures != 0) {
        printf("\n%d check(s) failed. If every one failed, the implementation\n"
               "is still stubbed out — that is the exercise, go write it.\n",
               g_failures);
        return 1;
    }
    printf("\nNothing above proves you freed anything. LeakSanitizer does, at\n"
           "exit, and it is on. A silent exit here is the fourth boundary.\n");
    printf("d4 PASS\n");
    return 0;
}

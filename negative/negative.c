/* negative/negative.c — the runner the three negative tests share.
 *
 * There is one interesting function here and it is neg_report(). Everything
 * else is printing.
 *
 * What makes it interesting is that it is asked to decide two different
 * questions with the same code path, because `make test` runs every binary the
 * same way and must not have to know which kind it is looking at:
 *
 *   the correct build        every case returns the code it expects
 *   a defect build           the cases that STOPPED returning what they
 *                            expect are EXACTLY the ones the file predicted,
 *                            neither fewer nor more
 *
 * "Neither fewer nor more" is the whole point and it is the half that is easy
 * to leave out. Fewer means the suite cannot see the defect it was written
 * for. More means two cases are being refused by the same check and the suite
 * is reporting more coverage than it has — docs/roadmap.md standing rule 13,
 * which was written on 2026-08-31 after exactly that was found by hand in a
 * suite built to demonstrate the rule.
 */

#include "negative.h"

#include <stdio.h>
#include <string.h>

const char *neg_status_text(neg_status_t status)
{
    switch (status) {
    case NEG_OK:                             return "NEG_OK";
    case NEG_ERR_WINDOW_OFFSET_PAST_END:     return "NEG_ERR_WINDOW_OFFSET_PAST_END";
    case NEG_ERR_WINDOW_LENGTH_PAST_END:     return "NEG_ERR_WINDOW_LENGTH_PAST_END";
    case NEG_ERR_WINDOW_SUM_OVERFLOWS:       return "NEG_ERR_WINDOW_SUM_OVERFLOWS";
    case NEG_ERR_WINDOW_ZERO_LENGTH:         return "NEG_ERR_WINDOW_ZERO_LENGTH";
    case NEG_ERR_FIELD_LONGER_THAN_MESSAGE:  return "NEG_ERR_FIELD_LONGER_THAN_MESSAGE";
    case NEG_ERR_FIELD_LONGER_THAN_BUFFER:   return "NEG_ERR_FIELD_LONGER_THAN_BUFFER";
    case NEG_ERR_FIELD_NOT_TERMINATED:       return "NEG_ERR_FIELD_NOT_TERMINATED";
    case NEG_ERR_FIELD_WRITE_ESCAPED_BUFFER: return "NEG_ERR_FIELD_WRITE_ESCAPED_BUFFER";
    case NEG_ERR_TRANSCRIPT_MISSING_MESSAGE: return "NEG_ERR_TRANSCRIPT_MISSING_MESSAGE";
    case NEG_ERR_TRANSCRIPT_WRONG_ORDER:     return "NEG_ERR_TRANSCRIPT_WRONG_ORDER";
    case NEG_ERR_TRANSCRIPT_LENGTH_MISMATCH: return "NEG_ERR_TRANSCRIPT_LENGTH_MISMATCH";
    }
    /* No default: above, so -Werror=switch catches a code added to the enum
     * and not named here. This line is for a value that was never in the enum,
     * which is a different mistake and deserves a different answer. */
    return "NEG_STATUS_NOT_IN_THIS_ENUM";
}

static bool in_list(const int *list, int want)
{
    if (list == NULL) {
        return false;
    }
    for (size_t i = 0; list[i] >= 0; i++) {
        if (list[i] == want) {
            return true;
        }
    }
    return false;
}

static size_t list_len(const int *list)
{
    size_t n = 0;
    if (list != NULL) {
        while (list[n] >= 0) {
            n++;
        }
    }
    return n;
}

int neg_report(const char *suite,
               const char *class_name,
               const neg_case_t *cases,
               const neg_status_t *got,
               size_t ncases,
               int defect_id,
               const neg_defect_t *defects,
               size_t ndefects)
{
    const neg_defect_t *defect = NULL;

    if (defect_id != 0) {
        if (defect_id < 1 || (size_t)defect_id > ndefects) {
            printf("%s: built with -DNEG_DEFECT=%d, but this file declares "
                   "%zu defect variant(s)\n", suite, defect_id, ndefects);
            return 1;
        }
        defect = &defects[defect_id - 1];
    }

    printf("\n%s — %s\n", suite, class_name);
    if (defect != NULL) {
        printf("  build   : DEFECT %d — %s\n", defect_id, defect->what);
        printf("  asserts : exactly %zu case(s) must stop matching\n",
               list_len(defect->must_move));
    } else {
        printf("  build   : the implementation this file argues is correct\n");
        printf("  asserts : all %zu case(s) return the code they expect\n", ncases);
    }
    printf("  ran     : %zu of %zu case(s)\n", ncases, ncases);
    printf("\n");

    /* The per-case table. Printed in full in both directions, because a reader
     * looking at a failure needs to see what the OTHER cases did — that is
     * what tells them whether one check moved or the implementation fell
     * over. */
    size_t moved_count = 0, unexpected = 0, missing = 0, wrong_severity = 0;
    for (size_t i = 0; i < ncases; i++) {
        bool matched  = (got[i] == cases[i].expect);
        bool declared = (defect != NULL) && in_list(defect->must_move, (int)i);

        /* "Accepted" means the case expected a refusal and got NEG_OK. That is
         * the vulnerability; a refusal through the wrong door is not. */
        bool accepted      = (cases[i].expect != NEG_OK) && (got[i] == NEG_OK);
        bool must_accept   = (defect != NULL) && in_list(defect->must_accept, (int)i);

        const char *mark;
        if (matched && !declared) {
            mark = "  ok   ";
        } else if (!matched && declared) {
            mark = accepted ? " ACCEPT" : " MOVED ";   /* predicted, and it happened */
        } else if (!matched && !declared) {
            mark = "**BAD**";   /* moved, and nothing predicted it */
            unexpected++;
        } else {
            mark = "**MISS*";   /* predicted to move and did not */
            missing++;
        }

        if (!matched) {
            moved_count++;
        }
        if (declared && !matched && (accepted != must_accept)) {
            wrong_severity++;
        }

        printf("  [%zu] %s  %-34s\n", i, mark, cases[i].name);
        printf("             expected %s\n", neg_status_text(cases[i].expect));
        if (!matched) {
            printf("             got      %s%s\n", neg_status_text(got[i]),
                   accepted ? "   <-- the input was ACCEPTED" : "");
            if (declared && accepted != must_accept) {
                printf("             but this defect declared the case would %s\n",
                       must_accept ? "be ACCEPTED, and it was only refused"
                                   : "be REFUSED, and it was ACCEPTED");
            }
        }
    }
    printf("\n");

    if (defect == NULL) {
        if (moved_count == 0) {
            printf("  PASS  %zu case(s), every one through the door it named\n", ncases);
            return 0;
        }
        printf("  FAIL  %zu of %zu case(s) did not return the expected code\n",
               moved_count, ncases);
        return 1;
    }

    /* Defect build. Four distinct answers, and only one of them is success. */
    if (unexpected == 0 && missing == 0 && wrong_severity == 0) {
        size_t nacc = list_len(defect->must_accept);
        printf("  DEFECT CAUGHT  by exactly the %zu case(s) this file predicted,\n"
               "                 and by no others — so those case(s) are the only\n"
               "                 thing standing between this mistake and a green run\n",
               list_len(defect->must_move));
        if (nacc > 0) {
            printf("                 %zu of them ACCEPTED the input, which is the\n"
                   "                 difference between a mislabelled refusal and a\n"
                   "                 hole\n", nacc);
        } else {
            printf("                 none of them ACCEPTED the input: this mistake\n"
                   "                 mislabels a refusal, it does not open a hole\n");
        }
        return 0;
    }
    if (wrong_severity > 0 && unexpected == 0 && missing == 0) {
        printf("  WRONG SEVERITY %zu case(s) moved as predicted but not in the\n"
               "                 predicted direction. A refusal through the wrong\n"
               "                 door and an accepted input are not the same event.\n",
               wrong_severity);
        return 1;
    }
    if (missing > 0 && unexpected == 0) {
        printf("  DEFECT MISSED  %zu predicted case(s) still returned the expected\n"
               "                 code. The suite cannot see the mistake it was\n"
               "                 written to demonstrate (standing rule 11).\n", missing);
        return 1;
    }
    if (unexpected > 0 && missing == 0) {
        printf("  WRONG DOOR     %zu case(s) moved that were not predicted to. Either\n"
               "                 the prediction is wrong or the cases are not\n"
               "                 discriminating (standing rule 13).\n", unexpected);
        return 1;
    }
    printf("  WRONG DOOR     %zu unpredicted case(s) moved and %zu predicted case(s)\n"
           "                 did not. The defect is not the one the file describes.\n",
           unexpected, missing);
    return 1;
}

int neg_handled_args(int argc, char **argv,
                     const neg_case_t *cases, size_t ncases,
                     const neg_defect_t *defects, size_t ndefects)
{
    if (argc < 2) {
        return 0;
    }
    if (strcmp(argv[1], "--defects") == 0) {
        printf("%zu\n", ndefects);
        return 1;
    }
    if (strcmp(argv[1], "--list") == 0) {
        for (size_t i = 0; i < ncases; i++) {
            printf("case   %zu  %-34s  %s\n", i, cases[i].name,
                   neg_status_text(cases[i].expect));
        }
        for (size_t d = 0; d < ndefects; d++) {
            printf("defect %zu  %s\n", d + 1, defects[d].what);
            printf("          must move  :");
            for (size_t i = 0; defects[d].must_move[i] >= 0; i++) {
                printf(" %d", defects[d].must_move[i]);
            }
            printf("\n          must accept:");
            if (list_len(defects[d].must_accept) == 0) {
                printf(" (none — this mistake mislabels, it does not open a hole)");
            } else {
                for (size_t i = 0; defects[d].must_accept[i] >= 0; i++) {
                    printf(" %d", defects[d].must_accept[i]);
                }
            }
            printf("\n");
        }
        return 1;
    }
    return 0;
}

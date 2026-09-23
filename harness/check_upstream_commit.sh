#!/usr/bin/env bash
#
# harness/check_upstream_commit.sh — does this commit satisfy the project it is
# about to be sent to?
#
#     bash harness/check_upstream_commit.sh ~/spdm-lab/work/spdm-emu-pr
#     bash harness/check_upstream_commit.sh --self-test
#
# Why this is a script and not a checklist
# ----------------------------------------
# `docs/upstream/0001-corim-verify.md` has a checklist, and a checklist is a
# discipline. On 2026-09-13 the discipline missed something: the commit prepared
# for `DMTF/spdm-emu` carried no `Assisted-by:` trailer, which that project's
# CONTRIBUTING.md requires of any AI-assisted contribution. It was found by
# being asked a question about paperwork, not by the checklist beside the
# commit.
#
# The rule that makes this worth automating rather than re-reading:
#
#   ★ The contribution rules of a project you have not contributed to are not
#     the ones you already know. This repository's own commits carry
#     `Co-Authored-By: Claude …`, and DMTF's CONTRIBUTING.md **forbids naming an
#     AI in Co-authored-by**. A convention that is correct here is a violation
#     there, and nothing about writing the commit would have said so.
#
# Where the rules come from
# -------------------------
# Read out of the target repository's own CONTRIBUTING.md, not from memory and
# not from this project's week plan. The digest of the file the rules were read
# from is recorded below, and this script says so when the target's copy differs
# — because a rule set that has moved is exactly the thing a returning
# contributor would not re-read.
#
#   DMTF/spdm-emu CONTRIBUTING.md
#   sha256 52b95edb12676cb51d1d3e681b6ec266fdfd7abe9c782c9a1be47ea81d1da3cc
#   added   b569bc0, 2026-06-05, "Add CONTRIBUTING.md with DCO and AI
#           attribution policy"
#   read at ea77f25 (upstream main, 2026-09-12) and byte-identical in the
#           pinned tree at 5f01d2f, so this is not a rule that arrived after
#           the captures did.
#
# What it says, in the three lines that decide a commit:
#
#   * DCO sign-off on every commit, real name, reachable email, **matching the
#     commit author**. There is NO contributor licence agreement — the word does
#     not appear in the file. That is the opposite of OpenBMC, where a CLA goes
#     to manager@lfprojects.org and is separate from the DCO.
#   * An AI must NOT be named in `Signed-off-by` (the DCO is a certification
#     only a human can make) or in `Co-authored-by` (authorship rests with the
#     humans responsible).
#   * An AI-assisted commit MUST carry `Assisted-by: AGENT_NAME:MODEL_VERSION`.
#     The maintainers use it on their own merges — `Assisted-by: Claude
#     Code:claude-sonnet-5` on #519.
#
# ── the OpenBMC profile, added 2026-09-18 ──────────────────────────────────
#
# Written when there was a real commit to check it against, which is why it was
# not written in week one: a check whose failure mode has never fired is what
# `docs/roadmap.md` standing rule 15 is about.
#
#   openbmc/docs CONTRIBUTING.md
#   sha256 e27c7768eedaeded3823727087a6e8e6c7034bfb91c5a60deb7305c108480301
#   read 2026-09-18 from https://github.com/openbmc/docs, master
#
# What it says that DMTF's does not, and the reverse:
#
#   * **Gerrit, not a pull request.** `git push … HEAD:refs/for/main` — and for
#     `openbmc/spdm` it is `main`, not `master`: `git ls-remote --heads`
#     returns exactly one head and it is `refs/heads/main`. That is worth
#     checking rather than assuming, because most OpenBMC repositories are on
#     `master` and this project's own `docs/upstream/README.md` recorded the
#     rehearsal command with `master` in it.
#   * **A `Change-Id` trailer**, written by the commit-msg hook Gerrit serves.
#     Without it the push is rejected outright. There is no equivalent at DMTF.
#   * **A CLA**, an Individual Contributor Licence Agreement to
#     manager@lfprojects.org, separate from the DCO and covering every OpenBMC
#     repository. This script cannot see its state; it says so rather than
#     passing silently.
#   * **50/72, a Signed-off-by with a full real name, and a statement of how it
#     was tested.** Same shape as DMTF's, and the CONTRIBUTING.md is explicit
#     that "xXthorXx" and a bare given name are not acceptable.
#   * ★ **An AI policy exists, and it is in review rather than merged.** This
#     header said "No AI policy at all" until 2026-09-23, on the evidence that
#     the word does not appear in CONTRIBUTING.md. A reviewer on 94773 pointed
#     at openbmc/docs 89452, `coding-assistants.md`, 404 on master — a grep
#     over a merged file could not have seen it. What it says:
#       - attribution SHOULD be `Assisted-by: AGENT_NAME:MODEL_VERSION`, and
#         the word is under dispute in that review ("should" or "can");
#       - "AI agents MUST NOT add Signed-off-by tags". That rule is about WHO
#         TYPED the line, and no check on a finished commit can see who typed
#         anything. So it is printed below as something this script does not
#         know, and the prepared commit is left for the human to sign.
#     This script still REPORTS the disclosure rather than requiring it: the
#     policy is not merged, and a check that enforced an unmerged rule would
#     teach the wrong rule set for the next repository just as surely as one
#     that invented a rule.
#
# Exit code 0 = ready to send.

set -uo pipefail
_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${_HERE}/lib/common.sh"
set +e

CONTRIB_SHA256=52b95edb12676cb51d1d3e681b6ec266fdfd7abe9c782c9a1be47ea81d1da3cc

FAILED=0
ok()   { printf '  \033[32mok\033[0m    %s\n' "$*"; }
no()   { printf '  \033[31mFAIL\033[0m  %s\n' "$*"; FAILED=1; }
skip() { printf '  \033[33m--\033[0m    %s\n' "$*"; }

# ---------------------------------------------------------------- rules -----

# -- file modes, which both profiles share ------------------------------------
#
# ★ 2026-09-23. openbmc/spdm 94773 patchset 1 added README.md as 100755. The
# file had been copied out of /mnt/c, where DrvFs reports every file as
# executable, into a tree with core.filemode=true, and `git add` recorded what
# it was given. Thirteen mechanical checks, two linters and this script passed
# it. Gerrit prints the mode in the file list, which a reviewer reads before
# the diff.
#
# The rule is lintian's: an executable file has to be something the kernel can
# execute, which for a text file means a #! line. The first two bytes are read
# through a process substitution rather than `| head`, so that no branch here
# is decided by a pipeline whose producer can be killed.
check_file_modes() {   # check_file_modes <repo-dir>
    local dir="$1" line rest mode sha path first bad=0 n=0
    while IFS= read -r line; do
        # :<old mode> <new mode> <old sha> <new sha> <status>TAB<path>
        rest="${line#:}"
        mode="$(cut -d' ' -f2 <<<"$rest")"
        sha="$(cut -d' ' -f4 <<<"$rest")"
        path="${line#*$'\t'}"
        n=$((n + 1))
        [ "$mode" = 100755 ] || continue
        first="$(head -c 2 < <(git -C "$dir" cat-file blob "$sha"))"
        if [ "$first" != '#!' ]; then
            no "$path is executable (100755) and does not start with #! — chmod 644, git add, amend"
            bad=1
        fi
    done < <(git -C "$dir" diff-tree -r --root --no-commit-id --diff-filter=AMT HEAD)
    if [ "$bad" = 0 ]; then
        ok "no file in this commit is executable without a #! line ($n file(s))"
    fi
}

check_commit() {   # check_commit <repo-dir>
    local dir="$1" msg author sob subj long n
    msg="$(git -C "$dir" log -1 --format='%B')"
    author="$(git -C "$dir" log -1 --format='%an <%ae>')"
    sob="$(printf '%s\n' "$msg" | grep -i '^signed-off-by:')"
    subj="$(git -C "$dir" log -1 --format='%s')"

    printf '  commit  %s\n  author  %s\n\n' \
        "$(git -C "$dir" log -1 --format='%h %s')" "$author"

    # -- the DCO --------------------------------------------------------------
    n="$(printf '%s\n' "$msg" | grep -ci '^signed-off-by:')"
    if [ "$n" = 1 ]; then ok "exactly one Signed-off-by"
    else no "$n Signed-off-by line(s); DCO wants exactly one"; fi

    if [ "$sob" = "Signed-off-by: $author" ]; then
        ok "Signed-off-by matches the commit author exactly"
    else
        no "Signed-off-by is '$sob' and the author is '$author' — DCO checking compares them"
    fi

    case "$sob" in
        *"<"*"@"*"."*">"*) ok "sign-off carries a reachable-looking address" ;;
        *) no "sign-off has no email address" ;;
    esac

    # -- AI attribution -------------------------------------------------------
    #
    # Word boundaries, not substrings, and the reason is worth keeping: the
    # first version of this test used the bare pattern `ai`, which matched
    # "gmail" in the author's own address and reported a compliant commit as a
    # violation. A check that fails for a reason unrelated to what it checks is
    # worse than no check, because the failure is specific, legible and wrong.
    local ai_re='(^|[^[:alnum:]])(claude|ai|assistant|bot|anthropic|copilot|gpt|gemini|llm)([^[:alnum:]]|$)'

    # Here-strings rather than `printf … | grep -q`, and not for style.
    # `grep -q` exits at the first match, the producer gets SIGPIPE, and with
    # `pipefail` the branch is decided by 141 rather than by the match. This
    # file was written with four of them, and verify_repo.sh's SIGPIPE guard —
    # added 2026-09-10 after that shape inverted two branches elsewhere in
    # harness/ — refused it on the first run. A here-string is a redirection,
    # with no second process to lose.
    if grep -qiE "$ai_re" <<<"$sob"; then
        no "an AI appears to be named in Signed-off-by — CONTRIBUTING.md forbids it; the DCO is a human certification"
    else
        ok "no AI named in Signed-off-by"
    fi

    if grep -qi '^co-authored-by' <<<"$msg"; then
        no "Co-authored-by present. If it names an AI this violates CONTRIBUTING.md; note that THIS repository's own commits carry one and it must not travel"
    else
        ok "no Co-authored-by"
    fi

    if grep -q '^Assisted-by: [^:]\+:[^ ]\+' <<<"$msg"; then
        ok "Assisted-by present: $(printf '%s\n' "$msg" | grep '^Assisted-by:' | head -1)"
    else
        no "no Assisted-by: AGENT_NAME:MODEL_VERSION. If no AI assisted this commit, delete this check rather than the trailer"
    fi

    # -- the shape upstream reviewers read first ------------------------------
    if [ "${#subj}" -le 50 ]; then ok "subject ${#subj} chars"
    else no "subject ${#subj} chars, over 50"; fi

    long="$(git -C "$dir" log -1 --format='%b' | awk 'length > 72 {c++} END {print c+0}')"
    if [ "$long" = 0 ]; then ok "no body line over 72 chars"
    else no "$long body line(s) over 72 chars"; fi

    if grep -q '^Tested:' <<<"$msg"; then
        ok "Tested: present — and it is yours to have actually run"
    else
        no "no Tested: line"
    fi

    check_file_modes "$dir"

    if [ "$(git -C "$dir" status --porcelain | wc -l)" = 0 ]; then
        ok "working tree clean"
    else
        no "uncommitted changes in the tree"
    fi
}

check_commit_openbmc() {   # check_commit_openbmc <repo-dir>
    local dir="$1" msg author sob subj long n
    msg="$(git -C "$dir" log -1 --format='%B')"
    author="$(git -C "$dir" log -1 --format='%an <%ae>')"
    sob="$(printf '%s\n' "$msg" | grep -i '^signed-off-by:')"
    subj="$(git -C "$dir" log -1 --format='%s')"

    printf '  commit  %s\n  author  %s\n\n' \
        "$(git -C "$dir" log -1 --format='%h %s')" "$author"

    # -- the DCO, which is the half both projects share -----------------------
    n="$(printf '%s\n' "$msg" | grep -ci '^signed-off-by:')"
    if [ "$n" = 1 ]; then ok "exactly one Signed-off-by"
    else no "$n Signed-off-by line(s); DCO wants exactly one"; fi

    if [ "$sob" = "Signed-off-by: $author" ]; then
        ok "Signed-off-by matches the commit author exactly"
    else
        no "Signed-off-by is '$sob' and the author is '$author'"
    fi

    # CONTRIBUTING.md: "the full name you commonly use, often a given name and
    # a family name or surname. (ok: Sam Samuelsson, Robert A. Heinlein; not
    # ok: xXthorXx, Sam, RAH)". Two words is the weakest testable form of that.
    if printf '%s\n' "$sob" | sed 's/^[Ss]igned-off-by: *//; s/ *<.*//' \
         | grep -qE '^[^ ]+( [^ ]+)+$'; then
        ok "sign-off carries a name with at least two parts"
    else
        no "sign-off name looks like a handle or a single word; CONTRIBUTING.md asks for the full name you commonly use"
    fi

    case "$sob" in
        *"<"*"@"*"."*">"*) ok "sign-off carries a reachable-looking address" ;;
        *) no "sign-off has no email address" ;;
    esac

    # An AI cannot make the DCO certification, whatever a project's AI policy
    # says, because the certification is about who has the right to submit the
    # code. This is the one rule carried over from the DMTF profile on
    # reasoning rather than on text.
    local ai_re='(^|[^[:alnum:]])(claude|ai|assistant|bot|anthropic|copilot|gpt|gemini|llm)([^[:alnum:]]|$)'
    if grep -qiE "$ai_re" <<<"$sob"; then
        no "an AI is named in Signed-off-by; the DCO is a certification only a person can make"
    else
        ok "no AI named in Signed-off-by"
    fi

    # -- Gerrit -------------------------------------------------------------
    #
    # ★ Count, do not merely detect. On 2026-09-18 an amend that appended a
    # trailer AFTER the Change-Id made the commit-msg hook add a second one:
    # the hook looks for a Change-Id in the message's last paragraph, and there
    # was not one there any more. Two Change-Ids is a push Gerrit refuses, and
    # the first version of this check said "Change-Id present" and passed the
    # commit. A check that answers "is there at least one" cannot see the
    # failure that actually happens.
    n="$(grep -cE '^Change-Id: I[0-9a-f]{40}$' <<<"$msg")"
    if [ "$n" = 1 ]; then
        ok "exactly one Change-Id: $(grep -E '^Change-Id:' <<<"$msg" | head -1)"
    elif [ "$n" = 0 ]; then
        if grep -q '^Change-Id:' <<<"$msg"; then
            no "a Change-Id line is present but malformed; it is I followed by 40 hex digits"
        else
            no "no Change-Id — install the commit-msg hook Gerrit serves and amend; the push is rejected without it"
        fi
    else
        no "$n Change-Id lines. Gerrit refuses that. An amend that appends a trailer after the Change-Id makes the hook add a second one; put the Change-Id last."
    fi

    # What stops the failure above from recurring is that the Change-Id sits
    # in the message's LAST PARAGRAPH, which is where the hook's
    # `git interpret-trailers --parse` looks for it.
    #
    # ★ Corrected 2026-09-23. This check used to require the Change-Id on the
    # last LINE, and the 15 most recent commits merged into openbmc/spdm all
    # put Signed-off-by after it — `git commit --amend -s` appends the sign-off
    # to the same trailer block. The stricter rule failed every commit the
    # target has ever accepted, and it would have refused the one command a
    # human uses to sign a prepared commit. A rule the target's own history
    # breaks is the thing this script's header says not to encode.
    local last_para
    last_para="$(awk 'BEGIN { RS = "" } { p = $0 } END { print p }' <<<"$msg")"
    if grep -q '^Change-Id:' <<<"$last_para"; then
        ok "Change-Id is in the final trailer block, so the next amend will not add another"
    else
        no "Change-Id is not in the message's last paragraph; the commit-msg hook will add a second one on the next amend"
    fi

    # -- the shape reviewers read first --------------------------------------
    if [ "${#subj}" -le 50 ]; then ok "subject ${#subj} chars"
    else no "subject ${#subj} chars, over 50"; fi

    case "$subj" in
        *": "*) ok "subject names a component before the colon" ;;
        *) no "subject has no 'component: ' prefix; CONTRIBUTING.md asks for one" ;;
    esac

    long="$(git -C "$dir" log -1 --format='%b' | awk 'length > 72 {c++} END {print c+0}')"
    if [ "$long" = 0 ]; then ok "no body line over 72 chars"
    else no "$long body line(s) over 72 chars"; fi

    if grep -q '^Tested:' <<<"$msg"; then
        ok "Tested: present — and it is yours to have actually run"
    else
        no "no Tested: line"
    fi

    # -- disclosure, reported and not required -------------------------------
    #
    # ★ OpenBMC's AI policy is in review (openbmc/docs 89452), not merged, and
    # its own reviewers are arguing about "should" against "can". Requiring the
    # trailer would encode an unsettled rule as a settled one; the header says
    # why that is as wrong as inventing one.
    if grep -q '^Assisted-by: ' <<<"$msg"; then
        skip "Assisted-by present — not required by OpenBMC, disclosed anyway: $(grep '^Assisted-by:' <<<"$msg" | head -1)"
    else
        skip "no Assisted-by — not required by OpenBMC. If an AI assisted, disclosing is a choice and this script does not make it for you"
    fi

    if grep -qi '^co-authored-by' <<<"$msg"; then
        skip "Co-authored-by present — permitted here, unlike DMTF. Check it names a person"
    fi

    # -- the thing this script cannot see ------------------------------------
    skip "the Individual CLA to manager@lfprojects.org is NOT checkable from here; Gerrit rejects the push if it is missing, and docs/upstream/README.md records the date it was sent"

    check_file_modes "$dir"

    if [ "$(git -C "$dir" status --porcelain | wc -l)" = 0 ]; then
        ok "working tree clean"
    else
        no "uncommitted changes in the tree"
    fi

    # -- the branch, because most OpenBMC repositories are not on this one ----
    local head
    head="$(git -C "$dir" ls-remote --heads origin 2>/dev/null | awk '{print $2}' | sed 's|refs/heads/||' | tr '\n' ' ')"
    if [ -n "$head" ]; then
        printf '  \033[33m--\033[0m    remote heads: %s — push to refs/for/<one of these>\n' "$head"
    fi
}

check_rules_unmoved() {   # check_rules_unmoved <repo-dir>
    local f="$1/CONTRIBUTING.md" got
    if [ ! -f "$f" ]; then
        no "$1 has no CONTRIBUTING.md — the rules this script encodes may not be that project's"
        return
    fi
    got="$(sha256sum "$f" | cut -d' ' -f1)"
    if [ "$got" = "$CONTRIB_SHA256" ]; then
        ok "CONTRIBUTING.md is the one these rules were read from"
    else
        no "CONTRIBUTING.md has changed since these rules were read (${got:0:16}… vs ${CONTRIB_SHA256:0:16}…). Re-read it before sending; a moved rule set is exactly what a returning contributor does not re-read."
    fi
}

# ------------------------------------------------------------- self-test ----
#
# Standing rule 11: every check here is fed something it must refuse. Built in a
# throwaway repository, because the only commit available to test against is the
# one that must pass, and a suite validated only against a good input has been
# observed doing one thing.

self_test() {
    local t got fails=0 cases=0
    t="$(mktemp -d)"
    git -C "$t" init -q
    git -C "$t" config user.name "Jane Developer"
    git -C "$t" config user.email "jane@example.com"
    printf 'x\n' > "$t/f"
    git -C "$t" add f

    # A message that satisfies everything, and the mutations that break one
    # rule each. `want` is the number of FAIL lines expected.
    local good
    good="component: a subject under fifty characters

A body line that stays inside seventy-two characters, saying why.

Tested: nothing, this is a fixture

Signed-off-by: Jane Developer <jane@example.com>
Assisted-by: Claude Code:claude-opus-5"

    run_case() {   # run_case <name> <expected-fails> <message>
        cases=$((cases + 1))
        git -C "$t" commit -q --allow-empty -m "$3" 2>/dev/null
        FAILED=0
        got="$(check_commit "$t" 2>&1 | grep -c 'FAIL')"
        if [ "$got" = "$2" ]; then
            printf '    ok   %-42s %s failure(s)\n' "$1" "$got"
        else
            printf '    FAIL %-42s expected %s failure(s), got %s\n' "$1" "$2" "$got"
            fails=$((fails + 1))
        fi
    }

    run_case "a compliant commit" 0 "$good"
    run_case "no Assisted-by" 1 "${good%$'\n'Assisted-by*}"
    run_case "an AI in Signed-off-by" 2 \
        "${good/Signed-off-by: Jane Developer <jane@example.com>/Signed-off-by: Claude <noreply@anthropic.com>}"
    run_case "a Co-authored-by trailer" 1 \
        "$good
Co-authored-by: Claude Opus 5 <noreply@anthropic.com>"
    run_case "no Tested: line" 1 "${good/Tested: nothing, this is a fixture/}"
    run_case "a subject over fifty characters" 1 \
        "${good/component: a subject under fifty characters/component: a subject that is comfortably over the fifty character limit}"
    run_case "a body line over seventy-two" 1 \
        "${good/A body line that stays inside seventy-two characters, saying why./A body line that does not stay inside seventy-two characters, because it keeps going and going}"
    run_case "no sign-off at all" 3 "${good/Signed-off-by: Jane Developer <jane@example.com>/}"

    # The one that cost ten minutes: a perfectly compliant sign-off whose email
    # contains the letters of a pattern written without word boundaries.
    cases=$((cases + 1))
    git -C "$t" config user.email "somebody@gmail.com"
    git -C "$t" commit -q --allow-empty -m "${good/jane@example.com/somebody@gmail.com}"
    FAILED=0
    got="$(check_commit "$t" 2>&1 | grep -c 'FAIL')"
    if [ "$got" = 0 ]; then
        printf '    ok   %-42s %s failure(s)\n' "a gmail.com address (contains 'ai')" "$got"
    else
        printf '    FAIL %-42s a compliant commit was refused\n' "a gmail.com address (contains 'ai')"
        fails=$((fails + 1))
    fi

    # ── the OpenBMC profile, against inputs it must refuse ────────────────
    #
    # Standing rule 11 again, and rule 13: the cases below break DIFFERENT
    # rules, and a suite where all of them came back "no Change-Id" would
    # report four times the coverage it has.
    git -C "$t" config user.name "Jane Developer"
    git -C "$t" config user.email "jane@example.com"
    local good_obmc
    good_obmc="component: a subject under fifty characters

A body line that stays inside seventy-two characters, saying why.

Tested: nothing, this is a fixture

Signed-off-by: Jane Developer <jane@example.com>
Change-Id: I0123456789abcdef0123456789abcdef01234567"

    run_case_obmc() {   # run_case_obmc <name> <expected-fails> <message>
        cases=$((cases + 1))
        git -C "$t" commit -q --allow-empty -m "$3" 2>/dev/null
        FAILED=0
        got="$(check_commit_openbmc "$t" 2>&1 | grep -c 'FAIL')"
        if [ "$got" = "$2" ]; then
            printf '    ok   %-42s %s failure(s)\n' "$1" "$got"
        else
            printf '    FAIL %-42s expected %s failure(s), got %s\n' "$1" "$2" "$got"
            fails=$((fails + 1))
        fi
    }

    run_case_obmc "openbmc: a compliant commit" 0 "$good_obmc"

    # Two failures and not one: with the Change-Id gone there is also no
    # Change-Id in last position. Rule 13 — distinct breaks, distinct checks,
    # and the count is what says so.
    run_case_obmc "openbmc: no Change-Id" 2 \
        "${good_obmc%$'\n'Change-Id*}"

    run_case_obmc "openbmc: a malformed Change-Id" 1 \
        "${good_obmc/I0123456789abcdef0123456789abcdef01234567/Ideadbeef}"

    # ★ The case the first version of this profile PASSED. Two Change-Ids is
    # what an amend produces when a trailer is appended after the first one,
    # and Gerrit refuses it. "Is there at least one" could not see it.
    run_case_obmc "openbmc: two Change-Id lines" 1 \
        "$good_obmc
Change-Id: Ifedcba9876543210fedcba9876543210fedcba98"

    # And the shape that causes it, caught one amend earlier: a trailer added
    # as a NEW PARAGRAPH after the Change-Id, so the hook no longer finds one.
    run_case_obmc "openbmc: a new paragraph after the Change-Id" 1 \
        "$good_obmc

Assisted-by: Claude Code:claude-opus-5"

    # ★ And its neighbour, which the first version of this suite got backwards:
    # a sign-off appended to the SAME trailer block. That is what
    # `git commit --amend -s` produces, and it is the order of the 15 most
    # recent commits merged into openbmc/spdm. It must pass.
    run_case_obmc "openbmc: Signed-off-by after Change-Id, as merged" 0 \
        "component: a subject under fifty characters

A body line that stays inside seventy-two characters, saying why.

Tested: nothing, this is a fixture

Change-Id: I0123456789abcdef0123456789abcdef01234567
Signed-off-by: Jane Developer <jane@example.com>"

    run_case_obmc "openbmc: no component prefix" 1 \
        "${good_obmc/component: a subject under fifty characters/a subject with no component prefix}"

    # ★ The one that is NOT a failure here and IS one at DMTF. If this starts
    # failing, either OpenBMC grew an AI policy or the two profiles have been
    # confused with each other.
    #
    # Note where the trailer goes: BEFORE the Change-Id. The first version of
    # this fixture put it after, and the duplicate check above caught its own
    # test data on the first run — which is the most convincing thing a new
    # check can do.
    run_case_obmc "openbmc: Assisted-by is allowed, not required" 0 \
        "${good_obmc/Change-Id: I0123456789abcdef0123456789abcdef01234567/Assisted-by: Claude Code:claude-opus-5
Change-Id: I0123456789abcdef0123456789abcdef01234567}"

    # A single-word sign-off name: CONTRIBUTING.md rejects "Sam" and "RAH".
    cases=$((cases + 1))
    git -C "$t" config user.name "Jane"
    git -C "$t" commit -q --allow-empty -m \
        "${good_obmc/Signed-off-by: Jane Developer <jane@example.com>/Signed-off-by: Jane <jane@example.com>}"
    FAILED=0
    got="$(check_commit_openbmc "$t" 2>&1 | grep -c 'FAIL')"
    if [ "$got" = 1 ]; then
        printf '    ok   %-42s %s failure(s)\n' "openbmc: a one-word sign-off name" "$got"
    else
        printf '    FAIL %-42s expected 1 failure, got %s\n' "openbmc: a one-word sign-off name" "$got"
        fails=$((fails + 1))
    fi

    # ── file modes ────────────────────────────────────────────────────────
    #
    # ★ The first case is 94773 patchset 1, reduced. The other two are what
    # rule 13 asks for: the neighbours the check must NOT refuse — a script
    # that really is executable, and a text file that is not. A mode check
    # that passed all three, or failed all three, would look identical in a
    # one-case suite.
    git -C "$t" config user.name "Jane Developer"
    git -C "$t" config core.filemode true

    mode_case() {   # mode_case <name> <expected-fails> <file> <content> <mode>
        cases=$((cases + 1))
        printf '%b' "$4" > "$t/$3"
        chmod "$5" "$t/$3"
        git -C "$t" add "$3"
        git -C "$t" commit -q -m "$good_obmc" 2>/dev/null
        FAILED=0
        got="$(check_commit_openbmc "$t" 2>&1 | grep -c 'FAIL')"
        if [ "$got" = "$2" ]; then
            printf '    ok   %-42s %s failure(s)\n' "$1" "$got"
        else
            printf '    FAIL %-42s expected %s failure(s), got %s\n' "$1" "$2" "$got"
            fails=$((fails + 1))
        fi
    }

    mode_case "a README added as 100755" 1 README.md '# spdm\n' 755
    mode_case "a script added as 100755, with #!" 0 run.sh '#!/bin/sh\nexit 0\n' 755
    mode_case "a README added as 100644" 0 NOTES.md '# notes\n' 644

    rm -rf "$t"
    printf '\n  %s case(s), %s failed\n' "$cases" "$fails"
    return "$fails"
}

# ------------------------------------------------------------------ main ----

PROFILE=dmtf

while [ $# -gt 0 ]; do
    case "$1" in
        --self-test)
            hdr "harness/check_upstream_commit.sh — the checks, against inputs they must refuse"
            self_test
            exit $?
            ;;
        --profile)
            PROFILE="${2:?--profile needs dmtf or openbmc}"
            shift 2
            ;;
        -h|--help)
            sed -n '2,90p' "$0"
            exit 0
            ;;
        *)
            DIR="$1"
            shift
            ;;
    esac
done

[ -n "${DIR:-}" ] || { sed -n '2,90p' "$0"; exit 0; }
[ -d "$DIR/.git" ] || die "$DIR is not a git repository"

hdr "the commit about to be sent to $(git -C "$DIR" remote get-url origin 2>/dev/null)"
printf '  profile %s\n\n' "$PROFILE"

# ★ Which profile is not a detail. The two projects disagree about the one
# trailer this repository's own commits carry: DMTF requires `Assisted-by:` and
# forbids naming an AI in `Co-authored-by`; OpenBMC has no AI policy at all and
# requires a `Change-Id` that DMTF has never heard of. Running the wrong profile
# would pass a commit that the target rejects, which is the failure this whole
# script exists to prevent.
case "$PROFILE" in
    dmtf)
        check_rules_unmoved "$DIR"
        printf '\n'
        check_commit "$DIR"
        ;;
    openbmc)
        # OpenBMC's CONTRIBUTING.md lives in openbmc/docs, not in the target
        # repository, so there is nothing local to digest. The digest of the
        # copy these rules were read from is in the header; re-read it if the
        # rules look surprising.
        skip "OpenBMC's CONTRIBUTING.md is in openbmc/docs, not here; rules read 2026-09-18, sha256 e27c7768…"
        printf '\n'
        check_commit_openbmc "$DIR"
        ;;
    *)
        die "unknown profile '$PROFILE' (expected: dmtf | openbmc)"
        ;;
esac

printf '\n'
if [ "$FAILED" -eq 0 ]; then
    ok "every rule this script knows about is satisfied"
    printf '\n'
    printf '  What it does NOT know:\n'
    printf '    * whether somebody has already reported this — search on the day\n'
    printf '    * whether the diff is right. Read it: git -C %s show HEAD\n' "$DIR"
    printf '    * whether every Tested: line was actually run by you\n'
    if [ "$PROFILE" = openbmc ]; then
        printf '    * whether the CLA has been accepted. Gerrit answers that\n'
        printf '      on the push, and it is the one failure that is loud\n'
        printf '    * whether YOU typed the Signed-off-by. openbmc/docs 89452:\n'
        printf '      "AI agents MUST NOT add Signed-off-by tags". Sign it with\n'
        printf '      git commit --amend -s --no-edit, yourself\n'
    fi
    printf '  Those are the checklist in docs/upstream/0001-corim-verify.md\n'
    printf '  section 6, and none of them is mechanisable.\n'
else
    printf '  fix the FAIL lines above before sending\n'
fi
exit "$FAILED"

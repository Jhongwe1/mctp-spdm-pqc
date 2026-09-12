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
# Only the DMTF profile is implemented. OpenBMC's — Gerrit, a Change-Id from the
# commit-msg hook, and a CLA whose state this script cannot see — arrives in
# week 9, when there is a real commit to check it against. Writing it now
# against no commit would be a check whose failure mode has never fired, which
# `docs/roadmap.md` standing rule 15 is about.
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

    if [ "$(git -C "$dir" status --porcelain | wc -l)" = 0 ]; then
        ok "working tree clean"
    else
        no "uncommitted changes in the tree"
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

    rm -rf "$t"
    printf '\n  %s case(s), %s failed\n' "$cases" "$fails"
    return "$fails"
}

# ------------------------------------------------------------------ main ----

case "${1:-}" in
    --self-test)
        hdr "harness/check_upstream_commit.sh — the checks, against inputs they must refuse"
        self_test
        exit $?
        ;;
    -h|--help|"")
        sed -n '2,70p' "$0"
        exit 0
        ;;
esac

DIR="$1"
[ -d "$DIR/.git" ] || die "$DIR is not a git repository"

hdr "the commit about to be sent to $(git -C "$DIR" remote get-url origin 2>/dev/null)"
check_rules_unmoved "$DIR"
printf '\n'
check_commit "$DIR"

printf '\n'
if [ "$FAILED" -eq 0 ]; then
    ok "every rule this script knows about is satisfied"
    printf '\n'
    printf '  What it does NOT know:\n'
    printf '    * whether somebody has already reported this — search on the day\n'
    printf '    * whether the diff is right. Read it: git -C %s show HEAD\n' "$DIR"
    printf '    * whether every Tested: line was actually run by you\n'
    printf '  Those three are the checklist in docs/upstream/0001-corim-verify.md\n'
    printf '  section 6, and none of them is mechanisable.\n'
else
    printf '  fix the FAIL lines above before sending\n'
fi
exit "$FAILED"

#!/usr/bin/env bash
#
# harness/recheck_upstream.sh — has anything this project depends on moved since W13?
#
#     bash harness/recheck_upstream.sh              # fetch, compare with 2026-09-29, report
#     bash harness/recheck_upstream.sh --keep DIR   # and keep what was fetched, for reading
#     bash harness/recheck_upstream.sh --selftest   # prove it can say CHANGED and NO DATA
#
# What it is for
# --------------
# plan/W13 closes by asking for a verify.sh that W14 runs in one go: has libspdm
# shipped 4.0.0, is there a new advisory, has DSP0274 moved, did openbmc/spdm get
# a README, and so on. The plan's version was a list of `curl -s ... | grep`.
# That shape has a failure this repository has now met three times: when the
# network fails, curl -s prints nothing, grep prints nothing, and nothing looks
# exactly like "nothing changed". On 2026-09-23 a DNS failure left an old Gerrit
# response in place and a summary reported a patchset that was no longer
# current; on 2026-09-28 the weekly CI step read no advisory list and said "0
# drifted".
#
# So every question here has three answers, not two:
#
#     same      fetched, parsed, and equal to the 2026-09-29 baseline
#     CHANGED   fetched, parsed, and different — the new value is printed
#     NO DATA   not fetched, or fetched and unreadable. Never reported as same.
#
# Every output file is deleted before its fetch, so a failed fetch cannot leave
# yesterday's answer behind. HTTP 404 is an answer ("it does not exist") for the
# questions that ask whether something exists, and NO DATA everywhere else;
# 403, 429, 5xx and a timeout are NO DATA everywhere.
#
# The baselines
# -------------
# Measured on 2026-09-29, the day W13's upstream changes were sent, and written
# into BASELINE below with that date. A CHANGED row is not an error: it is the
# reason this exists. When W14 has read them, it records what moved in LOG.md
# and, if a change is taken into the repository, moves the baseline.
#
# ★ What the first version could not see (2026-09-30)
# ------------------------------------------------------
# Its pull-request rows compared two counters, `comments` and
# `review_comments`. A review without an inline comment moves neither.
# Measured on DMTF/libspdm #3987: APPROVED by a maintainer, both counters 0. A
# request for changes is the same kind of object, a review, so the same is
# expected of it; that part is inferred, not measured. Either way #526 or #527
# could have been approved and this would have printed "same". The rows now carry the reviews
# themselves, the labels (#524 got `bug` two minutes before it merged) and the
# head commit. Three rows were added for the same reason, each a thing the
# 2026-09-30 re-check had to read by hand: #496, the maintainer's own open pull
# request touching six of #527's eight files (and, measured with git merge-tree
# that day, itself conflicting with main in three files, while GitHub still
# advertises a merge ref for it computed in June against a main 33 commits
# old — a merge ref proves nothing until its first parent is today's main);
# #358, the issue a fix for
# candidate 20 would reference; and the conformance suite's own `main`, because
# candidate 19 was fixed there while its consumer's pointer stood still. And
# the advisory row now prints the drifted count, which it used to drop.
#
# Exit codes: 0 everything same · 2 something is NO DATA and nothing changed ·
# 3 something CHANGED (NO DATA rows are still printed) · 1 the tool itself failed

set -u
_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${_HERE}/.." && pwd)"

KEEP=""
SELFTEST=0
while [ $# -gt 0 ]; do
    case "$1" in
        --keep)     KEEP="${2:?--keep needs a directory}"; shift 2 ;;
        --selftest) SELFTEST=1; shift ;;
        -h|--help)  sed -n '3,8p' "$0"; exit 0 ;;
        *) printf 'unknown argument %s\n' "$1" >&2; exit 1 ;;
    esac
done

# ── the judge: reads a directory of fetched files, prints the table ──────────
#
# <id> holds the body and <id>.code the HTTP status ("000" for no response).
# Kept separate from the fetching so that --selftest can hand it fabricated
# directories and require the answers a real outage or a real change would get.
judge() {
    python3 - "$1" <<'PY'
import json, os, re, sys

D = sys.argv[1]
BASELINE_DATE = "2026-09-29"

def code(i):
    try:
        return open(os.path.join(D, i + ".code")).read().strip()
    except OSError:
        return "000"

def body(i):
    p = os.path.join(D, i)
    if not os.path.exists(p):
        return None
    t = open(p, encoding="utf-8", errors="replace").read()
    return t[4:].lstrip("\n") if t.startswith(")]}'") else t   # Gerrit's XSSI prefix

class NoData(Exception):
    pass

def need(i, ok=("200",)):
    c = code(i)
    if c not in ok:
        raise NoData(f"HTTP {c}")
    return c

def js(i):
    need(i)
    t = body(i)
    if not t or not t.strip():
        raise NoData("an empty body with HTTP 200")
    try:
        return json.loads(t)
    except ValueError:
        raise NoData("HTTP 200 and not JSON")

def text(i):
    need(i)
    t = body(i)
    if not t or not t.strip():
        raise NoData("an empty body with HTTP 200")
    return t

# Each check returns the value that is compared with its baseline, as a string.
def libspdm_release():
    r = js("libspdm_releases")
    if not isinstance(r, list) or not r:
        raise NoData("no releases in the listing")
    stable = next((x["tag_name"] for x in r if not x["prerelease"]), "-")
    return f"newest {r[0]['tag_name']}, newest non-prerelease {stable}"

def emu_tag():
    t = js("emu_tags")
    if not isinstance(t, list) or not t:
        raise NoData("no tags in the listing")
    return f"{t[0]['name']} = {t[0]['commit']['sha'][:7]}"

def head(i):
    c = js(i)
    return c["sha"][:7]

def advisories():
    c = code("advisories")
    out = body("advisories") or ""
    if c == "0":
        m = re.search(r"(\d+) unchanged, (\d+) drifted, (\d+) new and unpinned, (\d+) older", out)
        if not m:
            raise NoData("the advisory tool's summary line is missing")
        return (f"{m.group(1)} pinned unchanged, {m.group(2)} drifted, {m.group(3)} new, "
                f"{m.group(4)} older unpinned")
    if c == "3":
        return "NEW OR EDITED advisory (see harness/check_advisories.py --refresh)"
    raise NoData(f"harness/check_advisories.py --refresh exited {c}")

def exists(i):
    c = code(i)
    if c == "200":
        return "exists"
    if c == "404":
        return "does not exist"
    raise NoData(f"HTTP {c}")

def obmc_libspdm():
    return f"{len(re.findall(r'libspdm', text('obmc_meson')))} mention(s) in meson.build"

def obmc_doe():
    t = js("obmc_tree")
    paths = [x["path"] for x in t.get("tree", [])]
    if not paths:
        raise NoData("an empty tree")
    return f"{sum(bool(re.search(r'doe', p, re.I)) for p in paths)} path(s) matching doe"

def gerrit():
    g = js("gerrit")
    votes = [a.get("value") for a in g.get("labels", {}).get("Code-Review", {}).get("all", [])
             if a.get("value")]
    return f"{g['status']}, last update {g['updated'][:19]}, Code-Review {votes or 'none'}"

def pr(n):
    # The counters alone miss a review without inline comments; see the header.
    p = js(f"pr{n}")
    rv = js(f"pr{n}_reviews")
    if not isinstance(rv, list):
        raise NoData("the review list is not a list")
    state = "merged" if p.get("merged") else p["state"]
    reviews = ", ".join(sorted(f"{r['user']['login']}:{r['state']}" for r in rv)) or "none"
    labels = ", ".join(sorted(x["name"] for x in p.get("labels", []))) or "none"
    return (f"{state}, head {p['head']['sha'][:7]}, {p.get('comments', 0)} comment(s), "
            f"{p.get('review_comments', 0)} review comment(s), reviews {reviews}, labels {labels}")

def pr_watched(n):
    # Somebody else's pull request: any activity at all moves updated_at.
    p = js(f"pr{n}")
    state = "merged" if p.get("merged") else p["state"]
    return f"{state}, head {p['head']['sha'][:7]}, updated {p['updated_at'][:19]}"

def issue(n):
    i = js(f"i{n}")
    who = ", ".join(sorted(a["login"] for a in i.get("assignees", []))) or "nobody"
    return f"{i['state']}, {i['comments']} comment(s), assigned {who}, updated {i['updated_at'][:19]}"

def meas_c():
    c = code("meas_c")
    if c == "404":
        return "GONE from libspdm main"
    return f"present, {js('meas_c').get('size')} bytes"

def emu_doc():
    t = text("emu_doc")
    return (f"hybrid x{len(re.findall(r'hybrid', t, re.I))}, "
            f"--data_transfer_size x{len(re.findall(r'data_transfer_size', t))}")

CHECKS = [
    # label, why it matters, how, baseline
    ("libspdm release", "is there a final 4.0.0 to re-pin to", libspdm_release,
     "newest 4.0.0-rc2, newest non-prerelease 3.8.3"),
    ("spdm-emu newest tag", "the pqc flavor is pinned to 4.0.0-rc = 5f01d2f", emu_tag,
     "4.0.0-rc2 = eff07cf"),
    ("spdm-emu main", "#526/#527 are based on it; a move may need a rebase", lambda: head("emu_main"),
     "eff07cf"),
    ("libspdm main", "where a defect is checked (standing rule 22)", lambda: head("libspdm_main"),
     "a6994ee"),
    ("SPDM-Responder-Validator main", "the suite's own head, not spdm-emu's pointer to it (candidate 19)",
     lambda: head("suite_main"), "7acde98"),
    ("libspdm advisories", "the four pinned in third_party/, and any new one", advisories,
     "4 pinned unchanged, 0 drifted, 0 new, 2 older unpinned"),
    ("DSP0274 1.4.1 PDF", "the pinned specification is still where the pin says", lambda: exists("dsp_141"),
     "exists"),
    ("DSP0274 1.4.2 PDF", "a newer specification to check the docs against", lambda: exists("dsp_142"),
     "does not exist"),
    ("DSP0274 1.5.0 PDF", "SPDM 1.5, hybrid PQC", lambda: exists("dsp_150"),
     "does not exist"),
    ("openbmc/spdm README", "94773 merged, or someone else's", lambda: exists("obmc_readme"),
     "does not exist"),
    ("openbmc/spdm uses libspdm", "80267 'Add libspdm dependency' merged", obmc_libspdm,
     "0 mention(s) in meson.build"),
    ("openbmc/spdm DOE", "a DOE transport arrived", obmc_doe,
     "0 path(s) matching doe"),
    ("Gerrit 94773", "the README change; no ping before 2026-10-07", gerrit,
     "NEW, last update 2026-09-23 17:10:44, Code-Review none"),
    ("DMTF/spdm-emu #526", "0003, CoRimTool exit status", lambda: pr(526),
     "open, head 60748b7, 0 comment(s), 0 review comment(s), reviews none, labels none"),
    ("DMTF/spdm-emu #527", "0004, --data_transfer_size", lambda: pr(527),
     "open, head 367414a, 0 comment(s), 0 review comment(s), reviews none, labels none"),
    ("DMTF/spdm-emu #496", "the maintainer's own, on 6 of #527's 8 files; whichever merges second rebases",
     lambda: pr_watched(496), "open, head 34f40fd, updated 2026-06-27T12:48:42"),
    ("DMTF/spdm-emu #358", "candidate 20's issue, assigned to its reporter; ask there before a fix",
     lambda: issue(358), "open, 1 comment(s), assigned arugan02, updated 2024-07-29T14:13:05"),
    ("libspdm meas.c", "device/meas-from-file.patch edits it; a re-pin needs it to apply", meas_c,
     "present, 33484 bytes"),
    ("spdm-emu doc", "hybrid PQC flags, and 0004's option once merged", emu_doc,
     "hybrid x0, --data_transfer_size x0"),
]

rows, changed, nodata = [], 0, 0
for label, why, fn, base in CHECKS:
    try:
        now = fn()
        verdict = "same" if now == base else "CHANGED"
    except NoData as e:
        now, verdict = f"({e})", "NO DATA"
    except (KeyError, TypeError, IndexError) as e:
        now, verdict = f"(unreadable: {type(e).__name__} {e})", "NO DATA"
    changed += verdict == "CHANGED"
    nodata += verdict == "NO DATA"
    rows.append((label, why, base, now, verdict))

for label, why, base, now, verdict in rows:
    mark = {"same": "  same   ", "CHANGED": "  CHANGED", "NO DATA": "  NO DATA"}[verdict]
    print(f"{mark}  {label}  — {why}")
    if verdict == "same":
        print(f"             {now}")
    else:
        print(f"             {BASELINE_DATE}: {base}")
        print(f"             now:        {now}")
print(f"\n  {len(rows)} checked: {len(rows) - changed - nodata} same, {changed} changed, {nodata} no data")
if nodata:
    print("  NO DATA is not 'unchanged'. Re-run when the network is back, or read the item by hand.")
sys.exit(3 if changed else (2 if nodata else 0))
PY
}

# ── --selftest: the three answers, each from inputs built to produce it ───────

if [ "$SELFTEST" -eq 1 ]; then
    T="$(mktemp -d)"
    trap 'rm -rf "$T"' EXIT
    # A directory that says exactly what the baseline says.
    mkbase() {
        local d="$1"; mkdir -p "$d"
        w() { printf '%s' "$2" > "$d/$1"; printf '200' > "$d/$1.code"; }
        w libspdm_releases '[{"tag_name":"4.0.0-rc2","prerelease":true},{"tag_name":"3.8.3","prerelease":false}]'
        w emu_tags '[{"name":"4.0.0-rc2","commit":{"sha":"eff07cf69d55"}}]'
        w emu_main '{"sha":"eff07cf69d55"}'
        w libspdm_main '{"sha":"a6994ee59334"}'
        w suite_main '{"sha":"7acde987a0e0"}'
        printf '  4 unchanged, 0 drifted, 0 new and unpinned, 2 older and deliberately unpinned\n' > "$d/advisories"
        printf '0' > "$d/advisories.code"
        printf '200' > "$d/dsp_141.code"; printf '404' > "$d/dsp_142.code"; printf '404' > "$d/dsp_150.code"
        printf '404' > "$d/obmc_readme.code"
        w obmc_meson "project('spdm', 'cpp')"
        w obmc_tree '{"tree":[{"path":"meson.build"},{"path":"tests/x.cpp"}]}'
        w gerrit ")]}'"$'\n''{"status":"NEW","updated":"2026-09-23 17:10:44.000000000","labels":{"Code-Review":{"all":[]}}}'
        w pr526 '{"state":"open","merged":false,"comments":0,"review_comments":0,"head":{"sha":"60748b75ff8b"},"labels":[]}'
        w pr527 '{"state":"open","merged":false,"comments":0,"review_comments":0,"head":{"sha":"367414adee84"},"labels":[]}'
        w pr526_reviews '[]'
        w pr527_reviews '[]'
        w pr496 '{"state":"open","merged":false,"head":{"sha":"34f40fdb1b07"},"updated_at":"2026-06-27T12:48:42Z"}'
        w i358 '{"state":"open","comments":1,"assignees":[{"login":"arugan02"}],"updated_at":"2024-07-29T14:13:05Z"}'
        w meas_c '{"size":33484}'
        w emu_doc '--pqc_asym only'
    }
    fails=0
    # A mutation that never reaches its input proves nothing and looks exactly
    # like one that works (2026-09-30), so each case first shows that the file
    # it changed differs from the unmutated baseline's.
    landed() {  # landed <case-dir> <file>
        if cmp -s "$T/same/$2" "$T/$1/$2"; then
            printf '  FAIL  %-44s the mutation did not change %s\n' "$1" "$2"
            fails=$((fails + 1))
        fi
    }
    expect() {  # name dir want-exit want-word
        local out rc
        out="$(judge "$2")"; rc=$?
        if [ "$rc" -eq "$3" ] && grep -q "$4" <<<"$out"; then
            printf '  ok    %-44s exit %s, says %s\n' "$1" "$rc" "$4"
        else
            printf '  FAIL  %-44s exit %s (wanted %s), %s\n' "$1" "$rc" "$3" \
                "$(grep -c "$4" <<<"$out") line(s) say $4"
            fails=$((fails + 1))
        fi
    }
    mkbase "$T/same";      expect "everything as on 2026-09-29"            "$T/same" 0 "19 same"
    mkbase "$T/released";  printf '[{"tag_name":"4.0.0","prerelease":false}]' > "$T/released/libspdm_releases"
                           landed released libspdm_releases
                           expect "libspdm ships 4.0.0"                    "$T/released" 3 "CHANGED"
    mkbase "$T/down";      rm -f "$T/down/gerrit"; printf '000' > "$T/down/gerrit.code"
                           landed down gerrit.code
                           expect "Gerrit unreachable"                     "$T/down" 2 "NO DATA"
    mkbase "$T/empty";     : > "$T/empty/pr527"
                           landed empty pr527
                           expect "HTTP 200 with an empty body"            "$T/empty" 2 "NO DATA"
    mkbase "$T/blocked";   printf '403' > "$T/blocked/dsp_142.code"
                           landed blocked dsp_142.code
                           expect "403 where 404 means 'does not exist'"   "$T/blocked" 2 "NO DATA"
    mkbase "$T/merged";    printf '{"state":"closed","merged":true,"comments":1,"review_comments":0,"head":{"sha":"367414adee84"},"labels":[]}' > "$T/merged/pr527"
                           landed merged pr527
                           expect "#527 merged"                            "$T/merged" 3 "CHANGED"
    mkbase "$T/gone";      printf '404' > "$T/gone/meas_c.code"
                           landed gone meas_c.code
                           expect "meas.c moved away"                      "$T/gone" 3 "GONE"
    mkbase "$T/advnew";    printf '3' > "$T/advnew/advisories.code"
                           landed advnew advisories.code
                           expect "a new advisory"                         "$T/advnew" 3 "NEW OR EDITED"
    # ── added 2026-09-30, one for each thing the first version could not see
    mkbase "$T/approved";  printf '[{"user":{"login":"jyao1"},"state":"APPROVED"}]' > "$T/approved/pr526_reviews"
                           landed approved pr526_reviews
                           expect "#526 approved, with no comment at all"  "$T/approved" 3 "CHANGED"
    mkbase "$T/labelled";  printf '{"state":"open","merged":false,"comments":0,"review_comments":0,"head":{"sha":"367414adee84"},"labels":[{"name":"bug"}]}' > "$T/labelled/pr527"
                           landed labelled pr527
                           expect "#527 labelled, as #524 was"             "$T/labelled" 3 "CHANGED"
    mkbase "$T/rvblock";   printf '403' > "$T/rvblock/pr527_reviews.code"
                           landed rvblock pr527_reviews.code
                           expect "#527's reviews unreadable (403)"        "$T/rvblock" 2 "NO DATA"
    mkbase "$T/m496";      printf '{"state":"closed","merged":true,"head":{"sha":"34f40fdb1b07"},"updated_at":"2026-10-02T08:00:00Z"}' > "$T/m496/pr496"
                           landed m496 pr496
                           expect "#496 merged: #527 will need a rebase"   "$T/m496" 3 "CHANGED"
    mkbase "$T/c358";      printf '{"state":"closed","comments":2,"assignees":[{"login":"arugan02"}],"updated_at":"2026-10-02T08:00:00Z"}' > "$T/c358/i358"
                           landed c358 i358
                           expect "#358 closed by somebody else"           "$T/c358" 3 "CHANGED"
    mkbase "$T/suite";     printf '{"sha":"1234567abcdef"}' > "$T/suite/suite_main"
                           landed suite suite_main
                           expect "the suite's own main moved"             "$T/suite" 3 "CHANGED"
    mkbase "$T/drift";     printf '  3 unchanged, 1 drifted, 0 new and unpinned, 2 older and deliberately unpinned\n' > "$T/drift/advisories"
                           landed drift advisories
                           expect "a pinned advisory drifted"              "$T/drift" 3 "1 drifted"
    [ "$fails" -eq 0 ] && { printf '  selftest: every answer reachable\n'; exit 0; }
    printf '  selftest: %s case(s) wrong\n' "$fails"; exit 1
fi

# ── the fetch ────────────────────────────────────────────────────────────────

T="${KEEP:-$(mktemp -d)}"
mkdir -p "$T"
[ -n "$KEEP" ] || trap 'rm -rf "$T"' EXIT
printf 'recheck against %s, at %s\n\n' "2026-09-29" "$(date -u +%FT%TZ)"

fetch() {  # id url — body to $T/id, status to $T/id.code; both deleted first
    rm -f "$T/$1" "$T/$1.code"
    local c
    c="$(curl -sS -L --retry 4 --retry-all-errors --max-time 40 -A 'mctp-spdm-pqc recheck' \
             -H 'Accept: application/vnd.github+json' -o "$T/$1" -w '%{http_code}' "$2" 2>/dev/null)" \
        || c="${c:-000}"
    printf '%s' "${c:-000}" > "$T/$1.code"
}
exists_url() {  # id url — status only, for "does it exist"
    rm -f "$T/$1.code"
    local c
    c="$(curl -sS -o /dev/null -L --retry 2 --retry-all-errors --max-time 40 -A 'Mozilla/5.0' \
             -w '%{http_code}' "$2" 2>/dev/null)" || c="${c:-000}"
    printf '%s' "${c:-000}" > "$T/$1.code"
}

GH=https://api.github.com/repos
RAW=https://raw.githubusercontent.com
DSP=https://www.dmtf.org/sites/default/files/standards/documents
fetch libspdm_releases "${GH}/DMTF/libspdm/releases?per_page=8"
fetch emu_tags         "${GH}/DMTF/spdm-emu/tags?per_page=5"
fetch emu_main         "${GH}/DMTF/spdm-emu/commits/main"
fetch libspdm_main     "${GH}/DMTF/libspdm/commits/main"
fetch suite_main       "${GH}/DMTF/SPDM-Responder-Validator/commits/main"
fetch meas_c           "${GH}/DMTF/libspdm/contents/os_stub/spdm_device_secret_lib_sample/meas.c"
fetch emu_doc          "${RAW}/DMTF/spdm-emu/main/doc/spdm_emu.md"
fetch obmc_readme      "${RAW}/openbmc/spdm/main/README.md"
fetch obmc_meson       "${RAW}/openbmc/spdm/main/meson.build"
fetch obmc_tree        "${GH}/openbmc/spdm/git/trees/main?recursive=1"
fetch gerrit           "https://gerrit.openbmc.org/changes/openbmc%2Fspdm~94773/detail"
fetch pr526            "${GH}/DMTF/spdm-emu/pulls/526"
fetch pr527            "${GH}/DMTF/spdm-emu/pulls/527"
fetch pr526_reviews    "${GH}/DMTF/spdm-emu/pulls/526/reviews?per_page=100"
fetch pr527_reviews    "${GH}/DMTF/spdm-emu/pulls/527/reviews?per_page=100"
fetch pr496            "${GH}/DMTF/spdm-emu/pulls/496"
fetch i358             "${GH}/DMTF/spdm-emu/issues/358"
exists_url dsp_141     "${DSP}/DSP0274_1.4.1.pdf"
exists_url dsp_142     "${DSP}/DSP0274_1.4.2.pdf"
exists_url dsp_150     "${DSP}/DSP0274_1.5.0.pdf"
# The advisory list has its own reader, with its own pins and its own three
# answers; this records what it said rather than re-implementing it.
rm -f "$T/advisories" "$T/advisories.code"
( cd "$REPO_ROOT" && python3 harness/check_advisories.py --refresh ) > "$T/advisories" 2>&1
printf '%s' "$?" > "$T/advisories.code"

judge "$T"
rc=$?
[ -n "$KEEP" ] && printf '\n  fetched files kept in %s\n' "$KEEP"
exit "$rc"

#!/usr/bin/env bash
#
# rats/test_svn_policy.sh — the four secure-version-number cases, under the
# policy that replaced equality and under the one it replaced.
#
#     bash rats/test_svn_policy.sh
#
# What this is for
# ----------------
# Changing an appraisal rule is not an achievement. Being able to show which
# verdicts the change moved — and, harder, which it did NOT move — is.
#
# So this does not run four cases. It runs four cases twice: once under
# rats/policy.rego, whose secure-version-number rule is per index and
# one-sided, and once under rats/policy-v0-equality.rego, which is the same
# file with the same rule written as `==` and frozen on the day it was
# replaced. Same four captures, same signed reference value, same evidence
# path. Eight cells, and exactly one of them may differ.
#
# The four cases
# --------------
#   S-eq    the device is what the reference says              must pass
#   S-up    the device is NEWER than the reference             must pass  <- moves
#   S-down  the device is OLDER than the reference             must fail
#   S-hash  the version is right, one measurement byte is not  must fail
#
# S-hash is the one the table would be dishonest without. Relaxing a rule
# invites exactly one question — did you relax security? — and the answer has
# to be a cell in the table rather than a sentence in a README.
#
# Where the evidence comes from
# -----------------------------
# Four real handshakes, taken on 2026-09-10, with the responder reading four
# different measurement fixtures through device/meas-from-file.patch. The
# evidence is the 528-byte measurement record sliced out of each MEASUREMENTS
# response — what the device SENT, not the fixture it read. Appraising the
# fixture would compare a document against itself and pass for every input.
#
# All four are appraised against ONE reference value, rats/ref/clean.corim,
# minted from the clean capture. A reference per case is the mistake that makes
# four passing cases out of a policy that does nothing.
#
# Exit codes
#   0  every cell as specified in rats/out/svn_cases.expected.json
#   1  a cell disagreed — the table is printed either way
#   2  the appraisal could not run at all (no opa, missing capture)

set -uo pipefail
_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${_HERE}/../harness/lib/common.sh"
set +e          # a FAIL verdict is exit 1 from appraise.py, and it is data

EXPECT="${REPO_ROOT}/rats/out/svn_cases.expected.json"

while [ $# -gt 0 ]; do
    case "$1" in
        --expect)  EXPECT="${2:?--expect needs a path}"; shift 2 ;;
        -h|--help) sed -n '3,46p' "$0"; exit 0 ;;
        *)         die "unknown argument '$1'" ;;
    esac
done

if ! command -v opa >/dev/null 2>&1; then
    printf 'opa is not on PATH. Every cell in this table is an opa evaluation,\n' >&2
    printf 'so without it this script would report success by not running.\n' >&2
    printf 'RUNBOOK.md section 11 installs it.\n' >&2
    exit 2
fi
[ -f "$EXPECT" ] || die "no expectation file at ${EXPECT}"

TMP="$(mktemp -d -t svncases-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# The plan, read out of the expectation file rather than repeated here: one
# line per cell, so that adding a case is a JSON edit and never a shell edit.
PLAN="${TMP}/plan.tsv"
python3 - "$EXPECT" > "$PLAN" <<'PY' || die "could not read ${EXPECT}"
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
run = doc["run"]
for name, c in doc["cases"].items():
    for side in ("before", "after"):
        print("\t".join([name, side, doc["policies"][side],
                         run + "/" + c["arm"] + ".decode.txt"]))
PY

hdr "four SVN cases x two policies"

n=0
while IFS=$'\t' read -r case side policy decode; do
    [ -n "$case" ] || continue
    n=$((n + 1))
    if [ ! -f "${REPO_ROOT}/${decode}" ]; then
        die "missing capture: ${decode}
  This table is derived from captures already in the repository. If the run
  directory was renamed, rats/out/svn_cases.expected.json names the one to use."
    fi
    python3 "${REPO_ROOT}/rats/appraise.py" appraise "${REPO_ROOT}/${decode}" \
        --policy "${REPO_ROOT}/${policy}" --json \
        > "${TMP}/${case}.${side}.json" 2> "${TMP}/${case}.${side}.err"
    printf '%s' "$?" > "${TMP}/${case}.${side}.rc"
    dim "  ${case} / ${side}: $(basename "$policy")"
done < "$PLAN"

[ "$n" -gt 0 ] || die "the expectation file names no cases"

# ---------------------------------------------------------------------------
# Everything above ran appraisals. Everything below compares them with what was
# specified, and the comparison is deliberately in one place: a check spread
# through a loop is a check nobody can read the whole of.

python3 - "$EXPECT" "$TMP" <<'PY'
import json
import sys
from pathlib import Path

expect = json.load(open(sys.argv[1], encoding="utf-8"))
tmp = Path(sys.argv[2])
cases = expect["cases"]

# appraise.py's contract: 0 pass, 1 fail, 2 could-not-tell. The verdict is read
# out of the JSON rather than out of the exit code — 2026-08-11 in LOG.md, the
# day three tools answered slightly different questions with their exit codes —
# and then the two are required to AGREE. A tool whose exit code disagrees with
# its own verdict is the upstream defect this repository found on 2026-09-12.
RC_FOR = {"pass": 0, "fail": 1}

fails = []
got = {}

for name, c in cases.items():
    for side in ("before", "after"):
        stem = str(tmp / (name + "." + side))
        rc = int(Path(stem + ".rc").read_text())
        try:
            v = json.loads(Path(stem + ".json").read_text(encoding="utf-8"))
        except Exception:
            err = Path(stem + ".err").read_text(encoding="utf-8").strip()
            fails.append(name + "/" + side + ": no verdict JSON (exit "
                         + str(rc) + "): " + err[:200])
            got[(name, side)] = {"outcome": "error", "blocked_by": [], "detail": {}}
            continue
        r = v["result"]
        outcome = r["verdict"]
        blocked = sorted(r.get("failed_checks") or [])
        detail = {k: sorted(x) for k, x in (r.get("detail") or {}).items() if x}
        got[(name, side)] = {"outcome": outcome, "blocked_by": blocked,
                             "detail": detail}

        want = c[side]
        if outcome != want["outcome"]:
            fails.append(f"{name}/{side}: verdict {outcome}, expected "
                         f"{want['outcome']} — {c['proves'][:90]}")
        if blocked != sorted(want["blocked_by"]):
            fails.append(f"{name}/{side}: blocked by {blocked}, expected "
                         f"{sorted(want['blocked_by'])}")
        # Exact, not a superset. A case refused by the right check AND by one
        # nobody expected is a case whose input broke more than it meant to,
        # and standing rule 13 exists for precisely that.
        if detail != {k: sorted(x) for k, x in want["detail"].items()}:
            fails.append(f"{name}/{side}: detail {detail}, expected {want['detail']}")
        if rc != RC_FOR.get(outcome, 2):
            fails.append(f"{name}/{side}: exit {rc} with verdict {outcome} — "
                         f"the CLI's exit code and its own verdict disagree")


def cell(g):
    if g["outcome"] == "pass":
        return "PASS"
    why = ",".join(x.replace("SPDM_", "") for x in g["blocked_by"]) or "?"
    det = " ".join(k + str(v) for k, v in sorted(g["detail"].items()))
    return ("FAIL " + why + " " + det).strip()


W = max(len(x) for x in cases) + 2
print()
print(f"{'case':<{W}}{'arm':<11}{'svn':>4}  "
      f"{'== (frozen)':<36}{'>= (live)':<36}")
print("-" * (W + 17 + 72))

moved = []
for name, c in cases.items():
    b, a = got[(name, "before")], got[(name, "after")]
    if b["outcome"] != a["outcome"]:
        moved.append(name)
    mark = "*" if b["outcome"] != a["outcome"] else " "
    print(f"{name:<{W}}{c['arm']:<11}{c['device_svn']:>4}  "
          f"{cell(b):<36}{cell(a):<36}{mark}")

print()
print("  * the verdict moved between the two policies")
print("  reference value: " + expect["reference"] + "  (one, shared by all four)")
print("  captures:        " + expect["run"])

# ── the assertion the file exists for ──────────────────────────────────────
want_moved = sorted(expect["outcome_changes_expected"])
if sorted(moved) != want_moved:
    fails.append(f"cases whose verdict moved: {sorted(moved)}, expected "
                 f"{want_moved}. A change that moves more than the case it was "
                 f"written for has loosened something else; a change that moves "
                 f"none has done nothing.")

print()
for f in fails:
    print("  FAIL  " + f)
cells = len(cases) * 2
print(f"{cells} cells, {cells * 4 + 1} assertions, {len(fails)} failed")
sys.exit(1 if fails else 0)
PY
rc=$?

if [ "$rc" -eq 0 ]; then
    ok "the version rule was loosened in one direction and nothing else moved"
else
    printf '\n'
    warn "a cell disagreed with rats/out/svn_cases.expected.json"
    warn "  either the policy changed or the expectation is wrong — argue with"
    warn "  the sentence in the 'proves' field before editing the cell"
fi
exit "$rc"

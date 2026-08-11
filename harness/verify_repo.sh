#!/usr/bin/env bash
#
# harness/verify_repo.sh — everything CI checks, runnable locally.
#
#     bash harness/verify_repo.sh
#
# Run this before committing. It is the same set of checks as
# .github/workflows/ci.yml, so a green run here means a green run there, and
# finding out locally costs seconds rather than a push and a wait.
#
# It touches nothing outside the repository and builds no upstream code.

set -uo pipefail
_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${_HERE}/lib/common.sh"
set +e

FAILED=0
step() { printf '\n\033[34m--- %s\033[0m\n' "$*"; }
good() { printf '  \033[32mok\033[0m   %s\n' "$*"; }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$*"; FAILED=1; }

cd "$REPO_ROOT" || exit 1

step "shellcheck"
if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck -x -S warning harness/*.sh; then
        good "no warnings or errors"
    else
        bad "shellcheck reported problems"
    fi
else
    printf '  --   shellcheck not installed (apt: shellcheck) — skipped\n'
fi

step "python syntax"
if python3 -m py_compile harness/pcapcount.py harness/lib/_manifest.py; then
    good "harness python compiles"
else
    bad "python syntax error"
fi

step "pcapcount self-test"
python3 - <<'PY'
import json, pathlib, struct, subprocess, sys, tempfile
hdr = struct.pack('<IHHiIII', 0xa1b2c3d4, 2, 4, 0, 0, 65535, 1)
rec = lambda n: struct.pack('<IIII', 1700000000, 0, n, n) + b'\xaa' * n
p = pathlib.Path(tempfile.mkdtemp()) / 'two.pcap'
p.write_bytes(hdr + rec(4) + rec(6))
out = subprocess.run([sys.executable, 'harness/pcapcount.py', str(p), '--json'],
                     capture_output=True, text=True)
if out.returncode != 0:
    print('  pcapcount failed:', out.stderr.strip()); sys.exit(1)
s = json.loads(out.stdout)['summary']
for key, want in (('packets', 2), ('captured_bytes_total', 10), ('linktype', 1)):
    if s[key] != want:
        print(f'  {key}: got {s[key]}, want {want}'); sys.exit(1)
if s['byte_order'] != 'little-endian' or s['truncated']:
    print('  header parsed wrong:', s); sys.exit(1)
print('  parsed 2 packets / 10 bytes from a hand-built capture')
PY
[ $? -eq 0 ] && good "parser agrees with a capture built byte by byte" \
             || bad "pcapcount self-test failed"

step "c-drills compile and run"
if make -C c-drills --no-print-directory >/dev/null 2>&1; then
    good "every drill compiles under -Werror + ASan + UBSan"
    if make -C c-drills --no-print-directory test 2>&1 | tail -3 | sed 's/^/  /'; then
        good "drills marked complete in DONE.txt pass"
    else
        bad "a completed drill failed"
    fi
else
    make -C c-drills --no-print-directory 2>&1 | tail -20 | sed 's/^/  /'
    bad "a drill does not compile"
fi

step "every experiment run is attributed"
missing=0
shopt -s nullglob
for d in bench/data/*/; do
    case "$d" in bench/data/_scratch/*) continue ;; esac
    [ -f "${d}manifest.json" ] || { printf '  UNATTRIBUTED: %s\n' "$d"; missing=1; }
done
if [ "$missing" -eq 0 ]; then
    good "$(find bench/data -maxdepth 2 -name manifest.json 2>/dev/null | wc -l) run(s), all carrying provenance"
else
    bad "a run directory has no manifest.json (see docs/decisions/0003)"
fi

step "scope statement precedes the build badge"
# Two checks. The first reads README.md with all whitespace collapsed, so the
# sentence is found whether or not Markdown wrapped it across source lines —
# the first version of this check searched for the sentence on one line and
# reported a false failure the moment the paragraph was reflowed.
# The second uses a short single-line anchor to compare positions.
if tr '\n' ' ' < README.md | tr -s ' ' \
     | grep -q 'protocol-level correctness validation.\{0,10\}It is not a security assessment'; then
    good "scope sentence present"
else
    bad "README.md does not state the scope in the expected words"
fi
scope=$(grep -n 'security assessment' README.md | head -1 | cut -d: -f1)
badge=$(grep -n 'actions/workflows/ci.yml/badge.svg' README.md | head -1 | cut -d: -f1)
if [ -z "$scope" ]; then
    bad "no scope anchor found in README.md"
elif [ -n "$badge" ] && [ "$scope" -gt "$badge" ]; then
    bad "scope statement (line $scope) comes after the badge (line $badge)"
else
    good "scope at line $scope, badge at line ${badge:-none}"
fi

step "planning material is not tracked"
if git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    leaked="$(git ls-files plan archive 2>/dev/null)"
    if [ -n "$leaked" ]; then
        printf '%s\n' "$leaked" | sed 's/^/  /'
        bad "private planning files are staged or tracked"
    else
        good "plan/ and archive/ are untracked"
    fi
fi

printf '\n'
if [ "$FAILED" -eq 0 ]; then
    hdr "all checks passed"
else
    hdr "checks failed — fix the FAIL lines above"
fi
exit "$FAILED"

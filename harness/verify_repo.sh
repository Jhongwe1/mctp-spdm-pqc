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

step "python syntax (analysis tools)"
if python3 -m py_compile harness/fields.py; then
    good "harness/fields.py compiles"
else
    bad "harness/fields.py has a syntax error"
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

step "every artifact still hashes to what its manifest signed for"
# A manifest lists each artifact with its SHA-256. Three things can break that
# promise, and only the first one is obvious:
#
#   the file is gone;
#   the file is present but not tracked, so a fresh clone never receives it —
#     which is worse than absence, because the mechanism reports success. This
#     is not hypothetical: .gitignore's `*.log` quietly excluded twelve evidence
#     files that three manifests had already signed for;
#   the file is present, tracked, and no longer the file that was hashed.
#
# The third is why the digest is recomputed rather than the path merely checked.
# "Do not edit anything under bench/data" is a rule a person can forget by week
# six; a digest cannot. Line endings are pinned to LF in .gitattributes for
# every text file precisely so this comparison means the same thing on every
# platform.
python3 - <<'PY'
import hashlib, json, pathlib, subprocess, sys

tracked = set(subprocess.run(
    ["git", "ls-files", "bench/data"], capture_output=True, text=True, check=False
).stdout.split())

problems, checked = [], 0
manifests = sorted(pathlib.Path("bench/data").glob("*/manifest.json"))
for man in manifests:
    data = json.loads(man.read_text(encoding="utf-8"))
    for art in data.get("artifacts", []):
        rel = f"{man.parent.as_posix()}/{art['path']}"
        path = pathlib.Path(rel)
        if not path.exists():
            problems.append(f"MISSING   {rel}")
            continue
        if rel not in tracked:
            problems.append(f"UNTRACKED {rel}  (attested with a sha256 but not committed)")
            continue
        checked += 1
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if digest != art["sha256"]:
            problems.append(f"ALTERED   {rel}")
            problems.append(f"          manifest: {art['sha256']}")
            problems.append(f"          on disk : {digest}")
        elif path.stat().st_size != art["bytes"]:
            problems.append(f"SIZE      {rel}: manifest {art['bytes']}, on disk {path.stat().st_size}")

for p in problems:
    print("  " + p)
print(f"  {checked} artifact(s) across {len(manifests)} manifest(s) re-hashed")
sys.exit(1 if problems else 0)
PY
[ $? -eq 0 ] && good "every attested artifact is present, tracked, and unaltered" \
             || bad "an artifact no longer matches the manifest that attests to it"

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

step "the handshake walkthrough still agrees with its capture"
# The walkthrough is a document made almost entirely of stated facts, which is
# the category this project has twice caught itself getting wrong. So its
# numbers are not typed in: each is marked up as <!--claim key=value--> and
# re-derived here from the decode file the document names. A number that drifts
# from its capture is a failed build, not something a reader might notice.
if [ -f docs/handshake-walkthrough.md ]; then
    if python3 harness/fields.py --check docs/handshake-walkthrough.md; then
        good "every claim in the walkthrough matches the capture it cites"
    else
        bad "docs/handshake-walkthrough.md contradicts its own capture"
    fi
else
    printf '  --   docs/handshake-walkthrough.md not written yet — skipped\n'
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

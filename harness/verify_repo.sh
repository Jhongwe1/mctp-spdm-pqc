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
    if shellcheck -x -S warning harness/*.sh certs/*.sh rats/*.sh negative/*.sh; then
        good "no warnings or errors"
    else
        bad "shellcheck reported problems"
    fi
else
    printf '  --   shellcheck not installed (apt: shellcheck) — skipped\n'
fi

step "python syntax"
if python3 -m py_compile harness/pcapcount.py harness/lib/_manifest.py certs/check_chain.py; then
    good "harness python compiles"
else
    bad "python syntax error"
fi

step "no private key material is tracked"
# .gitignore excludes *.key, and for one commit's worth of time it also did not
# exclude end_responder.key.pem, because that pattern matches the END of a name
# and gen_chain.sh had written a second spelling. The rule looked like it
# covered the case and did not.
#
# So the guarantee is not a pattern any more. This reads every file git is
# actually tracking and refuses a PEM private-key header in any of them. A
# pattern describes what someone expected to write; this describes what is
# there. Costs about a second.
python3 - <<'PY'
import pathlib, subprocess, sys

# Assembled rather than written out, and the first version of this check was not
# — so it found a private-key header in the only file that had one: itself. A
# checker that spells out what it forbids becomes an instance of it. Built from
# pieces, the header never appears as a byte sequence in any tracked file, and
# the check's answer about this file is the true one.
RULE = b"-" * 5
def marker(kind: bytes) -> bytes:
    return RULE + b"BEGIN " + kind + b"PRIVATE KEY" + RULE

MARKERS = tuple(marker(k) for k in
                (b"", b"RSA ", b"EC ", b"DSA ", b"OPENSSH ", b"ENCRYPTED "))
MARKERS += (RULE + b"BEGIN PGP " + b"PRIVATE KEY BLOCK" + RULE,)

tracked = subprocess.run(["git", "ls-files", "-z"], capture_output=True, check=False)
names = [n for n in tracked.stdout.split(b"\0") if n]
found, scanned = [], 0
for raw in names:
    path = pathlib.Path(raw.decode("utf-8", "surrogateescape"))
    if not path.is_file():
        continue
    try:
        blob = path.read_bytes()
    except OSError:
        continue
    scanned += 1
    for marker in MARKERS:
        if marker in blob:
            found.append(f"{path}  contains {marker.decode()}")
            break

for line in found:
    print("  " + line)
print(f"  {scanned} tracked file(s) scanned")
sys.exit(1 if found else 0)
PY
[ $? -eq 0 ] && good "no tracked file carries a private-key header" \
             || bad "a private key is committed — remove it and rotate it"

step "the certificate chain is well formed, and the checker can still reject"
# certs/gen_chain.sh builds this project's own three-layer chain, and
# certs/check_chain.py reads it out of DER rather than out of a pretty-printer.
# Both halves run here: the committed chain has to pass, and the checker has to
# be observed rejecting four different breaks through four different checks —
# because a suite where two breaks are caught by the same check is claiming
# more coverage than it has, and this one was, until the order of two checks
# was swapped.
if [ -f certs/out/bundle_responder.certchain.der ]; then
    if python3 certs/check_chain.py certs/out >/dev/null 2>&1; then
        good "the committed chain links to its root and carries both identity OIDs"
    else
        python3 certs/check_chain.py certs/out 2>&1 | sed 's/^/  /' | tail -20
        bad "certs/out does not pass its own checker"
    fi
    if python3 certs/check_chain.py certs/out --self-test 2>&1 | sed 's/^/  /'; then
        good "four breaks, four distinct checks, every one rejected"
    else
        bad "the chain checker accepted something it should have refused"
    fi
else
    printf '  --   certs/out holds no chain — skipped (bash certs/gen_chain.sh)\n'
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
    if out="$(make -C c-drills --no-print-directory test 2>&1)" \
       && printf '%s\n' "$out" | tail -3 | sed 's/^/  /'; then
        good "drills marked complete in DONE.txt pass"
    else
        bad "a completed drill failed"
    fi
else
    make -C c-drills --no-print-directory 2>&1 | tail -20 | sed 's/^/  /'
    bad "a drill does not compile"
fi

step "python syntax (analysis tools)"
if python3 -m py_compile harness/fields.py bench/pcapstat.py \
                         bench/exp04_fragmentation.py \
                         harness/check_claims.py \
                         harness/lib/check_negotiated.py \
                         harness/lib/ci_tools_check.py \
                         harness/check_advisories.py \
                         device/gen_measurements.py rats/cose.py \
                         rats/appraise.py rats/rats_selftest.py; then
    good "fields.py, pcapstat.py, exp04_fragmentation.py, gen_measurements.py and rats/ compile"
else
    bad "an analysis tool has a syntax error"
fi

step "every CI job installs the tools it runs"
# ★ 2026-09-14. The badge had been red for two days: verify_repo.sh hard-fails
# without `opa`, which is correct, and the job that runs it never installed
# `opa`, which is not. The script was right and the job was wrong, and neither
# was visible from the other.
#
# harness/lib/ci_tools_check.py states the invariant that was violated — a job
# must not run a tool it does not install — and derives it from the
# consumed-by= field the pins already carry.
if out="$(python3 harness/lib/ci_tools_check.py 2>&1)"; then
    printf '%s' "$out" | sed 's/^/  /'
    good "no CI job runs a pinned tool its runner will not have"
else
    printf '%s' "$out" | sed 's/^/  /'
    bad "a CI job runs a tool it does not install — that is a red build nobody reads"
fi

step "and that check can still say no"
# Standing rule 11. A regex over a file that has only ever met a correct file is
# a string search that happens to match. So it is given a copy of the workflow
# with the install step deleted — which is exactly the state this repository was
# in between 2026-09-12 and 2026-09-14.
CIW="$(mktemp -d)"
mkdir -p "${CIW}/.github/workflows" "${CIW}/third_party"
cp third_party/*.pin "${CIW}/third_party/"
python3 - "$CIW" <<'PY'
import pathlib
import re
import sys

src = pathlib.Path(".github/workflows/ci.yml").read_text(encoding="utf-8")
broken = re.sub(r"      - name: Install Open Policy Agent.*?(?=^      - name:)",
                "", src, flags=re.S | re.M)
(pathlib.Path(sys.argv[1]) / ".github" / "workflows" / "ci.yml").write_text(
    broken, encoding="utf-8")
PY
if python3 harness/lib/ci_tools_check.py "$CIW" >/dev/null 2>&1; then
    bad "the workflow check accepted a job that runs opa without installing it"
else
    good "a job that runs a pinned tool it does not install is refused"
fi
rm -rf "$CIW"

step "the measurement source module compiles, rejects, and agrees with its writer"
# device/measurement_source.c is compiled twice: here on its own under two
# sanitizers, and inside libspdm's sample secret library where nothing can run
# it. Only the first of those fits in CI, which is why the module takes no
# libspdm dependency at all.
#
# `test` runs 66 checks, of which the ones that matter feed the loader eleven
# malformed fixtures and require ELEVEN DIFFERENT reason codes — standing rule
# 13 — and then require every value of ms_status_t to have been observed, so an
# error code nothing provokes is a failing build.
#
# `interop` byte-compares what the C builder writes with what
# device/gen_measurements.py writes for the same defaults. The format has two
# implementations and standing rule 12 says two routes to one quantity are made
# to agree; without this the drift would surface as a responder quietly serving
# upstream's synthetic values during a tamper run.
#
# Both of these capture before they judge, and the reason is a bug this step
# had on 2026-09-10. It was written as
#
#     if make -C device interop 2>&1 | head -2 | sed 's/^/  /'; then
#
# and `head -2` closes the pipe as soon as it has two lines. `make` is still
# writing — the recipe ends with a --describe whose ten lines come after the
# summary — so it dies of SIGPIPE, exits 141, and `set -o pipefail` makes the
# whole pipeline non-zero. The step then reported that the two implementations
# of the file format disagree, on the line after printing that they agree.
#
# It had been intermittent since the step was written, and became deterministic
# the day /mnt/c's clock skew made `make` print one extra warning line, which
# moved head's exit to before the --describe ran. Measured: PIPESTATUS=141 0,
# five runs out of five, and 0 out of 5 when captured first.
#
# A check that fails for a reason unrelated to what it checks is worse than no
# check, because the failure is legible and wrong.
if out="$(make -C device --no-print-directory test 2>&1)"; then
    printf '%s\n' "$out" | tail -2 | sed 's/^/  /'
    good "the loader's self-test passes under -Werror + ASan + UBSan"
else
    printf '%s\n' "$out" | tail -25 | sed 's/^/  /'
    bad "the measurement source self-test failed"
fi
if out="$(make -C device --no-print-directory interop 2>&1)"; then
    printf '%s\n' "$out" | head -2 | sed 's/^/  /'
    good "the C reader and the Python writer produce identical bytes"
else
    printf '%s\n' "$out" | tail -20 | sed 's/^/  /'
    bad "gen_measurements.py and the C builder disagree about the file format"
fi
make -C device --no-print-directory clean >/dev/null 2>&1 || true

step "the measurement record walk can still fail"
# fields.py now reports what is INSIDE a measurement record, not just its
# length, because "the record is still 528 bytes" is exactly what a successful
# tamper looks like. The walk is over-determined three ways — the block count
# must equal NumberOfBlocks, the walk must consume MeasurementRecordLength
# exactly, and each block's MeasurementSize must equal 3 plus its own DMTF
# value size — so a correct record is built here and then broken once per
# equation, and each break must be REPORTED rather than turned into eight
# plausible blocks.
python3 - <<'PY'
import json, pathlib, subprocess, sys, tempfile

# ALGORITHMS has to be here even though nothing below is signed: reconstruct()
# refuses to place a MEASUREMENTS message for a connection whose signature
# algorithm it cannot name, and refusing is the right behaviour — an offset
# derived from an unknown signature size is a guess. Leaving it out made this
# test report "a correct record did not close", which was true and was about
# the fixture rather than the code.
ALGS = ("1 (1) MCTP(5) RSP->REQ SPDM(14, 0x63) SPDM_ALGORITHMS "
        "(Hash=0x00000002(SHA_384), MeasHash=0x00000008(SHA_512), "
        "Asym=0x00000080(ECDSA_P384), ReqAsym=0x0008(RSAPSS_3072)) ")
GM = ("2 (1) MCTP(5) REQ->RSP SPDM(14, 0xe0) SPDM_GET_MEASUREMENTS "
      "(Attr=0x00(), MeasOp=0xff(All), SlotID=0x00) ")
MS = ("3 (1) MCTP(5) RSP->REQ SPDM(14, 0x60) SPDM_MEASUREMENTS "
      "(NumOfBlocks=0x02, MeasRecordLen=0x00000000, ContentChange=0x20(NoChange), "
      "SlotID=0x00) ")


def block(raw):
    return "\n".join(f"    {i:04x}: " + " ".join(f"{b:02x}" for b in raw[i:i + 32])
                     for i in range(0, len(raw), 32))


def mblock(index, vtype, value, size=None, vsize=None):
    size = 3 + len(value) if size is None else size
    vsize = len(value) if vsize is None else vsize
    return (bytes([index, 0x01, size & 0xFF, size >> 8, vtype,
                   vsize & 0xFF, vsize >> 8]) + value)


def message(nblocks, record):
    body = bytes([0x14, 0x60, 0x00, 0x20, nblocks,
                  len(record) & 0xFF, (len(record) >> 8) & 0xFF,
                  (len(record) >> 16) & 0xFF]) + record
    return body + bytes(32) + b"\x00\x00"        # nonce, OpaqueLength = 0


def walk(nblocks, record):
    d = pathlib.Path(tempfile.mkdtemp())
    algs = bytes([0x14, 0x63]) + bytes(34)
    req = bytes([0x14, 0xE0, 0x00, 0xFF])
    rsp = message(nblocks, record)
    (d / "t.decode.txt").write_text(
        "spdm_dump version 0.1\n"
        "PcapFile: Magic - 'a1b2c3d4', version2.4, DataLink - 291 (MCTP),"
        " MaxPacketSize - 65536\n" + ALGS + "\n" + GM + "\n" + MS + "\n",
        encoding="utf-8")
    (d / "t.hex.txt").write_text(
        ALGS + "\n  SPDM Message:\n" + block(algs) + "\n"
        + GM + "\n  SPDM Message:\n" + block(req) + "\n"
        + MS + "\n  SPDM Message:\n" + block(rsp) + "\n", encoding="utf-8")
    out = subprocess.run([sys.executable, "harness/fields.py",
                          str(d / "t.decode.txt"), "--json"],
                         capture_output=True, text=True)
    if out.returncode != 0:
        print("  fields.py failed:", out.stderr.strip())
        return None
    return json.loads(out.stdout)["layout"]["measurement_record"]


good_record = (mblock(0x01, 0x00, bytes(range(8)))
               + mblock(0x10, 0x87, (7).to_bytes(8, "little")))

rec = walk(2, good_record)
if rec is None or not rec["closes"]:
    print("  a correct record did not close:", rec and rec["why"])
    sys.exit(1)
if rec["blocks"]["0x10"]["value_uint64"] != 7 or rec["blocks_walked"] != 2:
    print("  the intact walk disagrees with what was built:", rec)
    sys.exit(1)
print(f"  intact: closes — {rec['blocks_walked']} blocks, svn "
      f"{rec['secure_version_number']}, {rec['record_bytes']} bytes")

seen = {}
for name, nblocks, record in (
    ("NumberOfBlocks disagrees", 3, good_record),
    # MeasurementSize 11 FITS in the record — it is the same size the first
    # block legitimately has — but says 3 + 4 rather than 3 + 8. If this case
    # is written with a size that overflows the record instead, the length
    # check catches it first and the equation being tested here never runs.
    # That is what the first version of this test did, and the distinctness
    # check below did not notice because the two sentences differed by a digit.
    ("MeasurementSize disagrees with the value size", 2,
     mblock(0x01, 0x00, bytes(8), vsize=4) + mblock(0x10, 0x87, bytes(8))),
    ("a block runs past the record", 2,
     mblock(0x01, 0x00, bytes(8), size=900) + mblock(0x10, 0x87, bytes(8))),
    ("a block header is cut short", 2, good_record + b"\x01\x01"),
):
    rec = walk(nblocks, record)
    if rec is None:
        sys.exit(1)
    if rec["closes"]:
        print(f"  ACCEPTED A BROKEN RECORD: {name}")
        sys.exit(1)
    key = rec["why_kind"]
    if key is None:
        print(f"  {name}: refused without saying which check refused it")
        sys.exit(1)
    if key in seen:
        print(f"  BOTH '{seen[key]}' and '{name}' are caught by '{key}';")
        print("  one of the equations between them has never rejected anything")
        sys.exit(1)
    seen[key] = name
    print(f"  {name}: rejected by {key} — {rec['why']}")
print(f"  4 breaks, {len(seen)} distinct checks — none redundant")
PY
[ $? -eq 0 ] && good "the record walk closes on a correct record and on nothing else" \
             || bad "the measurement record walk accepted something it should have rejected"

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

step "every LOG.md entry is dated the day its work was committed"
# ★ ADR 0012. Eleven entries agreed with `git log` and two did not: those two
# carried dates from plan/, which is not in this repository and by policy never
# will be, so a reader could check them only against a calendar they cannot
# open. The rule is now the simplest one that is checkable — a heading's date
# has to be a date on which something was committed.
#
# A shallow clone cannot answer this, and what to do about that depends on who
# is asking.
#
# ★ Locally it skips, because a shallow clone is a reasonable thing to have.
#   In CI it FAILS, and that is the whole point: the job's log is not readable
#   without a token — the API returns 403 even for a public repository — so a
#   green run has to *mean* the comparison happened. If a skip were allowed
#   there, dropping `fetch-depth: 0` from ci.yml would silently disarm this
#   step and nothing would ever go red. That is precisely the failure ADR 0012
#   describes, rebuilt inside the check written to prevent it.
if [ "$(git rev-parse --is-shallow-repository 2>/dev/null)" = "true" ]; then
    if [ -n "${CI:-}" ]; then
        bad "shallow clone in CI — ci.yml must keep fetch-depth: 0 on this job"
    else
        printf '  --   shallow clone — LOG.md dates not compared against git log\n'
    fi
else
    log_dates=$(grep -oE '^## 2[0-9]{3}-[0-9]{2}-[0-9]{2}' LOG.md | cut -d' ' -f2 | sort -u)
    commit_dates=$(git log --format=%ad --date=short | sort -u)
    undated=""
    for d in $log_dates; do
        printf '%s\n' "$commit_dates" | grep -qxF "$d" || undated="$undated $d"
    done
    if [ -n "$undated" ]; then
        bad "LOG.md heading dates with no commit that day:$undated"
    else
        good "$(printf '%s\n' "$log_dates" | wc -l | tr -d ' ') distinct entry dates, every one has commits"
    fi
fi

step "the fragmentation arithmetic, and the two formulas it is usually confused with"
# ★ Two layers split a large SPDM message and they cost different things: a
# chunk is a whole request/response round trip, an MCTP packet is a continuation
# of one message. A tool that adds them together adds an RTT to a byte.
#
# The selftest checks the cases that SEPARATE the right formula from the
# subtract-the-transport-header version everybody writes, and it computes the
# rival rather than describing it.
#
# 🔴 That sentence used to end "...: 177 bytes at MTU 64 is 3 packets, and the
# subtract-the-header version says 4." It says 3 — 59 x 3 = 177 — so 177 is one
# of the 300 lengths in 1..399 where the two AGREE, and the case named here as
# the separating one separated nothing. It survived three weeks because the
# rival was a sentence and never a function. Standing rule 18.
if out="$(python3 bench/exp04_fragmentation.py --selftest 2>&1)"; then
    printf '%s\n' "$out" | sed -n '$p' | sed 's/^/  /'
    good "the fragmentation formulas reject the versions they are confused with"
else
    printf '%s\n' "$out" | sed 's/^/  /'
    bad "bench/exp04_fragmentation.py --selftest failed"
fi

step "the chunk round-trip model reproduces the sweep it was built from"
# ★ This is what makes the chunk numbers a MODEL rather than an extrapolation,
# and therefore what makes them publishable without a "computed" label while the
# MCTP numbers beside them carry one.
#
# The sweep varied DataTransferSize over a 32x range on one build and counted
# what happened; this replays all twelve captures through the formula and
# requires the same answer. A model that agreed at one point would be a
# coincidence, which is why the check is the whole sweep and not one arm.
sweep="$(ls -d bench/data/w8-dts-sweep-* 2>/dev/null | sort | tail -1)"
if [ -z "$sweep" ]; then
    bad "no bench/data/w8-dts-sweep-* run: the chunk model has nothing to be validated against, and an unvalidated model must not be published as a measurement"
elif out="$(python3 bench/exp04_fragmentation.py --validate "$sweep" 2>&1)"; then
    printf '%s\n' "$out" | sed -n '$p' | sed 's/^/  /'
    good "the chunk model reproduces every measured round-trip count in ${sweep##*/}"
else
    printf '%s\n' "$out" | sed 's/^/  /'
    bad "the chunk model disagrees with the sweep it claims to describe"
fi

step "the MCTP packet model reproduces the link it was measured on"
# ★ The Gate 5 counterpart of the step above, and the thing that lets
# docs/fragmentation.md stop saying [computed] at one transmission unit.
#
# The captures this replays were taken off an AF_PACKET socket on a real
# mctp-serial interface inside a guest. --observed regroups the packets into
# messages out of their own SOM/EOM/tag fields, compares each message's packet
# count against the model, AND reports how many of them are lengths at which
# the plausible wrong formula would have answered differently. The last part is
# the one that makes the rest mean something: a capture whose every length is
# one the two formulas agree about would print a column of ticks and
# discriminate nothing.
afm="$(ls -d bench/data/w9-afmctp-2* 2>/dev/null | sort | tail -1)"
if [ -z "$afm" ]; then
    bad "no bench/data/w9-afmctp-* run: the MCTP packet counts have nothing to be validated against"
else
    mctp_fail=0
    for lp in "$afm"/*.link.pcap; do
        [ -e "$lp" ] || continue
        if out="$(python3 bench/exp04_fragmentation.py --observed "$lp" 2>&1)"; then
            printf '%s\n' "$out" | grep -E '^  ★' | sed 's/^/  /'
        else
            printf '%s\n' "$out" | tail -5 | sed 's/^/  /'
            mctp_fail=1
        fi
    done
    if [ "$mctp_fail" -eq 0 ]; then
        good "the packet model reproduces every observed MCTP message in ${afm##*/}"
    else
        bad "an observed MCTP capture disagrees with the model, or lost packets"
    fi
fi

step "the controlled flags are the ones the published captures were taken with"
# ★ harness/lib/arms.sh was extracted out of harness/run_pair.sh on 2026-09-18
# so that harness/run_afmctp.sh could run the SAME arms across a real MCTP
# link. Two copies of that list would have made "the same experiment over a
# different transport" a claim about two flag lists that nobody compares.
#
# One copy is not enough on its own either: the file could drift from what the
# published captures were actually taken with, and every comparison against
# them would quietly stop being like-for-like. So the live array is compared
# against the controlled_flags string recorded in the manifests of the runs
# that are in this repository. That is what makes the extraction checkable
# rather than merely careful.
# shellcheck source=lib/arms.sh
if ! . harness/lib/arms.sh 2>/dev/null; then
    bad "harness/lib/arms.sh could not be sourced"
else
    live="${COMMON[*]}"
    arms_checked=0
    arms_fail=0
    for m in bench/data/w7-pqc-ab-*/manifest.json \
             bench/data/w8-pqc-matrix-*/manifest.json \
             bench/data/w9-afmctp-2*/manifest.json; do
        [ -f "$m" ] || continue
        rec="$(python3 -c '
import json, sys
print(json.load(open(sys.argv[1]))["run"].get("controlled_flags", ""))' "$m")"
        [ -n "$rec" ] || continue
        arms_checked=$((arms_checked + 1))
        if [ "$rec" != "$live" ]; then
            arms_fail=1
            printf '  %s\n' "$(basename "$(dirname "$m")")"
            printf '    recorded: %s\n' "$rec"
            printf '    live    : %s\n' "$live"
        fi
    done
    if [ "$arms_checked" -eq 0 ]; then
        bad "no manifest records controlled_flags, so the arm list is unattributed"
    elif [ "$arms_fail" -eq 0 ]; then
        good "the controlled set matches all ${arms_checked} manifests that record it"
    else
        bad "harness/lib/arms.sh has drifted from the captures it produced"
    fi
fi

step "the transport programs compile, twice, one of the ways with sanitizers"
# Neither program can be RUN here: mctp_bridge needs CONFIG_MCTP, which this
# kernel does not have, and doe_probe needs a device with a DOE capability,
# which this machine does not have. Both run in the guest. What CI can do
# without a virtual machine is exactly this, and transport/Makefile says so in
# the file rather than leaving the gap unexplained.
if out="$(make -s -C transport clean >/dev/null 2>&1; make -s -C transport 2>&1 && make -s -C transport check 2>&1)"; then
    printf '%s\n' "$out" | sed 's/^/  /'
    good "transport/ builds clean under -Werror and under two sanitizers"
else
    printf '%s\n' "$out" | tail -12 | sed 's/^/  /'
    bad "transport/ did not build"
fi

step "a flavor that is defined by a patch has that patch in this checkout"
# harness/lib/common.sh's flavor_patch() names a patch a flavor cannot be built
# without. third_party/<flavor>.pin records its SHA-256 at build time. If the
# two disagree, a capture attributing itself to that flavor is attributing
# itself to a build nobody can reconstruct — ADR 0009.
#
# Checked here rather than at build time because the failure it catches is a
# patch edited AFTER a build: the pin still names the old digest and the tree
# still compiles.
patch_problems=0
for pin in third_party/spdm-emu-*.pin; do
    want_patch="$(sed -n 's/^flavor-patch=//p' "$pin" | head -1)"
    [ -n "$want_patch" ] || continue
    want_sha="$(sed -n 's/^flavor-patch-sha256=//p' "$pin" | head -1)"
    if [ ! -f "$want_patch" ]; then
        printf '  %s names %s, which is not in this checkout\n' "${pin##*/}" "$want_patch"
        patch_problems=$((patch_problems + 1))
        continue
    fi
    got_sha="$(sha256sum "$want_patch" | cut -d' ' -f1)"
    if [ "$got_sha" != "$want_sha" ]; then
        printf '  %s: %s has changed since the build\n' "${pin##*/}" "$want_patch"
        printf '      pin says %s\n' "${want_sha:0:16}…"
        printf '      file is %s\n' "${got_sha:0:16}…"
        patch_problems=$((patch_problems + 1))
    else
        printf '  %s pins %s at %s…\n' "${pin##*/}" "$want_patch" "${got_sha:0:16}"
    fi
done
if [ "$patch_problems" -eq 0 ]; then
    good "every flavor patch a pin names is present and unchanged"
else
    bad "a pin and the patch it names have drifted apart"
fi

step "every document quoting a specification quotes the pinned one"
# A pin carrying `sha256=` and `quoted-in=` names a document that is NOT
# vendored — the DMTF specifications this week cites live outside the repo,
# because they are not ours to redistribute. What is inside the repo is the
# digest of the exact file that was read, and the documents that cite it.
#
# Those two can drift apart in the direction that matters: someone re-downloads
# a specification, updates the pin, and six documents keep quoting the old
# digest. CLAUDE.md asks a person to grep for the old version number after
# moving a pin, because that has already happened once on 2026-08-16. This is
# the same instruction with the remembering taken out.
python3 - <<'PY'
import pathlib, sys

problems, checked = [], 0
pins = sorted(pathlib.Path("third_party").glob("*.pin"))
for pin in pins:
    fields = {}
    for line in pin.read_text(encoding="utf-8").splitlines():
        if line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        fields[k.strip()] = v.strip()
    digest, quoted = fields.get("sha256"), fields.get("quoted-in")
    if not digest or not quoted:
        continue
    for rel in (q.strip() for q in quoted.split(",") if q.strip()):
        target = pathlib.Path(rel)
        if not target.exists():
            problems.append(f"{pin.name}: quoted-in names {rel}, which does not exist")
            continue
        if digest not in target.read_text(encoding="utf-8", errors="replace"):
            problems.append(f"{rel} does not carry the sha256 in {pin.name}")
            problems.append(f"          pin says {digest}")
            continue
        checked += 1
        print(f"  {rel} quotes {pin.name} at {digest[:16]}…")

if checked == 0:
    print("  no pin declares a quoted-in= file")
for line in problems:
    print("  " + line)
sys.exit(1 if problems else 0)
PY
[ $? -eq 0 ] && good "no document quotes a specification digest the pin disagrees with" \
             || bad "a pinned specification and a document that cites it have drifted apart"

step "the capability-bit names were checked against the pinned libspdm"
# fields.py names capability bits from a table transcribed by hand out of
# libspdm's spdm.h, and section 10 of the walkthrough names what that leaves
# open: --check cannot notice a bit upstream renamed, because a wrong name stays
# consistent with itself and no capture disagrees with it.
#
# `fields.py --verify-tables <spdm.h>` compares the two directly, but it needs
# the upstream source and CI has none. So the comparison is pinned. This step
# checks the pin: the header must have been read at the same libspdm commit the
# captures came from, and the tables must still have the number of entries that
# comparison found. Move the emulator pin without re-reading the header, or add
# a bit by hand, and the build goes red asking for the check to be re-run.
python3 - <<'PY'
import pathlib, sys


def pinned(path):
    out = {}
    for line in pathlib.Path(path).read_text(encoding="utf-8").splitlines():
        if line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        out[key.strip()] = value.strip()
    return out


header_pin = pathlib.Path("third_party/spdm-h.pin")
if not header_pin.exists():
    print("  third_party/spdm-h.pin is missing")
    print("  run: python3 harness/fields.py --verify-tables <spdm.h> --write-pin")
    sys.exit(1)

hp, ep = pinned(header_pin), pinned("third_party/spdm-emu-pqc.pin")
if hp.get("libspdm") != ep.get("libspdm"):
    print(f"  the bit names were checked against libspdm {hp.get('libspdm', '?')[:7]}")
    print(f"  the captures were produced by libspdm     {ep.get('libspdm', '?')[:7]}")
    print("  re-run: python3 harness/fields.py --verify-tables <spdm.h> --write-pin")
    sys.exit(1)

sys.path.insert(0, "harness")
import fields as F                                          # noqa: E402

local = sum(1 for side, _bit in F.LOCAL_BIT_NAMES if side == "requester")
want_req, want_rsp = int(hp["requester-bits"]) + local, int(hp["responder-bits"])
if (len(F.REQ_FLAGS), len(F.RSP_FLAGS)) != (want_req, want_rsp):
    print(f"  the tables hold {len(F.REQ_FLAGS)} requester and {len(F.RSP_FLAGS)} "
          f"responder bits; the pin was written against {want_req} and {want_rsp}")
    print("  a bit was added or removed without re-reading the header")
    sys.exit(1)

print(f"  libspdm {hp['libspdm'][:7]}, spdm.h {hp['sha256'][:16]}…, "
      f"read {hp['verified-at']}")
print(f"  {want_req} requester and {want_rsp} responder capability bits")
PY
[ $? -eq 0 ] && good "the bit names come from the same libspdm as the captures" \
             || bad "the capability tables and the pinned libspdm have drifted apart"

step "two tools agree on how many bytes went down the wire"
# pcapcount.py owns the capture file and fields.py never opens one. That
# separation is what lets them check each other, because neither can be wrong in
# a way the other would repeat.
#
# Every record in these captures carries five bytes of transport framing ahead
# of the SPDM message — the four-byte mctp_header_t plus the MCTP message-type
# byte, taken apart in docs/transports.md — and nothing is ever fragmented. So
# for an MCTP capture whose decode is complete:
#
#     pcap captured bytes  ==  SPDM message bytes  +  5 x messages
#
# This is added after the double count it would have caught, not before, and it
# is worth saying which: it finds nothing today. It is here so that the next
# disagreement between these two tools is found by the build rather than by
# someone noticing a number looks large.
python3 - <<'PY'
import json, pathlib, subprocess, sys

FRAMING = 5
checked, skipped, problems = [], [], []


def tool(script, *args):
    out = subprocess.run([sys.executable, script, *args], capture_output=True, text=True)
    if out.returncode != 0:
        raise SystemExit(f"  {script} failed on {args[0]}: {out.stderr.strip()}")
    return json.loads(out.stdout)


for decode in sorted(pathlib.Path("bench/data").glob("*/*.decode.txt")):
    name = f"{decode.parent.name}/{decode.name}"
    hexfile = decode.with_name(decode.name.replace(".decode.txt", ".hex.txt"))
    pcap = decode.with_name(decode.name.replace(".decode.txt", ".pcap"))
    if not hexfile.exists() or not pcap.exists():
        skipped.append(f"{name}: no hex dump or no capture beside it")
        continue
    f = tool("harness/fields.py", str(decode), "--json")
    if f["source"]["decode_truncated"]:
        skipped.append(f"{name}: {f['source']['truncation_reason']}")
        continue
    if f["transport"]["link_type"] != "MCTP":
        skipped.append(f"{name}: link type is {f['transport']['link_type']}")
        continue
    p = tool("harness/pcapcount.py", str(pcap), "--json")["summary"]
    if f["messages"]["decoded"] != p["packets"]:
        problems.append(f"{name}: {p['packets']} packets but {f['messages']['decoded']} decoded")
        continue
    want = f["message_bytes"]["total"] + FRAMING * p["packets"]
    if p["captured_bytes_total"] != want:
        problems.append(f"{name}: capture holds {p['captured_bytes_total']} bytes, "
                        f"{f['message_bytes']['total']} + {FRAMING} x {p['packets']} = {want}")
        continue
    checked.append(f"{name}: {p['captured_bytes_total']} = "
                   f"{f['message_bytes']['total']} + {FRAMING} x {p['packets']}")

for line in checked:
    print("  " + line)
for line in skipped:
    print(f"  --   skipped {line}")
for line in problems:
    print("  " + line)
if not checked:
    print("  no capture could be cross-checked")
    sys.exit(1)
sys.exit(1 if problems else 0)
PY
[ $? -eq 0 ] && good "the pcap layer and the SPDM layer account for the same bytes" \
             || bad "pcapcount.py and fields.py disagree about a capture"

step "a second parser reaches the same per-message byte counts"
# The step above compares one total against another total, which is one
# equation over a whole capture: a message counted 200 bytes too large and
# another 200 too small would satisfy it.
#
# bench/pcapstat.py closes that gap. It walks the capture file itself, strips
# the five bytes of MCTP framing, reads the RequestResponseCode out of each
# SPDM header and totals per message type — never opening a decode.
# fields.py reaches the same per-type totals from spdm_dump's hex output and
# never opens a capture. Requiring agreement PER TYPE is eighteen equations on
# the walkthrough capture instead of one.
#
# A truncated decode is reported rather than failed: spdm_dump stops partway
# through the post-quantum arm, so the two tools are genuinely not looking at
# the same thing there, and pcapstat prints how much of the capture the decoder
# does not see instead of demanding that a prefix equal a whole.
# Before requiring the two parsers to agree, require the new one to be capable
# of disagreeing. bench/pcapstat.py --selftest builds ALGORITHMS responses and
# ERROR responses byte by byte, parses them, and then hands the comparison a
# pair that does not match — standing rule 11, applied to a check that is
# otherwise a dictionary comparison over inputs that have always matched.
if out="$(python3 bench/pcapstat.py --selftest 2>&1)"; then
    printf '%s
' "$out" | sed -n '$p' | sed 's/^/  /'
    good "the capture parsers refuse a wrong answer before being asked for a right one"
else
    printf '%s
' "$out" | sed 's/^/  /'
    bad "bench/pcapstat.py --selftest failed"
fi

fails=0
total=0
shopt -s nullglob
for pcap in bench/data/*/*.pcap; do
    # ★ Skip the Gate 5 link captures. Every other capture in bench/data/ has
    # one record per SPDM MESSAGE; a *.link.pcap has one record per MCTP
    # PACKET, so a 16,853-byte certificate chain is 264 records and none of
    # them is a message. Reading one here would not be a false alarm, it would
    # be a category error — and on 2026-09-18 it was, until this line.
    # bench/exp04_fragmentation.py --observed is what owns these files.
    case "$pcap" in *.link.pcap) continue ;; esac
    total=$((total + 1))
    if ! out="$(python3 bench/pcapstat.py "$pcap" --check 2>&1)"; then
        printf '%s\n' "$out" | grep -E '^\s+FAIL' | sed 's/^/  /'
        printf '  in %s\n' "$pcap"
        fails=$((fails + 1))
    fi
done
if [ "$total" -eq 0 ]; then
    bad "no capture to cross-check"
elif [ "$fails" -eq 0 ]; then
    good "$total capture(s): pcapstat.py and fields.py agree message type by message type"
else
    bad "$fails capture(s) where the two parsers disagree"
fi

step "every published cross-capture number still comes out of its captures"
# fields.py --check guards a number against the ONE capture named beside it.
# A ratio has two captures and belongs to neither, so it has nowhere to live
# under that mechanism — and a ratio is exactly the form every post-quantum
# cost claim takes. bench/claims.json writes the derivation out; this re-runs
# it. Tolerances there are all zero, because these are byte counts re-derived
# from committed captures and a tolerance would only be absorbing a change in
# the file.
if out="$(python3 harness/check_claims.py 2>&1)"; then
    printf '%s
' "$out" | sed -n '$p' | sed 's/^/  /'
    good "bench/claims.json re-derives from the captures it names"
else
    printf '%s
' "$out" | sed 's/^/  /'
    bad "a published number no longer comes out of its capture"
fi
# And the companion, because a checker that has only seen agreeing inputs is a
# float comparison that happens to agree.
if out="$(python3 harness/check_claims.py --selftest 2>&1)"; then
    printf '%s
' "$out" | sed -n '$p' | sed 's/^/  /'
    good "the claims checker refuses a value that has drifted"
else
    printf '%s
' "$out" | sed 's/^/  /'
    bad "harness/check_claims.py --selftest failed"
fi

step "the stock measurement record is the same in every baseline ever taken"
# docs/tamper.md's whole argument rests on one digest: the 528-byte measurement
# record a responder produces when nothing has been done to it. Two claims lean
# on it — "the added lines change nothing when no fixture is named", and "a
# fixture holding upstream's own values reproduces upstream's own record" — and
# both are comparisons against a number that would be worthless if it drifted.
#
# It has not drifted. The record holds no nonce and no timestamp, so it is a
# run-invariant, and this asserts that over every baseline run in the
# repository plus the two tamper arms that must equal them. Four runs, four
# dates, both certificate chains, and a binary built before the patch existed
# alongside one built after it.
#
# Derived from the DECODES rather than from the committed fields.json, so it
# keeps working on runs whose derivations predate a change to fields.py — which
# is precisely the situation this repository was in on 2026-09-01.
python3 - <<'PY'
import json, pathlib, subprocess, sys

seen = {}
for decode in sorted(pathlib.Path("bench/data").glob("*/*.decode.txt")):
    run = decode.parent.name
    arm = decode.name.replace(".decode.txt", "")
    stock = ("baseline" in run) or (arm in ("t0_none", "t0_clean"))
    if not stock:
        continue
    if not decode.with_name(arm + ".hex.txt").exists():
        continue
    out = subprocess.run([sys.executable, "harness/fields.py", str(decode), "--json"],
                         capture_output=True, text=True)
    if out.returncode != 0:
        continue
    got = json.loads(out.stdout)
    if got["source"]["decode_truncated"]:
        continue
    rec = (got.get("layout") or {}).get("measurement_record")
    if not rec or rec["blocks_walked"] != 8:
        continue
    if not rec["closes"]:
        print(f"  {run}/{arm}: the record does not close — {rec['why']}")
        sys.exit(1)
    seen.setdefault(rec["sha256"], []).append(f"{run}/{arm}")

if not seen:
    print("  no eight-block measurement record found in any baseline")
    sys.exit(1)
for digest, where in sorted(seen.items(), key=lambda kv: -len(kv[1])):
    print(f"  {digest[:16]}…  {len(where)} arm(s)")
    for w in where:
        print(f"      {w}")
if len(seen) != 1:
    print("  the stock measurement record is NOT the same everywhere")
    sys.exit(1)
runs = {w.split("/")[0] for w in next(iter(seen.values()))}
print(f"  one digest across {len(runs)} run(s)")
PY
[ $? -eq 0 ] && good "every untampered capture carries the same measurement record" \
             || bad "the stock measurement record differs between runs"

step "every fields.json a document cites is still reproducible"
# harness/capture.sh writes a *.fields.json beside each capture, and
# prov_finish hashes it into manifest.json alongside the pcap. But a pcap is
# evidence and a fields.json is a DERIVATION, and a derivation committed beside
# its inputs can disagree with the tool that produced it. It did: after the
# double count was fixed on 2026-08-28, the committed JSON still said 15,803
# where fields.py had begun saying 11,291, and the manifest attested to the
# stale one. Nothing noticed, because the manifest checks that a file has not
# been altered, which is a different question from whether it is still true.
#
# So a derivation has to be reproducible from its inputs, and this checks it.
# `source.decode_file` is excluded because it records the absolute path the
# capture ran from, which is a property of the machine and not of the result.
#
# Scope, deliberately: the run directories that a document actually cites,
# found by reading their <!-- capture: --> directives rather than from a list
# that would go stale exactly the way this did. Runs no document cites keep the
# guarantee their manifest gives them — that they are unaltered — which is all
# this repository has ever claimed about them.
python3 - <<'PY'
import json, pathlib, re, subprocess, sys

CAPTURE_RE = re.compile(r"<!--\s*capture:\s*(?P<path>\S+)\s*-->")

cited = set()
for doc in sorted(pathlib.Path("docs").rglob("*.md")):
    fenced = False
    for line in doc.read_text(encoding="utf-8").splitlines():
        if line.lstrip().startswith("```"):
            fenced = not fenced
            continue
        if fenced:
            continue
        found = CAPTURE_RE.search(line)
        if found:
            path = pathlib.Path(found.group("path"))
            if path.parts[:2] == ("bench", "data") and path.parent.is_dir():
                cited.add(path.parent)

if not cited:
    print("  no document cites a run directory — nothing to check")
    sys.exit(0)

problems, checked = [], 0
for run in sorted(cited):
    for stored in sorted(run.glob("*.fields.json")):
        decode = stored.with_name(stored.name.replace(".fields.json", ".decode.txt"))
        if not decode.exists():
            problems.append(f"{stored}: no decode beside it to reproduce it from")
            continue
        out = subprocess.run([sys.executable, "harness/fields.py", str(decode), "--json"],
                             capture_output=True, text=True)
        if out.returncode != 0:
            problems.append(f"{stored}: fields.py failed on its decode")
            continue
        fresh, old = json.loads(out.stdout), json.loads(stored.read_text(encoding="utf-8"))
        for side in (fresh, old):
            side.get("source", {}).pop("decode_file", None)
        if fresh == old:
            checked += 1
            continue
        keys = sorted({k for k in set(fresh) | set(old) if fresh.get(k) != old.get(k)})
        problems.append(f"{stored}: differs in {', '.join(keys)}")
        problems.append("          re-run: bash harness/capture.sh --name "
                        f"{run.name.rsplit('-', 1)[0]}, then point the document at the new run")

print(f"  {checked} derivation(s) across {len(cited)} cited run(s) reproduce exactly")
for line in problems:
    print("  " + line)
sys.exit(1 if problems else 0)
PY
[ $? -eq 0 ] && good "a committed derivation still equals what the tool produces" \
             || bad "a committed fields.json no longer matches its own decode"

step "the layout reconstruction can still fail"
# The walkthrough's offsets are checked by rebuilding each signed response and
# requiring the bytes left over to equal the signature size the negotiation
# implies. A check is worth exactly what it rejects, so this builds a correct
# CHALLENGE_AUTH by hand, confirms it closes at the offsets the document
# publishes, and then breaks it three ways — one byte short, a RequesterContext
# that does not echo the request, and a different signature algorithm — and
# requires every one to be reported rather than accepted.
python3 - <<'PY'
import json, pathlib, subprocess, sys, tempfile

H, S = 48, 96                       # SHA-384, ECDSA-P384
CTX = bytes(range(0x11, 0x19))      # the RequesterContext the request sends

ALGS = ("1 (1) MCTP(5) RSP->REQ SPDM(14, 0x63) SPDM_ALGORITHMS "
        "(Hash=0x00000002(SHA_384), MeasHash=0x00000008(SHA_512), "
        "Asym={asym}, ReqAsym=0x0008(RSAPSS_3072)) ")
CHAL = ("2 (1) MCTP(5) REQ->RSP SPDM(14, 0x83) SPDM_CHALLENGE "
        "(SlotID=0x00, HashType=0xff(AllHash)) ")
AUTH = ("3 (1) MCTP(5) RSP->REQ SPDM(14, 0x03) SPDM_CHALLENGE_AUTH "
        "(Attr=0x80(BasicMutAuth, SlotID=0x00), SlotMask=0x13) ")


def block(raw):
    return "\n".join(f"    {i:04x}: " + " ".join(f"{b:02x}" for b in raw[i:i + 32])
                     for i in range(0, len(raw), 32))


def reconstruct(asym, chal_raw, auth_raw):
    d = pathlib.Path(tempfile.mkdtemp())
    algs, algs_raw = ALGS.format(asym=asym), bytes([0x14, 0x63]) + bytes(34)
    (d / "t.decode.txt").write_text(
        "spdm_dump version 0.1\n"
        "PcapFile: Magic - 'a1b2c3d4', version2.4, DataLink - 291 (MCTP),"
        " MaxPacketSize - 65536\n" + algs + "\n" + CHAL + "\n" + AUTH + "\n",
        encoding="utf-8")
    (d / "t.hex.txt").write_text(
        algs + "\n  SPDM Message:\n" + block(algs_raw) + "\n"
        + CHAL + "\n  SPDM Message:\n" + block(chal_raw) + "\n"
        + AUTH + "\n  SPDM Message:\n" + block(auth_raw) + "\n", encoding="utf-8")
    out = subprocess.run([sys.executable, "harness/fields.py",
                          str(d / "t.decode.txt"), "--json"],
                         capture_output=True, text=True)
    if out.returncode != 0:
        print("  fields.py failed:", out.stderr.strip())
        return None
    return json.loads(out.stdout)["layout"]


good_chal = bytes([0x14, 0x83, 0x00, 0xFF]) + bytes(32) + CTX
good_auth = (bytes([0x14, 0x03, 0x80, 0x13]) + bytes(H) + bytes(32) + bytes(H)
             + b"\x00\x00" + CTX + bytes(S))

lay = reconstruct("0x00000080(ECDSA_P384)", good_chal, good_auth)
if lay is None or lay["closed"] != 1:
    print("  a correct CHALLENGE_AUTH did not close:", lay and lay["unexplained"])
    sys.exit(1)
ca = lay["challenge_auth"]
if (ca["nonce_offset"], ca["signature_bytes"],
        ca["summary_hash_sized_by"]) != (52, 96, "BaseHashAlgo"):
    print("  the intact reconstruction disagrees with the document:", ca)
    sys.exit(1)
print(f"  intact: closes — nonce at {ca['nonce_offset']}, "
      f"signature {ca['signature_bytes']} B, summary hash by {ca['summary_hash_sized_by']}")

for name, asym, chal, auth in (
    ("one byte short", "0x00000080(ECDSA_P384)", good_chal, good_auth[:-1]),
    ("context does not echo", "0x00000080(ECDSA_P384)", good_chal,
     good_auth[:134] + bytes([good_auth[134] ^ 0xFF]) + good_auth[135:]),
    ("signature algorithm changed", "0x00000010(ECDSA_P256)", good_chal, good_auth),
):
    lay = reconstruct(asym, chal, auth)
    if lay is None:
        sys.exit(1)
    if lay["closed"] != 0 or not lay["unexplained"]:
        print(f"  ACCEPTED A BROKEN CASE: {name} -> closed={lay['closed']}")
        sys.exit(1)
    print(f"  {name}: rejected")
PY
[ $? -eq 0 ] && good "the reconstruction closes on a correct message and on nothing else" \
             || bad "the layout reconstruction accepted a message it should have rejected"

step "the certificate reconstruction can still fail"
# CHALLENGE_AUTH is over-determined by one equation. CERTIFICATE is over-
# determined by four, and each of the four has to be shown rejecting something
# on its own or it is decoration:
#
#   closure     the message length against its header plus PortionLength
#   agreement   the chain's own Length against PortionLength + RemainderLength
#   structure   the certificates as a whole number of DER SEQUENCEs, consumed
#               to the last byte
#   digest      RootHash against the hash of the first certificate, computed
#
# The fourth is reported rather than enforced, because DSP0274 permits a chain
# whose root is not among its certificates — so the test requires the field to
# turn FALSE rather than requiring the message to be refused. A check that
# cannot say "no" and a check that says "no" wrongly are different failures and
# this suite has to distinguish them.
python3 - <<'PY'
import hashlib, json, pathlib, subprocess, sys, tempfile

H = 48                                   # SHA-384, which the ALGORITHMS line below negotiates

ALGS = ("1 (1) MCTP(5) RSP->REQ SPDM(14, 0x63) SPDM_ALGORITHMS "
        "(Hash=0x00000002(SHA_384), MeasHash=0x00000008(SHA_512), "
        "Asym=0x00000080(ECDSA_P384), ReqAsym=0x0008(RSAPSS_3072)) ")
GET = ("2 (1) MCTP(5) REQ->RSP SPDM(14, 0x82) SPDM_GET_CERTIFICATE "
       "(SlotID=0x00, LargeCert=0x80, Attr=0x00(), Offset=0x00000000, "
       "Length=0x00027ff0) ")
CERT = ("3 (1) MCTP(5) RSP->REQ SPDM(14, 0x02) SPDM_CERTIFICATE "
        "(SlotID=0x00, LargeCert=0x80, Attr=0x01(DEVICE), PortLen=0x00000295, "
        "RemLen=0x00000000) ")


def seq(body: bytes) -> bytes:
    """A DER SEQUENCE with a minimally encoded length — a stand-in certificate."""
    n = len(body)
    if n < 0x80:
        return bytes([0x30, n]) + body
    width = (n.bit_length() + 7) // 8
    return bytes([0x30, 0x80 | width]) + n.to_bytes(width, "big") + body


def _stretched(cert: bytes) -> bytes:
    """The same bytes, declaring one more content byte than it carries.

    Byte 3 is the low half of the two-byte DER length in `30 82 01 2C ...`, so
    raising it turns 300 into 301 without moving anything. Same buffer length,
    same chain length, one certificate that no longer fits.
    """
    out = bytearray(cert)
    out[3] += 1
    return bytes(out)


CERTS = [seq(b"\xAA" * 100), seq(b"\xBB" * 200), seq(b"\xCC" * 300)]
BLOB = b"".join(CERTS)
ROOT = hashlib.sha384(CERTS[0]).digest()


DIG = ("4 (1) MCTP(5) RSP->REQ SPDM(14, 0x01) SPDM_DIGESTS "
       "(SupportedSlotMask=0x01, ProvisionedSlotMask=0x01) ")


def digests(slots=1, extra=4, pad=0):
    """4 + n x (H + extra) bytes, plus `pad` the reconstruction must not accept."""
    return (bytes([0x14, 0x01, (1 << slots) - 1, (1 << slots) - 1])
            + bytes(slots * (H + extra) + pad))


def build(chain_len=None, portion=None, remainder=0, root=None, blob=None,
          trim=0, req_len=16):
    blob = BLOB if blob is None else blob
    root = ROOT if root is None else root
    chain = (chain_len if chain_len is not None else 4 + H + len(blob))
    body = chain.to_bytes(4, "little") + root + blob
    port = portion if portion is not None else len(body)
    rsp = (bytes([0x14, 0x02, 0x80, 0x01]) + bytes(4)
           + port.to_bytes(4, "little") + remainder.to_bytes(4, "little") + body)
    if trim:
        rsp = rsp[:-trim]
    req = (bytes([0x14, 0x82, 0x80, 0x00]) + bytes(4)
           + (0).to_bytes(4, "little") + (0x27FF0).to_bytes(4, "little"))[:req_len]
    return req, rsp


def block(raw):
    return "\n".join(f"    {i:04x}: " + " ".join(f"{b:02x}" for b in raw[i:i + 32])
                     for i in range(0, len(raw), 32))


def run(req, rsp, dig=None):
    dig = digests() if dig is None else dig
    d = pathlib.Path(tempfile.mkdtemp())
    algs_raw = bytes([0x14, 0x63]) + bytes(34)
    (d / "t.decode.txt").write_text(
        "spdm_dump version 0.1\n"
        "PcapFile: Magic - 'a1b2c3d4', version2.4, DataLink - 291 (MCTP),"
        " MaxPacketSize - 65536\n" + ALGS + "\n" + GET + "\n" + CERT + "\n" + DIG + "\n",
        encoding="utf-8")
    (d / "t.hex.txt").write_text(
        ALGS + "\n  SPDM Message:\n" + block(algs_raw) + "\n"
        + GET + "\n  SPDM Message:\n" + block(req) + "\n"
        + CERT + "\n  SPDM Message:\n" + block(rsp) + "\n"
        + DIG + "\n  SPDM Message:\n" + block(dig) + "\n", encoding="utf-8")
    out = subprocess.run([sys.executable, "harness/fields.py",
                          str(d / "t.decode.txt"), "--json"],
                         capture_output=True, text=True)
    if out.returncode != 0:
        print("  fields.py failed:", out.stderr.strip())
        return None
    return json.loads(out.stdout)["layout"]


lay = run(*build())
if lay is None:
    sys.exit(1)
cert = lay["certificate"]
if not cert or not cert.get("closes"):
    print("  a correct CERTIFICATE did not close:", lay["unexplained"])
    sys.exit(1)
want = {"chain_offset": 16, "chain_length": 4 + H + len(BLOB),
        "root_hash_offset": 20, "certificates": 3,
        "certificate_bytes": [len(c) for c in CERTS],
        "root_hash_matches_first_certificate": True, "large_form": True}
wrong = {k: (cert.get(k), v) for k, v in want.items() if cert.get(k) != v}
if wrong:
    print("  the intact reconstruction disagrees with the document:", wrong)
    sys.exit(1)
print(f"  intact: closes — chain at {cert['chain_offset']}, Length "
      f"{cert['chain_length']} = {cert['portion_length']} + {cert['remainder_length']}, "
      f"{cert['certificates']} certificates "
      f"{'+'.join(str(n) for n in cert['certificate_bytes'])}, RootHash verified")

# DIGESTS is reconstructed from two hypotheses that differ by 4 bytes per slot,
# and only one can close. That is what turns "the requester dropped two slots"
# into an exact 104 bytes rather than an observation, so it needs a length that
# neither hypothesis explains and a refusal to guess between them.
d = lay["digests"]
if not d or (d["slots"], d["per_slot_bytes"], d["total_bytes"]) != (1, H + 4, 4 + H + 4):
    print("  a correct DIGESTS did not close:", d)
    sys.exit(1)
print(f"  intact: DIGESTS {d['total_bytes']} B = 4 + {d['slots']} x "
      f"({d['digest_bytes']} + {d['per_slot_extra']}), "
      f"per-slot extra read as {d['per_slot_extra_is']}")
for pad, why in ((1, "one byte more than either hypothesis"),
                 (-2, "two bytes short, matching neither")):
    lay2 = run(*build(), dig=digests(pad=pad))
    if lay2 is None:
        sys.exit(1)
    if lay2["digests"] is not None:
        print(f"  ACCEPTED A BROKEN DIGESTS: {why}")
        sys.exit(1)
    print(f"  DIGESTS {why}: rejected")

# And the second hypothesis has to be live, or the first is hard-coded and the
# "two hypotheses, one closes" claim is decoration. A DIGESTS four bytes shorter
# is not broken: it is the same message without the per-slot key information,
# and the reconstruction has to read it as that rather than refuse it.
lay2 = run(*build(), dig=digests(extra=0))
if lay2 is None or not lay2["digests"] or lay2["digests"]["per_slot_extra"] != 0:
    print("  the digests-only hypothesis never closes:", lay2 and lay2["digests"])
    sys.exit(1)
print(f"  DIGESTS without per-slot key information: read as "
      f"{lay2['digests']['total_bytes']} B = 4 + 1 x ({H} + 0)")

caught = {}
for name, kwargs, expect in (
    ("one byte short", dict(trim=1), "reject"),
    ("chain Length disagrees with the two portion fields",
     dict(chain_len=4 + H + len(BLOB) + 8), "reject"),
    # The declared length is raised by one and the buffer is left alone, so the
    # chain is still exactly as long as both length fields say it is: only the
    # DER walk can find this. Written the other way round first — a byte
    # removed and a byte appended — which changed nothing at all, because the
    # byte removed and the byte appended were the same value. The test passed
    # by not testing anything.
    ("a certificate declaring one byte too many",
     dict(blob=CERTS[0] + CERTS[1] + _stretched(CERTS[2])), "reject"),
    ("GET_CERTIFICATE the wrong length for its Param1", dict(req_len=8), "reject"),
    ("RootHash altered", dict(root=bytes(48)), "flip"),
):
    lay = run(*build(**kwargs))
    if lay is None:
        sys.exit(1)
    got = lay["certificate"]
    if expect == "reject":
        if got is not None or not lay["unexplained"]:
            print(f"  ACCEPTED A BROKEN CASE: {name}")
            sys.exit(1)
        caught[name] = lay["unexplained"][0].split(":", 1)[1].strip()[:44]
        print(f"  {name}: rejected")
    else:
        if got is None:
            print(f"  {name}: refused the message instead of reporting the mismatch")
            sys.exit(1)
        if got["root_hash_matches_first_certificate"] is not False:
            print(f"  {name}: RootHash mismatch was not noticed")
            sys.exit(1)
        print(f"  {name}: reported as a mismatch, message still parsed")

if len(set(caught.values())) != len(caught):
    print("  two breaks are caught by the same check:", caught)
    sys.exit(1)
print(f"  {len(caught)} rejections through {len(set(caught.values()))} distinct checks")
PY
[ $? -eq 0 ] && good "the certificate reconstruction closes on a correct chain and on nothing else" \
             || bad "the certificate reconstruction accepted a chain it should have rejected"

step "every document that cites a capture still agrees with it"
# These documents are made almost entirely of stated facts, which is the
# category this project has twice caught itself getting wrong. So their numbers
# are not typed in: each is marked up as <!--claim key=value--> and re-derived
# here from the decode file the document names. A number that drifts from its
# capture is a failed build, not something a reader might notice.
#
# Discovered by reading which documents make claims, not from a list. A list is
# how docs/certchain.md would have been added and left unchecked, which is the
# same failure docs/decisions/0004 is about, one level up.
#
# Selected on the CLAIM marker rather than the capture directive, and the
# difference matters. The obvious selector was the capture directive, and it
# picked up ADR 0004 — which quotes the directive's syntax in prose while
# asserting nothing, so it failed for having no claims. Selecting on claims is
# also the complete rule: no claim can escape, because any document containing
# one is selected by containing it.
# Three outcomes, not two. A document that merely QUOTES the markup — LOG.md
# explaining what a claim looks like, RUNBOOK.md showing the syntax in a
# sentence — asserts nothing and must not be failed for it; a document that
# names a capture and asserts nothing is a different thing and is failed.
# fields.py --check says which with exit 2 against exit 1, because "verified"
# and "did not participate" are different facts and one status cannot carry
# both. The first version of this step had two outcomes and reported LOG.md as
# contradicting a capture.
found=0
skipped=0
while IFS= read -r doc; do
    python3 harness/fields.py --check "$doc"
    case $? in
        0) found=$((found + 1)); good "$doc" ;;
        2) skipped=$((skipped + 1)) ;;
        *) bad "$doc contradicts a capture it cites" ;;
    esac
done < <(git ls-files '*.md' | xargs grep -l '<!--claim ' 2>/dev/null | sort)
if [ "$found" -eq 0 ]; then
    bad "no document asserts anything against a capture — the mechanism reaches nothing"
else
    good "$found document(s) checked, $skipped that only quote the markup"
fi

step "no branch is decided by a pipeline that can lose its producer"
# The bug class this exists for cost an hour on 2026-09-10 and had been latent
# since the step it broke was written.
#
#     if make ... 2>&1 | head -2 | sed 's/^/  /'; then
#
# `head -2` closes the pipe once it has two lines. Everything upstream that is
# still writing gets SIGPIPE and exits 141, and `set -o pipefail` — which
# lib/common.sh turns on for every script here — makes the pipeline non-zero.
# The branch that should have been taken is not, and the message printed is
# about something that did not happen.
#
# `grep -q` and `grep -m N` are the same hazard and the more dangerous one,
# because they exit early exactly WHEN THEY MATCH. Two checks in this
# repository would have reported "this OpenSSL has no ML-DSA" on the machines
# that have it, which is the reverse of the truth, on the path that decides
# whether week eight's post-quantum certificate chain is possible.
#
# The fix is always the same: capture into a variable, then match with a
# here-string, which is a redirection and has no second process to fail.
python3 - <<'PY'
import pathlib, re, sys

# A pipeline whose status is a boolean: it opens a compound command, and its
# consumer is one that exits before end of input.
DECIDES = re.compile(r'^\s*(if|while|until|elif)\b|(\|\||&&)\s*$')
EARLY = re.compile(r'\|\s*(head\b|grep\s+(-\w*q|-m\b|-\w*m\s)|sed\s+-n?\s*[\'"]?\dq)')

flagged = []
for path in sorted(pathlib.Path(".").glob("harness/**/*.sh")) + \
            sorted(pathlib.Path(".").glob("certs/*.sh")):
    for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        stripped = line.strip()
        if stripped.startswith("#") or not DECIDES.search(line):
            continue
        if not EARLY.search(line):
            continue
        # A pipeline inside $( ) is a value, not a branch: its status is
        # discarded by whatever consumes the substitution.
        before = line.split("|")[0]
        if before.count("$(") > before.count(")"):
            continue
        flagged.append(f"{path}:{n}: {stripped[:96]}")

if flagged:
    print("  a branch is decided by a pipeline whose producer can be killed:")
    for f in flagged:
        print("    " + f)
    print("  capture into a variable and match with a here-string instead")
    sys.exit(1)
print("  every conditional pipeline either reads to end of input or is a value")
sys.exit(0)
PY
[ $? -eq 0 ] && good "no conditional pipeline can turn 0 into 141" \
             || bad "a branch can be decided by SIGPIPE"

step "the tamper proxy can still refuse to change a byte"
# The proxy is the only thing in this repository that produces a successful
# cryptographic rejection, and it does it by changing one byte of a message it
# has parsed. If its parse is wrong the byte lands somewhere else, the arm
# still fails, and the wrong sentence gets written about why.
#
# So its refusals are the check, not its successes. --self-test feeds the
# parser thirteen broken messages, requires each to be refused by the
# specifically named check that should catch it, and fails if any registered
# check was never exercised. One of the thirteen is the field list in
# plan/W05's own text, which omits RequesterContext.
if out="$(python3 harness/tamper_proxy.py --self-test 2>&1)"; then
    printf '%s\n' "$out" | tail -3 | sed 's/^/  /'
    good "every registered refusal fires, and the flip lands where the walk says"
else
    printf '%s\n' "$out" | sed 's/^/  /'
    bad "harness/tamper_proxy.py --self-test failed"
fi

step "a libspdm status can be named, and a C errno cannot be mistaken for one"
# Table 1's most load-bearing cell is a status code that two arms share. Naming
# it from a table is only safe if the table is right and the line shape is not
# over-matched: the emulators print "receive_platform_data Error - 2" through
# the same macro, and reading that 2 as a libspdm status would name a layer
# that had no opinion about anything.
if out="$(python3 harness/spdm_status.py --self-test 2>&1)"; then
    printf '%s\n' "$out" | tail -2 | sed 's/^/  /'
    good "severity and source are computed, names are checked against the header"
else
    printf '%s\n' "$out" | sed 's/^/  /'
    bad "harness/spdm_status.py --self-test failed"
fi

step "three tools agree on how big the certificate chain is"
# certs/check_chain.py adds up the DER files on disk and never opens a capture.
# harness/fields.py reads spdm_dump's decode and never opens a certificate.
# bench/pcapstat.py walks the capture file and opens neither. Three routes to
# one number, sharing no input:
#
#     4 + RootHash + sum of the certificates  ==  the chain's own Length field
#                                             ==  the sum of every PortionLength
#
# The third route arrived in week five, with cert_roundtrips, and it found
# something the other two could not: the 4.0.0-rc responder sends the chain in
# ONE message where the 3.8.0 responder sends it in two, and the number of
# round trips is a property of the exchange rather than of the certificates.
python3 - <<'PY'
import json, pathlib, subprocess, sys

def tool(script, *args):
    out = subprocess.run([sys.executable, script, *args],
                         capture_output=True, text=True)
    if out.returncode not in (0, 1):
        raise SystemExit(f"  {script} failed: {out.stderr.strip()[:200]}")
    return json.loads(out.stdout)

bundle = pathlib.Path("certs/out/bundle_responder.certchain.der")
on_disk = bundle.stat().st_size if bundle.exists() else None
if on_disk is None:
    print("  certs/out is not staged; the disk route is skipped")

checked, chunked, problems = [], [], []
for pcap in sorted(pathlib.Path("bench/data").glob("*/*.pcap")):
    # See the note in the pcapstat --check loop above: a *.link.pcap holds MCTP
    # packets, not SPDM messages, and the chain walk below assumes messages.
    if pcap.name.endswith(".link.pcap"):
        continue
    name = f"{pcap.parent.name}/{pcap.name}"
    stats = tool("bench/pcapstat.py", str(pcap), "--json")["summary"]
    cert = stats["certificates"]
    if cert["roundtrips"] == 0:
        continue
    if not cert["slots"]:
        # A chain larger than the negotiated DataTransferSize comes back inside
        # CHUNK_RESPONSE rather than CERTIFICATE, so there is no chain to
        # reassemble here. Reported, because a silent zero looks like a bug.
        if stats["by_type"].get("SPDM_CHUNK_RESPONSE"):
            chunked.append(f"{name}: {cert['roundtrips']} round trip(s), the "
                           "chain came back in CHUNK_RESPONSE messages")
        elif stats["by_type"].get("SPDM_ERROR"):
            # t3_cert: the responder validated its own chain, could not, and
            # answered SPDM_ERROR instead of serving the slot. There is no
            # chain because none was ever sent, which is the finding rather
            # than a failure to parse one.
            chunked.append(f"{name}: {cert['roundtrips']} round trip(s) "
                           "answered with SPDM_ERROR, so no chain was sent")
        else:
            problems.append(f"{name}: {cert['roundtrips']} GET_CERTIFICATE and "
                            "no chain reassembled")
        continue
    for c in cert["slots"]:
        if not c["closes"]:
            problems.append(f"{name} slot {c['slot']}: {c['why']}")
            continue
        if c["length_field"] != c["chain_bytes"]:
            problems.append(f"{name} slot {c['slot']}: Length field "
                            f"{c['length_field']} != {c['chain_bytes']}")
    ours = [c for c in cert["slots"]
            if c["closes"] and c["certificates_bytes"] == on_disk]
    if ours:
        checked.append(f"{name}: slot {ours[0]['slot']} carries 4 + "
                       f"{cert['root_hash_bytes']} + {on_disk} = "
                       f"{ours[0]['chain_bytes']} bytes in "
                       f"{ours[0]['messages']} message(s), "
                       f"{cert['roundtrips']} round trip(s)")

for line in checked:
    print("  " + line)
for line in chunked:
    print("  --   " + line)
for line in problems:
    print("  " + line)
if on_disk is not None and not checked:
    print(f"  no capture carries a chain whose certificates total {on_disk} bytes")
    sys.exit(1)
sys.exit(1 if problems else 0)
PY
[ $? -eq 0 ] && good "the DER files, the decode and the capture agree on the chain" \
             || bad "the three routes to the chain's size disagree"

step "an in-flight tamper is still rejected, and the device-side one still is not"
# This is the assertion the whole tamper directory exists to make, written as a
# negative: the build turns RED if a tampered measurement stops being refused.
# It reads the primary evidence rather than the table tamper.sh printed — the
# requester's own log for the status, and the committed fields.json for what
# reached the wire — so it is checking the run, not the summary of it.
#
# Four things have to hold, and the third is the one people find surprising:
#
#   t0_proxy    forwarded unchanged: no error, and the control's record
#   t2a_record  the signed CONTENT changed in flight: refused
#   t2b_sig     the SIGNATURE changed in flight:      refused, SAME status
#   t1_meas     changed at the DEVICE:                NOT refused, and the
#               record on the wire differs from the control
#
# t1_meas is asserted to keep passing. It is not a gap in the harness; it is
# the measurement that says why Gate 3 exists, and if it ever starts failing
# that is a change in libspdm worth stopping for.
python3 - <<'PY'
import json, pathlib, subprocess, sys

def status(log):
    out = subprocess.run([sys.executable, "harness/spdm_status.py", str(log),
                          "--json"], capture_output=True, text=True)
    if out.returncode not in (0, 1) or not out.stdout.strip():
        return None
    got = json.loads(out.stdout)
    return got if isinstance(got, dict) else None

def record(fields_json):
    if not fields_json.exists():
        return None
    d = json.loads(fields_json.read_text())
    return ((d.get("layout") or {}).get("measurement_record") or {}).get("sha256")

WANT = {
    "t0_proxy":   ("no status", "same record"),
    "t1_meas":    ("no status", "different record"),
    "t2a_record": ("VERIF_FAIL", "different record"),
    "t2b_sig":    ("VERIF_FAIL", "same record"),
}

demonstrated, problems, seen = 0, [], 0
for run in sorted(pathlib.Path("bench/data").glob("*-tamper-*")):
    control = record(run / "t0_clean.fields.json")
    if control is None:
        continue
    present = {c for c in WANT if (run / f"{c}.req.log").exists()}
    if not present:
        continue
    seen += 1
    print(f"  {run.name}")
    rejections = {}
    for case in sorted(present):
        st = status(run / f"{case}.req.log")
        rec = record(run / f"{case}.fields.json")
        got_status = "no status" if st is None else (st["name"] or st["status"])
        got_record = ("no record" if rec is None else
                      "same record" if rec == control else "different record")
        want_status, want_record = WANT[case]
        ok = got_status == want_status and got_record == want_record
        if st is not None and st["name"] == "VERIF_FAIL":
            rejections[case] = st["status"]
        print(f"    {'ok  ' if ok else 'FAIL'} {case:<11} {got_status:<12} "
              f"{got_record}")
        if not ok:
            problems.append(f"{run.name}/{case}: wanted {want_status} and "
                            f"{want_record}, got {got_status} and {got_record}")
    if {"t2a_record", "t2b_sig"} <= present:
        codes = set(rejections.values())
        if len(codes) == 1 and rejections:
            print(f"    ok   both in-flight tampers refused with the same "
                  f"status, {codes.pop()}")
            demonstrated += 1
        else:
            problems.append(f"{run.name}: the two in-flight tampers did not "
                            f"share one status: {rejections}")

    # The proxy and the capture are two witnesses to the same byte, and they
    # never see each other: the proxy reported what it read and what it wrote
    # while the connection was open, and fields.py read what the requester
    # ended up with, out of a file, afterwards. So for t2a_record:
    #
    #   proxy "before"  ==  the control's record   the responder sent the right one
    #   proxy "after"   ==  the record in the pcap  the requester got the wrong one
    #
    # Either half failing means the byte that changed is not the byte anybody
    # thinks changed, and that is not a distinction an exit code carries.
    report = run / "t2a_record.proxy.json"
    if report.exists():
        pr = json.loads(report.read_text()).get("tamper") or {}
        wire = record(run / "t2a_record.fields.json")
        before_ok = pr.get("record_sha256_before") == control
        after_ok = pr.get("record_sha256_after") == wire
        print(f"    {'ok  ' if before_ok else 'FAIL'} t2a_record  the proxy read "
              f"the control's record off the wire "
              f"({(pr.get('record_sha256_before') or '-')[:16]}…)")
        print(f"    {'ok  ' if after_ok else 'FAIL'} t2a_record  and what it "
              f"wrote is what the capture holds "
              f"({(pr.get('record_sha256_after') or '-')[:16]}…)")
        if not before_ok:
            problems.append(f"{run.name}/t2a_record: the responder's record was "
                            f"not the control's")
        if not after_ok:
            problems.append(f"{run.name}/t2a_record: the proxy's output digest "
                            f"is not the one in the capture")

if seen == 0:
    print("  no tamper run in bench/data carries these arms")
    sys.exit(1)
if demonstrated == 0:
    print("  no run demonstrates an in-flight tamper being rejected")
    sys.exit(1)
for line in problems:
    print("  " + line)
sys.exit(1 if problems else 0)
PY
[ $? -eq 0 ] && good "tampering in flight is refused; tampering at the device is not" \
             || bad "the tamper detection this repository claims did not hold"

step "the upstream-commit rules can still refuse a commit"
# What a change has to look like before it is sent is a checklist in
# docs/upstream/0001-corim-verify.md, and on 2026-09-13 the checklist missed
# that DMTF/spdm-emu requires an `Assisted-by:` trailer on an AI-assisted
# commit. It was found by being asked a question, not by the checklist.
#
# The commit being checked lives outside this repository, so what runs here is
# the checker's own self-test: nine throwaway commits, one compliant and eight
# breaking one rule each. The ninth is the one that matters — a sign-off with a
# gmail.com address, which the first version of the AI-detection pattern
# refused because `ai` is a substring of `gmail`.
if bash harness/check_upstream_commit.sh --self-test > /tmp/upstream-rules.$$ 2>&1; then
    sed -n '$p' /tmp/upstream-rules.$$ | sed 's/^ */  /'
    good "a compliant commit passes and eight broken ones do not"
else
    sed 's/^/  /' /tmp/upstream-rules.$$
    bad "the upstream-commit checker does not refuse what it should"
fi
rm -f /tmp/upstream-rules.$$

step "the appraisal's own encoders and policy can still reject"
# rats/ is a second implementation of somebody else's format, and the two ways
# it can be quietly wrong are an encoder that agrees only with itself and a
# policy that has only ever seen good input. Both self-tests run here.
if python3 rats/cose.py selftest > /tmp/rats-cose.$$ 2>&1; then
    sed -n '$p' /tmp/rats-cose.$$ | sed 's/^/  /'
    good "CBOR, COSE and the DER conversion, against RFC 8949's own vectors"
else
    sed 's/^/  /' /tmp/rats-cose.$$
    bad "rats/cose.py self-test failed"
fi
rm -f /tmp/rats-cose.$$
if python3 rats/appraise.py selftest > /tmp/rats-policy.$$ 2>&1; then
    grep -E 'ACCEPTS this|categories, all fired|checks, 0 failed' /tmp/rats-policy.$$ | sed 's/^/  /'
    good "every broken pair is refused, and each one names its own reason"
else
    sed 's/^/  /' /tmp/rats-policy.$$
    bad "rats/appraise.py self-test failed — a policy that cannot reject is not a policy"
fi
rm -f /tmp/rats-policy.$$

step "a tampered measurement is still REJECTED by the appraisal"
# ★ The assertion this repository is built to support, and the reason Gate 3
# exists. docs/tamper.md row 1 is a tamper NOTHING in the SPDM handshake
# refused: the device signed what it measured, every signature verified, the
# requester exited 0. rats/out/expected.json says that arm must appraise FAIL,
# and this is where that stops being a sentence.
#
# Two assertions, not one. --check re-derives every verdict and requires it to
# equal the committed one, so a change in the tools that changes a result is a
# red build. --expect compares the OUTCOMES against a committed statement of
# what they must be, because a policy that passes everything re-derives
# perfectly and would satisfy --check forever.
if command -v opa >/dev/null 2>&1; then
    # The engine is pinned like the decoder is, and for the same reason: a
    # verdict whose producer has no recorded version has half a provenance.
    # What is compared is the Rego LANGUAGE version, not the release — OPA made
    # v1 the default at 1.0 and the dialects are incompatible, while a patch
    # release is nobody's problem. third_party/opa.pin says why at length.
    OPA_REGO="$(opa version 2>/dev/null | awk '/^Rego Version:/{print $3}')"
    WANT_REGO="$(awk -F= '/^rego-version=/{print $2}' third_party/opa.pin 2>/dev/null)"
    OPA_VER="$(opa version 2>/dev/null | awk '/^Version:/{print $2}')"
    if [ -z "$WANT_REGO" ]; then
        bad "third_party/opa.pin has no rego-version="
    elif [ "$OPA_REGO" = "$WANT_REGO" ]; then
        good "opa $OPA_VER speaks Rego $OPA_REGO, which is what opa.pin records"
    else
        bad "opa speaks Rego $OPA_REGO and third_party/opa.pin records $WANT_REGO — the policy language changed incompatibly at OPA 1.0"
    fi
    if python3 rats/appraise.py matrix --check > /tmp/rats-matrix.$$ 2>&1; then
        sed -n '/^arm /,/^$/p' /tmp/rats-matrix.$$ | sed 's/^/  /'
        grep -c '^  ok ' /tmp/rats-matrix.$$ | sed 's/^/  assertions passed: /'
        good "ten arms, every verdict re-derived, every outcome as specified"
    else
        sed 's/^/  /' /tmp/rats-matrix.$$
        bad "the appraisal matrix does not match rats/out/expected.json"
    fi
    rm -f /tmp/rats-matrix.$$

    # ── and the version rule was loosened in ONE direction only ────────────
    #
    # The matrix above says every arm still reaches the outcome it must. It
    # cannot say what CHANGED on 2026-09-14, because it only ever runs one
    # policy, and "the results are what the file says" keeps being true after
    # a change that did nothing. So four of those arms are run again under the
    # live policy AND under a frozen copy of the one it replaced, and exactly
    # one cell is allowed to move. Two would mean something besides the
    # version rule was relaxed; none would mean the change was cosmetic.
    if bash rats/test_svn_policy.sh > /tmp/rats-svn.$$ 2>&1; then
        sed -n '/^case /,/^  captures/p' /tmp/rats-svn.$$ | sed 's/^/  /'
        good "four SVN cases under two policies, and one cell moved"
    else
        sed 's/^/  /' /tmp/rats-svn.$$
        bad "the SVN case table disagrees with rats/out/svn_cases.expected.json"
    fi
    rm -f /tmp/rats-svn.$$
else
    # Not a skip. The step above — rats/appraise.py selftest — already refuses
    # to run without an engine, on the grounds that a self-test which passes by
    # not running is worse than no self-test. This one used to print a loud
    # "skipped" and pass anyway, which made the two steps disagree about what a
    # missing opa means, and made this script's own message describe a state it
    # could no longer reach.
    #
    # Measured 2026-09-13 by removing opa from PATH: the run was already red,
    # from the step above, while this one was explaining that a green run would
    # be misleading. So: red, once, for one reason.
    bad "opa is not installed, so the appraisal cannot be evaluated — and THIS IS THE CHECK THAT MATTERS. Install it (RUNBOOK.md §2) rather than reading this as a skip: curl -L -o /tmp/opa https://openpolicyagent.org/downloads/v1.20.2/opa_linux_amd64_static && sudo install -m 0755 /tmp/opa /usr/local/bin/opa"
fi

step "this project's encoders still agree with DMTF's"
# rats/interop/ holds what DMTF's spdm_device_verifier_tool produced, recorded
# once by rats/interop.sh on a machine that has a spdm-emu checkout. Here — on
# a runner that has none — this project's side is re-derived and required to
# equal it. The interoperability claim is therefore checked on every push
# rather than on the day somebody re-runs the comparison.
INTEROP="rats/interop"
if [ -f "$INTEROP/dmtf-evidence.json" ]; then
    T="$(mktemp -d)"
    RUNDIR="bench/data/w5-tamper-20260910T092621Z"

    python3 harness/fields.py "$RUNDIR/t0_clean.decode.txt" \
            --emit-record "$T/record.bin" >/dev/null 2>&1
    if cmp -s "$T/record.bin" "$INTEROP/record.bin"; then
        good "the measurement record is the one both tools were given"
    else
        bad "the record emitted from the capture is not the one in $INTEROP"
    fi

    python3 rats/appraise.py evidence "$RUNDIR/t0_clean.decode.txt" \
            -o "$T/evidence.json" >/dev/null 2>&1
    # SpdmMeasurement.py writes json.dumps(...) and stops, with no final
    # newline. Every byte of the document agrees; one writer ends the file.
    if [ "$(sed -e '$a\' "$T/evidence.json" | sha256sum)" \
       = "$(sed -e '$a\' "$INTEROP/dmtf-evidence.json" | sha256sum)" ]; then
        good "evidence: identical to SpdmMeasurement.py's, bar its missing newline"
    else
        diff "$INTEROP/dmtf-evidence.json" "$T/evidence.json" | head -20 | sed 's/^/  /'
        bad "the evidence document no longer matches DMTF's"
    fi

    python3 rats/appraise.py to-cbor -i "$INTEROP/reference.json" \
            -o "$T/reference.cbor" >/dev/null 2>&1
    if cmp -s "$T/reference.cbor" "$INTEROP/dmtf-reference.cbor"; then
        good "CoRIM: $(wc -c < "$T/reference.cbor" | tr -d ' ') bytes, identical to CoRimTool.py's"
    else
        bad "the CBOR encoding no longer matches CoRimTool.py's"
    fi

    # Encode, decode, encode: the property a signature depends on, and the one
    # CoRimTool.py does not have (KeyError: 'corim' on its own sample).
    python3 rats/appraise.py to-json -i "$T/reference.cbor" -o "$T/back.json" >/dev/null 2>&1
    python3 rats/appraise.py to-cbor -i "$T/back.json" -o "$T/again.cbor" >/dev/null 2>&1
    if cmp -s "$T/again.cbor" "$T/reference.cbor"; then
        good "encode -> decode -> encode returns the same bytes"
    else
        bad "a decode and re-encode changed the reference document"
    fi

    if python3 rats/cose.py verify -i "$INTEROP/dmtf-signed.corim" \
            --key rats/keys/ref-signer.pub -o "$T/payload.cbor" >/dev/null 2>&1; then
        good "rats/cose.py still verifies a COSE_Sign1 CoRimTool.py signed"
    else
        bad "rats/cose.py no longer verifies CoRimTool.py's signature"
    fi

    if python3 rats/cose.py verify -i rats/ref/clean.corim \
            --key rats/keys/ref-signer.pub >/dev/null 2>&1; then
        good "the published reference value verifies against the committed key"
    else
        bad "rats/ref/clean.corim does not verify — every appraisal below is void"
    fi
    rm -rf "$T"
else
    bad "$INTEROP is missing; run bash rats/interop.sh on a machine with spdm-emu"
fi

step "the three gate tables agree, and they agree about which week it is"
# README.md, docs/roadmap.md and RUNBOOK.md each carry a table of the nine
# gates, in two languages and three formats. On 2026-09-10 the RUNBOOK's first
# screen was nine days stale, and the person it misled was the author: it said
# the three tamper points had not been started while section 8.8 of the same
# file explained all three.
#
# Worth being exact about what this catches, because the first version of this
# check would NOT have caught that day. The three tables' STATE columns all
# said "in progress" for G2 and were all correct. What had rotted was the prose
# beside the state, and the week number at the top of the RUNBOOK, and there is
# no mechanism for prose — 2026-09-01 in LOG.md is the entry that says so.
#
# The week number is mechanisable, and it is the load-bearing half: a reader
# who is told "week three finished" stops reading before the section that
# explains week four. So both halves are checked, and only one of them is the
# reason this step exists.
#
# CLAUDE.md's end-of-day list already said to keep two of the tables in step.
# That is a discipline; this is a mechanism, and the difference between them
# was nine days.
python3 - <<'PY'
import re, sys

STATES = {
    "complete": "complete", "in progress": "in progress",
    "not started": "not started",
    "完成": "complete", "進行中": "in progress",
    "未開始": "not started",
}
FILES = ["README.md", "docs/roadmap.md", "RUNBOOK.md"]
ROW = re.compile(r"^\|\s*\*{0,2}(G[0-8])\*{0,2}\s*\|(?P<rest>.*)\|\s*$")

def states(path):
    out = {}
    for line in open(path, encoding="utf-8"):
        m = ROW.match(line.rstrip())
        if not m:
            continue
        rest = m.group("rest")
        hits = [(rest.find(k), v) for k, v in STATES.items() if k in rest]
        if not hits:
            out[m.group(1)] = "UNSTATED"
            continue
        out[m.group(1)] = min(hits)[1]
    return out

tables = {f: states(f) for f in FILES}
gates = sorted(set().union(*(set(t) for t in tables.values())))
width = max(len(f) for f in FILES)
for f in FILES:
    row = " ".join(f"{g}:{tables[f].get(g, '-')[:11]:<11}" for g in gates)
    print(f"  {f:<{width}}  {row}")

bad = 0
for g in gates:
    got = {f: tables[f].get(g) for f in FILES}
    if len(set(got.values())) != 1:
        print(f"  {g} disagrees: " + ", ".join(f"{f}={v}" for f, v in got.items()))
        bad += 1
    elif set(got.values()) == {"UNSTATED"}:
        print(f"  {g} carries no recognised state in any table")
        bad += 1
    elif None in got.values():
        print(f"  {g} is missing from " +
              ", ".join(f for f, v in got.items() if v is None))
        bad += 1
if not gates:
    print("  no gate table found in any of the three files")
    bad += 1

# The week number, from the sentence each file states it in.
WEEK = {
    "README.md": r"[Tt]his is week (\d+) of a 14-week programme",
    "RUNBOOK.md": r"W0*(\d+)\s*收工",
}
weeks = {}
for f, pattern in WEEK.items():
    m = re.search(pattern, open(f, encoding="utf-8").read())
    weeks[f] = int(m.group(1)) if m else None
    print(f"  {f:<{width}}  says week {weeks[f]}")
if None in weeks.values():
    for f, w in weeks.items():
        if w is None:
            print(f"  {f} no longer states which week it is, in the form "
                  f"/{WEEK[f]}/")
    bad += 1
elif len(set(weeks.values())) != 1:
    print("  the two files disagree about which week it is: "
          + ", ".join(f"{f}={w}" for f, w in weeks.items()))
    bad += 1

sys.exit(1 if bad else 0)
PY
[ $? -eq 0 ] && good "nine gates, three tables, one answer each, and one week" \
             || bad "the gate tables disagree about what exists"

step "every figure still renders from the data it claims to show"
# CLAUDE.md and figures/README.md have said since 2026-08-11 that no figure
# here is drawn by hand, and README.md's repository layout has listed the
# directory since the same day. The directory was empty until 2026-09-10, which
# is the "table indexing a directory" shape of the rot this repository keeps
# finding, aimed at a directory with nothing in it.
#
# So the rule now has something to hold. harness/mkfigures.py re-renders each
# figure from certs/check_chain.py, harness/fields.py and bench/pcapstat.py and
# this step requires the committed file to be identical. A figure whose numbers
# stopped being true fails the build rather than staying beautiful.
if out="$(python3 harness/mkfigures.py --check 2>&1)"; then
    printf '%s\n' "$out" | sed 's/^/  /'
    good "the committed figures are what the data renders to"
else
    printf '%s\n' "$out" | sed 's/^/  /'
    bad "a figure no longer matches the data it was rendered from"
fi

step "the drills track reports itself"
# The project track has spent five weeks generating work for a track that has
# completed nothing, and until now that was a sentence in LOG.md rather than a
# number anywhere. A sentence does not get read on a day nobody is looking for
# it.
#
# This does not fail the build. Whether to spend an evening on paper is not a
# decision a script gets to make, and a check that fails for a reason nobody
# intends to fix teaches people to ignore red. What it does assert is the one
# thing that would be dishonest: a drill in DONE.txt whose compile-error count
# was never recorded. DONE.txt is what CI runs and SCORECARD.md is the only
# thing in this repository that measures the author rather than the system.
python3 - <<'PY'
import pathlib, re, sys

drills = sorted(p.stem for p in pathlib.Path("c-drills").glob("d*_*.c"))
done = [ln.strip() for ln in pathlib.Path("c-drills/DONE.txt").read_text().splitlines()
        if ln.strip() and not ln.strip().startswith("#")]
scorecard = pathlib.Path("c-drills/SCORECARD.md").read_text()

print(f"  {len(drills)} drill(s) with a contract, tests and a stub: "
      + ", ".join(d.split('_')[0] for d in drills))
print(f"  {len(done)} in DONE.txt" + (": " + ", ".join(done) if done else ""))
if len(done) < len(drills):
    print(f"  --   {len(drills) - len(done)} written and not yet finished. The "
          "implementations are not the harness's to write.")

bad = 0
for name in done:
    if name not in drills:
        print(f"  {name} is in DONE.txt and has no source file")
        bad += 1
        continue
    key = name.split("_")[0].upper()
    row = re.search(rf"^\|\s*{key}\s*\|.*$", scorecard, re.M | re.I)
    if not row:
        print(f"  {name} is finished and has no row in SCORECARD.md")
        bad += 1
        continue
    cells = [c.strip() for c in row.group(0).split("|")]
    # columns: '', #, Drill, Date, Paper time, Compile errors, ...
    if len(cells) < 7 or not cells[6]:
        print(f"  {name} is finished and its compile-error count is blank")
        bad += 1
sys.exit(1 if bad else 0)
PY
[ $? -eq 0 ] && good "every finished drill carries the number it exists to produce" \
             || bad "a drill is claimed finished without its measurement"

step "the conformance instruments can still reject"
# Both of these are new in W10 and both exist to make a claim falsifiable, so
# both have to be observed refusing something. validator_report.py is fed a
# truncated log, a log whose footer disagrees with its own lines, and a log
# with no assertions; challenge_verify.py is fed a signature over a transcript
# one bit different, and a chain whose certificates do not tile it.
_vr=0; _cv=0
python3 harness/validator_report.py --self-test >/tmp/vr.txt 2>&1 || _vr=1
python3 harness/challenge_verify.py  --self-test >/tmp/cv.txt 2>&1 || _cv=1
sed -n 's/^/  /p' /tmp/vr.txt | grep -c 'ok  ' >/dev/null 2>&1 || true
printf '  validator_report.py  %s\n' "$([ $_vr -eq 0 ] && echo 'every refusal fired' || echo 'FAILED')"
printf '  challenge_verify.py  %s\n' "$([ $_cv -eq 0 ] && echo 'every refusal fired' || echo 'FAILED')"
if [ $_vr -eq 0 ] && [ $_cv -eq 0 ]; then
    good "both W10 analysis tools refuse what they are supposed to refuse"
else
    sed -n '/FAIL/p' /tmp/vr.txt /tmp/cv.txt | sed 's/^/  /'
    bad "a W10 analysis tool accepted something it should have refused"
fi
rm -f /tmp/vr.txt /tmp/cv.txt

step "the conformance suite can still be made to say FAIL"
# The calibration, re-asserted from the COMMITTED logs rather than by running
# the suite again: CI has no build tree. proxy-inert and proxy-flip-sig differ
# by one byte of one signature, changed in flight, and the requirement is that
# exactly one assertion regressed, that it is the one named "response
# signature", and that nothing improved.
#
# Without this, docs/validator-report.md section 4 would be a paragraph about
# a run nobody can repeat. With it, a change that quietly stopped the suite
# noticing turns the badge red.
_vrun="$(ls -d bench/data/w10-validator-* 2>/dev/null | tail -1)"
if [ -z "$_vrun" ]; then
    bad "no w10-validator run directory is committed, so the calibration cannot be re-asserted"
elif [ ! -f "${_vrun}/proxy-inert.test.log" ] || [ ! -f "${_vrun}/proxy-flip-sig.test.log" ]; then
    bad "${_vrun} is missing one of the two proxy arms"
else
    _tmpa="$(mktemp)"; _tmpb="$(mktemp)"
    python3 harness/validator_report.py --parse "${_vrun}/proxy-inert.test.log" \
        --label proxy-inert --json "$_tmpa" >/dev/null
    python3 harness/validator_report.py --parse "${_vrun}/proxy-flip-sig.test.log" \
        --label proxy-flip-sig --json "$_tmpb" >/dev/null
    if python3 harness/validator_report.py --compare "$_tmpa" "$_tmpb" \
           --require-regressed-message "response signature" | sed 's/^/  /'; then
        good "one signature byte still moves exactly the assertion that reads it"
    else
        bad "the calibration no longer holds on the committed logs"
    fi
    rm -f "$_tmpa" "$_tmpb"
fi

step "the signature the conformance suite rejected still verifies"
# docs/validator-report.md section 5 says the responder was right and the suite
# was wrong. That is the strongest claim in the week and it rests on
# arithmetic, so the arithmetic runs here, on the committed capture, every time.
#
# Two requirements, and the first one is what makes the second mean anything:
# every connection that DID fetch the certificate must verify (the transcript
# model is calibrated), and only then is the verdict on the ones that did not
# worth reading.
if [ -z "$_vrun" ] || [ ! -f "${_vrun}/caps-default.pcap" ]; then
    bad "no committed conformance capture to verify against"
else
    _cvj="$(mktemp)"
    if python3 harness/challenge_verify.py "${_vrun}/caps-default.pcap" \
            --json "$_cvj" >/dev/null 2>&1; then
        python3 - "$_cvj" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
cal, dis = d["calibration"], d["disputed"]
cal_ok = sum(1 for r in cal if r["verified"] is True)
dis_ok = sum(1 for r in dis if r["verified"] is True)
print(f"  calibration  {cal_ok}/{len(cal)} verify   disputed  {dis_ok}/{len(dis)} verify")
bad = 0
if not cal or cal_ok != len(cal):
    print("  the transcript model no longer reproduces a signature the suite accepts")
    bad = 1
if not dis:
    print("  no disputed connection in the capture, so nothing is being asserted")
    bad = 1
elif dis_ok != len(dis):
    print("  a signature the suite rejected no longer verifies here either -- "
          "docs/validator-report.md section 5 would have to be rewritten")
    bad = 1
sys.exit(bad)
PY
        [ $? -eq 0 ] && good "the responder's CHALLENGE_AUTH signatures are still good" \
                     || bad "the section 5 verdict does not reproduce"
    else
        bad "challenge_verify.py could not read the committed capture"
    fi
    rm -f "$_cvj"
fi

step "the conformance sample still runs fewer cases than the suite implements"
# docs/validator-report.md section 2.1 states four numbers about two upstream
# files: 73 cases implemented, 71 registered, three implemented-and-unregistered,
# one registered-and-absent. They are checkable only where the upstream tree
# exists, which is not CI. So this check is CONDITIONAL and says so loudly when
# it is skipped, the same way the appraisal does when opa is missing -- a check
# that silently does nothing is worse than no check, because it reports as
# green.
_valsrc="${LAB_DIR:-$HOME/spdm-lab}/work/spdm-emu-pqc/SPDM-Responder-Validator"
_valcfg="${LAB_DIR:-$HOME/spdm-lab}/work/spdm-emu-pqc/spdm_emu/spdm_device_validator_sample/spdm_device_validator_config.c"
if [ -d "$_valsrc" ] && [ -f "$_valcfg" ]; then
    _audit="$(python3 harness/validator_report.py --audit-config "$_valsrc" "$_valcfg")"
    printf '%s\n' "$_audit" | sed 's/^/  /'
    _impl="$(printf '%s' "$_audit" | sed -n 's/.*implemented by the suite *\([0-9]*\).*/\1/p')"
    _reg="$(printf '%s'  "$_audit" | sed -n 's/.*registered by the sample *\([0-9]*\).*/\1/p')"
    if [ "$_impl" = "73" ] && [ "$_reg" = "71" ]; then
        good "the two upstream files still disagree in both directions, by the counts the report states"
    else
        bad "docs/validator-report.md says 73 implemented and 71 registered; this tree says ${_impl:-?} and ${_reg:-?}"
    fi
else
    printf '  --   no SPDM-Responder-Validator tree at %s\n' "$_valsrc"
    printf '  --   section 2.1 of docs/validator-report.md is NOT being checked on this machine.\n'
    printf '  --   Run harness/build_spdm_emu.sh pqc, or read the committed run directory.\n'
fi

step "the negative tests, and every defect they say they can catch"
# `make test` is not a loop over three binaries. It rebuilds each finished test
# once per declared defect variant and requires each of those to be caught by
# exactly the cases the file predicted — no fewer (rule 11) and no others
# (rule 13) — and then runs the two --asan-demo halves, which assert what this
# toolchain does and does not report about an overflow.
#
# So the exit status of this one command covers three suites, twenty-four
# cases, twenty-one deliberately wrong implementations and one claim about the
# sanitizer. The counts are printed from the binaries rather than written here,
# because a count kept in two places is a count that drifts.
if [ -d negative ] && [ -f negative/Makefile ]; then
    if make -C negative clean >/dev/null 2>&1 && make -C negative >/tmp/neg.txt 2>&1; then
        sed -n 's/^/  /p' /tmp/neg.txt | head -6
        if make -C negative test >/tmp/negtest.txt 2>&1; then
            grep -E '^  (PASS|FAIL)|asan_demo|^ALL NEGATIVE' /tmp/negtest.txt \
                | sed 's/^/  /'
            _negdone="$(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' negative/DONE.txt 2>/dev/null | wc -l)"
            _negall="$(ls negative/test_*.c 2>/dev/null | wc -l)"
            printf '  %s of %s negative test(s) claimed complete\n' "$_negdone" "$_negall"
            good "every defect variant caught by exactly the cases its file predicted"
        else
            tail -40 /tmp/negtest.txt | sed 's/^/  /'
            bad "a negative test, or one of its defect variants, did not behave as declared"
        fi
        make -C negative clean >/dev/null 2>&1
    else
        sed 's/^/  /' /tmp/neg.txt | tail -20
        bad "a negative test does not compile"
    fi
    rm -f /tmp/neg.txt /tmp/negtest.txt
else
    bad "negative/ has no Makefile"
fi

step "the advisory verdicts still come out of the evidence"
# docs/advisories.md states six verdicts about whether this project's own two
# builds carry three published defects. They are not opinions: each one is
# assembled from an advisory pin, a recorded run, the capability bits in the
# committed captures, and a grep of the source the compiler read.
#
# ★ --selftest first, and it is the half that matters. A tool that answered
# NOT-AFFECTED for everything would pass --check against a patched tree and say
# nothing at all. The selftest feeds it evidence that must produce every other
# verdict, including the one where its two routes disagree, and fails if the
# answer does not move. Rule 11, applied to a verdict instead of a parser.
#
# The output is captured and then printed, rather than piped into sed inside
# the `if`. A pipeline's status is its LAST command's, so `cmd | sed` is always
# a success — which is the defect the step "no branch is decided by a pipeline
# that can lose its producer" exists to find, and there is no reason for this
# file to contain the thing it checks other files for.
if _adv="$(python3 harness/check_advisories.py --selftest 2>&1)"; then
    printf '%s\n' "$_adv" | sed 's/^/  /'
    if _adv="$(python3 harness/check_advisories.py --check docs/advisories.md 2>&1)"; then
        printf '%s\n' "$_adv" | sed 's/^/  /'
        good "the document's verdicts match the recorded evidence, and the tool can still say otherwise"
    else
        printf '%s\n' "$_adv" | sed 's/^/  /'
        bad "docs/advisories.md states a verdict the evidence does not support"
    fi
else
    printf '%s\n' "$_adv" | sed 's/^/  /'
    bad "check_advisories.py cannot reproduce a verdict it is supposed to be able to reach"
fi
unset _adv

step "private material is not tracked"
# plan/ and archive/ hold the schedule this work is executed against; study/
# holds a question bank and its answers, which is a record of what one person
# does not yet know. All three are the author's, none is the repository's, and
# `git add -A` does not distinguish. So the mechanism does.
if git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    leaked="$(git ls-files plan archive study 2>/dev/null)"
    if [ -n "$leaked" ]; then
        printf '%s\n' "$leaked" | sed 's/^/  /'
        bad "private material is staged or tracked"
    else
        good "plan/, archive/ and study/ are untracked"
    fi
fi

printf '\n'
if [ "$FAILED" -eq 0 ]; then
    hdr "all checks passed"
else
    hdr "checks failed — fix the FAIL lines above"
fi
exit "$FAILED"

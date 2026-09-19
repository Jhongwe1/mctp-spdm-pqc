#!/usr/bin/env bash
#
# harness/run_coverage.sh — run libspdm's own unit tests under gcov and say
# which of its handlers they actually reach.
#
#     bash harness/run_coverage.sh
#     bash harness/run_coverage.sh --list
#
# What this is for
# ----------------
# A fuzzing report that says "no crashes" is worth as much as the reader's
# estimate of how much code was executed, and that estimate should not be the
# reader's to make. So this produces the number: lines and functions covered,
# for the library rather than for the test code, with the per-directory split
# that says whether the responder handlers -- the ones a device exposes to an
# untrusted peer -- were reached at all.
#
# It is a different build from harness/run_fuzz.sh's and the difference is
# deliberate:
#
#   run_fuzz.sh     AFL toolchain, mbedtls     upstream's own fuzzing config
#   this            GCC toolchain, openssl     the backend every capture in
#                                              this repository was produced
#                                              against
#
# Running both and saying which is which is the point. A coverage figure taken
# under mbedtls does not describe the binary that produced Table 2, and a
# coverage figure is the kind of number that gets quoted without its build.
#
# What it does not claim
# ----------------------
# Coverage is not correctness and it is not security. A line that executed is a
# line that did not crash on one input. docs/roadmap.md standing rule 11 --
# a check is worth what it rejects -- applies to the unit tests too, and
# nothing here measures what they would have caught.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
. "${REPO_ROOT}/harness/lib/provenance.sh"

FLAVOR="pqc"
LIST=0

while [ $# -gt 0 ]; do
    case "$1" in
        --flavor) FLAVOR="${2:?}"; shift 2 ;;
        --list)   LIST=1; shift ;;
        -h|--help) sed -n '3,9p' "${BASH_SOURCE[0]}" | sed 's/^#\{1,\} \{0,1\}//'; exit 0 ;;
        *) die "unknown argument '$1'" ;;
    esac
done

need lcov genhtml

LIBSPDM="$(flavor_dir "$FLAVOR")/libspdm"
COV_BIN="${LIBSPDM}/build_cov/bin"

[ -d "$COV_BIN" ] || die "no coverage build at ${COV_BIN}
Build it the way libspdm/doc/test.md does:
  cd ${LIBSPDM} && mkdir -p build_cov && cd build_cov
  cmake -DARCH=x64 -DTOOLCHAIN=GCC -DTARGET=Debug -DCRYPTO=openssl -DGCOV=ON ..
  make copy_sample_key && make -j\$(nproc)"

# The unit tests, discovered rather than listed.
#
# A hard-coded list is a list that silently stops covering a test upstream
# added -- and 4.0 added one that matters here, test_spdm_fips, which runs the
# FIPS 140-3 known-answer vectors. The random number generator those vectors
# check is the same one GET_MEASUREMENTS draws its nonce from, and a
# predictable nonce is a replay defence that is not there.
#
# But `test_*` is not the same set as "the unit tests". A GCC build of libspdm
# also produces every FUZZ target, uninstrumented, and a fuzz target takes its
# input as argv[1]: run with no argument it prints "file error" and exits 1.
# The first version of this script ran all 112 of them and reported six
# failures that were nothing but missing arguments -- a failure count that
# would have gone into a published report as if the library were broken.
#
# So the exclusion is taken from the tree rather than from the names: every
# directory under unit_test/fuzzing/<family>/ is a fuzz target, and that list
# is what it is regardless of what upstream adds next.
mapfile -t FUZZ_TARGET_NAMES < <(
    find "${LIBSPDM}/unit_test/fuzzing" -mindepth 2 -maxdepth 2 -type d \
        -printf '%f\n' 2>/dev/null | sort -u)
is_fuzz_target() {
    local n
    for n in "${FUZZ_TARGET_NAMES[@]}"; do [ "$n" = "$1" ] && return 0; done
    return 1
}

TESTS=()
mapfile -t CANDIDATES < <(cd "$COV_BIN" && find . -maxdepth 1 -type f -executable \
    -name 'test_*' -printf '%f\n' | sort)
for c in "${CANDIDATES[@]}"; do
    is_fuzz_target "$c" || TESTS+=("$c")
done
[ "${#TESTS[@]}" -gt 0 ] || die "no unit-test binaries in ${COV_BIN}
(${#CANDIDATES[@]} test_* binaries were found and every one of them is a fuzz
target, which would mean this build produced no unit tests at all)"

if [ "$LIST" -eq 1 ]; then
    printf 'unit tests found in %s:\n' "$COV_BIN"
    printf '  %s\n' "${TESTS[@]}"
    exit 0
fi

hdr "libspdm unit tests under gcov (${FLAVOR} flavor, openssl backend)"

prov_begin w10-coverage "$FLAVOR"
prov_note lcov_version "$(lcov --version 2>&1 | head -1)"
prov_note coverage_build_crypto openssl
prov_note coverage_build_toolchain GCC
prov_note unit_tests_found "${#TESTS[@]}"
prov_note fuzz_targets_excluded "$(( ${#CANDIDATES[@]} - ${#TESTS[@]} ))"

# Old .gcda from an earlier run would be merged into this one's counts, which
# is how a coverage figure becomes the union of every run anybody ever did.
# Scoped to build_cov and not to the whole tree, because build_afl is also a
# GCOV build and harness/run_fuzz.sh may be writing its counters right now.
prov_run lcov --zerocounters --directory "${LIBSPDM}/build_cov" >/dev/null 2>&1 || true

hdr "running ${#TESTS[@]} unit test binaries"

# Where the full output goes, which is NOT the run directory.
#
# test_spdm_requester alone prints 24 MB of cmocka chatter, and the verdict in
# it is one line. A run directory is evidence somebody clones, so what lands
# there is the verdict, the counts and coverage.info; the transcript stays on
# this machine beside the build it came from. prov_finish hashes what is in the
# run directory, so this is a decision about what is being attested to rather
# than a decision about disk.
CHATTER="${LIBSPDM}/build_cov/.test-output"
mkdir -p "$CHATTER"
prov_note full_test_output_kept_at "${CHATTER#"${WORK_DIR}/"}"
prov_note test_logs_in_run_dir "last 120 lines of each, plus every cmocka verdict line"

passed=0; failed=0
: > "${PROV_RUN_DIR}/tests.txt"
for t in "${TESTS[@]}"; do
    rc=0
    ( cd "$COV_BIN" && timeout 600 "./${t}" ) \
        >"${CHATTER}/${t}.log" 2>&1 || rc=$?
    # The verdict lines and the tail. cmocka prints every failure as
    # "[  FAILED  ]" and the totals at the end, so a reader of the committed
    # file sees WHICH test failed and why without the 24 MB.
    {
        printf '# %s exited %s\n' "$t" "$rc"
        printf '# full output: %s\n#\n' "${CHATTER}/${t}.log"
        # || true, and it is load-bearing. lib/common.sh turns on `set -e` and
        # `pipefail`, so a grep that matches nothing -- which is what a test
        # with an unfamiliar output format produces -- takes the whole script
        # down between two passing tests. The first version of this did, and
        # the symptom was a run directory holding nine kilobytes and no
        # manifest.
        { grep -E '^\[( *(FAILED|ERROR|LINE|PASSED|==========) *)\]|FAILED TEST' \
            "${CHATTER}/${t}.log" 2>/dev/null | tail -60; } || true
        printf '#\n# --- last 120 lines ---\n'
        tail -120 "${CHATTER}/${t}.log"
    } > "${PROV_RUN_DIR}/test-${t}.log"
    if [ "$rc" -eq 0 ]; then
        passed=$((passed + 1)); printf '%-44s ok\n'   "$t" | tee -a "${PROV_RUN_DIR}/tests.txt"
    else
        failed=$((failed + 1)); printf '%-44s rc=%s\n' "$t" "$rc" | tee -a "${PROV_RUN_DIR}/tests.txt"
    fi
    prov_note "unit_test_${t}" "$rc"
done
prov_note unit_tests_passed "$passed"
prov_note unit_tests_failed "$failed"
printf '\n  %s passed, %s did not\n' "$passed" "$failed"

# A failing unit test is not this script's to fix and not its to hide. The
# coverage figure is still produced -- a test that fails still executed lines,
# and excluding it would quietly lower the number for the wrong reason -- and
# the count of failures rides beside it in the manifest and in the report.

hdr "collecting coverage"

# coverage.info is 220 KB and is the evidence: every later number is computed
# from it. The 1.4 MB unfiltered capture and the 7.8 MB HTML rendering are both
# derivable from it and from this build, so they stay beside the build.
INFO="${PROV_RUN_DIR}/coverage.info"
RAW="${CHATTER}/coverage.info.raw"
HTML="${LIBSPDM}/build_cov/cov_html"
prov_note coverage_html_at "${HTML#"${WORK_DIR}/"}"
# lcov 2.x is stricter than the 1.x every tutorial was written against: it
# refuses on mismatched .gcno/.gcda pairs and on source it cannot find, both of
# which a vendored OpenSSL produces in quantity. They are demoted rather than
# turned off, so the run finishes and the reasons stay in the log.
prov_run lcov --capture --directory "${LIBSPDM}/build_cov" --output-file "$RAW" \
    --rc branch_coverage=1 \
    --ignore-errors mismatch,negative,unused,empty,source,gcov,unsupported \
    >"${PROV_RUN_DIR}/lcov-capture.log" 2>&1 || \
    die "lcov --capture failed; see ${PROV_RUN_DIR}/lcov-capture.log"

# The library, not the test code and not the vendored crypto. A figure that
# includes unit_test/ measures how thoroughly the tests test themselves.
prov_run lcov --remove "$RAW" \
    "*/unit_test/*" "*/os_stub/*" "*/openssl/*" "*/mbedtls/*" "/usr/*" \
    --output-file "$INFO" \
    --ignore-errors unused,empty,source \
    >"${PROV_RUN_DIR}/lcov-remove.log" 2>&1 || \
    die "lcov --remove failed; see ${PROV_RUN_DIR}/lcov-remove.log"

prov_run genhtml "$INFO" --output-directory "$HTML" \
    --ignore-errors source,unmapped,empty \
    >"${PROV_RUN_DIR}/genhtml.log" 2>&1 || \
    warn "genhtml failed; the .info file is still the evidence"

hdr "what the tests reached"

# The summary, and then the split that actually answers a question. lcov --list
# gives per-file rates; the interesting grouping is per library directory,
# because "the responder handlers" is the set a device exposes to a peer it
# does not control.
prov_run lcov --summary "$INFO" \
    --ignore-errors empty,unused 2>&1 | tee "${PROV_RUN_DIR}/summary.txt"

python3 - "$INFO" "${PROV_RUN_DIR}/by-directory.txt" <<'PY' | tee -a "${PROV_RUN_DIR}/summary.txt"
import collections, pathlib, sys

info, out = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
per = collections.defaultdict(lambda: [0, 0])   # [found, hit]
cur = None
for line in info.read_text(errors="replace").splitlines():
    if line.startswith("SF:"):
        p = pathlib.PurePosixPath(line[3:])
        parts = p.parts
        cur = parts[-2] if len(parts) >= 2 else "?"
    elif line.startswith("LF:") and cur:
        per[cur][0] += int(line[3:])
    elif line.startswith("LH:") and cur:
        per[cur][1] += int(line[3:])

rows = sorted(per.items(), key=lambda kv: -kv[1][0])
total_f = sum(v[0] for v in per.values())
total_h = sum(v[1] for v in per.values())
lines = ["", "  lines covered, by library directory", ""]
lines.append(f"  {'directory':<40} {'lines':>7} {'hit':>7} {'%':>7}")
for name, (f, h) in rows:
    pct = (100.0 * h / f) if f else 0.0
    lines.append(f"  {name:<40} {f:>7} {h:>7} {pct:>6.1f}%")
pct = (100.0 * total_h / total_f) if total_f else 0.0
lines.append(f"  {'TOTAL':<40} {total_f:>7} {total_h:>7} {pct:>6.1f}%")
text = "\n".join(lines)
out.write_text(text + "\n", encoding="utf-8")
print(text)
PY

prov_finish

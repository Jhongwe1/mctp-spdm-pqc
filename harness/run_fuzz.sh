#!/usr/bin/env bash
#
# harness/run_fuzz.sh — libspdm's own fuzz targets, seeded from this project's
# own captures, against the corpus upstream ships.
#
#     bash harness/run_fuzz.sh                      # seeds, corpus A/B, short fuzz
#     bash harness/run_fuzz.sh --seconds 900        # longer fuzz, per target
#     bash harness/run_fuzz.sh --no-fuzz            # the deterministic half only
#     bash harness/run_fuzz.sh --list
#
# What is being measured, and what is not
# ---------------------------------------
# Not "are there bugs in libspdm". libspdm is on OSS-Fuzz, its CI runs CodeQL
# and Coverity, and an afternoon of local fuzzing finding something they have
# not is close enough to zero that planning for it would be dishonest. Finding
# nothing is the expected and complete result, and it is reported as a result.
#
# What IS measured is the seed corpus, and that is a question with an answer
# that can come out either way.
#
#   The claim worth making is "my fuzz seeds are real messages from my own
#   handshakes rather than something invented". The claim NOT worth making is
#   "and therefore they are better", because that compares against random bytes
#   and nobody fuzzes with random bytes. libspdm ships a corpus:
#   unit_test/fuzzing/seeds/, 69 directories and 81 files, mostly one
#   hand-written seed per target -- test_spdm_responder_version's is four bytes,
#   `10 84 00 00`.
#
#   So the rival hypothesis is upstream's corpus, not noise, and
#   docs/roadmap.md standing rule 18 says a claim that two things differ has to
#   evaluate both. `afl-showmap -C` does exactly that and deterministically: it
#   executes a whole corpus and reports the union of the edges reached. Three
#   numbers per target -- upstream's seeds, this project's, and both together --
#   and the third one is the interesting column, because a corpus that adds
#   nothing to upstream's is a corpus with a story and no effect.
#
# Two things this deliberately does not hide
# ------------------------------------------
#   * The AFL build uses mbedtls, because that is what upstream's own
#     fuzzing_AFL.sh and oss-fuzz_conf/build.sh use. Every capture in this
#     repository was produced against libspdm's vendored OpenSSL. So the code
#     under the fuzzer is the same protocol handler and a different crypto
#     backend, and no coverage number here transfers to the OpenSSL builds
#     without saying so. harness/run_coverage.sh is the OpenSSL one.
#   * A time-boxed run reports the box. "I fuzzed for N seconds" is a fact;
#     "I fuzzed for eight hours" when the session was twenty minutes is not,
#     and there is no version of this report where the number is impressive
#     enough to be worth the alternative.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
. "${REPO_ROOT}/harness/lib/provenance.sh"

FLAVOR="pqc"
SECONDS_PER_TARGET=120
DO_FUZZ=1
LIST=0

# SPDM message name (as bench/pcapstat.py names it) -> libspdm responder fuzz
# target. Transcribed, and therefore checked: every target named here must
# exist as a binary AND as an upstream seed directory, and the script fails
# naming the one that does not. A mapping that silently pointed at nothing
# would report "0 edges" as a measurement.
MAP=(
    "SPDM_GET_VERSION|test_spdm_responder_version"
    "SPDM_GET_CAPABILITIES|test_spdm_responder_capabilities"
    "SPDM_NEGOTIATE_ALGORITHMS|test_spdm_responder_algorithms"
    "SPDM_GET_DIGESTS|test_spdm_responder_digests"
    "SPDM_GET_CERTIFICATE|test_spdm_responder_certificate"
    "SPDM_CHALLENGE|test_spdm_responder_challenge_auth"
    "SPDM_GET_MEASUREMENTS|test_spdm_responder_measurements"
    "SPDM_KEY_EXCHANGE|test_spdm_responder_key_exchange"
    "SPDM_FINISH|test_spdm_responder_finish_rsp"
    "SPDM_HEARTBEAT|test_spdm_responder_heartbeat_ack"
    "SPDM_KEY_UPDATE|test_spdm_responder_key_update"
    "SPDM_END_SESSION|test_spdm_responder_end_session"
    "SPDM_CHUNK_GET|test_spdm_responder_chunk_get"
    "SPDM_CHUNK_SEND|test_spdm_responder_chunk_send_ack"
    "SPDM_GET_CSR|test_spdm_responder_csr"
    "SPDM_SET_CERTIFICATE|test_spdm_responder_set_certificate"
    "SPDM_GET_MEASUREMENT_EXTENSION_LOG|test_spdm_responder_measurement_extension_log"
)

# The captures the corpus is drawn from, and why each one is in the list.
#
#   A0-all / P2-all  one classical and one post-quantum handshake, the pair
#                    Table 2 is built on. Real nonces, real chain fetches, and
#                    a post-quantum CERTIFICATE large enough to chunk.
#   caps-default     the conformance run: 128 connections, five negotiated
#                    versions, several slot ids, and the request shapes the
#                    suite sends to provoke an ERROR -- which a handshake that
#                    succeeds never produces.
#
# The union is taken by content digest, so a message common to all three is one
# seed. bench/pcapstat.py --export-seeds does that.
#
# The conformance capture is in the list on evidence rather than on taste. The
# first run of this script used the two handshakes alone and could seed seven
# of the seventeen targets: the other ten want KEY_EXCHANGE, FINISH, HEARTBEAT,
# KEY_UPDATE, END_SESSION, GET_CSR, SET_CERTIFICATE or GET_MEL, and no arm of
# this project's A/B has ever sent one. harness/lib/arms.sh says why in its own
# words -- `--exe_session NO_END` does not include EXE_SESSION_KEY_EX, so no
# session is ever established -- and it took a fuzz corpus to make the
# consequence visible. A corpus is limited by the flags of the runs it is drawn
# from, and that is a property of the corpus, not of the fuzzer.
CAPTURES_DEFAULT=(
    "bench/data/w8-pqc-matrix-20260914T131557Z/A0-all.pcap"
    "bench/data/w8-pqc-matrix-20260914T131557Z/P2-all.pcap"
    "bench/data/w10-validator-20260919T184429Z/caps-no-mut-auth.pcap"
)

# Targets given a real fuzzing budget, as opposed to the corpus comparison
# which covers every target a seed exists for.
#
# Chosen for the advisory classes W11's negative tests reproduce rather than
# for corpus size: GET_CERTIFICATE carries an Offset and a Length that are
# added together, GET_MEASUREMENTS walks an index, and CHALLENGE carries the
# nonce and slot the signature is computed over.
FUZZ_TARGETS=(
    test_spdm_responder_certificate
    test_spdm_responder_measurements
    test_spdm_responder_challenge_auth
)

usage() {
    sed -n '3,9p' "${BASH_SOURCE[0]}" | sed 's/^#\{1,\} \{0,1\}//'
    printf '\nmessage type -> fuzz target:\n'
    local row m t
    for row in "${MAP[@]}"; do
        IFS='|' read -r m t <<<"$row"
        printf '  %-36s %s\n' "$m" "$t"
    done
    printf '\ntargets given a fuzzing budget: %s\n' "${FUZZ_TARGETS[*]}"
}

CAPTURES=()
while [ $# -gt 0 ]; do
    case "$1" in
        --flavor)  FLAVOR="${2:?}"; shift 2 ;;
        --seconds) SECONDS_PER_TARGET="${2:?}"; shift 2 ;;
        --capture) CAPTURES+=("${2:?}"); shift 2 ;;
        --no-fuzz) DO_FUZZ=0; shift ;;
        --list)    LIST=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown argument '$1' (try --help)" ;;
    esac
done
[ "$LIST" -eq 0 ] || { usage; exit 0; }
[ "${#CAPTURES[@]}" -gt 0 ] || CAPTURES=("${CAPTURES_DEFAULT[@]}")

need python3 afl-showmap
[ "$DO_FUZZ" -eq 0 ] || need afl-fuzz

LIBSPDM="$(flavor_dir "$FLAVOR")/libspdm"
AFL_BIN="${LIBSPDM}/build_afl/bin"
UPSTREAM_SEEDS="${LIBSPDM}/unit_test/fuzzing/seeds"

[ -d "$AFL_BIN" ] || die "no AFL build at ${AFL_BIN}
Build it the way upstream does:
  cd ${LIBSPDM} && mkdir -p build_afl && cd build_afl
  cmake -DARCH=x64 -DTOOLCHAIN=AFL -DTARGET=Release -DCRYPTO=mbedtls -DGCOV=ON ..
  make copy_sample_key && make -j\$(nproc)"

# AFL in WSL: the kernel's core_pattern is not ours to set, and the CPU
# governor does not exist. Both are refusals rather than warnings by default,
# and both are about the HOST rather than about the target, so they are waived
# here and the waiver is recorded in the manifest rather than being an
# environment variable somebody has to remember.
export AFL_SKIP_CPUFREQ=1
export AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES=1
export AFL_NO_AFFINITY=1

hdr "libspdm fuzz targets, seeded from this project's captures"

prov_begin w10-fuzz "$FLAVOR"
prov_note afl_version "$(afl-fuzz -h 2>&1 | head -1 | tr -d '\033' | sed 's/\[[0-9;]*m//g')"
prov_note afl_build_crypto mbedtls
prov_note afl_build_crypto_why \
    "upstream's own unit_test/fuzzing/fuzzing_AFL.sh and oss-fuzz_conf/build.sh use it"
prov_note captures_published_with openssl
prov_note afl_env_waivers \
    "AFL_SKIP_CPUFREQ, AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES, AFL_NO_AFFINITY (WSL host)"
prov_note seconds_per_fuzz_target "$SECONDS_PER_TARGET"
prov_note fuzz_targets "${FUZZ_TARGETS[*]}"

# ------------------------------------------------------------- the corpus ---

MINE="${PROV_RUN_DIR}/seeds"
mkdir -p "$MINE"

log "exporting seeds from ${#CAPTURES[@]} capture(s)"
for cap in "${CAPTURES[@]}"; do
    [ -f "${REPO_ROOT}/${cap}" ] || die "no such capture: ${cap}"
    prov_note "seed_source_$(basename "$cap" .pcap)" "$cap"
    prov_run python3 "${REPO_ROOT}/bench/pcapstat.py" "${REPO_ROOT}/${cap}" \
        --export-seeds "$MINE" --seed-direction req
done

# ------------------------------------------------------- the mapping check --
#
# Before any number is produced. A target named in MAP that has no binary would
# otherwise contribute a zero to the comparison, and a zero is indistinguishable
# from "this corpus reaches nothing".

hdr "the mapping, checked rather than trusted"
missing=0
for row in "${MAP[@]}"; do
    IFS='|' read -r msg target <<<"$row"
    bin_ok="ok"; seed_ok="ok"
    [ -x "${AFL_BIN}/${target}" ] || { bin_ok="MISSING"; missing=1; }
    [ -d "${UPSTREAM_SEEDS}/${target}" ] || { seed_ok="MISSING"; missing=1; }
    printf '  %-36s %-46s binary %-7s upstream seeds %s\n' \
        "$msg" "$target" "$bin_ok" "$seed_ok"
done
[ "$missing" -eq 0 ] || die "the message-to-target map names something that is not there"
ok "every target in the map has a binary and an upstream seed directory"

# ------------------------------------------- the corpus comparison (rule 18) -

hdr "edges reached: upstream's corpus, this project's, and both"

CMP_JSON="${PROV_RUN_DIR}/corpus-comparison.json"
: > "${PROV_RUN_DIR}/showmap.log"

# afl-showmap -C executes every file in a directory and writes the UNION of the
# edges hit. It prints the count on stderr as "Captured N tuples"; the output
# file has one line per edge, so `wc -l` is the same number by a second route
# and the two are required to agree.
edges() {
    local corpus="$1" target="$2" out="$3" said counted
    [ -d "$corpus" ] || { echo "-1"; return; }
    [ -n "$(ls -A "$corpus" 2>/dev/null)" ] || { echo "-1"; return; }
    said="$(cd "$AFL_BIN" && afl-showmap -C -i "$corpus" -o "$out" \
              -- "./${target}" @@ 2>&1 \
            | tr -d '\033' | sed 's/\[[0-9;]*m//g' \
            | sed -n 's/.*Captured \([0-9]*\) tuples.*/\1/p' | head -1)"
    counted="$(wc -l < "$out" 2>/dev/null || echo 0)"
    if [ -z "$said" ]; then echo "-1"; return; fi
    if [ "$said" != "$counted" ]; then
        warn "${target}: afl-showmap said ${said} tuples and wrote ${counted} lines"
        echo "-1"; return
    fi
    echo "$said"
}

printf '  %-46s %8s %8s %8s %8s\n' target upstream mine both added
printf '{\n  "targets": [\n' > "$CMP_JSON"
first=1
for row in "${MAP[@]}"; do
    IFS='|' read -r msg target <<<"$row"
    mine_dir="${MINE}/${msg}"
    if [ ! -d "$mine_dir" ]; then
        printf '  %-46s %8s %8s %8s %8s   (no message of this type in the captures)\n' \
            "$target" "-" "-" "-" "-"
        continue
    fi
    merged="${PROV_RUN_DIR}/merged/${target}"
    mkdir -p "$merged"
    cp -f "${UPSTREAM_SEEDS}/${target}"/* "$merged/" 2>/dev/null || true
    cp -f "${mine_dir}"/* "$merged/" 2>/dev/null || true

    up="$(edges "${UPSTREAM_SEEDS}/${target}" "$target" "${PROV_RUN_DIR}/showmap-${target}-upstream.txt")"
    mi="$(edges "$mine_dir" "$target" "${PROV_RUN_DIR}/showmap-${target}-mine.txt")"
    bo="$(edges "$merged" "$target" "${PROV_RUN_DIR}/showmap-${target}-both.txt")"
    n_mine="$(find "$mine_dir" -type f | wc -l)"
    n_up="$(find "${UPSTREAM_SEEDS}/${target}" -type f | wc -l)"

    added="-"
    if [ "$up" -ge 0 ] && [ "$bo" -ge 0 ]; then added="$((bo - up))"; fi
    printf '  %-46s %8s %8s %8s %8s\n' "$target" "$up" "$mi" "$bo" "$added"
    printf '%s    {"target": "%s", "message": "%s", "seeds_upstream": %s, "seeds_mine": %s, "edges_upstream": %s, "edges_mine": %s, "edges_both": %s, "edges_added_by_mine": "%s"}\n' \
        "$([ "$first" -eq 1 ] && echo "" || echo "    ,")" \
        "$target" "$msg" "$n_up" "$n_mine" "$up" "$mi" "$bo" "$added" >> "$CMP_JSON"
    first=0
done
printf '  ]\n}\n' >> "$CMP_JSON"
ok "corpus comparison in $(basename "$CMP_JSON")"

# ------------------------------------------------------------- the fuzzing --

if [ "$DO_FUZZ" -eq 1 ]; then
    hdr "fuzzing, for ${SECONDS_PER_TARGET}s per target"
    FINDINGS_ROOT="${SPDM_FUZZ_OUT:-/dev/shm/w10-fuzz-$$}"
    mkdir -p "$FINDINGS_ROOT"
    prov_note findings_root "$FINDINGS_ROOT"

    for target in "${FUZZ_TARGETS[@]}"; do
        msg=""
        for row in "${MAP[@]}"; do
            IFS='|' read -r m t <<<"$row"
            [ "$t" = "$target" ] && msg="$m"
        done
        corpus="${PROV_RUN_DIR}/merged/${target}"
        if [ -z "$msg" ] || [ ! -d "$corpus" ]; then
            warn "${target}: no merged corpus, skipped"
            continue
        fi
        out="${FINDINGS_ROOT}/${target}"
        log "afl-fuzz ${target} for ${SECONDS_PER_TARGET}s"
        prov_cmd afl-fuzz -V "$SECONDS_PER_TARGET" -i "$corpus" -o "$out" \
            -- "./${target}" @@
        ( cd "$AFL_BIN" && afl-fuzz -V "$SECONDS_PER_TARGET" -i "$corpus" \
              -o "$out" -- "./${target}" @@ ) \
            >"${PROV_RUN_DIR}/fuzz-${target}.log" 2>&1 || true

        stats="${out}/default/fuzzer_stats"
        if [ -f "$stats" ]; then
            cp "$stats" "${PROV_RUN_DIR}/fuzzer_stats-${target}.txt"
            crashes="$(find "${out}/default/crashes" -type f ! -name README.txt 2>/dev/null | wc -l)"
            hangs="$(find "${out}/default/hangs" -type f 2>/dev/null | wc -l)"
            execs="$(awk -F': *' '/^execs_done/{print $2}' "$stats" | tr -d ' ')"
            secs="$(awk -F': *' '/^run_time/{print $2}' "$stats" | tr -d ' ')"
            printf '  %-46s %10s execs in %5ss   crashes %s   hangs %s\n' \
                "$target" "${execs:-?}" "${secs:-?}" "$crashes" "$hangs"
            prov_note "fuzz_${target}_execs"    "${execs:-unknown}"
            prov_note "fuzz_${target}_run_time" "${secs:-unknown}"
            prov_note "fuzz_${target}_crashes"  "$crashes"
            prov_note "fuzz_${target}_hangs"    "$hangs"
            if [ "$crashes" != "0" ]; then
                mkdir -p "${PROV_RUN_DIR}/crashes-${target}"
                cp -r "${out}/default/crashes/." "${PROV_RUN_DIR}/crashes-${target}/" || true
                warn "${target}: ${crashes} crash input(s) kept in the run directory.
Before anything else: do NOT open a public issue and do not describe it
outside this repository. docs/upstream/README.md has the reporting path."
            fi
        else
            warn "${target}: no fuzzer_stats, so nothing is claimed about it"
            prov_note "fuzz_${target}_execs" "none — afl-fuzz left no fuzzer_stats"
        fi
    done
    rm -rf "$FINDINGS_ROOT"
else
    prov_note fuzzing_skipped "--no-fuzz"
fi

prov_finish

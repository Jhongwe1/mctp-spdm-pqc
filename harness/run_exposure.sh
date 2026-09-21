#!/usr/bin/env bash
#
# harness/run_exposure.sh — is THIS project's build affected by the three 2026
# advisories, and decided how?
#
#     bash harness/run_exposure.sh                  both flavors, with network
#     bash harness/run_exposure.sh --offline        skip the ancestry queries
#
# Why this exists
# ---------------
# negative/ demonstrates three advisory CLASSES. That is a statement about
# understanding and it deliberately says nothing about any real build — the
# directory's README is explicit that reproducing a class is not auditing an
# implementation for it.
#
# This is the other question, and it is the one somebody actually asks: the
# emulator in this repository is libspdm, two versions of it, and two of the
# three advisories name libspdm version ranges. So: yes or no, and on what
# evidence.
#
# ★ "The pinned version is inside the affected range" is not the answer. It is
# the first of five things, and the other four disagree with each other:
#
#   1. the version range from the advisory                 a claim about releases
#   2. whether the fix COMMIT is an ancestor of the pin    upstream's own answer
#   3. whether the fixed LINE is in the source on disk     this tree's answer
#   4. whether the vulnerable code is LINKED               present != reachable
#   5. whether the preconditions hold in this config       capability bits, and
#                                                          what an assert
#                                                          compiles to in Release
#
# 2 and 3 are deliberately redundant. Standing rule 12: where two routes reach
# the same quantity they are made to agree, because a single route that is
# wrong is indistinguishable from one that is right. The ancestry comes from
# GitHub and the line comes from the file the compiler read, and if they ever
# disagree the run says so instead of picking one.
#
# What it produces
# ----------------
# A run directory under bench/data/ with exposure.json in it, and a manifest
# that attributes every field. harness/check_advisories.py turns that evidence
# into verdicts and CI re-derives them offline, which is the split this
# repository uses everywhere: the measurement needs the lab, the conclusion
# needs only the committed bytes.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
. "${REPO_ROOT}/harness/lib/provenance.sh"

OFFLINE=0
[ "${1:-}" = "--offline" ] && OFFLINE=1

FLAVORS="stable pqc"
API="https://api.github.com/repos/DMTF/libspdm"

# ---------------------------------------------------------------------------
# One advisory's fix commits, read out of its pin rather than written here.
pin_field() {
    awk -F= -v k="$2" '$1 == k { sub(/^[^=]*=/, ""); print; exit }' \
        "${REPO_ROOT}/third_party/$1.pin"
}

# ancestry <base-commit> <head-commit>
#
# "ahead" or "identical" means base is an ancestor of head, so the fix is in.
# Anything else means it is not. The submodule checkouts in LAB_DIR cannot
# answer this locally — they carry one commit of history each — so the question
# goes to the host that owns the history.
ancestry() {
    local base="$1" head="$2"
    if [ "$OFFLINE" = "1" ]; then echo "not-queried"; return; fi
    curl -fsS -m 40 -H 'Accept: application/vnd.github+json' \
        "${API}/compare/${base}...${head}" 2>/dev/null \
        | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status","unknown"))' \
        2>/dev/null || echo "query-failed"
}

json_escape() { python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().rstrip("\n")))'; }

prov_begin w11-exposure pqc
prov_pin stable BUILD_PIN.stable.txt
prov_note advisories "DMTF-2026-0001 DMTF-2026-0002 DMTF-2026-0003"
prov_note offline "$OFFLINE"

OUT="${PROV_RUN_DIR}/exposure.json"

{
    echo '{'
    echo '  "generated_by": "harness/run_exposure.sh",'
    printf '  "offline": %s,\n' "$([ "$OFFLINE" = 1 ] && echo true || echo false)"
    echo '  "flavors": {'

    first_flavor=1
    for flavor in $FLAVORS; do
        dir="$(flavor_dir "$flavor")/libspdm"
        emu="$(flavor_dir "$flavor")"
        [ -d "$dir" ] || { warn "no libspdm tree for flavor $flavor - skipped"; continue; }

        head="$(git -C "$dir" rev-parse HEAD)"
        [ "$first_flavor" = 1 ] || echo ','
        first_flavor=0

        printf '    "%s": {\n' "$flavor"
        printf '      "libspdm_commit": "%s",\n' "$head"
        printf '      "libspdm_ref": %s,\n' \
            "$(awk -F= '/^libspdm-ref=/{print $2}' "$(flavor_pin "$flavor")" | json_escape)"

        # 4. what the emulator actually linked. Present in the tree and linked
        #    into the binary are different facts and only one of them matters.
        linked="$(find "${emu}/build" -maxdepth 4 -name 'libcryptlib_*.a' \
                       -printf '%f\n' 2>/dev/null | sort -u | tr '\n' ' ' | sed 's/ $//')"
        printf '      "cryptlib_linked": %s,\n' "$(printf '%s' "$linked" | json_escape)"
        printf '      "cryptlib_present": %s,\n' \
            "$(find "$dir/os_stub" -maxdepth 1 -name 'cryptlib_*' -printf '%f\n' \
               2>/dev/null | sort | tr '\n' ' ' | sed 's/ $//' | json_escape)"

        # 5b. what LIBSPDM_ASSERT compiles to. The bound check inside
        #     libspdm_copy_mem() is spelled LIBSPDM_ASSERT, and Release defines
        #     LIBSPDM_DEBUG_ENABLE=0, which makes the macro expand to nothing —
        #     so the check is in the source and absent from the binary.
        target="$(awk -F= '/^target=/{print $2}' "$(flavor_pin "$flavor")")"
        rel_line="$(grep -n 'LIBSPDM_DEBUG_ENABLE=0' "$dir/CMakeLists.txt" 2>/dev/null \
                    | head -1 | cut -d: -f1)"
        empty_assert="$(awk '/^#else$/{p=1;next} p&&/define LIBSPDM_ASSERT\(expression\)[[:space:]]*$/{print "yes";exit}' \
                        "$dir/include/hal/library/debuglib.h" 2>/dev/null)"
        printf '      "build_target": %s,\n' "$(printf '%s' "$target" | json_escape)"
        printf '      "debug_enable_zero_at_cmakelists_line": %s,\n' "${rel_line:-null}"
        printf '      "assert_expands_to_nothing": %s,\n' \
            "$([ "$empty_assert" = yes ] && [ "$target" = Release ] && echo true || echo false)"
        printf '      "copy_mem_copies_after_assert": %s,\n' \
            "$(grep -A4 'if (src_len > dst_len)' "$dir/os_stub/memlib/copy_mem.c" 2>/dev/null \
               | grep -qF 'while (src_len-- != 0)' && echo true || echo false)"

        echo '      "advisories": {'

        # --- DMTF-2026-0002 -------------------------------------------------
        site="$dir/$(pin_field dmtf-2026-0002 site)"
        def_line="$(pin_field dmtf-2026-0002 defective-line)"
        rep_line="$(pin_field dmtf-2026-0002 repaired-line)"
        printf '        "DMTF-2026-0002": {\n'
        printf '          "fixed_line_present": %s,\n' \
            "$(grep -qF "$rep_line" "$site" 2>/dev/null && echo true || echo false)"
        printf '          "defective_line_present": %s,\n' \
            "$(grep -qF "$def_line" "$site" 2>/dev/null && echo true || echo false)"
        printf '          "ancestry_3_8_2": %s,\n' \
            "$(ancestry "$(pin_field dmtf-2026-0002 patch-commit-3.8.2)" "$head" | json_escape)"
        printf '          "ancestry_4_0": %s\n' \
            "$(ancestry "$(pin_field dmtf-2026-0002 patch-commit-4.0)" "$head" | json_escape)"
        printf '        },\n'

        # --- DMTF-2026-0001 -------------------------------------------------
        x509="$dir/os_stub/cryptlib_mbedtls/pk/x509.c"
        marker="$(pin_field dmtf-2026-0001 repaired-marker)"
        printf '        "DMTF-2026-0001": {\n'
        printf '          "fixed_line_present": %s,\n' \
            "$(grep -qF "$marker" "$x509" 2>/dev/null && echo true || echo false)"
        printf '          "defective_line_present": %s,\n' \
            "$(grep -qF 'the buffer is too small' "$x509" 2>/dev/null \
               && ! grep -qF "$marker" "$x509" 2>/dev/null && echo true || echo false)"
        printf '          "ancestry_3_8_2": %s,\n' \
            "$(ancestry "$(pin_field dmtf-2026-0001 patch-commit-3.8.2)" "$head" | json_escape)"
        printf '          "ancestry_4_0": %s\n' \
            "$(ancestry "$(pin_field dmtf-2026-0001 patch-commit-4.0)" "$head" | json_escape)"
        printf '        },\n'

        # --- DMTF-2026-0003 -------------------------------------------------
        # A defect in a document. There is no commit to be an ancestor of and
        # no line to grep for, and saying so is the honest answer rather than
        # an omission.
        printf '        "DMTF-2026-0003": {\n'
        printf '          "kind": "specification",\n'
        printf '          "session_established_by_this_project": false\n'
        printf '        }\n'

        echo '      }'
        printf '    }'
    done
    echo
    echo '  }'
    echo '}'
} > "$OUT"

python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$OUT" \
    || { echo "run_exposure.sh produced invalid JSON" >&2; exit 1; }

# The capability bits are NOT re-measured here. They are a property of the
# captures, they are already committed, and harness/fields.py owns them. The
# checker reads them from the capture the same way every other document does,
# which is what keeps one fact in one place.

prov_note exposure_json "$(basename "$OUT")"
prov_finish

log "wrote $OUT"
python3 "${REPO_ROOT}/harness/check_advisories.py" --exposure "$PROV_RUN_DIR"

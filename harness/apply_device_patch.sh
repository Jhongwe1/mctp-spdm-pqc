#!/usr/bin/env bash
#
# harness/apply_device_patch.sh — put device/ into the pinned build tree.
#
#     bash harness/apply_device_patch.sh pqc            # apply
#     bash harness/apply_device_patch.sh pqc --build    # apply, then rebuild
#     bash harness/apply_device_patch.sh pqc --status
#     bash harness/apply_device_patch.sh pqc --revert
#
# What this exists for
# --------------------
# No upstream source is vendored here; third_party/*.pin records the commits
# and harness/build_spdm_emu.sh reconstructs the trees. A change to upstream
# source is therefore a patch and a copy, applied by a script, or it is a thing
# that happened once on one laptop and cannot be reproduced by a reader.
#
# The patch is sixteen added lines across two files, three of which are code.
# Everything else this change consists of — the loader, its format, its tests —
# is in device/ and belongs to this repository. That split is the argument, so
# the mechanism is built to keep it visible rather than to be clever.
#
# The three guards, and why each one is here
# ------------------------------------------
#   1. The tree's libspdm commit must equal the one in third_party/*.pin.
#      CLAUDE.md's standing rule is that the pin is the single source of truth
#      about versions; a patch applied to some other commit produces a binary
#      no pin describes.
#
#   2. meas.c and CMakeLists.txt must hash to the values this patch was made
#      against. `git apply` would refuse a patch whose context had moved, but
#      it would ACCEPT one whose context is intact while the rest of the file
#      changed underneath — and the interesting failure is exactly that: an
#      upstream revision that keeps the two anchor lines and changes what they
#      mean.
#
#   3. Re-applying is a no-op rather than an error, because a script that
#      cannot be run twice gets run once and then worked around.
#
# What it leaves behind for provenance
# ------------------------------------
# DEVICE_PATCH.txt, beside the flavor's BUILD_PIN.txt, in the same key=value
# form. Every capture taken after this folds it into its manifest.json through
# prov_pin_file, so "which binary produced this number" keeps its answer: the
# pinned commit, plus this patch, by digest. A patched tree that said nothing
# about being patched is the failure this file exists to prevent — the same
# failure certs/stage_chain.sh avoids by building a sandbox rather than
# overwriting the build tree.

set -uo pipefail
_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "${_HERE}/lib/common.sh"

FLAVOR="pqc"
ACTION="apply"
DO_BUILD=0

while [ $# -gt 0 ]; do
    case "$1" in
        pqc|stable) FLAVOR="$1"; shift ;;
        --revert)   ACTION="revert"; shift ;;
        --status)   ACTION="status"; shift ;;
        --build)    DO_BUILD=1; shift ;;
        -h|--help)  sed -n '3,12p' "$0"; exit 0 ;;
        *)          die "unknown argument '$1'" ;;
    esac
done

PATCH="${REPO_ROOT}/device/meas-from-file.patch"
MODULE_C="${REPO_ROOT}/device/measurement_source.c"
MODULE_H="${REPO_ROOT}/device/measurement_source.h"
PIN="${REPO_ROOT}/third_party/spdm-emu-${FLAVOR}.pin"

LIBSPDM_DIR="$(flavor_dir "$FLAVOR")/libspdm"
SECRET_DIR="${LIBSPDM_DIR}/os_stub/spdm_device_secret_lib_sample"
STAMP="$(flavor_dir "$FLAVOR")/DEVICE_PATCH.txt"

# The digests meas.c and CMakeLists.txt have at libspdm 8a92317, before this
# patch. Recorded here rather than computed, because the point of a pre-image
# digest is to be a value from the past.
PRE_MEAS="74d38f39bed2e12ac03977ce09da8984ad182081b48e37144a0ea981bcac9304"
PRE_CMAKE="82a379dbe991f7010e5b2d2aae0e1681008d577a9f907ce39c2b64afc9816525"

sha() { sha256sum "$1" | cut -d' ' -f1; }

is_applied() {
    [ -f "${SECRET_DIR}/meas.c" ] &&
        grep -q 'measurement_source.h' "${SECRET_DIR}/meas.c"
}

# ------------------------------------------------------------------ status --

report_status() {
    printf '  flavor        : %s\n' "$FLAVOR"
    printf '  libspdm tree  : %s\n' "$LIBSPDM_DIR"
    if [ ! -d "$SECRET_DIR" ]; then
        warn "no build tree — bash harness/build_spdm_emu.sh ${FLAVOR}"
        return 1
    fi
    printf '  libspdm commit: %s\n' \
        "$(git -C "$LIBSPDM_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
    if is_applied; then
        ok "device patch is APPLIED"
        if [ -f "$STAMP" ]; then
            sed 's/^/      /' "$STAMP"
        else
            warn "applied, but no DEVICE_PATCH.txt — captures cannot attribute it"
        fi
        printf '  measurements  : set %s to a fixture; unset means upstream behaviour\n' \
            "SPDM_MEASUREMENTS_FILE"
    else
        ok "device patch is NOT applied — the tree is upstream's"
    fi
    return 0
}

if [ "$ACTION" = "status" ]; then
    hdr "device patch status"
    report_status
    exit $?
fi

# ------------------------------------------------------------------ checks --

[ -f "$PATCH" ]    || die "missing ${PATCH}"
[ -f "$MODULE_C" ] || die "missing ${MODULE_C}"
[ -f "$MODULE_H" ] || die "missing ${MODULE_H}"
[ -d "$SECRET_DIR" ] || die "no build tree for flavor '${FLAVOR}'
  bash harness/build_spdm_emu.sh ${FLAVOR}"
git -C "$LIBSPDM_DIR" rev-parse --git-dir >/dev/null 2>&1 \
    || die "${LIBSPDM_DIR} is not a git checkout; this script needs git apply"

# ------------------------------------------------------------------ revert --

if [ "$ACTION" = "revert" ]; then
    hdr "reverting the device patch  ·  ${FLAVOR}"
    if ! is_applied; then
        ok "nothing to revert"
        exit 0
    fi
    run git -C "$LIBSPDM_DIR" apply -R "$PATCH" \
        || die "could not reverse the patch; the tree has been edited by hand"
    rm -f "${SECRET_DIR}/measurement_source.c" "${SECRET_DIR}/measurement_source.h"
    rm -f "$STAMP"
    ok "reverted — rebuild to get an unpatched binary:"
    printf '      make -C %s -j\n' "$(flavor_dir "$FLAVOR")/build"
    exit 0
fi

# ------------------------------------------------------------------- apply --

hdr "applying the device patch  ·  ${FLAVOR}"

if is_applied; then
    ok "already applied — nothing to do"
    report_status
    exit 0
fi

# Guard 1: the pin is the truth about which commit this is.
if [ -f "$PIN" ]; then
    want="$(sed -n 's/^libspdm=//p' "$PIN" | head -1)"
    got="$(git -C "$LIBSPDM_DIR" rev-parse HEAD 2>/dev/null || echo unknown)"
    if [ -n "$want" ] && [ "$want" != "$got" ]; then
        die "libspdm in the build tree is ${got}
  but third_party/spdm-emu-${FLAVOR}.pin says ${want}.
  Rebuild from the pin before patching, or the binary matches no pin at all."
    fi
    dim "    libspdm ${got} matches the pin"
else
    warn "no ${PIN} — cannot confirm the commit this patch is being applied to"
fi

# Guard 2: the two files must be the ones the patch was made against.
for pair in "meas.c:${PRE_MEAS}" "CMakeLists.txt:${PRE_CMAKE}"; do
    f="${pair%%:*}"; want="${pair#*:}"
    got="$(sha "${SECRET_DIR}/${f}")"
    if [ "$got" != "$want" ]; then
        die "${f} is not the file this patch was made against.
  want ${want}
  got  ${got}
  Upstream has changed it. Re-read it before re-making the patch: the two
  anchor lines can survive a revision that changes what they mean."
    fi
    dim "    ${f} pre-image matches"
done

run cp "$MODULE_C" "$MODULE_H" "${SECRET_DIR}/"
run git -C "$LIBSPDM_DIR" apply --check "$PATCH" \
    || die "git apply --check refused the patch"
run git -C "$LIBSPDM_DIR" apply "$PATCH"

{
    printf '# written by harness/apply_device_patch.sh — do not edit\n'
    printf 'patch=device/meas-from-file.patch\n'
    printf 'patch_sha256=%s\n' "$(sha "$PATCH")"
    printf 'module_c_sha256=%s\n' "$(sha "$MODULE_C")"
    printf 'module_h_sha256=%s\n' "$(sha "$MODULE_H")"
    printf 'meas_c_pre_sha256=%s\n' "$PRE_MEAS"
    printf 'meas_c_post_sha256=%s\n' "$(sha "${SECRET_DIR}/meas.c")"
    printf 'libspdm=%s\n' "$(git -C "$LIBSPDM_DIR" rev-parse HEAD)"
    printf 'env_var=%s\n' "SPDM_MEASUREMENTS_FILE"
    printf 'applied_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$STAMP"

ok "applied"
printf '\n'
git -C "$LIBSPDM_DIR" diff --stat | sed 's/^/    /'
printf '\n'
ok "provenance stamp: ${STAMP}"

if [ "$DO_BUILD" -eq 1 ]; then
    hdr "rebuilding"
    run make -C "$(flavor_dir "$FLAVOR")/build" -j"$(jobs_default)" || die "build failed"
    ok "rebuilt"
else
    log "now rebuild:"
    printf '      make -C %s -j\n' "$(flavor_dir "$FLAVOR")/build"
fi

#!/usr/bin/env bash
#
# harness/build_openbmc_spdm.sh — reproduce the openbmc/spdm build attempt.
#
#     bash harness/build_openbmc_spdm.sh
#
# This is not part of the measurement pipeline. It exists so that the build
# blockers recorded in docs/upstream/README.md can be reproduced by someone
# else on a stock Ubuntu 24.04, which is the difference between "I ran into a
# problem" and "here is how to see it".
#
# It deliberately does NOT install anything with root. Everything goes into a
# virtualenv, because a recipe that needs sudo is a worse recipe, and because
# the venv is where blocker 2 lives.
#
# Expected outcome on Ubuntu 24.04 / GCC 13.3 as of 2026-08-11: setup succeeds,
# compile fails. That is the finding, not a failure of this script — so it
# exits 0 and reports what happened.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
set +e

SRC="${WORK_DIR}/openbmc-spdm"
VENV="${LAB_DIR}/venv-obmc"
UPSTREAM="https://github.com/openbmc/spdm.git"

need git python3

hdr "openbmc/spdm — build attempt (Gate 7)"

mkdir -p "$WORK_DIR"
if [ ! -d "${SRC}/.git" ]; then
    log "cloning"
    run git clone "$UPSTREAM" "$SRC" || die "clone failed"
else
    ok "already cloned"
fi
cd "$SRC" || die "cannot enter ${SRC}"

log "target state"
printf '  HEAD          : %s\n' "$(git rev-parse --short HEAD)"
printf '  last commit   : %s\n' "$(git log -1 --format='%ci  %s')"
printf '  tracked files : %s\n' "$(git ls-files | wc -l)"
printf '  root README   : %s\n' "$([ -f README.md ] && echo present || echo ABSENT)"
printf '  untested src  : %s\n' "$(git ls-files 'requester/utils/*' | tr '\n' ' ')"

# ── blockers 1-3: three python modules, discovered one build at a time ──────
#
# sdbusplus generates C++ from YAML and needs inflection + mako at configure
# time and jsonschema at compile time. None of it is documented in the tree.
log "creating a virtualenv with all three generator dependencies at once"
if [ ! -x "${VENV}/bin/meson" ]; then
    run python3 -m venv "$VENV" || die "venv creation failed"
    "${VENV}/bin/pip" install -q --upgrade pip
    "${VENV}/bin/pip" install -q meson ninja inflection mako pyyaml jsonschema \
        || die "pip install failed"
fi

# ── blocker 2: the venv must be on PATH, not merely used to launch meson ────
#
# sdbusplus's meson.build resolves the generator with find_program('python3'),
# which searches PATH. Running ${VENV}/bin/meson without activating the venv
# finds /usr/bin/python3, which does not have the modules — and reports the
# same "missing modules" error as before, so it reads as "the fix did not
# work" rather than "the fix went to the wrong interpreter".
export PATH="${VENV}/bin:${PATH}"
ok "python3 resolves to $(command -v python3)"
ok "meson   resolves to $(command -v meson)"

hdr "meson setup"
rm -rf build
SETUP_LOG="${LAB_DIR}/logs/obmc-setup-$(date -u +%Y%m%dT%H%M%SZ).log"
mkdir -p "$(dirname "$SETUP_LOG")"
meson setup build > "$SETUP_LOG" 2>&1
SETUP_RC=$?
if [ "$SETUP_RC" -eq 0 ]; then
    ok "setup succeeded — $(grep -c 'Build targets' "$SETUP_LOG" >/dev/null && grep -m1 'Build targets' "$SETUP_LOG")"
else
    warn "setup failed (rc=${SETUP_RC})"
    grep -E 'ERROR|missing modules' "$SETUP_LOG" | head -5 | sed 's/^/  | /'
    hdr "stopped at setup — see ${SETUP_LOG}"
    exit 0
fi

hdr "meson compile"
COMPILE_LOG="${LAB_DIR}/logs/obmc-compile-$(date -u +%Y%m%dT%H%M%SZ).log"
meson compile -C build > "$COMPILE_LOG" 2>&1
COMPILE_RC=$?
if [ "$COMPILE_RC" -eq 0 ]; then
    ok "compile succeeded — the blockers recorded in docs/upstream/ are gone"
    hdr "meson test"
    meson test -C build --print-errorlogs 2>&1 | tail -15
    exit 0
fi

warn "compile failed (rc=${COMPILE_RC}) — this is the expected outcome, see docs/upstream/"
printf '\n  blockers observed:\n'
if grep -q 'internal compiler error' "$COMPILE_LOG"; then
    printf '  * GCC internal compiler error:\n'
    grep -m1 -B1 'internal compiler error' "$COMPILE_LOG" | sed 's/^/      /'
fi
if grep -q 'formatter must be specialized' "$COMPILE_LOG"; then
    printf '  * std::formatter has no specialization for a type the tests format:\n'
    grep -m1 'evaluates to false' "$COMPILE_LOG" | sed 's/^/      /'
fi
if grep -q 'ModuleNotFoundError' "$COMPILE_LOG"; then
    printf '  * a python generator dependency is still missing:\n'
    grep -m1 'ModuleNotFoundError' "$COMPILE_LOG" | sed 's/^/      /'
fi

printf '\n  compiler: %s\n' "$(gcc --version | head -1)"
printf '  full log: %s\n' "$COMPILE_LOG"

hdr "finished — failure recorded, not an error in this script"
exit 0

#!/usr/bin/env bash
#
# negative/asan_demo.sh — what the toolchain in front of us actually watches.
#
# Two writes of seventy-two bytes into a sixty-four byte destination. They
# differ only in how the destination was declared, and they are treated
# differently at both layers that are supposed to catch them:
#
#   char cn[64];                             ASan reports it
#   struct { char cn[64]; ... } f;  f.cn     ASan says nothing
#
# and before either runs, with a CONSTANT length, GCC rejects only the first at
# compile time through _FORTIFY_SOURCE's fortified memcpy. That is why
# test_oversized_field.c makes the length volatile: a length off the wire is
# never a constant, so the static check is not the one protecting a responder.
#
# This script asserts both halves. It exists because docs/roadmap.md standing
# rule 11 applies to the INSTRUMENT as much as to the code: a project that
# leans on AddressSanitizer in four places should be able to say where it stops
# looking, and should have watched it stop rather than read that it does.
#
#   bash negative/asan_demo.sh ./test_oversized_field
#
# Run from `make test`, so a toolchain upgrade that changes either answer turns
# the build red rather than quietly invalidating a paragraph in docs/.

set -u

BIN="${1:-./test_oversized_field}"

if [ ! -x "$BIN" ]; then
    echo "  asan_demo: $BIN is not executable" >&2
    exit 1
fi

fails=0

# ---------------------------------------------------------------------------
# A bare array. Expected: the sanitizer reports a bad write, and the process
# exits non-zero. ASAN_OPTIONS sets abort_on_error=0 in the Makefile, so this
# is an exit rather than a signal.
out="$("$BIN" --asan-demo bare 2>&1)"
rc=$?
if [ "$rc" -eq 0 ]; then
    echo "  asan_demo bare: exited 0. The overflow out of a BARE array was not"
    echo "                  reported, which this repository has been assuming it"
    echo "                  would be since week one."
    fails=$((fails + 1))
elif printf '%s' "$out" | grep -qiE 'AddressSanitizer|stack-buffer-overflow|unknown-crash'; then
    echo "  asan_demo bare  : reported by AddressSanitizer, exit $rc   (as expected)"
else
    echo "  asan_demo bare  : exit $rc but no sanitizer report in the output"
    printf '%s\n' "$out" | sed 's/^/      /' | head -5
    fails=$((fails + 1))
fi

# ---------------------------------------------------------------------------
# The same overflow into the next member of the same object. Expected: nothing
# from the sanitizer, exit 0, and the guard byte after the destination
# overwritten — which the program checks itself, because nothing else will.
out="$("$BIN" --asan-demo member 2>&1)"
rc=$?
if printf '%s' "$out" | grep -qiE 'AddressSanitizer|stack-buffer-overflow'; then
    echo "  asan_demo member: AddressSanitizer DID report an overflow between two"
    echo "                    members of one object. That is better than expected"
    echo "                    and docs/negative-tests.md now says something false."
    printf '%s\n' "$out" | sed 's/^/      /' | head -8
    fails=$((fails + 1))
elif [ "$rc" -ne 0 ]; then
    echo "  asan_demo member: exit $rc"
    printf '%s\n' "$out" | sed 's/^/      /' | head -8
    fails=$((fails + 1))
elif printf '%s' "$out" | grep -q 'NOT REPORTED'; then
    echo "  asan_demo member: silent, and the guard after the destination was"
    echo "                    overwritten                          (as expected)"
else
    echo "  asan_demo member: exit 0 but the guard was not touched, so the"
    echo "                    demonstration demonstrated nothing"
    printf '%s\n' "$out" | sed 's/^/      /' | head -5
    fails=$((fails + 1))
fi

exit $((fails > 0 ? 1 : 0))

# device/ — the measurement source module, built and tested on its own.
#
#   make            build the self-test
#   make test       run it under AddressSanitizer and UBSan
#   make interop    the C reader and the Python writer must agree byte for byte
#   make clean
#
# Why this builds outside the libspdm tree
# ----------------------------------------
# measurement_source.c is compiled twice: once here, on its own, with two
# sanitizers and -Werror; and once inside libspdm's sample device secret
# library, where it is one of twenty-two translation units in a thirty-minute
# build that produces no test binary at all.
#
# Only the first of those can be run in CI, on a machine with no build tree, in
# under a second. A module that can only be exercised by rebuilding libspdm is
# a module that gets exercised when somebody has half an hour, which is another
# way of saying rarely. So the module takes no dependency on libspdm — not one
# header — and that constraint is what keeps this Makefile possible.
#
# The flags are the same ones c-drills/Makefile uses, for the same reasons.

CC      ?= gcc
CFLAGS  ?= -std=c11 -Wall -Wextra -Werror -g -O1 \
           -fsanitize=address,undefined -fno-omit-frame-pointer
LDFLAGS ?= -fsanitize=address,undefined
PYTHON  ?= python3

export ASAN_OPTIONS  ?= detect_leaks=1:abort_on_error=0
export UBSAN_OPTIONS ?= print_stacktrace=1:halt_on_error=1

BIN := measurement_source_test

.PHONY: all test interop clean

all: $(BIN)

$(BIN): measurement_source_test.c measurement_source.c measurement_source.h
	@printf '  CC   %s\n' "$@"
	@$(CC) $(CFLAGS) -o $@ measurement_source_test.c measurement_source.c $(LDFLAGS)

test: $(BIN)
	@./$(BIN)

# Two implementations of one file format: the C reader that the responder
# links, and the Python writer that produces every fixture. Standing rule 12 —
# where two tools can reach the same quantity by different routes, they are
# made to agree. Here the quantity is the whole file.
#
# The failure this catches is specific and would otherwise be silent: a format
# change made in one language and not the other produces a fixture the
# responder refuses, and the refusal surfaces as a handshake that carries
# upstream's synthetic measurements instead of the tampered ones — an
# experiment that reports "no effect" for a tamper that never happened.
interop: $(BIN)
	@$(PYTHON) gen_measurements.py --out .interop_py.bin > /dev/null
	@./$(BIN) --emit .interop_c.bin
	@if cmp -s .interop_py.bin .interop_c.bin; then \
	    printf '  ok   gen_measurements.py and the C builder write identical bytes (%s)\n' \
	        "$$(wc -c < .interop_py.bin) bytes"; \
	else \
	    echo "  FAIL the Python writer and the C builder disagree:"; \
	    cmp -l .interop_py.bin .interop_c.bin | head -20; \
	    rm -f .interop_py.bin .interop_c.bin; \
	    exit 1; \
	fi
	@./$(BIN) --emit .interop_c.bin
	@$(PYTHON) gen_measurements.py --describe .interop_c.bin | sed 's/^/       /'
	@rm -f .interop_py.bin .interop_c.bin

clean:
	@rm -f $(BIN) .ms_case.bin .interop_py.bin .interop_c.bin
	@rm -rf *.dSYM

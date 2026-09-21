# negative/ - three advisory CLASSES, written as tests that can fail.
#
#   make            build every test (skeletons included)
#   make test       run the tests listed in DONE.txt, and every defect variant
#   make list       what is present, what is claimed, and what each one asserts
#   make clean
#
# Same flags and the same DONE.txt mechanism as c-drills/Makefile and
# device/Makefile, and deliberately so: the three directories are the same
# argument applied to three subjects. A test that has not been written yet
# still has to COMPILE - so a syntax error turns the badge red on the day it is
# committed - but it is not executed and it is not claimed.
#
# Why this builds outside libspdm
# -------------------------------
# For device/Makefile's reason, word for word: a module that can only be
# exercised by rebuilding libspdm is a module that gets exercised when somebody
# has half an hour. Nothing here includes a libspdm header or links a libspdm
# object, and that constraint is what lets CI run it on a machine with no build
# tree in under a second.
#
# It also keeps the claim honest. These tests say a CLASS is understood. They
# would say something much stronger - and unsupported - if they linked the
# library and appeared to be testing it.
#
# ★ The defect variants, and why `make test` is not just a loop
# -------------------------------------------------------------
# Standing rule 11 says a check is worth what it rejects and that something has
# to prove it rejects. `make test` therefore builds each finished test TWICE OR
# MORE: once as the implementation the file argues is correct, and once per
# declared defect with -DNEG_DEFECT=k.
#
# Each binary exits 0 when it behaved as its own file says it must, so this
# recipe does not have to know which kind it is running. What differs is what
# "as it must" means, and the binary prints which question it answered.
#
# How many defects a file has is asked OF the file - `./test_x --defects` -
# rather than written here. A count kept in two places is a count that drifts,
# and this repository has caught that four times.

CC      ?= gcc
CFLAGS  ?= -std=c11 -Wall -Wextra -Werror -g -O1 \
           -fsanitize=address,undefined -fno-omit-frame-pointer
LDFLAGS ?= -fsanitize=address,undefined

export ASAN_OPTIONS  ?= detect_leaks=1:abort_on_error=0
export UBSAN_OPTIONS ?= print_stacktrace=1:halt_on_error=1

SOURCES := $(sort $(wildcard test_*.c))
TESTS   := $(basename $(SOURCES))
DONE    := $(shell sed -e 's/#.*//' -e '/^[[:space:]]*$$/d' DONE.txt 2>/dev/null)

.PHONY: all test list clean

all: $(TESTS)

%: %.c negative.c negative.h
	@printf '  CC   %s\n' "$<"
	@$(CC) $(CFLAGS) -o $@ $< negative.c $(LDFLAGS)

list: all
	@echo "present : $(TESTS)"
	@echo "claimed : $(DONE)"
	@for t in $(TESTS); do \
	    printf '\n--- %s ---\n' "$$t"; ./$$t --list; \
	done

test: all
	@if [ -z "$(strip $(DONE))" ]; then \
	    echo "no negative test is marked complete in DONE.txt yet"; \
	    echo "(all $(words $(TESTS)) skeletons compiled under -Werror + both sanitizers)"; \
	    exit 0; \
	fi; \
	fails=0; ntests=0; ndefects=0; \
	for t in $(DONE); do \
	    if [ ! -x "./$$t" ]; then \
	        echo "MISSING  $$t  (listed in DONE.txt but no such test)"; \
	        fails=$$((fails+1)); continue; \
	    fi; \
	    ntests=$$((ntests+1)); \
	    if ./$$t; then echo "  PASS     $$t (correct implementation)"; \
	    else echo "  FAIL     $$t (correct implementation)"; fails=$$((fails+1)); fi; \
	    n=$$(./$$t --defects); \
	    k=1; \
	    while [ "$$k" -le "$$n" ]; do \
	        $(CC) $(CFLAGS) -DNEG_DEFECT=$$k -o ".defect_$$t_$$k" "$$t.c" negative.c $(LDFLAGS) \
	            || { echo "  FAIL     $$t defect $$k does not compile"; fails=$$((fails+1)); k=$$((k+1)); continue; }; \
	        ndefects=$$((ndefects+1)); \
	        if ./".defect_$$t_$$k"; then echo "  PASS     $$t defect $$k (caught, by exactly the declared cases)"; \
	        else echo "  FAIL     $$t defect $$k"; fails=$$((fails+1)); fi; \
	        rm -f ".defect_$$t_$$k"; \
	        k=$$((k+1)); \
	    done; \
	    if [ "$$t" = "test_oversized_field" ]; then \
	        echo; \
	        echo "  what the toolchain watches, asserted rather than recalled:"; \
	        bash asan_demo.sh "./$$t" || fails=$$((fails+1)); \
	    fi; \
	done; \
	echo; \
	if [ $$fails -eq 0 ]; then \
	    echo "ALL NEGATIVE TESTS PASS — $$ntests suite(s), $$ndefects defect variant(s),"; \
	    echo "each defect caught by exactly the cases its file predicted and no others"; \
	else echo "$$fails FAILED"; exit 1; fi

clean:
	@rm -f $(TESTS) .defect_*

# negative/ - three advisory CLASSES, written as tests that can fail.
#
#   make            build every test (skeletons included)
#   make test       run the tests listed in DONE.txt
#   make list       what is present, and what is claimed
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

%: %.c negative.h
	@printf '  CC   %s\n' "$<"
	@$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

list:
	@echo "present : $(TESTS)"
	@echo "claimed : $(DONE)"

test: all
	@if [ -z "$(strip $(DONE))" ]; then \
	    echo "no negative test is marked complete in DONE.txt yet"; \
	    echo "(all $(words $(TESTS)) skeletons compiled under -Werror + both sanitizers)"; \
	    exit 0; \
	fi; \
	fails=0; \
	for t in $(DONE); do \
	    if [ ! -x "./$$t" ]; then \
	        echo "MISSING  $$t  (listed in DONE.txt but no such test)"; \
	        fails=$$((fails+1)); continue; \
	    fi; \
	    printf '\n--- %s ---\n' "$$t"; \
	    if ./$$t; then echo "PASS     $$t"; else echo "FAIL     $$t"; fails=$$((fails+1)); fi; \
	done; \
	echo; \
	if [ $$fails -eq 0 ]; then echo "ALL NEGATIVE TESTS PASS ($(words $(DONE)) complete)"; \
	else echo "$$fails FAILED"; exit 1; fi

clean:
	@rm -f $(TESTS)

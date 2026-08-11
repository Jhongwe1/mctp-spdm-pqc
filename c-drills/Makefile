# c-drills — eight C exercises pulled out of the problems this project runs into.
#
#   make            build every drill
#   make test       run the drills listed in DONE.txt
#   make d3_queue_via_list && ./d3_queue_via_list     build and run just one
#   make clean
#
# The flags are not decoration. -Werror means a warning is a failure, and
# AddressSanitizer + UndefinedBehaviorSanitizer turn the two bug classes these
# drills exist to teach — use-after-free and leaked nodes — from "the tests
# happened to pass" into a hard stop with a stack trace.
#
# DONE.txt is what `make test` runs. A drill that has not been written yet
# still has to COMPILE (so `make` catches syntax problems immediately) but is
# not executed, which keeps CI honest: it reports progress rather than
# pretending an unwritten drill passes.

CC      ?= gcc
CFLAGS  ?= -std=c11 -Wall -Wextra -Werror -g -O1 \
           -fsanitize=address,undefined -fno-omit-frame-pointer
LDFLAGS ?= -fsanitize=address,undefined

# Leak detection is the whole point of drill boundary (3): "queue_free must not
# miss a node". Make it explicit rather than relying on a default.
export ASAN_OPTIONS ?= detect_leaks=1:abort_on_error=0
export UBSAN_OPTIONS ?= print_stacktrace=1:halt_on_error=1

SOURCES := $(sort $(wildcard d[0-9]*.c))
DRILLS  := $(basename $(SOURCES))
DONE    := $(shell sed -e 's/#.*//' -e '/^[[:space:]]*$$/d' DONE.txt 2>/dev/null)

.PHONY: all test list clean

all: $(DRILLS)

%: %.c
	@printf '  CC   %s\n' "$<"
	@$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

list:
	@echo "present : $(DRILLS)"
	@echo "complete: $(DONE)"

test: all
	@if [ -z "$(strip $(DONE))" ]; then \
	    echo "no drills marked complete in DONE.txt yet — nothing to run"; \
	    echo "(every drill still compiled cleanly under -Werror + sanitizers)"; \
	    exit 0; \
	fi; \
	fails=0; \
	for d in $(DONE); do \
	    if [ ! -x "./$$d" ]; then \
	        echo "MISSING  $$d  (listed in DONE.txt but no such drill)"; \
	        fails=$$((fails+1)); continue; \
	    fi; \
	    printf '\n--- %s ---\n' "$$d"; \
	    if ./$$d; then echo "PASS     $$d"; else echo "FAIL     $$d"; fails=$$((fails+1)); fi; \
	done; \
	echo; \
	if [ $$fails -eq 0 ]; then echo "ALL DRILLS PASS ($(words $(DONE)) complete)"; \
	else echo "$$fails drill(s) failed"; exit 1; fi

clean:
	@rm -f $(DRILLS)
	@rm -rf *.dSYM

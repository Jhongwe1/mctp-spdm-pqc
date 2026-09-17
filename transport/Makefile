# transport/ — the two Gate 5 programs, built and checked on their own.
#
#   make            build both
#   make check      compile them a second way, with two sanitizers and -Werror
#   make clean
#
#   mctp_bridge     carries the spdm-emu handshake across a real MCTP network
#   doe_probe       drives a real PCIe DOE mailbox from userspace
#
# Why there is no `make test` here
# --------------------------------
# Every interesting behaviour of these two programs needs something this host
# does not have. mctp_bridge needs a kernel with CONFIG_MCTP — on this one,
# `socket(AF_MCTP, SOCK_DGRAM, 0)` returns EAFNOSUPPORT, recorded in
# docs/env-baseline.md. doe_probe needs a PCI device with a Data Object
# Exchange capability, and there is none. So the runtime tests live in
# harness/run_afmctp.sh and harness/run_doe.sh, which boot the guest that has
# both, and what is checkable without a virtual machine is exactly this: that
# they compile clean under -Werror and under AddressSanitizer and UBSan.
#
# That distinction is deliberate rather than a gap. A `make test` here would
# have to either skip on this host — a test that has never run — or fake the
# socket family and the config space, which would test the fake. The compile is
# honest about being a compile.
#
# The flags are the ones c-drills/Makefile and device/Makefile use, for the
# same reasons.

CC      ?= gcc
CFLAGS  ?= -std=c11 -Wall -Wextra -Werror -g -O2
SANFLAGS := -std=c11 -Wall -Wextra -Werror -g -O1 \
            -fsanitize=address,undefined -fno-omit-frame-pointer
SANLD    := -fsanitize=address,undefined

BINS := mctp_bridge doe_probe

.PHONY: all check clean

all: $(BINS)

mctp_bridge: mctp_bridge.c
	@printf '  CC   %s\n' "$@"
	@$(CC) $(CFLAGS) -o $@ mctp_bridge.c

doe_probe: doe_probe.c
	@printf '  CC   %s\n' "$@"
	@$(CC) $(CFLAGS) -o $@ doe_probe.c

# The second compilation. It produces binaries that are not what gets run in
# the guest — the guest runs the -O2 ones — so this exists for the diagnostics
# and not for the artifact, and the artifacts are removed again.
check: mctp_bridge.c doe_probe.c
	@for b in $(BINS); do \
	    printf '  CC   %s.san (asan+ubsan)\n' "$$b"; \
	    $(CC) $(SANFLAGS) -o $$b.san $$b.c $(SANLD) || exit 1; \
	    out=$$(./$$b.san --help 2>&1 | head -1); \
	    case "$$out" in *usage*) printf '  ok   %s: sanitized build starts and prints its usage\n' "$$b" ;; \
	                    *) printf '  FAIL %s printed: %s\n' "$$b" "$$out"; exit 1 ;; esac; \
	    rm -f $$b.san; \
	done

clean:
	@rm -f $(BINS) $(addsuffix .san,$(BINS))
	@rm -rf *.dSYM

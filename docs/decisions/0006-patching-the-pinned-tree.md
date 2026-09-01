# 0006 — A patch to the pinned tree, not a fork and not a second build

**Status:** accepted, 2026-09-01
**Supersedes nothing. Amends [0001](0001-two-build-flavors.md) and
[0003](0003-provenance-manifests.md), both of which assume a pin fully
describes a binary.**

## The problem

Gate 2 needs a measurement whose bytes can be changed. libspdm's sample device
secret library does not have one: index 1 is the SHA-512 of 72 bytes of `0x01`
and the secure version number is the constant `0x7`, both compiled in. A tamper
test needs an input, and a constant inside a function is not one.

So upstream source has to change. This repository has two standing rules that
make that awkward, and they were written on purpose:

- **no upstream source is vendored** — `third_party/*.pin` records commits and
  `harness/build_spdm_emu.sh` reconstructs the trees;
- **every result names the build that produced it**, automatically, through
  `manifest.json`.

A modified build tree satisfies neither by default. The pin still says
`libspdm 8a92317`, which is true and no longer sufficient.

## What was decided

**A patch plus a script, applied to the pinned tree, with the patch's digest
folded into every manifest taken afterwards.**

Three parts, and the split between them is the decision:

1. **`device/measurement_source.{c,h}` is this project's**, takes no libspdm
   dependency at all, and is compiled and tested on its own by `device/Makefile`
   under two sanitizers in under a second.
2. **`device/meas-from-file.patch` is sixteen added lines across two files, no
   deleted ones, three of which are code.** Both additions sit on the line
   *after* upstream computes its own value and leave the destination untouched
   when they decline, so the diff is purely additive.
3. **`harness/apply_device_patch.sh` is the only supported way to apply it**,
   and it writes `DEVICE_PATCH.txt` beside `BUILD_PIN.txt` in the same
   `key=value` form, so `prov_pin_file` folds it in with no new mechanism.

Turned on by `SPDM_MEASUREMENTS_FILE`. Unset, no file is opened.

## Alternatives rejected

**Fork libspdm and vendor it.** The diff is the artifact. A fork is reviewable
only by someone who already knows what upstream looked like, and it would make
"I did not change libspdm's logic" a claim rather than something a reader can
check in sixteen lines. It also breaks the no-vendoring rule for the rest of
the project's life to serve one week.

**A second build tree, `spdm-emu-pqc-meas`.** Clean isolation: the baseline
tree is never touched. Rejected on three counts. It costs a thirty-minute build
and several GB. It requires `flavor_emu_ref()` — named in `CLAUDE.md` as the
single source of truth about versions — to grow a third flavor that is not a
version at all. And it does not actually buy the guarantee it appears to,
because the thing that has to be true is *"the patched binary behaves as
upstream does when the fixture is absent"*, and a second tree does not
demonstrate that; a capture does.

**Rewrite `meas.c` to read from a file throughout.** This is the tempting one,
because the result reads better as code. It would destroy the point of the
measurements: a capture would then measure this project's implementation rather
than libspdm's, and every number in `docs/tamper.md` and every later comparison
against upstream behaviour would lose its meaning. **The smallness of the diff
is not tidiness, it is the argument.**

**Do it at runtime with no source change at all** — `LD_PRELOAD`, or a
debugger. Leaves nothing reviewable, works differently on every host, and
produces a binary that is harder to describe in a manifest than a patched one.

## How the risk is actually contained

The hazard is exact and this repository has met it before: `certs/stage_chain.sh`
exists because overwriting the build tree's certificates *would have worked*
and would also have meant every later health check and baseline silently
measured the wrong chain, with nothing recording it. A patch cannot be
sandboxed the same way, because it has to be compiled in. So three other things
carry the weight.

**One — the claim is checked against a capture, not asserted.** The measurement
record is deterministic: no nonce, no timestamp. `bench/data/w4-tamper-*/t0_none`
reproduces the record digest of a capture committed before this patch was
written, byte for byte, and `verify_repo.sh` re-derives that invariant from
every baseline capture in the repository on every run.

**Two — the script refuses the two ways this goes wrong quietly.** The tree's
libspdm commit must equal `third_party/spdm-emu-pqc.pin`, and `meas.c` and
`CMakeLists.txt` must hash to the values the patch was made against. The second
is the one `git apply` cannot provide: it checks context, and would accept a
patch whose context survived a revision that changed what the context means.

**Three — a person is told.** `harness/healthcheck.sh` prints whether the patch
is applied, in the report someone reads *before* trusting a number, not only in
the manifest a machine reads afterwards.

## What this costs, stated rather than discovered later

A baseline taken from the patched tree is still correct, but the control for a
tamper experiment should not come from a binary carrying the code under test.
So taking a baseline now means: revert, rebuild, capture, re-apply, rebuild.
That is two builds, and 2026-09-01 in `LOG.md` is the day it was paid.

The alternative — accepting a control from the patched binary — is cheaper
every week and gives up the one sentence the whole change exists to support.

# 0007 — A second implementation of CoRIM and COSE, made to agree with the first

**Status:** accepted, 2026-09-12
**Amends nothing. Extends [0004](0004-derivations-must-reproduce.md), whose
argument is that a copy taken out of a source must be re-derivable from that
source — here the "source" is somebody else's format rather than a file.**

## The problem

Gate 3 needs reference values, an endorsement over them, and a policy. DMTF
ships all three in `spdm-emu/spdm_emu/spdm_device_verifier_tool/` — CoRIM
manifests, COSE signing, an Open Policy Agent policy — and this project's plan
was built around using them.

Running the published example verbatim, before connecting anything, it does not
work. Seven findings, recorded with their reproductions in
[`docs/upstream/README.md`](../upstream/README.md); the two that decide this
ADR are:

- **`requirements.txt` sets no upper bounds.** `cbor2` ≥ 6.0 decodes the
  contents of a `CBORTag` as immutable containers and `pycose` type-checks for
  `list`, so on a fresh install **pycose cannot decode its own `encode()`
  output**. Pinning `cbor2==5.6.5` works around it.
- **`CoRimTool.py verify` does not verify**, in two lines that mask each other.

And one constraint that is not about upstream at all: **the job that turns red
when a tampered measurement stops being rejected runs on a GitHub runner with
no `spdm-emu` checkout, no WSL, and no local patches.** A verifier that cannot
run there is a verifier that never fails.

## The three options

1. **Use DMTF's tools.** Faithful to "the reference implementation already does
   this", and it needs a vendored patch (which `CLAUDE.md` forbids), a pinned
   old `cbor2`, and a `spdm-emu` clone inside CI. The most important job in the
   repository becomes the heaviest and the most fragile one.
2. **Write our own and stop there.** Fastest, and CI stays clean. It throws
   away the interoperability claim entirely: nothing would show that this
   project's evidence and reference values are the shapes a DMTF tool reads,
   and the policy would be accepting documents produced by the same author who
   wrote the policy.
3. **Both, required to agree.**

## What was decided

**Option 3.** `rats/` is this project's implementation and owns the CI path;
DMTF's tools are run once, locally, by `rats/interop.sh`, and their outputs are
**committed** so that CI re-derives this project's side against them on a runner
that has none of what the comparison needs.

This is not a new arrangement. It is the one `pcapcount.py` and `fields.py`
already have, and `bench/pcapstat.py` after them —
[`docs/roadmap.md`](../roadmap.md) standing rule 12: *where two tools can reach
the same quantity by different routes, they are made to agree.*

What is compared, and how the comparison is chosen:

| | route | verdict |
|---|---|---|
| evidence JSON | `SpdmMeasurement.py` vs `rats/appraise.py evidence` | byte-identical, apart from the final newline DMTF's writer omits |
| CoRIM encoding | `CoRimTool.py json_to_cbor` vs `rats/appraise.py to-cbor` | byte-identical, 1480 bytes |
| signatures | each tool must accept the other's | both directions |

**Byte-equality where the operation is deterministic, cross-verification where
it is not.** An ECDSA signature carries a random nonce, so two signers over one
payload produce different files and "identical bytes" is not a property either
could have. Cross-verification is the strongest statement available, and
demanding byte-equality there would have been a check that fails for a reason
neither tool is responsible for.

### The cryptography is not ours

`rats/cose.py` does the *encoding* either side of a signature — the CBOR, the
COSE `Sig_structure`, and the conversion between OpenSSL's DER `(r, s)` and
COSE's fixed-width `r ‖ s`. Signing and verifying are `openssl` subprocesses,
which `certs/` already depends on.

An ECDSA implementation written here would be a second one to get right with
nothing checking it. The conversion is the only arithmetic in the file and it is
the one place a mistake could be silent, so `selftest` attacks it hardest: three
of its cases fail on about half of all signatures and pass on the other half,
which is the worst failure distribution a check can have.

### What is not deterministic is not compared at all

`rats/cose.py`'s CBOR encoder deliberately does **not** sort map keys, although
RFC 8949 §4.2.1 asks for it. `cbor2.dumps()` emits insertion order, the
interoperability check feeds one JSON file to both encoders and requires the
same bytes out, and sorting here would make that comparison impossible to pass
for a reason unrelated to either tool being wrong. `--sort-keys` exists and
nothing in this project uses it. The trade is stated in the module docstring
rather than left to be rediscovered.

## What it costs

- **Roughly 200 lines of CBOR and COSE that somebody else has already written.**
  The honest accounting: they are not lines this project would have written for
  fun, and the reason they exist is a defect count in the alternative.
- **A pinned Python environment on one machine.** `rats/interop.sh` needs
  `cbor2==5.6.5` and a `spdm-emu` checkout, so it runs where those are and
  nowhere else. Its outputs carry the run's versions in
  [`rats/interop/report.md`](../../rats/interop/report.md).
- **A reference value format chosen to match DMTF's quirks rather than the
  draft.** This project writes the hash algorithm as an integer (`8`) rather
  than a name (`"sha512"`), because `CoRimTool.py`'s `translate_data` maps
  exactly two name strings to integers, hard-coded, and a CoMID naming `sha512`
  encodes it as text — 43 bytes of difference between two encoders both doing
  what they were told. Matching the published sample is what makes the byte
  comparison possible at all, and the divergence from the draft is recorded
  rather than silently inherited.
- **A pin for the policy engine.** `third_party/opa.pin`, because every verdict
  is produced by `opa` evaluating `rats/policy.rego` and OPA's major version
  decides which Rego dialect that file has to be written in.

## What it buys, beyond CI

Two things that were not the reason for the decision and turned out to matter
more than the reason.

**The comparison found three differences before it agreed, and two of them were
this project's.** A signed CoRIM is `#6.500(#6.502(COSE_Sign1))` per the draft
and this project wrote a bare `#6.18`; the algorithm identifier was written as a
name. Neither would have been noticed by a pipeline that only ever talked to
itself.

**And the upstream report is re-run by the comparison.** `rats/interop.sh`
requires an **unpatched** `CoRimTool.py` to refuse a valid signature, and a
**half-patched** one to accept a forged one. Those are the two claims this
project is sending upstream. The day either stops being true, the script says
so instead of the bug report going quietly stale.

## The alternative that is still open

If DMTF's tools are fixed — this project has a change prepared for the sharpest
of the seven findings — option 1 becomes cheaper, and the parts of `rats/` that
duplicate them could be retired in favour of calling them. The interoperability
comparison is what would make that a small change rather than a rewrite: it
already establishes that the two produce the same documents.

What would **not** be retired is `rats/policy.rego`. That is not a
reimplementation of DMTF's sample; it is a different policy, and
[`docs/rats-pipeline.md`](../rats-pipeline.md) §5 measures three inputs the
sample accepts and it refuses.

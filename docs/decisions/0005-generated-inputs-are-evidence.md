# ADR 0005 — A generated input is evidence, and regenerating it is not reproducing it

**Status:** accepted · **Date:** 2026-08-31 · **Gate:** G2
· **Extends:** [ADR 0004](0004-derivations-must-reproduce.md)

## Context

ADR 0004 sorted this repository's artifacts into two kinds and gave each the
guarantee it can actually have:

| | what it is | what a matching digest tells you |
|---|---|---|
| `*.pcap`, `*.decode.txt`, `*.hex.txt` | **evidence** — what happened on the wire | everything |
| `*.fields.json` | **a derivation** — a tool's reading of that evidence | only that nobody edited it, so it must also be required to *reproduce* |

Week three produced a third kind, and neither guarantee fits it.

`certs/gen_chain.sh` builds this project's own three-layer certificate chain,
and the captures that use it publish its numbers: 504 + 573 + 768 bytes of DER,
1,897 bytes on the wire, a `RootHash` of `df0ee8f9…`. Those numbers are
measured, they are checked by CI against the capture, and they are attested by a
manifest.

But the chain is an **input**, not an output, and it is not reproducible:

- the keys are fresh on every run, so every certificate differs;
- an ECDSA signature is DER-encoded as two integers whose encoded length depends
  on whether their high bit happens to be set, so even the byte **count** of a
  regenerated certificate moves by a byte or two;
- and the private keys are deliberately not committed, so a fresh clone cannot
  reproduce the run even in principle.

Treating it as a derivation and requiring reproduction would fail on every
machine. Treating it as evidence and requiring only that its digest match is
correct — but incomplete, because it leaves unstated that `gen_chain.sh --force`
silently invalidates every published number without touching a single committed
file's digest.

The failure mode this creates is precise and would look like nothing at all:
someone regenerates the chain to see how the script works, `verify_repo.sh`
reports every artifact unaltered because the run directory was not touched, and
`docs/certchain.md` now describes a chain that no longer exists on that machine.

## Decision

**A generated input is committed as evidence, and the tool that generates it
refuses to overwrite what is committed.**

Three parts, and the second is the one that does the work:

1. **The certificates are committed; the private keys are not.**
   `.gitignore` excludes `*.key` and `*.key.pem`, and `verify_repo.sh` reads
   every tracked file for a PEM private-key header rather than trusting either
   pattern — because `*.key` already failed to match a second spelling that
   `gen_chain.sh` once wrote.

2. **`gen_chain.sh` refuses to run when `certs/out/` is non-empty**, and its
   refusal explains what would break rather than saying the directory exists.
   `--force` is available and says in the same message that every published
   byte count becomes false when it is used. This is the certificate equivalent
   of ADR 0004's refusal to re-stamp a manifest: the cheap repair is made
   impossible so the expensive one has to happen.

3. **What is required to reproduce is the *relationship*, not the bytes.**
   `certs/check_chain.py` re-derives every structural fact and the wire
   arithmetic from whatever chain is present — three DER certificates that
   parse and consume the bundle exactly, a leaf that verifies to the root
   through the intermediate, both identity OIDs located in the DER, and
   `4 + H + Σ|certᵢ|` as the chain's length on the wire. That holds for any
   chain the script produces, on any machine, including one whose byte counts
   differ from the published ones.

So the published numbers are properties of the committed chain, and the
published *method* is a property of the script. The document says which is
which, in the place a reader would otherwise assume the stronger claim.

## Consequences

**A fresh clone can verify everything and reproduce almost nothing.** It can
re-hash every artifact, re-derive every claim in `docs/certchain.md` from the
committed capture, and re-run `check_chain.py` against the committed
certificates. It cannot take a *new* capture with this chain, because it has no
private key. `RUNBOOK.md` §11 states this where someone will hit it, rather than
leaving them to discover it from a missing-file error.

**This is a real reduction in reproducibility and it is the right trade.** The
alternative is committing four private keys, and the argument for doing so is
that they protect nothing — an emulator, on a laptop, signing nothing anyone
depends on. That argument is correct today and is exactly the reasoning that
puts a key in a repository the one time it matters. A habit that only applies to
important keys is not a habit.

**The category now has a name, which is the point.** This repository already
distinguishes evidence from derivations. It now also distinguishes a *generated
input*: evidence about a run, unreproducible by construction, and dangerous
precisely because regenerating it looks like a no-op. `figures/` will be in this
category the moment it exists, and so will any future measurement fixture.

**One check moved from a pattern to a scan.** `verify_repo.sh` reading every
tracked file for a private-key header costs about a second and replaces a rule
that had already been wrong once. It also found the first file it looked at was
itself — a checker that spells out what it forbids becomes an instance of it —
so the markers are assembled at run time.

## Alternatives rejected

- **Commit the private keys so the chain is fully reproducible.** Reproducibility
  is not worth the habit. And it would not even achieve the goal: a second
  machine could take an identical capture, but the moment `--force` is run
  anywhere the published numbers are wrong again, so the guard in (2) would
  still be necessary.

- **Make `gen_chain.sh` deterministic** by seeding key generation from a fixed
  value. It would produce a repository whose private keys are recoverable from
  its own source, which is worse than committing them, because it looks safe.

- **Do not commit the chain; regenerate it in CI.** Then the published byte
  counts are properties of whatever CI happened to generate that morning, and
  `docs/certchain.md` could not state a single number. The whole point of the
  chain was to make the wire arithmetic checkable against a specific artifact.

- **Treat the chain as a derivation and require reproduction.** It would fail
  on the machine that created it, one second after creating it.

- **Say nothing and rely on nobody running `--force`.** That is a convention,
  and ADR 0003 exists because this project does not run on conventions.

## How to check this is working

```bash
bash harness/verify_repo.sh
#   no tracked file carries a private-key header
#   the committed chain links to its root and carries both identity OIDs
#   four breaks, four distinct checks, every one rejected

bash certs/gen_chain.sh
#   must REFUSE, and say why, while certs/out/ holds a chain

python3 certs/check_chain.py certs/out --self-test
#   4 breaks, 4 distinct checks — none redundant
```

The last line is the one that decays quietly. Two breaks caught by the same
check means one of the checks between them has never rejected anything, and that
was true of this suite until the order of two checks was swapped — so the
self-test asserts distinctness, not just rejection.

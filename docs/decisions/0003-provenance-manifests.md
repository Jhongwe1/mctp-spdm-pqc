# ADR 0003 — Provenance is a mechanism, not a convention

**Status:** accepted · **Date:** 2026-08-11 · **Gate:** G0

## Context

This project's whole claim is that its numbers were measured rather than
asserted. That claim rests on a reader being able to take any figure and walk
back to the capture file it came from and the build that produced it.

The usual way to arrange that is a convention: *every table caption must record
the build flavor, the upstream commit hashes, the SPDM version, and the full
command line.* Conventions of that shape survive about three weeks. The failure
is not laziness — it is that by week eight there are forty runs, the convention
was followed for thirty-two of them, and there is no way to tell which eight
are the gaps.

The failure mode also happens to be the expensive one. A missing number is
obvious. A number whose origin cannot be reconstructed looks exactly like a
number that was made up, and there is no way to argue otherwise after the fact.

## Decision

**A result cannot be produced without being attributed, because producing one
requires opening a run directory that stamps itself.**

Any script that records a result calls `prov_begin <name> <flavor>`, writes its
artifacts into `$PROV_RUN_DIR`, and calls `prov_finish`. Closing the run writes
`manifest.json` containing:

| Field | Why it is there |
|---|---|
| `upstream.libspdm`, `upstream.spdm_emu` | resolved commit hashes, not tag names |
| `upstream.libspdm_version` | the human-readable version the binary reports |
| `run.flavor` | which of the two builds, always |
| `commands[]` | the command lines as executed, quoted for re-execution |
| `artifacts[].sha256` | so the capture beside a table can be shown to be *that* capture |
| `run.repo_commit`, `run.repo_dirty` | whether the tree was clean when the run happened |
| compiler, OpenSSL, Python, kernel, arch, core count | the rest of the environment |

The implementation is `harness/lib/provenance.sh` with `harness/lib/_manifest.py`
doing the JSON. It is in Python rather than `jq` for two reasons: escaping JSON
from shell is a silent-corruption hazard, and `python3` is already a hard
dependency of this project while `jq` is not present in every container it has
to run in.

`run.repo_dirty` deserves a note. A result produced from a modified working
tree is not invalid, and pretending otherwise would just encourage people to
commit noise before every run. But the reader is entitled to know, so it is
recorded rather than prevented.

## Consequences

**Good**

- Provenance cannot be forgotten, because there is no unattributed path to a
  result.
- Re-running a past experiment is reading `commands[]`, not remembering.
- When upstream moves, the diff between two manifests states exactly what
  changed underneath a number.
- CI can assert on manifests directly (G6): the check that a tampered
  measurement is rejected reads a manifest, not a log file.

**Bad**

- Every experiment script carries three extra lines. Accepted.
- Run directories accumulate. Curated evidence is committed; scratch runs go
  under `bench/data/_scratch/` and are ignored.
- Hashing large captures costs time. Negligible at this project's scale, and
  revisit only if a single run exceeds a few hundred megabytes.

## Alternatives rejected

- **Write it in the caption by hand.** The convention this exists to replace.
- **Rely on git alone.** Git records the repository, not the upstream build the
  binaries came from, and not the command line that was actually typed.
- **Log everything and grep later.** Logs are unstructured, they get truncated,
  and they do not carry a hash of the artifact they describe.

## How to check this is working

Every directory under `bench/data/` has a `manifest.json`:

```bash
for d in bench/data/*/; do
    [ -f "$d/manifest.json" ] || echo "UNATTRIBUTED: $d"
done
```

Silence is the passing result. This check becomes a CI job in G6.

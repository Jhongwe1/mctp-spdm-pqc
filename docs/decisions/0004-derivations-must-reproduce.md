# ADR 0004 — A hash proves a file is unaltered, not that it is still true

**Status:** accepted · **Date:** 2026-08-28 · **Gate:** G1
· **Amends:** [ADR 0003](0003-provenance-manifests.md)

## Context

[ADR 0003](0003-provenance-manifests.md) made provenance a mechanism: no result
can be produced without a run directory that stamps itself, and `manifest.json`
carries a SHA-256 of every artifact. `harness/verify_repo.sh` re-computes those
digests on every run, so an artifact that is missing, untracked, or altered
fails the build.

On 2026-08-28 that mechanism reported complete success while the repository
held a committed, attested file whose contents were wrong.

`harness/capture.sh` writes a `*.fields.json` beside each capture — `fields.py`'s
reading of the decode — and `prov_finish` hashes it into the manifest alongside
the pcap. A bug fix that morning changed `message_bytes.total` for the
walkthrough capture from 15,803 to 11,291. The committed JSON still said 15,803.
Its digest still matched, because nobody had touched the file.

The two files sitting side by side in that directory are not the same kind of
thing:

| | what it is | what a matching digest tells you |
|---|---|---|
| `*.pcap`, `*.decode.txt`, `*.hex.txt` | **evidence** — what happened on the wire | everything. Evidence does not change its meaning |
| `*.fields.json` | **a derivation** — this project's tool reading that evidence, at one moment | only that nobody edited it |

**Integrity and currency are the same property for an input and different
properties for an output.** ADR 0003 secured the first and was read as securing
both.

The same shape appears once more in this repository, in a place with no
manifest at all. `harness/fields.py` names capability bits — `CERT_CAP`,
`CHUNK_CAP`, `LARGE_RESP_CAP` — from a table transcribed by hand out of
`libspdm/include/industry_standard/spdm.h`. If upstream renames a bit, that
table becomes wrong and stays perfectly self-consistent: no capture contradicts
it, `fields.py --check` passes, and nothing anywhere goes red. It is the same
failure with the copy taken from a header instead of from a capture.

## Decision

**Anything copied out of a source must be re-derivable from that source, and
the check has to be something a build runs rather than something a person
remembers.**

Three parts.

### 1. A committed derivation must reproduce from its inputs

`verify_repo.sh` re-runs `fields.py` on the decode beside every committed
`*.fields.json` and requires equality. `source.decode_file` is excluded from the
comparison: it records the absolute path the capture ran from, which is a
property of the machine and not of the result.

Scope is **the run directories a document actually cites**, discovered by
reading the `<!-- capture: -->` directives out of `docs/**/*.md`. Not a list —
a list is this same failure one level up. Runs that no document cites keep
exactly the guarantee ADR 0003 gives them, that they are unaltered, which is
all this repository has ever claimed about them.

### 2. A manifest is never rewritten. The repair for a stale derivation is a new run

There is no `prov_restamp`, and there must not be one. A manifest that can be
rewritten attests to nothing, and the moment such a helper exists it becomes
the cheap path taken under time pressure.

So the procedure when a tool changes under a committed derivation is: re-run,
commit the new run directory, re-point the documents at it, leave the old run
untouched. Written out step by step in `RUNBOOK.md` §8.5, including the
instruction **not** to re-point `LOG.md` — those entries are dated observations,
not current claims, and rewriting their pointers would make a diary lie.

### 3. A transcription is pinned to the source it was transcribed from

`fields.py --verify-tables <spdm.h>` parses every single-bit
`SPDM_GET_CAPABILITIES_{REQUEST,RESPONSE}_FLAGS_*` define and requires the two
sets to agree in both directions — a bit the header has and the table lacks
fails as loudly as the reverse. Composite aliases such as `MEAS_CAP`, which is
two bits under one name, are excluded by the power-of-two test that finds the
single bits rather than by a list of exceptions. One local name is accepted and
named in the source: requester bit `0x800`, `PSK_CAP_RESERVED`, which upstream
folds into the two-bit `PSK_CAP` mask and gives no `#define` of its own.

That comparison needs the upstream source and CI has none, so the result is
pinned. `third_party/spdm-h.pin` records the header's digest and the libspdm
commit it was read at, and `verify_repo.sh` fails when that commit is not the
one `third_party/spdm-emu-pqc.pin` says the captures came from, or when the
table has gained or lost an entry since.

**Moving a build pin without re-reading the header now turns the build red.**
That is `CLAUDE.md`'s "re-grep the old version number after changing a pin"
converted into something that does not depend on remembering.

## Consequences

**Good**

- The class of failure is closed rather than the instance. Any future field
  `fields.py` computes is covered whether or not a document quotes it, which is
  the specific gap that let a 40% error sit in `message_bytes.total` unnoticed.
- Refusing to re-stamp produced a result nobody designed. The repair required
  re-taking all five arms on the same pins eleven days later, and every arm
  reproduced to the byte — so `docs/handshake-walkthrough.md` can now say that
  every word of it was written against one capture and all 128 of its claims
  verify against a different one. The roadmap's rule that byte counts are
  reported as single values is no longer a convention this project asserts; it
  is a measured property of these captures.
- A constraint that makes the cheap repair impossible is sometimes the reason
  the expensive one produces something. Worth remembering as a design argument
  and not only as an outcome.

**Bad**

- Changing `fields.py` in a way that alters its output now costs a capture
  re-run, roughly four minutes plus a commit of about 20,000 lines of decode.
  Accepted: the cost is proportional to how often the analysis tool changes
  shape, which should be rarely and always deliberately.
- `bench/data/` grows a superseded run each time. Kept, because a superseded
  run is the evidence that the numbers reproduced.
- `--verify-tables` cannot run in CI. The pin narrows that to "the header was
  read at the right commit", which is weaker than reading it, and the weakness
  is stated in `docs/handshake-walkthrough.md` §10 rather than left implicit.

## Alternatives rejected

- **Add `prov_restamp` to `harness/lib/provenance.sh`.** The cheap fix, and the
  one that destroys the mechanism: an attestation that can be reissued after the
  fact is not an attestation. Rejected first and hardest.
- **Edit the stale JSON in place.** Same objection, minus the honesty of putting
  the helper in the repository where someone could argue with it.
- **Stop committing `*.fields.json` altogether.** Defensible — it is derivable
  from files that are committed — but it removes a machine-readable snapshot
  beside the evidence for no gain once reproduction is checked, and deleting is
  a worse default than verifying.
- **Keep a list of runs exempt from the reproduction check.** An exception list
  is the convention ADR 0003 exists to replace, wearing a different hat. Reading
  the documents' own `<!-- capture: -->` directives costs the same and cannot
  go stale.
- **Parse `spdm.h` at run time instead of transcribing it.** A header parser is
  a third thing to keep correct, and it would be the wrong one — the same
  argument `fields.py` already makes for not re-implementing `spdm_dump`.

## How to check this is working

```bash
bash harness/verify_repo.sh
#   N derivation(s) across M cited run(s) reproduce exactly
#   libspdm <hash>, spdm.h <digest>…, read <date>

# After moving any third_party/*.pin:
python3 harness/fields.py --verify-tables \
    ~/spdm-lab/work/spdm-emu-pqc/libspdm/include/industry_standard/spdm.h \
    --write-pin
```

Both steps are in the `verify` CI job, because that job shells out to
`verify_repo.sh` rather than restating its checks. The failing case was
exercised deliberately: with the pre-fix JSON in place the reproduction step
reports which keys differ and names the `capture.sh` invocation that repairs it.

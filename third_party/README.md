# third_party

Upstream source is **not vendored here.** What this directory holds is the set
of commit hashes every result in this repository was produced from.

```
spdm-emu-pqc.pin       flavor=pqc      the post-quantum build
spdm-emu-stable.pin    flavor=stable   the baseline build
spdm-dump.pin                          the decoder every result is read through
spdm-h.pin                             the header a hand-written table was copied from
```

The first three are a verbatim copy of the `BUILD_PIN.txt` that
`harness/build_spdm_emu.sh` wrote next to the build tree it describes.
`harness/lib/provenance.sh` folds the same fields into every experiment's
`manifest.json`, so a capture file and the build that produced it stay
connected without anyone having to remember to connect them.

## Reconstructing a build tree from a pin

```bash
bash harness/build_spdm_emu.sh pqc
diff <(grep -E '^(spdm-emu|libspdm)=' ~/spdm-lab/work/spdm-emu-pqc/BUILD_PIN.txt) \
     <(grep -E '^(spdm-emu|libspdm)=' third_party/spdm-emu-pqc.pin) \
  && echo "identical upstream"
```

A difference here is information, not a failure. It means upstream moved, and
the two hashes plus the date are exactly what a result produced before the move
needs beside it.

## Why the source is not committed

Three reasons, in order of how much they matter:

1. **It is not ours.** DMTF's projects carry their own licences and their own
   history. A copy pasted into this repository loses both.
2. **A copy cannot be verified.** A commit hash can be checked against the
   upstream repository by anyone. A directory of files cannot be checked
   against anything.
3. **It is enormous.** `libspdm` vendors OpenSSL, which vendors its own test
   corpora. A full source tree is around 2.5 GB per flavor, and the build
   output several times that.

## Contents

| File | What it pins |
|---|---|
| `spdm-emu-pqc.pin` | `spdm-emu` and `libspdm` at the post-quantum release candidate, plus compiler, cmake, kernel and build date |
| `spdm-emu-stable.pin` | the same fields for the baseline release pair |
| `spdm-dump.pin` | the offline decoder, and the certificate-chain ceiling measured out of the compiled binary |
| `spdm-h.pin` | the SHA-256 of the header whose capability-bit names `harness/fields.py` copied, and the libspdm commit it was read at |
| `dsp0274.pin` | the SHA-256 of the DSP0274 1.4.0 PDF that this repository's specification citations were read from, and which sections were read |
| `spdm15-wip.pin` | the same, for DMTF's SPDM 1.5 hybrid-PQC public-review draft |

The pins record the resolved **commit hashes**, not just tag names. A tag can be
moved; a hash cannot.

## Why a specification is pinned, and not only cited

A citation of the form "DSP0274 §425 says X" names a *title*. Titles are
revised. The version number helps and is not enough — a working draft, a
published revision and an errata update can all be "1.4.0" to a reader who
found the PDF by searching for it.

So the two specification pins here carry the SHA-256 of the exact file that was
read, and the list of sections that were read out of it. A claim attributed to
a specification in this repository therefore names a *document*, not a title,
and anyone can fetch the same URL and check they are holding the same bytes.

Neither PDF is committed. They are not this project's to redistribute, and
`.gitignore` keeps the working copies out; they live beside the build trees
under `LAB_DIR/spec/`. What is committed is the digest and the reading list.

`sections-read=` matters as much as the digest, and for the opposite reason.
It is the honest boundary of what was read: DSP0274 is 306 pages and this
project has read five tables and four numbered clauses of it. Recording which
ones stops "the specification says" from expanding quietly into territory
nobody opened.

`quoted-in=` is what makes the pin load-bearing rather than decorative.
`harness/verify_repo.sh` requires every file it names to contain the pinned
digest, so re-downloading a specification and updating its pin without
updating the documents that cite it turns the build red. That is
`CLAUDE.md`'s instruction to grep for the old version number after moving a
pin, with the remembering taken out of it — and 2026-08-16 is the day that
instruction was needed and not followed.

## Why a header is pinned, and not only a build

`harness/fields.py` turns a `Flags` word into names — `CERT_CAP`, `CHUNK_CAP`,
`LARGE_RESP_CAP` — from a table transcribed by hand out of
`libspdm/include/industry_standard/spdm.h`. That table is the one thing in this
repository that **nothing in a capture can contradict.** A byte count that
drifts from its capture fails `fields.py --check`; a bit that upstream renamed
produces a name that is wrong and entirely self-consistent, in a capture that
agrees with it, forever.

So the table is compared against the header directly:

```bash
python3 harness/fields.py --verify-tables \
    ~/spdm-lab/work/spdm-emu-pqc/libspdm/include/industry_standard/spdm.h
```

It parses every single-bit `SPDM_GET_CAPABILITIES_{REQUEST,RESPONSE}_FLAGS_*`
define and requires the two sets to agree in both directions — a bit the header
has and the table lacks is as much a failure as the reverse. Composite aliases
such as `MEAS_CAP`, which is two bits under one name, are excluded by the same
rule that finds the single bits, rather than by a list of exceptions.

One difference is accepted, and named in the source rather than waved through:
requester bit `0x00000800` is called `PSK_CAP_RESERVED` here and has no
individual `#define` upstream, because libspdm folds it into the two-bit
`PSK_CAP` mask. Dropping it would make every requester capability word report an
unrecognised bit.

Running that needs the upstream source, and CI has none. `spdm-h.pin` is how the
result reaches CI: it records the header's digest and the libspdm commit the
comparison was made at, and `harness/verify_repo.sh` fails when that commit is
not the one `spdm-emu-pqc.pin` says the captures came from, or when the table
has gained or lost an entry since. **Moving the emulator pin without re-reading
the header turns the build red**, which is the rule
[CLAUDE.md](../CLAUDE.md) states as "re-grep the old version number after
changing a pin", made into something that does not depend on remembering.

This is the same decision as the one governing derived artifacts under
`bench/data/` — a copy taken out of a source has to be re-derivable from that
source, whether the source is a capture or a header. Both are
[`docs/decisions/0004`](../docs/decisions/0004-derivations-must-reproduce.md).

At libspdm 4.0.0-rc the comparison found 19 requester and 32 responder
single-bit capabilities, and every name matched.

## Why the decoder is pinned too, and why that was missed at first

Only the two emulator builds were pinned to begin with, because they are what
produces a capture. But nothing in this repository reads a capture directly.
Every statement about what was *negotiated* — which is the discipline the whole
project rests on — is read out of `spdm_dump`'s decode of that capture. A
decoder whose version is not recorded makes those numbers half-attributed: the
bytes have provenance and the reading of them does not.

`spdm-dump.pin` carries one field the others do not, and it is the reason this
matters in practice:

```
max-cert-chain-size=0x1000
```

That is **measured**, not transcribed. `spdm_dump` checks the size of a
`--rsp_cert_chain` file against `LIBSPDM_MAX_CERT_CHAIN_SIZE` before parsing it,
so bisecting on file size reads the constant out of the compiled binary without
patching or rebuilding it. In libspdm 4.0.0-rc that macro takes one of three
values, and which one says how the build was configured:

| value | meaning |
|---|---|
| `0x1000` = 4,096 | no post-quantum signature support compiled in |
| `0x8000` = 32,768 | ML-DSA support |
| `0x28000` = 163,840 | SLH-DSA support |

This decoder measures 4,096, while the ML-DSA certificate chain it has to read
is 16,853 bytes — so the decode of a post-quantum capture stops partway through.
`spdm-emu-pqc` is built from **the same libspdm commit** and handles that chain
without complaint. The difference is build configuration, not version, and the
configuration that would fit is named in the table above. Recording the number
turns "the decoder cannot read this" into a statement with a next step.

# ADR 0001 — Maintain two pinned build flavors, pinned by spdm-emu tag

**Status:** accepted, revised the same day · **Date:** 2026-08-11 · **Gate:** G0

## Context

Post-quantum algorithm support (ML-DSA, ML-KEM, SLH-DSA) reached the `libspdm`
main line on 2026-08-04, in the `4.0.0-rc` tag. As of the date above, `4.0.0` is
a release candidate. The most recent stable release is `3.8.2` (2026-04-03).

The project needs post-quantum measurements, which only the release candidate
can produce, and it needs a baseline that will not have to be re-explained if
the release candidate changes before it ships.

Additionally, PQC in libspdm exists only behind the OpenSSL crypto backend. The
mbedTLS backend compiles cleanly and simply does not implement those
algorithms — a failure that only becomes visible at the point of use.

## Decision

Maintain two independent build trees. **Pin the `spdm-emu` tag; let `libspdm`
follow that tag's submodule pointer.** Require every published result to state
which flavor produced it.

| Flavor | spdm-emu | libspdm | Crypto | Used for |
|---|---|---|---|---|
| `stable` | tag `3.8.0` | 3.8.0 | OpenSSL | every baseline measurement |
| `pqc` | `5f01d2f` (post-`4.0.0-rc`) | 4.0.0-rc | OpenSSL | post-quantum experiments only |

`-DCRYPTO=openssl` is not configurable. The build script hard-codes it and the
health check verifies `--pqc_asym` is present in the resulting binary.

Both trees record their resolved commit hashes in `BUILD_PIN.txt`, which
`harness/lib/provenance.sh` copies into every run's `manifest.json`. **Hashes,
not tag names** — a tag can be moved, a hash cannot.

## Why the pin is on spdm-emu rather than on libspdm

This is the revision, and the reasoning is worth keeping because the obvious
approach is the wrong one.

The first version of this decision pinned **libspdm** to a tag (`3.8.2` for
stable) underneath whatever `spdm-emu` was current. It was written with this
risk stated explicitly:

> `spdm-emu` tracks libspdm's main line, so checking out an older libspdm tag
> underneath a current `spdm-emu` may eventually fail to compile. If that
> happens the fix is to pin `spdm-emu` to a contemporaneous commit as well, and
> the failure is loud (a compile error), not silent.

That risk materialised within the hour:

```
library/pci_doe_requester_lib/pci_doe_spdm_vendor_send_receive.c:63:9:
error: passing argument 11 of 'libspdm_vendor_send_request_receive_response'
       from incompatible pointer type [-Werror=incompatible-pointer-types]
```

`libspdm` changed that function's signature between 3.8.x and 4.0.0-rc, and
current `spdm-emu` calls the new form. Checking the submodule pointer history
showed why no amount of choosing a better `spdm-emu` commit fixes it cleanly:
**no `spdm-emu` commit has ever pointed at libspdm 3.8.2.** The pointer moves
in steps, and 3.8.1 and 3.8.2 fell between two of them.

The tags, on the other hand, correspond exactly:

| spdm-emu tag | libspdm | date |
|---|---|---|
| `3.7.0` | 3.7.0 | 2025-04-03 |
| `3.8.0` | 3.8.0 | 2025-07-10 |
| `4.0.0-rc` | 4.0.0-rc | 2026-08-04 |

Upstream releases and tests the pair together. Pinning the pair is therefore
both more likely to build and a more honest description of what was run.

## Consequences

**Good**

- A release candidate never becomes the baseline. If `4.0.0` changes before
  release, baseline numbers are unaffected and PQC numbers are re-runnable
  against the new tag with one command.
- Every table caption can name a commit hash rather than "latest".
- The mbedTLS trap is closed by construction rather than by remembering.
- The pair being one upstream tests together removes an entire class of
  build failure from anyone reproducing this.

**Bad**

- Roughly twice the disk (~20 GB) and, naively, twice the download. Mitigated
  by `--seed-from`, which copies the first source tree instead of paying the
  download again.
- Every experiment script must know which flavor it ran under. This is why
  `prov_begin` takes the flavor as a required argument rather than inferring it.

**Accepted, and stated wherever it matters**

**The baseline is libspdm 3.8.0, not 3.8.2.** 3.8.1 and 3.8.2 carry fixes for
two 2026 advisories, and the baseline does not have them.

This is acceptable for what the baseline is used for — byte counts and round
trip counts in a protocol flow, which bounds-check fixes do not change — and it
is unacceptable to leave implicit. If a result ever turns on behaviour that
changed between 3.8.0 and 3.8.2, that result must be re-run against a build
that has it, and getting there means pinning `spdm-emu` to an untagged commit
and confirming the pair compiles. Not attempted in G0; recorded as open.

## Alternatives rejected

- **Single build on `4.0.0-rc`.** Simpler, and wrong: it makes every baseline
  number contingent on a release candidate, and offers no way to separate
  "this changed because of PQC" from "this changed because of the RC".
- **Single build on a stable release.** No PQC at all. The post-quantum half
  becomes arithmetic over published specification values — a legitimate
  fallback, not a first choice while a real measurement is available.
- **Pin libspdm, take current spdm-emu.** Tried; does not compile. See above.
- **Trust the submodule pointer of whatever was cloned today.** Reproducible
  only until upstream moves it, which it did on 2026-08-04.

## How to verify this decision is still being honoured

```bash
grep -h -E '^(flavor|spdm-emu-ref|libspdm-version)=' \
    ~/spdm-lab/work/spdm-emu-*/BUILD_PIN.txt
```

Two flavors, two different `libspdm-version` lines. If they match, one of the
builds is not what it claims to be.

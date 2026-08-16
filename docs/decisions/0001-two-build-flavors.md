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

**The baseline is libspdm 3.8.0, not 3.8.2.** An earlier version of this record
said 3.8.1 and 3.8.2 carry fixes for two 2026 advisories. That was written from
memory and it is wrong. Audited on 2026-08-17 against upstream history, in a
clean blobless clone, with every tag resolved by SHA:

| range | released | commits | security content |
|---|---|---:|---|
| 3.8.0 → 3.8.1 | 2025-09-03 | 4 | **none** — two build breaks, a disabled-capability build fix, one unaligned-access fix |
| 3.8.1 → 3.8.2 | 2026-04-03 | 10 | **one** — `Fix security vulnerability in GET_CSR parsing code`, 2026-02-10 |

No commit message in either range names a CVE or a GHSA identifier. And 3.8.1
was released in 2025, so it cannot carry a fix for a 2026 advisory — which is
what should have made the original sentence suspect before any clone was made.

Three things follow. The second is the one that changes the conclusion.

1. 3.8.1 and 3.8.2 sit on a `release-3.8` maintenance branch that `spdm-emu`
   never followed. Its submodule pointer moved on 2026-03-10 and next on
   2026-05-11; 3.8.2 was tagged on 2026-04-03, inside that gap. **3.8.2 was
   never a configuration this project could have had**, regardless of the
   pinning rule.
2. **The GET_CSR fix is in 4.0.0-rc.** `704bc991` on `release-3.8` is a
   backport of main-line `713e32c0`, same day; `git cherry -v 4.0.0-rc 3.8.2`
   marks it `-`, meaning patch-equivalent content is already upstream. So the
   `pqc` flavor has the fix and only the `stable` baseline is without it.
3. The baseline also predates main-line fixes made after 3.8.0 — among them an
   out-of-bounds read in `libspdm_process_general_opaque_data_check`
   (`6485badd`, 2026-06-26) and an unaligned read of a vendor-defined response
   payload length (`070b4a3b`, 2026-07-20).

None of it is reached by what is measured here. These flows run as
`--exe_conn DIGEST,CERT,CHAL,MEAS --exe_session NO_END`, which excludes
`GET_CSR` entirely. That is a reason the baseline is usable, not a reason the
gap does not exist. If a result ever turns on post-3.8.0 behaviour it must be
re-run against a build that has it, and getting there means pinning `spdm-emu`
to an untagged commit and confirming the pair compiles. Not attempted in G0;
recorded as open.

Checked at the same time, because it is the assumption this whole record rests
on: **4.0.0 has not been released.** `4.0.0-rc` (2026-08-04) is still the
newest tag, although `main` has moved on to 2026-08-13. Re-check before
repeating either claim.

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

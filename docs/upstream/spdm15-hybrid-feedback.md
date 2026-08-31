# SPDM 1.5 hybrid PQC — industry feedback, draft

**Target:** DMTF Feedback Portal, <https://www.dmtf.org/standards/feedback>
**Deadline:** 2026-08-31, stated on page 8 of the WIP itself
**Document under review:** *Plan of Hybrid Support for Traditional Crypto and
Post Quantum Crypto (PQC) in SPDM 1.5*, June 2026, 8 pages
(`sha256 3e5366a386b9b340cb389ac1c8126ba96079f2df8391de68efd19eba02f39a25`)

**Status:** drafted 2026-08-31. Submission is the author's to make — it needs a
portal account and it has to be in his own words. This file is the draft and the
reasoning behind it; whether and when it was sent is recorded in
[`README.md`](README.md).

---

## What the WIP actually asks for

Not a general invitation. Page 8 asks two specific questions:

1. *"What are your thoughts on the hybrid approaches in SPDM 1.5?"*
2. *"Does your company or organization require algorithm combinations besides
   the highlighted ones …?"*

Question 2 is not answerable here — this is a graduate project with no
procurement requirement, and inventing one would be the worst possible thing to
put in front of a working group. So the feedback answers question 1, narrowly,
about the one thing this project has measured.

## The angle, and why this one

Three angles were considered. The chosen one is the only one backed by a number
from this repository rather than by an opinion:

| angle | why not |
|---|---|
| `--pqc_first` is "either/or" and hybrid needs "both" | true, but it is an observation about `spdm-emu`'s CLI, not about the standard. It reads as a bug report filed at the wrong project |
| hybrid signatures against `CHUNK_CAP` thresholds | close to the chosen one, but the threshold is a consequence, not the question |
| **the certificate chain: concatenation against slots** | **chosen.** It is a tension *inside the WIP's own text*, it is about cost rather than function, and this project has measured both sides of it |

The tension, in the WIP's words:

- **Guidelines for Changes to Support Hybrid:** message fields that today carry
  a certificate chain *"will contain the concatenation of two pieces of data for
  the two algorithms, respectively."*
- **Requirements, item 2:** *"SPDM 1.4 devices with a Traditional certificate
  chain and a PQC certificate chain are upgradeable to SPDM 1.5 with hybrid
  support."*

A 1.4 device that has both today has them in **two slots**, each fetched and
cached independently through `GET_DIGESTS`. Concatenation puts them in one. The
two arrangements are not equivalent on a constrained transport, and the
difference is exactly what this project measures.

## The draft — 297 words

> I'm a graduate student implementing the requester side against libspdm and
> spdm-emu 4.0.0-rc. This is an implementer's question rather than a position;
> I have no organizational requirement to submit.
>
> Measured on one binary, varying only the negotiated algorithm — spdm-emu
> 4.0.0-rc, libspdm `8a92317`, MCTP transport, negotiated `DataTransferSize`
> 4,608 bytes:
>
> | responder certificate chain | bytes on the wire | `CHUNK_GET` round trips |
> |---|--:|--:|
> | ECDSA-P384 | 1,655 | 0 |
> | ML-DSA-65 | 16,853 | 4 |
>
> The ML-DSA chain exceeds `DataTransferSize`, so `GET_CERTIFICATE` is answered
> with `ERROR(LargeResponse)` and the exchange falls into chunking. The
> classical path never executes that code.
>
> Two statements in the WIP read differently to me for the certificate-chain
> field specifically. "Guidelines for Changes to Support Hybrid" says such
> fields will carry the concatenation of the data for both algorithms.
> Requirement 2 says a 1.4 device that already has a Traditional chain and a PQC
> chain is upgradeable to 1.5 hybrid. A device that has both today has them in
> two slots, each fetched and cached independently via `GET_DIGESTS`;
> concatenating them makes the fetch a single object of roughly the sum of the
> two, about 18.5 kB on the figures above.
>
> Two questions:
>
> 1. Is a hybrid certificate chain expected to occupy one slot as a
>    concatenation, or may a hybrid endpoint keep the Traditional chain in one
>    slot and the PQC chain in another?
> 2. If concatenation is intended, does hybrid make `CHUNK_CAP` effectively
>    mandatory for endpoints on transports whose `DataTransferSize` is smaller
>    again — MCTP over SMBus or I²C?
>
> I ask rather than assume because the two arrangements have different caching
> behaviour under `GET_DIGESTS`, and on a constrained transport that difference
> is the dominant cost of an attestation.

## Every number in it, and where it comes from

| number | source | checked by |
|---|---|---|
| 1,655 bytes | `bench/data/w3-baseline-20260831T143123Z/walkthrough` | `certificate.responder_slot0_bytes` |
| 16,853 bytes | same run, `pqc` arm | `certificate.responder_slot0_bytes` |
| 4 round trips | same run, `pqc` arm | `chunking.chunk_get_count` |
| 4,608 bytes | same run | `capabilities.requester.data_transfer_size` |
| `libspdm 8a92317` | `third_party/spdm-emu-pqc.pin` | `BUILD_PIN.txt` in the run directory |
| "about 18.5 kB" | 1,655 + 16,853, **stated as approximate** | arithmetic, and labelled as such |

The last row matters. Whether a hybrid chain repeats the 4-byte `Length` and the
`RootHash` once or twice is not stated in the WIP and is not knowable from here,
so the figure is given as a rough sum and not as a computed total. **A number
computed from a specification rather than observed is labelled as computed** —
`docs/roadmap.md` standing rule 4, and the one place in this feedback where the
rule applies.

## What this is worth as evidence

**Less than a GitHub pull request, and it is filed here as such.** DMTF portal
submissions do not necessarily produce a public URL, there is no review thread,
and nothing external will ever confirm it was read. It is **evidence of timing,
not of contribution**: it shows that the implementation work and the standards
work were happening in the same weeks, which is a thing a senior engineer does
and a student usually does not.

The contribution evidence for G7 is still the two candidates in
[`README.md`](README.md), and neither is affected by this.

# SPDM Device Attestation Lab

A measurable, reproducible SPDM device-attestation pipeline built on DMTF's
reference implementations (`libspdm`, `spdm-emu`): a full requester/responder
handshake, three-point tamper detection, RATS reference-value comparison, and a
byte-level cost comparison of post-quantum algorithms against classical ones.

> ### ⚠️ Scope
>
> **This project performs protocol-level correctness validation.**
> **It is not a security assessment.**
>
> It answers questions of the form "does this flow behave as specified, and what
> does it cost in bytes and round trips". It does not answer "is this system
> secure". No threat model is claimed beyond the one written down in
> [`docs/threat-scope.md`](docs/threat-scope.md), no cryptographic review was
> performed, and the tamper cases exercised here are ones the author
> constructed, not ones an adversary chose.
>
> This statement is deliberately placed above the build badge. What a project
> declines to claim is a more reliable signal than what it claims.

![CI](https://github.com/Jhongwe1/mctp-spdm-pqc/actions/workflows/ci.yml/badge.svg)

---

## Current status

This is week 1 of a 14-week programme. The table below is the truth about what
exists today, not what is planned. Planned work is in
[`docs/roadmap.md`](docs/roadmap.md).

| Gate | Subject | State |
|:--|---|---|
| G0 | environment and version baseline | **complete** — see [`docs/env-baseline.md`](docs/env-baseline.md) |
| G1 | full handshake, field by field | not started |
| G2 | certificate chain, three tamper points | not started |
| G3 | RATS verification pipeline | not started |
| G4 | post-quantum cost quantification | not started |
| G5 | real transports (QEMU / AF_MCTP) | not started |
| G6 | conformance and negative testing | not started |
| G7 | upstream contribution | agreements and account done; target built, five blockers documented |
| G8 | delivery and write-up | not started |

Nothing in this repository reports a measurement that has not been made. A
table that does not exist yet is absent rather than sketched.

### What week 1 established

Two things came out of the environment work that were not the point of it.

**A post-quantum certificate chain is ten times the size of a classical one,
and that changes the message flow rather than only the byte count.**

| | classical | post-quantum |
|---|---|---|
| negotiated signature algorithm | ECDSA-P384 | **ML-DSA-65** |
| negotiated key encapsulation | none | **ML-KEM-768** |
| certificate chain | 1,655 bytes | **16,853 bytes** |
| chunk round trips to fetch it | **0** | **4** |

The chain exceeds the negotiated `DataTransferSize` (4,608 bytes), so
`GET_CERTIFICATE` is answered with `SPDM_ERROR(LargeResponse)` and the exchange
falls into SPDM's chunking mechanism. **The classical path never executes that
code.** On a real BMC speaking MCTP over I²C, where the transfer unit is
smaller again, that is the part that would be felt.

Both rows come from one decoded protocol field read out of both captures, with
the algorithm confirmed from the `ALGORITHMS` response rather than from what
was requested. `harness/healthcheck.sh` re-derives them on every run.

**The reference decoder cannot read the reference emulator's post-quantum
output.** `spdm_dump`, built from the same `libspdm` commit as the emulator,
stops partway through with `cert_chain is too larger — increase
LIBSPDM_MAX_CERT_CHAIN_SIZE and rebuild`. The handshake is fine; the decoder's
compile-time constant is not. Anything that reports a short decode as a short
handshake will be wrong, so the health check labels that case explicitly.

Neither of these is Gate 4. They are single observations from a single build,
recorded because they were seen, and they are what Gate 4 will have to
measure properly.

## Getting started

Read [**RUNBOOK.md**](RUNBOOK.md). It goes from a clean machine to a completed
SPDM handshake with a capture file, and it states what correct output looks
like at every step so that a failure is recognisable as a failure.

The short version, on Ubuntu 24.04 or WSL2:

```bash
git clone https://github.com/Jhongwe1/mctp-spdm-pqc.git
cd mctp-spdm-pqc

bash harness/doctor.sh                     # prerequisites; changes nothing
bash harness/build_spdm_emu.sh pqc         # ~30 min, mostly downloading
bash harness/healthcheck.sh pqc --write-baseline
```

## How results are recorded

Every experiment writes into `bench/data/<run-id>/`, and every run directory
contains a `manifest.json` holding:

- the exact `libspdm` and `spdm-emu` commit hashes the binaries were built from
- the complete command lines that were executed, as executed
- compiler, OpenSSL, Python and kernel versions
- SHA-256 and byte count of every artifact in the directory
- whether the working tree was clean when the run happened

This is a mechanism rather than a convention. Any script that records a result
calls `prov_begin` and `prov_finish`
([`harness/lib/provenance.sh`](harness/lib/provenance.sh)), so a result cannot
be produced without being attributed. The reason is narrow and practical: a
number in a table is worth exactly as much as the reader's ability to find the
capture file it came from and check it.

## Repository layout

```
harness/       build, health-check and analysis scripts
  lib/         shared shell helpers; provenance stamping
docs/          baseline, design notes, decision records, roadmap
  decisions/   architecture decision records — why, not what
  upstream/    upstream contribution tracking
bench/data/    experiment runs, one directory each, each with manifest.json
c-drills/      eight C exercises drawn from problems this project hits
third_party/   upstream commit pins only; no vendored source
certs/         certificate chain material                        (from W03)
device/        device secret / measurement modifications         (from W04)
rats/          reference values and verification policy          (from W06)
transport/     real-transport glue                               (from W09)
negative/      negative and conformance tests                    (from W10)
figures/       generated figures
```

Upstream source is not vendored. `third_party/*.pin` records the exact commits
every result was produced from; `harness/build_spdm_emu.sh` reconstructs the
build trees from those pins on any machine.

## Two build flavors

Two independent builds are maintained, and every result states which one
produced it.

| Flavor | libspdm | Used for |
|---|---|---|
| `stable` | 3.8.2 | every baseline measurement |
| `pqc` | 4.0.0-rc | post-quantum experiments only |

Post-quantum support reached the libspdm main line on 2026-08-04 in a release
candidate. A release candidate is not a baseline, so it is not used as one. The
reasoning is recorded in
[`docs/decisions/0001-two-build-flavors.md`](docs/decisions/0001-two-build-flavors.md).

## What this project does not do

- It does not evaluate the security of SPDM, of `libspdm`, or of any product.
- It does not measure on real hardware. Everything is emulator-based unless a
  result explicitly says otherwise.
- It does not implement SPDM. It uses DMTF's reference implementation and
  studies its behaviour.
- It does not extrapolate. Any figure that is computed from a specification
  rather than observed is labelled as computed, next to the figure itself and
  not only in a footnote.

## Licence and upstream

Original work here is under the licence in [LICENSE](LICENSE). `libspdm`,
`spdm-emu` and `spdm-dump` are DMTF projects under their own licences and are
referenced by commit hash, not copied.

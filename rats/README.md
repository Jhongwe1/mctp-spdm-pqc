# rats

The part SPDM does not standardise: reference values, the policy that compares
evidence against them, and the verdicts that come out.

```bash
python3 rats/appraise.py appraise bench/data/w5-tamper-20260910T092621Z/t0_clean.decode.txt
python3 rats/appraise.py appraise bench/data/w5-tamper-20260910T092621Z/t1_meas.decode.txt ; echo $?
python3 rats/appraise.py matrix --check      # all ten arms, against what they must produce
python3 rats/appraise.py selftest            # eleven broken pairs, each refused for its own reason
python3 rats/cose.py selftest                # the encoders, against RFC 8949's own vectors

bash rats/mint_reference.sh                  # the publisher's side
bash rats/interop.sh                         # compare against DMTF's tools (needs spdm-emu)
```

## The question this answers

`GET_MEASUREMENTS` returns digests, signed by the device. Verifying that
signature proves the values came from that device and were not altered in
transit. It proves **nothing about whether the values are correct**, and this
repository has the measurement: `docs/tamper.md` row 1 changed one byte of a
measurement **on the device**, before the responder hashed and signed it. The
handshake completed. Every signature verified. The requester exited 0 and
printed nothing.

A device that has been compromised still signs honestly. It signs the
compromised value.

The missing half is IETF RATS, RFC 9334, and it is three things SPDM does not
carry — what the value should be, who is entitled to say so, and what to do
when they differ. `docs/rats-pipeline.md` is the walkthrough;
`docs/rats-roles.md` is the five roles and which of them this project plays.

## What is here

| file | what it is |
|---|---|
| [`appraise.py`](appraise.py) | the Verifier. Capture → evidence → policy → verdict, with the exit code attached |
| [`cose.py`](cose.py) | CBOR and COSE_Sign1 in the subset a CoRIM needs, no packages; signing and verifying are `openssl` |
| [`policy.rego`](policy.rego) | the appraisal policy, Rego v1, and a long comment on what DMTF's sample does not check |
| [`rats_selftest.py`](rats_selftest.py) | eleven broken pairs, each refused, each for a **different** named reason |
| [`mint_reference.sh`](mint_reference.sh) | the Reference Value Provider's side: capture → CoMID → CBOR → COSE_Sign1 |
| [`interop.sh`](interop.sh) | this implementation against DMTF's, byte for byte where that is meaningful |
| [`ref/`](ref) | the signed reference values, and the same document in readable form |
| [`out/`](out) | one verdict per arm, re-derived by CI — and [`expected.json`](out/expected.json), which says what each one must be and why |
| [`interop/`](interop) | what DMTF's tools produced, committed so CI can check this project still matches without a `spdm-emu` checkout |
| `keys/ref-signer.pub` | the public half. The private half is not here — see below |

> **Why this exists rather than a call to DMTF's tools**, what it costs, and
> what would retire it:
> [`docs/decisions/0007`](../docs/decisions/0007-a-second-implementation-made-to-agree.md).
> The policy engine's version is pinned like the decoder's, and the field that
> matters is the Rego language version rather than the release:
> [`third_party/opa.pin`](../third_party/opa.pin).

## Three things worth knowing before reading the code

**The evidence comes off the wire, not out of `device/measurements.bin`.** That
file is the fixture the responder *read*; the evidence is the 528-byte
measurement record it *sent*, sliced out of the `MEASUREMENTS` message by
`harness/fields.py --emit-record`. Feeding the fixture instead would compare a
document against itself: the reference value and the evidence would both be
derived from the same file, so a tampered fixture would appraise as good. It
would also delete the conveyance that is the entire subject of RATS.

**The hash algorithm is read from the capture, not passed as a flag.** It comes
from `MeasHash` in the `ALGORITHMS` response — what the responder selected.
`docs/roadmap.md` standing rule 8, and 2026-08-17 in `LOG.md` is what assuming
it cost the first time.

**Six of the eight measurement blocks can be appraised. The other two cannot be
represented at all.** `MEASUREMENT_MANIFEST` (0xfd) and `DEVICE_MODE` (0xfe)
are raw bit streams that are not secure version numbers, and DMTF's evidence
format has no encoding for them; `SpdmMeasurement.py` walks past both without
comment. This project reproduces that behaviour for interoperability and
**counts what it dropped**, so every verdict carries a coverage line. The
`DEVICE_MODE` block is the one worth minding: it is where a device says whether
it is in a debug mode.

## The private key is not in this repository

`rats/keys/ref-signer.key` is excluded by `.gitignore`, and
`harness/verify_repo.sh` reads every tracked file looking for a PEM
private-key header rather than trusting the pattern to have worked.

The consequence is the same one `certs/` has and it is worth saying rather than
discovering: **a fresh clone can verify these reference values and cannot
re-mint them.** Verifying is what a Verifier does and what CI does. Minting is
the firmware vendor's job, and in this project it is the author's, which is
itself the limitation stated in `docs/rats-pipeline.md` — a reference value
taken from a capture of the device it will appraise cannot catch a device that
was already wrong when the capture was taken.

## The assertion this directory exists to support

Stated as a negative, because that is the form that can fail usefully:

> A **tampered** measurement must be **rejected**, and CI must turn red if it
> stops being.

That is the `rats` job in [`.github/workflows/ci.yml`](../.github/workflows/ci.yml),
and [`out/expected.json`](out/expected.json) is what it checks against — not a
snapshot of a previous run, but a per-arm statement of the outcome required and
the sentence that makes it required. A policy that passed everything would
reproduce a snapshot perfectly.

# third_party

Upstream source is **not vendored here.** What this directory holds is the set
of commit hashes every result in this repository was produced from.

```
spdm-emu-pqc.pin       flavor=pqc      the post-quantum build
spdm-emu-stable.pin    flavor=stable   the baseline build
spdm-dump.pin                          the decoder every result is read through
```

Each `.pin` is a verbatim copy of the `BUILD_PIN.txt` that
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

The pins record the resolved **commit hashes**, not just tag names. A tag can be
moved; a hash cannot.

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

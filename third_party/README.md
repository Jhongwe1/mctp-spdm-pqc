# third_party

Upstream source is **not vendored here.** What this directory holds is the set
of commit hashes every result in this repository was produced from.

```
spdm-emu-pqc.pin       flavor=pqc      the post-quantum build
spdm-emu-stable.pin    flavor=stable   the baseline build
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

The pins record the resolved **commit hashes**, not just tag names. A tag can be
moved; a hash cannot.

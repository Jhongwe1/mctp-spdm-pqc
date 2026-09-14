# 0009 — A third build flavor for one compile-time constant, not a rebuild of the second

**Status:** accepted, 2026-09-14 · **Gate:** G4
**Amends [0001](0001-two-build-flavors.md), which says two flavors, and
[0006](0006-patching-the-pinned-tree.md), which says a patch is an overlay on a
flavor rather than part of one.**

## The problem

`DataTransferSize` is the single most consequential transport parameter for
post-quantum SPDM. It decides whether a certificate chain arrives in one
`CERTIFICATE` response or through SPDM's chunking layer, and chunking costs a
complete request/response round trip per chunk. A 32× change in it moves this
project's post-quantum handshake from 0 to 59 round trips while moving its byte
total by 3% — measured, `docs/pqc-cost.md` §9.

`spdm-emu` has no flag for it. It is

```
LIBSPDM_DATA_TRANSFER_SIZE = LIBSPDM_RECEIVER_BUFFER_SIZE - (header + tail)
```

in `spdm_emu/spdm_emu_common/spdm_emu.h`, and libspdm derives the advertised
value from the buffer sizes handed to `libspdm_register_device_buffer_func`.

So measuring across it needs either one build per value, or a build whose value
can move at run time. And week 7's `docs/pqc-cost.md` had already published a
sentence about what a large `DataTransferSize` does — reasoned from the constant,
never run — which under standing rule 1 is a debt rather than a finding. (That
document was restructured on 2026-09-14 and its section numbers moved; the
sentence is now answered in §9.)

## What was decided

**A third flavor, `pqc-dts`: the same upstream pair as `pqc`, built with larger
buffers, carrying `transport/data-transfer-size.patch`, which adds a
`--data_transfer_size` flag that lowers the advertised value at run time.**

Four parts, and the fourth is the one that matters.

### 1. A flavor, not a rebuild of `pqc`

`pqc` is the build every number this project has published came from. Rebuilding
it with different buffers would change the advertised `DataTransferSize` in every
*future* capture taken from it, which silently breaks the promise a reader is
given: clone, rebuild from `third_party/spdm-emu-pqc.pin`, get the same numbers.
`pqc` is therefore not touched. `harness/lib/common.sh` gains a third case in
`flavor_emu_ref()`, which remains the single source of truth about versions.

### 2. A flavor patch is part of what a flavor is, and that is a different thing from ADR 0006's patch

ADR 0006's `device/meas-from-file.patch` is an **overlay**: any flavor may or may
not carry it, it is reversible on a live tree, and `harness/apply_device_patch.sh`
exists to put it on and take it off.

`transport/data-transfer-size.patch` is not like that. A tree without it is not
`pqc-dts`; it is `pqc` with odd buffer sizes. So it is applied by
`harness/build_spdm_emu.sh` as a build step, `flavor_patch()` names it beside
`flavor_cflags()`, and `BUILD_PIN.txt` records both the flag string and the
patch's SHA-256. `harness/run_pair.sh --set dts` refuses to run on a flavor whose
`flavor_patch()` is empty, because on such a build `--data_transfer_size` is an
unknown argument and `spdm-emu` answers an unknown argument with
`print_usage(); exit(0)` — a process that exits *successfully* without speaking
SPDM.

### 3. The patch registers a smaller buffer rather than setting the field

The obvious implementation is `libspdm_set_data(...,
LIBSPDM_DATA_CAPABILITY_DATA_TRANSFER_SIZE, ...)` after the buffers are
registered. That was the first implementation and **it does not work**: libspdm
returns `LIBSPDM_STATUS_INVALID_STATE_LOCAL` (0x80010002) for that field at that
point, and the patch silently did nothing.

So the patch changes the argument instead — the documented route, since
`libspdm_register_device_buffer_func` is where the value comes from:

```c
#define LIBSPDM_EFFECTIVE_RECEIVER_BUFFER_SIZE                       \
    ((m_use_data_transfer_size == 0) ? LIBSPDM_RECEIVER_BUFFER_SIZE  \
     : (m_use_data_transfer_size +                                   \
        (LIBSPDM_RECEIVER_BUFFER_SIZE - LIBSPDM_DATA_TRANSFER_SIZE)))
```

It can only *lower* the value, which is the only honest direction:
`DataTransferSize` is what an endpoint tells its peer it can receive, and
advertising more than the buffer holds is a lie the peer acts on. The flag is
range-checked against the SPDM 1.2 minimum of 42 below and the build's own
compile-time ceiling above.

### 4. ★ The sweep contains its own control, and the control is what makes the flavor admissible

The sweep's six points include **4,608 — the value the unpatched `pqc` build
computes**. That arm must reproduce `pqc`'s capture, and it does: 46 packets,
58,966 captured bytes, 12 chunk round trips, identical to Table 2's P2 row.

That is the decision's whole justification. A second build is only comparable to
the first if something says so, and a diff does not: a patch can be small,
correct-looking and still change a fourth number. **What says so is a capture
from the new build being byte-identical to one from the old.** Without that row
the other five would be measurements of an unknown binary.

The independent variable is also read back off the wire in every arm — the
`DTS=` clause in `harness/lib/check_negotiated.py` requires both ends'
advertised `DataTransferSize` to equal what was asked for, and it rejected all
twelve arms of the first attempt. That run is kept at
`bench/data/w8-dts-sweep-20260914T132232Z`.

## Consequences

- `third_party/` gains `spdm-emu-pqc-dts.pin`. It differs from
  `spdm-emu-pqc.pin` in exactly three lines: `flavor`, `cflags` and the two
  `flavor-patch` fields.
- `BUILD_PIN.txt` gains `cflags`, `flavor-patch`, `flavor-patch-sha256`, and
  separately `crypto-openssl-vendored` and `crypto-openssl-version` — because
  the same audit that produced this flavor found that no pin had ever recorded
  *which* OpenSSL computes the signatures. `--pin-only` backfills those into an
  existing tree without recompiling it, so the binaries behind the published
  captures were not replaced to fix their own provenance.
- A fresh machine that wants the sweep pays one extra build. `--seed-from pqc`
  copies the source tree so it is not a second multi-gigabyte download, and
  `docs/env-baseline.md` records what that costs.
- **Three flavors is the limit this reasoning supports.** A fourth for another
  constant would be the point at which the constant should become a runtime
  parameter upstream instead — which is what the patch is, and why it is
  upstream candidate 17 rather than a permanent local fork.

## What was rejected

- **One build per DataTransferSize value.** Six builds at ten to twenty-five
  minutes each, six pins, and no way to tell a difference between builds from a
  difference caused by the parameter.
- **Editing `pqc` in place and rebuilding.** Breaks reproduction of every
  published number, as above.
- **Computing the sweep instead of running it.** The model in
  `bench/exp04_fragmentation.py` would then be validated against nothing, and it
  is the model that lets values *outside* the sweep be stated at all.
- **Vendoring the patched source.** Standing rule: no upstream source in this
  repository. A patch and a digest, as ADR 0006 established.

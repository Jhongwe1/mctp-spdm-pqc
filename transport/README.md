# transport

Glue for carrying SPDM over something other than a TCP socket — and, already
here, the transport *parameter* that decides how many round trips a message
costs.

## `data-transfer-size.patch`  (W08)

`DataTransferSize` is what an endpoint tells its peer it can receive in one
message. Exceed it and SPDM chunks, and each chunk is a complete
request/response exchange — one bus round trip. It is therefore the parameter a
BMC or root-of-trust integrator tunes, and `spdm-emu` has no flag for it: it is
`LIBSPDM_RECEIVER_BUFFER_SIZE` minus the transport header and tail, in
`spdm_emu/spdm_emu_common/spdm_emu.h`.

These 55 lines across five files add `--data_transfer_size <bytes>`, which can
only *lower* the advertised value — advertising more than the buffer holds is a
lie the peer acts on. It is applied by `harness/build_spdm_emu.sh` as part of
what the `pqc-dts` flavor **is**, not as an optional overlay like
`device/meas-from-file.patch`; [ADR 0009](../docs/decisions/0009-a-third-build-flavor.md)
is the difference, and `third_party/spdm-emu-pqc-dts.pin` records the patch's
digest so a capture can name it.

What it bought: [`../docs/pqc-cost.md`](../docs/pqc-cost.md) §9 — a 32x sweep
showing that the parameter moves the byte total 3.1% and the round trips from 59
to zero. It is upstream candidate 17.

## Real transports

Carrying SPDM over something that is not a TCP socket arrives in **G5 (week 9)**.
Two candidate paths, both of which this development machine currently blocks (recorded in `../docs/env-baseline.md`): a QEMU device
exposing an SPDM port, and Linux `AF_MCTP` — which needs `CONFIG_MCTP`, and
the WSL2 kernel is built without it.

If both stay blocked, that is written down as two things tried and where each
stopped, and any derived figure is labelled as computed rather than observed.

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
to zero. It is upstream candidate 17, prepared for `DMTF/spdm-emu` as
[`../docs/upstream/0004-data-transfer-size.md`](../docs/upstream/0004-data-transfer-size.md).

### Two defects in this patch, found on 2026-09-29, and why the evidence stands

Rebuilding it on upstream's `4.0.0-rc2` to send it meant reading every line
again, and two were wrong. **This file is left exactly as it is**, because it is
what the `pqc-dts` captures were made with and its digest is in their pin:

1. **With `CHUNK_CAP` cleared, it advertises a `MaxSPDMmsgSize` larger than its
   `DataTransferSize`.** DSP0274 1.4.1 requires the two to be equal for an
   endpoint without the Large SPDM message transfer mechanism, and libspdm's
   requester enforces it. Measured on this flavor's own build: a responder
   without `CHUNK_CAP` at `--data_transfer_size 1024` advertises `1024/32768`,
   and the requester stops at `CAPABILITIES` with `0x80010005`.
2. **On `--trans NONE`, it advertises 128 bytes more than it is asked for.**
   NONE registers no transport header or tail, and the macro above subtracts
   the 64 + 64 the other transports register. The comment in the patch admitted
   it and relied on the harness to notice.

Neither reaches a published number. Every arm of the sweep runs over the
MCTP-framed socket with `CHUNK_CAP` on both sides, and each arm's
`DataTransferSize` is read back out of both `CAPABILITIES` messages and
compared with what was asked. The upstream version fixes both, and the sender
buffer has to follow as well: 0004 has the reasons and the measurements.

## Real transports

Both programs here are Gate 5's, and both run inside a QEMU guest whose kernel
has what this host's lacks. [`../docs/transports.md`](../docs/transports.md)
has the results.

- `mctp_bridge.c` carries the unmodified emulators' handshake across a real
  Linux `AF_MCTP` link between two network namespaces — endpoint IDs, a route
  table, kernel-allocated tags and 64-byte packetisation.
  `harness/run_afmctp.sh` runs it.
- `doe_probe.c` drives a PCIe DOE mailbox from guest userspace on a QEMU NVMe
  device, and got one SPDM `GET_VERSION` across it and answered.
  `harness/run_doe.sh` runs it.

`make check` compiles both again under `-Werror` with AddressSanitizer and
UBSan. There is no `make test` here, and the Makefile says why.

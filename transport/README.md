# transport

Glue for carrying SPDM over something other than a TCP socket.

Arrives in **G5 (week 9)**. Two candidate paths, both of which this development
machine currently blocks (recorded in `../docs/env-baseline.md`): a QEMU device
exposing an SPDM port, and Linux `AF_MCTP` — which needs `CONFIG_MCTP`, and
the WSL2 kernel is built without it.

If both stay blocked, that is written down as two things tried and where each
stopped, and any derived figure is labelled as computed rather than observed.

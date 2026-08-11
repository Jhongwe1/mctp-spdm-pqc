# device

Modifications to the device secret / measurement sample library, and the three
tamper points they implement.

Arrives in **G2 (weeks 3-5)**. The file being modified is
`os_stub/spdm_device_secret_lib_sample/meas.c` in libspdm — 33,452 bytes in
the `pqc` flavor, 32,179 in `stable` (confirmed 2026-08-11).

Each tamper point is a patch, not a fork: the diff is the artifact, because a
diff is reviewable and a modified copy is not.

# device

Where a measurement value comes from, and the sixteen lines of upstream that
were changed to ask.

```bash
make -C device test          # the loader, under -Werror + ASan + UBSan
make -C device interop       # the C reader and the Python writer must agree

python3 device/gen_measurements.py --out /tmp/m.bin
python3 device/gen_measurements.py --describe /tmp/m.bin

bash harness/apply_device_patch.sh pqc --build     # into the pinned tree
bash harness/apply_device_patch.sh pqc --status
bash harness/apply_device_patch.sh pqc --revert
```

## Why anything here exists

libspdm's sample device secret library invents its measurements, which is
correct for sample code and makes two experiments impossible.

`os_stub/spdm_device_secret_lib_sample/meas.c` fills a 72-byte buffer with the
measurement index repeated, hashes it, and calls that the firmware measurement;
it assigns the constant `0x7` and calls that the secure version number. Both
are visible on the wire, and this repository measured them before touching
anything: index `0x01`'s value is `sha512(72 × 0x01)`, and index `0x10` carries
`07 00 00 00 00 00 00 00`.

That means:

- **there is no byte to flip.** A tamper test needs an input, and a constant
  compiled into a function is not one;
- **a rollback policy has one input.** Gate 3's rule is
  `evidence_svn >= reference_svn`, and a rule fed a single value has never been
  tested, whichever way round it is written.

So this directory supplies the values and **nothing else**.

## What was changed upstream, and what deliberately was not

[`meas-from-file.patch`](meas-from-file.patch), applied to libspdm at the commit
in `third_party/spdm-emu-pqc.pin`:

```
 os_stub/spdm_device_secret_lib_sample/CMakeLists.txt |  1 +
 os_stub/spdm_device_secret_lib_sample/meas.c         | 15 +++++++++++++++
 2 files changed, 16 insertions(+)
```

**Sixteen added lines, no deleted ones, and three of the sixteen are code.** The
other twelve are the comment explaining the three. In full, the code is:

```c
#include "measurement_source.h"

    libspdm_set_mem(data, sizeof(data), (uint8_t)(measurements_index));
+   (void)ms_get_block(measurements_index, data, sizeof(data));

    svn = 0x7;
+   (void)ms_get_svn(&svn);
```

Both additions sit on the line *after* upstream computes its own value, and
both leave the destination untouched when they decline. Upstream's statements
are still there, still run, and still produce the value whenever no fixture
names that measurement. That is why the diff is purely additive: nothing was
replaced, so nothing has to be argued about.

**Hash computation, block assembly, record sizing, the measurement summary hash
and every signature are untouched.** The consequence is the point:

> I did not change libspdm's logic. I changed where one buffer's contents come
> from, on the line after upstream fills it. Everything a capture measures is
> still upstream's behaviour, not mine — and that is what makes the measurement
> worth reporting.

Two hooks, not four. `libspdm_fill_measurement_manifest_block` and
`libspdm_fill_measurement_device_mode_block` synthesise their values the same
way and could take the same one-line hook. They do not, because nothing needs
them yet, and the smallness of the diff is the entire argument for trusting the
captures taken through it. Adding one is a line here and a descriptor in the
fixture, on the day something needs it.

The measurement summary hash carried in `CHALLENGE_AUTH` follows the fixture
with no third hook at all, because `libspdm_generate_measurement_summary_hash`
obtains its blocks by calling `libspdm_measurement_collection` — the same
function. Reading that before writing a third hook saved the third hook.

## The module

| file | what it is |
|---|---|
| [`measurement_source.h`](measurement_source.h) | the contract, the file format, and why the parser is strict |
| [`measurement_source.c`](measurement_source.c) | the loader. No libspdm headers, no allocator, ~250 lines |
| [`measurement_source_test.c`](measurement_source_test.c) | 66 checks, including eleven malformed fixtures that must be refused for **eleven different reasons** |
| [`gen_measurements.py`](gen_measurements.py) | writes fixtures; refuses a flip that would land outside a measurement value |
| [`Makefile`](Makefile) | builds and runs the above with two sanitizers, with no build tree present |

Turned on by `SPDM_MEASUREMENTS_FILE`. Unset, no file is opened and no memory
is touched, which is what makes "identical to upstream" a claim a capture can
check rather than a claim about intent.

### Three details worth the space they take

**The bounds check is done in the file format's width, not the host's.**
Descriptor offsets are `uint32`, so `ms_range_ok` does its arithmetic in
`uint32`. Written the obvious way, `off + len <= total`, the sum wraps and a
descriptor claiming offset `0xfffffff8` length 16 passes against a 100-byte
file. The test demonstrates the wrong version accepting exactly that, beside the
right one refusing it, so the bug is shown rather than asserted absent. On this
x86-64 host a `size_t` version could not wrap at all and the mistake would be
invisible; on a 32-bit BMC it is a live out-of-bounds read. This is
GHSA-m4wc-xmvg-369f's shape and `c-drills/d2` is the same arithmetic on paper.

**Every rejection has its own reason code, and the test asserts which one
fired.** Eleven malformed fixtures refused by one check would be one check with
ten passengers — `docs/roadmap.md` standing rule 13. The last test in the file
walks the whole `ms_status_t` enum and requires every value to have been
observed, so adding an error code without a case that provokes it is a failing
build.

**There is deliberately no checksum over the fixture.** A digest inside the
loader would detect the byte flip that tamper point 1 exists to perform, in the
wrong layer, before anything reached the wire — and the question the experiment
asks is precisely *which* layer notices. Integrity is handled out of band: the
run's `manifest.json` records the SHA-256 of the exact file the responder read,
so which bytes went in is always recoverable and never enforced.

## The provenance problem this creates, and how it is handled

A patched build tree is a build tree that `third_party/*.pin` no longer fully
describes. `certs/stage_chain.sh` avoids the same hazard by building a sandbox
instead of overwriting the build tree; that is not available here, because a
patch has to be compiled in.

So three things are true instead:

1. **Without the environment variable the binary does not behave differently** —
   and `bench/data/w4-tamper-*/t0_none` reproduces the measurement record of a
   capture taken on 2026-08-31, before this patch was written, to the byte.
2. **`harness/apply_device_patch.sh` refuses to patch the wrong tree.** It
   compares the tree's libspdm commit against `third_party/spdm-emu-pqc.pin` and
   the pre-image SHA-256 of both files it touches. `git apply` alone would
   accept a patch whose context survived a revision that changed what the
   context means; a digest does not.
3. **The patch is in every manifest.** Applying writes `DEVICE_PATCH.txt` beside
   `BUILD_PIN.txt`, and `prov_pin_file` folds it in, so every capture taken
   afterwards names the patch, its digest, the module's digests, and the
   pre- and post-image of `meas.c`.

## Results

[`docs/tamper.md`](../docs/tamper.md) — what each change did, which layer
noticed, and the two that nothing noticed.

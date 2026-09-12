# rats/interop — measured, not asserted

Produced by `bash rats/interop.sh` on 2026-09-12T14:56:27Z.
Not re-run in CI; what CI re-runs is the comparison against the files
here. See harness/verify_repo.sh.

| | |
|---|---|
| spdm-emu | 5f01d2f |
| CoRimTool.py | last changed 2023-05-09 |
| opa | 1.20.2 |
| cbor2 | 5.6.5 (pinned; >= 6.0 breaks pycose) |
| pycose | 1.1.0 |
| capture | `bench/data/w5-tamper-20260910T092621Z/t0_clean` |
| record | f2a14684e8fae9ff0e3ebff2a380f435c0fee5b0c8199d3fdfed31b2252f51d8 |

## What was compared

| # | comparison | result |
|:--|---|---|
| 1 | `SpdmMeasurement.py meas_to_json` vs `rats/appraise.py evidence` | identical apart from a final newline |
| 2 | `CoRimTool.py json_to_cbor` vs `rats/appraise.py to-cbor` | byte-identical, 1480 bytes |
| 3 | `rats/`: encode → decode → encode | same 1480 bytes |
| 4 | `CoRimTool.py`: the same round trip | **KeyError: 'corim'** |
| 4b | …on its own `SampleManifests/SpdmSampleCoMid.json` | **KeyError: 'corim'** |
| 5 | `rats/cose.py verify` on `CoRimTool.py sign`'s output | accepted |
| 6 | `CoRimTool.py verify` (patched) on `rats/cose.py sign`'s output | accepted |
| 7 | `CoRimTool.py verify` (**unpatched**) on the same file | refused — the upstream defect |
| 8 | `SpdmSamplePolicy.rego` parsed as Rego v1 | refused, 11 parse errors |
| 9 | `SpdmSamplePolicy.rego` on the clean capture | passes, as this project's policy does |
| 10 | `SpdmSamplePolicy.rego` on an index swap | **accepts** |
| 11 | `rats/policy.rego` on the same swap | refuses |
| 12 | `SpdmSamplePolicy.rego` on nothing-measured-anywhere | **accepts** |
| 13 | `rats/policy.rego` on the same | refuses |

Rows 4 and 4b are not comparisons this project set out to make. They
are what row 2 turned into once the encoders were compared at all.
`cbor_to_json` writes the two CoRIM container tags as JSON KEYS —
`corim` and `unsigned_corim_map` — and `json_to_cbor`'s `AllMapDict`
has no entry for either, so `translate_data` raises before it reaches
anything else.

A second, narrower difference sits behind it and was found first:
`translate_data` maps exactly two name strings to integers —
`comid_tag_creator` and `sha256` — hard-coded, in a branch where a
table lookup was intended. A CoMID naming `sha512` or `comid_creator`
encodes those as text strings, 43 bytes larger than the same document
written with integers. This project's reference values are written
with integers, which is what the published sample does, and that is
why row 2 can be a byte comparison at all.

Rows 10 and 12 are the measured version of what `rats/rats_selftest.py`
models. The model exists so a runner without `spdm-emu` keeps checking
the claim; this file is the run that says the model is right.

## The two workarounds, and why they are not this project's

```
cbor2==5.6.5    pinned. 6.x decodes a CBORTag's contents as immutable
                containers and pycose type-checks for list/dict, so
                pycose cannot decode its own encode() output.

CoRimTool.py    one line, in a scratch copy:
-   cose_key = EC2Key(crv='P_256', d=key)
+   cose_key = EC2Key(crv='P_256', x=key[:len(key)//2], y=key[len(key)//2:])
```

Reported in `docs/upstream/README.md`. Row 5 above is this repository
re-running its own bug report on every interop run, so that the day
upstream fixes it, this script says so rather than the report going
quietly stale.

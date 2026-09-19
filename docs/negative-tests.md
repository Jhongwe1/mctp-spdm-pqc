# Fuzzing, coverage, and a corpus that had to be measured rather than asserted

> **This project performs protocol-level correctness validation. It is not a
> security assessment.** Running a fuzzer is the outermost edge of the second
> thing and not an instance of it. A security assessment involves formal
> verification, sustained fuzzing, side-channel analysis and third-party audit;
> what is below is a few minutes of one of those four.

**Nothing crashed, and that is the expected and complete result.** `libspdm`
runs on OSS-Fuzz, has CodeQL and Coverity in CI, and ships about sixty-nine AFL
targets of its own. An afternoon of local fuzzing finding something they have
not is close enough to zero that planning for it would be dishonest.

So this page is not about whether there are bugs. It is about two things that
can come out either way:

1. **the seed corpus** — a claim that this project's seeds are better than the
   alternative, evaluated against the alternative instead of asserted;
2. **the coverage** — how much of the library the tests actually reach, so that
   "no crashes" has a denominator.

| | |
|---|---|
| runs | [`w10-fuzz-20260919T185226Z`](../bench/data/w10-fuzz-20260919T185226Z) (two captures), [`w10-fuzz-20260919T185332Z`](../bench/data/w10-fuzz-20260919T185332Z) (three), [`w10-coverage-20260919T192627Z`](../bench/data/w10-coverage-20260919T192627Z) |
| harness | [`harness/run_fuzz.sh`](../harness/run_fuzz.sh), [`harness/run_coverage.sh`](../harness/run_coverage.sh), `bench/pcapstat.py --export-seeds` |
| AFL | AFL++ 4.09c, `-DTOOLCHAIN=AFL -DTARGET=Release -DCRYPTO=mbedtls -DGCOV=ON` |
| coverage | lcov 2.0, `-DTOOLCHAIN=GCC -DTARGET=Debug -DCRYPTO=openssl -DGCOV=ON` |

---

## 1. Two repositories, and only one of them is short of fuzzing

This distinction is worth getting exactly right, because the loose version of
it — *"the reference implementation has no fuzzing"* — is false and a reader
who knows the tree will notice.

| | |
|---|---|
| **`libspdm`** | the protocol library. `unit_test/fuzzing/` holds **six target families, about sixty-nine individual targets**, a seed corpus of **69 directories and 81 files**, an OSS-Fuzz configuration, and build scripts for AFL, AFL++, AFLTurbo and libFuzzer. Its CI runs CodeQL and Coverity |
| **`spdm-emu`** | the demonstration program. Its own `README.md`, verbatim: *"This package is only the sample code to show the concept. It does not have a full validation such as robustness functional test and fuzzing test. It does not meet the production quality yet."* |

So: this project uses `spdm-emu` to drive protocol flows, and fuzzes
**`libspdm`'s own targets**, in **upstream's own configuration** — the AFL
build here is the one `unit_test/fuzzing/fuzzing_AFL.sh` and
`oss-fuzz_conf/build.sh` specify, mbedtls and all.

> ⚠ **That last word is a caveat, not a detail.** Upstream fuzzes with mbedtls;
> every capture this repository publishes was produced against libspdm's
> vendored **OpenSSL 3.5.5**. The protocol handlers under the fuzzer are the
> same code and the crypto beneath them is not, so no number on this page
> transfers to the binaries that produced Table 2 without saying so. §4 is the
> OpenSSL one.

---

## 2. The corpus, and the claim that had to be withdrawn

The attractive sentence is *"my fuzz seeds are real messages from my own
handshakes, not random bytes"*. The first half is true. The second half
compares against something nobody does: **libspdm ships a corpus.**

It is small and hand-written — one seed per target for most of them.
`test_spdm_responder_version`'s is four bytes:

```
10 84 00 00        SPDM 1.0, GET_VERSION, param1 = 0, param2 = 0
```

`docs/roadmap.md` standing rule 18 says a claim that two things differ has to
evaluate both, so both were evaluated. `afl-showmap -C` executes an entire
corpus and reports the union of the edges it reached — deterministic, so a
single value rather than a median.

### 2.1 The corpus this project exports

`bench/pcapstat.py --export-seeds` writes one file per **distinct** SPDM
message, in a directory per message type, named by a digest of its own bytes —
so the same capture always produces the same tree, and the union across
captures deduplicates itself.

The direction matters and is not cosmetic: a responder fuzz target is fed
*requests*. `libspdm_run_test_harness` hands the file straight to
`libspdm_get_response_<x>()` as a received request, so a corpus of responses
would spend the budget rediscovering the request format. The default is
`REQ->RSP` and `--seed-direction` exists for the requester targets.

| source capture | messages | distinct seeds |
|---|---:|---:|
| `w8-pqc-matrix/A0-all.pcap` — a classical handshake | 11 | 8 |
| `w8-pqc-matrix/P2-all.pcap` — the post-quantum one | 23 | 20 |
| `w10-validator/caps-no-mut-auth.pcap` — the conformance run | 894 | 293 |
| **union, by content digest** | | **312** across 13 message types |

### 2.2 Edges reached

```
  target                                         upstream     mine     both    added
  test_spdm_responder_version                         442      442      442        0
  test_spdm_responder_capabilities                    436      535      535      +99
  test_spdm_responder_algorithms                      601      685      711     +110
  test_spdm_responder_digests                         581      592      592      +11
  test_spdm_responder_certificate                    2997     3012     3012      +15
  test_spdm_responder_challenge_auth                 3612     3716     3716     +104
  test_spdm_responder_measurements                   3630     3744     3744     +114
  test_spdm_responder_key_exchange                   4158     4210     4213      +55
  test_spdm_responder_finish_rsp                     3992     4016     4016      +24
  test_spdm_responder_heartbeat_ack                  2955     2898     2959       +4
  test_spdm_responder_key_update                      665      640      669       +4
  test_spdm_responder_end_session                    2867     2867     2867        0
  test_spdm_responder_chunk_get                       434      419      443       +9
  test_spdm_responder_chunk_send_ack                    -        -        -        -
  test_spdm_responder_csr                               -        -        -        -
  test_spdm_responder_set_certificate                   -        -        -        -
  test_spdm_responder_measurement_extension_log         -        -        -        -
```

**Read it honestly:**

- On **three** targets — heartbeat, key update, chunk get — this project's
  corpus reaches **fewer** edges than upstream's single hand-written seed.
- On **two** — version, end session — the union adds nothing at all.
- On **five** the union exceeds *both* individual corpora
  (`algorithms` 711 against 685 and 601 is the clearest), which means the two
  corpora are **complementary rather than ordered**. That is a more useful
  finding than "mine is better" and it is the one that survives.
- Four targets have **no seed at all**, because no capture in this repository
  contains a `CHUNK_SEND`, `GET_CSR`, `SET_CERTIFICATE` or
  `GET_MEASUREMENT_EXTENSION_LOG`.

### 2.3 ★ The finding the first run produced, and why the run was kept

The first run drew seeds from the two handshakes only. It is committed —
`w10-fuzz-20260919T185226Z` — because its result is the interesting one:

| target | 2 captures | 3 captures |
|---|---|---|
| `algorithms` | 2 seeds, **+0 edges** (and 378 alone, against upstream's 601) | 20 seeds, **+110** |
| `capabilities` | 1 seed, +41 | 24 seeds, +99 |
| `challenge_auth` | 2 seeds, +16 | 82 seeds, +104 |
| `measurements` | 2 seeds, +10 | 54 seeds, +114 |
| `key_exchange`, `finish_rsp`, `heartbeat_ack`, `key_update`, `end_session` | **no seed** | 73 / 6 / 1 / 1 / 1 seeds |

> **A seed is not good because it is real. It is good because the run it came
> from went somewhere.**
>
> Two successful handshakes produce two well-formed messages per type and
> nothing else — no version mismatch, no invalid parameter, no error path,
> because a handshake that took one would not have succeeded. The conformance
> run sends those deliberately, and its capture is the reason the corpus stopped
> losing.

And the ten empty targets trace to a decision made in week eight rather than to
anything about fuzzing: `harness/lib/arms.sh` pins `--exe_session NO_END`, which
does **not** include `EXE_SESSION_KEY_EX`, so **no arm of this project's A/B has
ever established a secure session** and no capture of one contains a
`KEY_EXCHANGE`. The file has said so in its own comment since it was written.
It took a fuzz corpus to make the consequence visible.

---

## 3. The fuzzing, and the arithmetic that makes "nothing found" a result

```
  target                                    execs      run time   crashes   hangs
  test_spdm_responder_certificate            3,510        420 s         0       0
  test_spdm_responder_measurements           5,930        420 s         0       0
  test_spdm_responder_challenge_auth         1,992        420 s         0       0
  total                                     11,432      1,260 s         0       0
```

Three targets, chosen for the advisory classes `negative/` reproduces rather
than for corpus size: `GET_CERTIFICATE` carries an Offset and a Length that get
added together, `GET_MEASUREMENTS` walks an index, and `CHALLENGE` carries the
nonce and slot the signature is computed over.

**Twenty-one minutes, and the number that matters is not the twenty-one.**

```
  11,432 executions / 1,260 seconds  =  9.07 executions per second
```

AFL++ says so itself in the log — *"WARNING: The target binary is pretty slow!"*
— and reports 107,000 to 214,000 microseconds per execution. Each one sets up
a full `libspdm` test context, which includes loading a certificate chain.

So the arithmetic on the eight-hour campaign the plan asked for:

| budget | executions, at this speed |
|---|---:|
| what was run, 21 minutes | 11,432 |
| 8 hours | ~261,000 |
| 24 hours | ~784,000 |

A fuzzing campaign is normally counted in **millions** of executions. At nine
per second, even the eight-hour version is three orders of magnitude short of
the point where an absence of crashes says anything about the code — which is
exactly why OSS-Fuzz exists, and it is the honest reason a local run finds
nothing, rather than "we got unlucky".

> **What was actually demonstrated:** that upstream's fuzzing toolchain builds
> and runs here, that a corpus can be extracted from this project's own
> evidence and measured against upstream's, and that the extraction is
> deterministic. Not that `libspdm` is robust.

**If a crash had been found**, `run_fuzz.sh` copies the inputs into the run
directory and prints the reporting rule beside them: no public issue, no
description outside this repository, and the [DMTF Security Issue Reporting
Process](https://www.dmtf.org/securityissuereporting) — which is the route
`libspdm`'s own `SECURITY.md` names — until it is published. None was.

---

## 4. Coverage, so that "no crashes" has a denominator

`libspdm`'s own unit tests, under gcov, against the **OpenSSL** backend that
every published capture here was produced with.

```
  lines......: 69.7%  (11,834 of 16,980)
  functions..: 79.9%  (421 of 527)

  directory                                  lines     hit       %
  spdm_requester_lib                          6094    4781   78.5%
  spdm_responder_lib                          4889    3740   76.5%
  spdm_common_lib                             2850    1689   59.3%
  spdm_crypt_lib                              2290     996   43.5%
  spdm_secured_message_lib                     846     617   72.9%
```

`spdm_responder_lib` at **76.5%** is the row worth reading: those are the
handlers a device exposes to a peer it does not control, which is level 3 of
libspdm's own [threat model](threat-scope.md#the-five-layers-of-the-thing-this-project-is-built-on).

### 4.1 Eight unit tests, of which two do not pass — and neither is a defect

`build_cov/bin` holds 112 binaries whose names begin `test_`, and **69 of them
are fuzz targets**, uninstrumented. A fuzz target run with no argument prints
`file error` and exits 1. The first version of this script ran all 112 and
reported six failures that were nothing but missing arguments — a number that
would have gone into this page as if the library were broken. The exclusion is
now taken from the tree (`unit_test/fuzzing/<family>/<target>/`) rather than
from the names.

Of the eight that remain:

| | |
|---|---|
| `test_crypt`, `test_spdm_common`, `test_spdm_crypt`, `test_spdm_requester`, `test_spdm_responder`, `test_spdm_secured_message` | pass |
| **`test_spdm_fips`** | *"test is valid only when LIBSPDM_FIPS_MODE is open"* — the flag is `0` in `include/library/spdm_lib_config.h:139`, and the test **refuses to run** rather than passing vacuously. Good test design, and it means this project has **not** exercised the FIPS known-answer vectors |
| **`test_spdm_sample`** | *"Unable to open file dice_cert/dice_root_cert.der"* — a fixture `make copy_sample_key` does not place. A missing input, not a failing assertion |

★ Both are the same classification the conformance report spends its §5.3 on:
**a test that did not run is not a test that failed**, and the two are
distinguishable only by reading what it said.

The `test_spdm_fips` one is worth a sentence more than its size suggests. The
vectors it declines to run check the random number generator — the same one
`GET_MEASUREMENTS` draws its nonce from. A predictable nonce is a replay
defence that is not there, and nothing in this project has checked it.

---

## 5. What is not here

- **No claim about `libspdm`'s robustness.** Eleven thousand executions.
- **No branch coverage.** lcov reports `no data found` for branches on this
  build; the line and function figures are what the tools produced and the
  branch row is left saying so rather than omitted.
- **No coverage figure for the fuzzing.** The AFL build is instrumented for
  gcov too, but merging its counters with the unit tests' would produce one
  number describing two different binaries with two different crypto backends.
  The edge counts in §2.2 are what the fuzz build reports, in AFL's own units.
- **No re-derivation of §2.2 in CI.** `afl-showmap` needs the AFL build, which
  CI does not have. The table is committed as `corpus-comparison.json` beside
  the seeds it was computed from, and reproducing it needs
  `harness/run_fuzz.sh --no-fuzz` on a machine with the tree. Every other
  number this repository publishes is re-derived on every CI run; these are
  not, and that is stated here rather than left for a reader to discover.

## 6. Reproducing it

```bash
# the deterministic half: seeds, the message-to-target map, and the edge counts
bash harness/run_fuzz.sh --no-fuzz

# and with a fuzzing budget, per target
bash harness/run_fuzz.sh --seconds 420

# coverage, against the OpenSSL backend the captures were taken with
bash harness/run_coverage.sh
bash harness/run_coverage.sh --list     # which binaries it considers unit tests

# the seed exporter's own self-test, which CI runs
python3 bench/pcapstat.py --selftest
```

Both builds are made the way `libspdm/doc/test.md` and
`unit_test/fuzzing/fuzzing_AFL.sh` say, and `run_fuzz.sh` prints the exact
`cmake` line in its error message when the build is absent.

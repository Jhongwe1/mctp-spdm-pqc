# The official conformance suite, and what running it is worth

> **This project performs protocol-level correctness validation. It is not a
> security assessment.** A conformance suite is the narrowest form of the first
> thing and none of the second: it checks that a device answers the way a
> specification says, on the inputs somebody wrote down.

DMTF publishes [`SPDM-Responder-Validator`][val], a conformance suite written
against [DSP-IS0023][is0023], and `spdm-emu` builds it as
`spdm_device_validator_sample`. It has been in this project's build tree since
week one. This is what happened when it was pointed at this project's
responder, four times.

[val]: https://github.com/DMTF/SPDM-Responder-Validator
[is0023]: https://www.dmtf.org/dsp/DSP-IS0023

| | |
|---|---|
| suite | `SPDM-Responder-Validator` at `c27bb1c7a5c2b289a316d0d5685ea899adc71899`, the submodule pointer of `spdm-emu` `4.0.0-rc` |
| device under test | `spdm_responder_emu` from the same pair, `libspdm` `4.0.0-rc`, vendored OpenSSL 3.5.5 |
| algorithms | whatever each test case negotiates; the responder is **not** pinned with `--ver`, and §1.3 says why |
| run | [`bench/data/w10-validator-20260919T184429Z`](../bench/data/w10-validator-20260919T184429Z), four arms, one `manifest.json` |
| harness | [`harness/run_validator.sh`](../harness/run_validator.sh), [`harness/validator_report.py`](../harness/validator_report.py) |

---

## 1. Three things to know before reading any number

### 1.1 The verdict is not on stdout, and the exit status is always 0

```c
/* common_test_framework/library/common_test_utility_lib/common_test_utility_lib.c */
#define COMMON_TEST_LOG_FILE_NAME "test.log"
...
m_log_file = fopen (COMMON_TEST_LOG_FILE_NAME, "w+");
```

Every result line is a `fprintf` to that file, opened in the **current working
directory**. The program prints four lines of banner to the console and nothing
else. And `spdm_device_validator_sample.c`'s `main()` ends in an unconditional
`return 0`: every assertion can fail, or the suite can fail to start, and the
status is 0 either way.

So the obvious command —

```bash
./harness/run_validator.sh 2>&1 | tee /tmp/validator.log
grep -ciE 'PASS|FAIL|SKIP' /tmp/validator.log        # prints 0
```

— counts nothing, and a script that believed the exit status would report a
clean run on a suite that never connected. `run_validator.sh` judges an arm by
the parsed contents of `test.log` and **fails loudly when that file is absent**,
which is the only way "it did not run" and "it ran and everything failed" can be
told apart.

> This is the third time this project has taken an easy signal for the real one.
> The pipeline's exit status instead of the build's, `spdm_dump`'s output length
> instead of the handshake's, and now a return value that is a constant.
> `CLAUDE.md` red line 2, and `LOG.md` 2026-08-11.

### 1.2 `NOT_TESTED` is counted by neither half of the suite's own footer

`common_test_record_test_suite_result` increments `total_pass` on PASS and
`total_fail` on FAIL, and does nothing at all on `NOT_TESTED`. The footer the
suite prints is therefore **not** the number of assertions it recorded:

| | baseline arm |
|---|---:|
| assertions recorded | **1,140** |
| the footer's `pass` + `fail` | 1,085 |
| the difference | **55**, every one of them `NOT_TESTED` |

Those 55 are the interesting ones. An assertion that recorded `NOT_TESTED` is
one the suite wanted to make and could not, and §3 is what happens when the
obstacle is removed.

### 1.3 The suite picks a version per case, so the responder must not be pinned

Every other experiment in this repository pins `--ver 1.4`. This one must not.
Each test case sets the version it targets — `SUCCESS_10`, `SUCCESS_11`,
`SUCCESS_12` — and a responder pinned to 1.4 makes most of them unreachable.
The run therefore leaves the responder offering 1.0 through 1.4, and the capture
shows it answering `GET_CAPABILITIES` with **five different `Flags` words**, one
per negotiated version, because the later capability bits do not exist in the
earlier ones:

```
  1.0   0x00000037      1.3   0x399afbf7
  1.1   0x0000fbf7      1.4   0xb99afbf7
  1.2   0x001afbf7
```

★ **This is what "arranging a test configuration" means**, and it is the
answer to why a real product does it before a conformance campaign rather than
during one. The suite's three stated prerequisites — standard algorithms, an
X.509 chain rather than a raw public key, and a device not in update mode — are
the same kind of fact: they are properties of the configuration, and they decide
which assertions are even reachable.

---

## 2. The four arms

One run of a conformance suite tells you about the device. It tells you nothing
about the suite, and `docs/roadmap.md` standing rule 11 says a check is worth
what it rejects. So three of these four arms exist to make the suite say
something other than PASS.

| arm | what differs | assertions | PASS | FAIL | `NOT_TESTED` | cases skipped |
|---|---|---:|---:|---:|---:|---:|
| `caps-default` | nothing — the shipped configuration | 1,140 | 1,077 | **8** | 55 | 3 |
| `caps-no-mut-auth` | one capability bit cleared | 1,751 | 1,721 | 6 | 24 | 3 |
| `proxy-inert` | reached through a proxy that changes nothing | 1,140 | 1,077 | 8 | 55 | 3 |
| `proxy-flip-sig` | the same proxy, one signature byte changed | 1,018 | 954 | **9** | 55 | 3 |

`caps-default` by group:

| Group | Name | PASS | FAIL | NOT_TESTED | Cases skipped |
|---:|---|---:|---:|---:|---|
| 1 | `spdm_test_group_version` | 9 | 0 | 0 | -- |
| 2 | `spdm_test_group_capabilities` | 80 | 0 | 0 | 2.7 |
| 3 | `spdm_test_group_algorithms` | 104 | 0 | 0 | 3.8 |
| 4 | `spdm_test_group_digests` | 15 | 0 | 0 | -- |
| 5 | `spdm_test_group_certificate` | 107 | 0 | 0 | 5.6 |
| 6 | `spdm_test_group_challenge_auth` | 254 | 4 | 24 | -- |
| 7 | `spdm_test_group_measurements` | 406 | 0 | 3 | -- |
| 8 | `spdm_test_group_key_exchange_rsp` | 102 | 4 | 1 | -- |
| 9 | `spdm_test_group_finish_rsp` | 0 | 0 | 14 | -- |
| 12 | `spdm_test_group_heartbeat_ack` | 0 | 0 | 4 | -- |
| 13 | `spdm_test_group_key_update_ack` | 0 | 0 | 5 | -- |
| 16 | `spdm_test_group_end_session_ack` | 0 | 0 | 4 | -- |
| **total** | | **1077** | **8** | **55** | **3** |

Two numbers in that table are re-derived from the committed `test.log` by
`harness/check_claims.py` on every CI run, as `validator_baseline_failures` and
`validator_baseline_not_tested`.

### 2.1 Twelve groups, not twenty — and 71 cases, one of which does not exist

The suite's `README.md` lists **twenty** test groups. Saying so in an interview
would be a mistake, because at this commit:

| | |
|---|---:|
| groups the README documents | 20 |
| groups with a source file in `spdm_responder_conformance_test_lib/` | **12** |
| cases those twelve implement | **73** |
| cases `spdm-emu`'s `spdm_device_validator_config.c` registers | **71** |

Groups 10, 11 (PSK), 14, 15 (encapsulated), 17 (CSR), 18 (`SET_CERTIFICATE`),
19 and 20 (chunking) have no implementation to run. They are not skips at
runtime; there is nothing there.

And the two lists disagree in **both directions**, which is what
`validator_report.py --audit-config` exists to find:

| | case | consequence |
|---|---|---|
| implemented, not registered | `CAPABILITIES_SUCCESS_13` | prints `- skipped`, visible in the log |
| implemented, not registered | `ALGORITHMS_SUCCESS_13` | prints `- skipped` |
| implemented, not registered | `CERTIFICATE_SIZE_REQ` | prints `- skipped` |
| **registered, not implemented** | `CERTIFICATE_SPDM_X509_CERTIFICATE` | ★ **prints nothing at all** |

The first three are the only two cases in the suite that exercise **SPDM 1.3**,
plus the one that tests a size-limited `GET_CERTIFICATE`. The fourth is worse
than a skip: the framework iterates the *library's* case table, so a case that
is only in the configuration is never looked for. Nothing in `test.log` says it
was meant to run. A reader counting the suite's output would conclude it ran 71
cases; it ran 70 and one of them is imaginary.

★ **So a clean conformance report from this sample says nothing about the
responder's behaviour above SPDM 1.2 — and not because the suite cannot reach
it. Three lines of a configuration array are the difference.** This is
[upstream candidate 18](upstream/README.md).

`harness/validator_report.py --audit-config` reads both files and recomputes
that table, so it is a check rather than a paragraph.

---

## 3. One capability bit, 611 assertions

Four of the eight baseline failures are `8.x.4`, the assertion

```
Assertion 8.1.4:  SpdmMessage.MutAuthRequested == 0 && SpdmMessage.SlotIDParam == 0
```

and the test case's own setup declares `Flags.MUT_AUTH_CAP = 0` in its
`GET_CAPABILITIES` (`spdm_responder_test_8_key_exchange_rsp.c:68-76` sets nine
requester capability bits and `MUT_AUTH_CAP` is not among them). The responder
answers `MutAuthRequested = 0x02` regardless.

Every group that needs a session is behind that failure. The case returns as
soon as assertion 4 fails, so no session is established, so `FINISH_RSP`,
`HEARTBEAT_ACK`, `KEY_UPDATE_ACK` and `END_SESSION_ACK` record **nothing at
all** — four groups whose footer reads `pass: 0, fail: 0`, which looks like a
group with no assertions rather than what it is.

So the second arm clears exactly that bit. `--cap` is given the responder's
shipped set minus `MUT_AUTH`, and then the claim that only one bit moved is
**verified from the captures** rather than from the flag:

```
  1.0   0x00000037 -> 0x00000037   moved: nothing
  1.1   0x0000fbf7 -> 0x0000faf7   moved: MUT_AUTH_CAP
  1.2   0x001afbf7 -> 0x001afaf7   moved: MUT_AUTH_CAP
  1.3   0x399afbf7 -> 0x399afaf7   moved: MUT_AUTH_CAP
  1.4   0xb99afbf7 -> 0xb99afaf7   moved: MUT_AUTH_CAP
  ok   MUT_AUTH_CAP moved in 4 of 5 negotiated version(s) and nothing else moved anywhere
```

(Version 1.0 does not carry the bit at all, so "nothing moved" is the right
answer there and the check is written to require it rather than to tolerate it.
Standing rule 8: the independent variable is read back, and enumerated rather
than spot-checked.)

**The result:**

| | |
|---|---:|
| assertions the suite recorded, before | 1,140 |
| after | 1,751 |
| **difference** | **+611** |
| assertions that appeared | 642 |
| assertions that disappeared | 31 |
| `FAIL` → `PASS` | 4 |
| `PASS` → `FAIL` | **2** |

Re-derived as `validator_assertions_unlocked_by_one_capability_bit`.

★ **A capability bit is not a feature flag; it is a gate on how much of the
suite can run.** Six hundred and eleven assertions — more than half the
baseline's entire output — were never executed, and nothing in the baseline
report says so except four groups reading `pass: 0, fail: 0`.

### 3.1 And it does not only add

Two assertions moved the other way:

```
PASS->FAIL  3.5.15   response req_base_asym_alg - 0x0008
PASS->FAIL  3.6.15   response req_base_asym_alg - 0x0008
```

With `MUT_AUTH_CAP` cleared, the responder still selects a requester signature
algorithm (`RSAPSS_3072`) that the suite now expects to be absent. That is the
same shape as [upstream candidate 13](upstream/README.md), found in week seven
from the other side: the responder's requirement for exactly one requester
signature algorithm is tied to `MUT_AUTH_CAP`, and the flags meant to turn
mutual authentication off do not all reach it.

> **The lesson is not "clear the bit".** It is that *there is no configuration
> that maximises the report*: the one that unlocks four groups loses two
> assertions elsewhere. A conformance result is a function of a configuration,
> and publishing one without publishing the configuration is publishing a
> number without its units.

---

## 4. Calibration

Everything above is a measurement of a device by an instrument nobody has
checked. Standing rule 11 applies to the instrument:

> A check is worth what it rejects, and something has to prove it rejects.

So the last two arms put [`harness/tamper_proxy.py`](../harness/tamper_proxy.py)
— week five's in-flight tamper harness — between the suite and the responder.

**`proxy-inert` is the control, and it came first.** The proxy forwards 768
frames in each direction and changes nothing. It must produce an identical
result to `caps-default`, and it does: 1,140 assertions, 1,077 PASS, 8 FAIL, 55
`NOT_TESTED`, the same three skipped cases. Asserted as
`validator_proxy_changes_nothing`, value **0**. Without it, a failure in the
next arm could as easily mean "the proxy cannot forward a 1.6 MB conformance run"
as "the suite noticed".

**`proxy-flip-sig` changes one byte.** The proxy parses the first `MEASUREMENTS`
response whose layout closes under two independent equations, and flips the last
byte of its signature:

```json
{ "negotiated": { "base_asym_name": "ECDSA_ECC_NIST_P384", "signature_bytes": 96 },
  "measurements": { "spdm_bytes": 161, "signature_offset": 65, "closed": true } }
```

The requirement is not that something turns red. It is that **exactly the right
thing** turns red:

```
proxy-inert  ->  proxy-flip-sig
  regressed        1
  improved         0
  disappeared    122
  appeared         0
    PASS->FAIL  7.6.7      response signature
  ok   every regression carries 'response signature', there is at least one, and nothing improved
```

One regression, and it is the assertion that verifies the measurement signature.
Nothing improved. The 122 assertions that disappeared are the remainder of case
7.6, which returns as soon as the signature check fails — and
`validator_report.py --compare` asserts separately that **every** disappearance
is inside a case that had a regression of its own, so a cascade cannot hide a
second, unrelated break.

Re-derived as `validator_calibration_one_more_failure`, value **1**.

★ **This is the difference between "I ran DMTF's conformance suite" and "I
measured what DMTF's conformance suite can see."** The four passing groups in
§2 mean something now, because the same instrument has been observed reporting
a failure, in the right place, on demand.

---

## 5. The four `response signature` failures, and who was wrong

The other four baseline failures are in `CHALLENGE_AUTH`:

```
6.2.7  6.3.7  6.12.7  6.13.7   -  FAIL response signature
```

The suite's case names encode the message mask each case uses. Reading them out
of `spdm_responder_test_6_challenge_auth.c` rather than guessing:

| | A | B |
|---|---|---|
| `A1` / `A2` | the Version-Capabilities-Algorithms exchange is re-sent / is not | |
| `B1` | | `GET_DIGESTS` **and** `GET_CERTIFICATE` |
| `B2` | | neither |
| `B3` | | `GET_DIGESTS` only |
| `B4` | | `GET_CERTIFICATE` only |

| case | mask | result |
|---|---|---|
| 6.1 `A1B1C1` | VCA + digests + certificate | PASS |
| 6.2 `A1B2C1` | VCA only | **FAIL** |
| 6.3 `A1B3C1` | VCA + digests | **FAIL** |
| 6.14 `A1B4C1` | VCA + certificate | PASS |

**The certificate fetch is necessary and sufficient.** `GET_DIGESTS` is
irrelevant: 6.14 omits it and passes, 6.3 performs it and fails.

### 5.1 The mechanism, from the source

Each case calls `libspdm_init_connection()` at the top of its per-slot loop
(`spdm_responder_test_6_challenge_auth.c:363`). That sends `GET_VERSION`, which
calls `libspdm_reset_context()`, which frees
`connection_info.peer_used_cert_chain[]` — including the chain the case's own
**setup** fetched thirty lines earlier at `:202`. A case whose mask then omits
`GET_CERTIFICATE` arrives at

```c
libspdm_verify_challenge_auth_signature(spdm_context, true, slot_id, sig, size)
```

with no peer certificate chain, and that function returns `false` at its first
step — `libspdm_x509_get_cert_from_cert_chain` on an empty buffer — before any
signature arithmetic happens.

That is a story, and this repository is unkind to stories: standing rule 19
exists because a very plausible one about two masking defects was wrong until
somebody ran the check.

### 5.2 So the signature was checked independently

[`harness/challenge_verify.py`](../harness/challenge_verify.py) takes the bytes
off the wire, rebuilds the transcript the signature covers, and hands the
arithmetic to OpenSSL. It implements no cryptography — the division is
`certs/check_chain.py`'s, in that file's words: *this file owns structure and
OpenSSL owns cryptography*. What it implements is a concatenation:

```
M1M2 = A || B || C
  A = GET_VERSION VERSION GET_CAPABILITIES CAPABILITIES NEGOTIATE_ALGORITHMS ALGORITHMS
  B = the digest and certificate exchanges, if any
  C = CHALLENGE, and CHALLENGE_AUTH up to but not including its signature
```

and for SPDM 1.0 and 1.1 the signature is `ECDSA(BaseAsymSel)` over
`Hash(BaseHashSel)(M1M2)` with no signing-context prefix
(`libspdm_asym_verify_ex`; the tool **refuses** a 1.2-or-later connection rather
than verifying the wrong bytes).

**It calibrates before it answers.** A tool that verifies a signature nobody
disputes proves nothing about the one that is disputed, so every run does both,
and the disputed verdict is offered only if the undisputed one came out right:

```
calibration -- connections that DID fetch the certificate, which the suite passes
  9 of 9 verify
    packet 204   SPDM 1.1 slot 0  ECDSA_P384/SHA_384  M1M2 2041 B (144+1775+122)  -> True
  ok   the transcript model reproduces a signature the suite accepts

disputed -- connections that did NOT fetch the certificate, which the suite fails
  2 of 2 verify
    packet 284   SPDM 1.1 slot 0  M1M2  266 B (144+   0+122)  -> True
    packet 306   SPDM 1.1 slot 0  M1M2  370 B (144+ 104+122)  -> True
```

The `B` column is the finding in one number: 1,775 bytes of certificate exchange
in the cases that pass, **0** and **104** in the two that fail — and the
signatures over those shorter transcripts are good.

> ### The verdict
>
> **The responder's `CHALLENGE_AUTH` signatures are valid. The suite reports
> FAIL because its own test case discarded the certificate chain it needed to
> verify them.**
>
> The device is not at fault, and neither is the specification. This is
> [upstream candidate 19](upstream/README.md), and it is the strongest one this
> project has: a conformance suite reporting a conforming device as
> non-conforming, with the proof attached.

### 5.3 The classification, which is the point of the exercise

| # | assertion | phenomenon | root cause | **behaviour wrong, or capability/configuration?** |
|---|---|---|---|---|
| 1 | `6.2.7` `6.3.7` `6.12.7` `6.13.7` | `response signature` FAIL | the test case's own `libspdm_init_connection` frees the chain its setup fetched; the mask does not re-fetch it | **neither — the test is wrong**, proved in §5.2 |
| 2 | `8.1.4` `8.2.4` `8.7.4` `8.8.4` | `mut_auth_requested - 0x02` | `spdm_responder_emu` sets `--mut_auth W_ENCAP` by default, and `libspdm_rsp_key_exchange_rsp.c:552` gates on the **responder's** `MUT_AUTH_CAP` and on the requester's `ENCAP_CAP`, consulting the requester's `MUT_AUTH_CAP` only on the mandatory path | **capability enabled by configuration.** DSP0274 1.4.0 defines the bit as a declaration of support and shows the mutual-authentication flow requiring **both** endpoints to set it, but carries no explicit prohibition in the `KEY_EXCHANGE_RSP` field description. One flag clears it |
| 3 | groups 9, 12, 13, 16 — 27 `NOT_TESTED` | four groups record nothing | every one needs a session, and `KEY_EXCHANGE` aborts at #2 | **downstream of #2.** Clearing the bit runs all four — §3 |
| 4 | `6.15.0`–`6.18.0` — 24 `NOT_TESTED` | `first challenge failure` | the `A2` cases do **not** re-send VCA, so the connection has no negotiated state when `CHALLENGE` is sent | **test-design**, and the same family as #1 |
| 5 | cases 2.7, 3.8, 5.6 | `- skipped` | implemented by the suite, absent from `spdm-emu`'s configuration array | **configuration**, §2.1 — and the only two 1.3 cases in the suite |
| 6 | case 5.5 | no output at all | registered by the configuration, absent from the library | **configuration**, §2.1 |

★ **Two of the six are the responder's configuration and none of the six is the
responder behaving incorrectly.** That sentence is only worth saying because
§4 established that this suite reports failures when there are failures.

---

## 6. What this report does not say

- **Not that the responder conforms to SPDM.** It conforms to the assertions in
  twelve implemented groups, at the versions those cases select, which top out
  at **1.2** in the shipped configuration. Nothing here exercises 1.3 or 1.4.
- **Not that the suite is wrong in general.** One defect was found and proved.
  Seventy of its seventy-three implemented cases ran and the device satisfied
  every assertion they made.
- **Not that passing is security.** Every input here was written down in
  advance by somebody who wanted the device to work.
- **Not that `NOT_TESTED` is harmless.** In the shipped configuration, 55
  assertions and four entire groups did not execute. A reader who takes
  `1077 PASS, 8 FAIL` at face value is reading a report on two thirds of a
  suite.

---

## 7. Reproducing it

```bash
bash harness/run_validator.sh                 # all four arms, about four minutes
bash harness/run_validator.sh --only caps-default

# the suite's configuration against the suite's own implementation
python3 harness/validator_report.py --audit-config \
    "$LAB_DIR/work/spdm-emu-pqc/SPDM-Responder-Validator" \
    "$LAB_DIR/work/spdm-emu-pqc/spdm_emu/spdm_device_validator_sample/spdm_device_validator_config.c"

# the signature proof, from the committed capture
python3 harness/challenge_verify.py \
    bench/data/w10-validator-20260919T184429Z/caps-default.pcap

# every number above, re-derived from the committed test.log
python3 harness/check_claims.py

# and the instruments' own self-tests, which CI runs
python3 harness/validator_report.py --self-test
python3 harness/challenge_verify.py --self-test
```

`run_validator.sh` asserts three things and carries a non-zero status to the end
if any of them does not hold, **after** writing the manifest — because a failing
assertion is a finding whose evidence is the run directory, and exiting early
would leave that directory unattributed.

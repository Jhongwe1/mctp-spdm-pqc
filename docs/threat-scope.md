# Threat scope

> **This project performs protocol-level correctness validation. It is not a
> security assessment.**

**Status: the outline was published on day one and filled in on 2026-09-20**,
when G6 produced limits that could be described from evidence rather than from
intention. The day-one text is still here, unedited, above the sections added
since; a threat scope written at the end is written to fit the results, and
being able to compare the two versions in `git log` is the only defence
against that.

What week ten added is [§ The five layers](#the-five-layers-of-the-thing-this-project-is-built-on),
which is *libspdm's own* threat model rather than this project's, and
[§ What the implementation layer costs](#what-the-implementation-layer-costs),
which is where the fuzzing and coverage work lands.

## What this project can show

| Claim | How it will be evidenced | Gate |
|---|---|---|
| A handshake completes and yields a measurement | capture file plus a field-by-field decode | G1 |
| Modifying a device measurement changes the evidence on the wire | before/after captures, byte-level diff | G2 — **done**, [`tamper.md`](tamper.md) row 1 |
| Modifying a message **in flight** is rejected by the measurement signature | a proxy between the emulators, two arms — the signed content changed, and the signature changed — and CI fails if either stops being rejected | G2 — **done**, rows 2a and 2b |
| A verifier comparing against reference values rejects the modified evidence | policy input, policy, verdict, all in the repository | G3 — **done**, [`rats-pipeline.md`](rats-pipeline.md) Table 3: the device-side tamper of row 1 is judged FAIL and names the index. The rollback half is done too — an upgrade passes and a downgrade is refused under its own category, and the four cases that show the change moved exactly one verdict run in CI. What it still cannot see is a rollback that stays **above** the reference value, which is stated beside the result rather than here |
| That rejection keeps working | CI asserts the tampered case **fails** | G6 |
| Post-quantum algorithms cost N more bytes and M more round trips | captures under both, with the negotiated algorithm read back out of the capture rather than assumed | G4 |

## What this project cannot show

| Not claimed | Why not |
|---|---|
| That SPDM is secure | Cryptographic and protocol analysis is not attempted. This uses the reference implementation and observes it. |
| That `libspdm` is free of vulnerabilities | Reproducing the *class* of a published advisory is not auditing an implementation. |
| That an attacker could not defeat this | The tamper cases are ones the author constructed. An adversary chooses differently, and chooses last. |
| Anything about real hardware | Emulator throughout. Byte counts should transfer; timing does not, and no timing claim is made without saying where it was taken. |
| That the certificate chain is trustworthy | The chain is self-signed. It was described here as "trusted by configuration" until 2026-09-01, and that was **too generous**: `bench/data/w5-tamper-*/t3b_foreign` completes a full handshake against a chain rooted in a CA the requester was never provisioned with. libspdm detects it and returns `LIBSPDM_STATUS_VERIF_NO_AUTHORITY`, which is `SEVERITY_WARNING`, and `spdm_requester_emu` tests `LIBSPDM_STATUS_IS_ERROR`. So the configuration expresses a preference that this requester does not enforce. [`tamper.md` §8](tamper.md). |
| That "the certificate chain" is one thing | It is not, and 2026-08-31 measured how many. A single mutually-authenticating handshake here carries **four chain fetches under three distinct roots** — this project's on responder slot 0, upstream's `ecp384` root on responder slot 4, and upstream's `rsa3072` root for the requester, whose chain is selected by the separately negotiated `ReqAsym`. Anything said about "the chain" applies to one of the three unless it names which. **2026-09-01 added the half that was missing:** the requester provisions *two* `ecp384` roots, and slot 4's is neither of them. Counting the anchors on the wire is not the same question as asking which of them the verifier was given. |
| That firmware is unmodified *now* | `CHALLENGE` proves the device held the key when it signed. It says nothing about one second later. Continuous attestation is a different problem. |
| That measurements mean what they appear to mean | A measurement is a hash of whatever the device chose to hash. What is covered is a device design question, not a protocol one. |
| That a signed measurement is a *correct* measurement | Measured, not assumed: `bench/data/w5-tamper-*/t1_meas` changes one byte of the device's own measurement and the handshake completes with every signature verifying. SPDM authenticates the report; nothing in it compares the report against what the value should be. That comparison is the verifier's, needs reference values, and is G3 — **built 2026-09-12**, and it refuses that capture. What is still not claimed is that the comparison is *sufficient*: the reference values here were minted from a capture of the very device they appraise, so they cannot detect a device that was already wrong when the capture was taken, and two of the eight measurement blocks have no representation in the evidence format at all. [`tamper.md` §4](tamper.md), [`rats-pipeline.md` §1 and §4](rats-pipeline.md). |

## The one attacker this project does defend against, and how little that is

Added 2026-09-10, because rows 2a and 2b of Table 1 are the first result here
that is about an *adversary* rather than about a specification's boundary, and
an unqualified "tampering is detected" would be the most misleading sentence
this repository could produce.

**What is demonstrated.** A process on the path between requester and responder
changes one byte of a `MEASUREMENTS` response — once in the measurement record,
once in the signature — and both are rejected with
`LIBSPDM_STATUS_VERIF_FAIL`. That is an on-link attacker: an interposer, a
compromised switch, a re-flashed retimer. It touches no file on the device.

**What that is not.**

| Not claimed | Why not |
|---|---|
| That an on-path attacker cannot succeed | One byte was changed because one byte makes the result legible. An adversary changes as many as necessary, and would not stop at the ones that leave an error message. |
| That this says anything about an encrypted session | `harness/tamper_proxy.py` reads `ALGORITHMS` in the clear to size the signature, which is true of these arms because no session is established. Against a session it would see far less, and nothing here measures that case. |
| That the proxy is a realistic adversary | It is an adversary with an implausible amount of cooperation: it knows the message layout, refuses to act unless two equations close, and reports what it did. Those properties exist to make the experiment attributable and an attacker would want none of them. |
| That detection implies response | Rows 2a and 2b both print `80020001`. Nothing in that number says which of the two happened, and the two need completely different responses. Detection here is one bit; triage is not in the protocol. |

**And the row that is not defended at all** stays row 1: a measurement changed
at the device is signed by the device. No attacker model makes that detectable
by SPDM, which is the whole reason G3 exists.

## Assumptions inherited from the emulator

Recorded now because they are easy to forget once results exist.

1. **Requester and responder are both `spdm-emu`.** Interoperability with an
   independent implementation is not demonstrated. Running the upstream
   responder validator (G6) narrows this but does not close it.
2. **The transport is a TCP socket carrying MCTP-encoded messages**, not MCTP
   over I²C or PCIe. Framing overhead differs on a real bus.
3. **The device secret library is the sample one.** Its measurements are
   fixtures, not a hash of anything that was executed.
4. **Most keys are DMTF's**, generated by `make copy_sample_key` and **published
   in the upstream repository**. Nothing here demonstrates key protection.

   Since 2026-08-31 this is no longer uniform, and the shape of the exception is
   the point. Responder slot 0 serves a chain generated here, whose private key
   was made locally and is not committed. Responder slot 4 and the requester's
   own chain are still upstream's, because `--slot_count` moves the requester's
   slots rather than the responder's, and because libspdm's sample library
   selects a certificate directory from the *separately negotiated* `ReqAsym` —
   `rsa3072/`, which the staging step never touched.

   So a reader who assumes "they replaced the certificates" is wrong about two
   of three, and a *vendor* who assumes it about their own product is wrong in a
   way that leaves a published private key reachable in the direction nobody
   looked at. `harness/fields.py` reports `layout.distinct_root_hashes` so the
   count is checked rather than remembered.

## The five layers of the thing this project is built on

Everything above is about SPDM and about this project. This section is about
**`libspdm`**, because a protocol's threat model and an implementation's are
different documents, and the library ships its own: `doc/threat_model.md`, at
the commit in [`third_party/spdm-emu-pqc.pin`](../third_party/spdm-emu-pqc.pin).
It is reproduced here in its own terms rather than summarised, because the
column that matters is the one that is easy to paraphrase away.

| Layer | Component | **External input** | Threats it names |
|:--:|---|---|---|
| **1** | `(req)asymsignlib` / `psklib` — holds the private key and the PSK | **None** | information disclosure, elevation of privilege, tampering |
| **2** | `spdm_secured_message_lib` — DH secret, session keys, key update | cipher message to be decrypted (**malicious**) | information disclosure, elevation of privilege, tampering, **denial of service** |
| **3** | `spdm_common_lib` / `spdm_requester_lib` / `spdm_responder_lib` | received SPDM message (**malicious**) | tampering, denial of service |
| **4** | `SpdmTransportXxxLib` — MCTP, PCI DOE | received transport-layer message (**malicious**) | tampering, denial of service |
| **5** | device send/receive | hardware device I/O (**malicious**) | denial of service |

★ **The layering is by the trustworthiness of the external input, not by
abstraction.** Level 1 has no external input at all, which is why the threat
list there is about what leaks out rather than about what comes in; level 5 has
nothing *but* external input and can only be made to stop. The sizes of the
threat lists are the shape of the argument.

**Where this project has been, layer by layer:**

| Layer | What this repository has touched |
|:--:|---|
| 1 | nothing. The keys are DMTF's sample keys or generated here and not protected; see *Assumptions inherited from the emulator* above |
| 2 | nothing. No arm of any experiment here has ever established a secure session — `--exe_session NO_END` does not include `EXE_SESSION_KEY_EX`, and the captures carry no `KEY_EXCHANGE`. It took a fuzz corpus to make that visible: ten of seventeen responder fuzz targets could not be seeded from this project's own handshakes |
| 3 | **most of it.** The handshake walkthrough, the tamper points, the conformance run, and the fuzz corpus all live here |
| 4 | week nine — a real Linux MCTP link and a PCIe DOE mailbox, [`docs/transports.md`](transports.md) |
| 5 | nothing. Emulator throughout |

## What the implementation layer costs

The row above that matters most is level 3, because it is the one a device
exposes to a peer it does not control, and because **the protocol being correct
does not make its implementation correct**. Those are separate claims with
separate evidence, and conflating them is the most common way an attestation
story goes wrong.

**The two upstream projects are not in the same position, and saying so
precisely is worth more than saying it loudly.**

| | |
|---|---|
| **`libspdm`** | the protocol library. It ships **six families of AFL fuzz targets — about sixty-nine individual targets** — under `unit_test/fuzzing/`, a seed corpus of 69 directories and 81 files, an OSS-Fuzz configuration, and CI workflows for CodeQL and Coverity. Its security policy points at the [DMTF Security Issue Reporting Process](https://www.dmtf.org/securityissuereporting) |
| **`spdm-emu`** | the demonstration program. Its own `README.md` says, verbatim: *"This package is only the sample code to show the concept. It does not have a full validation such as robustness functional test and fuzzing test. It does not meet the production quality yet."* |

So "the reference implementation has no fuzzing" is false about the library and
true about the sample, and this project uses the sample for protocol flow and
the library for anything that is about robustness.
[`docs/negative-tests.md`](negative-tests.md) is what that produced: a corpus
comparison, a coverage figure, and a time-boxed run that found nothing, reported
as a result rather than as an absence.

**What is still out of scope here, named rather than implied:**

- **Memory safety of `libspdm`.** Reproducing the *class* of a published
  advisory is not auditing an implementation for it, and a few minutes of local
  fuzzing at eight executions per second is not either. The arithmetic is in
  `negative-tests.md` §3.
- **Anything at all about the crypto backend.** The fuzz build uses mbedtls
  because upstream's own fuzzing configuration does; every capture here was
  produced against libspdm's vendored OpenSSL 3.5.5. Two different binaries.
- **The FIPS vectors.** `test_spdm_fips` exists in 4.0 and **refuses to run**
  in a default build — `LIBSPDM_FIPS_MODE` is `0` in
  `include/library/spdm_lib_config.h:139`, and the test says
  *"test is valid only when LIBSPDM_FIPS_MODE is open"* rather than passing
  vacuously. That is good test design and it means this project has **not**
  exercised the known-answer vectors for the RNG that `GET_MEASUREMENTS` draws
  its nonce from. A predictable nonce is a replay defence that is not there,
  and nothing here has checked it.

> **If anything found here ever looked like a real vulnerability**, the route is
> the DMTF Security Issue Reporting Process above — not a public issue, not a
> commit message, and not a project write-up, until it is published. Nothing
> found so far is in that category: the two upstream findings this project has
> are a stale configuration array and a test case that discards its own input.

## The question this project exists to ask

A completed handshake proves that a measurement genuinely came from the device
holding a given key, and was not altered in transit. It does not prove the
measurement is the *right* value. Those are different claims, and only the
first one has a reference implementation.

Everything between them — where reference values come from, what "matches"
means, what a verifier does about a mismatch, and who acts on the answer — is
out of scope for SPDM and is where this project spends its effort.

The failure mode worth naming early is not a missed attack. It is a verifier
that treats every mismatch as an attack, produces false rejections during
ordinary firmware updates, and gets switched off by operators. A system that
has been switched off provides no security at all, and no amount of
cryptographic correctness prevents that outcome.

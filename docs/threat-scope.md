# Threat scope

> **This project performs protocol-level correctness validation. It is not a
> security assessment.**

**Status: outline.** This document is completed in G6, when there is a
verification pipeline whose limits can be described from evidence rather than
from intention. What is written below is what is already known on day one, and
it is deliberately weighted towards the right-hand column.

Publishing the outline now rather than the finished document later is the
point: a threat scope written at the end is written to fit the results.

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

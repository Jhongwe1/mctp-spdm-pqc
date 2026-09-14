# What post-quantum authentication costs on the wire

> **I did protocol-flow level correctness validation, not a security
> assessment.** Nothing here says whether ML-DSA-65 is *safe*. It says how many
> bytes and how many round trips it takes, measured on one implementation, and
> what had to be held still for that measurement to mean anything.

Gate 4, and this is the **first half**: two of six planned algorithm groups,
both measured, with the apparatus that the other four will reuse. Week 8 adds
ML-DSA-44 + ML-KEM-512, ML-DSA-87 + ML-KEM-1024, ECDSA-P521 and a
Version-Capabilities-Algorithms-only arm. What is absent here is absent from
the repository rather than sketched in it.

Reproduce everything below with:

```bash
bash harness/run_pair.sh                    # four arms, about two minutes
python3 harness/check_claims.py             # every ratio, re-derived
python3 bench/pcapstat.py bench/data/w7-pqc-ab-20260914T073732Z/P2-all.pcap --check
```

---

## 1. What was compared, and at what security level

| arm | responder identity | key establishment | NIST level |
|:--|---|---|:--:|
| **A0** | ECDSA P-384 | ECDHE P-384 | 3 |
| **P2** | ML-DSA-65 | ML-KEM-768 | 3 |

The pairing is deliberate: comparing ML-DSA-65 against ECDSA P-256 would
measure a security-level change and call it a post-quantum cost. Both arms sit
at NIST category 3.

Each arm was run through **two measurement flows**, and §4 is why that is not
padding.

---

## 2. Table 2 — the measured cost

Run [`bench/data/w7-pqc-ab-20260914T073732Z`](../bench/data/w7-pqc-ab-20260914T073732Z),
2026-09-14, `spdm-emu` 4.0.0-rc / libspdm `8a92317`, `--meas_op ALL` unless a
row says otherwise. Every ratio below is re-derived by
`harness/check_claims.py` from these committed captures, and CI runs it.

| quantity | A0 · ECDSA-P384 | P2 · ML-DSA-65 | ratio |
|---|--:|--:|--:|
| responder slot 0 certificate chain | 1,655 B | 16,853 B | **10.18×** |
| total captured bytes, `--meas_op ALL` | 6,559 B | 58,966 B | **8.99×** |
| total captured bytes, `--meas_op ONE_BY_ONE` | 15,587 B | 93,698 B | **6.01×** |
| one signature (`CHALLENGE_AUTH`) | 238 B | 3,451 B | **+3,213 B** |
| `GET_CERTIFICATE` round trips | 3 | 3 | 1.00× |
| `CHUNK_RESPONSE` messages | 0 | 12 | — |

<!-- capture: bench/data/w7-pqc-ab-20260914T073732Z/A0-all.decode.txt -->
The classical chain is
<!--claim certificate.responder_slot0_bytes=1655-->1,655 bytes and the
negotiated identity algorithm is
<!--claim algorithms.negotiated.Asym=ECDSA_P384-->`ECDSA_P384`, with
<!--claim algorithms.negotiated.PqcAsym=-->no post-quantum algorithm selected
at all.
<!-- capture: bench/data/w7-pqc-ab-20260914T073732Z/P2-all.decode.txt -->
The post-quantum chain is
<!--claim certificate.responder_slot0_bytes=16853-->16,853 bytes, the
negotiated identity algorithm is
<!--claim algorithms.negotiated.PqcAsym=ML_DSA_65-->`ML_DSA_65`, key
establishment is <!--claim algorithms.negotiated.KEM=ML_KEM_768-->`ML_KEM_768`,
and <!--claim algorithms.negotiated.Asym=-->no classical signature algorithm
was selected.

**+3,213 bytes is the cleanest number in the table.** `CHALLENGE_AUTH` carries
exactly one signature, and the two arms' copies of that message differ in
nothing else — so the difference *is* the signature: ML-DSA-65 signs 3,309
bytes where ECDSA P-384 signs 96. The same +3,213 appears again in the
`MEASUREMENTS` response of the `ALL` flow, for the same reason.

---

## 3. Single-variable is a thing you prove, not a thing you intend

Eighteen flags are identical in every arm, and the list was read out of
`spdm_emu/spdm_emu_common/key.c` rather than out of `--help`. The defaults that
would otherwise have moved:

| default | value | what it would have done |
|---|---|---|
| `m_use_mut_auth` | `..._WITH_ENCAP_REQUEST` | mutual authentication ON |
| `m_use_basic_mut_auth` | `1` | and again, by a second route |
| `m_support_req_asym_algo` | four RSA algorithms | requester authenticates with RSA-PSS 3072 |
| `m_support_req_pqc_asym_algo` | ML-DSA 44, 65 and 87 | responder picks one of three for the requester |
| `m_use_slot_count` | `3` | `DIGESTS` grows with the slot count |
| `m_support_hash_algo` | SHA-384, SHA-256 | negotiated hash not determined by the flags |
| `m_support_measurement_hash_algo` | SHA-512, 384, 256 | measurement block size not determined either |
| `m_support_dhe_algo` | four groups | |
| `m_support_aead_algo` | two suites | |
| `m_support_other_params_support` | two bits | opaque data format |

Left alone, **both** arms would carry a requester RSA-3072 certificate chain
the experiment never asked for. In the 2026-08-28 baseline that chain is 4,460
bytes of `DELIVER_ENCAPSULATED_RESPONSE` — 22% of the capture. It is identical
in both arms, so it cannot corrupt a *difference*; it dilutes every *ratio*,
and a reader asking "where did that RSA come from" would have had no answer.

**The proof that it worked is the per-message-type table, not the flag list.**
Every message that is not the experiment is byte-identical across the two arms:

| message | A0 | P2 |
|---|--:|--:|
| `SPDM_NEGOTIATE_ALGORITHMS` | 48 | 48 |
| `SPDM_ALGORITHMS` | 52 | 52 |
| `SPDM_GET_CAPABILITIES` / `SPDM_CAPABILITIES` | 20 / 20 | 20 / 20 |
| `SPDM_GET_DIGESTS` / `SPDM_DIGESTS` | 12 / 300 | 12 / 300 |
| `SPDM_GET_CERTIFICATE` | 48 | 48 |
| `SPDM_CHALLENGE` | 44 | 44 |
| `SPDM_GET_MEASUREMENTS` | 45 | 45 |
| `SPDM_DELIVER_ENCAPSULATED_RESPONSE` | absent | absent |

`bench/data/w7-pqc-ab-*/A0-all.cmdline.txt` and `P2-all.cmdline.txt` are the
command lines as they ran, and `harness/run_pair.sh` prints their diff at the
end of every run. Those two lines are the independent variable.

### And the flag is not the negotiation

> **"I passed that flag" and "both sides agreed on that algorithm" are two
> different events.** A responder that cannot do what was asked does not fail
> the handshake — it selects something else. A table built from the flags would
> then be wrong with no symptom anywhere.

So every arm **declares** what it expects to be negotiated, in all twelve
groups, and `harness/run_pair.sh` reads the `ALGORITHMS` response back through
`harness/fields.py` and **refuses the run** when they differ. The declaration
is written out independently of the flags rather than derived from them;
deriving it would compare the flags with themselves.

It is also checked twice by different routes:
`bench/pcapstat.py --check` parses the `ALGORITHMS` message's own bytes and
requires `fields.py`, which parses `spdm_dump`'s rendering of the same message,
to agree — `docs/roadmap.md` standing rule 12. Neither tool sees the other's
input.

---

## 4. ★ The same A/B, measured two ways, gives 8.99× and 6.01×

This is the finding that changes how the rest of the table should be read.

`--meas_op ONE_BY_ONE` is `spdm-emu`'s default and walks every measurement
index from 1 to 0xFE. The classical arm's two flows differ by **9,028 captured
bytes — 58% of the `ONE_BY_ONE` total** — and that difference is 263
`GET_MEASUREMENTS` requests, 246 `ERROR` responses for indices that do not
exist, sixteen extra `MEASUREMENTS` responses and the MCTP framing of all of
them. Every byte of it is identical in the post-quantum arm except the
signatures, which §4's second half is about.

Its effect on the two ways of stating a result is opposite:

|  | `--meas_op ALL` | `ONE_BY_ONE` |
|---|--:|--:|
| difference, P2 − A0 | +52,407 B | +78,111 B |
| ratio, P2 ÷ A0 | 8.99× | 6.01× |

A constant added to both sides leaves a difference alone and pulls a ratio
toward 1. So the **ratio is diluted by the flow**, which is why both are
published with the flow named.

But the difference is not constant either, and that is the second half of the
finding: **+78,111 is not +52,407 plus a constant.** `ONE_BY_ONE` makes the
responder sign **nine times** instead of once, and `MEASUREMENTS` grows by
28,917 bytes — which is exactly 9 × 3,213. The post-quantum signature cost is
not paid once per handshake; it is paid once per signed response, and the flow
decides how many of those there are.

> **The lesson is the general one.** A cost ratio is a property of a workload,
> not of an algorithm. Quoting "post-quantum SPDM is N× bigger" without naming
> the flow it was measured over is a number nobody can check and nobody can
> reproduce — and the two numbers here differ by half.

---

## 5. ★ The chain does not arrive in `CERTIFICATE` at all

The negotiated `DataTransferSize` is
<!--claim capabilities.responder.data_transfer_size=4608-->4,608 bytes on both
sides, and the post-quantum chain is 16,853. So the responder cannot answer
`GET_CERTIFICATE` with the chain: it answers with `ERROR(0x0F, LargeResponse)`,
and the requester fetches the message through SPDM's **chunking** layer —
<!--claim chunking.chunk_response_count=4-->4 `CHUNK_RESPONSE` messages in the
part of this capture that `spdm_dump` decodes, and 12 in the capture itself.

Three consequences worth stating:

1. **`GET_CERTIFICATE` round trips are 3 in both arms.** A reader expecting the
   post-quantum chain to cost more round trips at the certificate layer is
   wrong; it costs them at the chunking layer instead. The count that moved is
   `CHUNK_RESPONSE`: 0 against 12.
2. **`bench/pcapstat.py` reports zero chains for the post-quantum arms**, and
   says why. Its chain walk reads `CERTIFICATE` responses, and every byte of
   this chain is in a message type it does not reassemble. The bytes are in the
   capture; they are not in `SPDM_CERTIFICATE`. Reassembling them is week 8.
3. **The chain length still comes off the wire**, from the `LargeMessageSize`
   and portion-length fields that arrive before any of this, which is why
   16,853 is a measurement rather than an estimate.

### The decode is truncated, and that is not the handshake being short

`spdm_dump`'s `LIBSPDM_MAX_CERT_CHAIN_SIZE` is a **compile-time constant**, and
it stops the decoder partway through the post-quantum arm: the decode accounts
for 13,365 of 58,736 SPDM bytes, **22.8%**. The handshake completed. The
requester exited 0. Every signature verified.

`bench/pcapstat.py --check` prints the shortfall instead of demanding that a
prefix equal a whole, and `harness/fields.py --check` now says
`this decode is TRUNCATED` beside every capture it checks claims against —
because the same decode answers some questions correctly and others with a
prefix. A chain length read from a length field is right; a running byte total
is short by whatever the decoder never reached. Both are checkable, and only
one of them belongs in a table.

---

## 6. What this cost in tooling, and one upstream finding

`plan/W07` specified `--req_asym NONE --req_pqc_asym NONE` to switch mutual
authentication off. **That pair makes the handshake impossible on this build**:
six packets, and `ERROR: libspdm_init_connection - 0x8001000a` with nothing
naming a flag. The responder answers `NEGOTIATE_ALGORITHMS` with
`ERROR(0x01, InvalidRequest)`.

The reason is in
`libspdm/library/spdm_responder_lib/libspdm_rsp_algorithms.c`:

```c
if (MUT_AUTH_CAP is mutually supported || requester advertises EP_INFO_CAP_SIG) {
    algo_size     = libspdm_get_req_asym_signature_size(req_base_asym_alg);
    pqc_algo_size = libspdm_get_req_pqc_asym_signature_size(req_pqc_asym_alg);
    if (((algo_size == 0) && (pqc_algo_size == 0)) ||
        ((algo_size != 0) && (pqc_algo_size != 0))) {
        return INVALID_REQUEST;      /* exactly one, never zero, never both */
    }
}
```

`--mut_auth` and `--basic_mut_auth` are **flow policy**. They do not clear
`MUT_AUTH_CAP` or `EP_INFO_CAP_SIG` out of `m_use_requester_capability_flags`,
and both are set by default — which this project's own capture confirms rather
than assumes: `fields.py` lists both in the requester's advertised flags.

So the requester's own signature algorithm is **pinned** rather than removed,
to the same classical value in every arm. Nothing signs with it — the captures
carry no encapsulated exchange and zero requester chain bytes, which
`harness/lib/check_negotiated.py` asserts per arm — and the only thing it puts
on the wire is one 4-byte `AlgStructure` entry that is byte-identical in all
four arms.

This is upstream candidate 6: a flag combination the parser accepts, the
documentation does not warn about, and the failure for which names no flag.
[`docs/upstream/README.md`](upstream/README.md).

---

## 7. What this does not measure

Beside the result, not after it.

- **Two algorithm groups of six.** ML-DSA-44, ML-DSA-87, SLH-DSA and
  ECDSA-P521 are week 8. A curve drawn through two points is a line by
  construction.
- **One implementation, one build, one host.** Every number is libspdm
  4.0.0-rc's behaviour with OpenSSL as the crypto backend. A different backend
  would produce different certificate DER and could produce different chain
  sizes for the same algorithm.
- **Bytes and round trips, never time.** Nothing here is a latency measurement,
  and nothing here should be read as one. Byte counts are deterministic under
  fixed flags, which is why `bench/claims.json` asserts them with a tolerance
  of exactly zero; a timing number would arrive with a median, a p95 and a
  stated number of runs, and none is published.
- **The certificate chains are DMTF's samples**, not this project's own. The
  `certs/` chain is three layers of ECDSA P-384 and has no post-quantum
  counterpart, because the system OpenSSL is 3.0.13 and cannot sign ML-DSA.
  What is compared is therefore two *sample* chains that upstream generated the
  same way, which is the right comparison for an algorithm cost and the wrong
  one for a claim about any particular vendor's PKI.
- **`DataTransferSize` is the emulator's default.** Raise it above 16,853 and
  the chunking in §5 disappears while the byte total barely moves. The
  threshold is a property of the transport, not of the algorithm, and it is
  recorded in every capture's `CAPABILITIES` rather than assumed.

---

*Every ratio in §2 is re-derived from the captures it names by
`harness/check_claims.py`, and every single-capture number is re-derived by
`harness/fields.py --check`. Both run in CI. A number here that drifts from its
capture is a failed build.*

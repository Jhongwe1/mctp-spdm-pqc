# certs

This project's own three-layer certificate chain — root → intermediate → leaf —
the scripts that build it, and the checker that reads it out of its DER.

```bash
bash certs/gen_chain.sh              # build one (refuses to overwrite)
python3 certs/check_chain.py certs/out
python3 certs/check_chain.py certs/out --self-test
bash certs/stage_chain.sh pqc        # put it where an emulator will find it
```

## Why not the sample chain

`make copy_sample_key` already produced a working chain, and for a handshake
that is enough. It is not enough for Gate 2, whose third tamper point is *alter
the intermediate certificate and require the handshake to fail*. Doing that
properly needs the intermediate's private key: without it the only available
tampering is corruption, and corruption and forgery produce different failures.
The one worth demonstrating is the one an attacker could actually attempt.

## What is committed and what is not

| | committed | why |
|---|:--:|---|
| `out/*.cert`, `out/*.cert.der` | yes | certificates are public, and they are the evidence every published byte count refers to |
| `out/*.certchain.der` | yes | the exact bytes the responder serves |
| `out/*.key` | **no** | `.gitignore` excludes them, and `verify_repo.sh` greps every tracked file for a private-key header rather than trusting the pattern — because the pattern already missed one spelling |

The consequence is stated rather than worked around: a fresh clone can check the
committed chain and the committed captures, but cannot take a *new* capture with
this chain, because it has no private key. It has to generate its own with
`gen_chain.sh --force`, which produces different certificates — fresh keys, and
an ECDSA signature whose DER length depends on whether its integers happen to
have a leading zero. RUNBOOK §8.7 says so where someone will read it.

## The two device-identity OIDs

The leaf carries two `otherName` entries in its `subjectAltName`, and they come
from different specifications:

| OID | From | Content | Verified |
|---|---|---|:--:|
| `1.3.6.1.4.1.412.274.1` | DSP0274 1.4.0 §425, `id-DMTF-device-info` | `Manufacturer:Product:SerialNumber` | **yes** — against the specification PDF |
| `2.23.147` | `plan/W03` §2.2, attributed to PCIe r6.1 §6.31.3 | `Vendor=…:Device=…:CC=…:REV=…:SSVID=…:SSID=…` | **no** — that specification is behind PCI-SIG membership |

What *was* checked about the second one is that the string `2.23.147` appears
zero times in DSP0274 1.4.0 and zero times in the pinned `libspdm` and
`spdm-emu` trees. Nothing in this project's toolchain reads it,
requires it, or would notice if it were wrong. It is carried because W09's QEMU
path is said to need it and it costs nothing now, and it is labelled as
unverified everywhere it appears.

The leaf also carries `id-DMTF-hardware-identity` (`1.3.6.1.4.1.412.274.2`)
inside `id-DMTF-spdm-extension` (`…274.6`), copied from the reference
implementation's own leaf. DSP0274 §10.9.2.2.1 defines it as the marker for
which certificate in a chain is bound to the hardware.

Full reasoning, and the diagram of who holds which private key, are in
[`docs/certchain.md`](../docs/certchain.md).

## Why the checker parses DER

The obvious check is `openssl x509 -text | grep -A3 'Subject Alternative Name'`,
and it answers a weaker question than it looks like it does: it asks whether
OpenSSL's *pretty-printer* mentioned a string. It cannot distinguish a critical
extension from a non-critical one, cannot say which of two `otherName`s holds
which OID, and cannot notice a mis-encoded OID, because the printer decodes the
bytes and a wrong OID prints as a different right OID.

So `check_chain.py` walks the certificate's own DER down to the extensions and
matches on encoded OID bytes. It owns structure; `openssl verify` owns
cryptography; where both can reach the same fact they are made to agree. The
same division the rest of this repository uses.

`--self-test` breaks the chain four ways — an altered identity OID, a reordered
bundle, a bundle one byte short, an altered signature — and requires each to be
rejected **by a different check**. Four rejections through three checks would
mean one of them had still never done anything, and for one commit that was
exactly the case: the byte-comparison against the individual certificates ran
before the DER walk and caught everything the walk would have. Swapping the two
gave each of them something only it can find.

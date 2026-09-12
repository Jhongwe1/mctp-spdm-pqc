# Change 0001 — `CoRimTool.py verify` does not verify

- **Repo:** `DMTF/spdm-emu` (GitHub pull request)
- **File:** `spdm_emu/spdm_device_verifier_tool/CoRimTool.py`, two lines in one
  function
- **Status:** **prepared, not submitted.** The branch and the commit exist;
  sending it is the author's keystroke, on the author's account.
- **Found:** 2026-09-12, by running the tool's own published example verbatim
  before connecting anything of this project's to it.
- **Branch:** `$LAB_DIR/work/spdm-emu-pr`, `corim-verify-public-key`, on top of
  upstream `main` at `ea77f25`.

---

## 0. Why two lines and not one

The first version of this change was one line, committed, signed off, and one
keystroke from being sent. It fixed the key construction, and **it would have
converted a verifier that accepts nothing into a verifier that accepts
anything.**

The second line was found by writing a script to re-run the `Tested:` claims of
the commit message that was already written. The claim *"a corrupted signature
is still refused"* was false: with the key repaired and the result still
discarded, flipping one byte of the signature printed **Signature verification
passed** and wrote the payload.

That is the reason the two are one change, and it is worth stating in the pull
request rather than leaving a reviewer to work out why a "one-line fix" has two
lines in it.

---

## 1. The commit

Subject ≤ 50 characters, body wrapped at 72, `Tested:` describing what was
actually run, `Signed-off-by:` in the legal name that matches the account.

```
CoRimTool: make verify actually verify

VerifySignedCbor does not verify a signature.  Two lines, and they mask
each other, so the tool looks fail-closed while being one fix away from
fail-open.

The key.  VerifyingKey.to_string() returns the public point x||y, 64
bytes on P-256, and it is passed as d=, the private scalar:

    key = VerifyingKey.from_pem(f.read()).to_string()
    cose_key = EC2Key(crv='P_256', d=key)

EC2Key raises ValueError("Invalid EC key"), the surrounding except
catches it, and the tool prints "Signature verification failed" -- for
a signature nothing looked at.  SignCbor three lines above does the
same construction correctly, because a SigningKey's to_string() really
is d.  So the verify step of the flow in readme.md cannot succeed, on
any input, with any key.

The result.  Sign1Message.verify_signature() RETURNS a bool; it does
not raise on a bad signature.  Its return value is discarded, so with
the key repaired, an invalid signature reaches the payload write and
"Signature verification passed".

Measured on the sample data, with the key line repaired and this one
not: flipping the last byte of the 64-byte signature still prints
"Signature verification passed" and still writes the 996-byte payload.

They are one change because fixing either alone is worse than fixing
neither: the first alone turns a verifier that accepts nothing into one
that accepts everything.

Tested: ... (see §5)

Signed-off-by: Chung-Wei Lan <zwwe1f@gmail.com>
```

The committed message carries the full `Tested:` block; it is reproduced in §5
rather than twice.

## 2. The diff

```diff
--- a/spdm_emu/spdm_device_verifier_tool/CoRimTool.py
+++ b/spdm_emu/spdm_device_verifier_tool/CoRimTool.py
@@ -206,10 +206,11 @@ def VerifySignedCbor(FilePath, Key, Algorithm, Payload):
         with open(Key, 'rb') as f:
             key = VerifyingKey.from_pem(f.read()).to_string()
 
-        cose_key = EC2Key(crv='P_256', d=key)
+        cose_key = EC2Key(crv='P_256', x=key[:len(key) // 2], y=key[len(key) // 2:])
         cose_msg.key = cose_key
 
-        cose_msg.verify_signature(Algorithm)
+        if not cose_msg.verify_signature(Algorithm):
+            raise ValueError('signature does not verify')
     except Exception:
         print("Signature verification failed")
         exit()
```

`3 insertions(+), 2 deletions(-)`, one file. The `raise` reuses the function's
existing error path rather than adding a second one, so the failure message and
the "no output file" behaviour are unchanged.

> ⚠ The file has **CRLF** line endings. The patch must preserve them or the
> diff is the whole file. Verified after applying: 392 CRLF, 0 bare LF.

## 3. What is deliberately NOT in this change

- **`exit()` on failure is status 0.** A shell cannot tell a verified manifest
  from a rejected one. Real, separate subject — "report the verdict to the
  shell" is not "make the verification correct" — and offered in the pull
  request as a follow-up rather than bundled.
- **`requirements.txt` has no upper bound on `cbor2`.** A different decision
  and a maintainer's call. Named in the pull request with the exact workaround,
  because without it a reviewer cannot observe this fix at all.
- Four further defects in the same directory, recorded in
  [`README.md`](README.md) with their reproductions.

## 4. The pull-request body

> ### `CoRimTool.py verify` does not verify
>
> The verification step of the example in
> `spdm_emu/spdm_device_verifier_tool/readme.md` fails on the sample data that
> ships beside it. Two lines are involved and they mask each other, so I have
> fixed both in one change — fixing either alone leaves the tool in a worse
> state than it is now. Details below.
>
> **The key.** `VerifySignedCbor` builds the COSE key as
>
> ```python
> key = VerifyingKey.from_pem(f.read()).to_string()   # the public point, x||y
> cose_key = EC2Key(crv='P_256', d=key)               # d= is the private scalar
> ```
>
> `EC2Key` raises `ValueError: Invalid EC key (key out of range, infinity,
> etc.)`, the enclosing `except Exception` catches it, and the tool prints
> `Signature verification failed`. `SignCbor` a few lines above does the
> equivalent construction correctly, with a `SigningKey`, whose `to_string()`
> really is `d`.
>
> **The result.** `Sign1Message.verify_signature()` is documented as returning
> `True` for a valid signature and `False` for an invalid one — it returns
> rather than raising — and its return value is discarded. With the key repaired
> and this line left alone, I flipped the last byte of the 64-byte signature in
> the sample manifest and the tool printed `Signature verification passed` and
> wrote the payload. So the two go together: on its own, the key fix turns a
> verifier that accepts nothing into one that accepts anything.
>
> I confirmed the signed file itself is sound before touching the verifier, by
> checking the signature with `ecdsa` over the COSE `Sig_structure`
> `["Signature1", protected, b"", payload]`; it verifies.
>
> **Reproducing this needs one unrelated workaround**, and I have deliberately
> not folded it into this change. `requirements.txt` sets no upper bounds, and
> `cbor2 >= 6.0` decodes the contents of a `CBORTag` as immutable containers
> (`tuple` / `FrozenDict`), while `pycose`'s `CoseMessage.decode` requires
> `list`. On a fresh install today, pycose cannot decode its own `encode()`
> output. Pinning `cbor2==5.6.5` puts that aside so this fix is observable:
>
> ```bash
> cd spdm_emu/spdm_device_verifier_tool
> pip install -r requirements.txt && pip install 'cbor2==5.6.5'
> python3 CoRimTool.py json_to_cbor -i SampleManifests/SpdmSampleCoMid.json -o /tmp/s.cbor
> python3 CoRimTool.py sign   -f /tmp/s.cbor   --key SampleTestKey/ecc-private-key.pem \
>                             --kid 11 --alg ES256 -o /tmp/s.corim
> python3 CoRimTool.py verify -f /tmp/s.corim --key SampleTestKey/ecc-public-key.pem \
>                             --alg ES256 -o /tmp/out.cbor
> ```
>
> Before: `Signature verification failed`, and `/tmp/out.cbor` is not written.
> After: `Signature verification passed`, 996 bytes recovered, and
> `cbor_to_json` → `SpdmMeasurement.py` → `OpaTool.py` →
> `opa eval --v0-compatible` run through to `SPDM_HASH_CHECK: true`.
>
> Flip one byte of `/tmp/s.corim` and `verify` now reports `failed` and writes
> nothing.
>
> Two further things I found while doing this and have left out of this change,
> happy to open either as a separate issue or PR if useful:
>
> - `verify` calls bare `exit()` on failure, which is status 0, so a shell
>   cannot distinguish a verified manifest from a rejected one;
> - the `cbor2` bound above.
>
> Found while building an SPDM attestation pipeline on top of these tools.

## 5. The `Tested:` lines, and the run behind each one

Every line below was executed against the branch, not against a scratch copy,
by `harness`-style script rather than by hand. `rats/interop.sh` now re-runs the
key ones on every interoperability run.

| claim | run | result |
|---|---|---|
| before: verify fails | stock `CoRimTool.py`, sample data | `Signature verification failed`, no output file |
| after: verify passes | branch, same data | `Signature verification passed`, 996-byte payload |
| the rest of the flow runs | `cbor_to_json`, `SpdmMeasurement.py`, `OpaTool.py`, `opa eval --v0-compatible` | 4312 / 1082 / 5779 bytes, then `SPDM_HASH_CHECK: true`, `SPDM_SVN_CHECK: true`, `error_code: 0` |
| a forged signature is refused | last byte of the signature flipped | `failed`, no output file |
| …and accepted with only the key fixed | half-patched copy, same input | **`passed`, 996 bytes** — the reason this is one change |
| an independent signer is accepted | manifest signed by `rats/cose.py` over the same payload | `Signature verification passed` |

## 6. The checklist, before sending

```
☐ target repo's CI is green on main
☑ subject <= 50 characters, "component: summary"
☑ body wrapped at 72, says WHY and not only what
☑ Tested: lines, each one actually run — and re-run after the change grew
☑ Signed-off-by, legal name, matching the account
☑ exactly one logical change, with the evidence for why the two lines are one
☑ diff reviewed line by line, CRLF preserved (392 CRLF, 0 bare LF)
☑ no prior issue or PR covers it — searched DMTF/spdm-emu for "CoRimTool"
   and "EC2Key" on 2026-09-12: 0 results each. RE-CHECK ON THE DAY.
☑ not a new feature, so no prior discussion is expected
   (DMTF takes documentation and fixes directly)
☐ decide the channel. Public PR, on the reasoning in README.md ② — the
   fail-open is not reachable in shipping code, because the key defect
   means the tool accepts nothing. If that reasoning is wrong, the
   channel is DMTF's security reporting process instead.
```

## 7. Sending it

The branch is prepared and the commit is made. What remains is a fork and a
push, and both are the author's:

```bash
LAB=${LAB_DIR:-$HOME/spdm-lab}
cd "$LAB/work/spdm-emu-pr"

git log -1                              # read the message once more
git show HEAD                           # and the diff, once more

gh repo fork DMTF/spdm-emu --remote=false --clone=false   # or fork in the web UI
git remote add fork git@github.com:<your-account>/spdm-emu.git
git push fork corim-verify-public-key
# then open the PR with the body from §4
```

Fill in §8 and the `README.md` status table **on the same day**: a URL recorded
a week later is a URL nobody can attach to a reviewer's first comment.

## 8. After it is sent

```
- URL:
- Opened:
- CI result:
- Review round trips:
    Patchset 1 -> <reviewer> said <what>
    Patchset 2 -> I changed <what>, because <why>
- What I learned from this review, specifically:
- Outcome: merged / changes requested / closed (why)
```

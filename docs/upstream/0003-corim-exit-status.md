# Change 0003 — `CoRimTool.py` exits 0 when a command fails

- **Repo:** `DMTF/spdm-emu` (GitHub pull request)
- **File:** `spdm_emu/spdm_device_verifier_tool/CoRimTool.py`, two lines
- **Status: PREPARED, NOT SENT, 2026-09-29.** The commit is unsigned; the
  sign-off and the push are the author's (§6).
- **Found:** 2026-09-12, as ⑤ of the seven findings in the same directory
  ([`README.md`](README.md)), and offered as a follow-up in the description of
  [#524](https://github.com/DMTF/spdm-emu/pull/524), which merged on 2026-09-28
  without anyone answering the offer.
- **Branch:** `$LAB_DIR/work/spdm-emu-pr`, `corim-exit-status`, commit
  `1a396c2`, on upstream `main` at `eff07cf` (the `4.0.0-rc2` tag).

## 0. Why this one next, and why alone

It is the smallest change that follows from the one that was accepted: same
file, same maintainers, the same shell pipeline a reader of #524 would build.
And it is still true after #524: at `eff07cf` a forged signature prints
`Signature verification failed` and exits **0**.

Two bare `exit()` calls are the whole defect, and both are failure paths —
`verify` on a bad signature, and `json_to_cbor` on a tagged key it cannot split.
Every other failure in the file raises an exception and ends with status 1, so
the change makes the file agree with itself rather than inventing a convention.

Not in it, on purpose: the `cbor2` upper bound (①), the round-trip defect in
`json_to_cbor` (③), the hard-coded names in `translate_data` (④) and the Rego v0
policy (⑥). Each is a separate decision, and three of them are a maintainer's.

## 1. The commit

```
CoRimTool: exit non-zero when a command fails

Two failure paths in CoRimTool.py end in a bare exit(), which is status
0: verify, when the signature does not verify, and json_to_cbor, when a
tagged key cannot be split.  Every other failure in the file raises an
exception and so ends with status 1.

A script that runs "CoRimTool.py verify ... && <next step>" therefore
continues after "Signature verification failed", and only the text on
stdout says that the manifest was rejected.  Exit with 1 on both paths,
as the rest of the file already does.

Tested: sample manifest, json_to_cbor -> sign -> verify: "Signature
        verification passed", 996-byte payload, exit 0, as before.
Tested: last byte of the signature flipped: "Signature verification
        failed", no payload written, exit 1 (was 0).
Tested: json_to_cbor on the sample manifest plus a key "bogus tagged":
        "No '_' found in key as separator with tag", no output, exit 1
        (was 0).
Tested: verify on a missing file still raises and exits 1.

Assisted-by: Claude Code:claude-opus-5-5
```

`Signed-off-by` is absent until the author adds it (§6).

## 2. The diff

```diff
@@ translate_data
                         except Exception:
                             print("No '_' found in key as separator with tag")
-                            exit()
+                            exit(1)
@@ VerifySignedCbor
     except Exception:
         print("Signature verification failed")
-        exit()
+        exit(1)
```

`2 insertions(+), 2 deletions(-)`. The file is CRLF, and the commit keeps it so:
392 CRLF lines, 0 bare LF, checked after the edit.

## 3. The `Tested:` lines, and the run behind each

Run on 2026-09-29 against a copy of the tool at upstream `main` (**before**) and
at the branch (**after**), with the virtualenv this project already uses for the
tool (`cbor2 5.6.5`, `pycose 1.1.0`):

| case | before | after |
|---|---|---|
| sample manifest, `json_to_cbor` → `sign` → `verify` | passed, 996 bytes, **0** | passed, 996 bytes, **0** |
| last byte of the signature flipped | failed, nothing written, **0** | failed, nothing written, **1** |
| `json_to_cbor` with a key `"bogus tagged"` | *No '_' found…*, nothing written, **0** | the same, **1** |
| `verify` on a file that does not exist | raises, **1** | raises, **1** |

And one run that belongs in the pull request because a reviewer will meet it:
**a fresh virtualenv from `requirements.txt` today still resolves `cbor2` 6.1.4,
and `verify` then fails on a good signature.** With this change it says so with
status 1 instead of 0, which is the change working, not a regression. The
workaround is the one #524 gave, `pip install 'cbor2==5.6.5'`.

## 4. The pull-request body

> ### `CoRimTool.py`: exit non-zero when a command fails
>
> A follow-up to #524, which mentioned it.
>
> `verify` prints `Signature verification failed` and then calls bare `exit()`,
> which is status 0; `json_to_cbor` does the same when it cannot split a tagged
> key. Every other failure in the file raises, and so exits 1. A script that runs
> `CoRimTool.py verify … && next-step` carries on after a rejected manifest.
>
> This changes those two `exit()` calls to `exit(1)` and nothing else
> (+2 −2, CRLF kept).
>
> To see it (the `cbor2` pin is the same workaround as in #524; on a fresh
> install `cbor2` 6.x stops `pycose` decoding even a good signature):
>
> ```bash
> cd spdm_emu/spdm_device_verifier_tool
> pip install -r requirements.txt && pip install 'cbor2==5.6.5'
> python3 CoRimTool.py json_to_cbor -i SampleManifests/SpdmSampleCoMid.json -o /tmp/s.cbor
> python3 CoRimTool.py sign -f /tmp/s.cbor --key SampleTestKey/ecc-private-key.pem \
>                      --kid 11 --alg ES256 -o /tmp/s.corim
> python3 -c "b=bytearray(open('/tmp/s.corim','rb').read()); b[-1]^=1; open('/tmp/f.corim','wb').write(b)"
> python3 CoRimTool.py verify -f /tmp/f.corim --key SampleTestKey/ecc-public-key.pem \
>                      --alg ES256 -o /tmp/out.cbor; echo "exit $?"
> ```
>
> Before: `Signature verification failed`, `exit 0`. After: the same message,
> `exit 1`. A good signature still prints `passed`, writes the 996-byte payload
> and exits 0.

## 5. The checklist, before sending

```
 ── mechanised: bash harness/check_upstream_commit.sh ~/spdm-lab/work/spdm-emu-pr ──
☑ Assisted-by present, no AI in Signed-off-by, no Co-authored-by
☑ subject 45 chars, body within 72, a Tested: line
☑ one commit, clean tree, no file executable without a #! line
☐ exactly one Signed-off-by, matching the author      ← the author's, §6

 ── only the author can tick these ──────────────────────────────────────
☐ diff read line by line, CRLF preserved
☐ every Tested: line run — the table in §3 is the run; re-run it if main moves
☐ ON THE DAY: upstream main still has both bare exit() calls
☐ ON THE DAY: no issue or pull request covers it. Checked 2026-09-29 14:11 UTC:
    "CoRimTool", "exit status verify", "cbor2" -> only #524 each
☐ ON THE DAY: the branch still applies to main without a rebase
```

## 6. Sending it

```bash
cd ~/spdm-lab/work/spdm-emu-pr
git checkout corim-exit-status
git fetch origin && git log --oneline -1 origin/main     # still eff07cf? if not, rebase and re-run §3
git show HEAD                                           # read it once more
git commit --amend -s --no-edit                         # the DCO sign-off: yours
bash /mnt/c/Users/Key20/Desktop/mctp-spdm-pqc/harness/check_upstream_commit.sh .   # expect no FAIL
git push fork corim-exit-status
# then open the pull request on github.com with the body in §4
```

## 7. After it is sent

```
- URL:
- Opened:
- Commit:
- Review round trips:
- Outcome:
```

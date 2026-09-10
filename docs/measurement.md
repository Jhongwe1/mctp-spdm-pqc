# How an experiment is run here

**This project performs protocol-level correctness validation. It is not a
security assessment.**

Every measured result in this repository is produced by the same shape of
procedure, and this page is that shape. It exists because the alternative —
deciding what counts as evidence while looking at the evidence — is how a
number that flatters the person who took it gets published.

It is a template with a worked example rather than a blank form. The example is
Table 1, because it is the one that went wrong in the most instructive way:
[`docs/tamper.md`](tamper.md).

---

## The seven fields

Fill these in **before** the first run, in `LOG.md` or in the document that will
carry the result. Six of them are cheap. The third is the one that costs
something, and it is the one that makes the rest worth anything.

### 1. Hypothesis, written as a prediction that could be wrong

Not "measure the effect of X". A sentence whose falsity you would recognise.

> *Table 1's:* "Changing one byte of a measurement value on the device will
> cause the requester's measurement signature verification to fail."
>
> **It was wrong.** The handshake completed with every signature verifying, and
> the capture that says so is `t1_meas`. That prediction was written down on
> 2026-08-31 and the run happened on 09-01, which is the only reason it can be
> reported as a refuted prediction rather than as something everyone always
> knew.

A hypothesis nobody wrote down before the run cannot be refuted afterwards,
because the memory of having expected the result is not evidence about what was
expected.

### 2. Independent variable — and how it is read back

What is deliberately different between the arms, **and the mechanism that
confirms it actually differed**. `docs/roadmap.md` standing rule 8: a flag is a
request, not a fact.

> *Table 1's:* the position of one changed byte relative to one signature.
> Confirmed three ways, none of them the command line —
> `SPDM_MEASUREMENTS_FILE` is read back out of the responder's own stderr, the
> proxy reports the absolute offset it wrote and the digest before and after,
> and `harness/fields.py` reads the resulting record out of the capture.
>
> On 2026-08-11 an arm reported a 5.94× effect that came from a flag that was
> requested and not negotiated. That number was withdrawn and this field exists
> because of it.

### 3. Control — taken before the thing being tested exists, if it can be

The arm that should show no effect. A control taken afterwards by the person
hoping for a result is worth less than one taken before, and sometimes the
earlier one is available for free.

> *Table 1's:* two of them, and the second was the harder call.
>
> `t0_clean` is the arm with a fixture holding exactly what upstream
> synthesises, and the digest it has to reproduce comes from a capture
> committed **before the patch was written** — so "the added lines do nothing
> when no file is named" is checked against a 256-bit target rather than
> against an opinion.
>
> `t0_proxy` is the control for the *instrument*. Rows 2a and 2b run through a
> proxy, and a proxy that corrupted a 1.9 KB certificate would fail those arms
> for a reason with no relation to the experiment — while looking exactly like
> success. So the proxy forwards a clean run first and has to produce the
> control's record byte for byte.

**A new instrument needs its own control.** That is the field most often
skipped, and skipping it turns "the tamper was detected" into a sentence about
the harness.

### 4. Controlled variables — enumerated, not "everything else"

Write the list. Anything not on it is a variable you have not controlled.

> *Table 1's:* the two binaries and their commits, the device patch's digest,
> the SPDM version, the four negotiated algorithms, the certificate chain, the
> slot count, `--exe_conn`, `--exe_session`, `--meas_op`, the working
> directory, and the fixture for every arm that is not varying it. All of them
> are in the run's `manifest.json`, hashed, because a list a person maintains
> is a list that drifts.

### 5. Dependent variables — and which class they are in

| class | examples | how it is reported |
|---|---|---|
| **A — deterministic** | byte counts, message counts, digests, status codes, round trips | a **single value**. Run three times to confirm it *is* deterministic, not to average |
| **B — noisy** | wall time, verification latency | median and p95 over a stated number of runs, and only from an environment where the quantity being measured dominates |

> *Table 1's:* class A throughout. No timing is reported anywhere in this
> repository, and the reason is stated rather than implied: the environment is
> two local processes over a TCP socket, with a Python proxy between them for
> three of the arms. The dominant term in any latency measured there is
> scheduling and I/O. **Publishing one number that cannot be overturned beats
> publishing two when the second can.**

If a class B number ever is reported here, it will be measured at L0 —
`libspdm`'s `test_crypt`, or `openssl speed` — and reported separately from any
handshake, because a handshake latency and a signature latency are not the same
quantity and only one of them is about cryptography.

### 6. Repetitions, and what they are for

> *Table 1's:* one run per arm, and the determinism is established by a
> different argument than repetition. The 528-byte measurement record has been
> byte-identical across capture runs on five dates and two certificate chains;
> the five-arm baseline has reproduced to the packet three times, eleven days
> apart, from binaries rebuilt in between. Repeating an arm three times inside
> one run would test the same binary against the same clock, which is the
> weaker statement.
>
> Where a number *is* newly deterministic — the per-message byte counts in §6
> of `docs/tamper.md` — it is stated as five arms agreeing, which is five
> independent runs by a different route.

Say which of the two you are doing. "Three runs" that share everything is not
three measurements.

### 7. Where the raw data is, and the exact command

> *Table 1's:* `bench/data/w5-tamper-20260910T092621Z/`, opened by
> `prov_begin` and closed by `prov_finish`, with a `manifest.json` holding the
> upstream commits, the tool versions, the host, every command line that ran,
> and a SHA-256 of all 80 artifacts. Reproduced by
> `bash harness/apply_device_patch.sh pqc --build && bash harness/tamper.sh`.
>
> `harness/verify_repo.sh` fails if a run directory has no manifest, if an
> artifact a manifest attests to is untracked, or if a committed derivation no
> longer equals what the tool produces.

---

## After the run: four questions

**Did the independent variable actually change?** Read it back from the far
side. Not from the flag you passed.

**Is the exit code answering the question you asked?** It usually is not.
`harness/tamper.sh` judges every arm on message counts, digests and the slot
mask, and prints the exit status beside them rather than instead of them —
2026-08-11 is the day three tools answered three slightly different questions
with one number each.

**Does anything in the capture contradict the log?** In `t3_cert` the log said
`do_authentication_via_spdm` failed and the obvious sentence was "the requester
rejected the chain". The capture had no `CERTIFICATE` message in it at all, and
the real answer — the device refused to serve a chain it could not validate —
is a different sentence about a different party.

**Which number would have to change for the conclusion to be wrong?** Name it,
then check that something re-derives it. In this repository a stated number
carries `<!--claim key=value-->` and `harness/fields.py --check` recomputes it
from the capture on every CI run; a number nothing recomputes is a number that
will be wrong later and quiet about it.

---

## What a result is allowed to say

| the claim | what has to exist first |
|---|---|
| "X takes N bytes" | a capture, and two tools that reach N without sharing an input |
| "X is faster than Y" | a class B protocol, an environment where the difference dominates, and a median with a p95 |
| "X is detected" | an arm where it is **not** detected, for contrast, and a build that fails if detection stops |
| "X is not detected" | the same arm, and an explanation of which layer would have to change for it to be |
| "this is how SPDM behaves" | usually not available. `docs/tamper.md` says *this responder, these flags, this commit*, and the difference is not pedantry: three of its rows are about a sample application's choices, not about the protocol |

---

## The order of operations, as a checklist

```
[ ] the hypothesis is written down, and it could be wrong
[ ] the independent variable has a read-back mechanism, not a flag
[ ] the control exists — and a new instrument has its own
[ ] the controlled variables are enumerated in a manifest, not remembered
[ ] each dependent variable is labelled class A or class B
[ ] the run happens inside prov_begin / prov_finish
[ ] the raw artifacts are committed, including the ones from arms that failed
[ ] every number the write-up states carries a claim comment
[ ] a check exists that turns red if the result stops holding
[ ] the prediction is compared with the outcome IN WRITING, including when it
    was wrong — especially when it was wrong
```

The last two are the ones that separate a result from a demonstration.

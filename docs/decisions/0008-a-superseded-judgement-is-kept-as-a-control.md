# 0008 — A superseded judgement is kept as a control, not deleted

**Status:** accepted, 2026-09-14 · **Gate:** G3
**Extends [0004](0004-derivations-must-reproduce.md), whose argument is that a
derivation has to be reproducible from its inputs. This is the case where one
of the inputs is a *decision* rather than a file.**

## The problem

`rats/policy.rego` compared the secure version number for **equality**, which
is what DMTF's `SpdmSamplePolicy.rego` does. That rule is wrong in two opposite
directions at once: an upgraded device fails, and a rolled-back one is refused
by the same check with the same category and the same index — so the verdict
cannot distinguish a routine update from an attack, which is the only
distinction a rollback rule exists to make.

Changing it to `evidence >= reference` is four lines. Showing that the change
**did something, and did only that**, is the part with no obvious home.

The repository's existing mechanisms cannot make that claim:

- **`rats/appraise.py matrix --check`** re-derives every verdict and compares
  it against a committed statement of what each must be. It evaluates **one
  policy**, so a change that did nothing at all satisfies it forever, and a
  change that loosened three rules instead of one satisfies it as soon as the
  expectations are edited to match.
- **`harness/fields.py --check`** guards numbers a document quotes against the
  capture beside them. A verdict is not a number in a capture.
- **`rats/rats_selftest.py`** feeds synthetic pairs to the live policy. It can
  show the new rule behaves; it cannot show the old one behaved differently,
  because the old one is gone.

The failure this leaves open is specific and unglamorous: **a rule change that
is described in prose and asserted by nothing.** Every mechanism in this
repository exists because that sentence was true of something once.

## The three options

1. **Delete the old rule and describe the change.** What every project does.
   The claim "this now refuses a rollback and accepts an upgrade" becomes a
   sentence in a commit message, and the claim "and it loosened nothing else"
   becomes a sentence nobody can check at all.
2. **Parameterise one policy** — a mode flag selecting equality or
   monotonicity. One file, testable both ways, and it ships a verdict engine
   with a switch that turns rollback detection into an accident of
   configuration. A policy whose failure mode is "someone set the mode wrong"
   is worse than the rule it replaced.
3. **Freeze the old file and run both.** A second `.rego`, marked frozen,
   referenced by the test and by nothing that ships a verdict.

## What was decided

Option 3. `rats/policy-v0-equality.rego` is the policy as it stood on
2026-09-13, and `rats/test_svn_policy.sh` appraises the same four captures —
an exact match, an upgrade, a rollback, and a correct version beside an altered
measurement — under both files, against the same signed reference value.

Eight cells. **Exactly one may differ**, and that assertion is in
`rats/out/svn_cases.expected.json` as `outcome_changes_expected`, so a change
moving two cells is a red build rather than a discussion.

### The part that makes it a control rather than two files

A frozen copy drifts. The live policy grows a check next week, the two files
differ in two places, and the table stops being able to say which of them moved
a verdict — while continuing to look exactly as convincing.

So both files carry `# >>> SVN-RULE` and `# <<< SVN-RULE` markers, and
`rats/rats_selftest.py` strips comments, blank lines and everything between the
markers from each, and requires **the remaining code to be identical**. Adding
a check to the live policy outside that region turns the self-test red, and the
message says what to do: decide deliberately what the control should be, rather
than editing the frozen file into agreement.

That check has been observed rejecting something, per standing rule 11: the
self-test writes a copy of the live policy with one unrelated check disabled
and requires the comparison to notice.

### Why the frozen file is not simply `git show`

The old policy does exist in history, and a reader can recover it. Three things
it cannot do from there:

- **CI cannot run it.** The assertion has to execute on a runner that has the
  working tree and nothing else.
- **It cannot be structurally compared.** A file in history has no marker
  relationship to a file in the tree; the drift check needs both on disk.
- **It does not announce itself.** A verdict table that silently stopped
  comparing two policies would look identical to one that still did.

## What it costs

**Forty lines of policy, a marker convention, and a fossil.** The frozen file
is dead weight in the sense that nothing ships from it, and it is now a file
every future reader of `rats/` has to be told to ignore — which is why the
directory's `README.md` says *"not a spare copy"* in the row that lists it.

**And it does not generalise for free.** Doing this for every judgement would
fill `rats/` with superseded policies, each with its own marker region, each a
thing to maintain. This ADR deliberately does **not** decide that. What it
decides is the criterion:

> Freeze a superseded judgement when the change is a **relaxation** — when the
> new rule accepts something the old one refused. A tightening can be
> demonstrated by an input the new rule refuses, which the self-test already
> does. A relaxation cannot: the evidence that it was safe is what it *still*
> refuses, and that is a statement about two rules rather than one.

By that criterion this is the first case and may be the only one for some time.
`LOG.md` 2026-09-14 records the open question rather than pretending it is
settled.

## What it buys, beyond the one table

The frozen column is **evidence in a form a reader can check in four seconds**.
`S-up` and `svn5` under the old policy produce byte-identical output — same
check, same category, same index. "A policy that cannot tell an update from an
attack" stops being a claim about the sample policy and becomes two identical
lines in a table, next to the two lines that are no longer identical.

It also fixes the shape of the honest limitation. With both columns present,
"what the change cost" has somewhere specific to be written: `>=` stops a
rollback *below* the reference value and nothing else, so a device on version 9
pushed back to 7 satisfies it exactly. That sentence sits beside the table in
[`docs/rats-pipeline.md`](../rats-pipeline.md) §5 rather than in a closing
section, which is standing rule 5.

## How to check this is working

```sh
bash rats/test_svn_policy.sh
#   8 cells, 33 assertions, 0 failed — and the one moved cell is S-up

python3 rats/appraise.py selftest
#   "the two policies differ in ONE marked region, and nowhere else"
#   "a change outside the region is detected"   <- rule 11's companion

bash harness/verify_repo.sh
#   runs both of the above, and prints the table under the tamper step
```

## The alternative that is still open

If the four cases are ever re-taken as their own capture run — they are
currently the four device states from `bench/data/w5-tamper-20260910T092621Z`,
which were recorded for a different experiment — the frozen policy stays
exactly as useful, because what it controls for is the *rule*, not the
captures. Nothing here depends on which run the evidence came from.

What would retire this file is the rule changing again. At that point the
question is whether the control should become the *current* policy rather than
the original one, and the answer is not obvious: the useful comparison is
against whatever a reader would otherwise assume, and for a version rule that
is still DMTF's sample.

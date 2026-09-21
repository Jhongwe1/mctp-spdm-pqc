# ADR 0011 — Two versions of one specification, both pinned

**Date:** 2026-10-19
**Status:** accepted
**Supersedes:** nothing. **Related:** [0003](0003-provenance-manifests.md),
[0004](0004-derivations-must-reproduce.md),
[0008](0008-a-superseded-judgement-is-kept-as-a-control.md)

## Context

`third_party/dsp0274.pin` has named DSP0274 **1.4.0** since 2026-08-31, with a
SHA-256 of the exact PDF that was read and a `quoted-in=` list that
`verify_repo.sh` holds to it: every file named there must contain that digest.
Two do — `docs/certchain.md` and `certs/openssl.cnf`.

In week 11 the specification acquired a second relevant version. **DSP0274
1.4.1** is the published fix for DMTF-2026-0003 / CVE-2026-61810, an advisory
whose affected product is not a library but the document itself: five transcript
definitions in 1.4.0 end at `[FINISH].SPDM Header Fields`, which is four bytes,
while SPDM 1.4 had already added two fields ahead of the signature. Any
implementation that follows 1.4.0 exactly has the defect.

`plan/W11` warned that 1.4.1 might not be downloadable — on the day the plan was
written only 1.4.0 was on dmtf.org. It is downloadable now, and that changed
what this project can say: not "the advisory describes a fix" but "here are both
documents, and here is what changed in all five places".

So the question is what to do with the pin.

## The two options

**Move `dsp0274.pin` to 1.4.1.** One pin, one version, the newest text. It is
what a dependency file would do.

**Add `dsp0274-1.4.1.pin` beside it and leave 1.4.0 alone.**

## Decision

The second. `third_party/dsp0274-1.4.1.pin` is a new file; `third_party/
dsp0274.pin` is untouched.

## Why

**A pinned document is not a dependency. It is the evidence that the claims
checked against it were checked.**

Every statement in `docs/certchain.md` about the certificate chain layout, and
every field name in `certs/openssl.cnf`, was read out of the text of 1.4.0 by a
person with that PDF open. Moving the pin to 1.4.1 would not re-check any of
them. It would leave them citing a document nobody has read them against, while
`verify_repo.sh` reported green — because the check that runs is "does this file
carry the pinned digest", and a global search-and-replace satisfies it
perfectly.

That is the failure standing rule 7 describes, arriving through the front door
with the paperwork in order. A version bump that costs nothing is a version bump
that verified nothing.

**And in this case the difference between the two documents *is* the result.**
DMTF-2026-0003 is a defect in a paragraph. The only way to show it was repaired
is to hold both paragraphs open beside each other, which one pin cannot express.
`docs/transcript.md` section 3 quotes all five definitions from each version.

## What follows from it

- `dsp0274.pin` keeps `version=1.4.0` and its `quoted-in=` list. Nothing about
  the certificate-chain work changes.
- `dsp0274-1.4.1.pin` carries `supersedes=third_party/dsp0274.pin` as a
  *pointer*, not an instruction: it records which document this one replaces
  upstream, while both remain pinned here.
- A document may quote either, and must carry the digest of the one it quotes.
  `verify_repo.sh` already enforces exactly that, per pin, with no change.
- **Migrating a claim from 1.4.0 to 1.4.1 means re-reading it**, section by
  section, and moving that file from one `quoted-in=` list to the other. When
  that happens it is a commit of its own with the sections named, not a side
  effect of a pin bump.

## The check that would have caught the other choice

1.4.0 was re-downloaded on the same day as 1.4.1 and hashed to
`a2035c64f614640ba34133ad255589269bf13c9d816414638fb22d89eb5369d9` — byte for
byte the digest the pin recorded eight weeks earlier. A pin that still names the
document it named two months ago is worth keeping; that is the whole argument
for pinning, and it is also the reason not to overwrite one.

## What this does not decide

Whether this project's own implementations follow 1.4.0's transcript rule. They
do not compute a FINISH transcript at all — **nothing here has ever established
a secure session**, which `docs/threat-scope.md` level 2 has said since
2026-10-12. `negative/test_transcript_coverage.c` models the rule rather than
running it, and says so in its first paragraph.

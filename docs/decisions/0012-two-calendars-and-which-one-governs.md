# ADR 0012 — Two calendars, and which one governs

**Date:** 2026-09-22
**Status:** accepted
**Supersedes:** nothing. **Related:**
[0003](0003-provenance-manifests.md),
[0004](0004-derivations-must-reproduce.md),
[0011](0011-two-versions-of-one-specification.md)

## Context

Two prepared changes were sent on 2026-09-22: `DMTF/spdm-emu` pull request
[#524](https://github.com/DMTF/spdm-emu/pull/524) and `openbmc/spdm` Gerrit
change [94773](https://gerrit.openbmc.org/c/openbmc/spdm/+/94773). They are the
first dates in this repository written by somebody else's server — timestamps
this project cannot revise and a reader can read without asking.

Filling in `docs/upstream/0001-corim-verify.md` §8 — a field called `Opened:`
sitting directly beneath a field called `URL:` — is what made the question
unavoidable, and measuring it produced something other than the expected answer.

### What was actually there

The first guess was that this project had always kept two clocks. It had not.

| | entry header | the commit that introduced it |
|---|---|---|
| Day 1 – Day 11 | 2026-08-11 … 2026-09-18 | **the same dates** |
| **Day 12** | `2026-10-12` | `6ea2e8d`, **2026-09-20** |
| **Day 13** | `2026-10-19` | `648d2a2`, **2026-09-22** |

Eleven entries agreed. Two did not, and they were the two most recent.

The cause is not carelessness, it is **arithmetic**: `plan/` is a fourteen-week
schedule beginning 2026-08-11, and the work outran it. Weeks 10 and 11 were
executed in two sessions, and from Day 12 the prose took the *plan's* dates for
those weeks rather than the day's. Thirty-one occurrences of three such dates
had spread across nineteen tracked files, including the `retrieved-at=` field of
four `third_party/*.pin` files.

### The fact that decided it

**`plan/` is gitignored and is never pushed.** `harness/verify_repo.sh` fails the
build if it ever becomes tracked.

So a reader of the published repository cannot open the calendar those dates are
on. They can open `git log`, which disagrees with them by 22 and 27 days.

## The three options

**(a) Declare the plan calendar** in `LOG.md`'s header and leave every entry
alone.

**(b) Put every date on the real clock** and keep the week labels.

**(c) Leave it.**

## Decision

**(b).** Thirty-one occurrences were converted:

| from | to | why that one |
|---|---|---|
| `2026-10-12` | `2026-09-20` | Day 12's commits |
| `2026-10-19` | `2026-09-22` | Day 13's commits |
| `2026-10-25` | `2026-09-22` | "W11 收工" — the same session as Day 13 |
| `…-10-19T18:18:25Z` | `…-09-21T18:18:25Z` | see below |

★ The four pins needed a different date from the prose around them, and the
reason is worth keeping. `retrieved-at=2026-10-19T18:18:25Z` had a **real time of
day** with a substituted date: 18:18Z is 02:18 the next morning at +0800, an hour
and a half before `f2afa02` added those pins at 03:39. Only the date had been
replaced, so only the date was restored — and in UTC that is 2026-09-**21**, not
the 22nd the local prose carries. A blanket substitution would have moved the
retrieval to after the commit that recorded it.

**The week labels stay.** `W10`, `W11` and `plan/W11` appear throughout and are
untouched. They name a unit of work, which is real; they are not claims about a
day, which is what was wrong.

`2026-11-15` also stays. It is the planned end of the schedule, it is stated as
such, and a plan is allowed to have a future date in it.

## Why

**Against (a): a declared convention has to point at something the reader can
open.** "Entries are dated by the plan calendar" sends a reader to `plan/`, which
is not in the repository and by policy never will be, while `git log` — which
is — contradicts it. That is not a convention. It is an explanation the reader
cannot check, offered by a repository whose entire claim is that its claims can
be checked. The same objection would apply to any rule this project wrote about
an artifact it does not publish.

**Against (c):** eleven entries were already on the real clock. Leaving two
others on a different one is not a convention either; it is an inconsistency
with a good story attached.

**And the plan calendar was costing something.** Fourteen weeks of scheduled work
were done in six. Dating the record by the schedule conceals the one number most
in the author's favour, and replaces it with a number anybody can disprove with
`git log`.

> ### The rule worth keeping
>
> **A clock you control is a convention; a clock somebody else controls is a
> fact — and a convention that refers to something you did not publish is
> neither.** This is [0004](0004-derivations-must-reproduce.md) pointed at
> dates: a figure whose derivation the reader cannot run is not evidence, and
> neither is a date whose calendar the reader cannot open.

## What follows from it

- Every date in a tracked file is the real one. Nothing is on a second calendar
  any more, so nothing needs a label saying which.
- `LOG.md`'s header says so, and says `git log` is the authority.
- Week labels continue to name work units.
- Commits and `bench/data/` run directories are unchanged — they were already on
  the real clock, per [0003](0003-provenance-manifests.md).
- External timestamps — a pull request, a Gerrit change, an advisory, a
  document retrieval — are recorded as the other side wrote them.

## The check

`harness/verify_repo.sh` now requires **every `## YYYY-MM-DD` heading in
`LOG.md` to have at least one commit authored on that date.**

Run against the tree as it stood this morning it fails on exactly the two
entries this ADR corrected and passes on the other thirteen.

It did not find them — a question about what to write in a field called
`Opened:` did. But it is the only form of "remember this" that survives a
contributor who was not here today, including the author in three months.

## What this does not decide

Whether `plan/` should be published. It should not, for the reasons already in
`.gitignore` and enforced by `verify_repo.sh`: it is a schedule, much of it
superseded, and a reader who finds a plan and a result in the same repository
will reasonably read the plan as a claim. This ADR is the opposite decision —
the repository stops *referring* to the unpublished thing rather than starting
to publish it.

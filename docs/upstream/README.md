# Upstream contribution tracking (G7)

The one form of evidence in this project that cannot be manufactured: a change
in someone else's repository, reviewed by someone who does not work for me.

Everything else here can in principle be fabricated by a sufficiently motivated
person with a text editor. A review thread cannot.

That is also why this gate starts in week one despite producing nothing for
weeks. It is the only item on the schedule with an external clock: agreements
have to be processed, accounts have to be approved, and a mailing list takes as
long as it takes. Work that has a queue in front of it starts first.

## Status

| Item | State | Date | Evidence |
|---|---|---|---|
| Gerrit account, real name, SSH key | **done** | 2026-08-04 | `ssh openbmc.gerrit` returns a greeting with the account's full name |
| git identity matches Gerrit on both host environments | **done** | 2026-08-11 | `user.name` is the legal name in WSL and on Windows |
| CLA sent to `manager@lfprojects.org` | **`TODO`** | | keep the sent copy in this directory |
| Community channel joined, reading only | **`TODO`** | | |
| Target repository built locally | **`TODO`** | | record every problem hit — those are the contribution |
| First change submitted | not started | | |
| Reviewer response received | not started | | |

## Two things that are easy to get wrong

**The CLA is not signed inside Gerrit.** It is a document that goes to
`manager@lfprojects.org`. Ticking something in a web interface is not the same
act, and the difference does not become visible until a change is blocked
months later. Keep the sent copy here — it is the only proof of the date.

**The CLA and the DCO are different requirements, and both apply.** The CLA is
a one-time agreement covering the person. The DCO is the `Signed-off-by:` line
that has to be on every individual commit, produced by `git commit -s`, and it
has to match the name on the account. This is why `user.name` is the legal name
in every environment that might produce a commit — a mismatch is rejected with
a message that explains the rule but not which of the two identities is wrong.

## Why this target

Chosen because the ratio matters more than the prestige:

- small enough that one person can hold the whole thing in their head
- active enough that a change gets looked at
- has real gaps — undocumented behaviour, untested helper code
- sits on both of the subject areas this project is about

A well-reviewed change to a repository of thirty files is worth more here than
an ignored change to one of thirty thousand.

## Working notes

Every problem hit while building or reading the target is recorded, because
those problems are the raw material. A contribution that begins "I tried to
build this and here is what was not obvious" is both genuinely useful and
something only someone who actually did it can write.

<!-- Append entries here as they happen. Date, what was hit, what was done. -->

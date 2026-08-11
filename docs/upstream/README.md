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

The account-level work was completed under a separate OpenBMC project of mine
before this one started. One Individual CLA and one Gerrit identity cover every
repository in the OpenBMC project, so none of it is repeated here — but the
dates belong in this tracker, because "the paperwork is done" is a claim that
needs a date attached to it.

| Item | State | Date | Evidence |
|---|---|---|---|
| Individual CLA sent to `manager@lfprojects.org` | **done** | 2026-08-04 | signed as the legal name; one agreement covers every OpenBMC repository |
| Gerrit account, SSH key, `~/.ssh/config` | **done** | 2026-08-04 | `ssh openbmc.gerrit` returns a greeting with the account's full name |
| Gerrit profile full name corrected | **done** | 2026-08-04 | GitHub OAuth had populated it with a short form — see the third trap below |
| `commit-msg` hook installed (Change-Id) | **done** | 2026-08-04 | hook served by Gerrit 3.11.7 |
| Submission pipeline rehearsed end to end | **done** | 2026-08-05 | a `%private,wip` change, three patchsets, abandoned once verified |
| git identity matches Gerrit in every environment | **done** | 2026-08-11 | legal name in both the WSL and the Windows git config |
| Community channel joined, reading only | **`TODO`** | | |
| **This project's** target repository built locally | **attempted** | 2026-08-11 | five distinct blockers, below |
| **This project's** first change submitted | not started | | |
| Reviewer response received | not started | | |

> **Not a deliverable of this project.** A change to `openbmc/docs` was
> submitted on 2026-08-11 under the other project. It appears nowhere in this
> repository's results and is mentioned only because of what it removes: the
> path from `git commit -s` to a change sitting in Gerrit has been walked once
> already, so what this project still owes upstream is a technical problem, not
> an administrative one.

## Rehearsing the submission before submitting

Worth naming, because it is the step most people skip. Before the first real
change, push one marked private and work-in-progress:

```bash
git push openbmc.gerrit HEAD:refs/for/master%private,wip
```

It traverses the whole pipeline — CLA check, DCO check, Change-Id, CI — while
remaining visible only to its author. Every configuration mistake surfaces with
nobody notified, and the change is abandoned afterwards. The alternative is
finding out about a rejected sign-off on a change that reviewers are already
looking at.

## First build attempt — 2026-08-11

Target at `72e3ea9` (last commit 2026-07-31). Host: Ubuntu 24.04.4 LTS,
GCC 13.3.0, meson 1.12.0, on the distribution's default toolchain.

Repository shape, re-verified rather than taken from notes:

| | |
|---|---|
| tracked files | **31** |
| root `README.md` | **absent** |
| `OWNERS` | present |
| tests | 3 files: `test_mctp_transport_discovery`, `test_policy_manager`, `test_spdm_discovery` |
| untested source | `requester/utils/mapper.{cpp,hpp}`, `requester/utils/paths.{cpp,hpp}` |
| subprojects pulled | CLI11, phosphor-dbus-interfaces, phosphor-logging, sdbusplus, stdexec — 53 MB |
| build tree after a full attempt | 1.8 GB |

### Five blockers, in the order they appear

1. **`meson setup` fails: `python3 is missing modules: inflection, mako`.**
   Required by sdbusplus's code generator, not documented anywhere in the
   repository.

2. **Installing those modules into a virtualenv is not sufficient.** meson
   resolves the generator through `find_program('python3')`, which searches
   `PATH`. Running `venv/bin/meson` while `venv/bin` is *not* on `PATH` finds
   `/usr/bin/python3`, which still lacks the modules. The error message is
   also self-contradictory — it reports `found: NO modules: yaml` on one line
   and `missing modules: inflection, mako` on the next.

3. **`meson compile` then fails: `ModuleNotFoundError: No module named
   'jsonschema'`.** A third generator dependency, surfacing only after setup
   succeeds, so the three are discovered one build at a time.

4. **GCC 13.3.0 hits an internal compiler error** on
   `requester/utils/mapper.cpp:46`:
   `internal compiler error: in build_special_member_call, at cp/call.cc:11096`.
   An ICE is a compiler defect, but the operational fact stands: this file does
   not compile with the toolchain shipped in the current Ubuntu LTS.

5. **`tests/test_policy_manager.cpp:67` requires `std::formatter<std::thread::id>`.**
   `std::format("spdm_test_{}_{}", ..., std::this_thread::get_id())` fails the
   `formatter must be specialized` static assertion, because the libstdc++
   shipped with GCC 13 has no specialization for `std::thread::id`. The
   project declares C++23 and states no minimum compiler version.

   *(The specialization comes from a C++23 library paper adopted after GCC 13.
   Check the exact paper number and the libstdc++ version that implements it
   against the primary source before quoting either — this project does not
   repeat version claims it has not verified itself.)*

### What this is worth

Blockers 1 through 3 are exactly the kind of thing a `README.md` exists to
prevent, and this repository does not have one. A newcomer on a mainstream
distribution hits three undocumented failures before reaching a compiler error,
and there is nothing in the tree to tell them any of it is expected.

Blockers 4 and 5 are separate and sharper: **the repository does not build with
the default toolchain of the current Ubuntu LTS**, and it does not say which
toolchain it does need.

That gives two candidate contributions, both small, both verifiable, and both
useful to the next person:

- a `README.md` stating prerequisites, the generator modules, the `PATH` trap,
  and a build recipe that works
- a statement of the minimum compiler version, supported by the two failures
  above

Reproduction recipe as it stands today, which is what a README would say:

```bash
git clone https://github.com/openbmc/spdm.git && cd spdm
python3 -m venv .venv
. .venv/bin/activate          # must be activated: meson finds python3 via PATH
pip install meson ninja inflection mako pyyaml jsonschema
meson setup build             # succeeds: 808 targets
meson compile -C build        # fails on GCC 13.3 — see blockers 4 and 5
```

## Three identity traps, all of which are silent until they are not

**The CLA is not signed inside Gerrit.** It is a document that goes to
`manager@lfprojects.org`. Ticking something in a web interface is not the same
act, and the difference does not become visible until a change is blocked
months later. Keep the sent copy — it is the only proof of the date.

**The CLA and the DCO are different requirements, and both apply.** The CLA is
a one-time agreement covering the person. The DCO is the `Signed-off-by:` line
on every individual commit, produced by `git commit -s`, and it has to match
the name on the account. A mismatch is rejected with a message that explains
the rule but not which of the two identities is wrong.

**Signing in to Gerrit with GitHub OAuth fills the profile name from GitHub.**
So the account can end up carrying a handle or a shortened display name rather
than the legal name that has to appear in `Signed-off-by:`. It has to be
corrected in Gerrit's profile settings, and nothing says so until a change is
rejected. Hit and fixed on 2026-08-04.

The three are the same failure in three costumes: an identity recorded in one
place and assumed everywhere else. The same shape turned up again on
2026-08-11 on this machine, where the Windows and WSL git configurations
carried different `user.name` values and only one of them would have satisfied
the DCO.

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

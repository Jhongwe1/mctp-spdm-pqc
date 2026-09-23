# Change 0002 — a first README for `openbmc/spdm`

**Target:** `openbmc/spdm` at `72e3ea9` (`main`, last merged 2026-07-31)
**Pipeline:** Gerrit, `gerrit.openbmc.org`
**State: IN REVIEW** — change
[94773](https://gerrit.openbmc.org/c/openbmc/spdm/+/94773). Patchset 1 sent
2026-09-22 and given Code-Review −1 by an owner the same day; patchset 2
prepared on 2026-09-23 and not yet pushed. See §10 and §11.
**Prepared:** 2026-09-18
**Local:** `~/spdm-lab/work/openbmc-spdm`, branch `readme`, commit `d3c84a1`

---

## 0. Why this change, and why it is not the obvious one

The obvious framing is "this repository has no README, so write one". That
framing is how the last attempt died.

**Change [80422](https://gerrit.openbmc.org/c/openbmc/spdm/+/80422),
"spdm: Add license and build infrastructure", 2025-05-19, abandoned
2026-05-27.** It was uploaded by Ratan Gupta — who is in this repository's own
`OWNERS` as a reviewer — and it contained `README.md`, `LICENSE` and
`.clang-format`. The `LICENSE` and `.clang-format` arrived by other routes. The
README did not.

What the maintainer said, on line 1 of the file:

> **Patrick Williams:** I don't know why we are adding a README with
> hypotheticals that do not match the code. Nothing in this commit (or earlier)
> accomplishes any of these.

And when the author proposed deferring it until the features existed:

> **Ratan Gupta:** Updating the README.md with every commit would be
> unnecessary overhead. Since we already know that this repository will
> eventually provide this functionality, I suggest holding off on merging this
> commit until the relevant functionality is introduced in later commits.
>
> **Patrick Williams:** It is unnecessary overhead to add a line to the README
> when you have a feature done? That's rather surprising.

Two other reviewers asked for specific things:

> **Chinmay Shripad Hegde**, line 5: Can we add a reference to upstream redfish
> design.
>
> **Chinmay Shripad Hegde**, line 29: Can we add Code organization section to
> give a overall code structure?
>
> **Patrick Williams**, line 28: Why?

Line 28 was the dependency list, which named boost. `meson.build` does not
depend on boost.

Then CI voted `Verified-1` twice, nobody rebased, and on 2026-05-27 a bot
abandoned it: *"Automatically abandoned due to missing or failing CI and
inactivity of over one year."*

> ### ★ So the review is the specification
>
> A README is wanted — the maintainer's second comment says so explicitly. What
> was rejected was a README that **described features the code did not have**.
> The requirements, in the reviewers' own words:
>
> 1. describe what the code does, not what the project is for;
> 2. reference the upstream Redfish design document;
> 3. include a code organization section;
> 4. do not list dependencies that are not dependencies;
> 5. **pass CI**, which for a `.md` file means prettier and markdownlint.
>
> This is worth more than the change. Finding that a repository lacks a README
> takes one `ls`. Finding out *why* the last one did not land, and what the
> people who will review this one have already said they want, took twenty
> minutes of reading a Gerrit change that a search for "README" surfaced.

## 1. What the change says, and how each claim was established

Every statement in the README was read out of the tree at `72e3ea9`, not
recalled. The ones that could have been wrong:

| Claim | Where it was read |
| --- | --- |
| the daemon does not speak SPDM | `meson.build` has no libspdm dependency |
| three transports named, two implemented | `TransportType` in `requester/spdm_discovery.hpp`; `spdmd_src` in `meson.build` lists `mctp_` and `tcp_transport_discovery.cpp` and no `doe_` |
| MCTP endpoints are filtered on message type `0x05` | `MCTPTransportDiscovery::spdm_message_type` |
| mctpd publishes under `/au/com/codeconstruct/mctp1` | `mctp_namespace_path`, and the comment beside it |
| TCP responders come from an entity-manager configuration | `xyz.openbmc_project.Configuration.SpdmTcpResponder`, and `properties.hostname` / `properties.port` |
| the name is requested only after discovery | `ctx.spawn([]... co_await discovery.run(); ctx.request_name(...))` in `spdmd.cpp` |
| the policy property names | ★ `Policy.interface.yaml` in phosphor-dbus-interfaces, **not** the C++ tag names. `allowed_algorithms_aead_t` is `AllowedAlgorithmsAEAD` on the bus, and transliterating the C++ would have got the capitalisation wrong |
| the cache is `policy.json` under the state directory | `paths.cpp`, `policy_cache()` |

The dependency list names exactly what `meson.build` names. Boost is not in it.

## 2. Two findings that came out of building it

> ### ⚠ Corrected 2026-09-23: the next sentence was false about patchset 1
>
> Neither finding was in the README that was sent. `GCC` appears in it **0**
> times and `dbus-run-session` **0** times; `test_policy_manager` appears once,
> in a list of test names. The sentence below was written from the plan for the
> file rather than from the file, and it survived four days of preparation, the
> checklist in §6 — which says *"Read the diff"* — and a reply on the change
> that called them *"the two build notes"*. Reading was not checking. Patchset
> 2 carries both, and each was re-run on 2026-09-23 before it was written
> down (§11).

Both are in the README because a newcomer hits both, and neither is documented
anywhere in the tree.

**① It does not build with the distribution's default compiler.** Recorded on
2026-08-11 and re-verified on 2026-09-18 at the same commit:

```text
../requester/utils/mapper.cpp:46:5: internal compiler error:
    in build_special_member_call, at cp/call.cc:11096
```

GCC 13.3, Ubuntu 24.04. **GCC 14.2 compiles the tree**: 863 targets, clean.
That is the whole of what the README says about it — a statement of what was
observed, not a proposal that the project adopt a minimum compiler version. The
second is a functional change and would invite a discussion this change is not
the place for.

**② One of the three unit-test suites fails on any machine that is not a BMC.**

```text
C++ exception with description "sd_bus_request_name:
org.freedesktop.DBus.Error.AccessDenied: Permission denied" thrown in SetUp().
```

`test_policy_manager` constructs the D-Bus server the daemon serves its policy
on, which means requesting a well-known name; a stock system's D-Bus policy
does not permit `xyz.openbmc_project.*` to be owned by an arbitrary user.

**It is not a defect and the README does not call it one.** It is an
undocumented environmental prerequisite, and one line fixes it:

```sh
dbus-run-session -- sh -c \
  'DBUS_SYSTEM_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS meson test -C build'
```

3 of 3 OK. That line was run before it was written down.

> Two open changes by Ravi Teja are in the same area —
> [93558](https://gerrit.openbmc.org/c/openbmc/spdm/+/93558) "tests: avoid
> D-Bus async context in discovery tests" and
> [93560](https://gerrit.openbmc.org/c/openbmc/spdm/+/93560) "tests: fix policy
> manager async test shutdown". Neither is this, and this change does not touch
> the tests. It is named here so that nobody has to wonder whether it was
> checked.

## 3. What is deliberately not in this change

- **No change to any source file.** A first README that also fixes a build is
  two changes, and the second one is the one that gets argued about.
- **No claim about PCIe DOE.** `TransportType::PCIE_DOE` exists with no
  discovery class, and the README says exactly that and stops. Whether that is
  deferred on purpose is a question for the maintainers, not a statement for a
  README — see §6.
- **No minimum-compiler-version policy.** §2①.
- **No mention of work in review.** There are 34 open changes against this
  repository, including a libspdm integration series open since 2025-11. A
  README that described them would be describing code that is not in the tree,
  which is precisely what got the last one rejected.

## 4. The commit

```text
spdm: add a README for the daemon and its build
...
Signed-off-by: Chung-Wei Lan <zwwe1f@gmail.com>
Assisted-by: Claude Code:claude-opus-5
Change-Id: Ib0191ead35bb19c0be46935c0da3a89b34b2a27d
```

`git -C ~/spdm-lab/work/openbmc-spdm show HEAD` is the authority; the message is
not duplicated here so that it cannot drift.

> ### ⚠ Corrected 2026-09-22, by a reviewer, on this change
>
> The paragraph below was **true about `CONTRIBUTING.md` and wrong about
> OpenBMC.** There is a policy — [89452](https://gerrit.openbmc.org/c/openbmc/docs/+/89452),
> *"Document AI coding assistant policy"*, by Ed Tanous — and on 2026-09-22
> Chinmay Shripad Hegde pointed at it from this very trailer.
>
> It is **in review, not merged**: `raw.githubusercontent.com/openbmc/docs/
> master/coding-assistants.md` returns 404. That is exactly why grepping a
> merged file could not find it, and exactly why grepping a merged file was the
> wrong instrument. **A project's rules live in its open changes as well as in
> its tree**, and one Gerrit query would have found this one:
>
> ```
> gerrit query project:openbmc/docs message:"AI coding"        -> 89452
> gerrit query project:openbmc/docs file:coding-assistants.md  -> 89452
> ```
>
> Both were run on 2026-09-22 and both return it. `message:Assisted-by` does
> not, which is worth knowing too: the query that looks like the obvious one is
> the one that fails.
>
> **The change already complies with it**, which is luck rather than diligence.
> The policy requires that an AI must not add `Signed-off-by` (only a human can
> certify the DCO, and the human is responsible for reviewing the work), and
> that attribution take the form `Assisted-by: AGENT_NAME:MODEL_VERSION [TOOL1]
> [TOOL2]` with basic tools omitted. This commit carries one human sign-off
> matching the author, no `Co-authored-by`, and
> `Assisted-by: Claude Code:claude-opus-5`. Verified rather than assumed —
> thirteen claims checked mechanically before the reply was posted, and one of
> the checks was itself wrong: `grep -i AI` on the sign-off line matched the
> `ai` in `gmail`.

**On the `Assisted-by:` trailer.** OpenBMC's `CONTRIBUTING.md` has no AI policy
— the word does not appear in the file, digest
`e27c7768eedaeded3823727087a6e8e6c7034bfb91c5a60deb7305c108480301`, read
2026-09-18 and unchanged on 2026-09-22. So the trailer is neither required nor forbidden, and including it
is a choice. It is included because DMTF *does* require it, this contributor
sends changes to both, and one convention across both is easier to defend than
a rule followed only where it is enforced. `harness/check_upstream_commit.sh
--profile openbmc` reports it and does **not** require it, deliberately: a check
that invented a rule the project does not have would teach the wrong rule set
for the next repository.

## 5. Three ways the format was checked before sending

Change 80422 failed CI twice. For a markdown-only change, OpenBMC's CI runs
`format-code.sh`, which runs `prettier` and `markdownlint` with the configs in
`openbmc/openbmc-build-scripts/config/`.

```sh
prettier --config prettierrc.yaml --check README.md     # clean
markdownlint --config markdownlint.yaml README.md       # clean
```

prettier 3.3.3 and markdownlint-cli 0.41.0, with the configs fetched from
`openbmc-build-scripts` rather than guessed. `printWidth: 80`,
`proseWrap: always`, `tabWidth: 2` for markdown; markdownlint default rules with
`MD013` off.

★ The versions are pinned below the current ones on purpose: this box has
Node 18, and markdownlint-cli 0.42 and later use a regular-expression `v` flag
that needs Node 20. The rules are what matter and they have not changed; the
tool that enforces them refused to start, which is a different problem and is
worth the two minutes it took to find out rather than assuming the linters were
fine.

## 6. The checklist, before sending

Nothing below is mechanisable, which is why it is a list and not a script.
**It was worked through on 2026-09-22 immediately before the push; every
answer is in [§10](#10-after-it-is-sent), including the two that had changed.**

- [ ] **Has somebody added a README since 2026-09-18?**
      `curl -sI https://raw.githubusercontent.com/openbmc/spdm/main/README.md`
      — 404 means no. If it is 200, **this is not bad news**: read that change's
      review, because the reviewers will have asked for things this one did not
      think of, and then go and do the `requester/utils/` unit tests instead
      (`mapper.cpp` and `paths.cpp` are pure functions and have no tests).
- [ ] **Has `main` moved?** `git ls-remote --heads https://github.com/openbmc/spdm.git`.
      If it has, rebase and re-run the build and the tests before re-reading the
      `Tested:` lines — they are claims about a tree.
- [ ] **Is `main` still the only branch?** It was on 2026-09-18, and most
      OpenBMC repositories are on `master`. The push target depends on it.
- [ ] **Does the OWNERS file still name the same reviewers?**
      `curl -s https://raw.githubusercontent.com/openbmc/spdm/main/OWNERS`
- [ ] **Read the diff.** `git -C ~/spdm-lab/work/openbmc-spdm show HEAD`
- [ ] **Re-run the two linters**, because a rebase can change nothing in the
      file and everything about whether they are installed.
- [ ] **Re-run `bash harness/check_upstream_commit.sh --profile openbmc
      ~/spdm-lab/work/openbmc-spdm`.**
- [ ] **Every `Tested:` line is yours to have actually run.** The ones in this
      commit were run on 2026-09-18; if the tree moved, they were not.

## 7. Sending it

```sh
cd ~/spdm-lab/work/openbmc-spdm
git remote add gerrit ssh://openbmc.gerrit/openbmc/spdm   # once
git push gerrit HEAD:refs/for/main
```

> ### ★ This section said `origin` until the day it was used, and `origin` is the wrong repository
>
> The working tree was cloned from GitHub, so its only remote was
> `https://github.com/openbmc/spdm.git` — **the read-only mirror**. Following
> this file's own instruction would have pushed at GitHub rather than Gerrit.
> It fails loudly, so nothing would have been damaged; it fails at the one
> moment when an unexplained error costs the most.
>
> The mistake is specific and worth naming: **a Gerrit project and its GitHub
> mirror have the same path and different meanings**, and nothing about the URL
> says which one accepts a push. A rehearsal against a *different* repository
> (`openbmc/docs`, 2026-08-05) proved the pipeline and did not prove this
> remote, because that tree had the Gerrit remote already configured.
>
> The project name was read out of Gerrit — `ssh openbmc.gerrit gerrit
> ls-projects` returns `openbmc/spdm` — rather than assumed from the GitHub
> path, and `git push --dry-run` printed `* [new reference] HEAD ->
> refs/for/main` before anything real was sent.

★ `main`, not `master`. `git ls-remote --heads` returns exactly one head for
this repository and it is `refs/heads/main` — which is unusual for OpenBMC and
is why it is checked rather than typed from habit. This file's neighbour,
`docs/upstream/README.md`, records the rehearsal command with `master` in it,
because the rehearsal was done against `openbmc/docs`.

Then, on the change's Gerrit page:

- **Add one or two reviewers from `reviewers:`, not from `owners:`.** Lei Yu
  (`mine260309@gmail.com`), Ratan Gupta (`ratankgupta31@gmail.com`) or Archana
  Kakani (`archana.kakani@ibm.com`). ★ Ratan Gupta wrote change 80422. Adding
  the person whose change this supersedes is the right call and the message
  already credits it.
- **Do not add five people.**

**On a reply after a review:** `git commit --amend` and push again. The same
`Change-Id` makes it a new patchset on the same change. A new commit makes a
second change and orphans the discussion.

## 8. What to expect, and what is not a problem

`openbmc/spdm` last merged anything on **2026-07-31**. There are 34 open
changes, some open since 2025-11. OpenBMC's own `CONTRIBUTING.md` has a section
called "Pace of Review" that says, in substance, that a week is a reasonable
time to wait before pinging and hours is not.

So: silence for a week is the expected outcome, not a failure. The thing this
change is for — a review thread with somebody who does not work for me — has an
external clock, and the only variable under control here is how early it starts.

## 9. If it is rejected

That is a result and it goes in `docs/upstream/README.md` with the reviewer's
reason quoted, the same way change 80422's rejection is quoted in §0 of this
file. The value of a review thread does not depend on the verdict; it depends on
there being one.

## 10. After it is sent

```
- URL:        https://gerrit.openbmc.org/c/openbmc/spdm/+/94773
- Pushed:     2026-09-22
- Change-Id:  Ib0191ead35bb19c0be46935c0da3a89b34b2a27d
- Patchset 1: d3c84a100487d01a94f578a4722cab7a483ad7ea
- Files:      README.md, ADDED, +130 -0
- Reviewers:  not requested by me.  Chinmay Shripad Hegde reviewed
              within 35 minutes and added Ratan Gupta; by 11:10 UTC all
              six people in OWNERS were on the change, including
              Patrick Williams, who rejected 80422.
- CI result:  Verified+1, Build Successful, jenkins job 149171.
- Review round trips:
    Patchset 1 -> two inline comments on /COMMIT_MSG, both unresolved,
                  neither a change request:
                  line 26 - context on 80422: the daemon functionality
                    was not in the tree when it was written, so its
                    README could not have described it.  Agreed, and
                    offered to reword that paragraph.
                  line 43 - the Assisted-by trailer: read the AI
                    assistant policy in openbmc/docs 89452 and align.
                    ANSWERED; the change already conforms.  See the
                    correction box in section 4.
    Patchset 1 -> Code-Review -1 from Patrick Williams, an owner,
                  2026-09-22 19:17 UTC: "I'm not interested in reviewing
                  AI-generated documentation.  There are bits here that
                  are potentially useful but I'm not merging something
                  that is a waste of human time to read."  Marked
                  resolved: a statement, not a question.  Section 11.
    Patchset 2 -> prepared 2026-09-23, fd3fa9b on branch readme-ps2,
                  rebased onto 32e9f8b.  59 lines instead of 130, mode
                  644, every command re-run that day.  Not pushed: the
                  sign-off and the push are the author's.  Section 11.
- What I learned from this review, specifically: TODO(me)
- Outcome: open, status NEW, Code-Review -1 on patchset 1
```

> ★ **The review arrived in 35 minutes, and it found the one thing the
> preparation got wrong.** Not the README — the research behind the commit
> message. Section 4 said OpenBMC has no AI policy, on the evidence of a grep
> over `CONTRIBUTING.md`; a reviewer produced one from a change in flight. That
> is the whole argument for sending work to people rather than checking it
> against yourself, and it cost 35 minutes to learn.

### §6's checklist, worked through on the day

| item | answer on 2026-09-22 |
|---|---|
| has somebody added a README? | no — `raw.githubusercontent.com/openbmc/spdm/main/README.md` returns **404**, and a Gerrit query for open changes with `message:README` on this project returns **nothing** |
| has `main` moved? | **no** — still `72e3ea9`. So the `Tested:` build claims, run 2026-09-18, are claims about the tree that is still there. They were not re-run, and that is stated rather than implied |
| is `main` still the only branch? | yes, exactly one head |
| does `OWNERS` still name the same reviewers? | yes — Lei Yu, Ratan Gupta, Archana Kakani; owners Manoj Kiran Eda and Patrick Williams |
| the two linters | **both had vanished from the machine.** Reinstalled at the pinned versions through `npx` and re-run against configs fetched from `openbmc-build-scripts` on the day: prettier 3.3.3 → *All matched files use Prettier code style!*; markdownlint-cli 0.41.0 → exit 0, no output |
| `check_upstream_commit.sh --profile openbmc` | every rule satisfied, including `Change-Id` last so an amend will not add a second one |
| does Gerrit know who I am? | `Hi **Chung-Wei Lan**, you have successfully connected over SSH` — the legal name, matching the sign-off. The OAuth display-name trap of 2026-08-04 has stayed fixed |
| OpenBMC's `CONTRIBUTING.md` | unchanged, `e27c7768eeda…`; the word *AI* still appears **0** times, so `Assisted-by:` remains a disclosure rather than a requirement |

> ★ **The linter row is the one worth keeping.** §6 says to re-run them
> *"because a rebase can change nothing in the file and everything about whether
> they are installed"* — and the file had not changed, and they were gone. A
> checklist item written about a hypothetical fired on its first real use.

### What changed since this file was written

`openbmc/spdm` now has **37** open changes rather than 34, and none of them is a
README. The three arrivals do not affect this change and are recorded because
"unchanged" is a measurement and it came back false.

## 11. The −1 on patchset 1, and patchset 2 — 2026-09-23

**What was said.** Patrick Williams, one of the two people in `OWNERS` with
approval authority (the other is Manojkiran Eda; the remaining four are
reviewers), voted Code-Review −1 at 19:17 UTC on 2026-09-22:

> I'm not interested in reviewing AI-generated documentation. There are bits
> here that are potentially useful but I'm not merging something that is a
> waste of human time to read.

He marked the comment resolved. It is a statement, not a question, and it is
not answered with an argument.

**What it is about.** The cost of reading. Patchset 1 was 130 lines, and most of
them restated what the code does: the start-up sequence, the discovery
internals, the list of policy properties, a file-by-file map. A maintainer
already knows all of it, and a newcomer can read it in the code in about the
same time. 80422 was refused for describing code that did not exist; this was
refused for describing, at length, code that does.

**What an audit of patchset 1 then found**, three defects that four days of
preparation, thirteen mechanical checks, two linters and
`harness/check_upstream_commit.sh` had all passed:

| | defect | how it was found |
|:-:|---|---|
| 1 | `README.md` was added as **100755** | `git ls-tree HEAD README.md`. The file had been copied out of `/mnt/c`, where DrvFs reports every file as executable, into a tree with `core.filemode=true` |
| 2 | **the two findings this change existed for were not in the file** | the correction box in §2. `GCC` appears 0 times and `dbus-run-session` 0 times in what was sent |
| 3 | the commit message said three newcomer problems were "stated explicitly", and the file stated two | reading the file against its own message, line by line |

So the "bits that are potentially useful" were largely the ones that never
reached the file.

**Two rules in `check_upstream_commit.sh` changed because of it.** It now
refuses an executable file without a `#!` line, and run against the real
patchset 1 it reports exactly one FAIL, that one. And its `Change-Id` rule was
wrong in the other direction: it required the `Change-Id` on the last line, and
the 15 most recent commits merged into `openbmc/spdm` all put `Signed-off-by`
after it. It now requires the `Change-Id` in the last paragraph, which is where
the `commit-msg` hook reads it.

**How the vote behaves**, read from 14 changes on `openbmc/spdm` and
`openbmc/bmcweb`, because it decides what a second patchset can do. Code-Review
is copied to a new patchset only on
`changekind:NO_CHANGE OR changekind:NO_CODE_CHANGE OR changekind:TRIVIAL_REBASE OR is:MIN`.
A −1 is not the minimum, so a patchset that changes the file starts without it,
and one that changes only the commit message keeps it. The vote is not
something to argue away. Whether it comes back is decided by patchset 2.

### Patchset 2, prepared

`fd3fa9b` on branch `readme-ps2`, on top of `32e9f8b`. Upstream had moved by
one commit, which added Chinmay Shripad Hegde to `OWNERS` as a reviewer.

- **`README.md`, 59 lines, mode 100644.** What `spdmd` does today, the design
  document, how to build it, how to run the tests off a BMC, and how it runs.
  Everything that restated the code is gone.
- **The commit message is 16 lines instead of 39.** The paragraph about 80422 is
  gone, as promised on the change. `Assisted-by: Claude Code:claude-opus-5-5`
  stays, because the text was drafted with an assistant and the disclosure goes
  with it.
- **It is prepared without `Signed-off-by`.** [89452](https://gerrit.openbmc.org/c/openbmc/docs/+/89452)
  says *"AI agents MUST NOT add Signed-off-by tags"*, so the certification is
  added by the author's own command below, and not by the tool that prepared the
  commit.

Every command the README gives was run on 2026-09-23 against `32e9f8b`, on
Ubuntu 24.04, in a fresh virtualenv made the way the README says:

| the README says | what running it gave |
|---|---|
| GCC 13.3 stops with an internal compiler error in `requester/utils/mapper.cpp` | `mapper.cpp:46:5: internal compiler error: in build_special_member_call, at cp/call.cc:11096` |
| GCC 14.2 works | `CC=gcc-14 CXX=g++-14`: 863 of 863 targets |
| the compiler is chosen when the build directory is created | `meson setup` again with GCC 14 on the GCC 13 directory: *"Directory already configured"*, still GCC 13.3 |
| meson looks for `python3` on `PATH`, so activate the virtualenv | `Program python3 (inflection, yaml, mako) found: YES (/home/key/venv-spdm/bin/python3)` |
| plain `meson test` fails off a BMC | `test_policy_manager` FAIL, `AccessDenied` thrown in `SetUp()` |
| on a private bus it passes | 3 of 3 OK |
| prettier and markdownlint | clean, prettier 3.3.3 and markdownlint-cli 0.41.0, configs fetched from `openbmc-build-scripts` at `8e613ad` that day |

The first draft of the README failed its own read-through twice before any of
that ran. It told the reader to create `.venv` inside the tree, which
`.gitignore` does not cover. And it gave the GCC 14 command *after* the plain
one, which sends a reader straight into the "already configured" trap in the
table above. Both are fixed.

`check_upstream_commit.sh --profile openbmc` against `fd3fa9b` reports four
FAILs, all about the missing sign-off. Against a throwaway clone of it after
`git commit --amend -s --no-edit` (the clone was deleted afterwards), it
reports every rule satisfied.

**To send it, three steps, all of them the author's:**

```sh
cd ~/spdm-lab/work/openbmc-spdm                       # on branch readme-ps2
git commit --amend -s --no-edit                       # your DCO certification
bash /mnt/c/Users/Key20/Desktop/mctp-spdm-pqc/harness/check_upstream_commit.sh \
    --profile openbmc .                               # expect: every rule satisfied
git push gerrit HEAD:refs/for/main
```

Then one comment on the change, in the author's own words and at most four
lines: what changed, that the file mode is fixed, and an offer to drop anything
left that is not useful. Then `Done` on Chinmay Shripad Hegde's two threads.

**What happens next, decided now rather than on the day.** A −1 with a concrete
reason: fix it. A −1 because no README is wanted from this source: abandon with
two lines of thanks, and the review is still the evidence. Silence: no ping for
two weeks, which is what `CONTRIBUTING.md`'s "Pace of Review" asks, and then
one.

## 12. A second comment, and patchset 3 — 2026-09-23

**Patchset 2 was pushed** by the author at 15:59:39 UTC: `3feccaf`, 59 lines,
mode 644, his sign-off. The −1 was dropped by the copy rule §11 read off 14
changes, and CI returned `Verified+1` at 16:01:09
([job 149426](https://jenkins.openbmc.org/job/ci-repository/149426/console)).

Five minutes and forty-two seconds later, Patrick Williams replied in his own
thread on patchset 1, with no vote:

> This is still nothing like any other instructions we have.

**Three readings**, tested in this order (`LOG.md`, 2026-09-24): the
instructions are unlike the other repositories' instructions; the whole file is
unlike their files; or no README is wanted from this source. The first two can
be measured against the other repositories in an afternoon. The third can only
be answered by the reviewer, so it is what is left if the first two come back
clean.

### What was measured

The `README.md` of 34 OpenBMC repositories, fetched on 2026-09-23: sdbusplus,
phosphor-logging, entity-manager, dbus-sensors, pldm, bmcweb,
phosphor-certificate-manager, phosphor-networkd, phosphor-host-ipmid,
phosphor-state-manager, phosphor-power, phosphor-fan-presence,
phosphor-led-manager, phosphor-bmc-code-mgmt, smbios-mdr, phosphor-objmgr,
phosphor-post-code-manager, phosphor-inventory-manager, service-config-manager,
phosphor-virtual-sensor, phosphor-time-manager, phosphor-debug-collector,
phosphor-hostlogger, phosphor-dbus-interfaces, libmctp, phosphor-event,
phosphor-gpio-monitor, phosphor-hwmon, phosphor-sel-logger, phosphor-pid-control,
phosphor-ipmi-flash, phosphor-misc, bios-settings-mgr and openpower-occ-control.

| what patchset 2 told a reader | of the 34, how many say it |
|---|:-:|
| a specific GCC version | **0** |
| `dbus-run-session` | **0** |
| a virtualenv, or `pip install` | 1 (sdbusplus) |
| a named distribution | 1 (sdbusplus) |

★ And the finding that made the `dbus-run-session` line unnecessary rather than
merely unusual. OpenBMC's CI runs a repository's unit tests through
`run-unit-test-docker.sh`, which starts the container with `--privileged=true`
and wraps `unit-test.py` in `dbus-unit-test.py`: a private `dbus-daemon`,
started with `/usr/share/dbus-1/system.conf`. In the job for patchset 3
([149439](https://jenkins.openbmc.org/job/ci-repository/149439/console)),
`spdm:test_policy_manager` is `OK` and the summary is `Ok: 3`, `Fail: 0`. The
`AccessDenied` that patchset 2 documented happens outside that path. It is
real, and it is knowledge about my machine rather than about the project, which
is — as far as one sentence can be read — the distinction the comment drew.

The shape of the file, over the same 34:

| | the 34 | patchset 3 |
|---|---|---|
| length | median 91.5 lines; three are shorter than patchset 3 | 28 lines |
| a paragraph before the first section | 25 | yes |
| `## To Build` | 8, the most common build heading (`Building` 5, `Build` 2) | yes |
| a meson configure command and `ninja -C` | 19 have a meson configure command in some form (`meson build`, `meson builddir`, `meson <build directory>`, `meson setup build`, with or without options) and 18 have `ninja -C <dir>`. The literal lines `meson setup build` and `ninja -C build`: 5 and 8 | the literal lines |
| unit tests pointed at `local-ci-build.md` | 2 (pldm, phosphor-debug-collector) | yes |
| `## Hosted Services` | 1 (phosphor-post-code-manager, whose layout patchset 3 follows) | yes |
| a link to a design in `openbmc/docs` | 5 | yes |

> ★ **A count has to say what it counted.** The first summary of this survey,
> in a working note and never in this repository, said *"19 `meson setup
> build`, 18 `ninja -C build`"*. Those are the counts of two regular expressions
> that match the whole family; the literal lines are 5 and 8. The conclusion
> survives, because patchset 3's form is the family's, but it was one step from
> being published as a claim about the text.

### Patchset 3

`2ea9ab3`: what `spdmd` does, the design, `## To Build` with the two lines, the
unit tests pointed at `local-ci-build.md` as pldm does, and `## Hosted
Services`. Removed: the GCC version, the virtualenv and `dbus-run-session`. The
GCC 13.3 internal compiler error survives in the commit message's `Tested:`
line, where a reviewer reads it and a newcomer is not asked to.

Two things were caught in the hour before it was sent.

1. ★ **A `Tested:` line written before its command was run.** The first
   candidate said that `ninja -C` on the build directory *"then reports no work
   to do"*. Run, it failed: that directory had been configured with an in-tree
   `.venv`, deleted when patchset 2 was finalised. The line was rewritten to
   what ran — `meson setup` and `ninja` with GCC 14 in a fresh directory, 863
   of 863 targets at 16:34:25 UTC, and no `FAILED:`, `error:` or `warning:`
   line in the log itself — before it was signed.
2. ★★ **A sentence true on the day and false on the merge.** The README said
   *"It does not run the SPDM protocol itself; libspdm is not a dependency."*
   True of `32e9f8b`. But `openbmc/spdm` had 37 open changes, this one
   included, and a chain of them by this change's own reviewers — Ratan
   Gupta's 80264, and Chinmay Shripad Hegde's 80267 *"spdmd: Add libspdm
   dependency and device secret lib"*, among others at patchsets 38 to 42, all
   updated that day — adds `dependency('libspdm')`. The current patchsets of
   the other 36 were read for any added or removed line naming a fact the
   README states, and 80267 is the only one. The sentence was deleted rather
   than reworded, so that every remaining sentence is true before that chain
   lands and after it, only less complete after. **Checking a document against
   the tree it was written from is not checking it against the tree it will
   merge into.**

The build was not re-run after that edit, and the reason is a measurement: no
build file mentions `README.md` (`git grep -i readme` over every `meson.build`
and `meson.options`), so the build's inputs were those of the tree built at
16:34. The linters read it, and were re-run: clean, with the configs fetched
from `openbmc-build-scripts` at `e62fb77`, which had moved since §11's
`8e613ad`.

80422 was re-read too, because a reviewer had added its author. It was
**abandoned by a bot**, for failing CI and a year without activity, not
withdrawn with a plan to redo it. And Patrick's position on it — *"It is
unnecessary overhead to add a line to the README when you have a feature done?
That's rather surprising."* — is that a README tracks the merged code and grows
as features land. Patchset 3 is written to that.

**Sent at 17:08:53 UTC.** The sign-off and the push were the author's, and the
commit was checked after he signed it: its message byte-identical to the
reviewed draft plus one `Signed-off-by`, its tree different from the prepared
candidate only in `README.md`, `check_upstream_commit.sh --profile openbmc`
with no FAIL, and `git push --dry-run` accepted. CI `Verified+1` at 17:10:44
([job 149439](https://jenkins.openbmc.org/job/ci-repository/149439/console));
`README.md` 28 lines, mode 33188, which is 100644.

> The assistant's `git commit --amend` of the prepared candidate was refused by
> its own permission classifier, as a destructive git operation, and was not
> worked around. The author applied the reviewed message and signed it in one
> command of his own. The keystroke that changes a commit sent under his name
> is his: that is 89452's rule for the sign-off, and it turned out to be the
> tool's rule for the amend.

**Not sent: replies to the three open threads** — Patrick's, and Chinmay
Shripad Hegde's two on patchset 1's commit message, whose requests patchset 2
had already met. The author decided on the day to wait for the reviewers' next
move. The cost is recorded rather than argued: the notification of patchset 3
carries no word of what changed, and two threads whose requests are done stay
open.

**What happens next** is §11's rule, unchanged. A −1 with a reason: fix it. A
−1 because no README is wanted from this source: two lines of thanks, then
abandon. Silence: no ping for two weeks from the push, which is 2026-10-07.

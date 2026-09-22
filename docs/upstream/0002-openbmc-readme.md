# Change 0002 — a first README for `openbmc/spdm`

**Target:** `openbmc/spdm` at `72e3ea9` (`main`, last merged 2026-07-31)
**Pipeline:** Gerrit, `gerrit.openbmc.org`
**State: SUBMITTED, 2026-09-22** — change
[94773](https://gerrit.openbmc.org/c/openbmc/spdm/+/94773), patchset 1.
See §10.
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

**On the `Assisted-by:` trailer.** OpenBMC's `CONTRIBUTING.md` has no AI policy
— the word does not appear in the file, digest
`e27c7768eedaeded3823727087a6e8e6c7034bfb91c5a60deb7305c108480301`, read
2026-09-18. So the trailer is neither required nor forbidden, and including it
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
- Reviewers added: TODO(me)
- CI result:  TODO(me)
- Review round trips:
    Patchset 1 -> TODO(me)
- What I learned from this review, specifically: TODO(me)
- Outcome: open, status NEW
```

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

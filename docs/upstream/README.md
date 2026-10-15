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
| Individual CLA sent to `manager@lfprojects.org` | **done** | 2026-08-04 | signed as the legal name; one agreement covers every OpenBMC repository — **and nothing outside OpenBMC**, see below |
| DMTF's requirements read, from its own `CONTRIBUTING.md` | **done** | 2026-09-13 | **no CLA exists**: DCO sign-off only, plus a mandatory `Assisted-by:` trailer for AI-assisted commits. Checked by `harness/check_upstream_commit.sh` rather than by a checklist |
| Gerrit account, SSH key, `~/.ssh/config` | **done** | 2026-08-04 | `ssh openbmc.gerrit` returns a greeting with the account's full name |
| Gerrit profile full name corrected | **done** | 2026-08-04 | GitHub OAuth had populated it with a short form — see the third trap below |
| `commit-msg` hook installed (Change-Id) | **done** | 2026-08-04 | hook served by Gerrit 3.11.7 |
| Submission pipeline rehearsed end to end | **done** | 2026-08-05 | a `%private,wip` change, three patchsets, abandoned once verified |
| git identity matches Gerrit in every environment | **done** | 2026-08-11 | legal name in both the WSL and the Windows git config |
| Community channel joined, reading only | **`TODO`** | | |
| OpenBMC's requirements read, from `openbmc/docs` `CONTRIBUTING.md` | **done** | 2026-09-18 | **no AI policy exists**: the word does not appear in the file, sha256 `e27c7768…` — ★ *corrected 2026-09-22 by a reviewer: a policy is in review, `openbmc/docs` 89452, and a grep of the merged file could not see it.* Gerrit, a `Change-Id` from the commit-msg hook, a full real name in the sign-off, 50/72, and a CLA that is separate from the DCO. Encoded as `harness/check_upstream_commit.sh --profile openbmc`, with six cases it must refuse |
| **This project's** target repository built locally | **attempted** | 2026-08-11 | five distinct blockers, below |
| Second candidate found, evidence assembled | **done** | 2026-08-17 | `DMTF/spdm-emu` `--help` disagrees with its own defaults — see below |
| Third and fourth candidates found, each with a capture | **done** | 2026-09-01 | `spdm-emu`: a discarded slot-0 read result, and a requester that never inspects `NO_AUTHORITY` — see below |
| Fifth candidate found while writing a proxy | **done** | 2026-09-10 | `spdm-emu`: `command.h` documents the socket payload as starting at the SPDM header when a transport byte precedes it — see below |
| Sixth through twelfth found by running the published example | **done** | 2026-09-12 | `spdm-emu`'s `spdm_device_verifier_tool` does not work: **seven** findings, and the two that matter are in one function and mask each other — `verify` has never verified a signature, and would accept any signature if only the first were fixed. See below |
| Thirteenth found while pinning an A/B's control variables | **done** | 2026-09-14 | `spdm-emu`: `--req_asym NONE --req_pqc_asym NONE` parses, echoes back, and then makes the handshake impossible — the responder requires exactly one requester signature algorithm whenever `MUT_AUTH_CAP` is supported, and `--mut_auth NO` does not clear that capability bit. Six packets and a bare status code. See below |
| Fourteenth through seventeenth, from measuring across the transport | **done** | 2026-09-14 | `spdm-emu`: ~~`--cap` is parsed by the requester and never read~~ *(withdrawn 2026-09-29: never true)*; every invalid argument exits **0**; **no signed operation completes with SLH-DSA** on a default build that ships its sample certificates; and `DataTransferSize` — the parameter that decides round trips — has no flag, for which a 55-line patch with a control exists. See below |
| Eighteenth and nineteenth, from the official conformance suite | **done** | 2026-09-20 | `spdm-emu`: the validator sample's configuration array and the `SPDM-Responder-Validator` submodule it configures disagree **in both directions** — three implemented cases are never requested, including the only two that test SPDM 1.3, and one requested case does not exist and prints nothing. And `SPDM-Responder-Validator` itself: a case whose message mask omits `GET_CERTIFICATE` reports the device's **valid** signature as FAIL, because the case's own `libspdm_init_connection` freed the chain its setup fetched. **Proved**, not argued — `harness/challenge_verify.py` verifies the disputed signatures against the leaf key after calibrating on the ones the suite accepts. See below |
| SPDM 1.5 hybrid-PQC public review read, feedback drafted | **done** | 2026-08-31 | [`spdm15-hybrid-feedback.md`](spdm15-hybrid-feedback.md); the WIP itself, 8 pages, `sha256 3e5366a3…` |
| …submitted to the DMTF Feedback Portal | **not recorded as submitted** | window closed 2026-08-31 | it needed a portal account, and nothing here records it being sent before the public review closed. Kept as a draft; the window is not coming back |
| **This project's** first change **SENT** | **done** | prepared 2026-09-12, **sent 2026-09-22** | [`DMTF/spdm-emu` #524](https://github.com/DMTF/spdm-emu/pull/524) — `CoRimTool.py verify` does not verify. Rebased onto `16119ea` and every `Tested:` line re-asserted in the hour before the push; `patch-id` and blob came through unchanged. DCO check green. Reviewers assigned by CODEOWNERS: **jyao1**, **steven-bellock**. See [`0001-corim-verify.md`](0001-corim-verify.md) §8 |
| **This project's** second change **SENT** | **done** | prepared 2026-09-18, **sent 2026-09-22** | [`openbmc/spdm` 94773](https://gerrit.openbmc.org/c/openbmc/spdm/+/94773) — a first `README.md`, written against the review that killed the 2025 attempt. Upstream `main` had **not** moved; both linters had vanished from the machine and were reinstalled at their pinned versions and re-run clean. See [`0002-openbmc-readme.md`](0002-openbmc-readme.md) §10 |
| **This project's** first change submitted | **done** | 2026-09-22 | scheduled W03 → slipped → prepared W06 → prepared W09, two of them → W10 re-verified both against an unchanged upstream → **both sent on the same day, each after its own freshness check, and one of those checks changed what was sent** (0001 was rebased; 0002's linters had to be reinstalled before they could agree) |
| Reviewer response received | **done** | 2026-09-22, **35 minutes after the push** | `openbmc/spdm` 94773: CI `Verified+1`, then two inline comments from **Chinmay Shripad Hegde** — who was also a reviewer on the change this one supersedes. Neither is a change request; one supplies context on 80422 and adds its original author, the other points at an AI-assistant policy this project had concluded did not exist. Both answered the same day, every factual claim in the replies checked mechanically first. All six people in `OWNERS` are now on the change, **including Patrick Williams**, who rejected 80422. `DMTF/spdm-emu` #524: DCO green, no human response yet |
| ★ **The first −1** | **received** | 2026-09-22, 19:17 UTC | Patrick Williams, one of the two owners with approval authority, on 94773 patchset 1: *"I'm not interested in reviewing AI-generated documentation. There are bits here that are potentially useful but I'm not merging something that is a waste of human time to read."* An audit then found three defects in patchset 1 that every earlier check had passed, including that the two findings the change existed for were **not in the file**. [`0002`](0002-openbmc-readme.md) §11 |
| Patchset 2 | **pushed** | 2026-09-23, 15:59 UTC | 59 lines instead of 130, mode 644, every command in it re-run that day against `32e9f8b`. Prepared **without** `Signed-off-by`, because 89452 says an AI agent must not add one; signed and pushed by the author. The −1 dropped by the copy rule, CI `Verified+1`. [`0002`](0002-openbmc-readme.md) §11–§12 |
| A second comment from the same owner | **received** | 2026-09-23, 16:05 UTC, under six minutes after the push | Patrick Williams, no vote: *"This is still nothing like any other instructions we have."* Measured against 34 other OpenBMC READMEs: what patchset 2 added — a GCC version, `dbus-run-session`, a virtualenv — appears in 0, 0 and 1 of them, and OpenBMC's CI starts its own `dbus-daemon`, under which the test patchset 2 documented passes. [`0002`](0002-openbmc-readme.md) §12 |
| Patchset 3 | **sent** | 2026-09-23, 17:08 UTC | 28 lines in the layout the other repositories use; CI `Verified+1`. Caught in the hour before it: a `Tested:` line written before its command ran, and a README sentence the reviewers' own open chain (80267, *"Add libspdm dependency"*) would have made false on merge. Replies to the three open threads **not sent**, by the author's decision on the day. [`0002`](0002-openbmc-readme.md) §12 |
| ★★ **The first change MERGED** | **done** | 2026-09-28, 14:43 UTC | [`DMTF/spdm-emu` #524](https://github.com/DMTF/spdm-emu/pull/524), merged by **Jiewen Yao** (`jyao1`) six days after it was opened. Two minutes earlier **Steven Bellock** (`steven-bellock`) labelled it `bug` and removed his own review request. Those two are the maintainers `CODEOWNERS` adds to every pull request. No comment and no review from either: the whole exchange is a label and a merge. It landed as **`b015187`**, rebased onto `16119ea`, with tree and message byte-identical to `d7ceeaa` and `CoRimTool.py` at blob `a5762c04…`, the bytes that were tested. It is in the `4.0.0-rc2` tag cut the next day. [`0001`](0001-corim-verify.md) §8 |
| Every unsent candidate, re-read at upstream's head | **done** | 2026-09-29 | ⑲ had been **fixed upstream five days before this project found it**; ⑱ is half fixed; ⑭ was **never true** and is withdrawn; ⑬ and ⑯ persist on 4.0.0-rc2. And ⑳, found while testing 0004, turned out to be **upstream issue #358, open since 2024** — found by the duplicate search, before it was written up as new. [§ Merged, and every candidate re-read at the head](#merged-and-every-candidate-re-read-at-the-head--2026-09-29) |
| Two more changes prepared | **prepared** | 2026-09-29 | ⑤ as [`0003`](0003-corim-exit-status.md), the follow-up #524's own description offered; ⑰ as [`0004`](0004-data-transfer-size.md), rebuilt and re-tested on 4.0.0-rc2, where porting it found two defects in this project's own version of the patch. Prepared unsigned: the sign-off and the push are the author's |
| ★ **Both SENT** | **done** | 2026-09-29, 15:14 UTC | [`DMTF/spdm-emu` #526](https://github.com/DMTF/spdm-emu/pull/526) (0003) and [#527](https://github.com/DMTF/spdm-emu/pull/527) (0004), the same evening, each after its freshness checks and its `Tested:` lines were re-run in the hour before. DCO green; upstream CI 45 of 45 on both, including the two VS2019 builds 0004 had never met. [§ Two more sent](#two-more-sent--2026-09-29) |
| `openbmc/spdm` 94773 | **in review, no movement** | checked 2026-09-29, 19:14 UTC | patchset 3 still current, CI `Verified+1`, no vote, three threads unresolved, last activity 2026-09-23 17:10 UTC, and no open change in the project has moved since. No ping before 2026-10-07, as decided |
| Every unsent candidate re-read at its owner's head, **and searched for upstream** | **done** | 2026-09-30 | 19:14–19:39 UTC on the 29th. All thirteen still present; 29 searches, the first for any of them, and **none reported**; #526 and #527 unchanged and unreviewed, the runs behind their `Tested:` lines repeated on the bytes GitHub serves. Two of this file's citations were wrong and are corrected, and two of this project's tools could not see what the check needed; both fixed that day. [§ Every candidate re-read, and searched for](#every-candidate-re-read-and-searched-for--2026-09-30) |
| #526 approved | **approved** | 2026-09-29, 23:36 UTC | by **Steven Bellock** (`steven-bellock`), one of the two maintainers CODEOWNERS assigns, eight hours after it was sent and without a comment. `jyao1` is still requested, and nothing is merged. Read on 2026-10-03 |
| #527 reviewed, and built on | **reviewed** | 2026-09-30, 10:03–10:08 UTC | by `LeonLinAtAMI`, a regular contributor who is not one of the two CODEOWNERS: a comment, an approval and one inline suggestion, which is correct and was acknowledged without amending the commit. On 2026-10-02 he opened [#531](https://github.com/DMTF/spdm-emu/pull/531), whose first commit is #527's `367414a`, byte for byte, and whose second extends it. [§ Two more sent, one of them a question](#two-more-sent-one-of-them-a-question--2026-10-04) |
| Candidate 3 reported by someone else | **not this project's** | 2026-10-02 | [#532](https://github.com/DMTF/spdm-emu/issues/532), by `annamdi`: the shared `res` that hides a failed slot read, found while deploying the responder, with a fix offered |
| ★ Two more **SENT**: a question and a pull request | **done** | 2026-10-03, 19:38 and 19:46 UTC | candidate 4 as issue [#533](https://github.com/DMTF/spdm-emu/issues/533), re-measured on the head that day; candidate 5 as [#534](https://github.com/DMTF/spdm-emu/pull/534), re-measured on four transports. Both texts are byte-identical to the drafts the author reviewed; the sign-off, the push and both submissions are his. [§ Two more sent, one of them a question](#two-more-sent-one-of-them-a-question--2026-10-04) |
| `openbmc/spdm` 94773 | **in review, no movement** | checked 2026-10-03, 20:00 UTC | unchanged since 2026-09-23 17:10 UTC: patchset 3, CI `Verified+1`, no Code-Review vote. No ping before 2026-10-07 |
| ★★ **Three more MERGED: four of four** | **done** | 2026-10-04, 10-05 and 10-12 | [#534](https://github.com/DMTF/spdm-emu/pull/534) by **Steven Bellock** seven hours after it was opened, approved and labelled `documentation` without a comment; [#526](https://github.com/DMTF/spdm-emu/pull/526) by him on 10-05, six days after his approval; [#527](https://github.com/DMTF/spdm-emu/pull/527) by **Jiewen Yao** on 10-12, with no maintainer review — its only review was a contributor's. Each landed by rebase with its commit message and every changed file's blob byte-identical to what was sent: `13edd65`, `532f667`, `fd75485`. [§ Four of four merged](#four-of-four-merged-and-the-rest-re-read--2026-10-12) |
| #533 answered | **answered** | 2026-10-12, 14:47 UTC | `steven-bellock` assigned it to `LeonLinAtAMI` and chose the smaller of its two proposals: *"Since this is a warning, I would go with option 1."* The change is assigned, so none is sent from here |
| #532, candidate 3's issue | **a maintainer's** | 2026-10-12, 14:45 UTC | assigned to `jyao1`, who wrote: *"Since we deprecate SLOT_COUNT in libspdm, we can deprecate slot_count parameter."* |
| `openbmc/spdm` 94773 | **in review, no movement** | checked 2026-10-12 | unchanged since 2026-09-23 17:10 UTC. Gerrit's attention set holds the author and neither owner, and three threads are unresolved, so to an owner the change is waiting on its author. **The author's decision, 2026-10-12: wait one more week** |
| Every unsent candidate re-read at `spdm-emu` `8f36665` | **done** | 2026-10-12 | all still present. ④ turned out to need no maintainer's call, and ⑥ and ④ are the two worth sending; 2 and ⑮ wait for the four open pull requests that edit the same two functions. [§](#four-of-four-merged-and-the-rest-re-read--2026-10-12) |
| Candidate ⑥ prepared | **prepared** | 2026-10-13 | *SpdmSamplePolicy: parse on OPA 1.0 and later*: `5800c37` on `8f36665`, unsigned, every `Tested:` line run against the committed bytes. The sign-off, the push and the pull request are the author's. [§](#the-sample-policy-on-opa-1x-prepared--2026-10-13) |
| ★ Candidate ⑥ **SENT** | **done** | 2026-10-12, 16:52 UTC | [`DMTF/spdm-emu` #536](https://github.com/DMTF/spdm-emu/pull/536), after a second look the author asked for, which found the message claiming more about old OPA releases than had been run: measured on 0.58.0, 0.59.0 and 0.70.0, corrected, re-signed as `09557d7` with the tree unchanged. Body byte-identical to the draft; reviewers by CODEOWNERS. [§](#the-sample-policy-on-opa-1x-prepared--2026-10-13) |
| ★★ #536 **MERGED: five of five** | **done** | 2026-10-13, 06:45 UTC | by **Jiewen Yao** (`jyao1`), fourteen hours after it was opened, with no review and no comment. Landed by rebase as **`1229103`**, on `c1bdbe0` — #531, merged two minutes earlier — with the commit message, the author and the policy file's blob (`4956c74d`) byte-identical to `09557d7`. All five pull requests this project had sent to `DMTF/spdm-emu` by then are merged. [§](#candidate-4s-change-sent-as-537--2026-10-13) |
| #533: the change asked of this project | **asked** | 2026-10-12, 17:29 UTC | by the assignee, `LeonLinAtAMI`: *"Please go ahead and base your PR on #530, since it touches the same call sites."* Every `get_certificate` call, the attester sample's included. This supersedes the 14:47 row's "none is sent from here". [§](#candidate-4s-change-sent-as-537--2026-10-13) |
| ★ Candidate 4's change **SENT** | **done** | 2026-10-13, 13:19 UTC | [`DMTF/spdm-emu` #537](https://github.com/DMTF/spdm-emu/pull/537), stacked on #530: a line naming the slot after each of seven calls, every `Tested:` claim measured against a build without the change. The freshness check before the sign-off found #530 rebased, and #536 and #531 merged, in the eighteen hours since it was prepared; the commit was moved, every run repeated with the same results, and one `Tested:` sentence that had become false rewritten. Signed by the author as `5195934`; body byte-identical to the reviewed file. [§](#candidate-4s-change-sent-as-537--2026-10-13) |
| Candidate 21, found while testing it | **recorded, not sent** | 2026-10-13 | `spdm_device_attester_sample` cannot connect to `spdm_responder_emu`: its `GET_CAPABILITIES` sets no `CHUNK_CAP` while `DataTransferSize` (4,608) differs from `MaxSPDMmsgSize` (163,840), so the responder answers `InvalidRequest`. Identical at `eff07cf`, so neither #527 nor #531 caused it; the program exits 0 regardless, and no workflow runs it. Since #531, `--max_spdm_msg_size 4608` gets it through |
| #537 approved, and asked for on `main` | **approved** | 2026-10-15, 01:59 and 02:01 UTC | `jyao1` approved `5195934` and wrote: *"In general please do not rely on unapproved branch, that will cause dependency issue unnecessarily. Please just rebase to latest main and resolve conflict, then we can merge easily."* `LeonLinAtAMI` had proposed the same order the day before: #537 first, and #530 rebased on top of it. [§](#537-rebased-onto-main-and-the-corim-names-sent-as-542--2026-10-15) |
| ★ #537 rebased onto `main` | **done** | 2026-10-15, 13:16 UTC | `9fdfdf1` on `8674afe`, signed by the author, with the added and removed lines `jyao1` approved; every `Tested:` run repeated on `main`, with the same results. The conflict GitHub showed had been #530's: its commit conflicts with `main` in four files #537 does not touch, and #537's commit alone merges clean. Body edited and a reply posted by the author; checks 45 of 45, `clean`. [§](#537-rebased-onto-main-and-the-corim-names-sent-as-542--2026-10-15) |
| #532, candidate 3's issue | **closed**, and the defect is not gone | 2026-10-15, 01:36 UTC | closed by `jyao1`'s #538, which removed `--slot_count`. The shared `res` that #532 also described, and that candidate 3 is, is unchanged at `8674afe` |
| ★ Candidate ④ **SENT** | **done** | 2026-10-15, 13:44 UTC | [`DMTF/spdm-emu` #542](https://github.com/DMTF/spdm-emu/pull/542), *CoRimTool: encode every hash and role name*: `0bdb70b` on `8674afe`, +3 −3, signed by the author; body byte-identical to the reviewed file; reviewers by CODEOWNERS. [§](#537-rebased-onto-main-and-the-corim-names-sent-as-542--2026-10-15) |
| Candidate 20 at `8674afe` | **does not reproduce** | 2026-10-15 | `--trans NONE` with `CHUNK_CAP` cleared starts, and `CAPABILITIES` carries `DataTransferSize` = `MaxSPDMmsgSize` = 4,736. #358 is still open, and still not this project's |
| Candidate 16's sentence about silence | **corrected** | 2026-10-15 | this file and [`../pqc-cost.md`](../pqc-cost.md) said the SLH-DSA requester exits 1 "having printed nothing". Both signed arms' logs begin `ERROR: do_authentication_via_spdm - 80020001`, `LIBSPDM_STATUS_VERIF_FAIL`, and had since the day the sentence was written |
| ★★ #537 **MERGED** | **done** | 2026-10-15, 14:07 UTC | by **Jiewen Yao** (`jyao1`), by rebase, as **`423ba4e`** on `8674afe`, with the tree and the message of `9fdfdf1`, the author's: 52 minutes after the rebase was pushed, 27 after the reply. #533 closed with it. Six of the seven pull requests this project has sent to `DMTF/spdm-emu` are merged. One check on `main` failed afterwards, in `actions/checkout`, fetching a third-party submodule, before anything was compiled. [§](#merged-and-the-red-check-after-it) |

> **Not a deliverable of this project.** A change to `openbmc/docs` was
> submitted on 2026-08-11 under the other project. It appears nowhere in this
> repository's results and is mentioned only because of what it removes: the
> path from `git commit -s` to a change sitting in Gerrit has been walked once
> already, so what this project still owes upstream is a technical problem, not
> an administrative one.

## Candidates, and my judgement on each

Twenty-one candidates have been recorded. Eight went as changes — #524, #534,
#526, #527, #536 and #537 are merged, and 94773 and #542 are in review — and
one of the eight, candidate 4, went first as a question, issue #533, whose
assignee then asked this project for the change. Two were fixed upstream by the
maintainer without this project, one of them before this project had found it,
and one, candidate 3, was reported by someone else on 2026-10-02, in an issue
the maintainer closed on 2026-10-15 without changing the lines this row is
about. One, ⑭, was never true and is withdrawn, and one, ⑳, had been reported
upstream two years earlier, and no longer reproduces. The judgement column is the part worth reading, because it
records what was **not** sent and why, and that is a decision a reviewer never
sees. *Every row was re-read against upstream `main` on 2026-09-29, not against
the pinned tree it was found in; the section after "Both sent" says why that
distinction turned out to matter. And again on 2026-09-30, when each unsent
row was also searched for upstream, which until then had been done only for
the rows that were sent ([§](#every-candidate-re-read-and-searched-for--2026-09-30)).
Rows 3, 4, 5, 17 and 20 changed on 2026-10-04 ([§](#two-more-sent-one-of-them-a-question--2026-10-04)),
and rows 2–5, 8–11, 15, 17, 18 and 20 on 2026-10-12, when every unsent row was
re-read at `8f36665` ([§](#four-of-four-merged-and-the-rest-re-read--2026-10-12)).
Rows 4 and 8–11 changed, and row 21 was added, on 2026-10-13 ([§](#candidate-4s-change-sent-as-537--2026-10-13)).
Rows 2–4, 8–11, 15, 16, 20 and 21 changed on 2026-10-15, when every unsent row
was re-read at `8674afe` ([§](#537-rebased-onto-main-and-the-corim-names-sent-as-542--2026-10-15)).*

| # | where | the candidate | evidence | judgement |
|:-:|---|---|---|---|
| 1 | `openbmc/spdm` | no `README.md`, and a newcomer hits five build and test blockers with nothing to say they are expected | five blockers reproduced on 2026-08-11 and 2026-09-18, and re-run on 2026-09-23 | **sent**, 94773. The review of the 2025 attempt was read first and treated as the specification. A minimum compiler version was deliberately **not** part of it: that is a policy change, and a first change should not start an argument |
| 2 | `DMTF/spdm-emu` | `--help` omits three capabilities the defaults set | two source lines, and the `Flags` word on the wire | not sent: correct and small, but a text fix outranked by ② on usefulness, and a second change to a project before the first is answered is two conversations that do not happen. *2026-10-12: unchanged at `8f36665` — the defaults still set `CHUNK` and `EP_INFO_SIG`, and the responder's `MEL`, and the `By default` lines still omit them. Four open pull requests edit `print_usage()`, so it waits for them. 2026-10-15: unchanged at `8674afe` — `key.c` still sets `CHUNK` and `EP_INFO_SIG` for both and `MEL` for the responder, and neither `By default` line names them. #529 and #531 have merged; #530 and #496 still edit `print_usage()`* |
| 3 | `DMTF/spdm-emu` | a slot-0 certificate read whose failure is discarded | `w4-tamper` `t3_cert`: the only trace is `ProvisionedSlotMask` 0x13 → 0x12 | not sent: sample-code robustness, queued behind ②. *2026-10-04: reported by someone else, [#532](https://github.com/DMTF/spdm-emu/issues/532) (`annamdi`, 2026-10-02), found while deploying the responder and filed with a `--slot_count` question; its author offers the fix. Not sent from here. 2026-10-12: the maintainer proposes deprecating `--slot_count` instead. 2026-10-15: #532 closed by `jyao1`'s #538, which removed `--slot_count`. The shared `res` is unchanged at `8674afe` — `spdm_responder_spdm.c` reads slots 0, 1 and 4 into it, lines 506–557, and tests it once, at 565 — so the issue that reported this row is closed and the defect is not. Whether to raise it again is the author's question; #532's reporter had offered a fix* |
| 4 | `DMTF/spdm-emu` | the requester never checks `VERIF_NO_AUTHORITY` | `t3b_foreign` completes a handshake against a root it was never given | **merged**: sent as [#537](https://github.com/DMTF/spdm-emu/pull/537) on 2026-10-13, after it was asked as issue [#533](https://github.com/DMTF/spdm-emu/issues/533) on 2026-10-03, and merged on 2026-10-15 as `423ba4e`. The library reports it as a warning **by design** — libspdm #1773 and #1774 made it one in 2023, so that the integrator decides — so it went as a question about what a sample should teach, not as a defect. Re-measured on the head first: `0x40020003` returned three times and ignored, and the same 578 messages as with the stock trust anchor. *2026-10-12: `steven-bellock` chose option 1 — a line naming the slot, and carry on — and assigned the issue to `LeonLinAtAMI`, whose #530 changes the same calls. Not sent from here; the issue's reproduction is what this project can offer the change. The same evening the assignee asked for the change itself, on top of #530 and covering every call; sent on 2026-10-13 as #537, after each of the seven calls had been made to print ([§](#candidate-4s-change-sent-as-537--2026-10-13)). 2026-10-15: approved by `jyao1`, who asked for it on `main` rather than on the unapproved #530; rebased as `9fdfdf1` with the same added and removed lines, and every run repeated with the same results ([§](#537-rebased-onto-main-and-the-corim-names-sent-as-542--2026-10-15)); merged by him at 14:07 UTC as `423ba4e`, byte-identical* |
| 5 | `DMTF/spdm-emu` | `command.h` says the socket payload starts at the SPDM header; for MCTP it starts one byte later | any capture here, and `tamper_proxy.py` | **merged**: sent as [#534](https://github.com/DMTF/spdm-emu/pull/534) on 2026-10-03, once #526 had been answered, and merged seven hours later as `13edd65`. Re-measured on four transports first: the comment is right for NONE only — MCTP, the default, puts one byte in front of the SPDM header, PCI_DOE eight and TCP four — so the change says what comes first for each. #408 quoted the comment; #244 asked the question it now answers |
| 6 | `DMTF/spdm-emu` | ① `requirements.txt` has no upper bounds and the ceiling has arrived | a fresh virtualenv, 2026-09-12 | **named in #524's body** as the workaround a reviewer needs; not a change of its own |
| 7 | `DMTF/spdm-emu` | ② `CoRimTool.py verify` has never verified a signature, in two lines that mask each other | re-running the commit's own `Tested:` lines: fixing one line alone makes it accept anything | **merged**, #524, 2026-09-28, as `b015187`, and in the `4.0.0-rc2` tag. Both lines in one change, because the first alone is the more harmful state — measured, not reasoned |
| 8–11 | `DMTF/spdm-emu` | ③ `json_to_cbor` cannot read `cbor_to_json`'s output; ④ `translate_data` hard-codes two names; ⑤ `verify` exits 0 on failure; ⑥ the sample policy does not parse on OPA 1.x | each reproduces with the tool's own sample data | ⑤ **merged**: sent as [#526](https://github.com/DMTF/spdm-emu/pull/526) ([`0003`](0003-corim-exit-status.md)) on 2026-09-29 — #524's description had offered it, and at `eff07cf` a forged signature still exits 0 — and merged on 2026-10-05 as `532f667`. ③ ④ ⑥ not sent and still present at `eff07cf`; three of them need a maintainer's call on which form is canonical. *2026-10-12: all three still present at `8f36665`. ④ needs no call after all: the tables it should consult, `SupportHashAlgMap` and `ComidRoleTypeChoice`, are in the same file. ⑥'s only call is which OPA releases it should still parse on. Both are sendable; ③ is a question first. 2026-10-13: ⑥ prepared, then sent as [#536](https://github.com/DMTF/spdm-emu/pull/536) ([§](#the-sample-policy-on-opa-1x-prepared--2026-10-13)), and merged on 2026-10-13 at 06:45 UTC as `1229103`, byte-identical. 2026-10-15: ④ sent as [#542](https://github.com/DMTF/spdm-emu/pull/542) ([§](#537-rebased-onto-main-and-the-corim-names-sent-as-542--2026-10-15)); ③ unchanged at `8674afe`, `cbor_to_json`'s output still stopping `json_to_cbor` at `KeyError: 'corim'`* |
| 12 | `DMTF/spdm-emu` | the sample policy does not check what it appears to check | [`../rats-pipeline.md`](../rats-pipeline.md) §5 | not a defect to report: a design finding, kept where the design is discussed |
| 13 | `DMTF/spdm-emu` | `--req_asym NONE --req_pqc_asym NONE` parses, then makes every handshake impossible | the bisection in `LOG.md`, 2026-09-14; four arms that work in `w7-pqc-ab` | not sent: three possible fixes, and the one that makes the flags mean what they say changes behaviour others may rely on — a conversation, not a patch. *Re-read 2026-09-29: libspdm 4.0.0-rc2 carries the same rule. `490f02c` (2026-09-07) changed when the responder emulator asks for mutual authentication, which is a different thing* |
| 14 | `DMTF/spdm-emu` | ~~`--cap` is parsed by the requester and never read, and echoed as if it were~~ | ~~a `grep` of every reader of the variable~~ | ★ **withdrawn 2026-09-29: it was never true.** The requester has applied `--cap` since `ef556a0` (2022-12-21), and the pinned tree has the two lines that do it. Measured: `--cap CERT,CHAL` on the requester puts `Flags 0x00000006` on the wire where the default puts `0x0002f7c6`. The evidence cell had been a `grep` whose printed output was abbreviated by hand, and the abbreviation is where the requester's line went. See § ⑭ below |
| 15 | `DMTF/spdm-emu` | every invalid argument exits 0 | `grep -c 'exit(0)'` | not sent: mechanical, and 78 sites at the pin have become 91 at `eff07cf`. It bit this project's own testing of 0004 twice on 2026-09-29: `--pcap` with `--trans NONE` or `TCP` prints the usage and exits 0. *2026-09-30: all 91 are in `process_args()`, where #527 adds 25 lines and the maintainer's #496 adds 54, so it goes after both. 2026-10-12: 93 at `8f36665`, and the four open pull requests that edit `process_args()` add fifteen more between them. After they land, and as a question first. 2026-10-15: 98 at `8674afe`, every one in `process_args()`; #529 and #531 have merged, and #530 and #496 still edit it* |
| 16 | `libspdm` / `spdm-emu` | no signed operation completes with SLH-DSA on a default build | `w8-pqc-matrix` `S1-*`: bisected to requester-side signature verification | **not sent, and not sendable yet**: the root cause needs a Debug build this project has not made, and a report without one asks the maintainer to do the work. *Re-run on 4.0.0-rc2, 2026-09-29: S1 still exits 1, P1 exits 0. 2026-10-15: the status was never unrecoverable. Both signed arms' logs begin `ERROR: do_authentication_via_spdm - 80020001`, `LIBSPDM_STATUS_VERIF_FAIL` — the status the README's Table 1 shows for a measurement or a signature altered in flight — so this row's premise that nothing was printed was false, and it is corrected in § ⑯ and in `../pqc-cost.md`. What a Debug build would add is which check fails. Not re-run at `8674afe`* |
| 17 | `DMTF/spdm-emu` | `DataTransferSize` has no run-time flag | a 55-line patch, a sweep, and a control that proves it inert | **merged**: sent as [#527](https://github.com/DMTF/spdm-emu/pull/527) ([`0004`](0004-data-transfer-size.md)), rebuilt on 4.0.0-rc2, and merged on 2026-10-12 as `fd75485`. Porting it found two defects in this project's version, neither of which the sweep could reach: with `CHUNK_CAP` cleared it advertised a `MaxSPDMmsgSize` larger than its `DataTransferSize`, which the peer rejects (`0x80010005`, measured on the `pqc-dts` build), and on `--trans NONE` it advertised 128 bytes more than asked. *2026-10-04: reviewed and approved by a contributor, `LeonLinAtAMI`, whose [#531](https://github.com/DMTF/spdm-emu/pull/531) is built on its commit, unchanged* |
| 18 | `DMTF/spdm-emu` | the validator sample's configuration and the suite disagree in both directions | `--audit-config` recomputes the table from the two files | **half fixed upstream**, without this project: `eff07cf`, 2026-09-29, registers both `SUCCESS_13` cases, which were the half that mattered. `CERTIFICATE_SIZE_REQ` is still not registered and `CERTIFICATE_SPDM_X509_CERTIFICATE` is still registered and not implemented — `--audit-config`, 83 implemented, 83 registered. Two lines remain. *2026-10-12: the same two, at `8f36665` with the suite at `7acde98`. Not sent: the maintainer re-syncs this array himself* |
| 19 | `SPDM-Responder-Validator` | a conformance case reports FAIL for a correct signature, because it discarded the chain it fetched | `challenge_verify.py`: calibration 9/9, disputed 2/2 verified | ★ **fixed upstream before this project found it.** `65bcccc` and `ad6db5c`, authored 2026-09-07 and 09-14, on the suite's `main` on 2026-09-15; this row was written on 2026-09-20, against the submodule pointer `c27bb1c`. Not sendable. The fix's own commit message names the mechanism this entry derived, and repairs it the way this entry preferred |
| 20 | `DMTF/spdm-emu` | `--trans NONE` with `CHUNK_CAP` cleared cannot start | unpatched `eff07cf`: the responder exits 1 before listening and prints nothing, where MCTP with the same capabilities completes. `MaxSPDMmsgSize` is computed from a 128-byte transport overhead NONE does not register, so `DataTransferSize` (4,736) exceeds it, and libspdm's context check requires the opposite. Setting the two equal with 0004's flag, and changing nothing else, makes it start | ★ **already reported upstream**: [#358](https://github.com/DMTF/spdm-emu/issues/358), opened 2024-07-28 by `arugan02`, labelled `bug`, open, with the same error text and the same diagnosis. The reporter offered a pull request and a maintainer answered *"that seems reasonable"*; none arrived. Found by the duplicate search before this row was written as a new finding. What this project adds is narrower: re-confirmed on 4.0.0-rc2, and since the maximum message size with chunking became `0x28000` it reproduces only with `CHUNK_CAP` cleared. 0004 is a workaround, not the fix; the fix is one line once 0004's helper exists, and would go as its own change referencing #358. *2026-09-30: #358 is assigned to its reporter, so the first step is a question there, not a pull request. 2026-10-04: [#531](https://github.com/DMTF/spdm-emu/pull/531) changes the default path on `--trans NONE` so that `MaxSPDMmsgSize` follows `DataTransferSize`, which reads as the fix for #358. It does not cite #358, and no build here has checked it. 2026-10-12: #531 has to resolve a conflict with the merged #527 first; after that, one build measures whether it closes #358. 2026-10-13: #531 merged as `c1bdbe0`; that build has not been run. 2026-10-15: it does not reproduce at `8674afe`: the responder with `--trans NONE` and `CHUNK_CAP` cleared starts, and `CAPABILITIES` carries `DataTransferSize` = `MaxSPDMmsgSize` = 4,736; with the requester's `CHUNK_CAP` cleared instead, or both, it exits 0 with no `ERROR:` line. Not bisected to #531. #358 is open, and a line there would be the author's* |
| 21 | `DMTF/spdm-emu` | `spdm_device_attester_sample` cannot connect to the responder it ships with | its `GET_CAPABILITIES`, read off the wire at `eff07cf`, and again on `1229103` under #530, which does not touch the sample: `Flags` `0x000072c6`, no `CHUNK_CAP`, `DataTransferSize` 4,608, `MaxSPDMmsgSize` 163,840. libspdm requires the two sizes to be equal without `CHUNK_CAP` (`libspdm_rsp_capabilities.c` 239–244 at `a6994ee`), so the responder answers `ERROR(InvalidRequest)`, `libspdm_init_connection` returns `0x8001000a`, and the program exits 0 | not sent. Found on 2026-10-13 while testing #537, whose attester half had to be run with a local patch because of it. Before #531 no option got past it: the sample never sets the SPDM version, so `--ver` changes nothing (measured from 1.0 to 1.4), and `process_args()` accepts `--cap` only from the requester and the responder. Since #531, `--max_spdm_msg_size 4608` does: the request then carries 4,608 twice, and the sample collects its chains and its measurement — measured, and found only when this row's first wording, "no command line gets past it", was audited. The sample also passes `chunk_cap = true` to #531's size helpers without setting `CHUNK_CAP`, so by the rule above one word or one flag would fix the default — inferred, not built. A question first, because which of the two is upstream's call. *2026-10-15: unchanged at `8674afe`: the same request, `0x000072c6` with 4,608 and 163,840, the same `ERROR(InvalidRequest)`, and `--max_spdm_msg_size 4608` still gets it through* |

**How the two were chosen**, in the order the criteria were applied: can a
reviewer verify it from the change alone; would the next person to hit it be
helped; is it one logical change; and is it likely to land from someone nobody
there knows. #524 passed all four. 94773 passed the first three and was a
calculated risk on the fourth, because the repository's owner had already
rejected one README. The −1 on patchset 1 was about something else, and
[`0002`](0002-openbmc-readme.md) §11 is what it taught; the second comment, on
patchset 2, is §12.

## Two upstreams, two processes, and the paperwork does not carry over

Worth its own section because it was a live confusion on 2026-09-13, the day
before the first change was due to be sent: *"do I need to sign a CLA? is this
the same as OpenBMC's Gerrit?"*

**No, and no.** They share exactly one thing — the `Signed-off-by` line — and
differ in everything else.

| | `openbmc/spdm` | `DMTF/spdm-emu` |
|---|---|---|
| submission | **Gerrit**, `git push gerrit HEAD:refs/for/main` — `main` for `openbmc/spdm`, although most OpenBMC repositories use `master` | **GitHub pull request** |
| `Change-Id` | required, from the `commit-msg` hook | not used |
| **CLA** | **required.** Individual CLA to `manager@lfprojects.org`, one per person, covering every OpenBMC repository | **none. The word does not appear in `CONTRIBUTING.md`** |
| DCO | required | required — DSP4014, real name, address you can be reached at, **matching the commit author** |
| AI assistance | ★ **corrected 2026-09-22, by a reviewer.** Not "no policy" — a policy in review: [`openbmc/docs` 89452](https://gerrit.openbmc.org/c/openbmc/docs/+/89452), `coding-assistants.md`, by Ed Tanous. Same three rules in substance: an AI must not add `Signed-off-by` because only a human can certify the DCO, the human is responsible for reviewing the work, and attribution is `Assisted-by: AGENT_NAME:MODEL_VERSION [TOOL1] [TOOL2]`. **404 on master**, so grepping the merged tree could not find it | **`Assisted-by: AGENT_NAME:MODEL_VERSION` required**, and an AI must NOT appear in `Signed-off-by` or `Co-authored-by` |
| who merges | maintainers, via Gerrit +2 | maintainers; any DMTF member may call a vote |

The CLA sent on 2026-08-04 is real, is dated, and covers OpenBMC. It has no
bearing on a DMTF pull request, and assuming it did would have been the
comfortable mistake: the paperwork *feels* done.

> ### The rule worth keeping
>
> **The contribution rules of a project you have not contributed to are not the
> ones you already know.** This repository's own commits carry
> `Co-Authored-By: Claude …`, which is correct here and **forbidden** by
> DMTF's `CONTRIBUTING.md` rule 2. A convention that is right in one repository
> is a rule break in another, and nothing about writing the commit says so.
>
> So the rules are now read out of the target's own `CONTRIBUTING.md` and
> encoded in [`harness/check_upstream_commit.sh`](../../harness/check_upstream_commit.sh),
> with the digest of the file they were read from. When that digest moves, the
> script says so — because a rule set that has changed is exactly the thing a
> returning contributor does not re-read.
>
> Only the DMTF profile is implemented. OpenBMC's arrives in week 9, when there
> is a real commit to check it against; writing it now against nothing would be
> a check whose failure mode has never fired.
>
> *(Both exist now. `--profile openbmc` arrived on 2026-09-18 with the change
> it was written for, and on 2026-09-23 it gained a file-mode rule and lost a
> `Change-Id` rule that every merged commit in its target broke.)*

**What was actually missing.** The prepared commit carried a correct DCO
sign-off and **no `Assisted-by:` trailer**, which rule 3 requires. Added
2026-09-13; the commit is now `425aa5a` and the checker passes all ten rules.

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

## The first build attempt, revisited — 2026-09-18

Blockers 1 to 3 are unchanged and are now written down in the README this
project is proposing. Blockers 4 and 5 turned out to be one blocker and a
compiler version.

**GCC 14.2 compiles the tree.** 863 targets, clean, at the same commit
`72e3ea9`. So the internal compiler error is GCC 13's and the
`std::formatter<std::thread::id>` failure is libstdc++ 13's, and neither is a
property of this repository beyond its choice of C++23.

The ICE was re-verified rather than taken from the August note, because a claim
about a compiler is a claim about a specific build and the tree had not moved:

```text
../requester/utils/mapper.cpp:46:5: internal compiler error:
    in build_special_member_call, at cp/call.cc:11096
```

★ **And a sixth blocker that the August attempt never reached**, because the
build stopped before the tests could run. With GCC 14 they do run, and one of
three fails on any machine that is not a BMC:

```text
C++ exception with description "sd_bus_request_name:
org.freedesktop.DBus.Error.AccessDenied: Permission denied" thrown in SetUp().
```

`test_policy_manager` requests a well-known name on the system bus, and a stock
D-Bus policy does not permit `xyz.openbmc_project.*` to be owned by an ordinary
user. It is an undocumented prerequisite rather than a defect, and one line
fixes it:

```sh
dbus-run-session -- sh -c \
  'DBUS_SYSTEM_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS meson test -C build'
```

3 of 3 OK. Both findings are in the README, because a newcomer hits both and
neither is written down anywhere in the tree. That is the whole argument for
the change.

> ⚠ **Corrected 2026-09-23: they were not, in the patchset that was sent.** The
> README of patchset 1 contains neither finding, and this paragraph was written
> from the plan for the file. Patchset 2 contains both.
> [`0002`](0002-openbmc-readme.md) §2 and §11.
>
> **And patchset 3, the same day, removes both again, on purpose.** Neither
> appears in any of 34 other OpenBMC READMEs, and the project's CI runs the
> tests under a `dbus-daemon` of its own, where the second is not a problem.
> The first survives in the commit message's `Tested:` line.
> [`0002`](0002-openbmc-readme.md) §12.

**What was read before writing it, and what it changed.** The obvious framing —
"there is no README, so write one" — is how change
[80422](https://gerrit.openbmc.org/c/openbmc/spdm/+/80422) died in May 2025: a
maintainer rejected it for *"hypotheticals that do not match the code"*, CI
voted `Verified-1` twice, and a bot abandoned it a year later. Reading that
change turned a guess into a specification, and it is quoted in full in
[`0002-openbmc-readme.md`](0002-openbmc-readme.md) §0.

---

## A second candidate, on a different repository — 2026-08-17

`DMTF/spdm-emu`, at `5f01d2f` (tag `4.0.0-rc`). Found while reading the source
for a different reason, which is usually how these are found.

**The `--help` text disagrees with the defaults it describes.**

```
spdm_emu/spdm_emu_common/spdm_emu.c:115
  "By default, CERT,CHAL,ENCRYPT,MAC,MUT_AUTH,KEY_EX,PSK,ENCAP,HBEAT,
   KEY_UPD,HANDSHAKE_IN_CLEAR,MULTI_KEY_NEG,LARGE_RESP is used for Requester."

spdm_emu/spdm_emu_common/key.c:12-30
  m_use_requester_capability_flags = ( ...
      SPDM_GET_CAPABILITIES_REQUEST_FLAGS_CHUNK_CAP |
      SPDM_GET_CAPABILITIES_REQUEST_FLAGS_EP_INFO_CAP_SIG | ... );
```

The help string is hand-written; the default is a hand-written initialiser; and
nothing checks that they agree. What is missing from the help text:

| side | capabilities set by default but not listed |
|---|---|
| Requester | `CHUNK`, `EP_INFO_SIG` |
| Responder | `CHUNK`, `EP_INFO_SIG`, `MEL` |

**Evidence in three forms, which is what makes this submittable rather than
merely noticed:**

1. the two source locations above,
2. the `Flags` word on the wire — `0x8882F7C6` and `0xB99AFBF7`, both with bit
   17 (`CHUNK_CAP`) set, in
   `bench/data/w2-baseline-20260828T110130Z/walkthrough.decode.txt`,
3. behaviour that could not happen otherwise: the post-quantum arm of the same
   run performs four `CHUNK_GET`/`CHUNK_RESPONSE` round trips. Chunking is not
   reachable unless both sides negotiated `CHUNK_CAP`.

**Why it is worth submitting.** Not for the size of the change — it is a few
lines of string — but because reading `--help` is how a newcomer decides which
flags to pass, and a wrong default sends them looking for a capability they
already have. This project's own week-two plan carried the belief that `CHUNK`
was absent from the defaults, sourced from that help text and marked as
re-checked. Being wrong from the same place twice is a reasonable argument that
the text is worth fixing.

**Why not today.** `DMTF/spdm-emu` takes GitHub pull requests rather than
Gerrit, so it is a different pipeline from the one already rehearsed, and
opening it properly is an hour that week two did not have. Scheduled for W03,
alongside the other upstream item that week. Deliberately recorded here with
its evidence attached so that scheduling it is not the same as forgetting it.

**Why it derisks Gate 7.** `openbmc/spdm` is the higher-value target and the
riskier one: five blockers, no README, and a change that argues for a minimum
compiler version is a change that invites disagreement. This one is a factual
correction with the wire as its witness. Two targets, one high-value and one
high-probability, is a better bet than one of either.

## Two more, found by running the tamper cases — 2026-09-01

Both on `DMTF/spdm-emu` at `5f01d2f` (tag `4.0.0-rc`), and both found the same
way as the second candidate: reading the source to explain a capture that had
not done what was expected. Neither is submitted. Both are recorded with the
capture that produced them, which is the part that makes them worth submitting
rather than worth mentioning.

### A slot-0 certificate read whose failure is discarded

`spdm_emu/spdm_responder_emu/spdm_responder_spdm.c:495-553`

```c
res = libspdm_read_responder_public_certificate_chain(..., &data, ...);       /* slot 0 */
res = libspdm_read_responder_public_certificate_chain_per_slot(1, ..., &data1, ...);
res = libspdm_read_responder_public_certificate_chain_per_slot(4, ..., &data4, ...);
...
if (res) { /* uses data, data1, data4 */ }
```

`res` is assigned three times and tested once, so a failure to read slot 0's
chain is not reported anywhere. `data` stays `NULL`, `libspdm_set_data(...,
LOCAL_PUBLIC_CERT_CHAIN, slot 0, NULL, 0)` leaves the slot unprovisioned, and
the responder starts normally.

**How it was found.** `bench/data/w4-tamper-*/t3_cert` flips one byte inside
the intermediate certificate of the chain the responder serves.
`libspdm_read_responder_public_certificate_chain` calls
`libspdm_verify_cert_chain_data` and correctly refuses it
(`read_pub_cert.c:447`). The only trace on the wire is `ProvisionedSlotMask`
falling from `0x13` to `0x12`; the only trace in the log is a requester saying
`do_authentication_via_spdm - 8001000a` several messages later. Nothing says
which file was rejected or why.

**Shape of a change.** Test each read, and emit `EMU_ERR` naming the slot when
one fails. Small, local, no behaviour change on the working path.

### The requester never asks whether the chain it accepted was authoritative

`spdm_emu/spdm_requester_emu/spdm_requester_authentication.c` calls
`libspdm_get_certificate()` four times, the form that discards the
`trust_anchor` out-parameters, and tests `LIBSPDM_STATUS_IS_ERROR` after
each. `grep -rn 'NO_AUTHORITY\|trust_anchor' spdm_emu` returns nothing.

> ★ *Corrected 2026-09-30.* This paragraph named `spdm_requester_spdm.c`,
> which has no `libspdm_get_certificate` call at the pin or at `main`. The
> four are in `spdm_requester_authentication.c`, at lines 63, 71, 78 and 107
> in both `5f01d2f` and `eff07cf`. The requester's fifth call, in
> `spdm_requester_session.c`, and the attester sample's loop over slots 1
> to 7 use `libspdm_get_certificate_ex` and pass `NULL, 0` for the trust
> anchor, and every one of them tests `IS_ERROR` only, so the finding holds
> at every call site. Found by listing the call sites at upstream's head
> rather than re-reading this sentence.

libspdm does the work and reports it as a warning, which is the correct
division of labour:

```c
/* Provided cert is valid but is not authoritative(mismatch the root cert). */
#define LIBSPDM_STATUS_VERIF_NO_AUTHORITY \
    LIBSPDM_STATUS_CONSTRUCT(LIBSPDM_SEVERITY_WARNING, LIBSPDM_SOURCE_CRYPTO, 0x0003)
```

and `libspdm_try_get_certificate` deliberately does **not** `goto done` on it,
unlike the integrity check three lines above
(`libspdm_req_get_certificate.c:483-496`). So the decision is handed to the
application, and the sample application does not take it.

**How it was found.** `bench/data/w4-tamper-*/t3b_foreign` has the responder
serve DMTF's own `ecp384` chain while the requester's trust anchor is this
project's root. The handshake completes, exit 0, every signature verified. The
same acceptance is visible in `w3-baseline-20260831T143123Z/selfsigned`, packet
12: slot 4's chain roots in `ed79ce9a…`, which is neither of the two roots that
requester provisioned.

**Shape of a change.** Use `libspdm_get_certificate_ex`, and print the trust
anchor or a warning when the status is `NO_AUTHORITY`. A sample that shows an
integrator where the decision is teaches more than one that hides it.

**What this is worth, stated before anyone asks.** Both are small, both are
documentation-adjacent rather than protocol changes, and neither is a
vulnerability — the second is explicitly a design decision by the library
underneath. What they demonstrate is reading a reference implementation closely
enough to find where its samples stop being examples, with a committed capture
behind each. That is the claim; "I found a security bug in libspdm" is not, and
would not survive review.

## A fifth, found by trusting a comment for ten minutes — 2026-09-10

`spdm_emu/spdm_emu_common/command.h` is the only place the socket wire format
is written down, and it is where anyone writing a tool that sits between the
two emulators will start. It says:

```c
/* Client->Server/Server->Client
 *   command/response: 4 bytes (big endian)
 *   transport_type: 4 bytes (big endian)
 *   PayloadSize (excluding command and PayloadSize): 4 bytes (big endian)
 *   payload (SPDM message, starting from SPDM_HEADER): PayloadSize (little endian)*/
```

The last line is wrong for the default transport. For `SOCKET_TRANSPORT_TYPE_MCTP`
the payload is what libspdm's MCTP transport encoded, which begins with the MCTP
message type — `0x05` for SPDM, `0x06` for a secured message — and the SPDM
header starts at `payload[1]`.

It is visible in any capture this project has taken, because
`send_platform_data` writes the same buffer into the pcap with a four-byte
synthesised `mctp_header_t` in front of it:

```
00 00 00 c0 | 05 | 10 84 00 00
└─ pcap only ┘ └┬┘  └─ SPDM header ─┘
                MCTP message type
```

`harness/tamper_proxy.py` reads `payload[1]` for the version and `payload[2]`
for the `RequestResponseCode`. A reader who trusts the comment reads
`payload[0]` and `payload[1]`, gets `0x05` and `0x10`, and is one byte out on
every field in the message — a `GET_VERSION` looks like a version byte of 5 and
a request code of 0x10, which is not a code at all.

**The proposed change is two lines of comment**, naming the transport
dependency and the message-type byte. Nothing else moves.

**What this is worth, stated before anyone asks.** It is a comment. It is not a
defect in the code, it changes no behaviour, and a reviewer would be right to
call it trivial. What it has going for it is that it is *checkable in one
command* against a file the repository itself produces, and that the person
proposing it hit the problem rather than read about it. Small documentation
changes are also the right first submission to a repository nobody there knows
you in, which is the actual reason it is the one being prepared first.

**A related observation that is NOT being submitted**, because it is a design
question rather than a defect: the comment is accurate for
`SOCKET_TRANSPORT_TYPE_NONE`, where the payload really does start at the SPDM
header. The sentence is not wrong so much as unqualified, and saying so is a
smaller and more likely-to-land change than arguing about which case should be
the default in the documentation.

## Six, from running the published example — 2026-09-12

`DMTF/spdm-emu` at `5f01d2f`, `spdm_emu/spdm_device_verifier_tool/`. The
tools this project's week-six plan was built around: CoRIM manifests, COSE
signing, an Open Policy Agent policy. Their `readme.md` gives an eight-command
example with the sample data that ships beside it.

**The example does not run.** Every one of these was found by typing those
eight commands, and the thing worth saying before the list is that *running the
published example first, unchanged, before connecting anything of my own* is
what made them findings rather than two days of debugging my own code.

The tool was last changed on 2023-05-09. Upstream `main` on 2026-09-12 is
byte-identical to the pinned copy — fetched and diffed, not assumed — so all six
are current.

### ① `requirements.txt` has no upper bounds, and the ceiling has arrived

```
cbor>=1.0.0
pycose>=0.1.2
cose>=0.9.dev8
jose>=1.0.0
python_jose>=3.1.0
cryptography>=2.3
```

> ★ *Corrected 2026-09-30.* The block above used to show four of these six
> lines, on one row; `jose` and `python_jose` were missing. It is now the
> file, blob `fabca0ad`, the same at the pin and at `main`. Neither missing
> line has an upper bound either, so the heading was right and the quote was
> not the file: candidate ⑭'s shape, a hand-shortened copy of the evidence.

`pip install -r requirements.txt` today resolves `cbor2` to 6.1.4 through
`pycose`. cbor2 ≥ 6.0 decodes the contents of a `CBORTag` as **immutable**
containers — arrays become `tuple`, maps become `FrozenDict` — and
`pycose.messages.CoseMessage.decode()` requires `isinstance(cose_obj, list)`.

Measured, and it is the cleanest way to state it: **pycose cannot decode its own
`encode()` output.** 79 bytes, byte-identical through a `cbor2` round trip,
`TypeError: Bytes cannot be decoded as COSE message`.

Bisected here: 6.1.4 fails, 5.6.5 and 5.4.6 return `list`/`dict` and work. This
is pycose's incompatibility rather than DMTF's code, but DMTF's tool is the
thing that stops working and the fix in their tree is a pin.

### ② `CoRimTool.py verify` does not verify — ★ the one being sent

Two lines of `VerifySignedCbor`, and **they mask each other**, which is the
whole reason this section is longer than the others and the whole reason the
change is one change.

**(a) The key.** `CoRimTool.py:209`:

```python
key = VerifyingKey.from_pem(f.read()).to_string()
cose_key = EC2Key(crv='P_256', d=key)
```

`VerifyingKey.to_string()` returns the **public point**, `x ‖ y`, 64 bytes for
P-256. It is passed as `d=`, the **private scalar**, 32 bytes. Three lines up in
the same file, `SignCbor` does the same construction correctly with a
`SigningKey`, whose `to_string()` really is `d`.

`EC2Key` raises `ValueError: Invalid EC key (key out of range, infinity, etc.)`,
the surrounding `except Exception` catches it, and the tool prints *Signature
verification failed*. **The message is wrong as well as the outcome**: nothing
ever looked at a signature.

**(b) The result.** `CoRimTool.py:214`:

```python
cose_msg.verify_signature(Algorithm)
```

`Sign1Message.verify_signature()` is documented as returning
*"True for a valid signature or False for an invalid signature"*. **It returns.
It does not raise.** The value is discarded, and control falls through to the
payload write and *Signature verification passed*.

> ### ⚠ Fixing (a) alone makes the tool worse
>
> Measured, on 2026-09-12, on the sample data: with (a) repaired and (b) not,
> flipping the last byte of the 64-byte signature still prints **Signature
> verification passed** and still writes the 996-byte payload.
>
> **This project had that one-line change committed and was one keystroke from
> sending it.** It was caught by the last line of a script written to check that
> the commit message's own `Tested:` claims were true — the claim being *"a
> corrupted signature is still refused"*, which turned out not to be.
>
> A verifier that accepts nothing is useless. A verifier that accepts anything
> is worse than useless, and the second is what the first fix produces. So they
> go together, and `rats/interop.sh` now keeps a **half-patched** copy beside
> the patched one and asserts that the half-patched one accepts a forged
> signature. A check is the only form of "remember this" that survives.

Reproduction, with cbor2 pinned so that ① is out of the way:

```bash
cd spdm_emu/spdm_device_verifier_tool
pip install -r requirements.txt && pip install 'cbor2==5.6.5'
python3 CoRimTool.py json_to_cbor -i SampleManifests/SpdmSampleCoMid.json \
                     -o /tmp/s.cbor
python3 CoRimTool.py sign -f /tmp/s.cbor --key SampleTestKey/ecc-private-key.pem \
                     --kid 11 --alg ES256 -o /tmp/s.corim
python3 CoRimTool.py verify -f /tmp/s.corim --key SampleTestKey/ecc-public-key.pem \
                     --alg ES256 -o /tmp/out.cbor
#   Signature verification failed
```

And the signature is good. Verified independently, with `ecdsa` over the COSE
`Sig_structure` built by hand — `["Signature1", protected, b"", payload]` — which
returns `True`. The fix is two lines:

```python
-        cose_key = EC2Key(crv='P_256', d=key)
+        cose_key = EC2Key(crv='P_256', x=key[:len(key) // 2], y=key[len(key) // 2:])
         cose_msg.key = cose_key
 
-        cose_msg.verify_signature(Algorithm)
+        if not cose_msg.verify_signature(Algorithm):
+            raise ValueError('signature does not verify')
```

With them, the same command prints *Signature verification passed*, a corrupted
signature prints *failed* and writes nothing, and the whole published example
runs to `opa eval`.

**Is (b) a vulnerability?** Not as shipped, and the reasoning matters more than
the answer. It is not reachable today: (a) means `verify` raises before any
signature is examined, so the tool accepts nothing and no deployed system can
be holding a forged manifest it approved. (b) becomes reachable only if someone
fixes (a) — which is exactly why the report and the fix cover both, and why
neither half is being sent on its own. If it had been reachable in shipping
code the channel would have been DMTF's security reporting process rather than
a public pull request, and this section would say so instead of describing it.

### ③ `json_to_cbor` cannot read `cbor_to_json`'s output

```bash
python3 CoRimTool.py json_to_cbor -i SampleManifests/SpdmSampleCoMid.json -o /tmp/a.cbor
python3 CoRimTool.py cbor_to_json -i /tmp/a.cbor                          -o /tmp/a.json
python3 CoRimTool.py json_to_cbor -i /tmp/a.json                          -o /tmp/b.cbor
#   KeyError: 'corim'
```

Three commands, the tool's own sample manifest, no other project involved.
`cbor_to_json` writes the two CoRIM container tags as JSON **keys** — `corim`
and `unsigned_corim_map` — and `translate_data`'s `AllMapDict` has no entry for
either, so it raises before reaching anything else.

It matters because `cbor_to_json` is step 2 of the documented verification flow:
its output is what the OPA policy is evaluated against, and it is not a document
the tool can take back.

### ④ `translate_data` hard-codes two names where a table was intended

`CoRimTool.py:190`, inside the list branch:

```python
if input[index] == "comid_tag_creator":
    output.append(AllMapDict[input[index]])
elif input[index] == "sha256":
    output.append(SupportHashAlgMap[input[index]])
else:
    output.append(input[index])
```

`sha384`, `sha512`, `comid_creator` and `comid_maintainer` all fall through and
are encoded as **text strings** where the CDDL has integers. Measured on a CoMID
with five SHA-512 digests and two entity roles: 1523 bytes rather than 1480, a
43-byte difference in a document a signature covers.

The published sample sidesteps it by writing the integers directly
(`"comid_digests": [[8, …]]`), so the shipped example never exercises the
branch.

### ⑤ `verify` reports failure on stdout and exits 0

`CoRimTool.py:215`:

```python
    except Exception:
        print("Signature verification failed")
        exit()
```

Bare `exit()` is status 0. A shell cannot tell a verified manifest from a
rejected one, and a pipeline that trusts the exit code treats a failed
verification as a success.

**Not filed as a security issue, and the reasoning is the point.** It cannot be
reached as a fail-open today, because ② means `verify` never succeeds and never
writes its output file, so every downstream step fails anyway. It is a
robustness defect in a tool whose own readme calls it a sample and whose keys
say *do NOT use them in any production*. If it had been reachable in shipping
code the channel would have been DMTF's security reporting process rather than a
public issue, and this section would not exist.

### ⑥ `SpdmSamplePolicy.rego` does not parse on a current OPA

OPA made Rego v1 the default in 1.0. On `opa 1.20.2` the sample produces
**eleven** `rego_parse_error` messages — `` `if` keyword is required before rule
body``, `` `contains` keyword is required for partial set rules`` — and
evaluates only under `--v0-compatible`. The readme documents a bare
`opa eval -i <input> -d <policy> "data.spdm"` and mentions no version anywhere.

### What is being submitted, and what is not

**② only, and both of its lines.** One logical change — *make `verify`
verify* — and the difference between the documented example working and not
working. The pull-request body is
[`0001-corim-verify.md`](0001-corim-verify.md); it names ① as a separate problem
with the exact command to work around it, because a maintainer who applies the
fix on a fresh virtualenv and sees it still fail will close the change.

The two lines are one change rather than two on evidence rather than on taste:
fixing the key alone converts a verifier that accepts nothing into one that
accepts anything, which was measured rather than reasoned about.

①, ③, ④, ⑤ and ⑥ are recorded here with their reproductions and are **not**
bundled. Six unrelated fixes in a first pull request to a repository where
nobody knows you is how a first pull request does not land, and three of the six
involve a judgment about which form is canonical — that is a maintainer's call
to make, not a contributor's to assume.

### What this is worth, stated before anyone asks

Finding seven defects in one directory sounds like more than it is: it is a
sample tool, last touched in 2023, whose dependencies moved underneath it. The
claim is not *I found bugs in DMTF's code*. The claim is narrower and more
useful, and it has two halves.

**I ran the published example before writing anything of my own**, and when it
failed I read the source until I could say which line and why, rather than
working around it and moving on. Four of the seven were found by the fifth
command.

**And I checked my own bug report before sending it.** The second half of ② —
the one that makes the first half dangerous — was found by writing a script to
re-run the `Tested:` lines of a commit message that was already written, already
signed off, and already on a branch. The last of those lines was false. That is
the finding I would actually talk about: not that upstream had a defect, but
that a fix which is obviously correct in isolation was, in context, the more
harmful of the two states.

The remaining one came from asking whether the policy that runs at the end
actually checks what it appears to check — and it does not, which is in
[`../rats-pipeline.md`](../rats-pipeline.md) §5 and is a finding about design
rather than a defect to report.

## A thirteenth, from a flag combination the parser accepts — 2026-09-14

Turning mutual authentication off is the first thing anyone measuring a
one-variable SPDM A/B has to do: left on, both arms carry a requester
certificate chain the experiment never asked for, and in this project's
2026-08-28 baseline that chain is 4,460 bytes — 22% of the capture.

The obvious way to do it, and the one this project's own week plan specified:

```bash
--basic_mut_auth NO --mut_auth NO --req_asym NONE --req_pqc_asym NONE
```

Every one of those four is a value the argument parser accepts. `NONE` is in
`m_asym_value_string_table` and in `m_pqc_asym_value_string_table`, both
emulators echo the parsed values back (`req_asym - 0x0000`,
`req_pqc_asym - 0x00000000`), and then the handshake dies after six packets:

```
ERROR: libspdm_init_connection - 0x8001000a
```

The capture says what the status code does not. The responder answers
`NEGOTIATE_ALGORITHMS` with `ERROR(ErrCode=0x01, InvalidRequest)`, and the
request that provoked it is missing both requester-signature AlgStructure
tables — because `libspdm_req_negotiate_algorithms.c` emits each one only when
the corresponding local algorithm is non-zero.

`libspdm/library/spdm_responder_lib/libspdm_rsp_algorithms.c` is where it is
refused:

```c
if (libspdm_is_capabilities_flag_supported(..., MUT_AUTH_CAP, MUT_AUTH_CAP) ||
    libspdm_is_capabilities_flag_supported(..., EP_INFO_CAP_SIG, 0)) {
    algo_size     = libspdm_get_req_asym_signature_size(req_base_asym_alg);
    pqc_algo_size = libspdm_get_req_pqc_asym_signature_size(req_pqc_asym_alg);
    if (((algo_size == 0) && (pqc_algo_size == 0)) ||
        ((algo_size != 0) && (pqc_algo_size != 0))) {
        return libspdm_generate_error_response(
            spdm_context, SPDM_ERROR_CODE_INVALID_REQUEST, 0, ...);
    }
}
```

**Exactly one requester signature algorithm, never zero and never both** —
whenever `MUT_AUTH_CAP` is mutually supported, or the requester merely
advertises `EP_INFO_CAP_SIG`.

The trap is that `--mut_auth` and `--basic_mut_auth` are **flow policy**. They
decide whether the encapsulated exchange runs. They do not clear `MUT_AUTH_CAP`
or `EP_INFO_CAP_SIG` out of `m_use_requester_capability_flags` in `key.c`, and
both bits are set there by default — which this project's captures confirm
rather than assume: `harness/fields.py` lists both in the requester's
advertised flags in every arm.

So a user who reads "mutual authentication off" as "the requester needs no
signature algorithm" has read the flags correctly and reached a configuration
that cannot complete, and the only diagnostic names a libspdm status code.

### What could be reported

Three shapes, in increasing order of how much they change:

1. **A parse-time refusal.** `spdm_emu.c` already validates values against
   tables; refusing `--req_asym NONE` together with `--req_pqc_asym NONE` with
   a sentence naming `MUT_AUTH_CAP` costs a few lines and turns a six-packet
   mystery into a message.
2. **A note in the readme**, beside the flags. Cheapest, and the least likely
   to be read at the moment it is needed.
3. **Clear the capability bits when both algorithm sets are empty**, so that
   asking for no requester signature produces a connection with no mutual
   authentication rather than an error. This is the one that makes the flags
   mean what they look like — and it is also the one that changes behaviour
   other people may be relying on, which is why it is third rather than first.

Evidence is committed: `bench/data/w7-pqc-ab-20260914T073732Z` holds four arms
that work, and the bisection that isolated the pair is in `LOG.md` for
2026-09-14. What this project does instead is pin the requester's own signature
algorithm to one classical value in every arm, which costs one 4-byte
`AlgStructure` entry that is byte-identical across the whole matrix —
[`../pqc-cost.md`](../pqc-cost.md) §3.

**Not yet reported.** It goes in the queue behind
[`0001-corim-verify.md`](0001-corim-verify.md), which is prepared and waiting on
a keystroke that is the author's; sending a second finding to a project before
the first one has been sent is a way of having zero conversations rather than
two.

## Four more, from measuring across the transport — 2026-09-14

All four came out of one week's work: building a DataTransferSize sweep and a
six-group algorithm matrix. Two are argument-handling, one is an algorithm that
does not work, and one is a missing knob with a patch attached.

### ⑭ `--cap` is parsed by the requester and then never read

> ★ **WITHDRAWN 2026-09-29. This section was never true, and it is kept so that
> what was wrong with it stays visible.**
>
> At the pinned commit `5f01d2f`, `spdm_requester_spdm.c` has, at lines 179–180:
>
> ```c
> if (m_use_capability_flags != 0) {
>     m_use_requester_capability_flags = m_use_capability_flags;
> }
> ```
>
> They arrived in `ef556a0`, *"Fix issue that the input CAP param is not
> saved."*, on 2022-12-21. Measured on the pinned `pqc` build rather than read:
> the requester's `GET_CAPABILITIES` carries `Flags 0x0002f7c6` by default and
> `0x00000006` with `--cap CERT,CHAL`, and the handshake completes either way.
>
> **What went wrong is visible below.** The `grep` output in this section is not
> the output of a `grep`. Run at `5f01d2f` it returns twelve lines; the block
> below has six, three of them cut to `...`, and the requester's two lines are
> among the six that are missing. It was abbreviated by hand, and the sentence
> after it —
> *"`spdm_requester_spdm.c` never mentions it"* — was written from the
> abbreviation. The same claim was then copied into `LOG.md` for 2026-09-14 as
> one of three instances of a design rule, into `docs/pqc-cost.md` §10 and into
> a comment in `harness/lib/handshake.sh`, and all three are corrected in place
> with this date. It was found on 2026-09-29 only because a freshness check
> re-read every candidate at upstream's head and the line was there.
>
> What is still true, and was always the operative reason the week-8 arms pass
> `--cap` to the responder alone: the two programs validate the names against
> different tables, so the responder's list is *rejected* by the requester,
> through `print_usage(); exit(0)` — candidate 15.

`spdm_emu_common/spdm_emu.c:859` parses `--cap` into `m_use_capability_flags`,
validates every name against a per-program table, and prints the result back:

```
cap - 0x8882f7c6
```

Exactly one place reads that variable:

```
$ grep -rn 'm_use_capability_flags' spdm_emu/
spdm_emu/spdm_responder_emu/spdm_responder_spdm.c:174:    if (m_use_capability_flags != 0) {
spdm_emu/spdm_responder_emu/spdm_responder_spdm.c:175:        m_use_responder_capability_flags = m_use_capability_flags;
spdm_emu/spdm_device_attester_sample/spdm_device_attester_spdm.c:189:    ...
spdm_emu/spdm_emu_common/key.c:63:uint32_t m_use_capability_flags = 0;
spdm_emu/spdm_emu_common/nv_storage.c:227:    ...
spdm_emu/spdm_emu_common/spdm_emu.c:884: ...
```

`spdm_requester_spdm.c` never mentions it. **So `--cap` on
`spdm_requester_emu` has no effect, and confirms in writing that it did.** It is
not a documentation gap: the flag is echoed, which is what makes it worth
reporting — a user who checks that their flag was accepted gets a yes.

**Why it was found:** this project needed a post-quantum arm with the
responder's `CHUNK_CAP` removed, to measure what SPDM's chunking layer is worth
([`../pqc-cost.md`](../pqc-cost.md) §10). Passing one capability list to both
binaries seemed wasteful rather than impossible; reading the source before
writing the arm is what turned it into a finding instead of a puzzle.

**What could be reported:** either read `m_use_capability_flags` in the
requester as the responder does, or reject `--cap` there. Two lines either way.

### ⑮ An unrecognised or invalid argument exits 0

Every argument-validation failure in `process_args` ends the same way:

```c
printf("invalid --slot_count %s\n", argv[1]);
print_usage(program_name);
exit(0);                       /* <- zero */
```

`grep -c 'exit(0)' spdm_emu/spdm_emu_common/spdm_emu.c` finds it throughout. So
a script that typos a flag gets a process which **exited successfully and never
spoke SPDM**, and `$?` says nothing happened wrong.

This is the same class as finding ⑤ in the 2026-09-12 batch, where `verify`
reported failure on stdout and exited 0, and it is the reason this project's own
harness judges an arm on its capture rather than on an exit status: what catches
a bad flag in `harness/run_pair.sh` is `hs_wait_for_responder` timing out and
there being no capture, not the status code. `EXIT_FAILURE` on the invalid-input
paths would be a mechanical change and would break nothing that was working.

### ⑯ ★ No signed operation completes with SLH-DSA on this build

DMTF ships sample certificate chains for **twelve** SLH-DSA parameter sets,
`--pqc_asym` accepts all twelve, and `LIBSPDM_SLH_DSA_*_SUPPORT` defaults to 1.
With `SLH_DSA_SHA2_128S` selected and everything else held constant, bisecting
on `--exe_conn` (ML-DSA-44 as the control, same flags):

| `--exe_conn` | responder signs? | SLH-DSA-SHA2-128s | ML-DSA-44 |
|---|:--:|:--:|:--:|
| `VCA` | no | exit 0 | exit 0 |
| `DIGEST` | no | exit 0 | exit 0 |
| `DIGEST,CERT` | no | **exit 0**, 54 packets | exit 0 |
| `DIGEST,CERT,MEAS` | yes | **exit 1** | exit 0 |
| `DIGEST,CERT,CHAL` | yes | **exit 1** | exit 0 |
| `DIGEST,CERT,CHAL,MEAS` | yes | **exit 1** | exit 0 |

Every unsigned operation completes; both signed ones fail. What that rules out,
with the capture that rules it out:

- **not negotiation** — `ALGORITHMS` selects `SLH_DSA_SHA2_128S`, asserted per
  arm by `harness/lib/check_negotiated.py`;
- **not chunking** — the 24,782-byte chain arrives in six `CHUNK_RESPONSE`,
  twice, and `bench/pcapstat.py` reassembles it and finds the chain closes;
- **not X.509** — `DIGEST,CERT` exits 0, so a chain whose every signature is
  SLH-DSA was parsed and verified;
- **not signing** — the `CHALLENGE_AUTH` arrives whole, through two chunks, at
  7,998 bytes, which is 142 + **7,856**: FIPS 205's SLH-DSA-SHA2-128s signature
  length exactly. The responder produced a correct-length signature.

**What is left is SPDM-signature verification on the requester**, and the
requester says so: both signed arms' logs begin `ERROR:
do_authentication_via_spdm - 80020001`, which is `LIBSPDM_STATUS_VERIF_FAIL`.
`TARGET=Release` compiles `LIBSPDM_DEBUG` out, so which check inside the
verification fails is not printed; that is what a `Debug` rebuild would add,
rather than a guess about `slhdsa_ext.c`.

> ★ *Corrected 2026-10-15.* This paragraph used to say that the libspdm status
> was not recoverable from this build and that the requester exits 1 having
> printed nothing at all. The line above is the first line of `S1-all.req.log`
> and `S1-obo.req.log`, committed on 2026-09-14 with the sentence that denied
> it; `EMU_ERR` writes it to stderr. Found when #529's help text suggested a
> timeout instead, and the log was read before anything was rewritten:
> `VERIF_FAIL` is libspdm's *"verification of the provided signature digest,
> signature, or AEAD tag failed"*, not a wait
> ([§](#537-rebased-onto-main-and-the-corim-names-sent-as-542--2026-10-15)).

**Evidence:** `bench/data/w8-pqc-matrix-20260914T131557Z/S1-*`, and the arm is
kept in Table 2 as a partial handshake rather than deleted.

### ⑰ `DataTransferSize` cannot be set at run time — with a patch

`DataTransferSize` decides whether a message crosses the wire once or as a
chunking exchange, and a chunk costs a complete request/response round trip. On
this project's post-quantum arm, moving it over a 32× range moves the byte total
3.1% and the round trips from 59 to 0 ([`../pqc-cost.md`](../pqc-cost.md) §9). It
is the parameter a BMC or RoT integrator actually tunes.

`spdm-emu` has no flag for it. It is

```
LIBSPDM_DATA_TRANSFER_SIZE = LIBSPDM_RECEIVER_BUFFER_SIZE - (header + tail)
```

in `spdm_emu_common/spdm_emu.h`, so measuring across it means one build per
value.

**A patch exists:** [`../../transport/data-transfer-size.patch`](../../transport/data-transfer-size.patch),
55 added lines across five files, no deletions. It adds
`--data_transfer_size <bytes>`, range-checked against
`SPDM_MIN_DATA_TRANSFER_SIZE_VERSION_12` below and the build's own compile-time
ceiling above, and it can only *lower* the advertised value — a device that
advertised more than its buffer holds would be lying to its peer.

One implementation note worth passing on, because it is the obvious approach and
it silently does nothing: `libspdm_set_data(...,
LIBSPDM_DATA_CAPABILITY_DATA_TRANSFER_SIZE, ...)` after the buffers are
registered returns `LIBSPDM_STATUS_INVALID_STATE_LOCAL` (0x80010002). The
working route is to register a smaller receive buffer, which is where libspdm
derives the value from in the first place.

**Verified inert where it is not aimed:** the patched build told to use the
unpatched build's value reproduces every count of that build's capture — 58,966
captured bytes, 58,736 SPDM bytes, 46 packets, 12 chunk round trips, and the
per-message-type byte table entry for entry. (Not the file digest: `CHALLENGE`
carries a fresh nonce, so byte counts are deterministic here and byte content is
not.) `bench/claims.json` asserts it as
`dts_patch_is_inert_at_the_default_value`, and
[ADR 0009](../decisions/0009-a-third-build-flavor.md) is why that assertion
rather than a small diff is what makes the sweep admissible.

**Not yet reported**, and this one is the most likely of the nineteen to be
wanted: it is a feature with a patch, a test matrix and a control, aimed at a
parameter the project's own CI already has two workflows about
(`chunk_check.yml`, `chunk_device_sample.yml`).

## Two more, from running the official conformance suite — 2026-09-20

Both found by running `SPDM-Responder-Validator` four ways and then reading the
source to explain what came back. Both are on repositories this project already
has an account and an agreement for. Neither is submitted, and the second is
the strongest candidate here so far because it comes with a proof rather than a
reading.

### ⑱ `spdm-emu`'s validator configuration disagrees with the suite it configures

`spdm_emu/spdm_device_validator_sample/spdm_device_validator_config.c`, against
`SPDM-Responder-Validator` at the submodule pointer `c27bb1c7`.

The sample program's configuration array and the suite's own case tables are
out of step **in both directions**:

| | case | what happens at runtime |
|---|---|---|
| implemented, not registered | `SPDM_RESPONDER_TEST_CASE_CAPABILITIES_SUCCESS_13` | prints `- skipped` |
| implemented, not registered | `SPDM_RESPONDER_TEST_CASE_ALGORITHMS_SUCCESS_13` | prints `- skipped` |
| implemented, not registered | `SPDM_RESPONDER_TEST_CASE_CERTIFICATE_SIZE_REQ` | prints `- skipped` |
| **registered, not implemented** | `SPDM_RESPONDER_TEST_CASE_CERTIFICATE_SPDM_X509_CERTIFICATE` | **prints nothing at all** |

The first three are defined in `spdm_responder_test.h` and present in the
library's `common_test_case_t` tables —
`spdm_responder_test_2_capabilities.c:1278`,
`spdm_responder_test_3_algorithms.c:2005`,
`spdm_responder_test_5_certificate.c:709` — and absent from the configuration,
so the framework prints one line each and moves on.

The fourth is the other way round and is worse. `common_test_run_test_suite`
iterates the **library's** case table, so a case that exists only in the
configuration is never looked for: no `- skipped` line, no assertion, nothing.
A reader counting the sample's output concludes it ran 71 configured cases. It
ran 70, and one of the 71 is imaginary.

**Why it matters rather than being tidy.** The two `SUCCESS_13` cases are the
**only** cases in the suite that exercise SPDM 1.3. With them unregistered, a
clean report from this sample says nothing about a responder's behaviour above
1.2 — and not because the suite cannot reach it.

**Evidence, in three forms:**

1. the four source locations above, at the pinned submodule commit;
2. a run: `bench/data/w10-validator-20260919T184429Z/caps-default.test.log`
   carries exactly three `- skipped` lines and no mention of case 5.5;
3. a checker rather than a claim —
   `python3 harness/validator_report.py --audit-config <validator-src> <config.c>`
   recomputes the whole table from the two files, and
   `harness/verify_repo.sh` runs it wherever the upstream tree is present.

**Shape of a change.** Four lines in one array: add the three cases, remove the
one that does not exist. No behaviour change to the suite, no new test code.
**Why it is a good first submission to this repository:** it is mechanical, it
is verifiable from the two files alone, and it is the kind of drift a
submodule bump produces rather than anyone's mistake.

**Not submitted.** `DMTF/spdm-emu` takes GitHub pull requests; change ⑲ below
is on the same repository and should go first or with it.

> **2026-09-29: half of it fixed upstream, without this project.** `eff07cf`,
> *"Sync latest case from validator."*, the commit the `4.0.0-rc2` tag points
> at, registers both `SUCCESS_13` cases — the half that mattered, because they
> were the only SPDM 1.3 coverage — along with ten cases the suite gained since.
> Re-running `--audit-config` on that tree: 83 implemented, 83 registered, and
> two lines left, `CERTIFICATE_SIZE_REQ` still unregistered and
> `CERTIFICATE_SPDM_X509_CERTIFICATE` still registered and not implemented.

### ⑲ ★ A conformance case reports FAIL for an input it discarded itself

> ★ **2026-09-29: fixed upstream five days before this section was written.**
> `SPDM-Responder-Validator` `65bcccc`, *"Fix CHALLENGE_AUTH signature verify
> for A1B2C1/A1B3C1 cases"* (authored 2026-09-07), and `ad6db5c`, the same for
> the A2 cases (2026-09-14), were on the suite's `main` on 2026-09-15. This
> section was written on 2026-09-20 against the suite at the commit `spdm-emu`
> pinned it to, `c27bb1c`, and every freshness check since read that pointer
> rather than the suite's own `main`. `spdm-emu` picked the fix up on
> 2026-09-29 (`f1c37e0`, in the `4.0.0-rc2` tag).
>
> The fix's commit message states the mechanism below in one sentence —
> *"libspdm_verify_challenge_auth_signature() needs the peer cert chain cached
> in spdm_context, but these cases skip GET_CERTIFICATE on the fresh
> re-initialized connection"* — and it repairs it the way option (1) below
> proposes: the chain captured during setup is put back into the context. So
> the diagnosis was right and was not first. It is kept as evidence of the
> first, and it is not sendable.

`SPDM-Responder-Validator`,
`library/spdm_responder_conformance_test_lib/spdm_responder_test_6_challenge_auth.c`.

Four assertions fail against a responder whose signatures are **correct**:

```
test assertion 6.2.7  - FAIL response signature
test assertion 6.3.7  - FAIL response signature
test assertion 6.12.7 - FAIL response signature
test assertion 6.13.7 - FAIL response signature
```

and the four are exactly the cases whose message mask omits `GET_CERTIFICATE`
(`B2` and `B3`, at 1.0/1.1 and at 1.2/1.3). The case that omits `GET_DIGESTS`
and keeps the certificate — `6.14`, `A1B4C1` — passes. **The certificate fetch
is necessary and sufficient**, and the digests are irrelevant.

**The mechanism.** The case's setup, `spdm_test_case_challenge_auth_setup_vca_digest`,
fetches the peer certificate chain at `:202`. The case body then calls
`libspdm_init_connection()` at `:363`, which sends `GET_VERSION`, which calls
`libspdm_reset_context()`, which frees
`connection_info.peer_used_cert_chain[]`. A mask that does not re-fetch the
chain arrives at

```c
libspdm_verify_challenge_auth_signature(spdm_context, true, slot_id, sig, size)
```

with nothing for `libspdm_get_peer_cert_chain_data` to return, and the function
returns `false` from `libspdm_x509_get_cert_from_cert_chain` before any
signature arithmetic happens. The device is then recorded as having produced a
bad signature.

**The proof, which is why this is a report and not an opinion.**
`harness/challenge_verify.py` rebuilds the transcript from the capture and
hands the arithmetic to OpenSSL. It calibrates first — on the nine connections
that *did* fetch the certificate and that the suite passes, so that a failure to
reproduce would mean the tool's transcript model is wrong rather than the
suite's verdict — and only then reports the disputed ones:

```
calibration  9/9 verify        disputed  2/2 verify
  packet 284   SPDM 1.1 slot 0   M1M2 266 B (144 +   0 + 122)  -> verified
  packet 306   SPDM 1.1 slot 0   M1M2 370 B (144 + 104 + 122)  -> verified
```

The middle term is the whole finding: 1,775 bytes of certificate exchange in
the transcripts that pass, **0** and **104** in the two that fail — and the
signatures over those shorter transcripts are good.

**Shape of a change.** Two candidates, and the pull request should say which
and why rather than assuming:

1. **Provision the chain into the local context before the reset.**
   `libspdm_reset_context` preserves `local_context` by design — its own
   comment says *"Local context information is preserved"* — so a setup that
   stores the fetched chain with `LIBSPDM_DATA_PEER_PUBLIC_CERT_CHAIN` would
   survive the `GET_VERSION` the case itself sends. This keeps every case's
   message mask exactly as designed, which is the point of the `B` axis.
2. **Record `NOT_TESTED` instead of `FAIL`.** The framework already has the
   result for "the suite could not make this assertion", and it is the honest
   one for an assertion whose input the suite does not hold. Smaller, and it
   does not restore the coverage the cases were written for.

(1) is preferred and (2) is the fallback if a maintainer objects to the setup
holding state across a reset. The pull request offers both.

**Why this is worth submitting.** A conformance suite that reports a conforming
device as non-conforming is the one defect class a conformance suite cannot
have. Anybody running it against a real responder sees four failures with a
message — `response signature` — that points straight at their crypto, and the
time that costs is the argument.

**Evidence:** the source locations above; the run directory
`bench/data/w10-validator-20260919T184429Z`; `harness/challenge_verify.py` with
its own self-test; and `harness/verify_repo.sh`, which re-runs the proof against
the committed capture on every CI run so the claim cannot rot.

**Not submitted.** Same keystroke rule as the other two.

## Freshness, checked immediately before the keystroke was offered — 2026-09-20

Two changes have been sitting prepared since September. Neither has been sent,
and a prepared change decays: the base moves, the defect gets fixed by somebody
else, the linters change their minds. So both were re-checked **today**, and
this table is the record of that rather than of the original work.

| | `DMTF/spdm-emu` — ② `CoRimTool.py verify` | `openbmc/spdm` — a first `README.md` |
|---|---|---|
| prepared | 2026-09-12, commit `425aa5a` | 2026-09-18, commit `d3c84a1`, `Change-Id: Ib0191ead…` |
| base then | `ea77f25` | `72e3ea9` |
| **upstream tip on 2026-09-20** | `ea77f25` — unchanged | `72e3ea9` — unchanged |
| **upstream tip on 2026-09-22** | ★ **`b5f3ec1`** — **MOVED, 2 commits.** Neither touches `CoRimTool.py`; the branch was rebased and the diff is byte-identical | **`72e3ea9`** — still unchanged, **0** commits since, README still 404 |
| still applies | yes, no rebase needed | yes, no rebase needed |
| still needed | yes — the two lines are still there | yes — `git ls-tree origin/main` still shows no README |
| its own `Tested:` claims | the load-bearing one, *"a corrupted signature is still refused"*, is re-asserted by `harness/verify_repo.sh` on every run, through `rats/interop.sh`'s half-patched copy | prettier 3.3.3 `--check` and markdownlint-cli 0.41.0 **re-run today**, both clean, with the two configs fetched from `openbmc-build-scripts` today rather than from a cached copy |
| **not re-run today** | — | the 863-target `meson compile` and the 3/3 `meson test`. Verified 2026-09-18 against a tree that has not moved since, which is what the row above establishes; stated here rather than implied |

★ **The freshness check is a separate act from the work, and it belongs
immediately before the outward one.** A change verified in September and sent
in October is a change verified against a repository that no longer exists.
Standing rule 19 is about reading the rest of the function; this is the same
rule pointed at the rest of the world.

**Both are still one keystroke away, and the keystroke is the author's.**

## Both sent — 2026-09-22

The keystroke was the author's and it happened. A third freshness check ran
first, because the second one was two days old and the rule is *immediately*
before, not *recently* before. It changed what was sent, both times.

| | [`DMTF/spdm-emu` #524](https://github.com/DMTF/spdm-emu/pull/524) | [`openbmc/spdm` 94773](https://gerrit.openbmc.org/c/openbmc/spdm/+/94773) |
|---|---|---|
| pipeline | GitHub pull request, from a fork | Gerrit, `refs/for/main` |
| sent | 2026-09-22 | 2026-09-22 |
| commit | `d7ceeaa` | `d3c84a1`, patchset 1 |
| base | **`16119ea`** — moved again, **one** commit, merged that same day | `72e3ea9` — unchanged |
| what the check changed | **rebased a second time.** `patch-id` `40e9bb3b…` and the blob `a5762c04…` both came through unchanged, and the pinned `pqc` tree's copy of `CoRimTool.py` hashes the same as upstream's at the new base — so `rats/interop.sh` re-asserts the `Tested:` lines against *the same bytes the change targets*, which is a statement worth making precisely rather than loosely | **both linters had vanished from the machine.** Reinstalled at their pinned versions, configs re-fetched, re-run: clean |
| still needed | yes — both lines read out of the freshly fetched objects, not a cache | yes — README still 404, and no open Gerrit change mentions one |
| nobody got there first | PR and issue search for `CoRimTool`, `EC2Key`, `verify_signature`: 0 | Gerrit `message:README` on this project: 0. Change 80422 still ABANDONED |
| upstream CI | green on `main`, five workflows | — |
| first check back | **DCO — success** | pending |
| reviewers | **jyao1**, **steven-bellock**, assigned by CODEOWNERS rather than requested | to be added from `reviewers:`, not `owners:` |

### Two things this day taught that the preparation had not

**① A document that tells you how to send a change is not a mechanism.**
`0002-openbmc-readme.md` §7 said `git push origin HEAD:refs/for/main`, and that
tree's `origin` is `https://github.com/openbmc/spdm.git` — the **read-only
GitHub mirror**. The Gerrit remote did not exist in that working tree at all.
The rehearsal on 2026-08-05 proved the pipeline against `openbmc/docs`, whose
tree already had the remote, so it proved everything except the thing that was
missing here. It fails loudly, which is the only reason this is a paragraph and
not an incident.

**② The verification a reader can run is worth more than the one you ran.**
Everything local said the change was intact: `patch-id` unchanged, blob
unchanged, 392 CRLF and 0 bare LF. None of those is a number GitHub computes.
The PR page says `1 commit`, `1 file changed`, `+3 −2`, and shows lines 206–218
rather than the whole file — the same claim, reached by somebody else along a
different path. `docs/roadmap.md` standing rule 12 was written about two
implementations of CoRIM; it applies to this.

## Merged, and every candidate re-read at the head — 2026-09-29

### #524, as it landed

Read from the GitHub API at 13:03–13:08 UTC, not from the notification:

| | sent | landed |
|---|---|---|
| commit | `d7ceeaa` | **`b015187`**, on `main` |
| parent | `16119ea` | `16119ea` |
| author / committer | Chung-Wei Lan / Chung-Wei Lan | Chung-Wei Lan / **Jiewen Yao**, 2026-09-28 14:43:19 UTC |
| tree | `b618c153…` | `b618c153…` |
| message | — | byte-identical, `Signed-off-by` and `Assisted-by` included |
| `CoRimTool.py` blob | `a5762c04…`, the bytes `rats/interop.sh` tested | `a5762c04…`, and the blob upstream `main` serves today |
| tag | — | in `4.0.0-rc2` (`eff07cf`, 2026-09-29), which is three commits ahead of it and none behind |

What the review consisted of: at 14:41:46 UTC Steven Bellock removed his own
review request, at 14:41:54 he added the label `bug`, and at 14:43:20 Jiewen Yao
merged. No comment, no review, no requested change. So this record can say what
was accepted and cannot say why. The one reading it supports is that a change
carrying its own reproduction and its own negative test did not need a
conversation; that is an inference, and it is labelled as one. The description
also offered two follow-ups, the exit status and the `cbor2` bound, and nobody
answered that either. The first is now prepared as
[`0003`](0003-corim-exit-status.md).

### Every candidate, re-read at the head of the repository that owns it

The freshness checks of 2026-09-20 and 09-22 read `DMTF/spdm-emu`'s `main`. For
`SPDM-Responder-Validator` and `libspdm` they read the commit `spdm-emu` pinned
them to, never their own `main`. That difference decided ⑲. So every unsent
candidate was re-read today at the head of the repository that owns its code,
and where a build could answer, on a build of that head (`spdm-emu` `eff07cf`
with `libspdm` `a6994ee` and the suite at `7acde98` — the `4.0.0-rc2` tags).

| # | at the pin | at the head, 2026-09-29 | now |
|:-:|---|---|---|
| 2 | help omits `CHUNK`, `EP_INFO_SIG` (and `MEL` for the responder) | help text and defaults unchanged | live |
| 3 | slot-0 read result discarded | `res` still overwritten by the slot 1 and slot 4 reads before it is tested | live |
| 4 | `NO_AUTHORITY` never inspected | connection path unchanged | a design question |
| 5 | `command.h`: "starting from SPDM_HEADER" | unchanged | live |
| 6, 8–11 | the verifier tool | `CoRimTool.py` changed only by #524; `requirements.txt` still unbounded; the sample policy still Rego v0 | ⑤ sent as #526 |
| 13 | the exactly-one requester signature rule | the same rule in libspdm 4.0.0-rc2 | live |
| 14 | "the requester never reads `--cap`" | it has read it since 2022 | **withdrawn** |
| 15 | 78 `exit(0)` | 91 | live |
| 16 | SLH-DSA S1 exits 1 | exits 1 on 4.0.0-rc2 as well | live, not sendable |
| 17 | no `DataTransferSize` flag | none | sent as #527 |
| 18 | four mismatches | two | half fixed upstream |
| 19 | the suite at `c27bb1c` | fixed on the suite's `main` on 2026-09-15 | **fixed before found** |
| 20 | — | NONE without `CHUNK_CAP` cannot start | **not new**: upstream #358, open since 2024-07-28 |

★ **What ⑲ teaches: a defect in a dependency is checked at the head of the
repository that owns the code, not at the pointer of the repository that
consumes it.** A submodule pointer is the consumer's decision about when to
update, and it lags by design: `c27bb1c` was seven weeks old on the day ⑲ was
written, and the fix had been on the suite's `main` for five of those days. Every freshness check this
project ran on ⑲ confirmed that `spdm-emu` had not moved its pointer. That was
true, and it was the wrong question.

★ **What ⑭ teaches, which is older than this week and should have been caught
before it: evidence is the command's output, pasted, or it is a paraphrase.** The
`grep` in § ⑭ was shortened by hand, the shortening dropped the two lines that
disproved the sentence under it, and three other files repeated that sentence
for fifteen days.

### Porting ⑰ found two defects in this project's own patch

`transport/data-transfer-size.patch` is what produced the `pqc-dts` flavor and
Figure 3, and it was written against `5f01d2f`. Rebuilding it on `eff07cf` meant
reading every line again, and two were wrong:

1. **Without `CHUNK_CAP` it advertised a `MaxSPDMmsgSize` larger than its
   `DataTransferSize`.** DSP0274 1.4.1 requires the two to be equal when an
   endpoint does not support the Large SPDM message transfer mechanism, and
   libspdm's requester refuses the `CAPABILITIES` that breaks it. Measured on
   the `pqc-dts` build: responder without `CHUNK_CAP` at 1024 advertises
   `1024/32768`, and the requester stops with `0x80010005`.
2. **On `--trans NONE` it advertised 128 bytes more than it was asked for**,
   because NONE registers no transport header or tail. The patch's own comment
   admitted this and relied on the harness to catch it.

Neither reaches the published evidence: every arm of the sweep runs over the
MCTP-framed socket with `CHUNK_CAP` on both sides, and each arm's
`DataTransferSize` is read back off the wire and compared. They are recorded in
[`../../transport/README.md`](../../transport/README.md) beside the patch, which
is left as it is because it is what the evidence was made with. The version in
0004 fixes both, and fixing the first surfaced a third rule the old patch never
met: libspdm also requires `MaxSPDMmsgSize` to be at least the sender's data
transfer size, so without chunking the sender buffer has to follow as well.
The first build of 0004 missed that too, and its responder exited silently until
the sender buffer followed.

## Two more sent — 2026-09-29

Asked for the steps rather than for the send, the author signed, pushed and
opened both himself; every check below ran in the hour before each keystroke,
and each keystroke waited until the one before it had been verified from here.

| | [#526](https://github.com/DMTF/spdm-emu/pull/526) · 0003 | [#527](https://github.com/DMTF/spdm-emu/pull/527) · 0004 |
|---|---|---|
| sent | 2026-09-29 15:14:37 UTC | 2026-09-29 15:14:44 UTC |
| commit | `60748b7` (prepared `1a396c2`) | `367414a` (prepared `eb294e4`) |
| base | `eff07cf` — upstream `main` had not moved | the same |
| sign-off | the author's; tree `b3dcd4b…` identical before and after | the author's; tree `84896f1…` identical before and after |
| still needed | both bare `exit()` calls at `main` | no `data_transfer_size` anywhere in `main` |
| nobody got there first | `CoRimTool`, `exit status`, `exit()`, `cbor2`: #524 only | `data_transfer_size`, `DataTransferSize`: #358, #329, #458, all known |
| `Tested:` re-run | all four, on `git archive` of both trees; §4's repro verbatim in a fresh virtualenv | every run of §3 with the tested binaries, identical counts |
| first check back | **DCO success**; CI **45 of 45** | **DCO success**; CI **45 of 45**, both VS2019 builds among them |
| reviewers | `jyao1`, `steven-bellock`, by CODEOWNERS | the same |

### What the hour before the keystroke found

**① `patch-id` is not byte identity.** 0004's record said the committed diff
had the same `patch-id` as the tested tree. It did, and it would have had it if
a line ending had changed, because `git patch-id` ignores whitespace. The blob
hash of each of the eight files is the comparison that means "the bytes sent
are the bytes built", and it was made: 8 of 8.

**② A claim can be right by accident.** 0004 §3 said invalid values exit 0.
The run behind it read `$(… | head -1); rc=$?`, which is the exit status of
`head`. Measured again with the emulator's own status, it is 0 — the sentence
was true and nothing had shown it. It is the pipeline rule of CLAUDE.md, met on
a line written to support a pull request rather than a result.

**③ A pull request's body is a claim too.** Its last paragraph said
`--trans NONE` without `CHUNK_CAP` starts once the option is set, and no
`Tested:` line covered it. NONE cannot be captured, so the requester's `-v`
trace was decoded message by message until it showed a `MEASUREMENTS`.

**④ The in-flight scan is not only for Gerrit.** #496, open since June and
written by one of the two reviewers, touches six of 0004's eight files.
Nothing to do about it before merging, and a reason not to read a rebase
request as a rejection.

## Every candidate re-read, and searched for — 2026-09-30

Read between 19:14 and 19:39 UTC on 2026-09-29, which was 03:14–03:39 on the
30th here, with every method the fortnight had taught, because the question
asked was whether anything on this page had stopped being true.

**Nothing upstream had moved.** `spdm-emu` `main` `eff07cf`, `libspdm` `main`
`a6994ee`, and `SPDM-Responder-Validator`'s own `main` `7acde98` — the last read
from the suite, not from `spdm-emu`'s pointer to it, although today the two
agree.

| | [#526](https://github.com/DMTF/spdm-emu/pull/526) · 0003 | [#527](https://github.com/DMTF/spdm-emu/pull/527) · 0004 |
|---|---|---|
| the head GitHub serves, the fork's branch and the signed commit | `60748b7`, all three | `367414a`, all three |
| its tree, against the tree that was tested | `b3dcd4b…`, the same | `84896f1…`, the same; the binaries tested on the 29th were built from these eight blobs, 8 of 8 |
| `refs/pull/N/merge` | present, first parent today's `main` | the same |
| reviews, comments, labels | none | none |
| upstream CI | 45 of 45 | 45 of 45 |
| `Tested:` re-run on GitHub's bytes | all four lines, and the repro block taken from the body GitHub serves and run as it stands in a fresh virtualenv: `exit 0` before, `exit 1` after | every run in 0004 §3, with the binaries built on the 29th: 25 of 25 rows identical to the send session's output, and `--trans NONE` without `CHUNK_CAP` decoded message by message as far as `MEASUREMENTS`. The build itself, the first `Tested:` line, was not repeated |

**All thirteen unsent candidates are still present** at the head that owns
them: 2, 3, 4, 5, ①, ③, ④, ⑥, ⑬, ⑮, ⑯ (S1 still exits 1 on the unpatched
4.0.0-rc2 build, P1 0), ⑱'s two lines (83 implemented and 83 registered,
against the suite's own `main`) and ⑳. Candidate 2 was checked by a script
this time rather than read (a scratch script, not committed): the defaults in
`key.c` mapped to names through each program's own string table and compared
with its `--help` — the requester's omits `CHUNK` and `EP_INFO_SIG`, the
responder's `MEL`, `CHUNK` and `EP_INFO_SIG`, at the pin and at `main`.

**And each was searched for upstream**: 29 issue and pull-request searches,
each on the repository that owns the code, every one answered. None has been
reported. Three hits needed reading: #408 quotes candidate 5's comment but asks
for DSP0287's TCP binding, and was closed by #416 — not a duplicate, and some
evidence that the comment is read literally; #120 is a 2022 typo fix in a
`rego` command in a readme; and of the twelve `SLH-DSA` results in `libspdm`,
ten are features and tests, #3246 is a build that could not find OpenSSL's
internal headers, and #3696 asks when 4.0.0 ships. None reports a signature
that fails to verify, which is ⑯. The rule that turned ⑳ into #358 had been
applied only to the candidates that were sent.

**What it found wrong was all this project's own:**

- two citations on this page, corrected above with the date: candidate 4's
  calls are in `spdm_requester_authentication.c`, and ①'s quote lacked two of
  the file's six lines;
- [`harness/recheck_upstream.sh`](../../harness/recheck_upstream.sh) could not
  see an approval. Its pull-request rows compared two counters that a review
  without an inline comment does not move — measured on `libspdm` #3987,
  approved by a maintainer with both at 0 — and it did not watch #496, #358 or
  the suite's own `main`. Fixed the same day;
- [`harness/check_upstream_commit.sh`](../../harness/check_upstream_commit.sh)
  refused a linked worktree, the natural way to check the commit a pull
  request's ref holds. Fixed the same day.

**Two facts that decide the order of what is sent next:**

- **#496 conflicts with `main` itself**, in `doc/spdm_emu.md`, `spdm_emu.c`
  and `spdm_emu.h` (a trial merge onto today's `main`, in a throwaway clone),
  while GitHub still advertises a `refs/pull/496/merge` — computed on
  2026-06-27, against a `main` 33 commits older. ★ **A merge ref proves
  nothing until its first parent is today's `main`**; for #526 and #527 it is.
  So #496 has to be rebased before it can merge at all, and #527, if it merges
  second, probably has to be as well; that second half is a prediction, not a
  measurement.
- **#358 is assigned to its reporter**, `arugan02`, so a fix for ⑳ starts with
  a question there. And all 91 of ⑮'s `exit(0)` are in `process_args()`, where
  #527 adds 25 lines and #496 adds 54: ⑮ goes last.

Why they are not all sent at once was asked the same night. The short answer
is already in candidate 2's row — *a second change to a project before the
first is answered is two conversations that do not happen* — and this section
is the long one: two maintainers review everything, the candidates overlap
each other and the maintainer's own work, and every row had to be re-verified
on the day it would be sent.

## Two more sent, one of them a question — 2026-10-04

Read and sent between 18:12 and 19:47 UTC on 2026-10-03, which was
02:12–03:47 on the 4th here. The questions were whether #527's reviewer was
right, and whether candidates 4 and 5 still needed sending. GitHub was read
through its API as the author, with read-only requests, because the anonymous
quota has run out in the middle of a check here before.

### What had moved since 2026-09-30

- **`spdm-emu` `main` had not**: `eff07cf`. `libspdm` `main` had, by 38 commits
  to `319fd96`, none of them in `libspdm_req_get_certificate.c` or in the
  status definitions.
- **#526 was approved** by `steven-bellock` at 23:36 UTC on 2026-09-29, with no
  comment. `jyao1` is still requested.
- **#527 was reviewed** by `LeonLinAtAMI` on 2026-09-30: a comment, an approval
  and one inline suggestion. He is a regular contributor here and not one of
  the two CODEOWNERS; the July refactor of the emulator's socket IO into an
  ops table, and the Linux kernel MCTP transport, are his.
- **#531**, his, on 2026-10-02. Its first commit is #527's `367414a` — the same
  hash, tree `84896f1`, author and sign-off — credited in its description. Its
  second, `a69dbcf`, lets `--data_transfer_size` go up to 1 MiB on heap buffers
  and adds `--max_spdm_msg_size`. Its default path on `--trans NONE` makes
  `MaxSPDMmsgSize` follow `DataTransferSize`, which reads as the fix for #358,
  candidate ⑳; it does not cite #358, and no build here has checked it.
- The same day he opened #528, #529 and #530. With #496 and #527, **six open
  pull requests now edit `spdm_emu.c`**, where ⑮'s 91 `exit(0)` and
  candidate 2's help text live. #530 rewrites the five call sites candidate 4
  is about, and still passes no trust anchor.
- **#532** (`annamdi`, 2026-10-02) is candidate 3, found independently while
  deploying the responder, with a fix offered.
- **#496**: untouched since 2026-06-27, and still in conflict with `main`.
- **94773**: unchanged since 2026-09-23 17:10 UTC, read from Gerrit at 20:00
  UTC.

### #527's suggestion was right, and the commit stayed as it was

*"It is nice to mention that MaxSPDMmsgSize would be equal to DataTransferSize
when given valid DataTransferSize and the CHUNK_CAP is not set."* Both
`*_spdm.c` in [`0004`](0004-data-transfer-size.md) set
`max_spdm_msg_size = m_use_data_transfer_size` in exactly that case, and 0004
§3 measured `1024/1024` on each side. The condition in it matters: without the
option and without `CHUNK_CAP`, on `--trans NONE`, the two differ, which is
#358.

The sentence was not added. #531 is built on that exact commit and already says
it, under `--max_spdm_msg_size`; amending #527 would have left #531 on a commit
#527 no longer contains. The author acknowledged the comment with a reaction
rather than a reply, and that blocks nothing here: `main` has no ruleset, and
#527 reports `mergeable_state` `clean` with the thread open.

### Candidate 4, measured on the head and then asked

The premise was measured, not re-read. The unpatched build of `eff07cf` with
`libspdm` `a6994ee` — Release, `CRYPTO=openssl`, built on 2026-09-29 as 0004's
control — ran with stock files: the responder with no options, the requester
with `--exe_conn DIGEST,CERT,CHAL,MEAS --exe_session KEY_EX`, once as shipped
and once from a copy whose `ecp384/ca.cert.der` is replaced by the stock
`ecp384/ca1.cert.der`. `gdb` read what `libspdm_get_certificate_ex` returned,
on the binary as built:

| requester's slot-0 trust anchor | the three certificate reads (slots 0, 4, 0) | exit | messages | requester output |
|---|---|:-:|--:|---|
| stock `ca.cert.der` | `0x00000000` | 0 | 578 | four lines |
| stock `ca1.cert.der` in its place | `0x40020003`, `VERIF_NO_AUTHORITY` | 0 | 578, in the same order, two sessions | the same four lines |

```python
# gdb -q -nx -batch -x c4_gdb.py --args ./spdm_requester_emu <the options above>
import gdb

class Ret(gdb.FinishBreakpoint):
    def stop(self):
        v = self.return_value
        if v is None:
            v = gdb.parse_and_eval("$rax")
        print("GETCERT_RETURN 0x%08x" % (int(v) & 0xFFFFFFFF), flush=True)
        return False

    def out_of_scope(self):
        print("GETCERT_RETURN out_of_scope", flush=True)

class Hit(gdb.Breakpoint):
    def stop(self):
        Ret(gdb.newest_frame(), internal=True)
        return False

gdb.execute("set pagination off")
gdb.execute("set confirm off")
Hit("libspdm_get_certificate_ex.constprop.0")   # the Release build's clone
gdb.execute("run")
```

The return value is what makes "nothing changed" mean something. It shows that
the swapped file was read and that the library noticed; the identical capture
shows that the program carried on regardless. Why the status is a warning is in
libspdm's own history: #1773 and #1774, March 2023, made `VERIF_NO_AUTHORITY` a
warning so that the integrator decides whether a chain from a root it did not
provision is acceptable. The issue asks whether the sample should show that
decision being taken — print the slot, or stop — and offers either, based on
#530 if that lands first. It says why this matters outside the emulator pair:
since `e9b30a0` (2026-07-19) the requester can reach a real MCTP endpoint with
`--trans MCTP_KERNEL`. And it carries an `Assisted-by:` line, as this project's
commits upstream do.

Two things found before its text was final:

- **The first run could not have gone into an issue.** With the requester's
  default flow, both arms ended with the requester killed by `SIGPIPE` (141)
  and the responder by the timeout (124), after a long secured phase, and both
  captures stop at exactly 163,840 bytes. The stock arm failing the same way is
  what assigned the failure to the setup rather than to the swap, and naming
  the flow removed it. Where the default flow breaks was not traced; nothing
  here depends on it.
- **The reproduction block passed by luck.** Run verbatim, with the responder
  started by `&`, it succeeded. But `init_client` has no retry around
  `connect()`, so on a slower machine the requester can lose that race and
  print `Connect Error`. The issue says two terminals.

### Candidate 5, re-measured on every transport and then sent

On 2026-09-10 the comment was known to be wrong for MCTP, by one byte. The
requester's `-v` trace on the same build shows what each transport puts in
front of `GET_VERSION`:

| `--trans` | first `GET_VERSION` payload | SPDM header at |
|---|---|:-:|
| NONE | `10 84 00 00` | 0 |
| MCTP, the default | `05 10 84 00 00` | 1 |
| PCI_DOE | `01 00 01 00 03 00 00 00 10 84 00 00` | 8 |
| TCP | `06 00 01 05 10 84 00 00` | 4 |

PCI_DOE's first payloads are DOE discovery objects and carry no SPDM at all. The
comment is right for one transport of four, and the change says what comes
first for each. `MCTP_KERNEL` is left out because it registers its own IO ops
instead of using this framing; the pull request says so, since the person who
wrote that transport is the likeliest reviewer. #408 quoted the comment, and
#244, open since 2023, asked why the MCTP payload has no MCTP transport header,
which the comment now states. No open pull request touches `command.h`.

Prepared unsigned as `2f8557f`. Every source in `spdm_emu_common` compiled with
the new header under each of the four targets' own flags, and a deliberately
unterminated comment failed to, so the check could fail. Signed by the author
as `d1ec185`, the tree `743e561` unchanged and the message otherwise identical;
`harness/check_upstream_commit.sh` clean; pushed by the author, and the branch
GitHub serves is `d1ec185`. DCO passed, and upstream CI passed 45 of 45, the
last check at 20:08 UTC.

### What the hours before the keystrokes found, all of it mine

- **A check that could not fail.** "Is the control build unpatched?" grepped
  the binary for `data_transfer_size` and found three, because libspdm's own
  error message contains the word — the message #358 quotes. The token only the
  patch adds is the option, `--data_transfer_size`: none.
- **A width check aimed at the whole file** refused the edit to `command.h`,
  whose own licence line is 112 characters. It now checks only the lines the
  change adds.
- **One sentence of the issue's draft was wrong in a small way**: "nothing is
  printed". The requester prints its usual four lines and nothing about the
  status. Corrected before sending.
- **And this repository's README** said, in Table 1, that case 3b's requester
  printed "only a warning". It printed nothing — `t3b_foreign.req.log` is the
  control's, line for line — and [`../tamper.md`](../tamper.md) had it right.
  Corrected in `ef0fb88`.

### What decides what goes next

- #533: an answer. If it is yes, a change of about ten lines, after #530.
- #534: review.
- ⑮ and 2: not #496 alone any more, but the six pull requests that edit
  `spdm_emu.c`.
- ⑳: whether #531 fixes #358 is one build away, and nothing is said there
  before it.
- 94773: no ping before 2026-10-07, as decided.

## Four of four merged, and the rest re-read — 2026-10-12

Read on 2026-10-12 from 15:00 UTC. `harness/recheck_upstream.sh` answered ten
of its nineteen rows `NO DATA` — nine HTTP 403s with the anonymous allowance
spent, and an advisory fetch that exited 2 — and called none of them
unchanged; each of the ten was then read by hand. Since 2026-10-04: three
merges, an answer, and a weekly CI job that was red for a reason of this
repository's own.

### As they landed

| | sent | landed, on | merged | review before the merge |
|---|---|---|---|---|
| [#534](https://github.com/DMTF/spdm-emu/pull/534), `command.h` | `d1ec185` | `13edd65`, on `eff07cf` | 2026-10-04 03:00 UTC, `steven-bellock`, seven hours after it was opened | labelled `documentation` and approved, without a comment |
| [#526](https://github.com/DMTF/spdm-emu/pull/526), `CoRimTool.py`'s exit status | `60748b7` | `532f667`, on `13edd65` | 2026-10-05 20:49 UTC, `steven-bellock` | approved on 2026-09-29, without a comment |
| [#527](https://github.com/DMTF/spdm-emu/pull/527), `--data_transfer_size` | `367414a` | `fd75485`, on `9975786` | 2026-10-12 14:43 UTC, `jyao1` | a contributor's inline suggestion and approval; no maintainer review |

All three by rebase, and in each the commit message and every changed file's
blob are byte-identical to what was sent — one, one and eight blobs — so the
`Tested:` lines on `main` describe the bytes on `main`. #527 landed three
commits past the `eff07cf` it was written on, without a conflict. #496, which
the in-flight scan expected to force a rebase on whichever merged second, has
not merged.

`9975786`, between #526 and #527, is `LeonLinAtAMI`'s fix for an MSVC build:
an em dash in a comment in `command.h`, which MSVC, reading a file without a
BOM in code page 950, reports as C4819, and `/WX` makes an error. It did not
come from #534 — none of the three patches adds a byte outside ASCII — and it
is the first thing to check in anything sent there next.

### Candidate 4, answered

At 14:47 UTC `steven-bellock` assigned #533 to `LeonLinAtAMI`, whose #530
changes the same calls, and wrote: *"Since this is a warning, I would go with
option 1."* Option 1 is the smaller of the two: a line naming the slot, and
carry on. The change is assigned, so none is sent from here. What this project
can offer it is the reproduction in the issue — with the requester's slot-0
anchor replaced by the stock slot-1 root, the three certificate reads return
`0x40020003`, so the new line would appear three times, for slots 0, 4 and 0.

### Every unsent candidate, at `8f36665`

| # | at `8f36665` | judgement now |
|:-:|---|---|
| 2 | the defaults still set `CHUNK` and `EP_INFO_SIG`, and the responder's `MEL`; both `By default` lines still omit them | not now: #496, #529, #530 and #531 all edit `print_usage()` |
| 3 | unchanged | #532's; the maintainer proposes deprecating the option instead |
| ③ | `json_to_cbor` still cannot read `cbor_to_json`'s output | a question first. The sample policy reads `input.reference.corim.unsigned_corim_map`, so changing the output would break it, and the fix belongs on the reading side — a maintainer's to agree to |
| ④ | the list branch still translates `comid_tag_creator` and `sha256` by name | **sendable**, and it needs no maintainer's call after all: the tables it should consult are in the same file — `SupportHashAlgMap` maps `sha384` to 7 and `sha512` to 8, and `ComidRoleTypeChoice`, already part of `AllMapDict`, maps `comid_creator` to 1 and `comid_maintainer` to 2 |
| ⑥ | eleven `rego_parse_error` on `opa 1.20.2`; clean under `--v0-compatible` | **sendable**, and the cleanest: one 53-line file, seven rules |
| 13 | the rule is libspdm's; not re-read at libspdm's head today | a conversation, later |
| 15 | 93 `exit(0)`, every one in `process_args()`; the four open pull requests that edit it add fifteen more between them | a question first, and a change after they land |
| 16 | no SLH-DSA issue or pull request in libspdm since 2026-09-30; `b574d5d` (2026-10-02) sweeps the PQC algorithms in `test_spdm_crypt` | not sendable. That commit is where a root-cause hunt would start |
| 18 | `--audit-config` with the suite at `7acde98`: 83 and 83, the same two names | not sent; the maintainer re-syncs this array himself |
| 20 | #358 open and assigned; #531 has to resolve a conflict with #527 | after that, one build to measure whether #531 closes #358 |

None of the five open pull requests touches `spdm_device_verifier_tool/`,
where ③, ④ and ⑥ live.

None of this is necessary: G7 asked for a change sent upstream, with reviewer
correspondence, and four are merged. Measured against the four criteria under
the candidate table, ⑥ and ④ are the two that pass — each verifiable from the
change alone, each useful to the next person who hits it, each one change, and
both in the directory where #524 and #526 already landed. Which goes, and
when, is the author's choice.

### 94773: whose turn it is

Gerrit keeps an attention set, the people a change is waiting on. On 94773 it
holds the author, put there when the −1 was posted on 2026-09-22, and neither
owner. Three threads are unresolved: Chinmay Shripad Hegde's two, answered on
2026-09-22 but not marked resolved, and Patrick Williams's comment of
2026-09-23, not answered. To an owner, then, the change is waiting on its
author, which explains nineteen quiet days at least as well as a decision
would. The author was shown this on 2026-10-12 and chose to wait one more
week; it is re-read on or after 2026-10-19.

### This repository's own red

The weekly `upstream` job had been red since 2026-10-05, and the README's
badge with it. Not upstream's doing: the job's unit-test step had never
passed. libspdm's own workflow copies the sample keys and runs every test from
`build/bin`; the step did neither. Fixed in `0451fac`, and the badge counts
push runs only since `614bc7c`. `LOG.md`, 2026-10-12, has the reproduction.

## The sample policy on OPA 1.x, prepared — 2026-10-13

Candidate ⑥, chosen from the two above as the one a reviewer can check most
completely from the change alone. Prepared on `8f36665` as **`5800c37`**,
unsigned, on branch `sample-policy-rego-v1` in the worktree
`work/spdm-emu-rego` of `work/spdm-emu-pr`. Nine lines in, seven out:
`import rego.v1`, `contains` on the four partial set rules, and `if` on all
seven rule heads. The file's
LF endings and its missing final newline are kept, so the diff is those lines
and nothing else. A duplicate search first (`rego`, `OPA`, `SpdmSamplePolicy`,
`v0-compatible`, `rego.v1`, `OpaTool`) found nothing but #120, a readme typo
fixed in 2022, and #524's own mention of `--v0-compatible`. The file was last
changed on 2022-08-01.

Every `Tested:` line was run against the committed bytes — `git show` and
`git archive` of the commit, not the working tree:

| claim | result |
|---|---|
| `opa check`, opa 1.20.2 | before: 11 `rego_parse_error`, exit 1; after: none. Both clean under `--v0-compatible` |
| older OPA, official binaries checked against the release's own sha256 (added after the second look below) | 0.70.0 and 0.59.0: both files check clean and give the same `data.spdm` on the sample input. 0.58.0: the old file checks clean, the new one fails with three `rego_parse_error` |
| the readme's flow, on the shipped samples | `json_to_cbor` 996 bytes, `cbor_to_json` 4312, `OpaTool.py` 5779 — #524's numbers — then the readme's `opa eval`: exit 2 before, exit 0 after, with `error_code` 0 and both checks true |
| nothing else changes | all ten rules in `data.spdm` equal, the old policy under `--v0-compatible` against the new one with and without it, on the shipped input and on two copies with one digest or one svn changed; both copies give `error_code` 1 |

The run found the first draft of the message wrong once: it said the readme's
command exited 1 before the change. `opa eval` exits 2 on a parse error; it is
`opa check` that exits 1. Corrected before anything was signed, and the tree,
`89010fc`, did not change. The run before that printed nothing at all and
exited 1 — the check script itself had a bug, and its stderr was not
captured — so nothing was concluded from it.

### The second look, before the pull request was opened

After the author had signed and pushed it, and before he opened the pull
request, he asked once more whether this was a real problem. Re-asked as five
questions, four held: the binary that gave the eleven errors is OPA's own
1.20.2 static build, from the URL in `third_party/opa.pin`; OPA 1.0's release
notes (2024-12-20) say `if` and `contains` are now mandatory; the release a
new user downloads today is 1.21.2, published that day; and the readme's other
path, the Rego Playground, was not checked, so the change claims only the
command line.

The fifth did not hold. The message said `import rego.v1` "keeps the file valid
where v0 is still the default" — every 0.x release — and what had been run was
1.20.2 under `--v0-compatible`. Official 0.58.0, 0.59.0 and 0.70.0 binaries,
each checked against its release's sha256:

| OPA, as measured | the policy on `main` | the change |
|---|---|---|
| 0.58.0 | parses | **three `rego_parse_error`** |
| 0.59.0 (2023-11-30) and 0.70.0 | parses | parses; `data.spdm` the same |
| 1.20.2 — v1 has been the default since 1.0, 2024-12-20 | **eleven `rego_parse_error`** | parses |

Read from those versions and from OPA's release notes, the change trades the
releases before 0.59.0 for every release since, which is the right trade — and
the text now says it is a trade. The corrected
message was signed by the author as **`09557d7`** — the tree still `89010fc`,
one sign-off — and force-pushed over his own branch before any pull request
pointed at it. Why 0.58.0 reports a missing `if` on lines that have one was not
investigated.

`rats/interop.sh` asserts that the sample does **not** parse as Rego v1. It
reads the pinned 4.0.0-rc tree, so nothing changes until a re-pin; if this has
merged by then, that assertion fails as expected, and its message — that OPA's
default has changed — will be the wrong explanation.

The title is the commit's subject. The body, as sent:

> OPA 1.0 made Rego v1 the default, and `SpdmSamplePolicy.rego` is written in
> v0. On a current OPA (1.20.2 here), the command the readme gives,
>
>     opa eval -i <OPA input file> -d <spdm policy rego file> "data.spdm"
>
> stops with eleven `rego_parse_error`s (`` `if` keyword is required before
> rule body``, `` `contains` keyword is required for partial set rules``), so
> the sample flow only completes with `--v0-compatible`, which is how I ran it
> for #524.
>
> This adds `contains` to the four partial set rules and `if` to the seven
> rule bodies, plus `import rego.v1`, so that OPA 0.59.0 and the later 0.x
> releases, where v0 is still the default, read it too. Releases before
> 0.59.0 (November 2023) do not; 0.58.0 rejects it. Nothing else changes.
>
> On the shipped samples (`SpdmSampleCoMid.json` through `json_to_cbor` and
> `cbor_to_json`, then `OpaTool.py` with `SpdmSampleMeasurement.json`), all
> ten rules in `data.spdm` have the same value before (under
> `--v0-compatible`) and after, on that input and on two copies with one
> digest or one svn changed:
>
> | input | `error_code` | `SPDM_HASH_CHECK` | `SPDM_SVN_CHECK` |
> |---|---|---|---|
> | as shipped | 0 | true | true |
> | one digest changed | 1 | false | true |
> | one svn changed | 1 | true | false |

The text to paste is `~/spdm-lab/work/sample-policy-rego-v1.pr-body.md`: the
same words, with each paragraph on one line.

Sending it, the author's:

```bash
cd ~/spdm-lab/work/spdm-emu-rego
git fetch origin && git log --oneline -1 origin/main   # still 8f36665? if not, stop: re-run the checks first
git show HEAD                                         # read it once
git commit --amend -s --no-edit                       # the DCO sign-off: yours
bash /mnt/c/Users/Key20/Desktop/mctp-spdm-pqc/harness/check_upstream_commit.sh .   # expect no FAIL
git push fork sample-policy-rego-v1
# then open the pull request with the title and body above
```

The second look added two steps between the push and the pull request:
`git commit --amend -s -F ~/spdm-lab/work/sample-policy-rego-v1.commit-msg.txt`
and `git push --force-with-lease fork sample-policy-rego-v1`. The first signed
version, `adbaa8b`, carried the overclaim, and it was replaced before anything
pointed at it.

### Sent — 2026-10-12, 16:52 UTC

| | |
|---|---|
| URL | <https://github.com/DMTF/spdm-emu/pull/536> |
| Opened | 2026-10-12 16:52:16 UTC by the author, from `Jhongwe1:sample-policy-rego-v1`. Title as above; body byte-identical to the file, 1245 bytes, read back from the API |
| Commit | **`09557d7`**: tree `89010fc`, the bytes tested; parent `8f36665`, still `main` when it was opened; one sign-off, the author's; `check_upstream_commit.sh` satisfied |
| Before opening | the second look above; the duplicate search repeated, and no open pull request touches the policy |
| Reviewers | `jyao1`, `steven-bellock`, added by CODEOWNERS |
| Checks | DCO success; **45 of 45** check runs success, every VS2019 build among them, the last at 17:15:37 UTC; `mergeable_state` clean. Read from the API |
| Outcome | **merged**, 2026-10-13 06:45 UTC, by `jyao1`, without a review or a comment, as `1229103`, byte-identical ([§](#candidate-4s-change-sent-as-537--2026-10-13)) |

## Candidate 4's change, sent as #537 — 2026-10-13

Read on 2026-10-12 at 17:45 UTC, sixteen minutes after #533's assignee,
`LeonLinAtAMI`, answered: *"Please go ahead and base your PR on #530, since
it touches the same call sites. I have no strong preference on how the
warning is printed. It would be nice to cover all `get_certificate` call
sites, including `spdm_device_attester_sample`."* The issue had offered to
base the change on #530 "if it lands first". It had not landed, so the change
is stacked on it, the way his #531 was stacked on #527.

The same comment asked `steven-bellock` about the responder's side: in the
encapsulated flow for mutual authentication the certificate step's warning is
checked with `LIBSPDM_STATUS_IS_ERROR` only and then overwritten by the flow
handler's call, so an Integrator cannot see it (`libspdm_rsp_encap_response.c`
598–611 and 723 at libspdm `98caf80`, its `main` that day — read here, and it
says what he says). The question was not this project's, and it was left
alone.

### Seven calls, and two that cannot print

| file, at #530's head | line | reads | the issue's reproduction reaches it |
|---|:-:|---|---|
| `spdm_requester_authentication.c` | 63 | slot 0 | yes |
| `spdm_requester_authentication.c` | 72 | the other slot, 4 there | yes |
| `spdm_requester_authentication.c` | 80 | `--slot_id` other than 0 | no |
| `spdm_requester_authentication.c` | 110 | the same slot, again | yes |
| `spdm_requester_session.c` | 87 | inside the session | no: `CERT` is in the default `--exe_session`, and the reproduction's `KEY_EX` leaves it out |
| `spdm_device_attester_collection.c` | 25 | slot 0 | no |
| `spdm_device_attester_collection.c` | 69 | slots 1–7, inside the session | no |

Two things the answer did not say, measured before anything was written. The
attester sample provisions **no root**: only the requester and the responder
set `LIBSPDM_DATA_PEER_PUBLIC_ROOT_CERT`, and with none provisioned libspdm
passes the authority check (`libspdm_com_crypto_service.c` 798–804 at
`a6994ee`: *"When there is no root_cert in local_context, the return is true
too"*). In the sample as shipped the warning cannot occur, and the line is for
the copy of it that adds a root. And #533's reproduction reaches three of the
requester's five calls; the other two need their own flags.

### The change

After each call's `LIBSPDM_STATUS_IS_ERROR` block, the same four lines:

```c
if (status == LIBSPDM_STATUS_VERIF_NO_AUTHORITY) {
    EMU_INFO("Slot %d: certificate chain matches no provisioned root "
             "(LIBSPDM_STATUS_VERIF_NO_AUTHORITY), continuing\n", slot_id);
}
```

`EMU_INFO`, because the macros' own comment keeps `EMU_ERR` for error
conditions, it prefixes `ERROR:`, and this flow carries on; the newest
non-fatal notice in the requester, `8f36665`'s *"--meas_att NEW is ignored"*,
is an `EMU_INFO` too. `printf` in the attester, whose fifteen other outputs are
all `printf`. No new macro, and `spdm_emu.h` untouched: #529, #530 and #496 edit
it, and #531 did until it merged. Inline at each call rather than in a helper, because the sample is
what people read to learn the API, and the check reads best beside the call.
+30 −1 in three files, the −1 being the attester file's copyright year, and
ASCII only, which `9975786` made the first thing to check there.

### Tested, twice

Release, `CRYPTO=openssl`, a build without the change against a build with it,
every run against the same unmodified responder, whose binary hashed the same
with and without the change. "Swapped" is #533's reproduction: the requester's slot-0
anchor replaced by the stock slot-1 root.

| requester | stock anchors, either build | swapped, without the change | swapped, with it |
|---|---|---|---|
| `--exe_conn DIGEST,CERT,CHAL,MEAS --exe_session KEY_EX` | no line | no line | slots 0, 4, 0 |
| the same, and `--slot_id 4` | no line | no line | slots 4, 4 |
| `--exe_conn DIGEST,CERT,CHAL,MEAS --exe_session KEY_EX,CERT` | no line | no line | slots 0, 4, 0, 0, 4 |

In all six pairs the exit status (0), the other output lines and the order of
the messages in the capture — 578, 576 and 582 — are the same without the
change as with it.

The attester could not be tested as shipped — candidate 21, in the table
above — so its calls were run with a local patch, never sent, that adds
`CHUNK_CAP` and, once the connection is negotiated, provisions one root the
way the requester does. The patch prints the size of the root it loaded, 472
bytes for `ca.cert.der` and 473 for `ca1.cert.der`, so every run shows that
it took effect. Its first version provisioned the root before negotiation,
when the algorithm it picks the file by is still 0; its own check reported
that no root had been read, and it was moved. Since #531,
`--max_spdm_msg_size 4608` would have done what the patch's `CHUNK_CAP` did;
that was found afterwards, and the root is needed either way.

| attester, with the local patch | root `ca.cert.der` | root `ca1.cert.der` |
|---|---|---|
| without the change | no line | no line |
| with it | slot 1 | slots 0 and 4 |

The slot-1 line was not expected, and it was not explained away: the root hash
at the head of each chain the attester saved says that slots 0 and 4 chain to
`ca.cert.der` and slot 1 to `ca1.cert.der`, so each line is true — the patch
provisions one root where the requester provisions two. The saved chains are
byte-identical without and with the change. After both variants the tree was
returned to the commit and rebuilt, and the binaries hashed as before, which is
how the commit is known to be the bytes that were tested.

### What the eighteen hours before the sign-off changed

Prepared on 2026-10-12 at 18:36 UTC as `028c986`, on #530's `92034e5`. When
the author had reviewed it, at 13:02 UTC on the 13th, the freshness check found
#536 and #531 merged and #530 rebased onto them as `9517beb`. Its added and
removed lines were unchanged and its patch-id was not — the context around
them had moved — so the commit was rebased onto it (`range-diff`: `=`; its own
patch-id unchanged), both builds were redone, and everything above was
repeated: every number the same. #531 had changed the attester's size setup,
so its numbers were read off the wire again rather than assumed: still
`0x000072c6`, 4,608 and 163,840.

One sentence had become false, "on #530's head (92034e5)". It now says "on top
of #530": a hash in a commit message expires at the next rebase of the change
below it, so the hashes are kept here instead.

The run also caught a tool of mine. The script comparing the order of messages
read each record's first byte, and every record starts with four bytes of MCTP
header, so its first "same order" compared strings of `00`. Found while reading
raw bytes for another reason, and fixed before any comparison was written down;
it now prints how many distinct items it saw, so a comparison that cannot tell
two messages apart says so.

### Sent — 2026-10-13, 13:19 UTC

| | |
|---|---|
| URL | <https://github.com/DMTF/spdm-emu/pull/537> |
| Opened | 2026-10-13 13:19:41 UTC by the author, from `Jhongwe1:cert-no-authority-warning`. Title the commit's subject; body byte-identical to the reviewed file, 1998 bytes, read back from the API |
| Commits | `9517beb` (#530, `LeonLinAtAMI`) and **`5195934`**: tree `c6e2c94`, the bytes tested; one sign-off, the author's; `check_upstream_commit.sh` satisfied. The body's first line asks for #530 to be merged first |
| Before opening | the freshness check repeated at 13:16 UTC; no open pull request touches the lines it changes, and no issue or pull request mentions `NO_AUTHORITY` |
| Reviewers | `jyao1` and `steven-bellock`, added by CODEOWNERS. `LeonLinAtAMI` offered to review; the API gives the author `pull` on the repository, which cannot request a reviewer, so the body mentions him |
| Linked | #533's timeline shows the reference; `Fixes #533` closes it on merge |
| Checks | DCO success; **45 of 45** check runs success, all eighteen VS2019 builds among them, the last at 13:41:55 UTC. Read from the API |
| Outcome | **merged**, 2026-10-15 14:07 UTC, by `jyao1`, as `423ba4e`, after it was approved and rebased onto `main` at his request as `9fdfdf1`, whose tree and message it carries ([§](#537-rebased-onto-main-and-the-corim-names-sent-as-542--2026-10-15)) |

## #537 rebased onto main, and the CoRIM names sent as #542 — 2026-10-15

Read from 12:34 UTC. Since 2026-10-13: an approval that came with a request,
six commits on `main`, an issue closed, and rows of the candidate table that
had changed under it.

### What came back

| who | when | what |
|---|---|---|
| `LeonLinAtAMI` | 10-14, 10:05 UTC | *"The second commit (the `VERIF_NO_AUTHORITY` reporting) looks good to me."* #530 still has open questions from `jyao1`, so #537 could go first: *"could you then drop the #530 commit and rebase onto main? I'll rebase #530 on top afterwards."* |
| `jyao1` | 10-15, 01:59 UTC | **approved** `5195934` |
| `jyao1` | 10-15, 02:01 UTC | *"I think the 5195934 is good. In general please do not rely on unapproved branch, that will cause dependency issue unnecessarily. Please just rebase to latest main and resolve conflict, then we can merge easily."* |

GitHub showed #537 as conflicting, and the conflict was not #537's. Merged onto
`main` `8674afe` without a working tree (`git merge-tree --write-tree`), #530's
commit `9517beb` conflicts in `doc/spdm_emu.md`, `key.c`, `spdm_emu.c` and
`spdm_emu.h`, which three of `main`'s new commits — #529, #538 and #540 — also
edit, and `jyao1` had already written *"conflict again..."* on #530 itself.
#537's own commit, replayed alone, merges clean. A change stacked on another
takes on every conflict of the one below it. The stack was what #533's assignee
had asked for on 2026-10-12; the maintainer who merges asked for `main`, and
that is the order that counts.

### The rebase, and every run again

`git rebase --onto origin/main 9517beb`, without a conflict. The added and
removed lines are the ones `jyao1` approved: `range-diff` shows only context,
`main`'s instead of #530's, so the patch-id moved, `b3f0691e` to `51bc4533`,
and the change did not. The seven calls are where they were — four in
`spdm_requester_authentication.c`, one in `spdm_requester_session.c`, two in
the attester sample — and none of the six new commits added another. One thing
#530 had carried is gone with it: the copyright year of
`spdm_requester_authentication.c`, which this change did not add back, so that
the diff stays the one approved. The message lost "on top of #530" and its
sign-off, and the author signed the rebased bytes himself: `9fdfdf1`, tree
`216ee85`.

Six commits, one of them a libspdm sync — `a6994ee` to `1d98f73`, 138 commits
— were reason enough to repeat everything rather than argue that nothing could
have changed: a Release build of `main` against one of the rebased change,
`CRYPTO=openssl`, every run against the same unmodified responder.

| requester | stock anchors, either build | swapped, `main` | swapped, with the change |
|---|---|---|---|
| `--exe_conn DIGEST,CERT,CHAL,MEAS --exe_session KEY_EX` | no line | no line | slots 0, 4, 0 |
| the same, and `--slot_id 4` | no line | no line | slots 4, 4 |
| `--exe_conn DIGEST,CERT,CHAL,MEAS --exe_session KEY_EX,CERT` | no line | no line | slots 0, 4, 0, 0, 4 |

578, 576 and 582 messages, in the orders recorded on 2026-10-13; in every pair
the exit status, the other output lines and the responder's log are the same
without and with the change. The attester as shipped still ends at
`GET_CAPABILITIES` — candidate 21 — and with the throwaway root patch of
2026-10-13, root `ca.cert.der` gives the line for slot 1 and `ca1.cert.der` for
slots 0 and 4, while the eight chains and the measurement it saves are
byte-identical without and with the change. The responder's binary is the same
in both builds, and a clean rebuild of the commit reproduces the tested
binaries.

### Sent back

| | |
|---|---|
| Pushed | 2026-10-15 13:16 UTC, by the author: `9fdfdf1` on `8674afe`, one commit, one sign-off, `check_upstream_commit.sh` satisfied |
| Body | edited by the author: the paragraph asking for #530 to be merged first removed, one parenthesis reworded; 1838 bytes, byte-identical to the file reviewed |
| Reply | 13:41 UTC, the author's, after a review of his draft: what was dropped and rebased, that the changed lines are the approved ones, that the tests were re-run on `main`, and that the point about unapproved branches was taken |
| Checks | **45 of 45**, DCO and all eighteen VS2019 builds among them, the last at 13:38:40 UTC; `mergeable_state` clean; the approval stands. Read from the API |
| Outcome | **merged**, 14:07 UTC, by `jyao1` |

### Merged, and the red check after it

`jyao1` merged #537 at 14:07:58 UTC, by rebase, as `423ba4e` on `8674afe`:
tree `216ee85` and the 2,261-byte message identical to `9fdfdf1`, the author's,
which are the bytes tested. Its `Fix #533.` closed the issue a second later.
This file's previous commit, written five minutes after the merge, still called
#537 in review: the last read of it had been at 14:03, and the state was not
read again before the commit that stated it.

Minutes later the repository's front page showed *"Some checks were not
successful"* for `main`, and the author asked whether his change had caused it.
One check of `423ba4e` had failed, `VS2019_openssl_build`, in its second step,
`actions/checkout`, which stopped with *"fatal: unable to access
'https://github.com/google/boringssl.git/': Empty reply from server"* while
fetching a submodule five levels down — `SPDM-Responder-Validator`, its
libspdm, OpenSSL, `cloudflare-quiche`, BoringSSL. Its build and test steps were
skipped, so nothing had been compiled, and the same tree had passed all 45
checks on the pull request, eighteen VS2019 builds among them. What the failure
measured was a third-party server's answer at 14:08 UTC. The other 43 checks
of `423ba4e`, seventeen VS2019 builds among them, passed, the last at 14:30:24
UTC. A re-run is the maintainers' to start, and nothing was said on the pull
request.

### Candidate ④, sent as #542

`json_to_cbor` translated two names in a list, `comid_tag_creator` and
`sha256`. `comid_creator`, `comid_maintainer`, `sha384` and `sha512` fell
through as text strings where CoMID has integers, while `cbor_to_json` maps all
six back from their integers through `ComidRoleTypeChoice` and
`SupportHashAlgMap`. The change looks the name up in those two tables: three
lines. `CoRimTool.py` is stored with CRLF line endings, all 392 lines, where
`OpaTool.py`, `SpdmMeasurement.py` and the policy beside it are LF — as
[`0001`](0001-corim-verify.md) and [`0003`](0003-corim-exit-status.md) recorded
for #524 and #526 — and the script that applied the edit refused the file until
it was made to keep them, so the diff is three lines and not 392.

Tested with `json_to_cbor` from `main` and from the commit, both taken out of
the commits by `git archive`, Python 3.12.3 and cbor2 5.6.5:

| input | `main` | the change |
|---|---|---|
| `SpdmSampleCoMid.json`, as shipped | 996 bytes | the same 996 bytes |
| the same, with the names `cbor_to_json` prints for its roles and digests | 1,033 bytes: `comid_creator` and four `sha512` as text | the sample's 996 bytes |
| all six names | 1,044 bytes | byte-identical to the same manifest written with integers, 997 bytes |

`cbor_to_json` gives the same 4,312 bytes from either build's output of the
sample, and prints the six names for the six integers. Its whole output still
cannot go back through `json_to_cbor` — `KeyError: 'corim'`, before and after —
which is ③, and the pull request says so, so that a reviewer who tries the
round trip is not surprised by it.

| | |
|---|---|
| URL | <https://github.com/DMTF/spdm-emu/pull/542> |
| Opened | 2026-10-15 13:44 UTC by the author, from `Jhongwe1:corim-list-names`. Title the commit's subject; body 1489 bytes, byte-identical to the reviewed file, read back from the API |
| Commit | **`0bdb70b`**: tree `c665618`, the bytes tested; parent `8674afe`, still `main` when it was opened; one sign-off, the author's; `check_upstream_commit.sh` satisfied |
| Before opening | no open pull request touches `spdm_device_verifier_tool/`, and no issue or pull request mentions `translate_data`, `comid_creator`, `comid_maintainer` or `SupportHashAlgMap` |
| Reviewers | `jyao1`, `steven-bellock`, added by CODEOWNERS |
| Checks | DCO success; **45 of 45** check runs success, all eighteen VS2019 builds among them, the last at 14:08:55 UTC; `mergeable_state` clean. Read from the API |
| Outcome | open |

### What moved under the other rows

- **`main`**, `1229103` to `8674afe`: #529 (`--ct_exponent`, `--rtt`), #538
  (removes `--slot_count`), #539, #540, and #541, which also syncs libspdm. The
  submodule's new commit had to be fetched from `DMTF/libspdm` by hash and
  given a ref: this clone's submodules come from a local mirror, and
  `git submodule update` re-fetches from there any commit that no ref reaches.
- **3.** #532 was closed by #538, which removed `--slot_count`. Its other
  subject, the shared `res`, is unchanged at `8674afe`: `spdm_responder_spdm.c`
  reads slots 0, 1 and 4 into one variable, lines 506 to 557, and tests it
  once, at 565. The issue is closed and the defect is not.
- **20.** At `8674afe` the responder with `--trans NONE` and `CHUNK_CAP`
  cleared starts; the requester's NONE flow runs to its end — 286 messages
  received and no session, which the requester skips on NONE by design — and
  the responder's `CAPABILITIES` carries `DataTransferSize` and
  `MaxSPDMmsgSize` both 4,736, where #358's error was 4,608 against 4,736. With the requester's
  `CHUNK_CAP` cleared instead, or both, the run also exits 0 with no `ERROR:`
  line — read from the log, without a trace. #531 changed that computation; no
  build here has bisected which commit made the difference.
- **16.** § ⑯ said the requester exits 1 having printed nothing at all, and
  [`../pqc-cost.md`](../pqc-cost.md) §12 said the same. Both signed arms' logs,
  committed with those sentences on 2026-09-14, begin `ERROR:
  do_authentication_via_spdm - 80020001`: `LIBSPDM_STATUS_VERIF_FAIL`, written
  by `EMU_ERR` to stderr. It was found because #529's new help text says that a
  responder using slow algorithms such as SLH-DSA needs a larger
  `--ct_exponent`; before anything was rewritten on that hint, the arm's own
  log was read, and the status in it names a verification, not a wait. Both
  sentences are corrected. The row is no more sendable than it was: which
  check fails inside the verification still needs a Debug build.
- **2, 15, 21 and ③**, re-read at `8674afe`: unchanged. The defaults still set
  `CHUNK`, `EP_INFO_SIG` and the responder's `MEL`, and neither `By default`
  line names them; `exit(0)` occurs 98 times, all in `process_args()`; the
  attester's request is still `0x000072c6` with 4,608 and 163,840, and
  `--max_spdm_msg_size 4608` still gets it through; `cbor_to_json`'s output
  still stops `json_to_cbor`. Of the four pull requests that edited
  `print_usage()` and `process_args()`, #529 and #531 have merged, and #530
  and #496 have not.

### What decides what goes next

- #542: review. #537 is merged.
- 3: the issue that reported it is closed and the defect is not. Whether to
  raise it again, and where — on #532, whose reporter offered a fix, or as a
  change — is the author's question.
- 21: a question, and the nearest of the rest to sendable.
- 2 and 15: after #530.
- ③: a question first. 13: a conversation. 16: a Debug build.
- 94773: re-read on or after 2026-10-19.

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

## A window that closes rather than a repository — 2026-08-31

Not a contribution, and filed under G7 only because it is the same kind of
activity: engaging with something outside this repository that will not wait.

DMTF's SPDM working group put *Plan of Hybrid Support for Traditional Crypto and
Post Quantum Crypto (PQC) in SPDM 1.5* out for industry feedback in June 2026,
closing **2026-08-31** — today. Both the WIP and DSP0274 1.4.0 were fetched and
their digests recorded; the WIP is eight pages and was read in full, DSP0274 was
read only in the sections a captured field name led to.

**What the WIP asks for is narrower than "feedback".** Page 8 asks two
questions, and one of them — *does your company require algorithm combinations
besides the highlighted ones* — is not answerable by a graduate project. Saying
so, and answering only the other one, is the whole difference between a useful
submission and noise.

The draft, the angle chosen, the two angles rejected, and the provenance of
every number in it are in
[`spdm15-hybrid-feedback.md`](spdm15-hybrid-feedback.md). In one line: the WIP
says hybrid message fields will carry *the concatenation of two pieces of data*,
and its second requirement says a 1.4 device that already holds a Traditional
chain and a PQC chain is upgradeable — but such a device holds them in two
slots, and concatenation puts them in one. This project has measured both sides
of the resulting cost, so the submission asks about it rather than asserting
anything.

**Evidence strength, stated before anyone asks.** Lower than a GitHub pull
request. A portal submission may produce no public URL, no review thread, and no
external confirmation it was read. It is evidence of **timing** — that the
implementation and the standards draft were being worked on in the same weeks —
and not evidence of contribution. G7 still rests on the two repository
candidates above.

**And the actual submission is not done.** It needs a DMTF Feedback Portal
account and it has to go in the author's own words, not a draft's. If the
deadline passes without it, that is recorded as a missed window rather than
quietly dropped: the draft and the reading are real either way, and *"I read the
WIP during the review period and wrote up a question I did not send"* is a true
sentence, while the alternative is not.

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

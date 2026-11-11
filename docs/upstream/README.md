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
| ★★ #542 **MERGED: seven of seven** | **done** | 2026-10-16, 02:04 UTC | by **Jiewen Yao** (`jyao1`), by rebase, as **`5b6e3a7`** on `423ba4e`, with no review and no comment: the message and `CoRimTool.py`'s blob (`08a4e885`) are byte-identical to `0bdb70b`, the author's. All seven pull requests this project has sent to `DMTF/spdm-emu` are merged. [§](#542-merged-and-two-more-prepared--2026-10-17) |
| #530 merged | **not this project's** | 2026-10-16, 02:14 UTC | `LeonLinAtAMI`'s `--cert_buf` and `--cert_block_len`, as `376869f`. Rows 2 and 15 had waited on it; the only open pull request that edits `print_usage()` or `process_args()` is now #496, untouched since 2026-06-27 |
| Every unsent row re-read at `376869f` | **done** | 2026-10-17 | 21 reproduces, and is the unanswered half of [#458](https://github.com/DMTF/spdm-emu/issues/458), which [`0004`](0004-data-transfer-size.md) §4 had recorded on 2026-09-29 as no longer reproducing — corrected there; upstream's own fix for the requester and the responder, `5ef1123`, is the design the row had called a question. 15 has 102 `exit(0)`; 2 and 3 unchanged. [§](#every-unsent-row-at-376869f) |
| Candidates 21 and 15 prepared | **prepared** | 2026-10-17 | *attester: base MaxSPDMmsgSize on CHUNK_CAP*, `0bd516a`, and *spdm_emu: exit 1 on an invalid argument*, `24849f6`, both on `376869f`, unsigned, every `Tested:` line run on the committed bytes. The sign-offs, the pushes and the pull requests are the author's. [§](#542-merged-and-two-more-prepared--2026-10-17) |
| ★ Candidates 21 and 15 **SENT** | **done** | 2026-10-17, 13:09 UTC | [`DMTF/spdm-emu` #545](https://github.com/DMTF/spdm-emu/pull/545), *attester: base MaxSPDMmsgSize on CHUNK_CAP*, and [#546](https://github.com/DMTF/spdm-emu/pull/546), *spdm_emu: exit 1 on an invalid argument*, six seconds apart, both on `376869f`: signed by the author as `afa4bb1` and `0dd5f75`, whose trees are the tested `ba9a379` and `024b536`; bodies byte-identical to the reviewed files; reviewers by CODEOWNERS; DCO success and 45 of 45 check runs on each. [§](#sent--2026-10-17-1309-utc) |
| ★★ #545 and #546 **MERGED: nine of nine** | **done** | 2026-10-19, 01:50 and 01:51 UTC | by **Jiewen Yao** (`jyao1`), by rebase, as **`ad6095f`** and **`ce3b513`** on `376869f`: trees, patch-ids and messages identical to `afa4bb1` and `0dd5f75`, the author's. #546 carried `steven-bellock`'s approval of 2026-10-17, 14:13 UTC, without a comment; #545 had no review. All nine pull requests this project has sent to `DMTF/spdm-emu` are merged. [§](#545-and-546-merged-2-sent-and-3-asked--2026-10-19) |
| `openbmc/spdm` 94773 | **in review, no movement** | checked 2026-10-19 | unchanged since 2026-09-23 17:10 UTC: patchset 3, CI `Verified+1`, no Code-Review vote, three threads unresolved. The week the author chose to wait on 2026-10-12 has passed; what happens next is his |
| ★ Candidate 2 **SENT** | **done** | 2026-10-19, 12:50 UTC | [`DMTF/spdm-emu` #548](https://github.com/DMTF/spdm-emu/pull/548), *spdm_emu: complete the --cap defaults in --help*: `aecb922` on `ce3b513`, +2 −2, signed by the author; body byte-identical to the reviewed file; reviewers by CODEOWNERS. On `main` the two `--help` lists, passed back as `--cap`, drop two of the Requester's capability flags and three of the Responder's, and the default flow then sends 32 messages fewer and exits 0; with the change they reproduce the defaults. [§](#candidate-2s-change) |
| ★ Candidate 3 **ASKED** | **done** | 2026-10-19, 12:49 UTC | issue [#547](https://github.com/DMTF/spdm-emu/issues/547): the slot-4 chain decides whether any slot is provisioned, measured seven ways at `ce3b513`, two of them without a line from the responder; it asks which of two behaviours, and names #532's reporter, who had offered the fix. Body byte-identical to the reviewed file. [§](#candidate-3s-question) |
| ★★ #548 **MERGED: ten of ten** | **done** | 2026-10-20, 02:40 UTC | by **Jiewen Yao** (`jyao1`), by rebase, as **`f7fa183`** on `897f13e`, with the patch-id and the message of `aecb922`, the author's, and no review or comment. The base had moved: `steven-bellock`'s #549 synced libspdm and `SPDM-Responder-Validator` to `4.0.0-rc3` the evening before. All ten pull requests this project has sent to `DMTF/spdm-emu` are merged. [§](#548-merged-and-3s-change-sent-as-550--2026-10-20) |
| #547 answered | **answered** | 2026-10-19, 14:24–15:28 UTC | #532's reporter and a second user chose option 2; `jyao1` doubted the use case, and wrote: *"First, I do not mind to fix. Feel free to submit patch if you want."* [§](#548-merged-and-3s-change-sent-as-550--2026-10-20) |
| ★ Candidate 3's change **SENT** | **done** | 2026-10-20, 09:04 UTC | [`DMTF/spdm-emu` #550](https://github.com/DMTF/spdm-emu/pull/550), *spdm_responder_emu: provision each slot that loads*: `8c43299` on `f7fa183`, +24 −11, signed by the author; option 2 of #547, measured against `main` in 48 runs, six of them on the `DEVICE=tpm` build, where a responder configured with one slot reproduces #547 with nothing removed. The author's answer to `jyao1`'s question went to #547 the same morning. [§](#548-merged-and-3s-change-sent-as-550--2026-10-20) |
| Candidate 22, found while testing it | **recorded, not sent** | 2026-10-20 | `spdm_requester_emu` built for a TPM responder with one slot stops before `GET_DIGESTS`: once the algorithms are negotiated it reads the responder's root for slot 1, and exits 1 when it cannot. [§](#candidate-22-found-while-testing-it) |
| ★ #550 **changes requested, and changed** | **done** | 2026-10-20, 10:11 and 12:23 UTC | `annamdi`, #532's reporter, asked that slot 4's chain be read, and reported, only in a multi-key connection, the only kind that provisions slot 4. Right: `8c43299` warned about slot 4 where it could never be provisioned, which this project's own runs had shown. Revised as **`dcf2cc4`**, measured in 84 runs, signed by the author and force-pushed; the body and two replies are his. CI 45 of 45. [§](#550-reviewed-and-changed--2026-10-20) |
| ★ #550 **approved twice** | **approved** | 2026-10-20, 14:55 and 15:02 UTC | by `annamdi`, #532's reporter, two and a half hours after the revision was pushed, and by `giovanni-cf`, the second user #547 heard from, each without a comment: the two deployments the question was about. At 15:08 `steven-bellock` removed his own review request, as he had on #524 before `jyao1` merged it; `jyao1` is the one reviewer still requested. Read on 2026-10-26: not merged, `main` still `f7fa183`. [§](#550-approved-twice-and-the-corim-round-trip-prepared--2026-10-26) |
| Candidate ③ prepared | **prepared** | 2026-10-26 | *CoRimTool: accept the JSON cbor_to_json writes*: `baedf75` on `f7fa183`, +7 in `CoRimTool.py` and +2 in its readme, unsigned, every `Tested:` line run on the committed bytes. Measured first, at `f7fa183`: the two keys `cbor_to_json` wraps the map in are the only asymmetry, and the shipped policy reads through them, which made the call the row had waited on. The sign-off, the push and the pull request are the author's. [§](#550-approved-twice-and-the-corim-round-trip-prepared--2026-10-26) |
| ★ Candidate ③ **SENT** | **done** | 2026-10-26, 05:28 UTC | [`DMTF/spdm-emu` #551](https://github.com/DMTF/spdm-emu/pull/551), *CoRimTool: accept the JSON cbor_to_json writes*: `2ee099d` on `f7fa183`, +9 −0, signed by the author; body byte-identical to the reviewed file; reviewers by CODEOWNERS. Before it was opened the author caught, on the preview, `#6.500` rendered as a link to issue #6; the body and the commit message were reworded to `tag 500`, the commit signed again, and the replacement force-pushed by the author after the classifier here refused it. DCO and 45 of 45 check runs success by 06:16 UTC; no review by then. [§](#sent--2026-10-26-0528-utc) |
| ★★ #551 **MERGED: eleven of twelve** | **done** | 2026-10-26, 14:21 UTC | by **Jiewen Yao** (`jyao1`), by rebase, as **`9cc8b46`** on `f7fa183`, nine hours after it was opened, with no review and no comment: the tree (`4639bc2`), the patch-id and the message are those of `2ee099d`, the author's. Read on 2026-10-29. Eleven of the twelve pull requests this project has sent to `DMTF/spdm-emu` are merged; #550 is the twelfth. [§](#551-merged-550-changed-for-its-maintainer-and-23-asked-as-552--2026-10-29) |
| #550 **answered by its maintainer** | **one comment, two parts** | 2026-10-26, 14:29 UTC | `jyao1`, seven minutes after merging #551: *"Please aware that slot 0 is must-have if cert_cap is there. Otherwise it is an invalid configuration. I think this should error out directly. Other slots are optional."* And: *"It is acceptable, if the configuration is consistent. Have you checked any data in sample library is consistent with slot 1 and slot 4, they are not there? E.g. KeyPair ID"*. Read on 2026-10-29. The second is his own libspdm [#3638](https://github.com/DMTF/libspdm/issues/3638), for the slots a responder leaves empty. [§](#551-merged-550-changed-for-its-maintainer-and-23-asked-as-552--2026-10-29) |
| ★ #550 **changed for its maintainer, and his question answered** | **done** | 2026-10-29, 15:26 and 15:59 UTC | the first comment as **`b20e680`** on `9cc8b46`, +8 −2 on `dcf2cc4`: with `CERT_CAP` set, a slot 0 whose chain does not load now stops the responder, with an `ERROR:` line, once the algorithms are negotiated. The second answered with measurements rather than code: the sample library's key pairs keep their association with a slot left empty, on `main` as with the change, and libspdm's `DIGESTS` cannot report a slot that has a key pair and no chain ([libspdm #2493](https://github.com/DMTF/libspdm/issues/2493)), so the reply offers two ways to make the two agree, recommends one and asks which. Signed and force-pushed by the author; the body and the reply are his, each byte-identical to the reviewed file. DCO and 45 of 45 check runs success; the two approvals stand, on `dcf2cc4`. [§](#551-merged-550-changed-for-its-maintainer-and-23-asked-as-552--2026-10-29) |
| ★ Candidate 23 **ASKED** | **done** | 2026-10-29, 15:56 UTC | issue [#552](https://github.com/DMTF/spdm-emu/issues/552): with RSA-2048 on both sides, the requester's `SET_KEY_PAIR_INFO` step erases the key pair the connection uses, so no session opens, and the requester exits 0. Found that day in the runs for `jyao1`'s second comment; #550's reply points at it. Title and body byte-identical to the reviewed files. [§](#551-merged-550-changed-for-its-maintainer-and-23-asked-as-552--2026-10-29) |
| #550 and #552 | **no answer yet** | checked 2026-11-01, 20:19 UTC | #550 unchanged since the reply of 2026-10-29, `jyao1` the one reviewer requested and the two approvals standing; #552 without a comment, label or assignee; `main` still `9cc8b46`. One working day had passed for the maintainer, whose public activity was his own libspdm pull requests. Not pinged. `openbmc/spdm` 94773 unchanged since 2026-09-23 17:10 UTC. [§](#candidate-16s-cause-found--2026-11-02) |
| ★ Candidate 16's cause **found** | **found, by intervention** | 2026-11-02 | in a connection that is not multi-key, the sample responder signs SLH-DSA with slot 4's private key: libspdm #3650's key selection compares KeyPairID 0 with slot 4's, and slot 4's is 0 for any algorithm without a key pair in the sample's table, which lists ML-DSA only. Giving `end_responder4.key` the bytes of `end_responder.key`, and changing nothing else, turns each failing arm it was tried on into a pass: three SLH-DSA parameter sets and both signed operations on `9cc8b46`, and S1's own run on the build of 2026-09-14. The requester's verification was right; the two sentences that said what was left was it are corrected. Six of the twelve SLH-DSA parameter sets never reach a signature: row 24. [§](#candidate-16s-cause-found--2026-11-02) |
| #550 and #552 | **no answer yet** | checked 2026-11-02, 05:11 UTC | as at 20:19 UTC the day before: #550 at `b20e680`, its last activity the reply of 2026-10-29; #552 without a comment, label or assignee; `main` still `9cc8b46`. Not pinged. [§](#candidate-16s-change-prepared--2026-11-02) |
| ★ Candidate 16's change **prepared** | **prepared** | 2026-11-02 | in libspdm, on `main` `6de8048`: KeyPairID 0 always selects the default key, at the four places #3650 and #4149 compare it with slot 4's; unsigned, tree `20b1b0c`. With it, both roles' SLH-DSA signatures verify on the six parameter sets that get that far, the other algorithms are unchanged, and libspdm's seven basic unit tests give the same results. spdm-emu's own PQC command then passes whole without multi-key; with it, the default, the second session, on slot 4, still fails, because SLH-DSA has no KeyPairID for slot 4 to carry — and the text says so. The fork, the sign-off, the push and the pull request are the author's; held for those, no longer for #550's answer. [§](#candidate-16s-change-prepared--2026-11-02) |
| Candidate 24's cause, and candidate 25 | **read; recorded** | 2026-11-02 | 24: the sample's chain readers call `libspdm_verify_cert_chain_data()`, which refuses a chain longer than 0xFFFF bytes less its header and the largest root hash, and all six chains are longer. 25: `spdm_requester_emu` exits 0 after any failure that follows its `GET_ENDPOINT_INFO` step — measured by leaving that step out of the same failing run, which then exits 1. Neither sent. [§](#candidate-16s-change-prepared--2026-11-02) |
| ★ Candidate 16's change **SENT** | **done** | 2026-11-02, 08:43 UTC | [`DMTF/libspdm` #4268](https://github.com/DMTF/libspdm/pull/4268), *spdm_device_secret_lib_sample: Use the default key for KeyPairID 0*: `d8c077c` on `6de8048`, +20 −8, signed by the author: tree `20b1b0c`, the bytes tested; body byte-identical to the reviewed file; reviewers by CODEOWNERS. This project's first pull request to libspdm, from a fork made that day. Before the push the freshness check failed for reasons of its own — a filter wider than the change, and four searches that never ran, which its verdict did not read — and was fixed and re-run. `main` had moved to `0df82c8`, in none of the files the change depends on. **56 of 56** check runs success, DCO among them, the last at 08:59:55 UTC; no review or comment at 09:02 UTC. [§](#sent--2026-11-02-0843-utc) |
| ★ #550 **answered: option 1** | **answered** | 2026-11-02, 15:34 UTC | `jyao1` (comment 6581157819): *"I am OK with option-1. Please validate carefully to ensure the final state is consistent. Since slot 0 is always there, we need to handle 4 cases {slot 1 and slot 4, slot 1 only, slot 4 only, no slot 1 or slot 4}. Also please validate for responder side cert and requester side cert in mut auth case"* — after *"If you prefer to make slot 1/4 optional, the everything must be consistent."* Read here ten minutes later. [§](#550-answered-and-changed-on-both-sides--2026-11-03) |
| ★ #550's fourth version **prepared** | **prepared** | 2026-11-03 | two unsigned commits on `9cc8b46`: the responder's slots (v3 and option 1, each removal scoped to its connection), and the Requester's on both programs, candidate 22 among them, with one rule the four cases showed was missing. In each of the four cases, for both certificates and in every mutual-authentication mode tried, what each side reports matches what it provisioned. The Requester's slot-1 cases needed a local change to the sample library, which reads that slot from slot 0's file. Held for the author's review, sign-off and push. [§](#550-answered-and-changed-on-both-sides--2026-11-03) |
| libspdm #4268 | **in review** | 2026-11-02, 15:20 UTC | `steven-bellock` removed his own review request, as on #524 and #550 before; `jyao1` the one reviewer. No review and no comment at 17:20 UTC. |
| ★★ libspdm #4268 **MERGED** | **done** | 2026-11-03, 02:49 UTC | by **Jiewen Yao** (`jyao1`), as **`b068d55`** on `0f72079`, eighteen hours after it was opened, with no review and no comment: its diff and its message, as GitHub serves them, are byte-identical to `d8c077c`'s, the author's. This project's first change merged in libspdm. Read at 03:44 UTC, by the freshness check before #550's push. [§](#libspdm-4268-merged-and-550s-fourth-version-sent--2026-11-03) |
| ★ #550's fourth version **SENT** | **done** | 2026-11-03, 03:56 UTC | **`3985d32`** and **`ddb5fd1`** on `9cc8b46`, signed by the author: trees `fddf3f7` and `f193f1f`, the bytes tested; force-pushed over `b20e680` on his word. The title, the description and the reply are his, each byte-identical to the reviewed file. The three texts cite #4268, merged an hour before, for why each connection gives a slot back; the description and the reply each gained a clause, that spdm-emu's libspdm, `6cb52f2`, predates it. **45 of 45** check runs success, DCO among them, the last at 04:20:59 UTC. [§](#libspdm-4268-merged-and-550s-fourth-version-sent--2026-11-03) |
| ★★ #550 **APPROVED** | **approved** | 2026-11-06, 04:53 UTC | by **Jiewen Yao** (`jyao1`), on `ddb5fd1`, the fourth version, with no comment in the review; not merged at 18:26 UTC. The day before he had commented twice, on the reply's last two paragraphs: the Requester's slot 1 read from slot 0's file *"seems a bug ... Could you please file an issue first? If you can also provide a PR to fix, that would be great. The cert chain can never be shared. The only shared element is key"*; and of a later connection signing with slot 4's key, *"It seems another bug to me ... Why the code pick KeyPairID 0??? ... Could you please file issue too?"* [§](#550-approved-and-the-requesters-slot-1-sent-to-libspdm--2026-11-07) |
| ★ Candidate 27 **FILED and SENT** | **done** | 2026-11-06, 18:02 and 18:23 UTC | as he asked: issue [`DMTF/libspdm` #4299](https://github.com/DMTF/libspdm/issues/4299) and its fix, [#4300](https://github.com/DMTF/libspdm/pull/4300), *spdm_device_secret_lib_sample: Read the Requester's slot 1 chain*: **`420fbce`** on `c2b2573`, +89 −0, signed by the author, tree `b187841`, the bytes tested. Measured before and after in spdm-emu: slot 1's digest in the Requester's `DIGESTS` changes from slot 0's chain to `bundle_requester.certchain1.der`, and nothing else on the wire; with #550, removing that file now removes the slot. Titles and bodies byte-identical to the reviewed files; reviewers by `CODEOWNERS`. **56 of 56** check runs success — DCO, 54 in GitHub Actions and CIFuzz's code-scanning check — the last at 18:41:01 UTC; `mergeable_state` clean. [§](#550-approved-and-the-requesters-slot-1-sent-to-libspdm--2026-11-07) |
| #550's second comment **answered, not filed** | **answered** | 2026-11-06, 18:26 UTC | the author's reply, comment 6692282602, byte-identical to the reviewed file: slot 4 is not requested there; KeyPairID 0 is what libspdm passes outside a multi-key connection, and the sample compared it with slot 4's, also 0 once no key pair of the algorithm has slot 4 — the line #4268 changed. Measured: without the give-back the second connection opens `end_responder4.key` and fails; with #4268's two files it opens only `end_responder.key` and passes; and a request for slot 4 without its chain is answered `ERROR(InvalidRequest)`. An issue offered, if he still wants one. [§](#550-approved-and-the-requesters-slot-1-sent-to-libspdm--2026-11-07) |
| ★★ #550 **MERGED: twelve of twelve** | **done** | 2026-11-09, 01:43 UTC | by **Jiewen Yao** (`jyao1`), by rebase, as **`30f9fc8`** and **`0e9d60c`** on `9cc8b46`, three days after his approval and with no comment: trees `fddf3f7` and `f193f1f`, and each commit's diff and message byte-identical to `3985d32`'s and `ddb5fd1`'s, the author's. #547 closed with it. All twelve pull requests this project has sent to `DMTF/spdm-emu` are merged. Read on 2026-11-11. [§](#550-and-libspdm-4300-merged-and-candidates-25-and-28-prepared--2026-11-11) |
| ★★ libspdm #4300 **MERGED** | **done** | 2026-11-09, 07:04 UTC | by **Jiewen Yao** (`jyao1`), as **`306502a`** on `ee4199f`, after `steven-bellock`'s approval of 2026-11-06 without a comment, and with no review of his own: its diff and its message byte-identical to `420fbce`'s, the author's. #4299 closed by it, as completed, two seconds later. Both pull requests this project has sent to libspdm are merged. [§](#550-and-libspdm-4300-merged-and-candidates-25-and-28-prepared--2026-11-11) |
| `openbmc/spdm` 94773, and #552 | **no movement** | checked 2026-11-11 | 94773 unchanged since 2026-09-23 17:10 UTC: patchset 3, `Verified+1`, no Code-Review vote, three threads unresolved. #552 without a comment, label or assignee since it was opened on 2026-10-29 |
| ★ Candidates 25 and 28 **prepared** | **prepared** | 2026-11-11 | 25, in spdm-emu: the requester exits 0 after any failure past its `GET_ENDPOINT_INFO` step, where #290, for #265, had made every failure exit 1, and `8e33385` broke it; `spdm_requester_emu.c` +4 −5, tested on six builds against every Linux command line in `.github/workflows`. 28, in libspdm, found in spdm-emu's own CI log while confirming what 25 hides: a requester built with `RECORD_TRANSCRIPT_DATA_SUPPORT` signs `FINISH` over its own slot's responder chain, so its session on slot 4 fails, in each of the 109 CI runs that got that far since 2026-08-17, and the step passes; +1 line, measured by intervention. With 25 alone that step fails in four jobs, so the two are prepared to go together, 28 first. Both unsigned; the issue, the sign-offs, the pushes and the pull requests are the author's. [§](#550-and-libspdm-4300-merged-and-candidates-25-and-28-prepared--2026-11-11) |
| ★ Candidate 28 **FILED and SENT** | **done** | 2026-11-11, 17:10 and 17:22 UTC | issue [`DMTF/libspdm` #4312](https://github.com/DMTF/libspdm/issues/4312) and its fix, [#4313](https://github.com/DMTF/libspdm/pull/4313), *Use the session's peer slot for the FINISH signature*: **`d65fe0e`** on `839bc24`, +1 −0, signed by the author, tree `53cdef6`, the bytes tested. Titles and bodies byte-identical to the reviewed files; reviewers by `CODEOWNERS`. **56 of 56** check runs success, the last at 17:38:37 UTC. [§](#28-and-25-sent-and-28s-fixes-corrected--2026-11-11) |
| ★★ libspdm #4313 **APPROVED**, and its `Fixes:` corrected | **approved** | 2026-11-11, 17:35 and 17:52 UTC | by **`steven-bellock`**, without a comment, two minutes after he said on #4312 that the defect was introduced by `13db5117`, not by his #3435, which the commit's `Fixes:` had named. Read and confirmed: `13db5117` removed the line #4313 puts back. Re-signed by the author with that line alone changed, **`6495195`**, the same tree, and pushed over `d65fe0e` with a lease; the approval stayed, and the CI ran again, 56 of 56, the last at 18:07:22 UTC. The author's reply on #4312, byte-identical to the reviewed file, at 17:58 UTC. Waiting on `jyao1`. [§](#28-and-25-sent-and-28s-fixes-corrected--2026-11-11) |
| ★ Candidate 25 **SENT** | **done** | 2026-11-11, 18:10 UTC | [`DMTF/spdm-emu` #553](https://github.com/DMTF/spdm-emu/pull/553), *spdm_requester_emu: exit 1 on errors after EP_INFO*: **`ab7ed0a`** on `0e9d60c`, +4 −5, signed by the author, tree `89da40a`, the bytes tested. Title and body byte-identical to the reviewed files; reviewers by `CODEOWNERS`. Its description cites libspdm #4312 and #4313 in full, and both show the reference. CI as the description said: **41 of 45** check runs success, and the four that failed are the four jobs that run `Test_RECORD_TRANSCRIPT_DATA_consistent`, each at that step, the last at 18:33:54 UTC. [§](#28-and-25-sent-and-28s-fixes-corrected--2026-11-11) |

> **Not a deliverable of this project.** A change to `openbmc/docs` was
> submitted on 2026-08-11 under the other project. It appears nowhere in this
> repository's results and is mentioned only because of what it removes: the
> path from `git commit -s` to a change sitting in Gerrit has been walked once
> already, so what this project still owes upstream is a technical problem, not
> an administrative one.

## Candidates, and my judgement on each

Twenty-eight candidates have been recorded. Seventeen went as changes — #524,
#534, #526, #527, #536, #537, #542, #545, #546, #548, #551 and #550, and
libspdm #4268 and #4300, are merged, and 94773, libspdm #4313 and #553 are in
review — and three of the seventeen went first as questions:
candidate 4 as issue #533, whose assignee then asked this project for the
change, candidate 3 as issue #547, where the maintainer invited it, and
candidate 27 in #550's reply, which the maintainer called a bug and asked to
have filed and fixed: libspdm #4299 and #4300. A third design
question, candidate 23, went as issue #552 on 2026-10-29 and has no change yet. Candidate 3 had been
reported by someone else on 2026-10-02, in an issue the maintainer closed on
2026-10-15 without changing the lines the row is about. Another, 21, sent
as #545, turned out to have been asked about upstream ten months before this
project found it, in #458, which was closed when the other half of it was fixed. Two were fixed upstream by the
maintainer without this project, one of them before this project had found it. One, ⑭, was never true and is withdrawn, and one, ⑳, had been reported
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
was re-read at `8674afe` ([§](#537-rebased-onto-main-and-the-corim-names-sent-as-542--2026-10-15)).
Rows 2, 3, 8–11, 15 and 21 changed on 2026-10-17, at `376869f` ([§](#every-unsent-row-at-376869f)), and 15 and 21 again that evening, when they were sent as #546 and #545 ([§](#sent--2026-10-17-1309-utc)). Rows 2, 3, 15 and 21 changed on 2026-10-19, when #545 and #546 merged, 2 was sent as #548 and 3 asked as #547 ([§](#545-and-546-merged-2-sent-and-3-asked--2026-10-19)). Rows 2 and 3 changed, and row 22 was added, on 2026-10-20, when #548 merged and 3 was sent as #550 ([§](#548-merged-and-3s-change-sent-as-550--2026-10-20)), and row 3 again that evening, when #550 was reviewed and changed ([§](#550-reviewed-and-changed--2026-10-20)). Rows 3 and 8–11 changed on 2026-10-26, when #550's two approvals were read and ③ was measured, prepared and sent as #551 ([§](#550-approved-twice-and-the-corim-round-trip-prepared--2026-10-26)). Rows 3, 8–11 and 22 changed, and row 23 was added, on 2026-10-29, when #551's merge and `jyao1`'s comment on #550, in two parts, were read, #550 was changed for the first and answered on the second, and 23 was asked as #552 ([§](#551-merged-550-changed-for-its-maintainer-and-23-asked-as-552--2026-10-29)). Row 16 changed, and row 24 was added, on 2026-11-02, when 16 was re-run at `9cc8b46` and its cause found ([§](#candidate-16s-cause-found--2026-11-02)). Rows 16 and 24 changed again, and row 25 was added, that afternoon, when 16's change was prepared and measured ([§](#candidate-16s-change-prepared--2026-11-02)), and row 16 once more when it was sent as libspdm #4268 ([§](#candidate-16s-change-sent-as-libspdm-4268--2026-11-02)). Rows 3 and 22 changed on 2026-11-03, when #550's fourth version was prepared ([§](#550-answered-and-changed-on-both-sides--2026-11-03)), and rows 3, 16 and 22 again that day, when libspdm #4268 merged and the fourth version was sent ([§](#libspdm-4268-merged-and-550s-fourth-version-sent--2026-11-03)). Rows 3 and 27 changed on 2026-11-07, when #550 was approved and 27 was sent to libspdm ([§](#550-approved-and-the-requesters-slot-1-sent-to-libspdm--2026-11-07)). Rows 3, 22, 25 and 27 changed, and row 28 was added, on 2026-11-11, when #550 and libspdm #4300 were read as merged and 25 and 28 were prepared ([§](#550-and-libspdm-4300-merged-and-candidates-25-and-28-prepared--2026-11-11)), and rows 25 and 28 again that evening, when 28 was sent as libspdm #4313 and 25 as #553 ([§](#28-and-25-sent-and-28s-fixes-corrected--2026-11-11)).*

| # | where | the candidate | evidence | judgement |
|:-:|---|---|---|---|
| 1 | `openbmc/spdm` | no `README.md`, and a newcomer hits five build and test blockers with nothing to say they are expected | five blockers reproduced on 2026-08-11 and 2026-09-18, and re-run on 2026-09-23 | **sent**, 94773. The review of the 2025 attempt was read first and treated as the specification. A minimum compiler version was deliberately **not** part of it: that is a policy change, and a first change should not start an argument |
| 2 | `DMTF/spdm-emu` | `--help` omits three capabilities the defaults set | two source lines, and the `Flags` word on the wire | **merged**: sent as [#548](https://github.com/DMTF/spdm-emu/pull/548) on 2026-10-19, and merged on 2026-10-20 as `f7fa183`, its patch and message unchanged, on a base #549 had moved. Until then not sent: correct and small, but a text fix outranked by ② on usefulness, and a second change to a project before the first is answered is two conversations that do not happen. *2026-10-12: unchanged at `8f36665` — the defaults still set `CHUNK` and `EP_INFO_SIG`, and the responder's `MEL`, and the `By default` lines still omit them. Four open pull requests edit `print_usage()`, so it waits for them. 2026-10-15: unchanged at `8674afe` — `key.c` still sets `CHUNK` and `EP_INFO_SIG` for both and `MEL` for the responder, and neither `By default` line names them. #529 and #531 have merged; #530 and #496 still edit `print_usage()`. 2026-10-17: unchanged at `376869f`. #530 has merged, and #496, untouched since 2026-06-27, is the only open pull request that edits `print_usage()`. Not sent with 21 and 15: a third pull request the same day spends a reviewer's attention on two lines that do not go stale. 2026-10-19: sent as #548 once #545 and #546 had merged, and measured for the first time on the way: the documented lists, passed back as `--cap`, advertise `0x8800f7c6` and `0xb818fbf7` instead of `0x8882f7c6` and `0xb99afbf7` and a `MaxSPDMmsgSize` of 4,608, and the default flow loses 32 messages, `GET_ENDPOINT_INFO` and `GET_MEASUREMENT_EXTENSION_LOG` among them, while both programs exit 0. The text fix had a behaviour ([§](#candidate-2s-change)). 2026-10-20: merged by `jyao1` as `f7fa183` ([§](#548-merged-and-3s-change-sent-as-550--2026-10-20))* |
| 3 | `DMTF/spdm-emu` | a slot-0 certificate read whose failure is discarded | `w4-tamper` `t3_cert`: the only trace is `ProvisionedSlotMask` 0x13 → 0x12 | **merged**: sent as [#550](https://github.com/DMTF/spdm-emu/pull/550) on 2026-10-20, after it was asked as issue [#547](https://github.com/DMTF/spdm-emu/issues/547) on 2026-10-19 and the maintainer invited the change; approved by him on 2026-11-06, in its fourth version, and merged on 2026-11-09 as `30f9fc8` and `0e9d60c`, byte-identical ([§](#550-and-libspdm-4300-merged-and-candidates-25-and-28-prepared--2026-11-11)). Until then not sent: sample-code robustness, queued behind ②. *2026-10-04: reported by someone else, [#532](https://github.com/DMTF/spdm-emu/issues/532) (`annamdi`, 2026-10-02), found while deploying the responder and filed with a `--slot_count` question; its author offers the fix. Not sent from here. 2026-10-12: the maintainer proposes deprecating `--slot_count` instead. 2026-10-15: #532 closed by `jyao1`'s #538, which removed `--slot_count`. The shared `res` is unchanged at `8674afe` — `spdm_responder_spdm.c` reads slots 0, 1 and 4 into it, lines 506–557, and tests it once, at 565 — so the issue that reported this row is closed and the defect is not. Whether to raise it again is the author's question; #532's reporter had offered a fix. 2026-10-17: unchanged at `376869f`, and the same shape is at 688–709, for the requester chains the responder provisions for mutual authentication. [#17](https://github.com/DMTF/spdm-emu/issues/17), open since 2021, asks the same of the requester's own reads at a 2021 commit; not re-read against `main`. The fix is a choice — stop, or name the slot and carry on — so a question, later. 2026-10-19: asked as #547, measured at `ce3b513` first: the slot-4 read decides whether any slot is provisioned, and a missing file is reported where a chain that does not verify is not. #17 re-read: its requester half was fixed by `c0f2e43` in 2021, whose message says so, and #17 is still open; and `jyao1`'s `8674afe` gave the requester's own three reads the chained form on 2026-10-14, in the commit that also wrote the responder's reads of the Requester's chains with one shared `res` ([§](#candidate-3s-question)). 2026-10-20: #532's reporter and a second user chose option 2, and `jyao1` invited a patch and asked how it is reproduced without removing a file. Sent as #550, option 2, measured on 48 runs; and answered in #547: a responder with one key and one chain, or with a chain that does not verify, and spdm-emu's own TPM build configured with one responder slot, with nothing removed ([§](#548-merged-and-3s-change-sent-as-550--2026-10-20)). That evening `annamdi` requested a change — read slot 4's chain only in a multi-key connection — which was right; revised as `dcf2cc4` and force-pushed ([§](#550-reviewed-and-changed--2026-10-20)), and approved that evening by `annamdi` at 14:55 UTC and by `giovanni-cf` at 15:02, the two users whose deployments #547 is about, each without a comment; at 15:08 `steven-bellock` removed his own review request, as he had on #524 before `jyao1` merged it. 2026-10-26: not merged; `main` still `f7fa183`, and `jyao1` the one reviewer requested ([§](#550-approved-twice-and-the-corim-round-trip-prepared--2026-10-26)). 2026-10-29: `jyao1` had commented on 2026-10-26, seven minutes after merging #551: slot 0 is a must-have when `CERT_CAP` is set, and its absence should be an error, while the other slots are optional, if the sample library's data agree with them. Revised for the first as `b20e680` on `9cc8b46`, so that the responder exits 1 when slot 0's chain does not load, and answered on the second with measurements: the key pairs keep their association with a slot left empty, on `main` as with the change, which is his libspdm #3638 for the slots a responder leaves empty; two ways to make them agree offered, and his choice asked ([§](#551-merged-550-changed-for-its-maintainer-and-23-asked-as-552--2026-10-29)). 2026-11-02: he chose the first, and asked for four cases on both sides; a fourth version, on both programs, prepared on 2026-11-03 ([§](#550-answered-and-changed-on-both-sides--2026-11-03)). Signed by the author as `3985d32` and `ddb5fd1`, trees unchanged, and sent the same day; its description and reply each gained a clause once libspdm #4268's merge, an hour before, had been read ([§](#libspdm-4268-merged-and-550s-fourth-version-sent--2026-11-03)). 2026-11-06: approved by `jyao1` ([§](#550-approved-and-the-requesters-slot-1-sent-to-libspdm--2026-11-07)). 2026-11-09: merged by him, by rebase, as `30f9fc8` and `0e9d60c`, the trees and the messages the author signed; #547 closed with it ([§](#550-and-libspdm-4300-merged-and-candidates-25-and-28-prepared--2026-11-11))* |
| 4 | `DMTF/spdm-emu` | the requester never checks `VERIF_NO_AUTHORITY` | `t3b_foreign` completes a handshake against a root it was never given | **merged**: sent as [#537](https://github.com/DMTF/spdm-emu/pull/537) on 2026-10-13, after it was asked as issue [#533](https://github.com/DMTF/spdm-emu/issues/533) on 2026-10-03, and merged on 2026-10-15 as `423ba4e`. The library reports it as a warning **by design** — libspdm #1773 and #1774 made it one in 2023, so that the integrator decides — so it went as a question about what a sample should teach, not as a defect. Re-measured on the head first: `0x40020003` returned three times and ignored, and the same 578 messages as with the stock trust anchor. *2026-10-12: `steven-bellock` chose option 1 — a line naming the slot, and carry on — and assigned the issue to `LeonLinAtAMI`, whose #530 changes the same calls. Not sent from here; the issue's reproduction is what this project can offer the change. The same evening the assignee asked for the change itself, on top of #530 and covering every call; sent on 2026-10-13 as #537, after each of the seven calls had been made to print ([§](#candidate-4s-change-sent-as-537--2026-10-13)). 2026-10-15: approved by `jyao1`, who asked for it on `main` rather than on the unapproved #530; rebased as `9fdfdf1` with the same added and removed lines, and every run repeated with the same results ([§](#537-rebased-onto-main-and-the-corim-names-sent-as-542--2026-10-15)); merged by him at 14:07 UTC as `423ba4e`, byte-identical* |
| 5 | `DMTF/spdm-emu` | `command.h` says the socket payload starts at the SPDM header; for MCTP it starts one byte later | any capture here, and `tamper_proxy.py` | **merged**: sent as [#534](https://github.com/DMTF/spdm-emu/pull/534) on 2026-10-03, once #526 had been answered, and merged seven hours later as `13edd65`. Re-measured on four transports first: the comment is right for NONE only — MCTP, the default, puts one byte in front of the SPDM header, PCI_DOE eight and TCP four — so the change says what comes first for each. #408 quoted the comment; #244 asked the question it now answers |
| 6 | `DMTF/spdm-emu` | ① `requirements.txt` has no upper bounds and the ceiling has arrived | a fresh virtualenv, 2026-09-12 | **named in #524's body** as the workaround a reviewer needs; not a change of its own |
| 7 | `DMTF/spdm-emu` | ② `CoRimTool.py verify` has never verified a signature, in two lines that mask each other | re-running the commit's own `Tested:` lines: fixing one line alone makes it accept anything | **merged**, #524, 2026-09-28, as `b015187`, and in the `4.0.0-rc2` tag. Both lines in one change, because the first alone is the more harmful state — measured, not reasoned |
| 8–11 | `DMTF/spdm-emu` | ③ `json_to_cbor` cannot read `cbor_to_json`'s output; ④ `translate_data` hard-codes two names; ⑤ `verify` exits 0 on failure; ⑥ the sample policy does not parse on OPA 1.x | each reproduces with the tool's own sample data | ⑤ **merged**: sent as [#526](https://github.com/DMTF/spdm-emu/pull/526) ([`0003`](0003-corim-exit-status.md)) on 2026-09-29 — #524's description had offered it, and at `eff07cf` a forged signature still exits 0 — and merged on 2026-10-05 as `532f667`. ③ ④ ⑥ not sent and still present at `eff07cf`; three of them need a maintainer's call on which form is canonical. *2026-10-12: all three still present at `8f36665`. ④ needs no call after all: the tables it should consult, `SupportHashAlgMap` and `ComidRoleTypeChoice`, are in the same file. ⑥'s only call is which OPA releases it should still parse on. Both are sendable; ③ is a question first. 2026-10-13: ⑥ prepared, then sent as [#536](https://github.com/DMTF/spdm-emu/pull/536) ([§](#the-sample-policy-on-opa-1x-prepared--2026-10-13)), and merged on 2026-10-13 at 06:45 UTC as `1229103`, byte-identical. 2026-10-15: ④ sent as [#542](https://github.com/DMTF/spdm-emu/pull/542) ([§](#537-rebased-onto-main-and-the-corim-names-sent-as-542--2026-10-15)); ③ unchanged at `8674afe`, `cbor_to_json`'s output still stopping `json_to_cbor` at `KeyError: 'corim'`. 2026-10-16: ④ merged as `5b6e3a7`, byte-identical. 2026-10-17: ③ unchanged; `CoRimTool.py` at `376869f` is the blob tested on 2026-10-15. 2026-10-26: ③ measured at `f7fa183`, where `CoRimTool.py` is still that blob: the two keys `cbor_to_json` wraps the map in, `corim` and `unsigned_corim_map`, are the only asymmetry — with them removed, `json_to_cbor` gives back the sample's 996 bytes — and the shipped policy reads the reference through them, so the call the row was waiting on is made by the files, and the change goes in `json_to_cbor`. Prepared as `baedf75`, +7 and +2 lines, unsigned, and sent the same day as [#551](https://github.com/DMTF/spdm-emu/pull/551), signed as `2ee099d` after the author caught `#6.500` in the message and the body rendering as a link to issue #6 ([§](#sent--2026-10-26-0528-utc)). 2026-10-26: ③ merged by `jyao1` as `9cc8b46`, byte-identical, without a review; read on 2026-10-29 ([§](#551-merged-550-changed-for-its-maintainer-and-23-asked-as-552--2026-10-29))* |
| 12 | `DMTF/spdm-emu` | the sample policy does not check what it appears to check | [`../rats-pipeline.md`](../rats-pipeline.md) §5 | not a defect to report: a design finding, kept where the design is discussed |
| 13 | `DMTF/spdm-emu` | `--req_asym NONE --req_pqc_asym NONE` parses, then makes every handshake impossible | the bisection in `LOG.md`, 2026-09-14; four arms that work in `w7-pqc-ab` | not sent: three possible fixes, and the one that makes the flags mean what they say changes behaviour others may rely on — a conversation, not a patch. *Re-read 2026-09-29: libspdm 4.0.0-rc2 carries the same rule. `490f02c` (2026-09-07) changed when the responder emulator asks for mutual authentication, which is a different thing* |
| 14 | `DMTF/spdm-emu` | ~~`--cap` is parsed by the requester and never read, and echoed as if it were~~ | ~~a `grep` of every reader of the variable~~ | ★ **withdrawn 2026-09-29: it was never true.** The requester has applied `--cap` since `ef556a0` (2022-12-21), and the pinned tree has the two lines that do it. Measured: `--cap CERT,CHAL` on the requester puts `Flags 0x00000006` on the wire where the default puts `0x0002f7c6`. The evidence cell had been a `grep` whose printed output was abbreviated by hand, and the abbreviation is where the requester's line went. See § ⑭ below |
| 15 | `DMTF/spdm-emu` | every invalid argument exits 0 | `grep -c 'exit(0)'` | **merged**: sent as [#546](https://github.com/DMTF/spdm-emu/pull/546) on 2026-10-17, and merged on 2026-10-19 as `ce3b513`, byte-identical, after an approval without a comment. Until then not sent: mechanical, and 78 sites at the pin have become 91 at `eff07cf`. It bit this project's own testing of 0004 twice on 2026-09-29: `--pcap` with `--trans NONE` or `TCP` prints the usage and exits 0. *2026-09-30: all 91 are in `process_args()`, where #527 adds 25 lines and the maintainer's #496 adds 54, so it goes after both. 2026-10-12: 93 at `8f36665`, and the four open pull requests that edit `process_args()` add fifteen more between them. After they land, and as a question first. 2026-10-15: 98 at `8674afe`, every one in `process_args()`; #529 and #531 have merged, and #530 and #496 still edit it. 2026-10-17: 102 at `376869f`, four of them #530's, and #530 has merged; the only open pull request that edits `process_args()` is #496, untouched since 2026-06-27. Prepared as `24849f6` rather than asked first: it is one rule a reviewer can check from the diff, the rule #526 applied to `CoRimTool.py` ([§](#candidate-15s-change)). Signed by the author as `0dd5f75`, tree unchanged, and sent the same evening as #546 ([§](#sent--2026-10-17-1309-utc)). 2026-10-19: merged by `jyao1` as `ce3b513`, byte-identical ([§](#545-and-546-merged-2-sent-and-3-asked--2026-10-19))* |
| 16 | `libspdm`, its sample secret library, which `spdm-emu` builds | no signed operation completes with SLH-DSA on a default build | `w8-pqc-matrix` `S1-*`: bisected to the two signed operations, which the requester refuses. ★ *Corrected 2026-11-02*: it is right to; the responder signs with slot 4's key | **merged**: sent as [libspdm #4268](https://github.com/DMTF/libspdm/pull/4268) on 2026-11-02, and merged on 2026-11-03 as `b068d55`, byte-identical, without a review. Until then not sendable: the root cause needed a Debug build this project had not made, and a report without one asks the maintainer to do the work. *Re-run on 4.0.0-rc2, 2026-09-29: S1 still exits 1, P1 exits 0. 2026-10-15: the status was never unrecoverable. Both signed arms' logs begin `ERROR: do_authentication_via_spdm - 80020001`, `LIBSPDM_STATUS_VERIF_FAIL` — the status the README's Table 1 shows for a measurement or a signature altered in flight — so this row's premise that nothing was printed was false, and it is corrected in § ⑯ and in `../pqc-cost.md`. What a Debug build would add is which check fails. Not re-run at `8674afe`. 2026-11-02: re-run at `9cc8b46`, where it persists, and its cause found without a Debug build. In a connection that is not multi-key the responder signs with KeyPairID 0, and the sample library reads slot 4's private key, `end_responder4.key`, whenever the KeyPairID equals slot 4's; its key pair table has no SLH-DSA key pair, so slot 4's is 0 too, and every SLH-DSA signature is made with slot 4's key and checked against slot 0's certificate. Giving `end_responder4.key` the bytes of `end_responder.key`, and changing nothing else, makes each failing arm it was tried on pass: three parameter sets and both signed operations there, and S1's own run on the build of 2026-09-14. From libspdm #3650, and still on libspdm `main`. The change is small; it is prepared here next, and held until #550 has its maintainer's answer — the same maintainer, and #3650's code ([§](#candidate-16s-cause-found--2026-11-02)). That afternoon prepared, in libspdm on `main` `6de8048`, unsigned, tree `20b1b0c`: KeyPairID 0 selects the default key at all four sites. Both roles' SLH-DSA signatures verify with it on the six parameter sets that reach a signature, and nothing else changes, except that in a multi-key connection, where SLH-DSA has no KeyPairID for any slot, slot 4 now fails where slot 0 used to — in spdm-emu's own default flow, its second session. The commit message and the pull request say so, and offer SLH-DSA key pairs as the way to make slot 4 work. Held for the author's keystrokes, no longer for #550's answer: neither of #550's two ways touches it ([§](#candidate-16s-change-prepared--2026-11-02)). Signed by the author as `d8c077c`, tree unchanged, and sent the same day as libspdm #4268, this project's first pull request there ([§](#candidate-16s-change-sent-as-libspdm-4268--2026-11-02)). 2026-11-03: merged by `jyao1` as `b068d55` on `0f72079`, its diff and message byte-identical; spdm-emu's libspdm, `6cb52f2`, predates it ([§](#libspdm-4268-merged-and-550s-fourth-version-sent--2026-11-03))* |
| 17 | `DMTF/spdm-emu` | `DataTransferSize` has no run-time flag | a 55-line patch, a sweep, and a control that proves it inert | **merged**: sent as [#527](https://github.com/DMTF/spdm-emu/pull/527) ([`0004`](0004-data-transfer-size.md)), rebuilt on 4.0.0-rc2, and merged on 2026-10-12 as `fd75485`. Porting it found two defects in this project's version, neither of which the sweep could reach: with `CHUNK_CAP` cleared it advertised a `MaxSPDMmsgSize` larger than its `DataTransferSize`, which the peer rejects (`0x80010005`, measured on the `pqc-dts` build), and on `--trans NONE` it advertised 128 bytes more than asked. *2026-10-04: reviewed and approved by a contributor, `LeonLinAtAMI`, whose [#531](https://github.com/DMTF/spdm-emu/pull/531) is built on its commit, unchanged* |
| 18 | `DMTF/spdm-emu` | the validator sample's configuration and the suite disagree in both directions | `--audit-config` recomputes the table from the two files | **half fixed upstream**, without this project: `eff07cf`, 2026-09-29, registers both `SUCCESS_13` cases, which were the half that mattered. `CERTIFICATE_SIZE_REQ` is still not registered and `CERTIFICATE_SPDM_X509_CERTIFICATE` is still registered and not implemented — `--audit-config`, 83 implemented, 83 registered. Two lines remain. *2026-10-12: the same two, at `8f36665` with the suite at `7acde98`. Not sent: the maintainer re-syncs this array himself* |
| 19 | `SPDM-Responder-Validator` | a conformance case reports FAIL for a correct signature, because it discarded the chain it fetched | `challenge_verify.py`: calibration 9/9, disputed 2/2 verified | ★ **fixed upstream before this project found it.** `65bcccc` and `ad6db5c`, authored 2026-09-07 and 09-14, on the suite's `main` on 2026-09-15; this row was written on 2026-09-20, against the submodule pointer `c27bb1c`. Not sendable. The fix's own commit message names the mechanism this entry derived, and repairs it the way this entry preferred |
| 20 | `DMTF/spdm-emu` | `--trans NONE` with `CHUNK_CAP` cleared cannot start | unpatched `eff07cf`: the responder exits 1 before listening and prints nothing, where MCTP with the same capabilities completes. `MaxSPDMmsgSize` is computed from a 128-byte transport overhead NONE does not register, so `DataTransferSize` (4,736) exceeds it, and libspdm's context check requires the opposite. Setting the two equal with 0004's flag, and changing nothing else, makes it start | ★ **already reported upstream**: [#358](https://github.com/DMTF/spdm-emu/issues/358), opened 2024-07-28 by `arugan02`, labelled `bug`, open, with the same error text and the same diagnosis. The reporter offered a pull request and a maintainer answered *"that seems reasonable"*; none arrived. Found by the duplicate search before this row was written as a new finding. What this project adds is narrower: re-confirmed on 4.0.0-rc2, and since the maximum message size with chunking became `0x28000` it reproduces only with `CHUNK_CAP` cleared. 0004 is a workaround, not the fix; the fix is one line once 0004's helper exists, and would go as its own change referencing #358. *2026-09-30: #358 is assigned to its reporter, so the first step is a question there, not a pull request. 2026-10-04: [#531](https://github.com/DMTF/spdm-emu/pull/531) changes the default path on `--trans NONE` so that `MaxSPDMmsgSize` follows `DataTransferSize`, which reads as the fix for #358. It does not cite #358, and no build here has checked it. 2026-10-12: #531 has to resolve a conflict with the merged #527 first; after that, one build measures whether it closes #358. 2026-10-13: #531 merged as `c1bdbe0`; that build has not been run. 2026-10-15: it does not reproduce at `8674afe`: the responder with `--trans NONE` and `CHUNK_CAP` cleared starts, and `CAPABILITIES` carries `DataTransferSize` = `MaxSPDMmsgSize` = 4,736; with the requester's `CHUNK_CAP` cleared instead, or both, it exits 0 with no `ERROR:` line. Not bisected to #531. #358 is open, and a line there would be the author's* |
| 21 | `DMTF/spdm-emu` | `spdm_device_attester_sample` cannot connect to the responder it ships with | its `GET_CAPABILITIES`, read off the wire at `eff07cf`, and again on `1229103` under #530, which does not touch the sample: `Flags` `0x000072c6`, no `CHUNK_CAP`, `DataTransferSize` 4,608, `MaxSPDMmsgSize` 163,840. libspdm requires the two sizes to be equal without `CHUNK_CAP` (`libspdm_rsp_capabilities.c` 239–244 at `a6994ee`), so the responder answers `ERROR(InvalidRequest)`, `libspdm_init_connection` returns `0x8001000a`, and the program exits 0 | **merged**: sent as [#545](https://github.com/DMTF/spdm-emu/pull/545) on 2026-10-17, and merged on 2026-10-19 as `ad6095f`, byte-identical, without a review. Until then not sent. Found on 2026-10-13 while testing #537, whose attester half had to be run with a local patch because of it. Before #531 no option got past it: the sample never sets the SPDM version, so `--ver` changes nothing (measured from 1.0 to 1.4), and `process_args()` accepts `--cap` only from the requester and the responder. Since #531, `--max_spdm_msg_size 4608` does: the request then carries 4,608 twice, and the sample collects its chains and its measurement — measured, and found only when this row's first wording, "no command line gets past it", was audited. The sample also passes `chunk_cap = true` to #531's size helpers without setting `CHUNK_CAP`, so by the rule above one word or one flag would fix the default — inferred, not built. A question first, because which of the two is upstream's call. *2026-10-15: unchanged at `8674afe`: the same request, `0x000072c6` with 4,608 and 163,840, the same `ERROR(InvalidRequest)`, and `--max_spdm_msg_size 4608` still gets it through. 2026-10-17: unchanged at `376869f`, on MCTP, PCI_DOE and NONE. And not new: [#458](https://github.com/DMTF/spdm-emu/issues/458), opened 2025-12-16, asked whether the attester and validator samples needed the fix `5ef1123` had made to the requester and the responder, and was closed when its reporter confirmed the validator's case gone; [`0004`](0004-data-transfer-size.md) had recorded that as no longer reproducing, for both. `5ef1123` is upstream's answer to the question this row asked, so it was prepared as a change, `0bd516a` ([§](#candidate-21s-change)). Signed by the author as `afa4bb1`, tree unchanged, and sent the same evening as #545 ([§](#sent--2026-10-17-1309-utc)). 2026-10-19: merged by `jyao1` as `ad6095f`, byte-identical ([§](#545-and-546-merged-2-sent-and-3-asked--2026-10-19))* |
| 22 | `DMTF/spdm-emu` | `spdm_requester_emu` built for a TPM responder with one slot cannot start | `DEVICE=tpm` with `LIBSPDM_TPM_RESPONDER_SLOT_IDS=0`, at `f7fa183`: *"unsupported slot_id 1 (supported mask: 0x1)"*, then *"read_responder_root_public_certificate fail!"*, and exit 1 after six messages. Once the algorithms are negotiated, the requester reads the responder's roots for slots 0 and 1 (`spdm_requester_spdm.c` 600–663) and stops if either read fails | **merged**, in #550: sent on 2026-11-03 in its fourth version's second commit, and merged on 2026-11-09 as `0e9d60c` ([§](#550-and-libspdm-4300-merged-and-candidates-25-and-28-prepared--2026-11-11)). Until then recorded, not sent: found on 2026-10-20 while testing #550, whose one-slot TPM runs had to use the requester of the default TPM build. Candidate 3's assumption, from the requester's side. After #550 has an answer ([§](#candidate-22-found-while-testing-it)). *2026-10-29: still reproduces at `9cc8b46`. Held for `jyao1`'s choice on #550: with the first of the two ways its reply offers, a responder with one TPM slot is a consistent configuration, and this is how its requester then fails; with the second, that responder stops by itself ([§](#551-merged-550-changed-for-its-maintainer-and-23-asked-as-552--2026-10-29)). 2026-11-02: he chose the first, so on 2026-11-03 the change went into #550's fourth version, prepared, in which the requester needs only slot 0's root; measured with the requester built for one responder slot, as above, which then completes ([§](#550-answered-and-changed-on-both-sides--2026-11-03)). Sent in it the same day, signed by the author ([§](#libspdm-4268-merged-and-550s-fourth-version-sent--2026-11-03))* |
| 23 | `DMTF/spdm-emu` | with RSA-2048, the requester's `SET_KEY_PAIR_INFO` step erases the key pair the connection uses | at `9cc8b46`, unmodified binaries, `--asym RSASSA_2048` given to both programs, nothing removed: no session opens — `KEY_EXCHANGE` gets `ERROR(InvalidRequest)` — in 570 messages, and the requester prints `ERROR: libspdm_start_session - 8001000a` and exits 0; with the step left out of `--exe_conn` and `--exe_session`, 2,256 messages, the sequence of `RSASSA_3072` with the same options. `do_set_key_pair_info_via_spdm()` (`spdm_requester_key_pair_info.c` 86–111, `d667dbe`, 2024) always sets KeyPairID 1's association to none and then erases it, and KeyPairID 1 is the sample library's RSA-2048 primary key pair, which backs slots 0 and 1 | **asked**: issue [#552](https://github.com/DMTF/spdm-emu/issues/552) on 2026-10-29, as a question, since the flow could pick a key pair the connection does not use in more than one way. Found that day in #550's runs for `jyao1`'s second comment, twelve of which used RSA-2048 so that KeyPairID 1, the one the requester asks about, would be the key pair in use: none of the twelve opened a session, and #550's reply says so ([§](#551-merged-550-changed-for-its-maintainer-and-23-asked-as-552--2026-10-29)) |
| 24 | `libspdm` | six of the twelve SLH-DSA parameter sets the sample ships never get past `GET_DIGESTS` | at `9cc8b46`, `--pqc_asym` `SLH_DSA_SHA2_192F`, `SHA2_256S`, `SHA2_256F` or their SHAKE twins, with `DIGEST,CERT,CHAL`: after eight messages `GET_DIGESTS` gets a four-byte `ERROR`, the requester prints `ERROR: do_authentication_via_spdm - 8001000a`, and the responder prints nothing but its arguments and its shutdown. Their slot-0 chains hold 90,634 to 150,832 bytes of certificates (SHA2 and SHAKE measured); the largest that works, SHAKE-128f's, holds 52,432 | **cause read, not sent**: found on 2026-11-02 while sweeping candidate 16 across every parameter set ([§](#candidate-16s-cause-found--2026-11-02)). *That afternoon its cause was read: the sample's chain readers call `libspdm_verify_cert_chain_data()` (`read_pub_cert_pqc.c` 524, 1118, 1268 and 1471), which first refuses chain data longer than `0xFFFF - (4 + LIBSPDM_MAX_HASH_SIZE)` bytes (`libspdm_crypt_cert.c` 1891–1897), 65,467 with SHA-512 built in. Given one of these chains as its own, the requester prints `read_requester_public_certificate_chain fail!`; the responder prints nothing. libspdm's own `GET_CERTIFICATE` handler takes a longer chain when SPDM 1.4's large certificate chain is in use (`libspdm_rsp_certificate.c` 149). Read, not instrumented; whether the sample should accept these is libspdm's question, after 16 ([§](#candidate-16s-change-prepared--2026-11-02))* |
| 25 | `DMTF/spdm-emu` | `spdm_requester_emu` exits 0 after any failure that follows its `GET_ENDPOINT_INFO` step | at `9cc8b46` with candidate 16's change, the default flow with `--pqc_asym SLH_DSA_SHA2_128S`, and `--pqc_first TRUE` on the responder: the second session, on slot 4, fails (`ERROR: libspdm_start_session - 80020001`) and the requester exits 0; the same run with `EP_INFO` left out of the default `--exe_conn` exits 1. Line 204 stores the result of the platform call for the encapsulated `GET_ENDPOINT_INFO` in `result`, which line 147 set to false and `main` returns negated, so every later `goto done` exits 0. From `8e33385`, 2025-06-06 | **sent** as [#553](https://github.com/DMTF/spdm-emu/pull/553) on 2026-11-11, with libspdm #4312 and #4313 named for the four jobs it turns red ([§](#28-and-25-sent-and-28s-fixes-corrected--2026-11-11)). Found on 2026-11-02 while running spdm-emu's own PQC command for candidate 16 ([§](#candidate-16s-change-prepared--2026-11-02)). The default flow runs that step from SPDM 1.3 on, so a failure after it does not reach the exit status upstream's workflows see. One line; after 16 and #550. *2026-11-11: both merged. Unchanged at `0e9d60c`, and not a design question: #290, for #265, made the requester exit 1 when its flow fails, and changed the `SHUTDOWN` call at `done:` so that it could not overwrite `result`; `8e33385` put that shape back. Prepared as `6726982` on `0e9d60c`, the call tested directly, +4 −5; on `main` #552's failure and a key mismatch on slot 4 each exit 0, and with the change 1, with the same messages ([§](#550-and-libspdm-4300-merged-and-candidates-25-and-28-prepared--2026-11-11))* |
| 26 | `DMTF/spdm-emu` | on one responder, a `--ver 1.2` connection after an SPDM 1.4 multi-key one fails its second session | at `9cc8b46`, unmodified binaries, nothing removed: the first requester with `--exe_mode CONTINUE` and the default flow, the second with `--ver 1.2`, on the same responder process: the second's `CHALLENGE` and first session complete, then `libspdm_start_session - 80020001` (`LIBSPDM_STATUS_VERIF_FAIL`). Two `--ver 1.2` connections in turn both complete. The same with #550's fourth version | **recorded, not sent**: found on 2026-11-03 as the control for #550's give-back, which is therefore shown with a second connection at 1.4 without multi-key instead ([§](#550-answered-and-changed-on-both-sides--2026-11-03)). Cause not read |
| 27 | `DMTF/libspdm` | the sample library reads the Requester's slot 1 from slot 0's file | `libspdm_read_requester_public_certificate_chain_per_slot()` and its PQC twin, in `read_pub_cert.c` and `read_pub_cert_pqc.c` at `6cb52f2`, and still at libspdm `main` `c2b2573`, give slot 4 `bundle_requester.certchain4.der` and every other slot `bundle_requester.certchain.der`; `bundle_requester.certchain1.der` is generated and read by nothing, while the Responder's readers give slot 1 `bundle_responder.certchain1.der` | **merged**: sent as libspdm issue [#4299](https://github.com/DMTF/libspdm/issues/4299) and its fix, [#4300](https://github.com/DMTF/libspdm/pull/4300), on 2026-11-07, after #550's maintainer, asked in the reply, called it a bug and asked for both ([§](#550-approved-and-the-requesters-slot-1-sent-to-libspdm--2026-11-07)); merged on 2026-11-09 as `306502a`, byte-identical, and #4299 closed by it ([§](#550-and-libspdm-4300-merged-and-candidates-25-and-28-prepared--2026-11-11)). Found on 2026-11-03 when removing that file changed nothing; #550's runs for the Requester's slot 1 used a local change that reads it ([§](#550-answered-and-changed-on-both-sides--2026-11-03)) |
| 28 | `DMTF/libspdm` | with `RECORD_TRANSCRIPT_DATA_SUPPORT`, the Requester signs `FINISH` over a transcript that holds its own slot's Responder chain | in spdm-emu `0e9d60c`, the Requester built with `LIBSPDM_RECORD_TRANSCRIPT_DATA_SUPPORT=1`, the default flow: the second `KEY_EXCHANGE` session, on slot 4 with mutual authentication and `ReqSlotIDParam` 0, has its `FINISH` answered `ERROR(DecryptError)`, `0x8001000f`, against a Responder built either way; slot 0's session passes, and slot 4's passes without mutual authentication. `libspdm_generate_finish_req_signature()` looks the chain up with its `slot_id` parameter, which is `req_slot_id_param`, the Requester's slot, since `13db5117` (2025-10-29) removed the line that had set it to the Responder's; the two HMAC functions in `libspdm_req_finish.c` use `session_info->peer_used_cert_chain_slot_id`, since libspdm #3435 (`0f0e189`, 2025-12-19). The file is one blob at `6cb52f2` and at `main` `839bc24`. With that one line added, as they have it, every case passes | **approved**: sent as libspdm issue [#4312](https://github.com/DMTF/libspdm/issues/4312) and its fix, [#4313](https://github.com/DMTF/libspdm/pull/4313), on 2026-11-11, and approved by `steven-bellock` within the hour; the commit's `Fixes:` changed from `0f0e189` to `13db5117` at his comment ([§](#28-and-25-sent-and-28s-fixes-corrected--2026-11-11)). Found on 2026-11-11 in spdm-emu's own CI log, while confirming what candidate 25 hides. The `Test_RECORD_TRANSCRIPT_DATA_consistent` step's second run, a Requester built with the option against a Responder built without it, prints the error in each of the 109 runs of the four jobs that have it that got that far, from 2026-08-17, the oldest log GitHub still serves, and passes because of 25 ([§](#550-and-libspdm-4300-merged-and-candidates-25-and-28-prepared--2026-11-11)) |

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

> ★ *Corrected 2026-11-02.* "Not signing" and "what is left is SPDM-signature
> verification on the requester" were both wrong. The responder signs with the
> wrong key: in a connection that is not multi-key, as S1's is, the sample
> library reads slot 4's private key, `end_responder4.key`, for every SLH-DSA
> parameter set, and the requester, verifying against slot 0's certificate,
> refuses the signature correctly. A signature made with another key of the
> same parameter set has the same size; the length above was never evidence of
> the right key. Found by giving `end_responder4.key` the bytes of
> `end_responder.key`, and changing nothing else: S1's own run then
> completes on this build, and so does each arm it was tried on at
> `9cc8b46`, three parameter sets and both signed operations
> ([§](#candidate-16s-cause-found--2026-11-02)).

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

## #542 merged, and two more prepared — 2026-10-17

Read from 08:58 UTC. Since 2026-10-15: #542 merged, and so had #530, which two
rows of the candidate table had been waiting for. The author asked which two
candidates were best sent now, and delegated the choice.

### What came back

`jyao1` merged #542 at 02:04:36 UTC on 2026-10-16, by rebase, as `5b6e3a7` on
`423ba4e`, with no review and no comment: the 1,535-byte message and the blob
of `CoRimTool.py`, `08a4e885`, are identical to `0bdb70b`, the author's. All
seven pull requests this project had sent to `DMTF/spdm-emu` were merged; two
more went that evening ([§](#sent--2026-10-17-1309-utc)).
Nineteen seconds later `steven-bellock`'s #544 landed, folding the VS2015,
VS2019 and VS2022 toolchains into one, and ten minutes after that #530,
`LeonLinAtAMI`'s `--cert_buf` and `--cert_block_len`, as `376869f`. That is
`main`; its libspdm is still `1d98f73`. The open pull requests are #496, last
touched on 2026-06-27, and #490, a rewording of the README.

### Every unsent row, at `376869f`

- **21** reproduces on MCTP and PCI_DOE — `Flags` `0x000072c6`,
  `DataTransferSize` 4,608, `MaxSPDMmsgSize` 163,840, `ERROR(InvalidRequest)`,
  `libspdm_init_connection - 0x8001000a`, exit status 0 — and on NONE, whose log
  shows the same status. And it is not new.
  [#458](https://github.com/DMTF/spdm-emu/issues/458), opened 2025-12-16, says
  that `18e49ea`, *"Adjust MaxSPDMMsgSize based on CHUNK_CAP"*, fixed the
  requester and the responder, and asks whether the attester and validator
  samples were missed. Its reporter ran the validator sample, confirmed the
  case gone on 2026-08-28, and the issue was closed; nobody answered for the
  attester. [`0004`](0004-data-transfer-size.md) §4 had found #458 on
  2026-09-29 and recorded it as closed *"as no longer reproducing"*, for both
  samples, which the issue does not say, and is corrected there; candidate 21
  was then written up on 2026-10-13 as new.
- The history explains when it broke. `18e49ea` landed as `5ef1123`, in #428,
  whose `97aeeed` raised `LIBSPDM_MAX_SPDM_MSG_SIZE` from `0x1200` — the same
  as `DataTransferSize` — to `0x28000` in builds with SLH-DSA, as the default
  build is, and `0x8000` with ML-DSA alone. Before #428 the attester's two
  sizes were equal; it broke in the pull request that fixed its siblings.
  Read from the commits, not built at the older one.
- **15**: 102 `exit(0)` at `376869f`, all in `process_args()`, one of them after
  `-h`/`--help`; #530 added four. The count was 78 at the pin, 91 at `eff07cf`,
  93 at `8f36665` and 98 at `8674afe`: every new option copies the idiom. With
  #530 merged, the only open pull request that edits `process_args()` is #496.
- **2**: unchanged. The requester's defaults set `CHUNK` and `EP_INFO_SIG` and
  the responder's also `MEL`, and neither `By default` line in `print_usage()`
  names them.
- **3**: unchanged: `spdm_responder_spdm.c` 506–557 reads slots 0, 1 and 4 into
  one `res` and tests it once, at 565. The same shape is at 688–709, for the
  requester chains the responder provisions for mutual authentication. The
  search found [#17](https://github.com/DMTF/spdm-emu/issues/17), open since
  2021, asking the same of the requester's own reads at a 2021 commit; not
  re-read against `main`.
- **③**: `CoRimTool.py` at `376869f` is the blob tested on 2026-10-15, which
  stops at `KeyError: 'corim'` on `cbor_to_json`'s output. 13, 16 and 20 were
  not re-run.

### What was chosen, and why

The criteria are the ones at the top of this file, and today two more decided
it: whether the decision a change needs has already been made, and whether
the code it edits is quiet now.

| row | send now? | because |
|:-:|---|---|
| 21 | **yes, as a pull request** | the shipped sample cannot do the one thing it is for; upstream made the design call in `5ef1123` for the requester and the responder, and #458 asked for it here, so nothing is left to ask; +22 −20, fifteen of them the flags, moved unchanged |
| 15 | **yes, as a pull request** | no open pull request edits `process_args()` but #496; the change is one rule a reviewer can check from the diff; the requester and the responder already exit 1 when they fail after parsing; #526 applied the same rule to `CoRimTool.py` and was merged; and the defect grows with every option |
| 2 | not now | correct, and two lines; a third pull request the same day spends attention for little, and it does not go stale |
| 3 | not now | the fix is a choice — stop, or say which slot and carry on — and #532, which reported it, was closed two days ago by the maintainer's own change; a question later, with #17 |
| ③ | not now | which JSON form is canonical is the maintainer's call; a question first |
| 13, 16 | not now | a conversation; a Debug build |

For 21 the change derives `chunk_cap` from the flags, as `spdm_requester_spdm.c`
does, rather than adding `CHUNK_CAP` to them. Adding it should also let the
sample connect — inferred, not built — and would change the capabilities the
sample advertises, which is its author's choice; following the flags changes
only the sizes, and is what `5ef1123` did.

### Candidate 21's change

*attester: base MaxSPDMmsgSize on CHUNK_CAP*, `0bd516a` on `376869f`, +22 −20
in `spdm_device_attester_spdm.c`: the capability flags are set before the sizes
that depend on them, `chunk_cap` is derived from them, and it is passed to
`spdm_emu_get_max_spdm_msg_size()` and `spdm_emu_get_sender_buffer_size()`
instead of `true`. The fifteen lines of flags move unchanged.

Tested with a Release build of `376869f` against one of the commit, against
the same unmodified responder:

| attester | `main` | the change |
|---|---|---|
| defaults | `DataTransferSize` 4,608, `MaxSPDMmsgSize` 163,840, `InvalidRequest` | 4,608 and 4,608; chains of slots 0, 1 and 4 (1,655, 1,658 and 1,660 bytes) and a 528-byte measurement |
| `--trans PCI_DOE` | the same `InvalidRequest` | the same files |
| responder `--cap` without `CHUNK` | the same `InvalidRequest` | the same files; `CAPABILITIES` 4,608 and 4,608 |
| `--data_transfer_size 2048` | 2,048 and 163,840, `InvalidRequest` | 2,048 and 2,048; the same files |
| `--max_spdm_msg_size 4608` | 4,608 and 4,608; the files | the same files |
| `--max_spdm_msg_size 8192` | `InvalidRequest` | refused before `GET_VERSION`: *"must equal DataTransferSize (4608) without CHUNK_CAP"* |
| `--trans NONE` | `0x8001000a` | connects, saves slot 0's chain, then `libspdm_start_session` `0x80040001` |

"The same files" is byte for byte, against what `main` saves with
`--max_spdm_msg_size 4608`. NONE carries no secured messages —
`spdm_transport_none_decode_message()` always reports no session — and
`spdm_requester_emu` skips the session there; the change does not touch that.
The other three programs build byte-identical.

### Candidate 15's change

*spdm_emu: exit 1 on an invalid argument*, `24849f6` on `376869f`: 101 of the
102 `exit(0);` in `process_args()` become `exit(1);`, and `git diff
--word-diff` shows nothing else. The one left is the one after `-h`/`--help`.

Tested on all four programs that call `process_args()`, against `main`, and
against a third, throwaway build in which exit *k* returns *k* + 1, so that each
case names the exit it reached. The inputs: each of the 52 option names
`process_args()` matches, alone and with the value `__bogus__`; an unknown
option, and `--slot_count`, which #538 removed; the cross-option and `--pcap`
checks; and `--iface` with an empty and with an overlong name — 492 cases:

| cases | `main` | the change | throwaway build |
|---|---|---|---|
| 431 rejected | 0 | 1, the same output | 99 distinct exits of the 101 |
| 45 accepted: a value the option takes as given, such as `--ip __bogus__`, a flag, or a valid combination | the same as the change | the same as `main` | the same |
| 16 `-h` and `--help`, alone and with a value | 0 | 0 | 0 |

The two exits no case reaches are an `#ifdef _MSC_VER` branch, which Linux does
not compile, and a failed allocation of the send/receive buffer. The command
lines in `.github/workflows` that run on Linux — eleven pairs, a responder with
the requester or the validator sample — were run on both builds, with the same
exit statuses, all 0, and the same number of messages in each pair, from 20 to
3,027, and no usage text and no `ERROR:` line in any of them.

### What the hours before the sign-off found

- This project's own run harness reported exit status 0 for both programs on
  `--trans NONE`, with logs of 177 and 176 lines: it had passed `--pcap`, which
  has no link type for NONE, so both had printed the usage and exited 0 —
  candidate 15, the third time it has bitten this project's testing. The
  harness now flags the usage and leaves `--pcap` off on NONE and TCP.
- The script that applied 15 refused `spdm_emu.c` for its non-ASCII bytes,
  three `§` in comments upstream wrote; it now keeps the bytes it does not edit.
  Neither change adds a non-ASCII byte.
- The throwaway build found one exit no case reached: `--iface` rejects only an
  empty or overlong name, and `__bogus__` is neither. Two cases were added.
- Two sentences of the drafts were false and were rewritten before anything was
  signed: *"refused before connecting"*, where the socket had connected and no
  SPDM message had been sent, and *"prints the usage … for everything it
  rejects"*, which two exits do not.

### What is left, and whose

The author's, for each of the two, after the freshness checks are repeated:
review the commit (`git --no-pager show` in `~/spdm-lab/work/spdm-emu-attester`
and `~/spdm-lab/work/spdm-emu-exit`, a worktree each), sign it with `git commit
--amend -s --no-edit` — the tree must not change — run
`harness/check_upstream_commit.sh` on the worktree, push the branch to the
fork, and open the pull request with the commit's subject as its title and
`~/spdm-lab/work/<branch>.pr-body.md` as its body, unedited. The branches are
`attester-chunk-cap` and `invalid-arg-exit-status`.

### Sent — 2026-10-17, 13:09 UTC

| | 21 | 15 |
|---|---|---|
| URL | <https://github.com/DMTF/spdm-emu/pull/545> | <https://github.com/DMTF/spdm-emu/pull/546> |
| Opened | 13:09:10 UTC by the author, from `Jhongwe1:attester-chunk-cap` | 13:09:16 UTC by the author, from `Jhongwe1:invalid-arg-exit-status` |
| Title and body | the commit's subject; the body byte-identical to the reviewed file, 1,305 bytes, read back from the API | the same; 1,388 bytes |
| Commit | **`afa4bb1`** on `376869f`, signed by the author at 12:47 UTC: tree `ba9a379`, the bytes tested, and the reviewed message with one line added, the sign-off; `check_upstream_commit.sh` satisfied | **`0dd5f75`** on `376869f`, signed at 12:47 UTC: tree `024b536`, the bytes tested; the same |
| Diff | one file, +22 −20 | one file, +101 −101 |
| Before opening | read at 12:49 and 13:03 UTC: `main` still `376869f`, nothing opened or updated upstream since 09:00 UTC, the fork's branch at the signed commit, and no pull request from it yet | the same |
| Reviewers | `jyao1` and `steven-bellock`, added by CODEOWNERS | the same |
| Checks | DCO success; **45 of 45** check runs success, all eighteen VS builds among them, the last at 13:32:08 UTC; `mergeable_state` clean. Read from the API | the same, the last at 13:33:07 UTC |
| Outcome | in review: no review and no comment at 13:34 UTC | the same |

### What decides what goes next

- #545 and #546: review. A comment that comes back is read here first, and
  the reply is the author's.
- 2: after these. 3 and ③: questions. 13: a conversation. 16: a Debug build.
- 94773: re-read on or after 2026-10-19.

## #545 and #546 merged, 2 sent and 3 asked — 2026-10-19

Read from 12:00 UTC. Both pull requests of 2026-10-17 had merged overnight. The
author asked for the next two of the candidates still open, and delegated the
choice.

### What came back

`jyao1` merged #545 at 01:50:47 UTC and #546 at 01:51:10 UTC, by rebase, as
`ad6095f` and `ce3b513` on `376869f`: their trees, patch-ids and messages are
identical to `afa4bb1` and `0dd5f75`, the author's. #546 carried
`steven-bellock`'s approval of 2026-10-17, 14:13 UTC, which had no comment;
#545 had no review. All nine pull requests this project has sent to
`DMTF/spdm-emu` are merged. `main` is `ce3b513`, and the open pull requests are
still #496 and #490.

### What was chosen, and why

| row | sent as | because |
|:-:|---|---|
| 2 | **a pull request** | it had waited for #545 and #546, which have merged; the decision it needs is made, since the help text has to say what `key.c` sets; and #496, the only open pull request that edits `print_usage()`, does not touch its two lines |
| 3 | **an issue** | users have met it, #532's reporter while deploying the responder on a BMC; the fix is a choice between two behaviours, which is the maintainers'; and #532's reporter offered to write it, so the question names them rather than taking it |
| ③ | not now | which JSON form is canonical is the maintainer's call |
| 13 | not now | a policy question |
| 16 | not now | a Debug build first |

### Candidate 2's change

*spdm_emu: complete the --cap defaults in --help*, `49dc663` on `ce3b513`,
+2 −2 in `spdm_emu.c`: the Requester's `By default` line of `--cap` gains
`CHUNK` and `EP_INFO_SIG`, and the Responder's `MEL`, `CHUNK` and `EP_INFO_SIG`,
in the order `key.c` sets them. Every other `By default` line of
`print_usage()` was read against its variable's initial value, and is right.

Tested with Release builds of `ce3b513` and of the change, over MCTP, each
program's own `--help` list passed back as `--cap`:

| | no `--cap` | `main`'s list | the change's list |
|---|---|---|---|
| Requester `Flags` | `0x8882f7c6` | `0x8800f7c6` | `0x8882f7c6` |
| Responder `Flags` | `0xb99afbf7` | `0xb818fbf7` | `0xb99afbf7` |
| `MaxSPDMmsgSize`, both | 163,840 | 4,608 | 163,840 |
| messages | 2,272 | 2,240 | 2,272, in the same order |
| exit statuses | 0 and 0 | 0 and 0 | 0 and 0 |

The 32 messages `main`'s list loses are eight in the clear —
`GET_ENDPOINT_INFO`, `GET_MEASUREMENT_EXTENSION_LOG`, their responses and one
encapsulated exchange — and 24 secured ones. `--help` differs from `main`'s in
these two lines only.

### Candidate 3's question

At `ce3b513`, `spdm_server_connection_state_callback()` reads the chains of
slots 0, 1 and 4 into one `res` and tests it once (`spdm_responder_spdm.c`
504–565), and the Requester's chains, which it reads when it needs the
Requester's public key, have the same shape (685–709). Run with
`spdm_requester_emu`'s defaults against a responder whose copy of `build/bin`
had one file removed or altered:

| the responder's copy | the responder prints | `ProvisionedSlotMask` | the requester |
|---|---|---|---|
| unchanged | nothing about the files | `0x13` | exit 0, 2,272 messages |
| slot 4's chain removed | `Unable to open file` and its name | none: `GET_DIGESTS` gets `ERROR(Unspecified)` | exit 1, `8001000a` |
| slot 1's chain removed | the same | `0x11` | exit 0, the same 2,272 messages in the same order |
| slot 0's chain removed | the same | `0x12` | exit 1: `GET_CERTIFICATE` for slot 0 gets `ERROR(InvalidRequest)` |
| slot 0's chain, one bit of the intermediate certificate's signature flipped | nothing | `0x12` | exit 1, the same messages as the row above |
| slot 4's chain, the same | nothing | none | exit 1, the same messages as slot 4's removed |
| the Requester's slot-4 chain removed | `Unable to open file` and its name | `0x13` | exit 0, after `libspdm_get_endpoint_info - 8001000a` four times |
| for contrast, the Requester's slot-4 chain removed from the requester's own copy | nothing | — | exit 1 after `ALGORITHMS`: `read_requester_public_certificate_chain fail!` |

The requester's own reads of the same three slots were rewritten by `jyao1` in
`8674afe` on 2026-10-14, chained with `if (res)` so that a failure stops it;
the same commit wrote the responder's reads of the Requester's chains, 685–709,
with one shared `res`. The requester has stopped on a failed read since
`c0f2e43`, 2021, whose message says it fixes #17; #17 is still open. The issue
asks which of two behaviours the maintainers want for the responder — #532's
proposal, chaining the reads so that one failure provisions nothing, or
provisioning each slot whose chain loaded and naming the ones that did not —
and leaves the change to #532's reporter if they want it.

### What the hours before sending found

- ★ **This project's own tool.** The line-ending strip run on the session's
  scripts, `sed -i 's/\r$//'` typed through PowerShell into `wsl.exe`, reached
  sed as `s/r$//` and removed a trailing `r` from every line:
  `bundle_responder.certchain4.der` became `.de`. The run stopped on its first
  case, because each case asserts that the file it removes exists, and the strip
  had never been needed: the files had no CR in them. Every earlier script that
  went through it was read line by line, and none had a line ending in `r`; the
  upstream diff had been checked against its bytes before.
- **A sentence of #532's, measured before it was repeated.** #532 says no log
  line points at the missing file. The responder prints `Unable to open file`
  with the file's name, and has since `56eb4b2`, 2021; the silent case is a
  chain that opens and does not verify, the one this project's `t3_cert` met on
  2026-09-10. The issue reports what was measured, and does not repeat the
  sentence.
- **Three sentences of the issue's draft**, false or short, were rewritten
  before it was opened: "the last paragraph of #532", which is the one before
  it; "these lines did not change", when #538 did edit the file, elsewhere, and
  `git blame` dates 504–565 to `e0abd5e`; and "the difference is the slot-1
  row", when the slot-4 row differs as well.
- **Candidate 2's row had called it a text fix** since 2026-08-17. Passing the
  documented list back as `--cap` costs 32 messages, and both programs exit 0:
  the text has a behaviour, measured for the first time today.

### Sent — 2026-10-19, 12:49 UTC

| | 2 | 3 |
|---|---|---|
| URL | <https://github.com/DMTF/spdm-emu/pull/548> | <https://github.com/DMTF/spdm-emu/issues/547> |
| Opened | 12:50:04 UTC by the author, from `Jhongwe1:help-default-caps`, on a page pre-filled from the reviewed files: each URL was decoded back and compared with them before it was opened | 12:49:57 UTC by the author, the same way |
| Title and body | the commit's subject; the body byte-identical to the reviewed file, 977 bytes, read back from the API | byte-identical to the reviewed files; the body 3,950 bytes |
| Commit | **`aecb922`** on `ce3b513`, signed by the author: tree `52f751e`, the bytes tested, and the reviewed message with one line added, the sign-off; `check_upstream_commit.sh` satisfied. Pushed to the fork at 12:48 UTC on the author's instruction | — |
| Before opening | read at 12:37 and 12:43 UTC: `main` still `ce3b513`, nothing opened or updated upstream since the merges, no duplicate found, the fork's branch absent | the same |
| Reviewers | `jyao1` and `steven-bellock`, added by CODEOWNERS | — |
| Checks | DCO success; **45 of 45** check runs success, all eighteen VS builds among them, the last at 13:13:12 UTC; `mergeable_state` clean. Read from the API | — |
| Outcome | in review: no review and no comment at 13:53 UTC | open: no comment, label or assignee at 13:53 UTC |

### What decides what goes next

- #548: review. #547: an answer, and whether #532's reporter takes the change.
  A comment that comes back is read here first, and the reply is the author's.
- ③: a question. 13: a conversation. 16: a Debug build.
- 94773: unchanged since 2026-09-23; the week the author chose to wait on
  2026-10-12 has passed, and what happens next is his.

## #548 merged, and 3's change sent as #550 — 2026-10-20

Read from 07:36 UTC. #548 had merged overnight, and #547 had had five
comments since the record of 2026-10-19 was written, the last of them the
maintainer's. The author asked what #547 now needed and for the candidate best
sent now, and delegated the choice.

### What came back

`jyao1` merged #548 at 02:40:26 UTC, by rebase, as `f7fa183`, with the
patch-id (`7d805a68395d`) and the message of `aecb922`, the author's, and no
review or comment. It landed on `897f13e`, not on `ce3b513`: at 21:51 UTC the
day before, `steven-bellock`'s #549 had moved libspdm and
`SPDM-Responder-Validator` to their `4.0.0-rc3` tags — libspdm `6cb52f2`,
whose OpenSSL submodule moved to `45e844f`. All ten pull requests this project
has sent to `DMTF/spdm-emu` are merged.

#547, on 2026-10-19, after the record was written (UTC):

| time | who | what |
|---|---|---|
| 14:24 | `annamdi`, #532's reporter | leans to option 2: *"a failed certificate read on one slot should not prevent successfully loaded slots from being provisioned"* |
| 14:43, edited 14:52 | `jyao1` | asks why one would remove slot 4's file, doubts the emulator is meant to be that robust, and asks whether it should still work with every certificate removed |
| 14:57 | the author | removing the file is the shortest reproduction; the case behind it is #532's; and with `--ver 1.2`, where slot 4 is never used, a missing slot-4 file still makes `GET_DIGESTS` fail |
| 15:14 | `giovanni-cf` | *"I agree with Nnamdi, as option 2 is better for our usage"* |
| 15:28 | `jyao1` | *"First, I do not mind to fix. Feel free to submit patch if you want."* Then: with the emulator's requester slot 4 is used by default, so why would the file be missing, and how is it reproduced without removing it? |

Nothing more by 2026-10-20 08:52 UTC, and `annamdi`'s fork had last been
pushed on 2026-09-29.

### What was chosen, and why

The maintainer had invited the change; both users who answered had chosen
option 2; and #532's reporter, who had offered a fix on 2026-10-02, had
answered the issue without taking it, after the issue had said it was happy
to leave the change to them or to send either. ③, 13 and 16 are where
2026-10-19 left them: a maintainer's call, a conversation, a Debug build. So
candidate 3 went as option 2, crediting the two users and asking them to check
it, and `jyao1`'s question was answered in #547, not left to the pull request.

### Candidate 3's change

*spdm_responder_emu: provision each slot that loads*, `8c43299` on `f7fa183`,
+24 −11 in `spdm_responder_spdm.c`. One result per read — `res`, `res1` and
`res4`, beside `data`, `data1` and `data4`; a line for each slot whose chain
did not load, `Slot N: certificate chain not loaded, not provisioned`, with
`EMU_INFO`, as #537 used for a notice the flow carries on from; provisioning
when any chain loaded; and each slot given its chain only when its own read
succeeded. The last part is not caution for its own sake: every chain reader
in libspdm's sample library sets `*data` to `NULL` before anything can fail,
but the TPM library's `libspdm_read_responder_public_certificate_chain_per_slot()`
returns false for a slot it is not configured for without writing `*data` —
in the callback, an uninitialised local. The Requester's chains, read further
down, also into the one `res`, are left as they are: there `res` also decides,
at line 771 of `main`, whether mutual authentication is requested.

### Tested

Release builds with `CRYPTO=openssl` of `f7fa183` and of the change, in one
build tree: the change recompiled one object, and the requester, the attester
and the validator came out byte-identical to `main`'s. Each run used fresh
copies of `build/bin`, an unmodified requester and a responder copy altered as
stated; 42 runs, in scratch, `~/spdm-lab/scratch-1020/t1`, with no
`manifest.json`:

| the responder's copy | `main` | the change |
|---|---|---|
| unaltered | `0x13`, exit 0, 2,272 messages | the same messages and the same output |
| slot 4's chain removed | no slot provisioned: `GET_DIGESTS` gets `ERROR(Unspecified)`, exit 1 | `0x03`, exit 0, slot 1 read where slot 4 was, and the message sequence of the unaltered run |
| slot 4's chain, one bit of its intermediate's signature flipped | the same as removed, and nothing printed | the same as removed, and one line |
| slot 4's chain removed, requester `--ver 1.2` | exit 1 | `0x03`, exit 0, the 2,216 messages of the unaltered 1.2 run |
| slot 4's chain removed, responder `--pqc_first TRUE`, ML-DSA-87 | exit 1 | `0x03`, exit 0, the 2,632 messages of the unaltered run |
| slot 0's chain only | no slot provisioned, exit 1 | `0x01`, exit 0, 1,696 messages |
| slot 1's chain removed | `0x11`, exit 0 | the same, and one line |
| slot 0's chain removed | `0x12`: `GET_CERTIFICATE` for slot 0 gets `ERROR(InvalidRequest)`, exit 1 | the same, and one line |
| slot 0's chain, one bit flipped | the same, and nothing printed | the same, and one line |
| all three removed | no slot provisioned, exit 1 | the same, and three lines |
| the Requester's slot-4 chain removed | `0x13`, exit 0, 2,252 messages | the same |

With slot 0 alone the requester exchanges 576 messages fewer, because it
reads no second slot's chain and does not open the second `KEY_EXCHANGE`
session, which `spdm_requester_emu.c` opens only when a slot other than 0 is
provisioned (lines 278–288). The commands the workflows run — the default, `PCI_DOE` with
and without `--exe_conn`, `--ver 1.1` to `1.4`, the slot ID 0xFF capabilities,
`--pqc_first TRUE` — gave the same exit status, the same message sequence and
the same output as `main`, except on `PCI_DOE`, whose `[PSK]` line differed;
it differed between two runs of `main`'s own responder as well.

`DEVICE=tpm`, Debug, built as `build_CI_TPM.yml` builds it, each run on a fresh
`swtpm` provisioned by upstream's `script/setup-tpm.sh` (`t2`, 6 runs). With
the default responder slots — 0, 1 and 4, all one key and one NV index — the
change and `main` are the same: 2,272 messages, the sequence of the sample
build's unaltered run. With the responder configured with slot 0 only
(`LIBSPDM_TPM_RESPONDER_SLOT_IDS=0`, one handle, one NV index), nothing
removed, `main` provisions no slot and the requester exits 1; the change
provisions slot 0, and the requester exits 0 with the sequence of the sample
build's slot-0-only run. Those two runs used the requester of the default TPM
build: the one built with the one-slot setting stops before `GET_DIGESTS`,
which is row 22.

### Candidate 22, found while testing it

`spdm_requester_emu` reads the responder's root certificates for slots 0 and 1
once the algorithms are negotiated, since the negotiated algorithm picks the
files (`spdm_requester_spdm.c` 600–663; `git blame` dates most of the lines to
`eb42a2e`, 2024-11), and stops if either read fails. Built for a TPM responder with one
slot, the slot-1 read fails — *"unsupported slot_id 1 (supported mask: 0x1)"*,
then *"read_responder_root_public_certificate fail!"* — and the requester exits
1 after six messages, before it asks the responder anything about slots. It is
candidate 3's assumption from the other side, and is recorded, not sent: one
change at a time to the same maintainer, and #550 first.

### What the hours before sending found

- **A hypothesis of mine, refuted before it was written anywhere.** Reading
  the TPM library's per-slot reader, I took it that upstream's TPM job
  provisions no slot today. Its log says `0x13`: the default configuration
  gives all three slots one key and one chain. What survived is narrower, and
  is the reason for the explicit conditions in the change.
- **Four sentences of my drafts claimed more than had been run**, found by
  reading each against the runs before the commit was signed: the `--ver 1.2`
  and post-quantum rows were stated for a removed *or altered* chain, and only
  removal was run; "slot 1's chain removed or altered" — only removed; "a line
  for each slot not provisioned" — slot 4 in a connection that is not
  multi-key is not provisioned and prints nothing; and "`[PSK]` differs between
  any two runs" — four runs, four values.
- **And a fifth that got out.** The pull request's body said the one-slot
  requester stops "reading the responder's roots for slots 1 and 4"; it reads
  the roots of slots 0 and 1, and stops at slot 1. The two slot numbers had
  come from the responder's log of the same run, not the requester's. Found
  seven minutes after the pull request was opened, by reading the code for
  row 22.
- **The control build was faster than it could be.** It finished in 21
  seconds after a libspdm and an OpenSSL bump. Every libspdm `.c` file that
  changed between `1d98f73` and `6cb52f2` was recompiled; OpenSSL, built by an
  `ExternalProject`, was not, so the sample builds link the library built on
  2026-10-13 from the earlier pointer. Both sides of the comparison load the
  same `libcrypto`, so the comparison stands; the new TPM build directory
  built `45e844f`.
- **`jyao1`'s "slot 4 by default" has a mechanism**:
  `spdm_requester_authentication.c` reads the highest provisioned slot other
  than 0 (lines 51–55). With slot 4 not provisioned it reads slot 1, which is
  why the default requester completes with the change.

### Sent — 2026-10-20, 09:04 UTC

| | 3 |
|---|---|
| URL | <https://github.com/DMTF/spdm-emu/pull/550> |
| Opened | 09:04:54 UTC by the author, from `Jhongwe1:responder-slot-res`, on a page pre-filled from the reviewed files; the URL was decoded back and compared with them before it was opened |
| Title and body | the commit's subject; the body byte-identical to the reviewed file, 3,133 bytes, read back from the API. At 09:29 and 09:34 UTC the author edited the last sentence of its fourth paragraph, which had the one-slot requester stopping on the roots of slots 1 and 4; it now ends *"reading the responder's roots for slot 1."*, and the rest is unchanged. Read back after each edit |
| Commit | **`8c43299`** on `f7fa183`, signed by the author: tree `948ebd5`, the bytes tested, and the reviewed message with one line added, the sign-off; `check_upstream_commit.sh` satisfied. Pushed to the fork at 09:04 UTC on the author's instruction |
| Before the push | read at 09:03 UTC: `main` still `f7fa183`; nothing on #547 since 15:28 UTC the day before; no other open pull request on the subject; the fork's branch absent |
| Reviewers | `jyao1` and `steven-bellock`, added by CODEOWNERS |
| Checks | DCO success; **44 of 45** check runs success, the last at 09:28:37 UTC, `mergeable_state` unstable. The one failure is `VS_openssl_build` in *Version 1.4 with Certificates*: `actions/checkout` could not reach github.com for `libspdm` → OpenSSL → `oqs-provider`, and the build and test steps were skipped. The seventeen Windows builds that got past checkout passed, and so did the TPM job and all seven format checks. A re-run is the maintainers': the author's permission on the repository is read-only. Read from the API |
| The answer in #547 | posted by the author in two comments, at 09:07:31 and 09:08:09 UTC, together byte-identical to the reviewed text: with the sample keys the file is always there; it takes a responder with one key and one chain, like #532's, or with a chain that does not verify, which is how this project found it, by `t3_cert` on 2026-09-10; the TPM build with one responder slot is the first kind, with nothing removed; and the emulator is not expected to work without certificates |

### What decides what goes next

- #550: review. #547: whether the answer satisfies the maintainer, and whether
  `annamdi` and `giovanni-cf` find that the change covers their setups.
- 22: after #550 has an answer.
- ③: a question. 13: a conversation. 16: a Debug build.
- 94773: read at 09:11 UTC, unchanged since 2026-09-23 17:10 UTC; the
  author's.

## #550 reviewed, and changed — 2026-10-20

Read from 10:16 UTC, when the author said #550 had a reply.

### What came back

`annamdi`, #532's reporter and one of the two users #550 credits, reviewed
`8c43299` an hour after it was opened. The API gives the reviewer no
association with the repository; it is the review of the person whose
deployment #547 is about.

| time (UTC) | where | what |
|---|---|---|
| 10:09:10 | line 529, the slot-4 read | *"why not only attempt to load slot 4 when multi_key_conn_rsp is true?"* |
| 10:10:30 | line 575, the `Slot 4` line | *"only when multi-key is intended but slot 4 cannot load."* |
| 10:11:25 | the review, **changes requested** | *"might be best to condition it to when multi-key is intended."* |

### Why it was right, and where this record had already shown it

The callback provisions slot 4 only in a multi-key connection:
`LIBSPDM_DATA_LOCAL_SUPPORTED_SLOT_MASK` gets bit 4 only when
`multi_key_conn_rsp` is true, and `slot_data[2]` is `NULL` otherwise — the
rule of `jyao1`'s `ea77f25`, 2026-09-08, titled *"fix: provision slot 4 only
when multi-key"*. libspdm sets `multi_key_conn_rsp` while answering
`NEGOTIATE_ALGORITHMS` (`libspdm_rsp_algorithms.c` 1080–1101 at `6cb52f2`):
from SPDM 1.3, and only if the Requester asked for `MULTI_KEY_CONN`.
`8c43299` still read slot 4's chain in every connection, and when the read
failed it printed `Slot 4: certificate chain not loaded, not provisioned` in
connections that could never provision slot 4 — a warning about something
nothing could have done, on every such connection to a responder like #532's.

The line was in this project's own runs. `t1`'s B1 and B6, `--ver 1.2` with
slot 4's chain removed (in B6 slot 1's too), print the slot-4 line, and the
previous section read them as the change working. Its "What the hours before sending found"
corrected a draft sentence, "a line for each slot not provisioned", because
slot 4 in a connection that is not multi-key is not provisioned and prints
nothing: the sentence was made to fit the code, and the code was not asked
whether it should read a chain it cannot use. And the author's answer in #547
had named both halves of the cause: slot 4's chain is read in every
connection although slot 4 is provisioned only in a multi-key one, and that
read decides for slots 0 and 1. `8c43299` fixed only the second.

### The change, revised

`dcf2cc4` on `f7fa183`, +50 −28 against `main` (`8c43299` was +24 −11; the
difference is the moved query and two re-indented reads). Still one commit, so that `main`
would get one change rather than the first version and its correction:

- the `multi_key_conn_rsp` query moves, unchanged, from the provisioning block
  to before the reads — with `multi_key_data_size`, which `ea77f25` introduced
  so that the query would not overwrite `data_size`, slot 0's chain size.
  Before the reads `data_size` would have been safe; a reviewer should not
  have to work out the order to see it;
- both slot-4 reads, the traditional and the post-quantum, are made only when
  it is true;
- the `Slot 4` line is printed on `multi_key_conn_rsp && !res4`.

The Requester's chains are still left as they are. The revision was committed
on a new branch, `responder-slot-res-v2`, from `main`, not by amending
`8c43299`: this session's permission classifier refused an amend of a signed
commit that had been pushed, and was not worked around. The author signed
with one command, which applied the reviewed message and the sign-off
together.

### Tested

The harness and the build tree of `t1`, 26 cases, each against `main`,
`8c43299`'s tree and the revision: 78 runs, in scratch,
`~/spdm-lab/scratch-1020/t4`, with no `manifest.json`. Five cases are new:
`--other_param OPAQUE_FMT_1` on the requester, which leaves `MULTI_KEY_CONN`
out of `NEGOTIATE_ALGORITHMS` and so gives a 1.4 connection without multi-key
(`DIGESTS` `0x03`/`0x03`), unaltered and with slot 4's chain removed, each
also with `--pqc_first TRUE` on the responder; and all three chains removed
with `--ver 1.2`.

- **The first version against the revision**: the same exit status, message
  sequence, requester log and responder log in 21 of the 26 cases, apart from
  the `[PSK]` line on `PCI_DOE`. The other five are exactly the connections
  without multi-key with slot 4's chain removed, and in each the revision's
  responder log lacks two lines: `Slot 4: certificate chain not loaded, not
  provisioned`, and `Unable to open file …/bundle_responder.certchain4.der` —
  it did not open the file.
- **`main` against the revision**, with slot 4's chain removed and no
  multi-key: `main` exits 1 after eight messages; the revision exits 0 with
  the message sequence of the unaltered run — 2,216 messages with `--ver 1.2`,
  2,272 with `--other_param OPAQUE_FMT_1`, 2,632 with that and `--pqc_first
  TRUE`. All three chains removed with `--ver 1.2`: exit 1 on both, and the
  revision prints lines for slots 0 and 1. The workflows' commands: as for
  `8c43299`.

`DEVICE=tpm`, Debug, a fresh `swtpm` for each run (`t5`, 6 runs). The default
slots, the workflow's configuration: the same as `main`. The one-slot
responder with the default build's requester: `0x01`, exit 0, and lines for
slots 1 and 4, since in a multi-key connection slot 4 is wanted and missing.
The same with `--ver 1.2` on the requester: `main` exits 1; `8c43299` exits 0,
prints lines for slots 1 and 4, and the TPM library reports *"unsupported
slot_id"* for both; the revision exits 0, prints the slot-1 line only, and
does not ask the TPM library for slot 4.

### Sent — 2026-10-20, 12:23 UTC

| | |
|---|---|
| Commit | **`dcf2cc4`** on `f7fa183`, signed by the author: tree `82ba048`, the bytes tested, and the reviewed message with one line added, the sign-off; `check_upstream_commit.sh` satisfied |
| Before the push | read at 12:21:30 UTC: #550 unchanged since 10:11:25 UTC, nothing new on #547, `main` still `f7fa183`, the fork's branch still `8c43299` |
| Push | a force-push with a lease on `8c43299`, run here on the author's instruction: `+ 8c43299...dcf2cc4` at 12:23:11 UTC. The pull request's head read back as `dcf2cc4`, one commit |
| Body | replaced by the author with the reviewed file, read back byte-identical, 3,473 bytes: a sentence on slot 4 and multi-key, a row for connections without multi-key in place of the `--ver 1.2` row, the all-removed row, and the one-slot TPM run with `--ver 1.2`. His correction of 09:34 UTC is kept |
| Replies | two comments by the author, at 12:25:37 and 12:26:46 UTC, on the pull request rather than in the two threads: agreement, then what the revision does where multi-key is not negotiated, and that the table was updated. His wording: the first is the first sentence of the reviewed draft, the second the draft without its first word |
| Review | requested again from `annamdi` at 12:26:53 UTC |
| Checks | DCO success; **45 of 45** check runs success, the last at 12:46:33 UTC, and `mergeable_state` clean — among them the Windows job whose checkout could not reach github.com on `8c43299`, built and passed this time. Read from the API |

### What decides what goes next

- #550: `annamdi`'s answer, then the maintainers'.
- 22: after #550 has an answer.
- ③: a question. 13: a conversation. 16: a Debug build.

## #550 approved twice, and the CoRIM round trip prepared — 2026-10-26

Read from 04:15 UTC. The author asked for the one candidate best sent now,
as a change or as a question, and delegated the choice.

### What came back

#550 had been approved twice on the evening it was revised, after this
record's last entry was committed: by `annamdi` at 14:55:58 UTC and by
`giovanni-cf` at 15:02:37 UTC, the two users whose deployments #547 is about,
each without a comment. At 15:08:40 `steven-bellock` removed his own review
request, as he had on #524 two minutes before `jyao1` merged it; `jyao1` is
the one reviewer still requested. Six days later nothing else has moved:
`main` is still `f7fa183`, #550 is open with `mergeable_state` clean, the open
pull requests are #550, #496 and #490, and no issue or pull request has been
updated since 15:08 UTC on 2026-10-20.

### What was chosen, and why

| row | send now? | because |
|:-:|---|---|
| ③ | **yes, as a pull request** | the call this row had waited on since 2026-10-12 — which JSON form is canonical — is made by the shipped files: `SpdmSamplePolicy.rego` reads the reference through the two keys `cbor_to_json` writes, so that form cannot change, and `json_to_cbor` is the only side free to move. Measured today: those two keys are the whole difference, and accepting them changes no existing output. `CoRimTool.py` is a file where four of four changes have merged, none with a comment, and #542's body had named this as what it did not fix |
| 22 | not now | after the maintainers have answered #550, which is the same question from the responder's side; and as a question first, since `c0f2e43` made the requester stop on a failed read on purpose, for #17 |
| 13 | not now | a conversation about three fixes, one of which changes behaviour |
| 16 | not now | a Debug build first |

Two pull requests open at once to the same maintainer is what the 2026-09-30
rule avoided. #550 is waiting on a merge, not a review, and this change is to
a Python tool the other does not touch; #545 and #546, and #548 with #547,
were open together without harm.

### Candidate ③, measured at `f7fa183`

`CoRimTool.py` is still the blob `08a4e885` that #542 left, in which every
line involved dates to `69d1c68`, 2022-06-28, the commit that added the tool.
`DecodeCbor.Decoder` (229–237) names each CBOR tag it meets through
`GetKeyByValue` and makes the name a JSON key, so the two tags around the
document, `corim` #6.500 and `unsigned-corim-map` #6.501, come out as
`{"corim": {"unsigned_corim_map": {…}}}`. `translate_data` (159–183) looks
every key up in `AllMapDict` (76–79), which merges the CDDL maps and not
`CorimCborTags`, and raises `KeyError: 'corim'` on the first. `GenCbor`
(104–116) adds both tags itself, so `json_to_cbor` expects the map bare, as
`SampleManifests/SpdmSampleCoMid.json` writes it.

Three things decided the shape of the change, each run rather than reasoned:

- **The two keys are the only asymmetry.** With them removed from
  `cbor_to_json`'s 4,312-byte output, `json_to_cbor` gives back the sample's
  996 bytes, byte for byte. Everything below the wrapper — the role and hash
  names #542 taught it — round-trips.
- **The wrapped form is what the readme's flow writes and the policy reads.**
  The documented verification — `json_to_cbor`, `sign`, `verify`,
  `cbor_to_json`, `SpdmMeasurement.py`, `OpaTool.py`, `opa eval` — runs end to
  end at `f7fa183` (OPA 1.20.2, `SPDM_HASH_CHECK` and `SPDM_SVN_CHECK` true),
  and its `SpdmSampleCoMid.corim.json` has `corim` and `unsigned_corim_map` as
  its two outer keys; `SpdmSamplePolicy.rego` line 9 reads
  `input.reference.corim.unsigned_corim_map.corim_tags[0]…`. Dropping the two
  keys in `cbor_to_json` would change that file under every policy written
  against it.
- **`cbor_to_json` reads a signed file too**, as the readme says: 6,052 bytes
  with `corim` → `signed_corim` → `cose_sign1` as its outer keys, which
  `json_to_cbor` cannot encode in any form, since signing is `sign`'s job.
  So that case gets a line, not a `KeyError`.

### The change

*CoRimTool: accept the JSON cbor_to_json writes*, `baedf75` on `f7fa183`,
unsigned, +7 in `CoRimTool.py` and +2 in `readme.md`: `GenCbor` takes the
two keys off when the document's one outer key is `corim` and its one inner
key is `unsigned_corim_map`; when the inner key is something else,
`signed_corim`, it raises `ERROR: json_to_cbor takes an unsigned CoRIM; this
file holds 'signed_corim' !`, in the file's own style; and the readme's
"CBOR tag support" paragraph gains a sentence saying what the two outer keys
are and that `json_to_cbor` accepts a file with or without them. Both files
are CRLF upstream — 392 of 392 lines in the tool, 143 of 143 in the readme —
and the change keeps them so: the committed blobs carry a CR on every line,
399 of 399 and 145 of 145.

### Tested

`main` (`f7fa183`) and the change, each in its own copy of the tool's
directory, Python 3.12.3, cbor2 5.6.5, OPA 1.20.2:

| | `main` | the change |
|---|---|---|
| `json_to_cbor` on the shipped sample | 996 bytes, sha256 `6fd030f9…` | the same bytes |
| `cbor_to_json` on those | 4,312 bytes, sha256 `a89af288…` | the same bytes |
| `json_to_cbor` on those 4,312 bytes | exit 1, `KeyError: 'corim'` | exit 0, the sample's 996 bytes |
| the readme's flow, seven commands | runs; both checks true | the same `.cbor`, `.json` and `opa.input` files, the same result |
| `json_to_cbor` on the flow's `SpdmSampleCoMid.corim.json` | exit 1, `KeyError: 'corim'` | exit 0, the 996 bytes `verify` extracted |
| `json_to_cbor` on `cbor_to_json`'s reading of the signed `.corim` | exit 1, `KeyError: 'corim'` | exit 1, the line naming `signed_corim` |

`python -m py_compile` passes; `check_upstream_commit.sh` on the worktree
reports the three sign-off lines only. The committed blobs are the bytes the
runs used (`b32e15c9` and `b9aff839`), checked by hashing the copies.

### What the hours before found

- ★ **The first application of the edit found no anchor.** The tool is CRLF
  upstream, which a listing on the terminal does not show; the editing
  script matched LF. It now reads each file's own line ending and asserts
  that the file does not mix them. An editor that normalised the file would
  have produced a 392-line diff of nothing, and a reviewer would have been
  right to refuse it.
- **The approvals had been in the record's blind spot for six days.** The
  2026-10-20 entry ends with "`annamdi`'s answer, then the maintainers'", and
  the answer came that afternoon, after the entry was committed. Nothing here
  reads upstream between sessions, so the first act of a session is the
  read, and it was.
- **`py_compile` left a `__pycache__`** in the worktree, which the checker
  reported as uncommitted changes. Removed; the tree the commit holds was
  never in question, but the checker was right to stop.
- **Freshness**, read at 04:50 UTC: `main` `f7fa183`; nothing opened or
  updated upstream since 15:08 UTC on 2026-10-20; the fork has no branch
  `corim-json-roundtrip`; and five searches for the defect's words find only
  this project's own merged pull requests. The pre-filled pull-request page
  was built from the reviewed files and decoded back to them byte for byte.
- ★ **A link nobody wrote.** The author, reading the pre-filled page's
  preview before opening it, saw `#6.500` rendered as a link to issue #6.
  GitHub links `#` and digits in pull-request text and in commit messages,
  and the commit, once in the repository, would have put a reference on #6,
  a 2021 issue of `jyao1`'s. The notation is CDDL's for a CBOR tag and the
  file's own — `#6.505` in `GenCbor`'s comments, `#6.552(svn)` in the
  readme — and in a rendered Markdown file GitHub leaves it alone. So the
  body and the commit message now say `tag 500` and `tag 501`, in one line
  each, and the code comment and the readme sentence keep the notation. The
  message changed, so the commit did: the author signed `2ee099d` in place
  of `5698f6e`, same tree.
- **The replacement push was refused here.** This session's permission
  classifier refused the force-push with a lease on `5698f6e`, as it had
  refused an amend on 2026-10-20, and the author ran the prepared script
  himself. He had opened the pull request first, so from 05:28 to 05:51 UTC
  #551's head was the first signed commit, with the old wording, under the
  new body.

### What is left, and whose

The author's, after the freshness read is repeated: review the commit
(`git --no-pager show` in `~/spdm-lab/work/spdm-emu-corim-rt`), sign it with
`git commit --amend -s --no-edit` — the tree `4639bc2` must not change — have
the branch pushed to the fork, and open the pull request from
`~/spdm-lab/work/corim-json-roundtrip.pr-url.txt`, whose title and body are
the reviewed files, unedited.

### Sent — 2026-10-26, 05:28 UTC

| | |
|---|---|
| URL | <https://github.com/DMTF/spdm-emu/pull/551> |
| Opened | 05:28:02 UTC by the author, from `Jhongwe1:corim-json-roundtrip`, on a page pre-filled from the reviewed files; the URL had been decoded back and compared with them before it was handed over |
| Title and body | the commit's subject; the body byte-identical to the reviewed file, 2,631 bytes, read back from the API |
| Commit | **`2ee099d`** on `f7fa183`, signed by the author at 05:23 UTC: tree `4639bc2`, the bytes tested, and the reviewed message with one line added, the sign-off; `check_upstream_commit.sh` satisfied. It replaced `5698f6e`, signed at 05:13 UTC with the message's first wording, which the fork held from 05:14 UTC and the pull request from 05:28 to 05:51 UTC |
| Diff | two files, +9 −0 |
| Before each push | read at 05:13:58 and 05:24:07 UTC: `main` still `f7fa183`, nothing opened or updated upstream since 2026-10-20 15:08 UTC, no duplicate, the fork's branch absent and then at the first signed commit, and no pull request from it yet |
| Pushes | the first at 05:14:25 UTC, run here on the author's instruction; the replacement, a force-push with a lease on `5698f6e`, run by the author at 05:51:09 UTC after this session's permission classifier refused it |
| Reviewers | `jyao1` and `steven-bellock`, added by CODEOWNERS |
| Checks | DCO success; **45 of 45** check runs success on `2ee099d`, all eighteen VS builds among them, the last at 06:16:12 UTC; `mergeable_state` clean. Read from the API |
| Outcome | in review: no review and no comment at 06:16 UTC |

### What decides what goes next

- #551: review. A comment that comes back is read here first, and the
  reply is the author's.
- #550: the maintainers.
- 22: after #550 has the maintainers' answer, and as a question. 13: a
  conversation. 16: a Debug build.
- 94773: not read today; the author's.

## #551 merged, #550 changed for its maintainer, and 23 asked as #552 — 2026-10-29

Read from 11:10 UTC. The author asked whether #550 should be changed as its
maintainer had said, and for the candidate best sent now; when the answer to
the maintainer's second comment turned out to be a design choice, he
delegated it.

### What came back

#551 was merged on 2026-10-26 at 14:21:55 UTC by `jyao1`, by rebase, as
`9cc8b46` on `f7fa183`, nine hours after it was opened: the tree `4639bc2`,
the patch-id and the message are those of `2ee099d`, and there was no review
and no comment. Seven minutes later he commented on #550:

> Comment 1:
> Please aware that slot 0 is must-have if cert_cap is there. Otherwise it is an invalid configuration.
> I think this should error out directly. Other slots are optional.
>
> Comment 2:
> It is acceptable, if the configuration is consistent.
> Have you checked any data in sample library is consistent with slot 1 and slot 4, they are not there? E.g. KeyPair ID

Nothing else had moved by 12:35 UTC: `main` was `9cc8b46`, and #550's head
and the fork's branch were `dcf2cc4`, with its two approvals.

### What Comment 1 and Comment 2 ask

- **Comment 1 is the specification's rule.** Slot 0 shall hold a certificate
  chain when the endpoint supports certificates (DSP0274 1.4.0, ¶374). On
  `main`, a responder whose slot-0 chain does not load provisions slots 1
  and 4 (`ProvisionedSlotMask` `0x12`), and the requester fails later, at
  `GET_CERTIFICATE` for slot 0.
- **Comment 2 is his own libspdm
  [#3638](https://github.com/DMTF/libspdm/issues/3638)**, open since
  2026-06-05, for the slots a responder leaves empty. Since his
  [#3650](https://github.com/DMTF/libspdm/pull/3650) the sample key-pair
  library associates each algorithm's primary key pair with slots 0 and 1
  and its secondary with slot 4 — `AssocCertSlotMask` `0x03` and `0x10` —
  whichever chains load, and libspdm's TPM library builds the same file.
  libspdm's `DIGESTS` reports a slot only when it holds a chain, so it cannot
  report a slot that has a key pair and no chain, the state DSP0274 calls
  "Exists with key" ([#2493](https://github.com/DMTF/libspdm/issues/2493),
  open since 2023). Wherever a slot is left empty the two disagree, on
  `main` as with #550.

Measured in 28 runs with a requester that asks for every KeyPairID, and in
the TPM build:

- With `--asym RSASSA_2048` on both sides, KeyPairID 1, the one
  `spdm_requester_emu` asks about, is the negotiated key pair. With slot 1's
  chain removed, `DIGESTS` has `ProvisionedSlotMask` `0x11` and
  `KEY_PAIR_INFO` `AssocCertSlotMask` `0x03`, on `main` as with the change.
  With slot 4's chain removed, the change gives `0x03`, and the secondary,
  KeyPairID 13, still reports `0x10`.
- `DEVICE=tpm` with `LIBSPDM_TPM_RESPONDER_SLOT_IDS=0` and nothing removed:
  the change provisions slot 0 only, while the ECDSA P-256 key pairs,
  KeyPairIDs 4 and 16, report `0x03` and `0x10`.
- A prototype that removes an empty slot from its key pair's association,
  through `libspdm_write_key_pair_info`, as `SET_KEY_PAIR_INFO` does, makes
  the two agree in every case: #547's case, slot 0's chain only, then
  reports `0x01` and `0x00`, as `DIGESTS` does, and so does the one-slot TPM
  build. About fifty lines; not sent.

### What was decided, and why

The author's question was whether to do as the maintainer said. For the
first comment, yes; for the second, the answer is a question back.

| | decided | because |
|---|---|---|
| Comment 1 | **changed**, as `b20e680` | it is the specification's rule, it is one `if`, and its effect is measurable: the requester now fails at `libspdm_init_connection`, after the responder's `ERROR:` line, instead of at slot 0's `GET_CERTIFICATE` |
| Comment 2 | **answered, not changed**: two ways offered, the first recommended, his choice asked | either way changes what the sample's key pairs report, from the table his #3650 set; the first is the smaller, prototyped and measured here, and the second would stop the one-slot TPM build too |
| 23 | **asked**, as #552 | found in Comment 2's own runs; independent of #550; it can be fixed in more than one way |
| 22 | **held** | whether it is a defect depends on which way #550 goes |
| 13, 16 | not now | a conversation; a Debug build |

### The change

*spdm_responder_emu: provision each slot that loads*, third version,
**`b20e680`** on `9cc8b46`: +56 −28 against `main`, +8 −2 against
`dcf2cc4`. When slot 0's chain does not load and `CERT_CAP` is set, the
responder prints `ERROR: Slot 0: certificate chain not loaded; CERT_CAP
requires one` and exits 1. The check sits in the connection-state callback,
which runs once the algorithms are negotiated, so the responder stops before
it answers `NEGOTIATE_ALGORITHMS`; without `CERT_CAP` it prints the line
`dcf2cc4` printed and carries on. Nothing else in `dcf2cc4` changed. `exit()`
is new to the file, and every toolchain upstream's CI builds sees it
declared: `spdm_emu.h` includes `stdlib.h` unconditionally.

### Tested

`main` (`9cc8b46`) and the change, Release, `CRYPTO=openssl`, each against an
unmodified `spdm_requester_emu`, with the responder's copy of `build/bin`
altered as stated, in 44 runs; and the TPM build, as `build_CI_TPM.yml`
builds and runs it:

| | `main` | the change |
|---|---|---|
| slot 4's chain removed, or one bit of its intermediate certificate's signature flipped | no slot provisioned: `GET_DIGESTS` gets `ERROR(Unspecified)`, exit 1 | `0x03`, exit 0, reading slot 1 where it read slot 4: the 2,272 messages of an unaltered run, and 2,632 with `--pqc_first TRUE` on the responder |
| slot 4's chain removed, without multi-key (`--ver 1.2`; `--other_param OPAQUE_FMT_1`, also with `--pqc_first TRUE`) | the same, exit 1 | slot 4's chain neither opened nor reported; exit 0 after the unaltered runs' 2,216, 2,272 and 2,632 messages |
| slot 0's chain only | no slot provisioned | `0x01`, exit 0, the second `KEY_EXCHANGE` session skipped |
| slot 0's chain removed, or altered as above, or all three removed, also with `--pqc_first TRUE` | `0x12`, or no slot: `GET_CERTIFICATE` for slot 0, or `GET_DIGESTS`, gets an `ERROR`, exit 1 | the `ERROR:` line; the responder exits 1 on `NEGOTIATE_ALGORITHMS`, after five messages, without answering it; the requester's `libspdm_init_connection` returns `0x80040001`, and it is then killed by `SIGPIPE` sending its shutdown (status 141) |
| `DEVICE=tpm`, the responder configured with slot 0 only, nothing removed | no slot provisioned, exit 1 | `0x01`, exit 0, also with `--ver 1.2` (1,696 and 1,654 messages) |

Slot 1's chain removed: the same messages and exit status as `main`, and a
line for slot 1. The commands upstream's workflows run — the default,
`PCI_DOE` with and without `--exe_conn`, `--ver 1.1` to `1.4`, the slot ID
0xFF capabilities, `--pqc_first TRUE` — and `spdm_device_validator_sample`,
and the TPM build as its workflow runs it: the same exit status, messages and
output as `main`, apart from `PCI_DOE`'s `[PSK]` lines, which change from run
to run. `check_upstream_commit.sh` on the signed commit is satisfied.

### What the hours before found

- ★ **The answer's own runs carried another defect.** Twelve of the runs for
  Comment 2 used RSA-2048, so that KeyPairID 1, the one the requester asks
  about, would be the key pair in use; none of the twelve opened a session.
  Not #550's doing: with nothing removed, on `main`, the same. The
  requester's `SET_KEY_PAIR_INFO` step, after it has read KeyPairID 1, takes
  the key pair's association away and erases it; the responder then clears
  slots 0 and 1's key usage, and refuses `KEY_EXCHANGE` on slot 0. Recorded
  as row 23 and asked as #552. The reply waited for the issue's number and
  gained one sentence pointing at it, so that a maintainer who reproduces the
  reply's numbers does not take the failure for the change's.
- **The first TPM runs measured the machine.** Every case failed after six
  messages, on `main` as with the change, because they ran without the three
  variables `build_CI_TPM.yml` sets — `TPM2TOOLS_TCTI`, `TPM2OPENSSL_TCTI`,
  `OPENSSL_MODULES` — and the TPM library looked for `/dev/tpm0`. Kept
  apart; no number here is from them.
- **A status that was not a verdict.** The first wording of the slot-0
  `Tested:` line said the requester "exits 1". It is killed by `SIGPIPE`,
  status 141, writing its shutdown to the socket the responder closed; the
  failure is `libspdm_init_connection`'s, `0x80040001`, and that is what the
  line now says.
- **The order of the sends changed on the way.** The plan was the push, the
  body, the reply and then the issue. The reply went last: it needed #552's
  number, and its first words are "done in the update", so it also waited for
  the 45 checks.
- **Freshness**, read before and after each of the author's five steps, from
  15:17 to 15:59 UTC: `main` `9cc8b46`; #550 unchanged since 2026-10-26
  14:29:47 UTC until the push, and the fork's branch `dcf2cc4`; no issue or
  pull request opened in `DMTF/spdm-emu` since 2026-10-27 until #552, and no
  earlier report of 23 by its words. `jyao1`'s open #496 adds `SLOT_MGMT` to
  the same `--exe_conn` and `--exe_session` lists and does not touch the step
  23 is about.

### Sent — 2026-10-29, 15:26–15:59 UTC

| | |
|---|---|
| #550's commit | **`b20e680`** on `9cc8b46`, signed by the author at 15:15 UTC: tree `2a9704b`, the bytes tested, and the reviewed message with one line added, the sign-off; `check_upstream_commit.sh` satisfied |
| Push | by the author at 15:26:53 UTC, a force-push with a lease on `dcf2cc4`, from a script that first checked the fork's branch and `main` |
| Body | edited by the author after the push: byte-identical to the reviewed file, 3,820 bytes. The three slot-0 rows become one, with the new behaviour; `main` is `9cc8b46`; and a sentence says the key-pair question is discussed below |
| #552 | opened by the author at 15:56:13 UTC: title and body byte-identical to the reviewed files, the body 2,553 bytes |
| Reply | posted by the author at 15:59:07 UTC, comment 6501700247: the reviewed reply, 2,083 bytes, with one sentence added once #552 had a number, 2,253 bytes, byte-identical to the file. Comment 1: done, with the new behaviour; Comment 2: the measurements above, the two ways, the first recommended, and the question. #552 was cross-referenced from #550 at 15:59:10 UTC |
| Checks | DCO success at 15:26:56 UTC; **45 of 45** check runs success, the last at 15:51:18 UTC; `mergeable_state` clean |
| Reviews | `annamdi`'s and `giovanni-cf`'s approvals of 2026-10-20 stand, on `dcf2cc4`; nothing new by 15:59 UTC |

### What decides what goes next

- #550: `jyao1`'s choice between the two ways. Whichever he picks is a
  fourth version, with its runs repeated; the first is prototyped here.
- #552: the maintainers' answer, then the change.
- 22: after #550's answer.
- 13: a conversation. 16: a Debug build. 94773: not read today; the
  author's.

## Candidate 16's cause, found — 2026-11-02

Read from 20:19 UTC on 2026-11-01. The author asked whether #550's third
version and #552 had been answered, and whether another candidate should go
now; he then delegated what to do while waiting, and, once it was found, what
to do with the cause.

### What came back

Nothing. #550's head was `b20e680`, and its last activity the reply of
2026-10-29 at 15:59 UTC, which ends by asking `jyao1` which of two ways he
prefers; he was still the one reviewer requested, and the approvals of
2026-10-20 stood, on `dcf2cc4`. #552 had no comment, label or assignee.
`main` was `9cc8b46`, and no other issue or pull request in `DMTF/spdm-emu`
had been opened or updated since 2026-10-29. `jyao1`'s public activity since
the reply was on 2026-10-30, from 13:10 to 13:47 UTC: his own libspdm #4261,
one of three pull requests of his that replace FIPS self-test vectors, and a
review in `intel/MigTD`; nothing at the weekend. One working day had passed.
libspdm #3638, #2493 and #3717, which the reply's two ways rest on, had not
moved since 2026-07-28, 2024-01-04 and 2026-09-01. `openbmc/spdm` 94773 was
as on 2026-09-23 at 17:10 UTC: patchset 3, `Verified+1`, no Code-Review vote,
three threads unresolved, and Gerrit's attention set holding the author,
Ratan Gupta and Chinmay Shripad Hegde.

### What was decided, and why

| | decided | because |
|---|---|---|
| a reminder on #550 | **not yet** | one working day; this project's questions have been answered in two hours (#547) and in nine days (#533, across the National Day holiday), and #550's first round took six; a design choice in the maintainer's own library is the slower kind |
| another candidate | **none sent** | both open items are questions to the same maintainer; 22 waits on #550's answer, 13 is a conversation, and 16 had no cause |
| the wait | **16, measured until it had one** | the one candidate that needed nobody's answer to move |
| 16's change | **prepared here, held** | the same maintainer, and #3650's own code; #550's second question is about the same table |

### 16 at `9cc8b46`

Re-run on `9cc8b46` (libspdm `6cb52f2`), Release, `CRYPTO=openssl`, with the
options S1 held constant on 2026-09-14 less `--slot_count 1`, which #538
removed, in runs kept outside this repository; `ALGORITHMS` was read back as
declared in each:

| arm | `--exe_conn` | result |
|---|---|---|
| SLH-DSA-SHA2-128s | `DIGEST,CERT,CHAL,MEAS`, and `DIGEST,CERT,CHAL` | exit 1, `do_authentication_via_spdm - 80020001`, 42 messages |
| SLH-DSA-SHA2-128s | `DIGEST,CERT,MEAS` | exit 1, `do_measurement_via_spdm - 80020001`, 60 messages |
| SLH-DSA-SHA2-128s | `DIGEST,CERT` | exit 0, 54 messages |
| ML-DSA-44 | `DIGEST,CERT,CHAL,MEAS` | exit 0, 40 messages |
| ML-DSA-87 | `DIGEST,CERT,CHAL,MEAS` | exit 0, 66 messages; its `CHALLENGE_AUTH` and `MEASUREMENTS` are larger than `DataTransferSize`'s 4,608 bytes, and chunked |

With `DIGEST,CERT,CHAL` and each of the sample's twelve SLH-DSA parameter
sets, the six whose chains arrive — SHA2 and SHAKE, 128s, 128f and 192s —
fail the same way, and the other six get an `ERROR` for `GET_DIGESTS`
(row 24). ML-DSA-44, -65 and -87 pass.

### Ruled out, and how

- **Chunking.** ML-DSA-87's signed responses are chunked as SLH-DSA's are,
  and verify. The control of 2026-09-14, ML-DSA-44, could not have shown it:
  its `CHALLENGE_AUTH` is 2,562 bytes and is not chunked, on either build.
- **The sample's files.** In all fifteen post-quantum directories the
  responder's PEM and raw private keys hold the same key, and it pairs with
  `end_responder.cert.der`, the leaf of the chain the responder sends: an
  SLH-DSA private key's second half is its public key, and an ML-DSA private
  key holds its public key's `rho` and `tr`, the public key's 64-byte SHAKE256
  hash. For SHA2-128s, another directory's leaf, slot 4's leaf and its own
  leaf with one bit flipped do not pair. This checked the files, and not
  which file the responder reads.
- **A parameter-set mapping.** SHA2 and SHAKE sets fail alike, and the
  certificate OID table maps all twelve correctly; only its comment for
  SHAKE-256f says `.21` for `.31`.
- **The signing code.** Both sides build the same message, the 100-byte
  signing prefix and the transcript's hash; pass the same SPDM context string
  as FIPS 205's context; and, with a context string, call the same OpenSSL
  functions with the same parameters for SLH-DSA as for ML-DSA.

### The cause

In libspdm's sample secret library, `os_stub/spdm_device_secret_lib_sample/`
at `6cb52f2`:

1. In a connection that is not multi-key, the responder signs with
   KeyPairID 0; `sign.c` 181–189 asserts it.
2. `read_priv_key_pem_pqc.c` 92 reads the default `end_responder.key` only
   when the KeyPairID is not slot 4's —
   `if (key_pair_id != libspdm_get_key_pair_id_by_slot(0, pqc_asym_algo, 4))`
   — and otherwise `end_responder4.key`.
3. The sample's key pair table has post-quantum key pairs for ML-DSA-44, -65
   and -87 only (`key_pair.c` 25–28), and `libspdm_get_key_pair_id_by_slot()`
   returns 0 when no key pair matches (406–432).

For ML-DSA, slot 4's KeyPairID is its secondary key pair's, and 0 is not it:
the default key. For SLH-DSA it is 0, the KeyPairID it is compared with:
every SLH-DSA signature is made with slot 4's key, and checked against slot
0's certificate. The requester's refusal is right.

Shown by intervention, in a copy of the binaries' directory where
`end_responder4.key` holds the bytes of `end_responder.key`, checked with
`cmp` before any run, beside an untouched copy from which it was made:

| `9cc8b46`, `DIGEST,CERT,CHAL` and `DIGEST,CERT,MEAS` | as shipped | slot 4's key file replaced |
|---|---|---|
| SLH-DSA-SHA2-128s | `80020001`, 42 and 60 messages | exit 0, 60 and 60 |
| SLH-DSA-SHAKE-128s | `80020001`, 42 and 60 | exit 0, 60 and 60 |
| SLH-DSA-SHA2-128f | `80020001`, 74 and 108 | exit 0, 106 and 108 |

And on the build of 2026-09-14, `5f01d2f` with libspdm `8a92317`, with S1's
own command line: 42 messages and exit 1 as shipped, 66 messages and exit 0
with the file replaced. `8a92317` has the same lines; candidate 16 has had
this cause since the day it was found.

The selection, with a slot-4 file name for every post-quantum algorithm, came
with libspdm #3650 (`1e16c60`, merged 2026-06-11), which gave slot 4 a key of
its own. libspdm `main`, `6de8048` of 2026-10-29, has it still, and its line
225 selects the requester's own post-quantum key the same way — read, not
measured. Not reported upstream, by five searches of libspdm's issues and
pull requests.

### What this corrects

- § ⑯ and [`../pqc-cost.md`](../pqc-cost.md) §12 said the signing was not at
  fault, since the responder produced a correctly sized signature, and that
  what was left was the requester's verification. A signature made with
  another key of the same parameter set has the same size. Both carry a
  correction.
- Row 16's evidence cell: "bisected to requester-side signature
  verification".
- The control of 2026-09-14 never exercised chunking.

### What decides what goes next

- 16: the change — let `end_responder4.key` be chosen only for slot 4's own
  key pair, so that KeyPairID 0 never chooses it, on both sides — is small,
  and is prepared here next: measured on every parameter set, on ML-DSA and on
  a multi-key connection, and held until #550 has its maintainer's answer.
  Adding SLH-DSA key pairs to the sample's table is the other way, and his
  call.
- 24: which limit stops the six large parameter sets, read before anything is
  said of it.
- #550, #552, 22, 13 and 94773: as on 2026-10-29.

## Candidate 16's change, prepared — 2026-11-02

From 04:19 UTC. The author asked for 16's change to be prepared in libspdm,
locally and unsigned, and tested on every SLH-DSA parameter set, on ML-DSA, on
the traditional algorithms, on a multi-key connection and with the requester
signing; then asked for a second check, from another angle, of whether it
needed sending at all; then delegated what was left.

### What came back

Nothing, at 04:19 UTC and again at 05:11. #550 was at `b20e680`, its last
activity the reply of 2026-10-29; #552 had no comment, label or assignee;
`spdm-emu` `main` was `9cc8b46`, and libspdm `main` `6de8048`, 45 commits after
the `6cb52f2` that `9cc8b46` builds. No issue or pull request in either
repository had been updated since 04:00 UTC. `jyao1`'s public activity that
morning was in `intel/MigTD` and `confidential-containers/td-shim`, from 01:51
to 03:02 UTC.

### What was decided, and why

| | decided | because |
|---|---|---|
| the change | KeyPairID 0 selects the default key, at all four sites | the header describes the readers that way: only the negotiated algorithm's secondary key pair selects `end_*4.key`, and "any other key_pair_id uses the default end_responder.key". SLH-DSA has no secondary key pair. `jyao1`'s `e79dc8c1` guards `key_pair_id == 0` the same way in the key pair info HAL |
| SLH-DSA key pairs in the table | offered, not included | they would give slot 4 a KeyPairID of its own, but would renumber every secondary KeyPairID — with all twelve parameter sets, ECDSA_P384's would move from 17 to 29 — change the default of `LIBSPDM_MAX_KEY_PAIR_COUNT`, which `cf053131` made overridable, and touch the table #550's second question is about. `spdm.h` already has their capability bits |
| when to send | on the author's keystrokes, not on #550's answer | a change from the section above. Neither of #550's two ways touches it: the first changes slot 4's association only in a multi-key connection, where the KeyPairIDs it changes are not 0 (read, not run). It goes to another repository, which has a second code owner, and it is a change, not a question |
| the texts | the default flow's result in both | the second check found it; below |

### The change

In a clone of libspdm, branch `default-key-for-key-pair-id-0`: `8e1a97c` on
`main` `6de8048`, unsigned, tree `20b1b0c`, +20 −8 in `read_priv_key_pem.c` and
`read_priv_key_pem_pqc.c`. Each of the four tests becomes

```c
    if ((key_pair_id == 0) ||
        (key_pair_id != libspdm_get_key_pair_id_by_slot(0, pqc_asym_algo, 4))) {
```

with its own arguments, and each comment gains a sentence. `Fixes:` names
`1e16c60f6d30`, #3650, for the Responder's two, and `8620d4cb14f4`, #4149, for
the Requester's. The four files the selection involves — the two readers,
`key_pair.c` and `sign.c` — are the same blobs at `6cb52f2` and at `main`.
libspdm's `CONTRIBUTING.md` asks for the DCO sign-off and an `Assisted-by:`
trailer, and forbids `Co-authored-by:` for a tool; its compliance workflow
requires an ASCII commit message and uncrustify 0.78's formatting; `CODEOWNERS`
adds `jyao1` and `steven-bellock`. The author has no fork of `DMTF/libspdm` yet,
and nothing there from him.

### Tested

The two blobs were put into `spdm-emu` `9cc8b46`'s libspdm, built, and
restored; the shipped binaries rebuilt afterwards are byte-identical to the
ones compared against. Both builds were run with strace recording which private
key file each side opened, the variable itself, and the algorithms, the slot,
the KeyPairIDs and `MutAuthRequested` were read back from each capture.

| | as shipped | with the change |
|---|---|---|
| Responder, not multi-key, `DIGEST,CERT,CHAL,MEAS`: SLH-DSA SHA2 and SHAKE, 128s, 128f, 192s | `80020001`, `end_responder4.key` | pass, `end_responder.key`; 42→66, 74→118 and 70→110 messages |
| the same, 192f, 256s, 256f | `ERROR` for `GET_DIGESTS` after eight messages, no key file opened | the same |
| ML-DSA-44/65/87 and 11 traditional algorithms | pass | the same |
| SM2_P256 | `ERROR(Unspecified)` for `CHALLENGE` | the same |
| Multi-key, slots 0 and 4: ECDSA_P384 (KeyPairIDs 5,5,17), RSAPSS_3072 (2,2,14), ML-DSA (10,10,22 to 12,12,24) | pass, slot 4 with `end_responder4.key` | the same |
| Multi-key, SLH-DSA SHA2-128s and SHAKE-128f (0,0,0), slot 0 | `80020001` | pass |
| the same, slot 4 | pass | `80020001` |
| Requester signing `FINISH`, `WO_ENCAP`, not multi-key: SLH-DSA SHA2 and SHAKE, 128s, 128f, 192s | `8001000f`, `end_requester4.key` | pass, `end_requester.key` |
| the same, 192f, 256s, 256f | cannot read its own chain | the same |
| Requester, SLH-DSA SHA2-128s, `W_ENCAP`, and `WO_ENCAP` in a multi-key connection | fail | pass |
| Requester ML-DSA-44/65/87, ECDSA_P384 and RSASSA_2048; ML-DSA-44 and ECDSA_P384 with `W_ENCAP` and multi-key | pass | the same |

The first run of the traditional arms is void, and kept: with `--dhe NONE
--kem NONE` both builds got `ERROR(InvalidRequest)` for `NEGOTIATE_ALGORITHMS`
in six messages and opened no key file — the same on both because nothing ran.
Re-run with `--dhe SECP_384_R1`, the one option changed. libspdm's seven basic
unit tests, built as its Tier 1 builds them (Linux, GCC, Release, OpenSSL,
`LIBSPDM_CHECK_MACRO` and assert configuration 3), give the same results and the
same passing test names with and without the change; `test_crypt` prints
nothing either way. `script/format_nix.sh --check` passes, and uncrustify with
the repository's configuration refuses a copy with one continuation line
indented two columns less.

### What a user sees

The matrix holds everything but one variable still. The second check asked the
other question: spdm-emu's own PQC command, as `pqc_check.yml` runs it, with
`--pqc_first TRUE` on the responder, `--pqc_asym SLH_DSA_SHA2_128S` on both,
and everything else default.

| | as shipped | with the change |
|---|---|---|
| not multi-key (`--other_param OPAQUE_FMT_1`) | `80020001` at the first `CHALLENGE`, 42 messages | the whole flow: 2,636 messages, `KEY_EXCHANGE` on slots 0 and 1 and the PSK session, no error in the log |
| multi-key, the default | the same | everything until the second `KEY_EXCHANGE`, on slot 4: `80020001`, after 1,978 messages, and exit status 0 |

SHAKE-128f behaves the same with multi-key; ML-DSA-44 is the same on both
builds, 2,376 messages. So the change is necessary, and not sufficient for the
default: it gives slot 0, which every connection uses, the key it needs, and in
a multi-key connection SLH-DSA still has no KeyPairID for slot 4. The commit
message and the pull request say so. The first run without multi-key stopped
at 2,461 messages when the harness's 120 seconds ran out, exit status 124, and
is not counted; with 600 it finished in 131.

Why nothing upstream noticed: `--pqc_asym`'s default lists ML-DSA only
(`doc/spdm_emu.md` 98), `pqc_check.yml` runs that default, and libspdm's
Requester and Responder unit tests mention SLH-DSA once, in a
`SET_KEY_PAIR_INFO` test. Eleven searches of the two repositories that day
found no report. Two open libspdm pull requests touch the same files:
`alistair23`'s #3668, and the #3637 it replaces. #3668 adds `spdm_context` to
the Responder's two tests and keeps the comparison, and has not moved since
2026-09-25; whichever lands second needs a small rebase.

### What else this found

- **24's cause, read.** The sample's chain readers call
  `libspdm_verify_cert_chain_data()`, which first refuses chain data longer than
  `0xFFFF - (4 + LIBSPDM_MAX_HASH_SIZE)` bytes, 65,467 with SHA-512 built in.
  The six chains are 90,634 to 150,832 bytes, and the six that pass at most
  52,432. Read, not instrumented (row 24).
- **25: an exit status set by the wrong call.** The run above that fails on
  slot 4 exits 0; left without `EP_INFO` in its `--exe_conn`, the same run exits
  1. Line 204 of `spdm_requester_emu.c`, from `8e33385`, stores the platform
  call for the encapsulated `GET_ENDPOINT_INFO` in the routine's own `result`,
  so every later failure returns success (row 25).
- **SM2_P256** fails `CHALLENGE` on both builds with `ERROR(Unspecified)`,
  having opened its key file: not this change's, and not investigated.

### What decides what goes next

- 16: the author's fork of `DMTF/libspdm`; his reading of the commit; his
  sign-off, `git commit --amend -s --no-edit`, after which the tree must still be
  `20b1b0c`; a freshness check; the push on his word; and the pull request, from
  the prepared title and body.
- SLH-DSA key pairs in `key_pair.c`: if the maintainer asks for them.
- 24 and 25: after 16, and 25 after #550.
- #550, #552, 22, 13 and 94773: as on 2026-10-29.

## Candidate 16's change, sent as libspdm #4268 — 2026-11-02

From 07:16 UTC. The author created his fork of `DMTF/libspdm`, signed the
commit, gave the word for the push, and opened the pull request.

### What the hour before found

- ★ **The freshness check failed for reasons of its own first.** At 07:16 UTC
  it named three open pull requests, #4258, #3671 and #3629, as new and
  touching the change's files, and each of its four searches of the last 24
  hours printed gh's `accepts 1 arg(s), received 4` where a count belonged.
  In the sample library the three touch only `set_cert.c`, the
  `SET_CERTIFICATE` writer: none of the four functions it defines is named
  in the five files the change depends on, the two readers, `key_pair.c`,
  `sign.c` and the header. The filter had been the whole directory. The searches had handed jq's `--arg` to `gh api --jq`,
  which took it as its expression and the next three words as arguments. And
  the verdict did not read the searches at all: with the filter right, the
  script would have said FRESH having searched nothing. Both fixed, and re-run
  at 07:18 and 07:26 UTC ([`0001`](0001-corim-verify.md) §6 gains the line).
- **The read-back was tested before it was used**, on #551: identical
  against its own title and body, and three differences against libspdm's
  texts and a wrong SHA. Its first test ran with #551's title file missing and
  went on to ask for the checks of an empty SHA; it now stops.
- **`main` had moved**, at 05:48 UTC, to `0df82c8`: `steven-bellock`'s *Make
  Basic Constraints optional in the leaf certificate*, in
  `libspdm_crypt_cert.c`, its unit test and the changelog — none of the five
  files, and not row 24's lines. So the pull request stays on `6de8048`, where
  it was tested. Its checks run it merged onto `0df82c8`, which no build here
  has run.
- **Freshness**, read at 07:26 UTC: among open pull requests only #3668 and
  #3637 touch the five files, as that afternoon; no issue or pull request
  updated in the previous 24 hours mentions `SLH-DSA`, `KeyPairID`,
  `key_pair_id` or `end_responder4`; #550 and #552 as at 05:11 UTC; the
  author's fork, created at 07:24:41 UTC, without the branch.

### Sent — 2026-11-02, 08:43 UTC

| | |
|---|---|
| URL | <https://github.com/DMTF/libspdm/pull/4268> |
| Opened | 08:43:57 UTC by the author, from `Jhongwe1:default-key-for-key-pair-id-0` |
| Title and body | the commit's subject; the body byte-identical to the reviewed file, 3,799 bytes, read back from the API |
| Commit | **`d8c077c`** on `6de8048`, signed by the author at 07:25:49 UTC: tree `20b1b0c`, the bytes tested, and the reviewed message with one line added, the sign-off, in ASCII — checked before the push by a script written for it, and read back as GitHub stores it. `check_upstream_commit.sh`, written for spdm-emu, flags the 66-character subject, the two unwrapped `Fixes:` lines and a `CONTRIBUTING.md` that is not spdm-emu's, as expected |
| Diff | one commit, two files, +20 −8 |
| Push | at 07:29 UTC, run here on the author's word: a new branch on his fork, by a script that checks the signed commit first and does not overwrite a branch; read back at 07:29:30 UTC |
| Reviewers | `jyao1` and `steven-bellock`, added by CODEOWNERS |
| Checks | **56 of 56** check runs success on `d8c077c`: DCO at 08:44:01 UTC, and 55 in four workflows — Compliance Checks, TPM Test, Tier 1 Build and Test and CIFuzz — the last, Fuzzing, at 08:59:55 UTC; `mergeable_state` clean. `main`'s own at `0df82c8`: 52 of 53 success, one skipped. Read from the API |
| Outcome | in review: no review and no comment at 09:02 UTC |

### What decides what goes next

- #4268: review. A comment that comes back is read here first, and the
  reply is the author's. SLH-DSA key pairs for slot 4, if asked for, are a
  second change.
- #3668: whichever of the two lands second needs a small rebase.
- 24: after 16, re-read at the head first, since `libspdm_crypt_cert.c` has
  moved. 25: after #550.
- #550, #552, 22, 13 and 94773: as on 2026-10-29.

## #550 answered, and changed on both sides — 2026-11-03

Read from 15:44 UTC on 2026-11-02, ten minutes after it came.

### What came back

`jyao1` on #550 at 15:34:11 UTC (comment 6581157819), to the reply of
2026-10-29 that offered two ways to make `KEY_PAIR_INFO` agree with `DIGESTS`:

> The old solution uses a fixed configuration and requires slot 0/1/4.
> If you prefer to make slot 1/4 optional, the everything must be consistent.
>
> I am OK with option-1. Please validate carefully to ensure the final state
> is consistent. Since slot 0 is always there, we need to handle 4 cases {slot
> 1 and slot 4, slot 1 only, slot 4 only, no slot 1 or slot 4}.
> Also please validate for responder side cert and requester side cert in mut
> auth case.

### What was decided, and why

- **"Everything" was read as a list of places, before any code.** The
  Requester's per-slot chains, written three weeks earlier in `8674afe`, have
  #547's shape twice: `spdm_client_init()` stops at the first of its three
  chains that does not load, and the requester exits; the responder reads its
  copy of them into one `res` that slot 4's read alone decides, and that `res`
  decides whether mutual authentication is requested. And the requester exits
  without the root of the responder's slot 1 — candidate 22, held since
  2026-10-20 for exactly this answer. So there is a second commit, for the
  Requester's certificate, and 22 goes into it rather than on its own.
- **Option 1 had to be scoped to a connection.** It writes the sample
  library's key-pair table, which belongs to the process. A responder serves
  another requester after `--exe_mode CONTINUE`, or with `--serve_mode
  PERSIST`; and `libspdm_get_key_pair_id_by_slot()`, which reads that table,
  is what the sample library's key choice for KeyPairID 0 compares against —
  candidate 16's mechanism. So each connection first gives back what the one
  before it removed.
- **A rule the four cases showed was missing.** With `--req_slot_id 4` and no
  Requester slot 4, the responder printed that the slot's chain did not load,
  designated it anyway, and the requester's session failed
  (`LIBSPDM_STATUS_INVALID_MSG_FIELD`). The responder's own precedent, for
  slot 4 without multi-key, is not to request mutual authentication; it now
  does the same for any designated slot whose chain did not load.

### The change

Two unsigned commits on `9cc8b46`, branch `responder-slot-res-v4`, both
authored by the author, messages from the reviewed files:

| | |
|---|---|
| 1 | `spdm_responder_emu: provision each slot that loads` — v3's file and option 1: tree `fddf3f7` |
| 2 | `spdm_emu: provision each requester slot that loads` — both programs: tree `f193f1f` (the sign-off will give both commits new names, not new trees) |
| Diff | two files, +239 −76 against `main` |
| Checker | `check_upstream_commit.sh` on each: only the three sign-off lines, which are the author's to add |
| Texts | description 6,859 bytes, reply 2,188 bytes, title *spdm_emu: provision each slot that loads, on both sides* |

### Tested

Release builds, `CRYPTO=openssl`, of `main` and of each commit, run on their
own ports in parallel; every run decoded from its capture by a decoder that
now also reassembles chunked messages, and judged on what the two sides
report, not on exit status:

| Batch | Runs | What it shows |
|---|---|---|
| The Responder's four cases | 24 per build: `main`, commit 1 alone, the final build; and 4 of v3 | six modes each — `W_ENCAP`, `WO_ENCAP`, `DIGESTS`, ML-DSA-87, no multi-key on the responder's side, `--ver 1.2`. `main`: no slot without slot 4's chain, and the slots-0/1 key pair still claiming slot 1 without slot 1's; v3: the slot-4 key pair claiming slot 4 without its chain. Both commits: `DIGESTS` and `KEY_PAIR_INFO` agree in every run that has `KEY_PAIR_INFO` (1.2 has none) |
| The Requester's four cases | 80, `main` and the final build, each with the local sample-library change | ten modes each, including `--req_slot_id 1` and `4` with `W_ENCAP` and `WO_ENCAP`. `main`'s requester exits in the 30 runs without slot 1 or 4; the final build's `DIGESTS` to the encapsulated `GET_DIGESTS` is `0x13`, `0x03`, `0x11`, `0x01`, checked run by run against the case, and every session opens — mutually authenticated with the designated slot where the Requester has it, without mutual authentication where it has not |
| The same without the change to the sample library | 72 and 40, on the first and the final build | in the 56 that removed the Requester's slot-1 file, that removal changed nothing: the slot reads slot 0's file. Kept, as void for slot 1, and as how it was found |
| One-sided copies | 10 | without the responder's copy of a designated slot, `main` fails `FINISH` (`ERROR(DecryptError)`) and the change does not request mutual authentication; without the Requester's own, the session fails, as the responder cannot tell |
| Two connections on one responder | 4 builds × 4, and 4 controls | the give-back measured both ways, on commit 1 and on the final build: without it, the second connection, without multi-key, fails its `CHALLENGE` (`VERIF_FAIL`), with ECDSA P-384 and with ML-DSA-87; with nothing removed, the same two connections complete on `main` and on the final build |
| Upstream's workflow commands | 12 × 2 | identical to `main` but for `PCI_DOE`'s random `[PSK]` lines |
| `DEVICE=tpm` | 7 + 4 | CI configuration identical to `main`; one responder slot: `0x01`, KeyPairIDs 4 and 16 `0x01` and `0x00`; one slot on both sides: `main`'s requester stops at the root of slot 1, the change's completes |

### What else this found

- **Candidate 26**: on one responder, a `--ver 1.2` connection after an SPDM
  1.4 multi-key one fails its second session with `VERIF_FAIL` — on `main`,
  with nothing removed; two `--ver 1.2` connections in turn do not. It was
  the control for the give-back, which is therefore shown with a second
  connection at 1.4 without multi-key. Cause not read.
- **Candidate 27**: libspdm's sample library reads the Requester's slot 1
  from slot 0's file; `bundle_requester.certchain1.der` is generated and read
  by nothing. Asked in the prepared reply.
- ★ **My own instruments, twice.** The first matrix removed
  `bundle_requester.certchain1.der` for its Requester's slot-1 cases and
  never checked that the Requester's `DIGESTS` changed; it had not, and 56
  runs said nothing about slot 1. Found only because a slot-0 run printed a
  slot-1 line. And two of its two-connection cases had an empty second
  requester field, which the runner reads as one connection: 10 runs over two
  batches. Both re-run, the first with an assertion per run that the case
  reached the wire.

### Checked a second way, before sending

Asked for by the author, once the first pass had caught my instruments
twice. Nothing in the change moved; the evidence for one sentence was re-run.

| Angle | Compared | Result |
|---|---|---|
| The binary under each sentence | the source hashes each tested binary set records, against the two commits' blobs | the sets behind the tables are the commits' bytes. The sentence on the root of the responder's slot 1 had run only against the responder before its last edit, the designated-slot rule: re-run, three runs on the final binaries and `main`'s control, the same |
| A second decoder | DMTF `spdm-dump` `9d91f21`, unmodified, on all 459 captures; a second build of it, because the pinned one's `LIBSPDM_MAX_CERT_CHAIN_SIZE` (0x1000) stops it at the first ML-DSA-87 certificate chain, record 22, with exit status 0 | 457 agree with `wire.py` on every field compared: both sides' `DIGESTS`, every `KEY_PAIR_INFO`, `KEY_EXCHANGE_RSP`'s MutAuth and ReqSlotID, `FINISH`, the slot in `ENCAPSULATED_RESPONSE_ACK`, and the counts of `CHALLENGE_AUTH`, `FINISH_RSP` and records. The other two are the PQC probes summarised before `wire.py` reassembled chunks. From `spdm_dump` alone, the description's two tables come out the same |
| What else option 1 changes | every `KEY_PAIR_INFO` response, its mask blanked, against the same KeyPairID in the nothing-removed run of its group | 2,811 of 2,811 identical: only `AssocCertSlotMask` changes |
| CI's own configuration | `build_CI.yml`'s configure line — `CRYPTO=mbedtls`, and `LIBSPDM_DEBUG_LIBSPDM_ASSERT_CONFIG=3`, which turns an assert into exit 1 — from the commits' bytes: `main`, commit 1, commit 2 | each builds under `-Werror` with no warning but LTO's. The workflow commands (the default, `PCI_DOE`, `--ver 1.1` to `1.4`, the slot ID 0xFF capabilities) and the validator sample give `main`'s exit status and logs on both commits, but for `PCI_DOE`'s random `[PSK]` lines. On commit 2, the four cases, and the Requester without slot 4 with and without `--req_slot_id 4`, come out as the description says. Both decoders agree on every new MCTP capture, 28 with the re-runs above |
| What CI does that was not done here | the workflows, read | the tab check: no tab in either file. Asserts: the builds here print and spin, and none of 1,936 logs printed one (longest run 271 s, timeout 900 s). MSVC `/W4 /WX`: no compiler here; libspdm builds its own `uint8_t \|= (1 << n)` under the same flags, the new forms are cast, and no new name hides another. That one is CI's to show |

### What decides what goes next

- #550: the author reads the two commits, signs them (`git rebase --signoff
  9cc8b46`), and pushes on his word; then the title and description, and the
  reply, are his. Then the maintainer.
- 26: after #550. 27: the maintainer's answer. #552, 13, 24, 25 and 94773: as
  before.

## libspdm #4268 merged, and #550's fourth version sent — 2026-11-03

From 03:41 UTC. The author signed #550's two commits, gave the word for the
push, edited the title and the description, and posted the reply. Between
his sign-off and the push, the freshness check found libspdm #4268 merged.

### libspdm #4268, merged

| | |
|---|---|
| Merged | 02:49:06 UTC, by **Jiewen Yao** (`jyao1`), eighteen hours after it was opened; no review and no comment |
| Commit | **`b068d55`** on `0f72079`, libspdm `main`: the author's, committed by Jiewen Yao. Its diff and its message, as GitHub serves them, are byte-identical to `d8c077c`'s |
| In spdm-emu | not yet: spdm-emu's `main`, `9cc8b46`, pins libspdm `6cb52f2`, 50 commits behind `b068d55`. There `read_priv_key_pem.c` compares the KeyPairID with slot 4's alone (line 77), and slot 4's is 0 when it has no key pair; at `b068d55` KeyPairID 0 selects the default key first (lines 79–80) |

### #550's fourth version, sent

| | |
|---|---|
| Commits | **`3985d32`** and **`ddb5fd1`** on `9cc8b46`, signed by the author at 03:41:52 UTC, by a rebase onto `9cc8b46` that added the sign-off: trees `fddf3f7` and `f193f1f`, the bytes tested; each message the reviewed file with one line added, the sign-off; the author both author and committer. `check_upstream_commit.sh`: every rule satisfied on each |
| Push | at 03:56 UTC, run here on the author's word, after a freshness read at 03:55:40 UTC: forced over `b20e680`, v3, with a lease on it, by the script that also checks that `main` is still `9cc8b46` |
| Pull request | read back at 03:56:17 UTC: head `ddb5fd1`, two commits, two files, +239 −76 |
| Title, description, reply | edited and posted by the author, and read back at 03:58:36 UTC, each byte-identical to the reviewed file: *spdm_emu: provision each slot that loads, on both sides*; the description, 6,923 bytes; the reply, comment 6595072958 at 03:58:14 UTC, 2,252 bytes |
| Checks | **45 of 45** check runs success on `ddb5fd1`: DCO at 03:56:09 UTC, and 44 in GitHub Actions, the last at 04:20:59 UTC; `mergeable_state` clean. Read from the API |
| Outcome | in review |

### What the merge changed in the texts

- **One clause, twice.** The description, the reply and the first commit's
  message cite #4268 for why each connection gives back the slot the one
  before it removed: without that, a later connection without multi-key
  finds slot 4 with no key pair, and the sample library signs with slot 4's
  key for KeyPairID 0. At #550's base that is still so (above), and the
  give-back still needed. But its reader had merged the fix an hour before,
  and could have read the reason as gone. The description and the reply each
  gained *(DMTF/libspdm#4268 fixes that in libspdm; spdm-emu's libspdm,
  6cb52f2, predates it)*: 6,859 bytes to 6,923, and 2,188 to 2,252. The
  commit's message keeps *(DMTF/libspdm#4268)*, which is true of its own
  tree; a second sign-off would have bought nothing a reviewer needs.
- **Once spdm-emu's libspdm has it**, the give-back is no longer what keeps
  the second connection's key right: KeyPairID 0 then selects the default key
  whatever slot 4's key pair is. What it still does is start each connection
  with slot 4's key pair as a fresh responder has it: in the give-back runs,
  the second connection reports it at `0x10` again, KeyPairID 17 with ECDSA
  P-384 and 24 with ML-DSA-87. Not measured with `b068d55`; measured if the
  maintainer asks.
- **KeyPairID 1, in the same second connections**, reads `0x00` where the
  first read `0x03`. That is the requester's own `SET_KEY_PAIR_INFO` step,
  candidate 23's, which in the first connection sets KeyPairID 1's
  association to none and erases it; `main`'s two-connection controls show
  the same. Not the change's.

### What decides what goes next

- #550: the maintainer. A comment that comes back is read here first, and
  the reply is the author's.
- 26: after #550. 27: the maintainer's answer to the reply's question. #552,
  13, 24, 25 and 94773: as before.

## #550 approved, and the Requester's slot 1 sent to libspdm — 2026-11-07

Read at 16:16 UTC on 2026-11-06, past midnight here, after the author said
#550 seemed to have an answer and an approval. It had both, and two comments
before the approval, each asking for an issue.

### What the maintainer wrote

| | |
|---|---|
| 2026-11-05, 03:18 UTC | comment 6648743209, quoting the reply's second point, that the sample library reads the Requester's slot 1 from slot 0's file: *"This seems a bug. By design, slot 1 should only read slot 1 cert. Slot 4 should only read slot 4 cert. Could you please file an issue first? If you can also provide a PR to fix, that would be great. The cert chain can never be shared. The only shared element is key (slot 1 and slot 0 are using the same key)."* |
| 2026-11-05, 07:09 UTC | comment 6652019977, quoting the first point, that without the give-back a later connection without multi-key signs with slot 4's key: *"It seems another bug to me. If slot 4 has no cert, then slot 4 should not have key as well. And slot 4 should not be exposed at all. Why the code pick KeyPairID 0??? I think libspdm should fail, if slot 4 is requested, but no cert. Could you please file issue too?"* |
| 2026-11-06, 04:53 UTC | **approved**, on `ddb5fd1`, the fourth version, with no comment in the review; not merged when the reply below was posted at 18:26 UTC |

### The first: a bug, filed and fixed as asked

At libspdm `main`, `c2b2573`, the Requester's two per-slot chain readers,
added by #4149, still give slot 4 `bundle_requester.certchain4.der` and every
other slot `bundle_requester.certchain.der`; nothing about it upstream, open
or closed. The file slot 1 should read is in each of the 24 `sample_key`
directories the readers use (four other directories there have none), and in
each its leaf's SubjectPublicKeyInfo is byte-identical to slot 0's and its
root certificate is not — measured from the blobs, with a negative control,
one flipped byte, caught; `readme.txt` says the same of the leaf key. So the
change gives slot 1 a branch of its own, with slot 4's list of algorithms,
and the key slot 1 signs with does not change.

Measured in `spdm-emu` `9cc8b46` on libspdm `6cb52f2`, whose
`read_pub_cert.c`, `read_pub_cert_pqc.c` and sample keys are those of
`c2b2573`, both programs built before and after; the new file name is in the
binaries of exactly the two variants that have the change, 24 times each.
Every digest in `DIGESTS` was matched to the sample file it is the digest of.

| run | before | after |
|---|---|---|
| default flow, RSAPSS_3072 | the Requester's `DIGESTS` `0x13`: slot 1 is `certchain.der`, slot 0's digest | slot 1 is `certchain1.der`; 2,272 messages, KeyPairIDs 2,2,14 and the errors as before |
| ML-DSA-87, `--pqc_first TRUE` on the Responder | slot 1 is slot 0's | slot 1 is `certchain1.der`; 2,601 messages, the rest as before |
| `--req_slot_id 1`, W_ENCAP | `FINISH` ReqSlotID 1, final ACK slot 1, exit 0 | the same |
| `--req_slot_id 1`, WO_ENCAP | `KEY_EXCHANGE_RSP` `01/1`, `FINISH` ReqSlotID 1, exit 0, 2,260 messages | the same |
| with #550, `bundle_requester.certchain1.der` removed | `DIGESTS` `0x13`: slot 1 still there, from slot 0's file | `DIGESTS` `0x11`; both programs log that slot 1 is not provisioned; mutual authentication with slot 0 |

The W_ENCAP row shows no regression and no more: its encapsulated
`GET_CERTIFICATE` fetches slot 0's chain, and slots 0 and 1 share the key, so
the new chain is never checked against a root there. That is why WO_ENCAP is
in the table: no chain crosses the wire in that session, so what the
Responder has for the Requester's slot 1 is its own copy, which it reads with
the same function (`spdm_responder_spdm.c` 823–844 at #550's head).

libspdm itself, at `c2b2573`, Linux GCC Release, OpenSSL: the change builds
with `-Werror`, and every `test_*` program gives the same exit status and the
same cmocka summary with it and without it (`test_spdm_sample` fails two
cases on both). `script/format_nix.sh --check` on a clean export of the tree:
clean.

### The second: answered, not filed

The author left the call to me. The behaviour is the line #4268 changed, and
the reply of 2026-11-03 had said so, in a parenthesis. An answer costs the
maintainer one read; an issue for a line already fixed, by the author's own
#4268, costs him a triage and a close, and would say the author had not read
his own change. So the
reply answers it, with measurements, and offers the issue. Before writing it,
the hypothesis that would have made the 2026-11-03 reply wrong was measured
first ([LOG, Day 31](../../LOG.md)):

| #550 without the give-back; a multi-key connection without slot 4, then one without multi-key on the Responder's side | the second connection |
|---|---|
| libspdm `6cb52f2` | `CHALLENGE` fails, `80020001`, 14 messages; strace, in a second run: the one key file it opens is `ecp384/end_responder4.key` |
| `6cb52f2` with #4268's two files | passes, 2,272 messages; strace, in a second run: it opens a key file 46 times, every time `ecp384/end_responder.key` |
| `6cb52f2`, with the give-back | passes, 2,272 messages |

The same requester binary in all three, so the Responder's two sample files
are the one difference between the first two rows; and the first connection
of each shows `DIGESTS` `0x03`, slot 4 gone. And the other half of what he
asked for, that libspdm fail when slot 4 is requested with no chain:

| `--slot_id 4` on the Requester, #550's Responder | result |
|---|---|
| slot 4's chain removed | `DIGESTS` `0x03`; `GET_CERTIFICATE` for slot 4 answered `ERROR(InvalidRequest)`; 10 messages, `8001000a` |
| slot 4's chain there | `GET_CERTIFICATE`, `CHALLENGE` and both `KEY_EXCHANGE`s on slot 4; 2,270 messages, exit 0 |

`CHALLENGE` and `KEY_EXCHANGE` make the same check, in
`libspdm_get_response_challenge_auth()` and
`libspdm_get_response_key_exchange()`; read, not run. The second connection
above is "without multi-key" on the Responder's side only: its `ALGORITHMS`
response still carries bit `0x10`, which is the Requester's (`rsp_algorithms.c`
803), and its `DIGESTS` has neither slot 4 nor KeyPairIDs.

### Sent

| | |
|---|---|
| Issue | [`DMTF/libspdm` #4299](https://github.com/DMTF/libspdm/issues/4299), *spdm_device_secret_lib_sample: the Requester's slot 1 chain is read from slot 0's file*, opened by the author at 18:02:17 UTC; title and body read back byte-identical to the reviewed files |
| Commit | **`420fbce`** on `c2b2573`, signed by the author: tree `b187841`, the bytes tested; its message the reviewed file and his sign-off, ASCII, `Fix #4299.` The check that said so was first run on a throwaway clone with a fake identity, where it passed the right commit and caught each of four faults |
| Push | by the author, to a new branch of his fork, after a freshness read at 18:20:51 UTC: `main` still `c2b2573`, nothing else about it upstream, the branch absent |
| Pull request | [#4300](https://github.com/DMTF/libspdm/pull/4300), *spdm_device_secret_lib_sample: Read the Requester's slot 1 chain*, opened by the author at 18:23:07 UTC: head `420fbce`, one commit, +89 −0, title and body byte-identical; reviewers by `CODEOWNERS`, `steven-bellock` and `jyao1` |
| Reply | on #550, comment 6692282602, posted by the author at 18:26:27 UTC after #550 was read again at 18:24:12; byte-identical to the reviewed file, 1,708 bytes. Its rendered links are three, all to libspdm |
| Checks | **56 of 56** check runs success — DCO, 54 in GitHub Actions and CIFuzz's code-scanning check — the last at 18:41:01 UTC; `mergeable_state` clean. |

### What decides what goes next

- #550: its merge is the maintainer's. A comment that comes back is read
  here first, and the reply is the author's.
- #4299 and #4300: the same.
- When spdm-emu's libspdm moves past #4300, its Requester's slot 1 is
  `certchain1.der` there too. Nothing in spdm-emu's CI passes `--req_slot_id`.
- 26, #552, 13, 24, 25 and 94773: as before.

## #550 and libspdm #4300 merged, and candidates 25 and 28 prepared — 2026-11-11

Read from 11:42 UTC, when the author asked whether what he had sent had
merged, and for the next candidate. Two had; nothing else had moved.

### Merged

| | |
|---|---|
| #550 | merged 2026-11-09 at 01:43:20 UTC by **Jiewen Yao** (`jyao1`), by rebase, as **`30f9fc8`** and **`0e9d60c`** on `9cc8b46`, three days after his approval and with no comment. Trees `fddf3f7` and `f193f1f`; each commit's diff, as GitHub serves it (12,856 and 14,021 bytes), and its message (4,018 and 4,409 bytes) byte-identical to `3985d32`'s and `ddb5fd1`'s, the author's. #547 closed with it |
| libspdm #4300 | merged 2026-11-09 at 07:04:13 UTC by **Jiewen Yao**, as **`306502a`** on `ee4199f`, one commit past `c2b2573` that changes two CI workflow files and nothing else. `steven-bellock` had approved it on 2026-11-06 at 21:08 UTC without a comment, and there was no other review. Its diff (5,472 bytes) and message (2,495 bytes) byte-identical to `420fbce`'s. #4299 closed by it, as completed, two seconds later |
| Not moved | `openbmc/spdm` 94773, unchanged since 2026-09-23 17:10 UTC; #552, without a comment, label or assignee since it was opened on 2026-10-29 |

Every pull request this project has sent to `DMTF/spdm-emu` or `DMTF/libspdm`,
fourteen, is merged, each as it was sent.

### Candidate 25, chosen

Row 25 had said *after 16 and #550*, and on 2026-11-09 the second of the two
merged. It is a defect, not a design question; the change is two lines a
reviewer can check from the diff alone; and upstream has accepted the same
kind twice: #546, from this project, made an invalid argument exit 1, and
#290 made a failed flow exit 1, which is the rule this line breaks (below).
Of the other unsent rows, 24 is libspdm's question to ask before any change,
26's cause has not been read, 23 waits on #552, 13 is a conversation, 18's two
lines are an array the maintainer re-syncs himself, and 20 does not
reproduce.

Re-read at `0e9d60c`: `spdm_requester_emu.c` is the blob it was at `9cc8b46`,
`706d361`, and the assignment is at line 204. Searched upstream, open and
closed, for `exit code`, `exit status`, `exits 0`, `requester returns 0`,
`OOB_ENCAP_ENDPOINT_INFO`, `platform_client_routine` and two more: nothing
reports it. Of the two open pull requests, #496 adds sixteen lines to the
same file and has not moved since 2026-06-27; #490 touches the README.

### The rule the line breaks

[#265](https://github.com/DMTF/spdm-emu/issues/265), opened by
`steven-bellock` in 2023: CI reports success when a test fails. Its fix,
[#290](https://github.com/DMTF/spdm-emu/pull/290) (Wenxing Hou, merged on
2023-10-13 as `1c34eb0`), set `result` to false before the flow and to true
after its last step, made `main` return `!result`, and changed the
`SHUTDOWN` call at `done:` from `result = communicate_platform_data(...)` to
`if (!communicate_platform_data(...))`, because the first shape overwrites
the verdict. `8e33385` (Aaron Li, 2025-06-06) added the encapsulated
`GET_ENDPOINT_INFO` with the first shape. When its call succeeds, `result`
is true for the rest of the flow, and every later `goto done` reports
success. The same commit put the same seventeen lines in
`spdm_requester_session.c`, where `result` is a local the function does not
return, so nothing is lost there.

### The change

`ep-info-exit-status` in `~/spdm-lab/work/spdm-emu-epinfo`, unsigned
`6726982` on `0e9d60c`, tree `89da40a`: +4 −5 in
`spdm_requester_emu.c`, the call tested directly, as #290 tests it at
`done:`; with whitespace ignored the diff is two lines. From `result = false`
to `result = true`, nothing else assigns `result`. A failed call is still
reported, and the flow still goes on.

### Tested

Built six ways from the same sources, each source tree checked file by file
against `0e9d60c`'s tree and libspdm `6cb52f2`'s before it was compiled:
OpenSSL Release; the build of `build_CI_TPM.yml` (Debug, OpenSSL,
`DEVICE=tpm`, the library's default slots); and with mbedtls the
configuration of `build_CI.yml` (`LIBSPDM_DEBUG_LIBSPDM_ASSERT_CONFIG=3`),
`chunk_check.yml`'s 170-byte buffers, `RECORD_TRANSCRIPT_DATA_SUPPORT=1`, and
FIPS. In all six the requester binary changes and the responder binary is
byte-identical.

| OpenSSL, each run twice | `main` | with the change |
|---|---|---|
| `--asym RSASSA_2048` on both, #552's: `KEY_EXCHANGE` answered `ERROR(InvalidRequest)` | exit 0 | exit 1, the same 570 messages |
| the responder's `ecp384/end_responder4.key` given `end_responder.key`'s bytes: the session on slot 4 fails to verify, `80020001` | exit 0 | exit 1, the same 1,704 messages |
| each of the two with `EP_INFO` left out of `--exe_conn` (`GET_ENDPOINT_INFO` sent once, then not at all) | exit 1 | exit 1 |
| `--hash` mismatched, a failure before the step | exit 1 | exit 1 |
| a responder without `PSK_WITH_CONTEXT`, with and without `EP_INFO`: nothing fails | exit 0 | exit 0 |
| the default flow | exit 0 | exit 0 |

Every Linux requester and responder command line in `.github/workflows`,
28 runs on each of `main` and the change, one for each distinct command line and build, on the build its job makes, the
mixed pairs of `chunk_check.yml` and of the two `RECORD_TRANSCRIPT_DATA`
steps included: each gives the same exit status, 0, and the same messages on both, except the two where a requester built with `RECORD_TRANSCRIPT_DATA_SUPPORT=1` meets a responder built without it, the mbedtls job's and the FIPS job's. On `main` those exit 0 with candidate 28's two `ERROR` lines; with the change, 1, with the same 1,712 messages; with 28's line as well, 0, twice each. The captures were compared by every message's code
and by the length of every plain message; two runs of one binary differ in the
length of most secured messages and of the CSR, whose ECDSA signature is DER,
and with 170-byte buffers in the length of the CSR's last chunk (measured: one
binary run twice, the one plain difference), so those are compared by code only.

### Candidate 28, found in the log 25 hides

To cite that the workflows judge the requester by its exit status rather than
assume it, the log of `0e9d60c`'s own run of `gcc_mbedtls_build` (run
42547056500) was read: its steps run under `/usr/bin/bash -e {0}`. And in
`Test_RECORD_TRANSCRIPT_DATA_consistent`, after the echo *requester
(DATA_SUPPORT = 1) <=> responder (DATA_SUPPORT = 0)*, the step that passed
prints `ERROR: libspdm_start_session - 8001000f` and `ERROR:
do_session_via_spdm - 8001000f`. `EMU_ERR` writes to stderr (`spdm_emu.h`
87–88), which the step does not redirect. `8001000f` is
`LIBSPDM_STATUS_SESSION_MSG_ERROR`, *Decrypt error from peer*.

| question | answer |
|---|---|
| #550's? | no: the same lines at `9cc8b46`, before it, and at `f7fa183` |
| how often | in all four jobs that run the step (`build_CI.yml` and `build_CI_FIPS.yml`, mbedtls and OpenSSL), in each of the 109 runs of `main` that got that far, from `64cf999` on 2026-08-17, the oldest log GitHub still serves, to `0e9d60c` on 2026-11-09; one more was cancelled before that session |
| reproduced here | the mbedtls requester built with `-DLIBSPDM_RECORD_TRANSCRIPT_DATA_SUPPORT=1` against the CI-flag mbedtls responder: the same two lines, exit 0 |
| where | the second `KEY_EXCHANGE` session, on slot 4, with mutual authentication (`MutAuthRequested` `0x02`, `ReqSlotIDParam` 0): the encapsulated `GET_DIGESTS` and `GET_CERTIFICATE` complete, and `FINISH`, 438 bytes as in the passing session on slot 0, is answered `ERROR(DecryptError)` |
| slot 4's session first (`--slot_id 4`) | fails, first |
| no `PSK` session between the two | slot 0 passes, slot 4 fails |
| both programs built with the option | slot 0 passes, slot 4 fails |
| the responder's `--mut_auth NO` | both pass |
| the responder's `--mut_auth WO_ENCAP` | slot 4 fails |
| which key the requester signs with | strace: `rsa3072/end_requester.key` only, as in the control |

Then read. `libspdm_send_receive_finish()` calls
`libspdm_generate_finish_req_signature()` with `req_slot_id_param`, the
requester's own slot. With `RECORD_TRANSCRIPT_DATA_SUPPORT`, that function
looks up the *responder's* chain for the transcript it signs with that
parameter, where its two siblings in `libspdm_req_finish.c`,
`libspdm_verify_finish_rsp_hmac()` and `libspdm_generate_finish_req_hmac()`,
use `session_info->peer_used_cert_chain_slot_id`. They were changed to it by
libspdm [#3435](https://github.com/DMTF/libspdm/pull/3435) (`0f0e189`,
2025-12-19), for [#3434](https://github.com/DMTF/libspdm/issues/3434), *"For
`KEX_EXCHANGE`, `peer_used_cert_chain_slot_id` needs to be preserved across
multiple messages within a session"*; this function's lookup gained a slot
argument there, from its parameter, which `13db5117` had made the requester's
slot seven weeks before, when it removed the line that set it to the
responder's: the commit the fix answers, as `steven-bellock` pointed out once
it was sent ([§](#28-and-25-sent-and-28s-fixes-corrected--2026-11-11)).
Without the option the requester signs the
running transcript hash, so only that build is affected, and only when the
session's responder slot differs from the requester's own. The file is the
same blob at `6cb52f2` and at libspdm `main`, `839bc24`.

Measured by intervention: the one line, `slot_id =
session_info->peer_used_cert_chain_slot_id;`, before the lookup, as its
siblings have it, in the requester's build alone, and every failing run above
passes, slot 4's `FINISH` answered `FINISH_RSP`, twice for the default flow.
libspdm's own unit tests at `839bc24`, OpenSSL, Release, give the same exit
status and the same cmocka summary with it and without it, in the default
configuration and with `LIBSPDM_RECORD_TRANSCRIPT_DATA_SUPPORT=1`;
`test_spdm_sample` fails the same two cases in each, as it did on 2026-11-07.
A first run of the second configuration, on mbedtls, also failed certificate
cases on both: its build directory had not had the sample certificates staged
(`copy_sample_key`, which libspdm's own workflow runs). Prepared in libspdm as `finish-signature-peer-slot`, unsigned
`4068033` on `839bc24`, tree `53cdef6`, +1; `script/format_nix.sh --check` on a clean
export of it returns 0. Searched upstream for the function, the field, the
option with *finish*, *slot* and *mutual*, and `8001000f`: nothing.

### What else this found

- **The verifier of the build stopped it twice, once wrongly.** Before
  compiling, the build script hashes every file of `0e9d60c`'s tree, and of
  libspdm `6cb52f2`'s, in the source tree it is about to build. Its first
  run found 25 files different; every one had carriage returns, and
  `git hash-object` run from inside this repository applies this
  repository's `eol=lf` to any file it is given: `010c806` for a README whose
  blob is `ed55ed7`, which `--no-filters`, or the same command from `/tmp`,
  gives. With `--no-filters`, from `/`, the tree matched in full. The second
  run found one file different, and that one was real: the copy of the tree
  built for #550's CI comparison on 2026-11-03 still carried that day's probe,
  a loop asking for every KeyPairID, in `spdm_requester_key_pair_info.c`. The
  probe's build had recorded it, every other build that day had recorded
  `main`'s blob, and nothing had been built from that copy since; it was put
  back, and the probe kept aside. [LOG, Day 32](../../LOG.md).
- **A case planned as a second failure was not one.** A responder without
  `PSK_WITH_CONTEXT` exits 0 on both builds with no error: the requester
  leaves out every step the responder's capabilities do not cover
  (`spdm_requester_spdm.c` 474–526), and sent no `PSK_EXCHANGE`. It stays in
  the table as a run where nothing fails. The second failure is the key
  mismatch instead, which no capability can route around.
- **247 `ERROR` responses in #552's run, and one is the session's.** 246
  answer `GET_MEASUREMENTS` for indices the sample has no block for, the
  default flow's own enumeration, all `InvalidRequest`; the 247th answers
  `KEY_EXCHANGE`.

### What decides what goes next

- 28 and 25, together, 28 first: libspdm's issue, so that 28's commit can say
  `Fix #N`; then 28's pull request; then 25's, whose description names both
  and says before anyone asks which four jobs it turns red, and why. Every
  step is the author's: the issue, the two sign-offs, the word for each push,
  the two pull requests. Until spdm-emu's libspdm has 28, those four jobs stay
  red on 25.
- #552: no answer in thirteen days; a reply there, or a ping, is the
  author's call.
- 24: now that 16 has merged, a question to libspdm: whether the sample's
  chain readers should take the chains of the six larger SLH-DSA sets.
- 26: its cause, read before anything is sent. 13, 18, 20 and 94773: as
  before.

## 28 and 25 sent, and 28's `Fixes:` corrected — 2026-11-11

From 17:10 UTC, the same evening. Each step was the author's keystroke or
word; each text was read back after it was posted and compared byte for byte
with the reviewed file; each push came after a read of upstream made minutes
before it.

### Sent

| UTC | |
|---|---|
| 17:10:31 | libspdm issue [#4312](https://github.com/DMTF/libspdm/issues/4312): title and body, 2,645 bytes, byte-identical |
| 17:19 | 28, signed by the author as `d65fe0e` (tree `53cdef6`, parent `839bc24`), pushed to a new branch of his fork, after a read at 17:19:14: no comment on #4312, nothing else opened in libspdm since 17:10, `main` `839bc24`, `libspdm_req_finish.c` blob `fab65a3`, no branch of that name |
| 17:22:33 | libspdm [#4313](https://github.com/DMTF/libspdm/pull/4313): title and body, 1,611 bytes, byte-identical; one commit, one file, +1 −0; `steven-bellock` and `jyao1` requested by `CODEOWNERS` |
| 17:33:06 | `steven-bellock` on #4312: the defect was introduced by `13db5117` (below) |
| 17:35:07 | `steven-bellock` approves #4313, without a comment |
| 17:38:37 | #4313's last check run completes: 56 of 56 success, CIFuzz among them |
| 17:52:40 | 28, re-signed by the author as `6495195` with its `Fixes:` line alone changed, the same tree, replaces `d65fe0e` with a lease, after a read at 17:51:59: #4313 open, its head `d65fe0e`; `main` moved to `9741bd5` at 17:33:59, dependabot's #4311, two workflow files, and `libspdm_req_finish.c` the same blob. The approval stays, now on `6495195` |
| 17:58:20 | the author's reply on #4312, 218 bytes, byte-identical |
| 18:07:22 | `6495195`'s last check run: 56 of 56 success |
| 18:09 | 25, signed by the author as `ab7ed0a` (tree `89da40a`, parent `0e9d60c`), pushed to a new branch of his fork, after a read at 18:08:54: spdm-emu `main` `0e9d60c`, `spdm_requester_emu.c` blob `706d361`, nothing opened since 17:58, no branch of that name |
| 18:10:36 | [#553](https://github.com/DMTF/spdm-emu/pull/553): title and body, 3,187 bytes, byte-identical; one commit, one file, +4 −5; `steven-bellock` and `jyao1` requested. It names libspdm #4312 and #4313 in full, and each shows the reference |
| 18:33:54 | #553's last check run: 41 of 45 success. The four that failed are `gcc_mbedtls_build` and `gcc_openssl_build` of *Version latest with Certificates* and of *FIPS*, each at `Test_RECORD_TRANSCRIPT_DATA_consistent`, as its description says, and no other. In the first two, the step after it, `Emu_PCIDOE_Test`, did not run; its command lines were among 2026-11-11's runs on the same two builds, and exit 0 before and after, with no `ERROR` line and the same 2,546 messages |

The one other open pull request on `spdm_requester_emu.c`, `jyao1`'s #496,
open since 2026-06-04 and in conflict with `main`, adds declarations and a
step early in `platform_client_routine()`, and assigns `result` nowhere.

### Where 28 came from

`steven-bellock`'s comment, in full: *"To be clear though, this issue was
introduced by https://github.com/DMTF/libspdm/commit/13db5117#diff-c12ea915…"*;
the anchor is the SHA-256 of `library/spdm_requester_lib/libspdm_req_finish.c`.
The commit had ended `Fixes: 0f0e189e8cd4 ("Add
peer_used_cert_chain_slot_id to session_info")`, his #3435. Read in the lab's
libspdm:

- **`13db5117`** (Jiewen Yao, 2025-10-29, *Add key_pair_id param for
  signing HAL API for multi-key.*) gave
  `libspdm_generate_finish_req_signature()` a `slot_id` parameter, which
  `libspdm_send_receive_finish()` sets to `req_slot_id_param`, for the key
  pair the requester signs with, and removed
  `slot_id = spdm_context->connection_info.peer_used_cert_chain_slot_id;`,
  the line that had set it to the responder's slot before the responder's
  chain is read.
- **`0f0e189`** (2025-12-19) gave `libspdm_get_peer_cert_chain_buffer()` a
  slot argument. The two sibling functions pass it
  `session_info->peer_used_cert_chain_slot_id`, which it added; this one
  passes `slot_id`, by then the requester's.

Between the two, the wrong slot decided only whether the responder's raw
public key or its chain went into the transcript; from `0f0e189` on, it also
chose the chain. The line #4313 adds is the line `13db5117` removed, with
`0f0e189`'s field: he is right, and `Fixes:` now names `13db5117`. The
function's own history says so: `git log -L` over it, at `839bc24`, lists four
commits whose diffs of it touch `slot_id` — `0f0e189`, `16bbbc7`, `13db5117`
and `5de7be0` — and `git log -S` on the removed line lists three, of which
`13db5117` took it out of this function. That history was not read on
2026-11-11: the comparison began at the two siblings, and `0f0e189` is where
they changed.

The correction changed that line and nothing else (`diff` of the two
messages: one line each way). libspdm's commit-message check asks only for
ASCII, and its `main` has `Fixes:` lines of up to 90 characters; this one is
80. The push script checked, before it pushed, that the two trees are equal,
that the messages differ in that line alone, and that the fork still had
`d65fe0e`, which the lease repeats. The author's reply on #4312: *"Thanks,
that's right: 13db5117 made `slot_id` the Requester's slot and removed the
line that had set it to the Responder's, before the Responder's chain is read.
#4313's `Fixes:` now names 13db5117 instead of 0f0e189."*

### What else this found

- **A watcher that knows which red is expected.** 25 turns four jobs red on
  purpose, so a watcher that stops at the first failure would stop at the
  expected one. The one written for #553 takes the expected failures as
  *workflow / job* and failed step, stops at any other, and at the end reports
  any expected failure that did not happen. It was run before it watched
  anything: on a commit with a real failure and nothing expected, it named
  *Version 1.3 with Certificates / gcc_openssl_build*, step *Build*; on
  `main`, green, with 25's four expected, it reported all four as not having
  failed.
- **The signing check printed a wrong label.** `v1111_signed.sh` said
  *parent = main 0e9d60c* while checking 28 against `839bc24`, which it did
  compare. It prints the parent it compares now; its self-test still passes,
  seven of seven.
- **A message-only force-push kept the approval** on libspdm, measured once:
  the review reads `APPROVED` on `6495195`.

### What decides what goes next

- #4313: `jyao1`'s merge. #553: its review. Until spdm-emu's libspdm includes
  #4313, the four `Test_RECORD_TRANSCRIPT_DATA_consistent` jobs stay red on
  #553, as its description says.
- Eleven of the twenty-eight are not sent as changes. The next are as before:
  24, a question to libspdm; 26, whose cause has not been read; and 23, which
  waits on #552, without an answer since 2026-10-29.

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

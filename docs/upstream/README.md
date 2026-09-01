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
| Second candidate found, evidence assembled | **done** | 2026-08-17 | `DMTF/spdm-emu` `--help` disagrees with its own defaults — see below |
| Third and fourth candidates found, each with a capture | **done** | 2026-09-01 | `spdm-emu`: a discarded slot-0 read result, and a requester that never inspects `NO_AUTHORITY` — see below |
| SPDM 1.5 hybrid-PQC public review read, feedback drafted | **done** | 2026-08-31 | [`spdm15-hybrid-feedback.md`](spdm15-hybrid-feedback.md); the WIP itself, 8 pages, `sha256 3e5366a3…` |
| …submitted to the DMTF Feedback Portal | **`TODO(me)`** | | needs a portal account; deadline is 2026-08-31 |
| **This project's** first change submitted | not started | | scheduled W03 → **slipped**, see below |
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

`spdm_emu/spdm_requester_emu/spdm_requester_spdm.c` calls
`libspdm_get_certificate()`, the form that discards the `trust_anchor`
out-parameters, and tests `LIBSPDM_STATUS_IS_ERROR`. `grep -rn 'NO_AUTHORITY\|
trust_anchor' spdm_emu` returns nothing.

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

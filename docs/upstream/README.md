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
| OpenBMC's requirements read, from `openbmc/docs` `CONTRIBUTING.md` | **done** | 2026-09-18 | **no AI policy exists**: the word does not appear in the file, sha256 `e27c7768…`. Gerrit, a `Change-Id` from the commit-msg hook, a full real name in the sign-off, 50/72, and a CLA that is separate from the DCO. Encoded as `harness/check_upstream_commit.sh --profile openbmc`, with six cases it must refuse |
| **This project's** target repository built locally | **attempted** | 2026-08-11 | five distinct blockers, below |
| Second candidate found, evidence assembled | **done** | 2026-08-17 | `DMTF/spdm-emu` `--help` disagrees with its own defaults — see below |
| Third and fourth candidates found, each with a capture | **done** | 2026-09-01 | `spdm-emu`: a discarded slot-0 read result, and a requester that never inspects `NO_AUTHORITY` — see below |
| Fifth candidate found while writing a proxy | **done** | 2026-09-10 | `spdm-emu`: `command.h` documents the socket payload as starting at the SPDM header when a transport byte precedes it — see below |
| Sixth through twelfth found by running the published example | **done** | 2026-09-12 | `spdm-emu`'s `spdm_device_verifier_tool` does not work: **seven** findings, and the two that matter are in one function and mask each other — `verify` has never verified a signature, and would accept any signature if only the first were fixed. See below |
| Thirteenth found while pinning an A/B's control variables | **done** | 2026-09-14 | `spdm-emu`: `--req_asym NONE --req_pqc_asym NONE` parses, echoes back, and then makes the handshake impossible — the responder requires exactly one requester signature algorithm whenever `MUT_AUTH_CAP` is supported, and `--mut_auth NO` does not clear that capability bit. Six packets and a bare status code. See below |
| Fourteenth through seventeenth, from measuring across the transport | **done** | 2026-09-14 | `spdm-emu`: `--cap` is parsed by the requester and never read; every invalid argument exits **0**; **no signed operation completes with SLH-DSA** on a default build that ships its sample certificates; and `DataTransferSize` — the parameter that decides round trips — has no flag, for which a 55-line patch with a control exists. See below |
| Eighteenth and nineteenth, from the official conformance suite | **done** | 2026-09-20 | `spdm-emu`: the validator sample's configuration array and the `SPDM-Responder-Validator` submodule it configures disagree **in both directions** — three implemented cases are never requested, including the only two that test SPDM 1.3, and one requested case does not exist and prints nothing. And `SPDM-Responder-Validator` itself: a case whose message mask omits `GET_CERTIFICATE` reports the device's **valid** signature as FAIL, because the case's own `libspdm_init_connection` freed the chain its setup fetched. **Proved**, not argued — `harness/challenge_verify.py` verifies the disputed signatures against the leaf key after calibrating on the ones the suite accepts. See below |
| SPDM 1.5 hybrid-PQC public review read, feedback drafted | **done** | 2026-08-31 | [`spdm15-hybrid-feedback.md`](spdm15-hybrid-feedback.md); the WIP itself, 8 pages, `sha256 3e5366a3…` |
| …submitted to the DMTF Feedback Portal | **`TODO(me)`** | | needs a portal account; deadline is 2026-08-31 |
| **This project's** first change **SENT** | **done** | prepared 2026-09-12, **sent 2026-09-22** | [`DMTF/spdm-emu` #524](https://github.com/DMTF/spdm-emu/pull/524) — `CoRimTool.py verify` does not verify. Rebased onto `16119ea` and every `Tested:` line re-asserted in the hour before the push; `patch-id` and blob came through unchanged. DCO check green. Reviewers assigned by CODEOWNERS: **jyao1**, **steven-bellock**. See [`0001-corim-verify.md`](0001-corim-verify.md) §8 |
| **This project's** second change **SENT** | **done** | prepared 2026-09-18, **sent 2026-09-22** | [`openbmc/spdm` 94773](https://gerrit.openbmc.org/c/openbmc/spdm/+/94773) — a first `README.md`, written against the review that killed the 2025 attempt. Upstream `main` had **not** moved; both linters had vanished from the machine and were reinstalled at their pinned versions and re-run clean. See [`0002-openbmc-readme.md`](0002-openbmc-readme.md) §10 |
| **This project's** first change submitted | **done** | 2026-09-22 | scheduled W03 → slipped → prepared W06 → prepared W09, two of them → W10 re-verified both against an unchanged upstream → **both sent on the same day, each after its own freshness check, and one of those checks changed what was sent** (0001 was rebased; 0002's linters had to be reinstalled before they could agree) |
| Reviewer response received | not started | | two threads are open. `DMTF/spdm-emu` last merged something this week; `openbmc/spdm` last merged on 2026-07-31 with 37 changes open, so silence there is the expected outcome rather than a failure |

> **Not a deliverable of this project.** A change to `openbmc/docs` was
> submitted on 2026-08-11 under the other project. It appears nowhere in this
> repository's results and is mentioned only because of what it removes: the
> path from `git commit -s` to a change sitting in Gerrit has been walked once
> already, so what this project still owes upstream is a technical problem, not
> an administrative one.

## Two upstreams, two processes, and the paperwork does not carry over

Worth its own section because it was a live confusion on 2026-09-13, the day
before the first change was due to be sent: *"do I need to sign a CLA? is this
the same as OpenBMC's Gerrit?"*

**No, and no.** They share exactly one thing — the `Signed-off-by` line — and
differ in everything else.

| | `openbmc/spdm` | `DMTF/spdm-emu` |
|---|---|---|
| submission | **Gerrit**, `git push …:refs/for/master` | **GitHub pull request** |
| `Change-Id` | required, from the `commit-msg` hook | not used |
| **CLA** | **required.** Individual CLA to `manager@lfprojects.org`, one per person, covering every OpenBMC repository | **none. The word does not appear in `CONTRIBUTING.md`** |
| DCO | required | required — DSP4014, real name, address you can be reached at, **matching the commit author** |
| AI assistance | no stated policy found | **`Assisted-by: AGENT_NAME:MODEL_VERSION` required**, and an AI must NOT appear in `Signed-off-by` or `Co-authored-by` |
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
cbor>=1.0.0     pycose>=0.1.2     cose>=0.9.dev8     cryptography>=2.3
```

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

**What is left is SPDM-signature verification on the requester.** The libspdm
status is not recoverable from this build: `TARGET=Release` compiles
`LIBSPDM_DEBUG` out, so the requester exits 1 having printed nothing at all — an
observation in its own right, and the reason a `Debug` rebuild is the next step
rather than a guess about `slhdsa_ext.c`.

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

### ⑲ ★ A conformance case reports FAIL for an input it discarded itself

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

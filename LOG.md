# Engineering log

Working notes, newest last. Each technical entry uses the same five parts:

**現象** what was observed ·
**假設** what it could have been ·
**先驗哪個、為什麼** which hypothesis was tested first and on what grounds ·
**根因** what it actually was ·
**教訓** what changes as a result

The third line is the one that matters. Anyone can list what they tried.
Choosing *which* hypothesis to test first, and being able to say on what
grounds, is the difference between an entry the next reader can reuse and one
they can only re-run.

Entries marked **`TODO(me)`** are placeholders for things only I can write —
what I read, what I concluded, how the drill went. They are left blank rather
than filled with something plausible.

**The dates are the real ones.** Every heading below carries the date its work
was done, and `git log` agrees: `harness/verify_repo.sh` requires at least one
commit authored on the date of every heading in this file. Week labels — `W10`,
`W11`, `plan/W11` — name units of the schedule, not days. Two entries carried
plan-calendar dates instead until 2026-09-22 and were corrected then; the
measurement and the reasoning are in
[`docs/decisions/0012-two-calendars-and-which-one-governs.md`](docs/decisions/0012-two-calendars-and-which-one-governs.md).

---

## 2026-08-11 · Day 1 · environment baseline

### Where the work happens: WSL2, not Docker, not native Windows

**現象** Host is Windows 11. Three plausible build environments: MinGW natively,
Docker Desktop, WSL2. Docker Desktop's daemon was not running; WSL2 with
Ubuntu 24.04.4 LTS was already up, with cmake 3.28.3, gcc 13.3, make 4.3,
python3 3.12, meson, ninja and shellcheck already installed.

**假設** (a) native Windows toolchain, (b) Docker, (c) WSL2.

**先驗哪個、為什麼** (c) first, because it was the only one already
functioning and because the failure mode of the other two was known to be
expensive: libspdm's CMake presets target GCC/Linux, and Docker Desktop on
Windows runs its Linux containers *inside* WSL2 anyway, so choosing Docker as
the primary environment would add a layer without removing one.

**根因** Not a fault — a choice. Recorded because "why not Docker" is a
reasonable question and the answer needs to be on record.

**教訓** WSL2 is the interactive environment; Docker is kept as the *hermetic*
one for CI and for anyone reproducing this on a different machine. Same
scripts, two entry points. Written up as
`docs/decisions/0002-wsl-and-docker-parity.md`.

Two consequences that had to be handled rather than discovered later:

- **Build trees go on ext4, never `/mnt/c`.** Compiling OpenSSL means tens of
  thousands of small file operations, and `/mnt/c` reaches NTFS through a
  9P protocol layer. `LAB_DIR` therefore defaults to `~/spdm-lab` while the
  repository itself can live anywhere.
- **Line endings.** The repo sits on NTFS but every script is run by bash.
  `.gitattributes` forces LF before the first `git add`, because after that
  point the index has already recorded whatever it first saw.

### Gerrit was already configured — by the other project

**現象** `ssh openbmc.gerrit` returned
`Hi Chung-Wei Lan, you have successfully connected over SSH.`
`~/.ssh/config` already had the `openbmc.gerrit` host block, and an ed25519
key was in place from 2026-08-04.

**根因** A separate OpenBMC project set this up. One Gerrit identity and one
CLA cover every OpenBMC repository, so this half of the upstream preparation
was already done.

**教訓** Two things follow, and the second one is a trap that would have
surfaced months later:

1. Gerrit's full name is the legal name, and the WSL git identity matches it
   (`Chung-Wei Lan`). Good — DCO requires the `Signed-off-by` line to match.
2. **The Windows-side git identity did not match** (`Jhongwe1`, an account
   handle). Any commit authored from the Windows side of the same machine
   would carry a `Signed-off-by` that Gerrit rejects. Fixed by aligning both.
   Nothing about this failure would have pointed at its cause.

**Resolved same day.** The Individual CLA was sent to
`manager@lfprojects.org` on **2026-08-04** under the other project, and one
agreement covers every OpenBMC repository. The Gerrit account, SSH key,
`commit-msg` hook and a rehearsed `%private,wip` submission were all completed
in the same window. Dates and evidence are in
[`docs/upstream/README.md`](docs/upstream/README.md).

So the item that was supposed to be day one's urgent one — the thing with a
queue in front of it — was already finished before this project started. Worth
noticing why: the queue was not shortened, it was simply entered earlier, fo
a different reason. Gate 7's remaining risk here is entirely technical.

One detail from that setup is worth carrying because it is the same mistake
this machine made again today: signing in to Gerrit with GitHub OAuth
populated the profile's full name from GitHub rather than the legal name, and
nothing indicates the problem until a `Signed-off-by:` is rejected. An identity
written down in one place and assumed everywhere else — which is exactly what
the Windows and WSL git configurations were doing this morning.

### A clone that looks like a hang

**現象** `git clone --recurse-submodules` on spdm-emu ran for well over ten
minutes, printing `Cloning into '...openssl/wycheproof'`,
`.../krb5`, `.../boringssl`, `.../tlsfuzzer` — none of which have anything to
do with SPDM.

**假設** (a) network stall, (b) genuinely that much data.

**先驗哪個、為什麼** (b), because it was checkable in one command without
interrupting anything: `du -sh` on the target directory. If the number is
growing, it is not stalled. It was growing, and reached 2.5 GB.

**根因** The dependency tree is deeper than it looks. `spdm-emu` carries
`libspdm`; it *separately* carries `SPDM-Responder-Validator`, which carries
its own copy of `libspdm`; `libspdm` vendors OpenSSL; and OpenSSL vendors its
own test tooling. Net effect: OpenSSL is downloaded twice, along with several
large test corpora.

**教訓** Two changes. `harness/build_spdm_emu.sh` gained `--seed-from`, so the
second flavor copies the first tree instead of paying the download again —
the flavors differ only in which libspdm tag is checked out. And the runbook
now states up front what this looks like and how to tell a slow clone from a
stuck one, because "it looks stuck but is not" is exactly what a runbook is
for.

### Editing a shell script while it is running

**現象** The build reported exit status 0, but the last line of output was
`harness/build_spdm_emu.sh: line 72: or,: command not found`. Line 72 is a
comment. No binaries were produced.

**假設** (a) a quoting bug in the script, (b) file corruption, (c) something
about how the script was being read.

**先驗哪個、為什麼** (c), because (a) and (b) cannot produce *this* symptom.
A comment line cannot be executed by a correct reader under any quoting
mistake — the `#` is consumed before word splitting. The only way a comment
becomes a command is if the reader's file offset no longer corresponds to the
file's content.

**根因** Two things, compounding.

1. **bash reads a script lazily.** It reads a block, executes it, then
   continues reading from the current byte offset. The script was edited
   during the ten-minute clone, every subsequent byte shifted, and bash
   resumed mid-line — executing the tail of a comment as a command.
2. **The exit status was a lie.** The script ran as
   `bash build.sh 2>&1 | tee log`, so the pipeline's status was `tee`'s,
   which succeeded. The failure was invisible to any caller checking `$?`.

**教訓** Do not edit a script that is currently executing; wait, or copy it
first. And a pipeline's exit status is the *last* command's — checking a build
through `| tee` without `set -o pipefail` or `PIPESTATUS` reports success fo
a build that failed. That second point is worth more than the first: it is a
silent-wrong-answer class of bug, and it is the same class as the reason
`bench/data/*/manifest.json` exists.

### Things the environment cannot do, recorded now rather than discovered late

| Capability | State | Consequence |
|---|---|---|
| system OpenSSL ML-DSA | absent — 3.0.13, needs ≥ 3.5 | affects only signing our own certificate chain in W03. libspdm builds its own OpenSSL, so the handshake and the PQC work are unaffected |
| `CONFIG_MCTP` in kernel | not set — WSL2 kernel | the `AF_MCTP` transport path is unavailable; main line unaffected |
| QEMU with `spdm_port` | not installed | the QEMU transport path is unavailable; main line unaffected |
| `tshark` | not installed | not needed — capture analysis is done by `harness/pcapcount.py`, which has no dependencies and is the seed of the analysis tool this project has to write anyway |

### The minimal handshake was not minimal, and the flag that mattered was the other one

**現象** `--exe_conn DIGEST,CERT,CHAL,MEAS` — supposedly the smallest useful
attestation flow — produced **1116 packets, 61,807 bytes, 53 seconds**, and the
requester exited 1 with:

```
ERROR: libspdm_set_certificate - 80010001
ERROR: do_certificate_provising_via_spdm - 80010001
ERROR: do_session_via_spdm - 80010001
```

**假設** (a) the sample key material is incomplete, (b) `--exe_conn` was not
parsed the way I read it, (c) something outside `--exe_conn` is running.

**先驗哪個、為什麼** (b) first — one line of output settles it, and if the
argument had not taken, nothing else is worth investigating. The emulato
echoes `exe_conn - 0x0000001e`, and the header defines
`DIGEST 0x2 | CERT 0x4 | CHAL 0x8 | MEAS 0x10` = `0x1e`. Parsed correctly.
That eliminated (b) and made (c) the only hypothesis consistent with an erro
inside `set_certificate`, which is `SET_CERT` — a flag that is *not* in `0x1e`.

Reading the source rather than guessing at flags:

```c
/* spdm_requester_emu.c — the session block, entered because the
   transport is not NONE and KEY_EX is set */
if ((m_exe_session & EXE_SESSION_KEY_EX) != 0) { do_session_via_spdm(false); }
if ((m_exe_session & EXE_SESSION_PSK)    != 0) { do_session_via_spdm(true);  }
```

**根因** `--exe_session` is a second flag with its own default, and its default
is **fourteen operations**:
`KEY_EX,PSK,KEY_UPDATE,HEARTBEAT,MEAS,MEL,DIGEST,CERT,GET_CSR,SET_CERT,GET_KEY_PAIR_INFO,SET_KEY_PAIR_INFO,EP_INFO,APP`.
All of it runs inside an encrypted session that a connection-phase attestation
flow does not need at all, and `SET_CERT` within it fails on the sample key
material. Constraining `--exe_conn` while leaving `--exe_session` at its
default constrains the smaller of the two.

Measured, same `--exe_conn` both times:

| `--exe_session` | packets | bytes | duration | exit |
|---|---:|---:|---:|:--:|
| default (14 operations) | 1116 | 61,807 | 53 s | **1** |
| `NO_END` (no session established) | 554 | 20,549 | 24 s | **0** |
| `KEY_EX` (one clean session) | 578 | 30,834 | 27 s | 0 |

`NO_END` is used because the parser has no token meaning "nothing", and
`NO_END` (0x4) sets neither `KEY_EX` (0x1) nor `PSK` (0x2) — the only two flags
that cause a session to be established at all. That is a side effect of the
flag rather than its purpose, so it is commented at the point of use.

**教訓** Three, and the third is the one worth carrying:

1. Cutting the output down is the right instinct, but only if you find *every*
   knob. One default left alone doubled the capture and broke the run.
2. Read the source for flag semantics. The help text lists the names; it does
   not say that two flags gate two different phases, and it does not say which
   phase an error came from.
3. **An exit status is not a verdict.** The requester does more than the
   handshake, so its status answers a broader question than the one being
   asked. `harness/healthcheck.sh` was changed to check the evidence as well —
   error lines in the log, packet count in the capture — because "exit 0" and
   "the thing I wanted happened" are different propositions. This is the same
   failure shape as the `| tee` problem earlier today, twice in one day.

**Also recorded, and not a result.** With the same flags, the classical flow
came to 20,549 bytes and the post-quantum flow to 122,057 bytes, a ratio of
5.94×. That is an observation, not a measurement: those are the algorithms the
requester was *asked* for. What was actually *negotiated* has to be read out of
the `ALGORITHMS` response in the capture, which needs `spdm_dump`. Until that is
done the number must not be quoted. Verifying the independent variable instead
of asserting it is the entire discipline; G4 is where this becomes a result.

Stage-by-stage cost of the connection phase, from the same session:

| Up to and including | packets | bytes | delta |
|---|---:|---:|---|
| `DIGEST` | 12 | 728 | — |
| `+ CERT` | 18 | 5,824 | +6 packets, +5,096 bytes (the certificate chain) |
| `+ CHAL` | 28 | 10,712 | +10 packets, +4,888 bytes |
| `+ MEAS` | 554 | 20,549 | **+526 packets**, +9,837 bytes |

`MEAS` accounts for 526 of the 554 packets and only half the bytes: the
emulator requests measurement blocks one at a time. Open question for G1 —
whether that per-block round trip is the emulator's choice or the protocol's.

### The stable build did not compile, exactly where the decision record said it might

**現象** `stable` reached 86%, built its OpenSSL, then failed:

```
library/pci_doe_requester_lib/pci_doe_spdm_vendor_send_receive.c:63:9:
error: passing argument 11 of 'libspdm_vendor_send_request_receive_response'
       from incompatible pointer type [-Werror=incompatible-pointer-types]
```

**假設** (a) a stale CMake cache from the seeded copy, (b) a genuine API
mismatch between the pinned `libspdm` and the current `spdm-emu`.

**先驗哪個、為什麼** (b), because the error names a specific argument of a
specific function and gives its type — a stale cache produces missing files o
link errors, not a type mismatch at a named parameter. (a) would also have been
cheap to test, but the evidence already pointed one way.

**根因** `libspdm` changed the signature of
`libspdm_vendor_send_request_receive_response` between 3.8.x and 4.0.0-rc, and
current `spdm-emu` calls the new form. This is exactly the risk written into
`docs/decisions/0001` a few hours earlier as accepted — and it turned out to be
same-day rather than eventual.

Walking the submodule pointer history showed the deeper problem: **no
`spdm-emu` commit has ever pointed at libspdm 3.8.2.** The pointer moves in
steps, and 3.8.1 and 3.8.2 landed between two of them. The tags, however,
correspond exactly — `spdm-emu 3.8.0` → `libspdm 3.8.0`, `spdm-emu 4.0.0-rc` →
`libspdm 4.0.0-rc`.

**教訓** The pin belongs on the pair upstream actually tests together, not on
the component I happened to care about. ADR 0001 was revised: pin the
`spdm-emu` tag and let `libspdm` follow its submodule pointer.

The cost is real and is written down rather than glossed: **the baseline is now
libspdm 3.8.0, not 3.8.2**, so it lacks the two 2026 advisory fixes. For byte
counts and round-trip counts that is immaterial, and saying so out loud is
cheaper than being asked. If any result ever turns on behaviour that changed
between those versions, it has to be re-run against a build that has it.

Two smaller notes. The failure was *loud* — a compile error, not a wrong
number — which is the property the original decision was betting on, and the
bet paid. And writing the risk down beforehand turned a surprise into a
scheduled decision: the response was already drafted before the failure
happened.

### The decoder ran out before the handshake did

**現象** `spdm_dump` on the two captures produced wildly different amounts of
output: 554 decoded messages for the classical capture, **18** for the
post-quantum one — despite the two captures holding 554 and 590 packets. The
post-quantum decode showed no `CHALLENGE` and no `MEASUREMENTS` at all.

**假設** (a) the post-quantum handshake genuinely stopped afte
`GET_CERTIFICATE`, and exit status 0 was hiding it; (b) the decoder stopped.

**先驗哪個、為什麼** Compared packet counts first, because it needs no tools
and it discriminates cleanly: a handshake that stopped early cannot produce
590 packets when the complete one produces 554. That pointed at (b) before
reading a single line of decode output.

**根因** Printed by the decoder itself, on its last line:

```
SPDM_CHUNK_RESPONSE (Attr=0x01(LastChunk), ChunkSize=0x00000f0d)
SPDM_CERTIFICATE (SlotID=0x00, PortLen=0x000041d5, RemLen=0x00000000)
SPDM cert_chain is too larger. Please increase LIBSPDM_MAX_CERT_CHAIN_SIZE and rebuild.
```

`LIBSPDM_MAX_CERT_CHAIN_SIZE` is a **compile-time constant** in the decoder's
own libspdm. An ML-DSA-65 certificate chain exceeds it, so `spdm_dump` gives up
partway through — while the emulator that produced the capture, built from the
same libspdm commit, handles it without complaint.

**教訓** A short decode is not a short handshake, and the health check now says
so out loud instead of reporting the decoded prefix as if it were the whole
capture. More generally: three times today a tool has answered a slightly
different question than the one being asked — `tee`'s exit status, the
requester's exit status, and now the decoder's output length. The pattern is
worth more than any of the three.

### What the captures actually contain

With the negotiation read back rather than assumed, section 11 of the health
check now records this on every run:

| | classical | post-quantum |
|---|---|---|
| SPDM version offered | 1.0, 1.1, 1.2, 1.3, 1.4 | same |
| negotiated Hash | SHA-384 | SHA-384 |
| negotiated MeasHash | SHA-512 | SHA-512 |
| negotiated Asym | **ECDSA-P384** | none |
| negotiated PqcAsym | none | **ML-DSA-65** |
| negotiated KEM | none | **ML-KEM-768** |
| negotiated AEAD | AES-256-GCM | AES-256-GCM |
| **certificate chain** | **1,655 bytes** | **16,853 bytes** |
| chunk round trips | **0** | **4** |
| `SPDM_ERROR` responses | 246 × `InvalidRequset` | 1 × `LargeResponse` |

Three things follow, and the second is the interesting one.

**The independent variable is now verified.** `ML_DSA_65` and `ML_KEM_768`
appear in the `ALGORITHMS` *response*, not only in the request. Earlier today
the same comparison was recorded as an observation because only the request
was known. It is a measurement now.

**Post-quantum does not merely cost more bytes — it changes the message flow.**
A 16,853-byte certificate chain exceeds the negotiated `DataTransferSize`
(0x1200 = 4,608 bytes), so the responder answers `GET_CERTIFICATE` with
`SPDM_ERROR(LargeResponse)` and the exchange falls into SPDM's chunking
mechanism: four `CHUNK_GET`/`CHUNK_RESPONSE` round trips to deliver one
certificate. **The classical path never executes that code at all.** On a real
BMC talking MCTP over I²C, where the transfer unit is smaller still, this is
the part that would be felt — not the byte count.

**The 5.94× total-byte ratio recorded earlier is withdrawn.** Not because
either run failed, but because the two captures cannot yet be shown to contain
the same operations: the classical one spends 246 of its messages on
`InvalidRequset` responses to a measurement-index probe, and the post-quantum
one cannot be decoded past packet 18. The certificate-chain comparison above
replaces it, and is sound for a specific reason — it is one protocol field,
read from both captures, with the negotiated algorithm confirmed in each.

Open for G1: the classical run issues 263 `GET_MEASUREMENTS` and receives 246
`InvalidRequset` errors and 17 `MEASUREMENTS`. That looks like the emulato
walking measurement indices and being told most do not exist. Whether that is
the emulator's choice or something the specification implies is a question fo
the field-by-field pass, and it dominates the packet count of every capture
this project will take.

### openbmc/spdm does not build on the current Ubuntu LTS

**現象** Five successive failures, each only visible after fixing the previous
one: two missing python modules at `meson setup`, a third at `meson compile`, a
GCC internal compiler error, and a C++23 library feature the compiler's
standard library does not have.

**根因** Recorded in full in [`docs/upstream/README.md`](docs/upstream/README.md),
including the one that cost the most time: installing the generator modules
into a virtualenv is not enough, because meson resolves `python3` through
`find_program`, which searches `PATH`. Running `venv/bin/meson` without
activating the venv finds `/usr/bin/python3` and fails with the same message as
before, which reads as "the fix did not work" rather than "the fix was applied
to the wrong interpreter".

**教訓** This is the contribution. The repository has **no `README.md`**, so
every one of those five is discovered by a newcomer, one build at a time,
with nothing in the tree suggesting any of it is expected. Two candidate
patches fall straight out: a README with the prerequisites and the `PATH` trap,
and a statement of the minimum compiler version — the second supported by two
concrete failures on a mainstream distribution's default toolchain.

Also worth noting for its own sake: the ICE is in
`requester/utils/mapper.cpp`, one of the two files that has no test coverage.
That is a coincidence, but it is the kind of coincidence worth being able to
point at.

**`TODO(me)`** — 緯穎 whitepaper, *SPDM Attestation between BMC and ERoT on AI
Server* (page updated 2026-08-06). Read it in full, not the abstract. Copy the
"challenges and future directions" section here point by point, in my own
words. Then write down the connection between it and the 2026-08-04 hardware
partitioning paper: partitioning produces multi-tenancy, and multi-tenancy
produces a trust question that attestation is the answer to. Partitioning
solves isolation; attestation is how you know the isolation held.

**`TODO(me)`** — What I am least sure about right now: _______________

> Leave that line honest. In three months it is the most useful thing on this
> page, because it is evidence that the uncertainty was real at the time and
> was later resolved.

---

## 2026-08-16 · the README named a version the repo does not build

**現象** `README.md` states the `stable` flavor is libspdm 3.8.2. So do fou
places in `RUNBOOK.md`, the usage comment of `harness/build_spdm_emu.sh`, and
an INFO verdict in `harness/healthcheck.sh`. What the build actually produces
is **3.8.0** — `third_party/spdm-emu-stable.pin` records it, and
`flavor_emu_ref()` in `harness/lib/common.sh` is what puts it there.

**假設** (a) the pin is stale and the documents are right; (b) the documents
are stale and the pin is right; (c) the two describe different things and both
are right.

**先驗哪個、為什麼** (b), and it needed no build to settle. The pin file is
*generated* — `build_spdm_emu.sh` writes `BUILD_PIN.txt` from
`git rev-parse HEAD` after the checkout, and `third_party/*.pin` is a copy of
it. A generated record and a hand-written sentence cannot disagree unless the
hand-written one is wrong, because the generated one is downstream of the
thing it describes. Checking (a) would have meant a rebuild; checking (b) meant
reading one function.

**根因** ADR 0001 was revised on 2026-08-11 — pin the `spdm-emu` tag and let
`libspdm` follow its submodule pointer, instead of pinning `libspdm` directly.
The mechanism changed, the ADR and this log recorded it, and six documents that
had quoted the *old* value were never revisited. Nothing failed: the version
string appears in no assertion, so no test, no `verify_repo.sh` check and no CI
job could see it. It survived five days precisely because it was inert.

**教訓** Two, and the second is the general one.

1. When a mechanism changes, grep for the old value before closing the change.
   The ADR is not the deliverable — the documents a reader actually opens are.
2. **This repository's whole claim is that every number points at its source, so
   a number that contradicts its own source is the most expensive kind of erro
   it can carry** — more expensive than a wrong measurement, because it
   discredits the mechanism rather than one result. The failure mode is
   specific: facts that are only ever *stated* have nothing checking them,
   while facts that are *computed* are checked every run. Where the two overlap,
   the stated one is the one that rots.

Fixed here, and the correction was not only the digit. The tables now name both
`spdm-emu` and `libspdm`, because naming only the one that is not pinned is
what made the drift possible; and the cost of the pinning rule — which ADR 0001
gave as "3.8.0 lacks the two 2026 advisory fixes" — was moved into `README.md`
and `RUNBOOK.md` next to the table, rather than left in ADR 0001 for a reade
who goes looking.

**That last sentence was itself wrong, and the next entry is about that.**

---

## 2026-08-17 · the sentence I promoted was one I had not checked

**現象** Asked to confirm the previous entry rather than accept it, the first
two claims held under direct measurement: the built tree is
`spdm-emu 3.8.0 → libspdm 3.8.0` with `VERSION.md` saying so, `BUILD_PIN.txt`
is byte-identical to the committed pin, and an exact-SHA sweep of every
`spdm-emu` commit that ever moved the `libspdm` gitlink shows **3.8.1 and 3.8.2
were never pointed at, once, in the entire history.** The third claim did not
hold. I had carried "3.8.0 lacks the two 2026 advisory fixes" out of ADR 0001
and into `README.md`, and I had never checked it.

**假設** (a) the claim is right and simply undocumented; (b) the advisory years
are wrong; (c) the affected releases are wrong; (d) some combination.

**先驗哪個、為什麼** None of them, first. Before fetching anything I checked
the claim against a number already on the table from the previous hour:
**libspdm 3.8.1 is dated 2025-09-03.** A release cut in 2025 cannot contain a
fix for a 2026 advisory. That is an internal contradiction, available for the
cost of re-reading two lines, and it converted "is this true" into "how is it
false" before any download. Only then was a clone worth making — blobless,
no checkout, outside `~/spdm-lab`, so nothing that produces a result could
change as a side effect of asking a question about it.

**根因** The sentence was written from memory and never verified. What upstream
history actually shows:

| range | released | commits | security content |
|---|---|---:|---|
| 3.8.0 → 3.8.1 | 2025-09-03 | 4 | **none** |
| 3.8.1 → 3.8.2 | 2026-04-03 | 10 | **one**, `Fix security vulnerability in GET_CSR parsing code` |

Not two, not spread over both releases, and no commit message in either range
names a CVE or GHSA identifier at all. Two further things fell out that matte
more than the correction:

- **`git cherry -v 4.0.0-rc 3.8.2` marks that security commit `-`.** It is a
  backport of main-line `713e32c0` from the same day, so **4.0.0-rc has the
  fix**. "3.8.2 is not an ancestor of 4.0.0-rc" is true and would have been a
  wrong thing to conclude from: on a maintenance branch the same fix has a
  different hash by construction, and ancestry is the wrong test. Patch-id is
  the right one.
- The gap the baseline really carries is the *main line* after 3.8.0, including
  an out-of-bounds read fix in `libspdm_process_general_opaque_data_check`
  (2026-06-26). That is a more useful thing to know than the original claim,
  and it is a class this project already has a drill for.

**教訓** Three, and the third is why this entry exists at all.

1. **Ancestry is not content.** Before concluding that a branch lacks a fix,
   compare by patch-id, not by `merge-base --is-ancestor`. The cheap test
   answers a neighbouring question — the same failure shape as `tee`'s exit
   status, now the fifth instance in this log.
2. **Check for internal contradiction before reaching for the network.** A
   2025 date under a 2026 claim is free to notice and settles the direction of
   the whole investigation.
3. **Moving a claim makes it mine.** The sentence had sat in ADR 0001 for five
   days without being examined; copying it into `README.md` put it on the page
   a stranger reads first, and that is the act that made it my assertion rathe
   than an inherited one. **I wrote the previous entry — about facts that are
   only ever stated having nothing to check them — and then committed exactly
   that failure one commit later.** Knowing the failure mode is not the same as
   being immune to it, which is the argument for mechanisms over intentions and
   is the reason `prov_begin` exists. There is no equivalent mechanism fo
   prose, so the substitute is a rule: **a claim that moves to a more prominent
   place gets re-checked at the moment it moves.**

Also settled while the clone was open, because it is what ADR 0001 rests on:
**4.0.0 has not been released.** `4.0.0-rc` (2026-08-04) is still the newest
tag; `main` is at 2026-08-13. The two-flavor decision is still current, and it
now has a date attached to when that was last true.

---

## 2026-08-17 · Day 2 · the handshake, and an audit of the week before it

### Auditing week one before building on it: three mechanisms that were reporting success

**現象** Before starting the field-by-field work, a check of what week one
actually left behind. The version pins held — both build trees are byte-identical
to their committed `.pin` files, and `stable` genuinely has no `--pqc_asym`. But
three mechanisms were found to be answering a different question than the one
they appeared to answer, and all three were reporting success while doing it:

1. `manifest.json` in all three committed runs lists `<arm>.req.log` and
   `<arm>.rsp.log` with a SHA-256 each. `.gitignore` line 55 is `*.log`. **Those
   twelve files were never in the repository.**
2. `repo_dirty` reads `true` in every manifest this project has produced,
   including runs from a clean checkout.
3. `third_party/` pinned two emulator builds and **not `spdm-dump`** — through
   which every statement about what was *negotiated* is read.

**假設** For (1): (a) the files were deleted after the run, (b) they were neve
added, (c) an ignore rule excluded them. For (2): (a) the tree really was dirty
every time, (b) the check runs at the wrong moment.

**先驗哪個、為什麼** For (1), `git check-ignore -v` on one of the files, because
it names the rule and the line number in a single command and distinguishes all
three hypotheses at once — a deleted file and an unadded file both produce no
output. It printed `.gitignore:55:*.log`.

For (2), read `prov_begin` rather than experiment, because a mechanism that has
produced the same answer on every run it has ever performed is more likely to be
structurally incapable of the other answer than to have encountered the same
condition every time. `mkdir -p "$PROV_RUN_DIR"` sits above the `git status`
call. **The directory it creates is what makes the tree dirty.**

**根因** Three different failures with one shape: a check placed where it cannot
fail. The ignore rule outranked the manifest, and no code compared them. The
dirty check ran after the thing that dirties. The decoder was outside the set of
things considered "upstream" because it is a reader rather than a producer, and
nobody had written down that a reading is part of a result.

**教訓** Four, and the last one is the general one.

1. **An ignore rule is not allowed to outrank a manifest.** `verify_repo.sh` now
   checks that every artifact a manifest attests to is present *and tracked*.
   Writing that check first is what found all twelve; a fix without it would
   have restored the files and left the hole.
2. **A field that cannot take more than one value is not an observation**, and
   it is worse than an absent field because a reader cannot tell the difference.
3. **A result's provenance includes the tools that read it**, not only the ones
   that produced it. `spdm-dump.pin` exists now.
4. **Auditing is cheapest immediately before building on something, and it is
   never the thing you planned to do that morning.** All three of these were
   invisible while everything was green, and all three would have been carried
   into every result this project produces afterwards. The trigger that found
   them was not suspicion — it was the ordinary act of asking, before adding a
   fifth run directory, what the first three actually contained.

### Determining a third-party binary's compile-time constant without rebuilding it

**現象** `spdm_dump` gives up partway through a post-quantum capture:
`SPDM cert_chain is too larger. Please increase LIBSPDM_MAX_CERT_CHAIN_SIZE and
rebuild.` `README.md` already recorded this as the decoder's compile-time
constant being too small. What it did not say is *what the constant is*, which
decides whether this is a limitation or a task.

**假設** From `libspdm/include/library/spdm_lib_config.h`, the macro can only be
one of three values: `0x1000` (4,096) with no post-quantum signature support
compiled in, `0x8000` (32,768) with ML-DSA, `0x28000` with SLH-DSA. The chain it
fails on is 16,853 bytes — **which `0x8000` would hold with room to spare.** So
either (a) the build has no ML-DSA support and the limit is 4,096, or (b) the
limit is larger and something else is failing.

**先驗哪個、為什麼** Neither by rebuilding, which is twenty minutes and changes
the thing being measured. `spdm_dump.c:850` compares the **size of a
`--rsp_cert_chain` file** against the macro *before parsing it*, and prints the
same message. That is an oracle: feed it files of known size and the constant
falls out of where the answer changes. Twenty probes, bisection from 1 to 2^20,
no rebuild and no patch.

```
  4096 bytes (0x1000)  accepted
  4097 bytes (0x1001)  REJECTED
```

**根因** `LIBSPDM_MAX_CERT_CHAIN_SIZE` is **4,096** in this build — the branch
taken when no post-quantum signature algorithm is compiled in. And
`spdm-emu-pqc`, which produced the capture and handles the same chain without
complaint, is built from **the same libspdm commit**. The difference is build
configuration, not version.

**教訓** Two.

1. **An input-validation check is a measuring instrument.** Anything that
   compares a caller-supplied quantity against an internal constant and reports
   the comparison will tell you the constant, and this one did it in eight
   seconds of shell. It is worth looking for that shape before reaching for a
   rebuild — a program that validates its inputs is a program that answers
   questions about itself.
2. **"Cannot" and "is not configured to" are different sentences**, and the
   README was carrying the first while the second was true. The correction is
   not cosmetic: one is a limitation to be documented in `limitations.md`, the
   other is a task with a known fix. `build_spdm_dump.sh` now runs the same
   bisection after every build, so the number is produced rather than
   remembered.

### The independent variable had two halves and only one was pinned

**現象** The post-quantum run of 2026-08-11 set `--pqc_asym ML_DSA_65` and its
`ALGORITHMS` response confirms `PqcAsym=ML_DSA_65`. Read one field further:
**`ReqPqcAsym=0x0004(ML_DSA_87)`**.

**假設** (a) a decoder artefact, (b) the responder ignored the request,
(c) `ReqPqcAsym` is negotiated separately and was never constrained.

**先驗哪個、為什麼** (c), by reading `--help` for a flag that would constrain it,
because if such a flag exists the question is answered and if it does not,
(a) and (b) are worth investigating. `--req_pqc_asym` exists, defaults to
`ML_DSA_44,ML_DSA_65,ML_DSA_87`, and was not passed.

**根因** SPDM authenticates in **two directions** and negotiates the algorithm
for each independently. `--pqc_asym` constrains the responder's signature;
`--req_pqc_asym` constrains the requester's. That capture therefore holds a
responder signing with ML-DSA-65 and a requester signing with ML-DSA-87 — while
the classical arm it would be compared against has a requester signing with
RSAPSS-3072. The requester's own certificate chain is **3,794 bytes** in the
classical arm, which is more than twice the responder's 1,655. Two arms whose
requester-side algorithm differs cannot be subtracted from each other.

**教訓** This is the same failure as the withdrawn 5.94× ratio, one week later,
and **it is hiding one layer deeper**. That one was "the number came from what
was requested rather than what was negotiated", and the fix was to read the
`ALGORITHMS` response. This one *was* read out of the `ALGORITHMS` response —
from the wrong field. So:

> **Verifying the independent variable means enumerating it, not spot-checking
> it.** "I confirmed the algorithm" is not a claim about a system with two
> independently negotiated algorithms. Every arm in `harness/capture.sh` now
> pins both directions, and `harness/fields.py` reports both whether or not
> anyone asks.

The general form is worth keeping: **when a check passes, ask what else is in
the same category as the thing you checked.** One `ReqAsym` row on the same
table would have shown this on 2026-08-11.

### 526 of 554 packets, and an open question closed from a source comment

**現象** The "minimal" handshake is 554 packets. 263 of them are
`GET_MEASUREMENTS`, 246 are `SPDM_ERROR(InvalidRequset)`, and 17 are
`MEASUREMENTS`. `LOG.md` left this open on 2026-08-11: is the per-block round
trip the emulator's choice or the protocol's?

**假設** (a) the protocol requires one request per measurement block, (b) the
emulator does it that way and there is a flag, (c) the responder is answering
badly.

**先驗哪個、為什麼** (b), by reading `spdm_requester_measurement.c` — because if
a flag exists it is one `--help` line away, and because (a) is a claim about
DSP0274 that would cost an hour of specification reading to settle either way.
Read the implementation first; it either names the alternative or rules it out.

**根因** Three causes stacked, and separating them is the whole answer:

- **The two-pass structure is required by the specification.** The source
  comment says why: *"In SPDM 1.2 spec, the L1/L2 will be reset in case of
  MEASUREMENT error. That impacts 1-by-1 calculation… The solution is: get the
  existing measurement list, then query measurement one by one."* A requeste
  building a signed transcript has to learn which indices exist before it
  starts, and the discovery pass is the one that absorbs the errors.
- **Walking the index space is the emulator's choice.** `--meas_op ALL` sends
  `MeasurementOperation = 0xFF` and gets every block in one message.
- **The early exit never fires because of the sample data.** Both loops break
  when they have collected `TotalNumberOfMeasurements` blocks. The eight that
  exist are `0x01–0x04, 0x10, 0x11, 0xFD, 0xFE`, and the last is `0xFE`.

Measured: `--meas_op ALL` gives **30 packets** instead of 554. And summing
`MeasurementRecordLength` over the eight indices under `ONE_BY_ONE` gives
**528 bytes**; the single `ALL` response carries a record of **528 bytes**.
**263 round trips and 1 round trip deliver the same measurement bytes.**

**教訓** Two.

1. **"Is this the protocol or the implementation" is answered by reading the
   implementation, not the specification.** The implementation names the
   specification's constraint where it is subject to one — this comment cites
   the SPDM 1.2 transcript rule directly — and where it does not, the behaviou
   is its own. Reading DSP0274 first would have found the L1/L2 rule and still
   not explained the 246 errors.
2. **A question left open in a log is an asset, not a debt**, provided it is
   written where it will be seen again. This one was closed by a source comment
   found while looking for something else, six days later, and the only reason
   it got closed is that it was written down as a question rather than
   dissolved into "measurements are slow".

### Two claims in this week's plan that the capture refutes

**現象** The plan for this week carries two facts marked as re-checked:
`CHUNK` is not in either side's default capabilities, and offering several
algorithms per group makes `NEGOTIATE_ALGORITHMS` larger. Both are wrong.

**假設** For `CHUNK`: (a) the plan is right and the capture is being misread,
(b) the plan's source is wrong, (c) the default changed between versions.

**先驗哪個、為什麼** (a) first, and cheaply: the post-quantum capture performs
four `CHUNK_GET`/`CHUNK_RESPONSE` round trips. **Chunking is not reachable
unless both sides negotiated `CHUNK_CAP`**, so behaviour that already happened
settles a question about capability bits without decoding anything. That
eliminated (a) before any bit was inspected.

**根因** `spdm_emu.c:115`'s `--help` string is hand-written and
`key.c:25`'s default is a hand-written initialiser, and nothing checks that they
agree. Requester defaults omit `CHUNK` and `EP_INFO_SIG` from the text;
responder defaults omit those two and `MEL`. `CHUNK_CAP` is set on **both**
builds, 3.8.0 included.

The second claim fell to a measurement rather than an argument. One arm offering
a single algorithm per group, against the stock arm offering two to four:
`NEGOTIATE_ALGORITHMS` is **56 bytes in both**, byte for byte the same `Length`
field, differing only in the values of fixed-width bitmasks. What does change
the size is a whole group being dropped (`--dhe NONE`: one fewe
`AlgStructure` table, 4 bytes) and the protocol version (1.3 is 48 bytes; 1.4's
two extra tables are the difference, while `PQCAsymAlgo` was carved out of
reserved space and cost nothing).

**教訓** Two, and the second is why this entry is not just a correction.

1. **`--help` is documentation, and documentation is a stated fact.** The wire
   is a computed one. Where they disagree the wire wins, and this is the third
   time this project has been caught by the same distinction — after the
   `--exe_session` default and the libspdm version number. The rule that follows
   is narrow and usable: **a default value read from help text is a hypothesis.**
2. **The plan's assumption about message size was reasonable and still wrong**,
   and the difference between "offering more costs bytes" and "offering more
   costs certainty" is the difference between optimising the wrong thing and the
   right one. The cost of offering everything you support is that **you do not
   know what you are using until you read the response** — which is not a
   bandwidth problem and cannot be fixed by trimming flags.

### The documentation mechanism, and proving it turns red

**現象** `docs/handshake-walkthrough.md` is a document made almost entirely of
stated facts — 84 numbers read out of captures. Two entries in this log, one day
apart, are about stated facts going wrong.

**假設** Not a fault to diagnose; a design choice with three options: write the
numbers and re-check them by hand periodically; generate the whole document from
the captures; or write the document by hand and have a machine check its
numbers.

**先驗哪個、為什麼** The third, because the first is exactly the discipline this
project has twice failed to sustain, and the second discards the reason to write
a walkthrough at all. **The value of this document is the sentences, not the
tables**, and a generator would produce the tables and none of the sentences.

**根因** — **教訓** Every number in the document is marked up as
`<!--claim key=value-->`, invisible when rendered, and `harness/fields.py
--check` re-derives it from the decode file the section names. `verify_repo.sh`
runs it; CI runs `verify_repo.sh`. 84 claims across five captures.

Three things this was made to fail on before being trusted, because **green is
worth nothing until it has been shown it can go red**:

| broken deliberately | result |
|---|---|
| a byte count changed from 528 to 529 | `FAIL: document says 529, capture says 528` |
| a claim naming a field the tool does not compute | `FAIL: 'measurements.mode' is not a field this tool computes` |
| the capture path pointed at a file that does not exist | `FAIL: capture not found` |

The second matters most: without it, a claim could be satisfied by inventing a
field name, and the mechanism would be theatre.

And the limits are written into §10 of the document itself, because **a check
trusted beyond its reach is worse than no check**. The capability-bit names are
transcribed from a header by hand, so a renamed bit would stay self-consistent
and pass. Most of the offsets come from struct definitions rather than from the
wire — three messages have been confirmed byte for byte, and the document says
which three.

**`TODO(me)`** — 緯穎 whitepaper, still unread. Carried from Day 1 deliberately
rather than quietly dropped.

**`TODO(me)`** — `c-drills` D1 and D3. D3 has been outstanding since week one and
`DONE.txt` is still empty. The drills measure whether C can still be written
correctly with no compiler to ask, which is a thing that decays silently and
which nothing else in this repository would notice. **A week where the project
track ran a week ahead and the drill track ran a week behind is the shape of the
risk, not an accident of scheduling.**

**`TODO(me)`** — What I am least sure about right now: _______________

---

## 2026-08-28 · Day 3 · the offsets, and the field nobody quoted

Eleven days after Day 2. The project track resumed where it stopped; the drill
track had not moved, which is the risk Day 2 wrote down and then demonstrated.

### A field that was wrong for eleven days inside a tool that checks 84 facts

**現象** While building the layout reconstruction below, `message_bytes.total`
for the walkthrough capture read **15,803**. That number is supposed to exclude
transport framing. `harness/pcapcount.py` reports the same capture as **11,441**
bytes *including* framing. A total that excludes something cannot exceed the
total that includes it.

**假設** (a) the hex dump repeats some bytes, (b) `pcapcount.py` is
undercounting, (c) `parse_hex` is summing lines it should not.

**先驗哪個、為什麼** (a), by printing the block structure of one packet — thirty
seconds, no rebuild, and it separates all three at once. Deliberately not (b):
`pcapcount.py` has a self-test in `verify_repo.sh` that builds a capture byte by
byte and checks the parser against it, and `fields.py` had nothing equivalent.
**Doubting the tool that is checked before the tool that is not is the wrong
order**, and it would have cost an afternoon.

**根因** `spdm_dump -x` prints a packet that carries mutual authentication as
**two** hex blocks — the encapsulated message first, then the carrier — and the
carrier already contains the encapsulated message byte for byte. `parse_hex`
summed every hex row under a packet number, so those bytes were counted twice:
**4,512 bytes, 40% of the total.**

A second fault sat in the same place and was quieter. `fields.py` paired blocks
to messages **by position**, and the print order is the reverse of the decode
line's, which names the carrier first. So the carrier's bytes were being handed
to the message it carries. Packet 21's `CHALLENGE_AUTH` measured 482 bytes. It
is 478.

**教訓** No number in `docs/handshake-walkthrough.md` moved. Every
`message_bytes` claim there is a first-message size for `GET_CAPABILITIES`,
`NEGOTIATE_ALGORITHMS` or `ALGORITHMS`, and none of those is ever encapsulated.
So the mechanism was reporting 84/84 correct while a field it also computed was
wrong by 40%.

> **The reach of a checking mechanism is the set of facts someone chose to
> state, not the set of facts the tool produces.** `fields.py` computes about
> twenty fields; the document quotes seven. It was checked on seven.

The response is not "write more claims" — the next unquoted field would sit in
exactly the same position. It is a **second tool that has to agree.**
`pcapcount.py` owns the capture file and never reads a decode; `fields.py` owns
the decode and never opens a capture. `verify_repo.sh` now requires

```
pcap captured bytes == SPDM message bytes + 5 x messages
```

on every capture whose decode is complete — the five being the four-byte MCTP
header plus the message-type byte, taken apart in `docs/transports.md` on Day 2
for an entirely different reason. Four captures satisfy it exactly. It finds
nothing today, and the source says that it finds nothing today, because a check
added after the bug it would have caught should admit which side of that line it
is on.

### Two equations and one unknown, which is what makes an offset falsifiable

**現象** §10 of the walkthrough states the hole in its own checking: the offset
columns come from struct definitions in `spdm.h`, so **a wrong offset printed
beside a right value passes every test in this repository.** The document's
sharpest claim — that the responder's nonce sits at `4 + digest_size` rathe
than at a fixed offset — was arithmetic, not a measurement.

**假設** for how to close it: (a) confirm each message against `spdm_dump -x` by
eye, as three already were; (b) write a second SPDM parser and diff it against
`spdm_dump`; (c) reconstruct each message's layout and require it to close on a
quantity that appears nowhere in the document.

**先驗哪個、為什麼** (c). (a) checks this document once and not the next capture,
so it decays the moment anything is re-run. (b) is the thing `fields.py`'s own
header warns against — a second parser is a second thing to keep correct, and it
would be the wrong one. (c) costs an afternoon and then runs on every build.

**根因** Not a bug; a property. Every field of an SPDM response is a constant
size, a size fixed by something negotiated several messages earlier, a size the
message itself carries, or the remainder — so the layout can be **rebuilt** and
then contradicted:

```
CHALLENGE_AUTH, packet 14, 238 bytes from the hex dump
  4 header + 48 CertChainHash + 32 Nonce + 48 MeasurementSummaryHash
    + 2 OpaqueLength + 0 OpaqueData + 8 RequesterContext = 142
  238 - 142 = 96 = ECDSA-P384, which is what ALGORITHMS negotiated
```

The total comes from the hex dump and the signature size from `ALGORITHMS`.
Neither is typed into the document, so the equation is between two independent
readings of the capture. And there is a second one: `RequesterContext` is chosen
by the requester and echoed back unchanged, so reading eight bytes at the
predicted offset 134 and comparing them against the request constrains the same
unknowns again — using no constant from the tool at all.

**教訓** A reconstruction that closes proves nothing unless it could have failed,
so `verify_repo.sh` now builds a correct `CHALLENGE_AUTH` and three broken ones
— a byte short, a context that does not echo, a different signature algorithm —
and requires every break to be rejected.

> **The value is in being over-determined by one.** A determined system restates
> its inputs. One spare equation is what turns "the layout is this" from an
> assertion into something the capture is able to refuse.

What the spare equation bought immediately: `MeasurementSummaryHash` is sized by
`BaseHashAlgo`, not by `MeasurementHashAlgo`. This connection negotiated both —
SHA-384 and SHA-512 — and the document could not say which applied. The two
hypotheses differ by 16 bytes and only one closes. **A question answered by
arithmetic on bytes already in hand, rather than by the specification section I
had not read.**

Three more things fell out unasked. The mutual-authentication `CHALLENGE_AUTH`
closes on a 384-byte RSAPSS-3072 signature against the responder's 96-byte
ECDSA-P384 — the 08-17 lesson about a two-halved independent variable, restated
as a byte count that nobody had to be looking for. The `ONE_BY_ONE` first pass
closes on a residue of **0** and the second on **96**, which is the two-pass
structure measured rather than argued from a source comment. And the request
length settled the next entry.

### The request is 12 bytes, so the answer is both

**現象** §7 has carried an open question since 08-17: is `Nonce` present in
`GET_MEASUREMENTS` when `GenerateSignature` is clear? libspdm's struct has it
unconditionally, and where DSP0274 stands was unread.

**假設** (a) always present, (b) conditional on the signature bit, (c) present,
but `SlotIDParam` is not.

**先驗哪個、為什麼** None of them by reading. The request's **total length** was
already in a hex dump committed on 08-16, and it separates all three at once:
with `GenerateSignature` the request is 45 bytes, without it **12**. The missing
33 is 32 + 1, which is `Nonce` **and** `SlotIDParam` together — no other subset
of those fields sums to 33.

**根因** Both are conditional on that bit. Which reads as deliberate once it is
visible: with no signature to produce there is no transcript to keep fresh, so
no nonce, and no key to select, so no slot.

**教訓** The question sat filed as "specification unread" for eleven days, and
the answer was in a file that had already been committed.

> **Re-ask an open question against the evidence accumulated since, not only
> against the source you meant to read.** The blocker was never access to
> DSP0274.

The answer is recorded in §7 as the weaker kind it is — arithmetic on one
emulator's bytes rather than a specification requirement — and the question is
left standing above it, per §10's rule.

### The alignment lesson that this struct cannot teach

**現象** Writing `c-drills/d1`, whose stated pitfall is "do not cast the buffe
to a struct pointer — it works on x86 and faults on ARM." The test hands the
parser a deliberately odd address, and a reference implementation that does cast
was written to confirm the test catches it. UndefinedBehaviorSanitizer said
nothing.

**假設** (a) the sanitizer flag is not actually on, (b) the address was not odd,
(c) the cast is legal here.

**先驗哪個、為什麼** (c), by `_Alignof`. One line, and no rebuild of anything.
(a) and (b) both blame the apparatus, and the apparatus had just caught a
misaligned load in a different test inside the same binary, so it was demonstrably
working. **A tool that has just been observed working is the last thing to
suspect, not the first.**

**根因** `struct { uint8_t version, code, param1, param2; }` has an alignment
requirement of **1**. Every member is a byte, so a cast to it cannot be
misaligned at any address on any architecture. Strict aliasing still argues
against the cast, and padding would bite the moment someone adds a `uint16_t`,
but neither faults and no sanitizer reports either.

**教訓** The lesson is true for structs with multi-byte members and false fo
this one — and it would have been taught here as though it were true, then
repeated in an interview.

> **A drill whose failure mode cannot occur teaches a superstition, and a
> superstition is worse than a gap, because it gets repeated with confidence.**

So `d1` gained a second function: reading a 32-bit little-endian field at a
caller-supplied offset, which is where the fault actually lives, and which is
`DataTransferSize` at offset 12 of this project's own `GET_CAPABILITIES`. The
tests were then run against **two** wrong implementations before being
committed. `off + 4 > len` is caught by AddressSanitizer as a buffer overflow,
because the sum wraps at an offset near `SIZE_MAX` and the bound passes; the
`uint32_t` cast is caught by UBSan as a misaligned load. A test suite that a
wrong implementation also passes is not a specification, and there is no way to
know which one you have written without trying it.

### A prerequisite for the certificate work, checked early and already failing

**現象** The next stage needs the *system* OpenSSL to sign ML-DSA certificates.
Measured today rather than in the week that needs it:

```
$ openssl version
OpenSSL 3.0.13 30 Jan 2024
$ openssl list -signature-algorithms | grep -i ml-dsa
(no output)
```

**根因** Ubuntu 24.04 LTS ships OpenSSL 3.0.x. Which release first offers ML-DSA
is **not checked here**, and should not be repeated from memory until it is.
What is measured is that this one does not offer it.

**教訓** This is unrelated to `libspdm`, which builds its own OpenSSL submodule —
so the emulator signs ML-DSA happily while the command line on the same machine
cannot produce a post-quantum certificate at all.

> **Two OpenSSLs in one project, and only one of them is pinned.** The pinned one
> is in `third_party/*.pin`. The other is whatever the distribution shipped, and
> until today nothing in this repository recorded that it exists.

The options — a newer OpenSSL from source, the provider route, or generating the
chain with `libspdm`'s own tooling — are unresearched. Recorded now so the week
that needs it starts from a known constraint instead of discovering one.

### A manifest says a file is unaltered. It does not say the file is still true.

**現象** After the double count above was fixed, `verify_repo.sh` passed every
check — including the one that re-hashes every artifact against its manifest.
And `bench/data/w2-baseline-20260816T172221Z/walkthrough.fields.json`, committed
and attested, still contained `"total": 15803`, a number `fields.py` had stopped
producing an hour earlier.

**假設** (a) the file was never actually committed, (b) the re-hashing check is
broken, (c) the re-hashing check is answering a different question than the one
I was asking of it.

**先驗哪個、為什麼** (c), by re-reading the check's own output line: *present,
tracked, and unaltered.* Thirty seconds, and it is the cheapest of the three by
an order of magnitude — (a) and (b) both require going and looking at a
mechanism that had just been extended and was demonstrably working on 76 othe
files. **When a check passes and the world looks wrong, read what the check
actually claims before doubting that it does it.**

**根因** `capture.sh` writes a `*.fields.json` beside each capture, and
`prov_finish` hashes it into `manifest.json` alongside the pcap. But those two
files are not the same kind of thing. A pcap is **evidence**: its meaning cannot
change, so knowing it is unaltered is knowing everything. A `fields.json` is a
**derivation** — this project's tool's reading of a decode at one moment — and
when the tool changes, a file that nobody touched becomes false while its hash
still matches perfectly.

**教訓**

> **Integrity and currency are different properties, and a digest only gives you
> the first.** "This file has not been altered" and "this file is still true"
> are the same sentence only for inputs, never for outputs.

Two consequences, and the second was unplanned.

`verify_repo.sh` now requires every committed derivation to **reproduce**: run
`fields.py` on the decode beside it and demand equality. Scoped to the run
directories a document cites, discovered by reading their `<!-- capture: -->`
directives rather than from a list — a list is the same failure one level up.

And the repair itself. There is no mechanism here for re-stamping a manifest,
and there should not be: a manifest that can be rewritten attests to nothing. So
the fix was a **new run**, not an edited old one — which meant re-taking all five
captures on the same pins, eleven days after the first set. Every arm reproduced
**to the byte**: 554/20,549, 584/114,751, 566/20,396, 30/11,441, 30/11,441.
Nonces and timestamps differ. Nothing this repository states does.

So `docs/handshake-walkthrough.md` can now say something it could not say this
morning: **every word of it was written against one capture and all 128 of its
claims verify against a different one.** That is the difference between a capture
and a measurement, and it is the evidence for a rule the roadmap had been
asserting since week one — that byte counts are deterministic and are reported
as single values rather than ranges.

Worth noticing about the order this happened in: the reproducibility result was
not an experiment anyone designed. It fell out of refusing to edit a manifest.
**A constraint that makes the cheap repair impossible is sometimes the reason
the expensive one produces something.**

**`TODO(me)`** — 緯穎 whitepaper, still unread. Carried from Day 1 and Day 2.
That is two carries, which is the point where a carried item gets scheduled o
dropped honestly rather than carried a third time.

**`TODO(me)`** — `c-drills`. `d1` now exists with a contract, tests and a stub,
and `d3` has existed since week one. **`DONE.txt` is still empty and
`SCORECARD.md` still has eight blank rows.** Three working days have gone into
mechanisms that check themselves; the track that measures whether *I* can still
write C with no compiler to ask has produced nothing. Day 2 wrote that down as a
risk. Eleven days later it is not a risk, it is a fact, and it is the largest
gap in this repository.

**`TODO(me)`** — `CERTIFICATE` is the next message worth reconstructing:
`PortionLength` is carried in the message, so header + lengths + portion ought to
account for every byte. "Ought to" is not a measurement, which is why it is
written in §10 as a task and not in §5 as a fact.

**`TODO(me)`** — What I am least sure about right now: _______________

## 2026-08-31 · Day 4 · a chain of my own, and the two it did not replace

Week three. The plan asked for a three-layer certificate chain accepted by the
responder, a diagram naming who holds each private key, the PCIe SAN, and a
submission to DMTF's SPDM 1.5 review before it closed today. All of that is
here. What is worth writing down is mostly the six things that were not planned,
four of which are mistakes I made and one of which I had already documented
eleven days ago and made again.

### The plan told me to cite a specification I cannot read

**現象** `plan/W03` §2.2 is unambiguous: the leaf certificate must carry a
`subjectAltName` `otherName` under OID `2.23.147` holding Vendor, Device, Class
Code, Revision and Subsystem IDs, per PCIe r6.1 §6.31.3, and a QEMU DOE endpoint
rejects a certificate without it. The obvious move is to add it and continue.

**假設** (a) the plan is right and this is simply what an SPDM leaf carries;
(b) the plan is right about PCIe but PCIe is not the only specification with an
opinion; (c) the plan is wrong.

**先驗哪個、為什麼** (b), and by the cheapest possible test: `grep`. The pinned
`libspdm` and `spdm-emu` trees are on this machine, and `spdm-emu`'s own
`openssl.cnf` — the one that generates the sample certificates every capture in
this repository has read — is thirty lines long. Reading it cost nothing and
answered the question before any certificate was generated. **Checking what the
reference implementation already does is faster than checking what a
specification says, and it is available first.**

**根因** Both. `2.23.147` appears **zero** times in `libspdm`, zero times in
`spdm-emu`, and zero times in DSP0274 1.4.0's 306 pages. What the reference
implementation emits is `1.3.6.1.4.1.412.274.1` — `id-DMTF-device-info`, defined
in DSP0274 §425 as a UTF8String of exactly three colon-separated fields,
`Manufacturer:Product:SerialNumber`, with no field permitted to contain a colon.
The sample leaf carries `ACME:WIDGET:1234567890`.

So there are two device-identity OIDs, from two specifications, answering the
same question for two different stacks. A PCIe device speaking SPDM is subject to
both. Carrying only the PCIe one would have produced a certificate that satisfies
the transport and ignores the protocol — and I would have had no idea, because
nothing in this project's toolchain reads either.

**教訓** The leaf carries both, and only one of them is claimed to be verified.
DSP0274 is a public PDF; the PCIe Base Specification is behind PCI-SIG
membership and was not read. So `2.23.147` is labelled *asserted by the plan, not
checked against its primary source* everywhere it appears — in `openssl.cnf`, in
`certs/README.md`, in `docs/certchain.md`, and in the checker's own output.

> **A repository that says "nothing is cited that has not been checked" has to be
> able to carry something unchecked, labelled, rather than either dropping it o
> quietly promoting it.** Dropping it loses a W09 prerequisite for a rule that
> was not about that. Promoting it makes every other citation worth less.

What *was* checked about the unverifiable one is stated as its own fact: the
string appears nowhere in the specification the project does have, and nowhere in
the code the project runs. That is a smaller claim than "PCIe requires this", and
it is true.

### 1897 bytes, computed twice, by two tools that share no input

**現象** The self-signed chain needed some way to be more than "it was accepted".
Acceptance is a boolean and this repository does not publish booleans.

**假設** (a) report the file sizes and the handshake's exit code; (b) diff the
capture against the sample-chain capture and report the delta; (c) predict the
chain's size on the wire from the files on disk, then read it back out of the
capture with a tool that never opens a certificate.

**先驗哪個、為什麼** (c), because it is the only one that can be **wrong**.
(a) restates its inputs. (b) measures a difference without explaining it. (c)
makes a claim before the evidence exists, and the evidence can refuse it.

**根因** DSP0274 Table 39: the chain on the wire is a 4-byte little-endian
`Length`, then `RootHash` of H bytes, then the DER certificates. So

```
certs/check_chain.py, from the files:   4 + 48 + (504 + 573 + 768) = 1897
harness/fields.py, from the capture:                                 1897
```

and the second tool recovered `504 + 573 + 768` by walking DER through bytes it
read off the wire, and confirmed that the 48 bytes at offset 20 are `sha384` of
`certs/out/ca.cert.der`. `check_chain.py` never opens a capture. `fields.py`
never opens a certificate. Neither was told the other's answer.

**教訓** `CERTIFICATE` turned out to be over-determined by three rather than by
one, and the fourth equation is a different kind from the other three:

| | equation | |
|---|---|---|
| closure | message length = 16 + `LargePortionLength` | length |
| agreement | chain `Length` = `PortionLength` + `RemainderLength` | length |
| structure | the certificates parse as DER, consuming the chain exactly | length |
| **digest** | `RootHash` = SHA-384 of the first certificate | **not a length** |

> **Two lengths can agree because both were derived from the same wrong
> assumption. A 48-byte digest cannot.** Where a message carries a hash of
> something else it carries, that is the cheapest independent equation available,
> and it is worth going looking for.

It is reported rather than enforced, because DSP0274 permits a chain whose root
is not among its certificates — so a mismatch is a fact about the chain, not a
malformed message. CI feeds the tool an altered `RootHash` and requires the field
to turn false, which is a different assertion from requiring a refusal and had to
be written as one.

Two things the specification settled that the captures could not, and the
distinction is worth keeping. Table 39 makes `Length` **four bytes**, not two
beside two reserved — indistinguishable below 65,536 bytes, which is every chain
this project has captured. And Table 44 against Table 46 is asymmetric: the
request's large offset/length pair is **absent** when `Param1` bit 7 is clear,
while the response's 16-bit pair is **reserved**, meaning still present. Fou
zero bytes that a parser reading "reserved" as "absent" would swallow.

> **Arithmetic on the evidence answers the questions whose alternatives differ on
> the evidence. The others need reading, and the way to tell them apart is to ask
> whether the hypotheses produce different bytes here.**

### I replaced the certificate chain and replaced one third of it

**現象** The self-signed capture is 11,821 SPDM bytes against the control's
11,337. The chain is 242 bytes larger. 484 is not 242.

**假設** (a) my arithmetic is wrong; (b) the chain is fetched more than once;
(c) something else changed between the two arms.

**先驗哪個、為什麼** (b), because `fields.py` already prints
`responder slot 0: … fetched 2x` and had been printing it since week two. Zero
cost, and a factor of exactly two is the shape of a repetition rather than of an
error. **When a number is wrong by an integer multiple, check for a repetition
before checking the arithmetic.**

**根因** Confirmed in one line — this flow fetches the responder's chain twice,
once before `CHALLENGE` and once after mutual authentication, so 2 × 242 = 484.
That took a minute and was not the finding.

The finding was in the next line of the same output. In the arm running **my**
chain, the requester's certificate chain is still 3,794 bytes with a root hash of
`e59ee211…` — which is `sha384` of upstream's `rsa3072/ca.cert.der`. And slot 4
is still 1,660 bytes under `ed79ce9a…`, upstream's `ecp384` root.

**Four chain fetches, three distinct roots, one handshake.** Mine on responde
slot 0. Upstream's `ecp384` root on responder slot 4, because `--slot_count`
depopulates the *requester's* slots and not the responder's — which is itself a
thing I had written a wrong comment about, below. And upstream's `rsa3072` root
for the requester, because SPDM negotiates the requester's signature algorithm
separately, `ReqAsym` settled on `RSAPSS_3072`, and libspdm's sample library
picks its certificate directory from the negotiated algorithm. A chain installed
in `ecp384/` never serves the direction that chose `rsa3072/`.

**教訓** This is 2026-08-17 again, in a mechanism that has nothing to do with the
first one. That day the independent variable had two halves and only one was
pinned. Today the certificate material has three parts and I replaced one.

> **The shape of the mistake is not "I forgot a flag". It is "I described a thing
> in the singular that the system implements in the plural".** "The certificate
> chain", "the signature algorithm", "the measurement" — every one of those is a
> set in SPDM, and the singular is where the error hides.

The failure mode outside an emulator is worth stating plainly. A vendo
provisioning "the device certificate" replaces one chain, for one slot, under one
algorithm. Everything else keeps what it had, and on a reference design what it
had is the reference implementation's sample chain, whose private keys are
published in the upstream repository. The handshake completes. Every signature
verifies. Nothing in the flow says which anchor was used.

So the count is now a field: `layout.distinct_root_hashes`, re-derived from the
capture on every CI run. **The difference between having noticed something and
having measured it is whether it can go wrong again without anyone being told.**

### The one thing in that commit nothing could check was the comment

**現象** `harness/capture.sh` gained two arms with `--slot_count 1`, and a
comment explaining that the flag leaves only this project's certificates on the
wire. It was committed. The capture taken about an hour later shows the
responder's `ProvisionedSlotMask` is `0x13` and slot 4 is served from upstream's
chain, exactly as before.

**假設** (a) the flag did not take effect; (b) the flag does something other than
what I assumed; (c) the capture is of the wrong binary.

**先驗哪個、為什麼** (b), by diffing the two arms' `DIGESTS` lines, which is one
`grep`. (a) and (c) both accuse the apparatus, and the apparatus had just
produced six other arms that reproduced to the byte. **A tool that has just been
observed working is the last thing to suspect** — the same reasoning as the
alignment entry on 2026-08-28, and it was right for the same reason.

**根因** `--slot_count` sets the **requester's** provisioned slot count. Its
`DIGESTS` mask went `0x07` to `0x01`; the responder's stayed `0x13`. The flag is
worth keeping, both arms carry it identically, and the pair is still a
one-variable comparison — but the sentence explaining *why* it was there was
false.

**教訓** Every number in that commit was checked by something. The byte counts by
`fields.py`, the artifacts by a manifest, the claims by `--check`. The one
sentence that was wrong was the prose, and prose is the only thing in this
repository with no mechanism behind it.

> **The parts of a commit that nothing can check are exactly the parts most
> likely to be wrong, because they are the only parts where being wrong is
> free.** Rule 9 says a published number is marked up so a machine can re-derive
> it. There is no equivalent for a justification, and there probably cannot be —
> so the answer is to notice that a justification is a claim, and to be as
> suspicious of it as of a number.

The comment now says what the flag does, what it was believed to do, and which
capture refuted it. That is longer than the original and it is the useful length.

### A checking suite is a thing that has to be checked

Two of today's mechanisms failed on their first run, in different ways, and both
failures were about the suite's relationship to itself rather than to its
subject.

**現象 (i)** A new check reads every tracked file and refuses a PEM private-key
header in any of them. It failed immediately. The file it found one in was
`harness/verify_repo.sh` — the check itself, which lists the headers it forbids.

**現象 (ii)** `certs/check_chain.py --self-test` breaks the chain four ways and
requires each to be rejected. All four were rejected. Two of them by the same
message.

**先驗哪個、為什麼** Neither needed a hypothesis. (i) prints the offending path.
(ii) prints the rejecting message, and reading four lines was enough to see that
two were identical. Both were found by looking at output that was already there —
which is the point: **a suite that reports only pass or fail hides this class of
defect completely, and one that prints what it did shows it for free.**

**根因** (i) A checker that spells out what it forbids becomes an instance of it.
The markers are assembled from pieces at run time now, so no tracked file
contains the byte sequence and the check's answer about this file is the true
one.

(ii) The bundle was compared against the concatenation of the individual
certificate files *before* being walked as DER. That comparison catches
everything the walk would catch, so the walk had never rejected anything — it was
arithmetic that happened to agree, which is precisely what rule 11 exists to
prevent, inside the suite written to demonstrate rule 11. Swapping the two gave
each check something only it can find: the walk catches a malformed bundle, the
comparison catches a well-formed bundle holding the wrong certificates.

**教訓** Rule 11 is not sufficient on its own, and rule 13 is now written down:

> **Two breaks caught by the same check are one check.** A suite where fou
> broken inputs are all refused by the cheapest check reports four times the
> coverage it has. So the self-test asserts that the rejections arrive through
> *distinct* mechanisms, and prints how many.

The same assertion is in the `CERTIFICATE` negative test — four rejections
through four distinct checks — and it is cheap enough that it should probably be
in all of them.

### I wrote d1's mistake again, eleven days after documenting it

**現象** `d6` is the packed-struct drill. Its first version was built on the
five-byte MCTP transport framing, on the reasoning that `harness/verify_repo.sh`
asserts `pcap bytes == SPDM bytes + 5 × messages`, and that taking the 5 from
`sizeof` would be the classic padding mistake. Compiled against a correct
reference implementation, two checks failed. Compiled against the *wrong* one,
the same two failed.

**假設** (a) the reference implementation is wrong; (b) the tests are wrong;
(c) the premise is wrong.

**先驗哪個、為什麼** (c), by one `printf` of `sizeof` and `_Alignof`. Cheape
than reading either the tests or the implementation, and it is the assumption
that both of the others rest on. **When a correct implementation and a wrong one
fail identically, the thing they have in common is the suspect, and what they
have in common is the premise.**

**根因** Upstream's `mctp_header_t` is four `uint8_t` members. Its alignment is
1, `sizeof` is exactly 4, the framing struct is exactly 5, and there is no
padding to be wrong about. The trap could not fire.

This is the same defect `d1` had on 2026-08-28 — "do not cast the buffer to a
struct pointer, it faults on ARM", for a struct whose alignment is 1 — and it was
written a second time by the person who wrote that entry.

**教訓** `d6` moved to `spdm_measurement_block_dmtf_header_t`: a `uint8_t`
followed by a `uint16_t`, three bytes on the wire and four in C, where the
padding moves a **field** as well as a **size**. Beside it in the same drill sits
`{uint8_t, uint8_t, uint16_t}`, which is identical packed or not, so the contrast
is the lesson instead of the rule that packing is always needed. `spdm.h` opens
with `#pragma pack(1)` on line 14 and closes it 1,813 lines later, which settles
what upstream thinks.

The test bytes are 38 real bytes from packet 30 of this week's capture, and they
close: `MeasurementSize` 11 = 3 + `ValueSize` 8, and 19 = 3 + 16. With `sizeof`
the first test reads 11 = 4 + 8 and the walk stops.

> **Knowing a lesson is not the same as being able to recognise the situation it
> applies to.** I could recite d1's finding. I did not notice I was constructing
> it again, because the two structs look nothing alike and the reasoning that
> produced the error was the reasoning I would use to check it.

The mechanism that caught it is the one written *because* of d1: every drill's
tests are compiled against a correct implementation and against the wrong one the
drill exists to teach, in a scratch directory, before the drill is committed.
That is now rule 15. The general form is worth more than the drill:

> **Before writing a check, compile the failure. Reasoning about whether a trap
> fires is exactly the reasoning that produced the trap.**

`d5` passed the same gate for a different reason, and it is worth noting because
the outcome looked identical. Its wrong version — `p[0] << 24` on a `uint8_t`
promoted to a signed `int` — produces the **correct value** on every compile
anyone will use. Only UndefinedBehaviorSanitizer separates it from the right
answer. A drill that checked values alone would have taught nothing and passed.

### A tool change and an evidence run are one unit of work

**現象** Today's baseline was captured twice, forty minutes apart, and only the
second is committed.

**根因** Not a mistake, a cost. `capture.sh` writes a `*.fields.json` beside each
capture, and ADR 0004 requires a committed derivation to reproduce from its
inputs. Extending `fields.py` after a run makes every derivation in it false
while its digest still matches — the 2026-08-28 finding, arriving this time as a
scheduled expense rather than as a surprise. I extended `fields.py` twice: once
for `CERTIFICATE`, and again for `DIGESTS` and the chain list, after the first
capture had already been taken.

**教訓** The first run was moved out of `bench/data/` rather than deleted, and it
was never committed, never cited, and is not evidence of anything. But the
sequencing lesson is real:

> **A tool change and the evidence run that follows it are one unit of work.
> Planning them as two is how a stale derivation gets committed** — and the only
> reason one did not is that the check added on 2026-08-28 went red.

Which is the more useful half of this entry. The check that made today cost an
extra six minutes is the same check that made 08-28 cost a re-run of five arms.
It has now been observed working twice, on the same failure, and both times the
alternative was publishing a number that was quietly false.

### The 08/31 window, and what it is honestly worth

DMTF's SPDM 1.5 hybrid-PQC industry review closed today. The WIP is eight pages
and was read in full; DSP0274 1.4.0 was read only where a captured field name led.
Both PDFs' digests are recorded, and the WIP's own page 8 gives the deadline and
the channel — which is what `plan/W03` said to verify rather than assume, and it
was worth doing, because the page asks **two specific questions** rather than
inviting general comment. One of them is *does your company require algorithm
combinations besides the highlighted ones*, which a graduate project cannot
answer and should not pretend to.

The angle chosen is a tension inside the WIP's own text. The hybrid guideline
says message fields carrying a certificate chain will hold "the concatenation of
two pieces of data for the two algorithms". Requirement 2 says a 1.4 device that
already has a Traditional chain and a PQC chain is upgradeable. But such a device
holds them in **two slots**, each fetched and cached independently through
`GET_DIGESTS`, and concatenation puts them in one. This project has measured both
sides — 1,655 bytes and no chunking classically, 16,853 bytes and fou
`CHUNK_GET` round trips with ML-DSA-65, on one binary against a negotiated
`DataTransferSize` of 4,608.

The draft is 297 words, asks rather than asserts, and every number in it names
the run and the claim key that checks it. The one figure that is arithmetic
rather than measurement — the rough size of a concatenated hybrid chain — says so
in the draft itself.

**`TODO(me)`** — it is not sent. It needs a DMTF portal account and it has to be
in your own words rather than a draft's. If it goes unsent, that is recorded as a
missed window and not quietly dropped: *"I read the WIP during the review period
and wrote a question I did not send"* is a true sentence and *"I submitted
feedback"* would not be.

Evidence strength was written down before anyone could ask: **lower than a GitHub
pull request.** A portal submission may produce no public URL, no review thread
and no confirmation it was read. It is evidence of **timing** — that the
implementation and the standards draft were being worked on in the same weeks —
and G7 still rests on the two repository candidates.

### The same comment was wrong twice in one day, in two files

**現象** After everything above was committed and pushed, I re-read every tracked
document against what the day had actually produced. Twenty-six markdown files,
**zero dangling links**, and the two gate tables agreeing row for row — and five
things stale, one of which had been stale since before the day started.

**假設** for the one that mattered: `docs/threat-scope.md` says the certificate
chain is "self-signed and trusted by configuration". Is that (a) still true,
(b) true but now incomplete, or (c) false?

**先驗哪個、為什麼** (b), because the day's own finding decides it and no new
work was needed to check. Three roots were measured; the document describes one
chain. **A statement that was true when written and is now a weaker version of
what was measured is worse than no statement**, because it reads as the current
state and a reader has no reason to doubt it.

**根因** The other four have one shape between them, and it is the shape of an
entry written six hours earlier on this same page:

| file | what was stale |
|---|---|
| `.github/workflows/ci.yml` | a comment listing what the `verify` job does — four checks, where it now runs twelve |
| `harness/doctor.sh` | "affects W03 certificate signing only", the twin of a message already corrected in `healthcheck.sh` |
| `docs/transports.md` | a footer naming the 08-28 run as though it were the current one |
| `RUNBOOK.md` | an interview line quoting 128/128 in the present tense |

**Every one of them is prose.** Not a number — `--check` re-derives 174 of those
against captures. Not an artifact — the manifests re-hash 258 tracked files. Not
a version — the pins compare themselves. **Prose.**

**教訓** The entry above says the parts of a commit nothing can check are the
parts most likely to be wrong, because being wrong there is free. That entry was
written about one comment. The re-read found four more, in files nobody had
touched, including one describing a CI job whose contents had roughly tripled.

> **There is no mechanism for prose, and the honest consequence is not to invent
> a weak one — it is to schedule the re-read.** The claim checker, the manifest
> re-hash and the pin comparison all exist because a person cannot be relied on
> to remember. Documentation drift has no equivalent, so the only tool left is
> going back and looking, on purpose, at a fixed point in the week.

Two things were also **missing** rather than stale, and both are the same
omission. Every citation of DSP0274 and of the SPDM 1.5 draft named a title and
a version and nothing else — but a version number does not identify a document,
since a working draft, a published revision and an errata update can all be
"1.4.0" to someone who found the PDF by searching. So both specifications are
now pinned by SHA-256, with the **list of sections actually read**, which is the
part that bounds the claim: DSP0274 is 306 pages and this project has opened
five tables and four clauses of it.

`quoted-in=` makes it a mechanism rather than a note: `verify_repo.sh` requires
every file a pin names to carry that pin's digest, so moving a pin without
moving the documents turns the build red. That is `CLAUDE.md`'s standing
instruction to grep for the old version number after touching a pin, with the
remembering removed — and 2026-08-16 is the day that instruction was needed and
not followed.

The check was broken twice before being believed: a digest moved by one
character, and a `quoted-in=` naming a file that does not exist. Both rejected.

**`TODO(me)`** — the re-read is currently a thing that happened once because
somebody asked. It should be the last item of the end-of-day list, not the
thing after it, and `CLAUDE.md` should say so. Until it does, this is a
discipline, and the whole argument of this repository is that disciplines are
the things that fail in week six.

### What is measured, and what is still a claim about myself

**`TODO(me)`** — `c-drills`. `d5` and `d6` now exist with contracts, tests and
stubs, both validated against reference implementations that were deliberately
not committed. That makes **four** drills waiting and **zero** finished.
`DONE.txt` is empty for the fourth working day running and `SCORECARD.md` has
eight blank rows.

Day 2 called this a risk. Day 3 called it a fact and the largest gap in the
repository. Today it is the same fact with two more rows in front of it, and the
honest description has changed shape: the project track is not merely running
ahead, it is **generating work for a track that has never started**. Two more
specifications for an implementer who has not written one yet is not progress on
that track; on some readings it is the opposite.

There is no mechanism that can fix this, and that is the point of it. Every othe
gap in this repository got closed by writing a check. This one measures whether I
can write C with nothing to ask, and the only thing that moves it is sitting down
with paper for twenty minutes.

**`TODO(me)`** — 緯穎 whitepaper, still unread. Third carry. Day 3 said a
carried item gets scheduled or dropped honestly at the second carry rather than
carried a third time, and this is the third. **Dropped**, not carried: it is not
on the W04 plan and pretending otherwise has cost three lines a week for three
weeks.

**`TODO(me)`** — W04 prerequisite, checked today rather than on the morning it is
needed: `os_stub/spdm_device_secret_lib_sample/` holds 21 files and `meas.c` is
33,452 bytes, exactly as `plan/W03` §8 predicted. And the hard-coded security
version number it warns about is not only in the source — it is on the wire. It
is `07 00 00 00 00 00 00 00`, the eight-byte value of measurement block index
`0x10`, `ValueType 0x87`, and it is now the test data in `c-drills/d6`. **A
constant that has to become configurable before any RATS policy can be tested
against more than one input, measured before the week that has to change it.**

**`TODO(me)`** — `CERTIFICATE` and `DIGESTS` are reconstructed; `VERSION`,
`CAPABILITIES` and `ALGORITHMS` are not, and §10 now says why rather than just
that. They have no signature, no echoed nonce and no self-declared inner length,
so there is no spare equation. `ALGORITHMS` may be reachable through its
`AlgStructure` count and `VERSION` through its version-entry count. Neither has
been tried, and neither is claimed.

**`TODO(me)`** — What I am least sure about right now: _______________


## 2026-09-01 · Day 5 · one byte, three places, and the layer that was not there

### Two predictions were written down, and the capture chose the other one

**現象** `plan/W04` §3 says tamper point ① — flip one byte of the device's own
measurement — makes the requester fail at **measurement signature
verification**. Before touching anything I read `meas.c` and predicted the
opposite: the handshake would complete, exit 0, every signature verifying.
Both predictions went into the record before the run.

The capture: `t1_meas`, exit 0, 30 packets, `CHALLENGE_AUTH` present,
`MEASUREMENTS` present, and the 528-byte measurement record differing from the
control in **exactly one of its eight blocks** — index `0x01`, the one whose
pre-image was changed.

**假設** Three, before running:

1. the signature check fails, because the record no longer matches — the plan's
   answer;
2. the handshake completes, because the responder signs what it actually sent,
   so the pair the requester verifies is self-consistent;
3. it completes but something else complains — the `MeasurementSummaryHash` in
   `CHALLENGE_AUTH` disagreeing with the blocks, say.

**先驗哪個、為什麼** (3) first, and by reading rather than running, because it
was the only one that could have been settled the wrong way by an accident of
this emulator's flags. It falls immediately:
`libspdm_generate_measurement_summary_hash` obtains its blocks by calling
`libspdm_measurement_collection` — the same function — so both sides of that
comparison move together. That also answered a design question I had been about
to get wrong, which is whether the summary hash needed a third hook. It did not.

With (3) gone, (1) and (2) differ on one question — *whose bytes does the
signature cover* — and that is a question the capture answers definitively. So
the run was worth doing rather than arguing about.

**根因** The responder signs a transcript of the messages it has sent, with its
own key. Change the input and it computes a new record and signs **that**. For
a signature check to fail, the bytes signed and the bytes verified have to
differ, and there are exactly two ways to arrange that: change them in flight,
or sign with a key that does not match the presented certificate. Changing the
source is neither.

The certificate chain behaves differently for a reason that is easy to say and
easy to skip past: the requester holds an **anchor it was given out of band**. A
measurement has no anchor. The requester has no idea what this device's firmware
hash should be, and nothing in SPDM gives it one.

**教訓** The plan's own diagram draws reference-value comparison *outside* the
protocol, and its table then predicted the protocol would do it. Both were
written by the same person on the same day. **A document can contradict itself
across two representations of the same thing, and the prose is the half that
will be believed**, because a table row is a sentence and a diagram is work.

The transferable version, and the sentence this whole week exists to be able to
say:

> SPDM proves that a measurement came from this device. It does not prove that
> the measurement is correct. The first is a signature; the second needs
> reference values, and reference values are not in the protocol.

A tampered measurement passing every check this repository currently owns is
not a disappointing result. It is the empirical case for Gate 3, and it is
stronger than the argument for Gate 3 was yesterday.

### The certificate byte flip failed earlier than expected, and for the wrong reason

**現象** `t3_cert` flips one byte inside the intermediate certificate's ECDSA
`s` value — chosen by `certs/check_chain.py --locate` so the certificate still
parses and exactly one link breaks. Result: exit 1, 10 packets, no
`CHALLENGE_AUTH`. The week's DoD is met and the pcap proves it.

I nearly wrote "the requester rejected the tampered certificate chain". That
sentence is false.

**假設** Why did it stop?

1. the requester verified the chain and refused it — the expected path;
2. the responder never served the chain at all;
3. the responder crashed at startup and the requester found nothing listening.

**先驗哪個、為什麼** (2), because it is the one the capture can settle without
any further runs, and because the decode already contained the thing that
settles it — I had simply read the error line first. There is **no
`CERTIFICATE` message anywhere in the capture**, and the last message is
`SPDM_ERROR(InvalidRequset)` in answer to `GET_CERTIFICATE`. (3) dies at the
same time: the responder answered eight messages before that.

Then one field: `ProvisionedSlotMask` is `0x13` in the clean run and **`0x12`**
here. Slot 0 is gone.

**根因** `libspdm_read_responder_public_certificate_chain` calls
`libspdm_verify_cert_chain_data` on the file it just read and returns false
(`read_pub_cert.c:447`). The device refused to serve a chain it could not
itself validate — which is good behaviour, and is not the certificate-chain
*verification* the tamper point was meant to exercise.

And the failure is silent. `spdm_responder_emu` assigns `res` three times —
slot 0, slot 1, slot 4 — and tests it once
(`spdm_responder_spdm.c:495-553`), so the slot-0 failure is discarded. `data`
stays `NULL`, the slot is left unprovisioned, and the responder starts
normally. **The only trace anywhere is one bit in a mask field on the wire.**

**教訓** Three artifacts described this run and they answered three different
questions: the exit code said 1, the requester's log said
`do_authentication_via_spdm - 8001000a`, and the pcap said *no certificate was
ever sent*. Only the third is about the thing being tested. That is the same
shape as 2026-08-11, where `tee`, the requester and `spdm_dump` each answered a
slightly different question and the plausible summary was wrong — and the rule
from it held again today: **look at the evidence, not at `$?`.**

The narrower lesson is worth keeping separately: **a byte flipped on the
device's own disk cannot reach the requester's verifier, because the device
checks first.** Reaching that verifier requires corrupting bytes after the
device has loaded them — which is tamper point ②, and this is now an argument
for building the proxy rather than a plan item that says to.

### The case that had to be added, and the one that did not fail

**現象** If corrupted bytes cannot reach the requester's chain verification,
then nothing measured this week exercises it. So: leave the chain internally
perfect and change *whose* it is. `t3b_foreign` has the responder serve DMTF's
own `ecp384` chain, signing with DMTF's leaf key, while the requester's trust
anchor is still this project's root — a different file, left alone.

The handshake **completed**. Exit 0, 30 packets, every signature verified,
against a device whose entire chain descends from a CA the requester was never
given.

**假設** 1. the swap did not take effect and our chain was served anyway;
2. the requester does not check the root at all in this configuration;
3. it checks, and does not treat the answer as fatal.

**先驗哪個、為什麼** (1) first, because it is the cheapest and because a
harness bug that looks like a finding is the worst outcome available. The
capture: slot 0 carried **1,655 bytes rooted at `ed79ce9a…`** where the clean
run carried 1,897 rooted at `df0ee8f9…`, and `distinct_root_hashes` fell from 3
to 2. The swap took.

Then (2) against (3), by reading libspdm rather than inferring from behaviour.
`libspdm_verify_peer_cert_chain_buffer_authority` exists, walks every
provisioned root, and returns false when none matches. So it checks.

**根因**

```c
/* Provided cert is valid but is not authoritative(mismatch the root cert). */
#define LIBSPDM_STATUS_VERIF_NO_AUTHORITY \
    LIBSPDM_STATUS_CONSTRUCT(LIBSPDM_SEVERITY_WARNING, LIBSPDM_SOURCE_CRYPTO, 0x0003)
```

`SEVERITY_WARNING`. And `libspdm_try_get_certificate` sets that status without
a `goto done` — unlike the integrity check three lines above it, which has one
(`libspdm_req_get_certificate.c:483-496`). The status survives to the return,
and `spdm_requester_emu` calls the API form that discards the trust anchor and
tests `LIBSPDM_STATUS_IS_ERROR`. A warning is not an error.

**This is a design decision, not a defect.** libspdm returns a distinct status
and an out-parameter naming the anchor precisely so an integrator can apply
policy — a device may legitimately present a chain from a CA the verifier
learns about by other means. What the sample application does with it is what a
sample does.

**教訓** The finding is not "libspdm accepts untrusted chains". It is:

> An integrator who checks only `LIBSPDM_STATUS_IS_ERROR` has silently accepted
> every certificate chain that parses. On a real BMC that is the difference
> between "this device is genuine" and "this device presented well-formed
> papers".

Two things about how this arrived. First, **the experiment that failed to
measure what it was designed to measure is what produced the experiment that
did.** `t3b_foreign` is not in any plan; it exists because `t3_cert`'s result
made the gap visible. That is the sequence worth being able to describe.

Second, and less comfortable: **the same acceptance is in a capture I committed
a week ago.** `w3-baseline-20260831T143123Z/selfsigned`, packet 12, slot 4's
chain, root `ed79ce9a…` — in neither of the two roots that requester
provisioned. Week 3 counted three trust anchors and called it a finding. It did
not ask whether the requester had been given all three. The number was on the
page and the question was not, which is a more useful description of how this
was missed than "I did not notice".

### A distinctness check that could not distinguish

**現象** `docs/roadmap.md` standing rule 13, added on 2026-08-31, says two
breaks caught by the same check are one check. So the new measurement-record
walk got a suite: four malformed records, each required to be refused, and a
check requiring the four refusals to be *distinct*. It passed on the first run.
It should not have.

**假設** The four cases were caught by 1. four different checks; 2. fewer, with
the distinctness test too weak to notice; 3. fewer, and the test was right but
I misread it.

**先驗哪個、為什麼** (2), because the distinctness test was mine and written
ten minutes earlier, and because reading four lines is cheaper than reasoning
about four code paths. It keyed on the refusal **message**:

```python
key = (rec["why"] or "").split(":")[0].split(",")[0][:28]
```

Two of the four cases produced *the same check* — a block whose declared size
runs past the record — and two different sentences, because the sentences
interpolate the size. `...declares 99 bytes` and `...declares 900 bytes` differ
in the twenty-eighth character. The keys differed; the checks did not.

**根因** The case meant to exercise "MeasurementSize disagrees with the DMTF
value size" used a size of 99 in a 30-byte record, so the length test caught it
first and the equation being tested never ran. Fixing the fixture is one line —
use a size that fits and still disagrees. Fixing the *test* is the real repair:
every mechanism that has to report which check rejected something now returns a
stable code beside the prose (`why_kind` in `fields.py`, `ms_status_t` in
`device/`), and the suite compares codes.

**教訓** Rule 13 was written to stop a suite from reporting more coverage than
it has. Its first implementation reported more coverage than it had, in the
same way, one day after being written. **A rule about redundant checks needs a
mechanism to decide what "distinct" means, and a prefix of a formatted string
is not one** — it is a fingerprint of the interpolated data, not of the code
path.

That is now rule 16, and the shape it generalises to is worth more than the
instance: **when a check's answer is going to be compared, the thing compared
has to be a category the code chose, not a rendering the code produced.** It is
the same reason this repository asserts on `layout.*` keys rather than on
`fields.py`'s printed table.

### Changing one tool made every derivation it had ever produced false

**現象** Adding the measurement-record walk to `fields.py` turned
`verify_repo.sh` red in a step that had nothing to do with it: seven committed
`*.fields.json` under `w3-baseline-20260831T143123Z` no longer reproduce from
their own decodes. Nothing about those captures changed. The tool did.

**假設** 1. regenerate the seven files in place; 2. re-stamp the manifest that
attests to them; 3. take a new run.

**先驗哪個、為什麼** None of them, first — check what the repository already
decided. `docs/decisions/0004` and the 2026-08-28 entry cover this exact case
and reject (1) and (2) in as many words: a manifest says a file is unaltered,
not that it is still true, and *"there is no mechanism here for re-stamping a
manifest and there should not be"*. So (3), and the question left was which
binary should take it.

**根因** The patched responder was in the tree. A baseline taken from it would
still be correct — with no fixture named, the added lines do nothing — but the
control for `docs/tamper.md` would then come from a binary carrying the code
under test. So the patch was reverted, the tree rebuilt, `w4-baseline` taken
from a binary with no patch in it, and the patch re-applied and rebuilt after.
Two rebuilds to keep one sentence honest.

All seven arms reproduced to the packet: 554/20,549, 584/114,751, 566/20,396,
30/11,441, 30/11,441, 30/11,337, 30/11,821 — the same numbers as 08-16, 08-28
and 08-31, now from a binary that had been rebuilt twice in between.

**教訓** The cost is not the rerun; it is that the cost is **invisible when the
tool is changed**. `fields.py` grew one key and that was a four-minute
consequence in a repository with eleven runs. At thirty it is not four minutes,
and nothing warns you at the moment of writing the key.

So the invariant that mattered got a mechanism rather than a re-run. The
528-byte stock measurement record is the number both of `docs/tamper.md`'s
control claims rest on, and `verify_repo.sh` now re-derives it **from the
decodes** — not from the committed derivations — across every baseline run in
the repository: one SHA-256, fourteen arms, five runs, four dates, two
certificate chains, and binaries built before and after the patch existed.
**A derivation goes stale when its tool changes. A capture does not.** Checks
that have to survive a tool change should be written against the capture.

### Two upstream candidates, found the same way as the last one

**`TODO(me)`** Both are in `docs/upstream/README.md` with the capture that
produced them: the discarded slot-0 read result above, and the requester that
never inspects `NO_AUTHORITY`. Neither is submitted. Both are small,
documentation-adjacent, and neither is a vulnerability — the second is
explicitly a hand-off the library underneath designed on purpose.

Stating what they are worth before anyone asks: what they demonstrate is
reading a reference implementation closely enough to find where its samples
stop being examples, with a committed capture behind each. *"I found a security
bug in libspdm"* is not the claim, would not survive review, and is the version
of this that a portfolio is tempted into.

G7 now has **four** candidates and **zero** submissions. Four candidates is not
four times better than one. The count going up while the submission count stays
at zero is the thing to watch, and this is the second week it has done that.

### The stub that did not compile, and the third condition nobody had written down

**現象** `c-drills/d4_bst_delete.c` was validated the way rule 15 requires:
compiled against a correct implementation (30/30 pass, no leaks) and against
the wrong one the drill exists to teach (caught by six checks *and* by
LeakSanitizer, which the lost subtree also leaks). Then the committed version —
the stubbed one, the one that actually goes in — **failed to compile**, twice,
under `-Werror`.

**根因** Both were the test harness reasoning about a stub that returns
`(size_t)-1`. `-Wmaybe-uninitialized` on a buffer the stub never fills, and
then `-Wstringop-overread` on a `memcmp` whose bound gcc could prove was
`(size_t)-1` — because the only path past `if (k != n)` while `bst_inorder`
always returns `(size_t)-1` is one where `n` is also `(size_t)-1`. gcc was
right both times, and the second one found a helper that could not state its
own limit.

**教訓** Rule 15 names two conditions — the correct implementation passes, the
wrong one is caught — and CI enforces a third that the rule does not mention:
**the stub compiles.** `make` builds every drill so a syntax error is caught
immediately, so a drill whose stub does not build turns the badge red on the
day it is committed, with nothing written down. Validating a drill means three
compilations, not two, and only two of them are about the exercise.


### Four places this week left the plan, and what each cost

**現象** `CLAUDE.md` says every deviation from the plan goes in this file with
the reason, and the entries above record two — the secure version number being
a `uint64_t` rather than the plan's `uint32`, and `--flip-byte 12` landing in
that field instead of in a measurement. Re-reading `plan/W04` against what was
actually built found two more that had gone unrecorded, plus one shape change
worth stating.

**根因** All four have the same origin: the plan was written on 2026-08-11,
before the code it describes existed, and its specifics are guesses about an
interface nobody had designed yet. That is not a defect in the plan. It is what
a plan is.

| the plan says | what exists | why |
|---|---|---|
| `./harness/run_pair.sh t0_clean …` | `harness/tamper.sh` | `run_pair.sh` has never existed. `capture.sh` and `lib/handshake.sh` already own "start a responder, wait for the socket, run a requester, keep the evidence", and a second copy would be a second place for its four failure modes to be wrong differently |
| `docs/meas-c.patch` | `device/meas-from-file.patch` | it is source, not documentation, and `device/README.md` already declared patches to be this directory's artifact kind. `docs/` links to it |
| `bench/data/{t0_clean,t1_meas,t3_cert}/` — three run directories | one run directory, seven cases by prefix | a run directory is one `prov_begin`/`prov_finish` pair, and these seven cases share a control, a chain, a build and a set of flags. Splitting them would produce seven manifests attesting to the same provenance and no place for `cases.tsv` to live |
| `--svn N` and `--flip-byte N` | both, plus `--flip-block/--flip-offset` | `--flip-byte` alone makes the caller compute a file offset by hand, and the offset that matters is *inside a value*. The by-block form reports the absolute offset, which is what `docs/tamper.md` has to state |

**教訓** Three of the four are the same decision made three times: **use the
mechanism that already exists rather than the name the plan happened to use.**
The fourth is the one the plan could not have got right, because the file
format it addresses did not exist when it was written.

What is worth extracting is the failure mode I nearly had. Deviations one and
three were made without being noticed as deviations at all — `run_pair.sh` was
absent, `tamper.sh` was obviously the right shape, and the plan's sentence
simply stopped being read. **An unrecorded deviation is not a decision, it is
drift**, and the difference between them is entirely whether somebody wrote
down the alternative that was rejected. The two that did get recorded were
recorded because the plan was *wrong* and being wrong is loud. The two that did
not were recorded nowhere because the plan was merely *stale*, and stale is
quiet.

So the re-read that found them is the same instrument as the one on
2026-08-31, pointed at a different target: that one compared documents against
the day's results, this one compares the day's results against the plan. Both
exist because there is no mechanism for either, and the honest response to that
is to schedule the reading rather than to invent a weak check.

### The same file went stale again, and the re-read was still not scheduled

**現象** Yesterday's last entry ended with a `TODO(me)`: the re-read that had
just found five stale documents *"is currently a thing that happened once
because somebody asked. It should be the last item of the end-of-day list, not
the thing after it."*

Today it happened once because somebody asked. It found eight things, and one
of them is `.github/workflows/ci.yml` — **the same file, the same comment, for
the same reason.** Yesterday it named four checks where the job ran twelve.
Today it named ten where the job runs twenty-two.

**假設** Why did a day's work leave eight documents behind?

1. carelessness — the documents were forgotten in the rush to push;
2. the documents are not reachable from the work, so nothing pointed at them;
3. they were reachable but the pointer only exists in one direction.

**先驗哪個、為什麼** (1) is untestable and flattering to reject, so it goes
last. (2) is checkable in one command and false: `verify_repo.sh` reports zero
dangling links across twenty-eight markdown files, and every one of the eight
is linked from something.

(3) is the one that survives, and the eight sort cleanly into two kinds:

| kind | what it is | examples |
|---|---|---|
| **a summary of a mechanism** | prose that restates what a script does, kept in a second place | `ci.yml`'s comment, `certs/README.md`'s usage block, `c-drills/README.md`'s table, the RUNBOOK's command appendix, `README.md`'s manifest list |
| **a statement a new measurement contradicts** | prose that was true and is now weaker than what is known | `threat-scope.md`'s "trusted by configuration", `rats-roles.md`'s "show that tampering changes the evidence — G2" |

**根因** Both kinds have the same shape and it is not carelessness. **The work
points at the document; the document does not point at the work.** `tamper.sh`
does not know that `RUNBOOK`'s appendix lists commands. `verify_repo.sh` does
not know that `ci.yml` describes it. The measurement that made "trusted by
configuration" too generous did not know that sentence existed.

Every one of them is a **second copy** — of a step list, of a usage line, of a
belief — and a second copy has no mechanism connecting it to the first. That is
the same finding as yesterday, stated one level up: *there is no mechanism for
prose.* Yesterday's version was about a comment. This one is about a category.

The eighth was different and worth separating: there was no
`docs/decisions/0006`. Patching a pinned build tree changes what "the pin
describes the binary" means, which is the foundation of ADRs 0001 and 0003, and
`CLAUDE.md` says a decision that changes the repository's shape gets a record.
That one was not stale — it was **absent**, and absence is the failure mode a
re-read is worst at catching, because nothing is there to read.

**教訓** Yesterday's TODO said the re-read should be scheduled rather than
requested. It was not, and the cost was one file going stale twice in two days.
So it is now the sixth item of the end-of-day list rather than a note about
one, and `ci.yml`'s comment says out loud that it is a summary which has
already rotted once and that the script is the list.

But the sharper lesson is about which documents to re-read, because "re-read
everything" does not survive week six either. **The ones that rot are the
second copies**, and they are enumerable: a comment describing a script, a
usage block listing a tool's modes, a table indexing files in a directory, and
any sentence stating what a measurement has not yet been taken to check. Four
shapes. That is a list short enough to actually walk.

And one of them cannot be caught by re-reading at all. A missing ADR is not a
stale sentence; it is a decision that was made without being written down, and
the only prompt for it is asking *"did anything I did this week change the
shape of the repository?"* — which is a question, not a document.
### What is measured, and what is still a claim about myself

**`TODO(me)`** — `c-drills`. `d4` now exists with a contract, tests and a stub,
validated three ways. That makes **five** drills waiting and **zero** finished.
`DONE.txt` is empty for the fifth working day running.

Day 2 called this a risk, Day 3 a fact, Day 4 "the project track is generating
work for a track that has never started". Today is the fifth day and the
description has not needed to change, which is itself the finding. There is no
mechanism that can close this one and that is the point of it: it measures
whether C can still be written with nothing to ask, and the only thing that
moves it is twenty-five minutes with paper.

**`TODO(me)`** — Table 1 has no row showing a signature verification actually
failing. Two of three tamper points are measured and **neither of them is
detected by a signature**: one is not detected at all, and one never reaches
the wire. Point ② is now the only case that would produce that row, which makes
next week's proxy load-bearing in a way the plan did not anticipate.

**`TODO(me)`** — `--flip-byte 12`, the example in `plan/W04`'s own text, lands
inside the secure version number rather than in a measurement value. The
generator refuses it and says so. Worth noting because the plan was written
before the file format existed, and it is the second thing this week where the
plan's specifics were overtaken by reading the source — the first being that
the secure version number is a `uint64_t`, not the `uint32` the plan describes.

**`TODO(me)`** — What I am least sure about right now: _______________

## 2026-09-10 · Day 6 · the same byte on both sides of one signature

Week five, taken nine days after week four ended. Table 1 is finished, and the
row that carries it is the one where nothing happened.

### A document misled its own author for nine days, and that is the measurement

**現象** Today started with "I am not sure whether the last session ended at
week three or week four — the RUNBOOK says week three." It says week three
because `RUNBOOK.md` §0, the thirty-second summary at the top, still read
**"W03 收工(2026-08-31)… 三個篡改點還沒開始"**. Section 8.8 of the *same
file*, 850 lines further down, explains all three tamper points in detail. The
file had been contradicting itself since 2026-09-01.

**假設** Why did the first screen rot while the section it contradicts was
being written?

1. carelessness on a busy day;
2. §0 is not reachable from the work, so nothing pointed at it;
3. the end-of-day list does not mention it;
4. the re-read that was supposed to catch exactly this was pointed somewhere
   else.

**先驗哪個、為什麼** (3) is checkable in seconds and false: `CLAUDE.md` item 4
says *"進度有變就更新 RUNBOOK.md"*, which covers it exactly. (2) is false too —
`git log` shows `RUNBOOK.md` was edited twice on 09-01, once to add §8.8 and
once to extend the appendix. The file was open. The screen was not read.

(1) and (4) are the same answer told at two altitudes, and (4) is the one that
transfers. 2026-08-28's commit is literally titled *"a runbook first screen that
is not stale"*, so the failure mode was known, named, and fixed once by hand
eleven days before it recurred.

**根因** The 09-01 entry enumerated four shapes of second copy that rot — a
comment describing a script, a usage block listing a tool's modes, a table
indexing a directory, and a sentence stating what a measurement has not yet been
taken to check. **It missed a fifth, and the fifth is the one with the most
readers: a status summary of the whole repository.** Every one of the four it
named is a *local* copy, describing a thing next to it. §0 describes
*everything*, so nothing in particular is next to it, and no piece of work feels
responsible for it.

**教訓** Two, and only one of them is a mechanism.

The mechanism: `verify_repo.sh` now extracts a state token per gate from all
three tables — `README.md`, `docs/roadmap.md`, `RUNBOOK.md`, in two languages
and three formats — and requires them to agree, plus the week number from the
two files that state one. `CLAUDE.md` already required two of the tables to be
kept in step; that was a discipline, and the difference between a discipline and
a mechanism was nine days.

The honest part: **that check would not have caught today.** The three tables'
G2 rows all said "in progress" and all three were right. What rotted was the
prose beside the state token, and the week number at the top. The week number is
mechanisable and is now checked; the prose is not, and pretending otherwise
would be worse than admitting it. What is genuinely new is only this: a reader
who is told "week three finished" stops reading before the section that explains
week four, so the week number is the load-bearing half of a first screen even
though it is the least interesting fact on it.

And one more thing worth writing down: **the bug report was a person being
confused.** No script produced it. That is the only kind of evidence there is
for a documentation defect, and it arrived nine days late because there was
nobody else reading.

### The week's headline claim was refuted by the previous week's own capture

**現象** `plan/W05.md` §0.6 gives the sentence the week is supposed to earn:
*"其中兩個會產生一模一樣的錯誤訊息 —— 改量測值跟改傳輸中的簽章"*. Point 1 does
not produce an error message. `t1_meas` completed on 09-01 with exit 0 and every
signature verifying, and `docs/tamper.md` said so a week before the plan's
sentence was due to be written.

**假設** What do you do with a plan whose flagship claim is already dead?

1. drop the claim and report four rows honestly;
2. keep hunting for a variant of point 1 that does fail;
3. find the pair somewhere else.

**先驗哪個、為什麼** (2) first, because it is cheap to reason about and it
decides the other two. For a signature check to fail, the bytes signed and the
bytes verified have to differ. There are exactly two ways: change them after
signing, or sign with a mismatched key. Changing the *source* is neither, so no
variant of point 1 — a different index, a different offset, the whole record —
can fail. (2) is not slow, it is impossible, and knowing that took five minutes
of asking who signs what rather than an afternoon of arms.

That leaves (1) and (3), and (3) is strictly better if the pair exists.
It does: **split point 2.** Flip a byte of the measurement *record* in flight,
and flip a byte of the *signature* in flight. Both reach the verifier. Both
fail. The only difference between them is which side of the signature the byte
was on.

**根因** The plan's error is a specific one and worth naming precisely. It
assumed *what* was changed determines the outcome — a measurement value, in both
cases. What determines the outcome is *when relative to the signature*. Point 1
and point 2 differ in both variables at once, so they were never a controlled
pair; 2a and 2b differ in exactly one.

**教訓** The measured version is stronger than the planned one, and it is
stronger for a reason that generalises: **a pair that demonstrates "same symptom,
opposite cause" has to hold everything else constant, including the layer the
symptom comes from.** `t2a_record` and `t2b_sig` are the same message, the same
index, the same offset in spirit, and the same status — `80020001`,
`VERIF_FAIL`, severity ERROR, source CRYPTO. `t1_meas` was never in that
comparison; it is a row about a layer that does not exist.

The interview sentence changes accordingly, and gets better:

> I did three tampers and one of them produced no error at all — the one where
> the device's own measurement was changed, because the device signs what it
> reads. So the two that produce the *same* message are both on the wire: one
> where the signed content changed and one where the signature changed. Same
> number, opposite causes, and the only thing that separates them is the pcap.

### The equation refused the plan's field list, which is what it was for

**現象** `harness/tamper_proxy.py` will not flip a byte until it can close

    len(message) - signature_offset  ==  the size ECDSA P-384 signs

Built with the field list from `plan/W05.md` §2.2, it computes `signature_offset`
= 570 and gets 104 where 96 was required, and refuses.

**假設** Either the message is not what the plan says, or the arithmetic is
wrong, or `BaseAsymSel` was read from the wrong offset.

**先驗哪個、為什麼** The third is cheapest to eliminate and would poison
everything: `ALGORITHMS` also carries its own `Length` field, so requiring
`Length == len(message)` costs one line and confirms the whole struct is being
read at the right base. It closed. So the offsets are right and the field list
is not.

**根因** `spdm.h:936-949`:

```c
    /*uint8_t                measurement_record[measurement_record_length];
     * uint8_t                nonce[32];
     * uint16_t               opaque_length;
     * uint8_t                opaque_data[opaque_length];
     * uint8_t                requester_context[SPDM_REQ_CONTEXT_SIZE];
     * uint8_t                signature[key_size];*/
```

`RequesterContext`, eight bytes, added in SPDM 1.3. The plan predates the
version this project pins and its diagram omits it. 104 − 96 = 8.

**教訓** This is the third time the same discipline has paid, and the first time
it paid against a document rather than against a decoder. §8.3b of the RUNBOOK
introduced it: an offset cannot be recomputed the way a value can, because a
decoder prints fields and not positions, so the answer was to reconstruct the
whole message and require the leftover to equal something known independently.

What is new today is that **the independently known quantity came off the wire in
the same connection.** The proxy watches `ALGORITHMS` go past, reads
`BaseAsymSel`, and sizes the signature from what was negotiated rather than from
what was requested. That is standing rule 8 applied inside a tool rather than
inside a report, and it means the refusal is not "the plan disagrees with my
constant" but "the plan disagrees with this connection".

`--self-test` now feeds the parser thirteen broken messages and fails if any of
its thirteen *named* checks was never exercised. The first version counted
distinct string prefixes and called that coverage, which reported three checks
where six inputs had fired only three of them — a suite measuring its own
vocabulary rather than its own reach.

### The comment I would have believed, and the byte it costs

**現象** `spdm_emu/spdm_emu_common/command.h` is the only written description of
the socket framing:

```
 *   payload (SPDM message, starting from SPDM_HEADER): PayloadSize (little endian)
```

It is wrong for the default transport. For MCTP the payload starts with
libspdm's message-type byte — `0x05` — and the SPDM header begins at
`payload[1]`.

**假設** Reading `payload[1]` as the `RequestResponseCode` gives `0x10` for a
`GET_VERSION`, which is not a request code at all. Either the comment is wrong,
or the capture is framed differently from the socket, or the transport was not
MCTP.

**先驗哪個、為什麼** The capture, because it costs one command and this repo
already has fifty-five of them:

```
pkt  0  len=   9  00 00 00 c0 05 10 84 00 00
                  └─ 4 B, pcap only ─┘ └┬┘ └── SPDM header ──┘
                                        MCTP message type
```

`send_platform_data` writes the *same buffer* to the pcap with a four-byte
synthesised `mctp_header_t` in front, so the pcap answers a question about the
socket. Five bytes of framing, not four — which is a number
`verify_repo.sh` has been asserting since week two, in the equation
`captured == SPDM bytes + 5 × messages`. **The correct answer was already
committed, in an assertion, and I still had to go and look.**

**根因** The comment is not exactly false; it is unqualified. It is accurate for
`SOCKET_TRANSPORT_TYPE_NONE`, where the payload really does begin at the SPDM
header. It is the default transport that makes it wrong, and defaults are what
people read comments for.

**教訓** Two.

The small one is filed: upstream candidate five, two lines of comment naming the
transport dependency. It is trivial, it changes no behaviour, and it is the
right first submission to a repository nobody there knows me in — small,
checkable in one command against a file the repository itself produces, and
found by hitting it rather than by reading about it.

The larger one is about where a fact lives. Three places described this framing:
a comment (wrong), an assertion in `verify_repo.sh` (right, and phrased as
arithmetic rather than as a sentence), and every committed capture (right, and
unreadable without a tool). **The one that was wrong is the only one written for
a human**, and that is not a coincidence — it is the only one nothing executes.

### The control was not clean, and it was my proxy that dirtied it

**現象** The passthrough arm — the proxy forwarding with nothing changed — exited
1, with `ERROR: receive_platform_data Error - 2` in the requester's log. The
handshake itself was complete: 30 packets, 11,337 bytes, `CHALLENGE_AUTH` and
`MEASUREMENTS` both present, the measurement record byte-identical to the
control.

**假設** ① the proxy corrupts something late in the connection; ② the requester
always exits 1 in this configuration; ③ the proxy closes too early.

**先驗哪個、為什麼** ② first, because it is one run and it decides whether there
is a problem at all: the same command without the proxy exits **0**. So there is
a problem and it is mine. Between ① and ③, the log line names a *receive* that
failed rather than a field that was wrong, which points at the connection's end
rather than at its content.

**根因** `spdm_requester_emu.c:253` sends `SHUTDOWN` through
`communicate_platform_data`, which **waits for a reply**, and
`spdm_responder_emu.c:126` sends one back before it stops looping. My proxy tore
the connection down the moment it saw `SHUTDOWN` go past, on the theory that the
requester says it and leaves. It does not.

**教訓** The transferable half is not about SPDM. **A transparent proxy does not
get to have opinions about when a conversation is over.** The peers close; it
notices. Every opinion I gave it was a place for it to be subtly different from
no proxy at all — and "subtly different" is exactly the failure a control exists
to detect and exactly the one an exit code hides.

Which is the other half: **that arm exists because the instrument is new.**
Rows 2a and 2b of Table 1 mean nothing without it. A proxy that mangled a 1.9 KB
`CERTIFICATE` would fail both tamper arms, and "the tamper was detected" is what
that looks like from the outside. `docs/measurement.md` now says this out loud
as a field of the template: **a new instrument needs its own control**, and it is
the field most often skipped because it feels like testing the test.

### Two digests in the draft were sixteen real characters and forty-eight invented ones

**現象** The first draft of `docs/tamper.md` carried

```
<!--claim …blocks.0x01.value_sha256=ce5dea03475fdf73e93d2f83a4d55b6ba2c1fd1cc6f8a4a4e0e66d8b6ba1e5f3-->
```

The real value is `ce5dea03475fdf73fa645ac2865d866a7e1aa6afae38be25c4b6f1525e3d0dc8`.
The first sixteen characters are right. The remaining forty-eight were invented.
The same happened to a second digest, in the row beside it.

**假設** How does a fabricated digest get into a document in a repository whose
entire argument is that its numbers point at captures?

1. carelessness;
2. the value was not available when the prose was written;
3. **the value was available in a truncated form, and the truncation is
   invisible once it is pasted.**

**先驗哪個、為什麼** (2) is false — the run had finished and the digests were in
`t2a_record.fields.json`. (3) is testable by looking at what was on screen, and
it is what happened: the summary script that surveyed the run printed
`sha=ce5dea03475fdf73`, sixteen characters, because that is what fits in a
table. Sixteen characters of a SHA-256 is a **prefix**, and a prefix pasted into
a field that wants a full digest is a hole exactly forty-eight characters wide.
Nothing about the result looks wrong. It is hex, it is the right length, it
starts correctly.

**根因** Every tool in this repository prints truncated digests, because full
ones do not fit in a table and `f2a14684e8fae9ff…` is how a human recognises one.
That is the right display and it is also a fabrication hazard, and the two are
the same property: **a truncated digest is designed to look like the digest.**

**教訓** The mechanism did its job, and that is the whole point of it. Every
claim in the document was rewritten from `fields.py`'s own output and the two
that changed were printed loudly; `fields.py --check` then confirmed 52/52
against the captures. It cost one command. Without the claim markup, two
fabricated digests would be sitting in the flagship document of a repository
whose thesis is that its numbers can be re-derived — and *nothing would ever
have found them*, because no reader checks a digest by eye and no reviewer has
the capture.

So the rule this produces is narrow and worth obeying: **never type a digest.
Copy it from a machine-readable output, or have a tool write it.** The moment a
digest is transcribed by a human from a display, it is not evidence any more,
and the display that makes it easy is the one that truncated it to help.

There is a smaller repo-shaped follow-on. `harness/tamper.sh`'s table and
several tool summaries print sixteen-character prefixes. They should stay — they
are for reading — but nothing that prints a prefix should ever be the place a
number is *copied* from, and the JSON beside it always exists. `TODO(me)`:
consider printing prefixes with a trailing `…` everywhere, so a pasted one is
syntactically invalid rather than plausibly complete.

### An empty chain is what a wrong layout looks like

**現象** `bench/pcapstat.py` gained the certificate-chain reconstruction, and it
reported **0 chains reassembled** on every capture taken with the `4.0.0-rc`
pair — while reporting three chains, correctly, on the one arm built from
`3.8.0`.

**假設** ① the reconstruction is wrong; ② the newer responder does something
different; ③ the newer captures are broken.

**先驗哪個、為什麼** ③ is refuted for free: `fields.py` reads those same captures
and reconstructs the chain, and has since week three. So the captures are fine
and one of the two parsers is reading something the other is not. That makes ②
worth one grep before ①, and the grep found it.

**根因** SPDM 1.4 adds `LargeCertChain`, bit 7 of `Param1`. When it is set,
`libspdm_rsp_certificate.c:212-229` writes **zero** into the 16-bit
`PortionLength` and `RemainderLength` and puts the real values in 32-bit fields
further in, with the chain starting at offset 16 rather than 8. The `4.0.0-rc`
responder sets it whenever `LARGE_RESP_CAP` was negotiated. `3.8.0` never does.

So my parser read offset 4, got 0, and reported a chain of length nought.
`fields.py` already handled both layouts — `CERT_LARGE_BIT` is in it — and the
verify step that says "chain at 16" had been printing the answer for a week.

**教訓** **A zero-valued field in the wrong layout does not look like an error.
It looks like data.** The parser did not crash, did not warn, and produced a
number: zero chains, zero bytes, everything self-consistent. What made it
visible was having one capture from a different upstream version in the same
directory, and that was luck rather than design — the `classical-stable` arm
exists to compare two releases' byte counts, not to catch this.

The generalisable form is the one to keep: **when two layouts share a struct and
one zeroes the other's fields, the zero is the trap.** The fix is not to read the
right offset; it is to *assert the other layout's fields are zero*, which turns
"I guessed the layout" and "the responder used that layout" into different
outcomes. `pcapstat.py` now does that and says so if they are not.

### A verdict that named the wrong stage

**現象** The first full run of the new arms reported
`t2a_record: stopped-after-CHALLENGE` — with `meas 1` in the column beside it.

**假設** Either the message count is wrong or the verdict vocabulary is.

**先驗哪個、為什麼** The count is produced by `fields.py` from the decode, agrees
with `pcapstat.py` from the capture, and both say one `MEASUREMENTS` arrived. So
the verdict is wrong, and it is wrong in a specific way: `run_case` had four
outcomes and none of them was "the message arrived and its signature did not
verify", so control fell through to the last `else`.

**根因** The vocabulary was written when every failure mode in the file happened
*before* a message could arrive. Point 2 is the first case where the exchange
completes and the verification does not, and there was no word for it.

**教訓** **A verdict that names the wrong stage is worse than no verdict**,
because it reads like an observation rather than like a gap. `stopped-after-
CHALLENGE` is a sentence somebody could have written into a document, and it
would have been wrong about which layer refused what, which is the one thing
Table 1 is about.

The table now also carries the status the requester actually printed, named
rather than quoted: `harness/spdm_status.py` decodes severity and source
arithmetically from the value — `0x80020001` is ERROR / CRYPTO / 0x0001 — and
looks up only the name. That distinction matters more than it sounds: it is why
`0x40020003` reads as a **warning** without anybody having to remember that
`VERIF_NO_AUTHORITY` is one, and the top nibble is the entire difference between
a row that stops a connection and a row that does not.

### `kill "${RPID:-0}"`

**現象** A scratch script died with exit 15 before printing anything.

**根因** `kill 0` sends `SIGTERM` to the whole **process group**, and `${RPID:-0}`
supplies `0` when the variable is unset — which it is on the first call, before
anything has been started.

**教訓** The default in `${VAR:-default}` is chosen for the case where the
variable is missing, and `0` is the most dangerous possible choice for something
about to be passed to `kill`. **A safe default is one whose meaning is "do
nothing", and for `kill` that is the empty string with a guard, not a number
that happens to be valid.** Sixty seconds to find, and it belongs here because
the same shape — a placeholder that is also a legal input — is what
`--flip-byte 12` was in week four and what a zero `PortionLength` was this
morning. Three of them in two weeks.

### Four places this week left the plan, and what each cost

| the plan says | what exists | why |
|---|---|---|
| `Tbl 1`, four rows, points ①②③ | five rows over ten arms | point ① produces no error, so the "identical message" pair had to come from inside point ②. The extra rows are `t0_proxy` (the instrument's control) and `t2a`/`t2b` |
| `pcapstat.py --out` producing the Markdown table | not built | this repository already has a mechanism for "the numbers in a document are generated": `<!--claim-->` plus `fields.py --check`. A second emitter would be a second copy with nothing holding it to the first, which is the failure mode the last two weeks have been about. Table 1's byte columns are claim-marked instead |
| `--flip-last-byte` | `--flip-signature N` and `--flip-record INDEX:OFFSET` | flipping the last byte requires no understanding of the message and cannot state which field it hit. `--flip-record` is what makes 2a possible at all |
| `MEASUREMENTS` field list without `RequesterContext` | eight bytes further along | the plan predates SPDM 1.3. The proxy refuses rather than guesses |

Three of the four are the same decision: **use the mechanism that already
exists rather than the name the plan happened to use** — which is word for word
the finding of 09-01, made again, which suggests it is a property of executing
a plan written thirty days before the tools existed rather than an insight.

The one that is not is the second, and it is a decision rather than a drift: the
plan asked for a generator, and the argument against it is one this repository
already made twice this fortnight. That is what a deviation record is for.

### The re-read found six more, and one of them was the defect I had just filed upstream

**現象** After everything above was committed and pushed, the sixth item of the
end-of-day list — the re-read — was run properly rather than assumed. It found
six things, and the first is the one worth leading with:

**`docs/transports.md` quotes `command.h`'s wrong comment verbatim, and does not
say it is wrong.** The same comment I spent the afternoon filing as upstream
candidate five. Four paragraphs below the quotation, in the same section, the
document prints `00 00 00 c0 05 10 84 00 00` and explains that the `05` is the
MCTP message type. **The refutation has been sitting next to the sentence for a
month.**

**假設** How does a repository end up carrying, in its own documentation, the
exact defect it is proposing to fix in somebody else's?

1. the document was written before the defect was understood;
2. the quotation was treated as source rather than as a claim;
3. the re-read after finding the defect never happened.

**先驗哪個、為什麼** (1) is true and uninteresting — `transports.md` predates
today by three weeks. (3) is false in an embarrassing way: the re-read *did*
happen, today, and it is what found this. What it did not happen is *at the
moment the defect was found*, which was six hours earlier.

(2) is the one that transfers, and it is checkable: the document introduces the
block with **"`command.h` states their byte order"**. That sentence treats the
comment as an authority. Every other quotation in that file is introduced as
something to be checked against the bytes — and the bytes are printed, and they
disagree, and nobody put the two next to each other because they are in
different subsections about different topics.

**根因** **A quotation is a claim, and this repository has a rule for claims and
no mechanism for quotations.** `<!--claim-->` covers numbers. `third_party/*.pin`
covers versions. Nothing covers "somebody else's prose, reproduced here" — and
reproducing prose is precisely how a defect propagates from one repository into
another, because it arrives already looking authoritative.

**教訓** The narrow fix is in: the quotation now carries a red note saying which
line is wrong, for which transport, with the refuting bytes named and the
upstream candidate linked.

The general one is a rule I will actually be able to follow: **when you find
that an upstream statement is wrong, grep your own repository for it before
writing the patch.** It costs one command, and the alternative is proposing a
fix to a project while shipping the bug yourself. `grep -rn "starting from
SPDM_HEADER"` returns four files here, and only one of them was wrong.

The other five, each smaller:

| what | why it had rotted |
|---|---|
| `figures/` was empty while `README.md`'s layout tree listed it as "generated figures" | the directory has been an advertised promise since 2026-08-11. Shape three — a table indexing a directory — pointed at a directory with nothing in it |
| `docs/threat-scope.md` had no row for an on-path attacker | the proxy is the first result here that is about an adversary rather than a specification boundary, and the document was written when there were none |
| `docs/threat-scope.md` and `docs/rats-roles.md` cited `w4-tamper-*` | the run they name still exists and still supports the claim, so this is the *mild* form — a live claim citing evidence that has been superseded rather than refuted. Both moved |
| `harness/healthcheck.sh` hard-codes a run family in its output, which is then generated into `docs/env-baseline.md` | a script that prints a specific run's path produces a generated document that rots on a schedule nobody controls. It now names no run |
| `README.md`'s manifest list said nothing about the proxy's reports | the same list the 2026-09-01 re-read fixed for the patch digest and the fixtures. **Second time.** Its job is "which bytes produced this", and an intervention is as much an input as a fixture |

Worth noticing that the manifest list is now the only thing in this repository
that has rotted twice and been fixed twice by hand. That is the signature of a
list that wants a mechanism, and the mechanism is available: the manifest
schema knows its own keys, so the document could be generated from a real
manifest rather than described beside one. `TODO(me)`.

### The figure that was a promise for a month

**現象** `plan/W05.md`'s DoD carries one line I could not tick by looking:
*"Fig 1 憑證鏈層級圖(W3 已做,確認還在)"*. It is not there. `figures/` holds a
`README.md` and nothing else, and has since 2026-08-11.

**假設** Either W03 produced it and it was lost, or W03 never produced it and
the plan assumed it had.

**先驗哪個、為什麼** `git log -- figures/` returns one commit, the one that
created the README. It was never produced. The plan's line is a *prediction
written as an observation*, which is the same class of statement as
"三個篡改點還沒開始" was this morning — a sentence about the repository's state
written by somebody who was not looking at the repository.

**根因** `figures/README.md` states the rule — every figure is produced by a
script from a run directory, none is drawn by hand — and the rule was never
exercised, so nothing enforced it and nothing produced anything. **A rule with
no instances is indistinguishable from a rule nobody follows**, and after four
weeks the difference stops mattering.

**教訓** `harness/mkfigures.py` renders Figure 1 — the three certificates, their
DER sizes, and `4 + 48 + 1845 = 1897` on the wire — and every number on it is
read from `certs/check_chain.py`, `harness/fields.py` and `bench/pcapstat.py`.
`--check` re-renders and requires the committed SVG to be identical;
`verify_repo.sh` runs it, and a deliberately drifted file was fed to it to
confirm it says so.

The part worth keeping is about ordering. I nearly skipped this on the grounds
that a diagram is decoration and the week's real work was done. It is not
decoration in *this* repository, because the repository's claim is that its
numbers can be re-derived — and a figure is the one artifact where a reader
cannot check that for themselves. So a figure here has to be *generated* or it
has to be *absent*, and for a month it was absent while being advertised, which
is the worst of the three states.

### A check that failed for a reason that had nothing to do with what it checks

**現象** The verify run after the re-read printed these two lines, in this
order:

```
    ok   gen_measurements.py and the C builder write identical bytes (336 bytes)
  FAIL gen_measurements.py and the C builder disagree about the file format
```

One line apart. The same step. The `ok` came from `make`; the `FAIL` came from
the shell wrapping it.

**假設** ① `make interop` really failed after printing that it succeeded;
② the step's condition is reading something other than `make`'s status;
③ a transient — the run also printed `make: Warning: File
'measurement_source_test' has modification time 0.032 s in the future`.

**先驗哪個、為什麼** ③ first, because if it is transient the other two do not
matter and because it is one re-run. It did not reproduce: `make interop` alone
exited 0, twelve lines, five times.

That leaves ① and ②, and ② is checkable by reading one line:

```bash
if make -C device --no-print-directory interop 2>&1 | head -2 | sed 's/^/  /'; then
```

The condition is a **pipeline**, and `lib/common.sh` turns on `set -o
pipefail`, so its status is any non-zero member's. My first guess was that
`head -2` closed the pipe and `make` died of SIGPIPE — and the first attempt to
reproduce it **refuted that**: `PIPESTATUS=0 0 0`, every time. Twelve short
lines fit in a 64 KB pipe buffer, so `make` finishes writing before `head` has
read anything.

The reproduction was wrong, not the theory, and what was missing was the
warning. `interop`'s recipe is several commands, and the last interesting one is
`gen_measurements.py --describe | sed`, which runs **after** the summary line.
Without the warning, `head -2` takes the summary and the first `--describe`
line and exits while that `sed` is mid-write — sometimes early enough to matter
and sometimes not. With the warning, the warning *is* line one, so `head` exits
one line sooner, before `--describe` runs at all, and the kill is certain.

Forced by giving the binary a future mtime:

```
  run 1: pipeline=141 PIPESTATUS=141 0        <- 141 = 128 + 13 = SIGPIPE
  run 2: pipeline=141 PIPESTATUS=141 0
  ... 5 of 5

  captured first, judged on make's own status:
  run 1: make=0  lines=12
  ... 5 of 5
```

**根因** `set -o pipefail` and a consumer that exits before end of input are
individually reasonable and jointly a bug: the producer gets `SIGPIPE`, 0
becomes 141, and 141 is not zero. The clock skew was not the cause. It was the
thing that turned an intermittent failure into a deterministic one by shifting
where `head` stopped reading — which is why it appeared on a day when nothing
about `device/` had changed.

`CLAUDE.md` already carries the neighbouring rule, from a different day:
*不要 `| tee` 接建置卻不看 `set -o pipefail` / `PIPESTATUS`*. That one is about
`pipefail` being **off** and a failure being hidden. This is the mirror image —
`pipefail` **on**, and a success being hidden — and the two look nothing alike
while having the same shape.

**教訓** The bug is one line. The interesting part is what looking for its
siblings found.

`grep -n 'if .*| *\(head\|grep -q\)' harness/*.sh` returns eight sites, and
**two of them invert their answer**:

```bash
if openssl list -signature-algorithms 2>/dev/null | grep -qi 'ml-dsa'; then
```

`grep -q` exits **at the first match**. So on a machine that *has* ML-DSA,
`openssl` is killed writing the rest of the list, the pipeline is 141, and the
branch reports **"no ML-DSA (needs >= 3.5)"** — the reverse of the truth, on
the single check that decides whether week eight's post-quantum certificate
chain is possible. It has never fired here because this machine's OpenSSL is
3.0.13 and there is no match, so the wrong branch happens to be the right
answer. It would have failed the day the machine was upgraded, which is the day
somebody would trust it most.

A third is worse in a quieter way. `lib/handshake.sh`'s `hs_port_is_listening`
is the same shape, and it runs in a loop on **every handshake this repository
takes**. When `grep -q` matches early enough to kill `ss`, "the port is
listening" is reported as "it is not", the caller keeps waiting, and ten
seconds later the run fails with `return 91` and no explanation. That function
exists *specifically* to replace a `sleep 3` race, and it had a race of its own
that gets more likely as the machine gets busier.

All eight are now captured into a variable and matched with a here-string,
which is a redirection rather than a pipeline and has no second process to
lose. And the class has a guard: `verify_repo.sh` flags any `if`/`while`/`&&`
whose pipeline ends in `head`, `grep -q`, `grep -m` or `sed Nq`, skipping the
ones inside `$( )` because a substitution's status is discarded. Fed a
deliberately broken line it names the file, the line and the fix; on the
repaired tree it passes.

Three things worth keeping, in increasing order of generality:

1. **A check that fails for a reason unrelated to what it checks is worse than
   no check**, because the failure is specific, legible and wrong. "The two
   implementations of the file format disagree" is a sentence somebody would
   have acted on.
2. **A wrong reproduction is not a wrong hypothesis.** The first attempt showed
   `PIPESTATUS=0 0 0` and I nearly filed the whole thing as a flake. What was
   missing was the *warning* — the condition that had made it deterministic in
   the first place — and reproducing a bug means reproducing its context, not
   its command.
3. **When a defect is found in one line, grep for its shape before fixing it.**
   One line was broken today. Seven more were broken and quiet, two of them in
   the direction that reports success as failure, and the cheapest moment to
   find them was while the shape was still in my head.

### What is measured, and what is still a claim about myself

**`TODO(me)`** — `c-drills`. `d2` now exists: contract, tests, stub, validated
**four** ways rather than three, because the drill's own comment calls a second
version correct and a comment that says so without checking is what the last two
weeks have been about. That makes **six** drills waiting and **zero** finished.
`DONE.txt` is empty for the sixth working day running.

What changed today is only that the number is now printed by
`verify_repo.sh` rather than described in a paragraph. It does not fail the
build, and it should not: whether to spend an evening with paper is not a
decision a script gets to make. What it does fail on is a drill listed as
finished whose compile-error count was never recorded — currently vacuous, and
load-bearing the moment the first one lands.

`d2` is also the drill with the shortest paper time in the series, ten minutes,
and the highest ratio of consequence to effort: the wrong version is caught by
AddressSanitizer with a two-byte out-of-bounds read, because `src + SIZE_MAX`
wraps the address space to `src - 1`. That is GHSA-m4wc-xmvg-369f's primitive,
reproduced in twenty lines.

**`TODO(me)`** — Table 1's row 1 is now the argument for Gate 3 rather than a
loose end, and Gate 3 has not started. Both its prerequisites are met: the
secure version number takes three values on the wire, and the build already
fails if an in-flight tamper stops being rejected. What is missing is the half
that needs a reference value, and that is the half nothing in this repository
can do yet.

**`TODO(me)`** — `docs/upstream/README.md` now lists **five** candidates and
**zero** submissions. The oldest is twenty-four days old. The newest is two
lines of a comment, which is the smallest and most likely to land, and it is the
one to send first. The DMTF portal account for the SPDM 1.5 feedback is still
not created and that window has closed.

**`TODO(me)`** — What I am least sure about right now: _______________


---

## 2026-09-12 · Day 7 · the fix that would have been worse than the bug

Week six. Gate 3's first half: a measurement compared against a signed
reference value, a policy, a verdict, and a CI job that turns red when a
tampered measurement stops being rejected. Three entries, and the middle one is
the only one I would tell somebody about.

### The published example does not run, and the first root cause was not the root cause

**現象** Before connecting anything of this project's, I ran DMTF's own
eight-command example from `spdm_emu/spdm_device_verifier_tool/readme.md`
verbatim, on the sample data that ships beside it. Step 3 printed
`Signature verification failed`, and every step after it failed on a missing
file.

I also fell into this repository's own second red line while doing it: my
scratch script printed `exit=0` after each step, because `$?` after `cmd | tail`
is `tail`'s status. The output was right and the exit code was meaningless.

**假設** Three, and they are not equally likely:

1. the environment — a Python dependency at a version the tool predates;
2. the tool — a defect in `CoRimTool.py`;
3. the data — the signed file really is bad, and the verifier is right.

**先驗哪個、為什麼** (3) first, because it is the only one that would make
everything else a waste of time, and because it is checkable *without either of
the other two being true*: the signature can be verified by a third party. I
built the COSE `Sig_structure` by hand — `["Signature1", protected, b"",
payload]` — and checked it with `ecdsa` alone. `True`. So the file is sound and
the verifier is wrong, and (3) is eliminated by evidence rather than by
assumption.

Then (2) before (1), for a bad reason that turned out to be lucky: I had already
read the function. `VerifySignedCbor` builds its key as
`EC2Key(crv='P_256', d=key)` where `key` came from `VerifyingKey.to_string()`
— the public point, 64 bytes, where the private scalar goes. `SignCbor`, three
lines above, does the same construction correctly with a `SigningKey`.

**I fixed that line and it still failed.** That is the useful part of this
entry. A hypothesis that explains the symptom is not the same as the hypothesis
that causes it, and the difference is visible only when you test the fix rather
than the reasoning.

**根因** Both (1) and (2), stacked, each sufficient on its own.

(1) is `requirements.txt` with no upper bounds. `cbor2` ≥ 6.0 decodes the
contents of a `CBORTag` as **immutable** containers — arrays become `tuple`,
maps become `FrozenDict` — and `pycose`'s `CoseMessage.decode` type-checks for
`list`. The sharpest statement of it is that **pycose cannot decode its own
`encode()` output**: 79 bytes, byte-identical through a `cbor2` round trip,
`TypeError`. Bisected: 6.1.4 fails, 5.6.5 and 5.4.6 work.

(2) is the key. With `cbor2` pinned, the unmodified tool still says *failed*;
with the one line changed it says *passed* and the whole example runs through to
`opa eval`.

**教訓** Two, and the second is more general than the tool.

**Run the published example first, unchanged, before connecting anything of
your own.** If I had wired my measurement record in on day one, the same
failure would have looked like my bug, and I would have spent a day inside my
own code. Four of this week's seven upstream findings came from the fifth
command of somebody else's tutorial.

**A wrong reproduction is not a wrong hypothesis, and a partial fix is not a
wrong root cause.** 2026-09-10's entry has the first half of that sentence. This
is the second: the key defect was real, was the thing I had reasoned to, and was
not sufficient. What settled it was applying the fix and re-running — not
re-reading the argument that produced it.

### The one-line fix that would have been worse than the bug

**現象** The commit was written. Subject line under fifty characters, body
wrapped at seventy-two, `Tested:` lines, `Signed-off-by:` with my legal name, on
a branch, on top of upstream `main`. One keystroke from a pull request.

Then I ran a script whose only job was to re-execute the `Tested:` claims of
that commit message, because a claim I send to somebody else is one I should
have run. The last claim was *"a corrupted signature is still refused"*. I
flipped the last byte of the 64-byte signature and the patched tool printed
**Signature verification passed** and wrote the 996-byte payload.

**假設** Three:

1. the flip did not land inside the signature;
2. `verify_signature()` raises for some inputs and not others, and this one
   slipped through a branch;
3. `verify_signature()` does not raise at all.

**先驗哪個、為什麼** (1) first, and not because it is likely — because it is the
only one that would make the other two irrelevant, and because it costs one
`cbor2.loads` and a comparison. Decoded both files: one byte differs, at offset
1118, which is the last byte of the 64-byte signature element of the COSE_Sign1
array. Eliminated.

(3) before (2), because (2) requires the library to be inconsistent and (3)
requires only that I did not read its signature. Reading it took four seconds:

```python
def verify_signature(self, *args, **kwargs) -> bool:
    """:returns: True for a valid signature or False for an invalid signature"""
```

**根因** `CoRimTool.py` calls `cose_msg.verify_signature(Algorithm)` and
**discards the return value**. The function returns a bool; it does not raise on
a bad signature. So the `except Exception` around it catches key-construction
errors and nothing else, and control falls through to the payload write and
`print("Signature verification passed")`.

Two defects, three lines apart, in one function, **and they mask each other**.
The key defect makes `EC2Key` raise before any signature is examined, so the
tool refuses everything and looks fail-closed. Repair it alone and the tool
accepts everything.

**The change I was one keystroke from sending would have converted a verifier
that accepts nothing into a verifier that accepts anything.** Not a regression I
would have introduced by carelessness — a regression that follows from a fix
that is correct, minimal, and exactly what the symptom asks for.

**教訓** Three, in increasing order of how much I would want to be asked about
them.

1. **Run your own commit message.** Not the change — the *claims*. Mine had
   four `Tested:` lines and the fourth was false, and the only reason I know is
   that re-running them was mechanical enough to be worth automating. A
   `Tested:` line is a promise made to a stranger; running it is the cheapest
   thing in the whole exercise and it is the step with nothing forcing it.

2. **When a defect is found in a line, read the rest of the function.**
   2026-09-10's lesson was *grep for the shape before fixing it*, and it found
   seven more instances of one pattern across the repository. This is the same
   instruction pointed the other way: not outward across files, but **downward
   through the enclosing scope**, because the two defects that mask each other
   are almost always neighbours. Three lines apart, in this case.

3. **A fix is correct in the state it leaves behind, not in isolation.** This is
   now standing rule 17 in `docs/roadmap.md`. "Is this change right?" is the
   wrong question when the surrounding code is also wrong; the question is
   "what is true after this lands?" — and the honest answer here was *worse than
   before*, for a change that reviews cleanly in one line of diff.

And a mechanism, because a lesson with no mechanism is a mood.
`rats/interop.sh` now keeps a **half-patched** copy of `CoRimTool.py` beside the
fully patched one and asserts that the half-patched one **accepts** a forged
signature. If that ever stops being true, the second half of the bug report is
wrong and must not be sent. The near-miss is not a story any more; it is a
check, and it runs whenever the interoperability comparison does.

### Comparing sets of hashes cannot see which hash belongs where

**現象** DMTF ships `SpdmSamplePolicy.rego` with the tools, and week six's plan
was to use it. Reading it first — `default SPDM_HASH_CHECK = false;
SPDM_HASH_CHECK { ev_hash_list == ref_hash_list }` — both sides are **partial
set** rules. It compares a *set* of digests against a *set* of digests.

**假設** What can a set comparison not see?

1. which index a digest belongs to;
2. duplicates, which collapse into one member;
3. an empty reference, since `set() == set()` is true;
4. the digest algorithm, which both sides carry and neither reads.

**先驗哪個、為什麼** (1) first, because it is the one with a consequence I can
state in a sentence about hardware rather than about Rego: measurement index 1
is the immutable ROM and index 2 is the mutable firmware, so a device presenting
its firmware digest as its ROM digest has said something false about which parts
of it can change — and the multiset is unchanged. If that were not true the rest
would be pedantry.

**根因** All four are real, and **(3) was wrong as I first wrote it**, which is
the part worth keeping.

I asserted in the self-test that set comparison passes *any* empty reference. It
does not: with an empty reference and real evidence, the two sets differ and the
sample correctly refuses. The self-test failed on my expectation, not on the
policy. The hole is narrower and worse — **both** sides empty — which is a
device that answered `GET_MEASUREMENTS` with nothing, appraised against a
reference that names nothing, and declared good. That fails **open**, on the
least trustworthy input a verifier will ever see.

The measured version, against the real file under `--v0-compatible` rather than
against my model of it: the sample **accepts** the index swap, **accepts** the
all-empty pair, **accepts** an algorithm substitution, and correctly refuses the
duplicate. Four of eleven cases in `rats/rats_selftest.py` are ones it lets
through.

**教訓** The lesson is not about Rego.

**A claim about somebody else's code is a claim, and mine was wrong in the
direction that flattered me.** "Their policy passes an empty reference" is a
better story than "their policy passes an empty reference *and* empty evidence,
which is a narrower case". I had the second and wrote the first, and what caught
it was a test I wrote to check the policy rather than to check myself.

The generalisation, which is the reason this entry exists: **when a test fails
against an expectation, the expectation is a hypothesis too.** Every previous
entry in this log treats a failing check as evidence about the system. This one
was evidence about the sentence I had written about the system, and I nearly
debugged the model instead of the claim.

### Two defects that only exist somewhere else

**現象** Everything was green: `verify_repo.sh` all passed, the interoperability
run agreed on sixteen comparisons, the health check reported `PASS=8 FAIL=0`,
twelve commits on a clean tree. Then the clone — `git clone` into
`$LAB_DIR/cleanclone-w6`, run the same suite there, because that is the only
check that answers "what will somebody else see".

Two failures, in a tree whose only difference from this one is **where it sits
on the disk**.

**假設** For the first, `t3_cert.verdict.json differs from the committed
verdict`:

1. the appraisal is not deterministic;
2. something in the verdict depends on the environment;
3. the clone is stale.

For the second, `rats/cose.py no longer verifies CoRimTool.py's signature`:

1. `cose.py` is broken;
2. the committed interop fixture is broken;
3. something in the clone changed the key.

**先驗哪個、為什麼** For the first, (3) costs one `git log` and is false. Then
(2) before (1), because nine of the ten arms reproduced exactly and a
non-deterministic appraisal would not be selective — so whatever it is, it is
something `t3_cert` has and the others do not. `t3_cert` is the arm whose
handshake never reaches `MEASUREMENTS`, so its entire committed verdict is the
*text of a refusal*. Opening it: the text begins `/mnt/c/Users/Key20/...`.

For the second, (3) first, on the grounds that two things had just failed in the
same run and a common cause is cheaper to test than two independent ones. The
clone's `rats/keys/` held a key with a timestamp of ninety seconds earlier. It
had been generated *by my own check script*, which runs `mint_reference.sh`.

**根因** Both are the same shape and neither can occur in the tree where the
code was written.

`_rel()` exists in `rats/appraise.py` for exactly this: a committed derivation
holding an absolute path only reproduces on the machine that wrote it. I applied
it to the verdict dictionary and not to the exception messages, and the only arm
whose verdict *is* an exception message is the one that failed.

`mint_reference.sh` generated a signing key because there was not one. The
private half is deliberately untracked, so **"there is not one" is what a fresh
clone looks like** — and generating one silently replaces the key that every
committed reference value was signed with. The script already refused to
*overwrite* an existing key. That is a different condition: "do not overwrite
something that exists" against "do not create something whose absence is
load-bearing". Only the second one fires on somebody else's machine.

**教訓** Three, and the third is the one I will keep.

**A property about other people's machines has to be tested on one.** Every
check in `verify_repo.sh` runs in the tree that produced the thing it checks,
and none of them can see an absolute path, because the absolute path is correct
there. `RUNBOOK.md` §10 has described the clean-clone re-run as a delivery step
since week one; it found two defects the first time it was run as a routine one,
and it cost ninety seconds.

**A guard is a shape, not a sentence.** The overwrite guard and the missing-key
guard read like the same precaution and protect against opposite states. When
writing one, the question worth asking is *which machine does this fire on* —
because a guard that only fires on the author's machine is a guard for the one
person who does not need it.

**And the cheapest place to find out what your repository promises is to stop
being inside it.** The private key's absence is a published property: it is in
`rats/README.md`, in `mint_reference.sh`'s header, and in the reasoning behind
ADR 0005. All three were written by someone who had the key.

### What is measured, and what is still a claim about myself

**`TODO(me)`** — `c-drills`. `d7` now exists: contract, tests, stub, validated
**five** ways rather than three, because it is the first drill whose contract
admits two correct answers and "both designs pass" is exactly the kind of claim
a comment makes and nothing checks. Both were written and both pass, 151 and
152 checks; the difference of one is the byte the leave-a-slot-empty design
cannot store. That makes **seven** drills waiting and **zero** finished.
`DONE.txt` has been empty for the seventh working day running.

The stub run found a defect in the tests themselves — `rb_capacity() - 1`
underflowing to `SIZE_MAX` when capacity is zero, which is this drill's own trap
inside the test that teaches it — and it was visible only because standing rule
15 requires running against the stub. That is twice now that the *boring* one of
the three compilations has been the one that found something.

**`TODO(me)`** — Gate 3's first half is done and the second is not. The secure
version number is compared for **equality**, so `svn5` and `svn9` produce the
same verdict with the same message: a rollback and an upgrade are
indistinguishable, which is the one distinction a rollback rule exists to make.
Week 7 is `evidence >= reference` and four cases, and the fourth is the one that
matters — it has to prove that loosening the version rule did not loosen the
integrity rule.

**`TODO(me)`** — `docs/upstream/` now lists **twelve** candidates and **zero**
submissions, and for the first time one of them is *prepared* rather than
*noticed*: branch, commit, pull-request body, checklist, and a re-run of its own
`Tested:` lines. The keystroke is mine and I have not made it. The oldest
candidate is thirty-two days old.

**`TODO(me)`** — Two of the eight measurement blocks cannot be appraised by
anything, because DMTF's evidence format has no encoding for a raw bit stream
that is not a secure version number. One of them is `DEVICE_MODE`, which is
where a device says whether it is in a debug mode. I reproduced that behaviour
for interoperability and printed a coverage number beside every verdict, and I
am not sure that is the right trade — the alternative is an evidence format of
my own that no DMTF tool can read.

**`TODO(me)`** — What I am least sure about right now: _______________


---

## 2026-09-13 · Day 8 · the re-read, and a sentence that was reasoned rather than run

Not new work. `CLAUDE.md`'s end-of-day list, item by item, done properly rather
than from memory — the same exercise as 2026-09-10, which found three things.
This one found fourteen, and the last one was mine.

### Fourteen, and the pattern behind twelve of them

**現象** Everything was committed, pushed and green. Asked to confirm that every
file which should have changed had changed, I read rather than remembered, with
`git grep -n -iE 'G3|gate 3|RATS'` over every tracked document.

Fourteen places needed work. The two that matter most:

- `RUNBOOK.md`'s first screen, the "⚠️ three things to remember" row, still
  said *"there are only two CI jobs, `verify` and `drills`; the `rats` job that
  should really be green — the one asserting that a tampered measurement must
  be judged FAIL — does not exist until G2/G3."* **It exists. I built it
  yesterday.** The sentence that told the reader what CI does not protect was
  itself the thing that had stopped being true.
- The same screen said six drills where there are seven, and *"today: start
  Gate 3"*.

And ten more of the same shape: `harness/doctor.sh` did not know `opa` existed;
`RUNBOOK.md` §2's tool list did not mention it; Appendix A had 116 lines of
command reference and zero `rats` commands; the glossary had `CoRIM` and not
`COSE`, `OPA` or `kid`; `docs/tamper.md` said *"the verifier that would refuse
it does not exist yet"*; `docs/certchain.md` said the RATS policy *"is Gate 3,
not this week"*; `docs/threat-scope.md` had two rows still pointing forward;
`device/README.md` stated Gate 3's rule as `>=` when the policy compares for
equality.

**假設** Why did twelve documents fall behind in one day?

1. carelessness at the end of a long session;
2. the end-of-day list names three documents — `LOG.md`, `README.md`/
   `roadmap.md`, `RUNBOOK.md` — and nothing names the rest;
3. the mechanism that exists for this only checks a state token, not prose.

**先驗哪個、為什麼** (3), because it is checkable in one run and it is the one I
would otherwise have assumed had covered me. `verify_repo.sh`'s gate-table check
compares a *state word* per gate across three files, plus the week number. It
passed the whole time. It was designed to pass: 2026-09-10's own entry says so
in as many words — *"that check would not have caught today"* — and then
yesterday I let the check's existence stand in for the thing it explicitly does
not do.

(2) is true and is the smaller half. The list says *"update `RUNBOOK.md` if
progress changed"*, and progress changing is exactly when eleven other files
change too.

**根因** **A forward reference is a claim with a timer on it**, and this
repository is full of them because it is written a week at a time. *"That is
Gate 3"*, *"does not exist yet"*, *"要到 G2/G3 才存在"* — every one was true
when written, every one becomes false on a specific day, and nothing points at
them on that day. They are the opposite of the stale-number problem
`fields.py --check` solves: a number that drifts from its capture is *wrong
about a fact*; a forward reference is **right about the past and read as the
present**.

**教訓** Two, and the first is the cheap one.

`git grep -iE 'G3|gate 3|RATS|not started|yet'` over `*.md` costs four seconds,
and it is now the first thing in the end-of-day sequence rather than an
afterthought — before the gate tables, because the gate tables are the three
files that already have a mechanism.

The second is the general form, and it is the one worth keeping: **when a gate
closes, the sentences that will rot are the ones written while it was open.**
They are findable by name — the gate's name is in them. That is a grep, and the
only reason it did not happen yesterday is that nothing asked for it.

### The paperwork I thought was done, for a project it does not cover

**現象** *"等等,你說要簽 CLA 嗎?我之前好像忘記了"* — asked the day before the
first change was due to go out, with the branch built, the commit signed off and
a checklist beside it saying the paperwork was in order.

**假設** Where does the confusion come from?

1. it is done — the Individual CLA went to `manager@lfprojects.org` on
   2026-08-04, and `docs/upstream/README.md` has the row to prove it;
2. it is done for the wrong project;
3. the target has no CLA at all and the question does not apply;
4. the documents here never said which of those was true.

**先驗哪個、為什麼** (3) first, because it is the only one answerable from a
primary source rather than from my own notes, and because if it is true the
other three stop mattering. `DMTF/spdm-emu` has a `CONTRIBUTING.md`. Reading it,
with `grep -ci 'contributor license agreement\\|\\bCLA\\b'`: **zero**.

Then (2), which is (1) with the scope stated: the agreement is the Linux
Foundation's, sent for OpenBMC, and covers every OpenBMC repository. DMTF is a
different standards body. The two share one line of process — the sign-off —
and nothing else.

(4) is the real finding and it was answered by the question existing. A
documentation defect has no other kind of witness, which is 2026-09-10's lesson
arriving a second time: the person confused by a document is the bug report.

**根因** Three things, in increasing order of how much they cost.

`CONTRIBUTING.md` requires the **DCO** — real name, reachable address, matching
the commit author, per DSP4014 — and no CLA. It also has a section this project
had not read at all: **AI assistance must be declared** with
`Assisted-by: AGENT_NAME:MODEL_VERSION`, and an AI must **not** be named in
`Signed-off-by` (the DCO is a certification only a human can make) or in
`Co-authored-by` (authorship rests with the humans responsible). The maintainers
use it on their own merges — `Assisted-by: Claude Code:claude-sonnet-5` on #519.

**The prepared commit had no `Assisted-by:` line.** That is rule 3, and it was
missing from a change that was otherwise reviewed, tested and one keystroke from
being sent. The checklist beside it had eleven ticks and no box for it.

And the sharper half: **this repository's own convention is a violation there.**
Every commit here carries `Co-Authored-By: Claude Opus 5 …`. Correct here,
forbidden by rule 2 upstream. The prepared commit did not carry it — but by
habit rather than by design, and a habit is not a mechanism.

**教訓** The mechanism first.
`harness/check_upstream_commit.sh` encodes the rules **read out of the target's
own `CONTRIBUTING.md`**, records that file's SHA-256, and says so when the
target's copy no longer matches — because a rule set that has moved is precisely
what a returning contributor does not re-read. Ten rules, nine self-test cases,
eight of which break exactly one rule.

Only the DMTF profile exists. OpenBMC's — Gerrit, `Change-Id`, a CLA whose state
no script here can see — waits for week 9 and a real commit to check against.
Writing it now would be a check whose failure mode has never fired, which is the
mistake `d1` and `d6` already taught.

Then the rule, which generalises past upstreams: **the contribution rules of a
project you have not contributed to are not the ones you already know.** The
comfortable failure here was not forgetting to do the paperwork. It was
*remembering having done it* — and the memory was accurate, for a different
organisation.

And two more, small and familiar, both of which this repository caught by
itself.

The first version of the "is an AI named in the sign-off" test used the bare
pattern `ai`, which matched **`gmail`** in the author's own address and reported
a compliant commit as a violation. Word boundaries. That is 2026-09-10's *"a
check that fails for a reason unrelated to what it checks"* for the third time
in four days, and it is now a self-test case of its own rather than a sentence
in a log.

And the new script's very first `verify_repo.sh` run was **red**, on
`a branch can be decided by SIGPIPE` — the guard added on 2026-09-10 after that
shape inverted two branches elsewhere in `harness/`. I had written four
`if printf … | grep -q` conditions in a file whose whole purpose is checking
things carefully. The guard named the file, the line and the fix, and the fix
was the one that entry prescribes: a here-string, which is a redirection with no
second process to lose.

That is the most encouraging thing in this entry. A rule written four days ago,
after a bug that took an afternoon, refused its own shape in new code written by
the person who wrote the rule — **before it could reach a commit.** It is the
only kind of evidence that a mechanism is worth more than a lesson.

### The sentence I wrote from reasoning rather than from a run

**現象** Fixing the twelve above, I added `opa` to `doctor.sh` as a FAIL rather
than an INFO, and wrote the justification into three places: *"without it,
`harness/verify_repo.sh` skips the whole appraisal — loudly, and still green. A
check that is green because nothing asked it looks exactly like a check that is
green because nothing is wrong."*

Then, because the new pin check had not been observed rejecting anything —
standing rule 11 — I wrote a script that feeds it four broken states. The fourth
removes `opa` from `PATH`. **`verify_repo.sh` returned 1.**

**假設** 1. the test removed more than `opa`; 2. something unrelated failed;
3. the sentence is wrong.

**先驗哪個、為什麼** (1) first, because the first attempt set `PATH` to three
directories and would have taken `shellcheck` with it — a test that breaks two
things and blames one. Re-run with a `PATH` filtered to remove exactly the one
directory `opa` lives in. Still 1, and the failing line named itself:

```
FAIL rats/appraise.py self-test failed — a policy that cannot reject is not a policy
```

**根因** The sentence was wrong, and it was wrong because I had written the
thing that falsifies it the day before and then reasoned about the system
instead of running it. `rats/rats_selftest.py` opens with a check for `opa` and
exits 2 — *"this self-test would pass by not running"* — which is deliberate,
correct, and exactly the principle the false sentence was invoking. The two
steps then disagreed: one hard-failed, and the next printed a loud "skipped" and
passed, explaining that a green run would be misleading. **The explanation
described a state the script could no longer reach.**

**教訓** The mechanism first: the matrix step now fails too, so a missing engine
is one red line for one reason rather than two steps with different opinions.
`doctor.sh`, `RUNBOOK.md` §2 and the first screen say what actually happens, and
the RUNBOOK note carries the correction in brackets rather than quietly reading
as if it had always said that.

The lesson is a narrower version of yesterday's, and narrower is better.
Yesterday: *run your own commit message*. Today: **a sentence about your own
system's behaviour is a claim, and the cost of checking it is one command.** I
had three: `opa` removed from `PATH`, and the exit code. What made me write it
instead of run it is that it was a *justification* rather than a *result* — it
was there to explain why `doctor.sh` should fail, and explanations do not feel
like the kind of thing that needs evidence.

That is the same shape as 2026-09-12's third entry, where a claim about DMTF's
policy was wrong in the direction that flattered it. Both times the false
sentence was in a supporting role. **Nothing checks the reasoning you use to
justify a check.**

---

## 2026-09-14 · Day 9 · a rule that had to be shown to do something, and a ratio that was not one number

### The four cases were already on the disk

**現象** `plan/W07` §3 opens Monday with a recipe: write four measurement
fixtures with `device/gen_measurements.py`, mint one reference value with
`rats/build_reference.py`, appraise each with `rats/run_appraisal.sh`. Two of
those three files do not exist. Neither does `rats/cases/`. And the one that
does exist, `gen_measurements.py`, produces a `.bin` that `rats/appraise.py`
has no way to accept — it takes a decoded capture, not a fixture.

**假設** 1. the files were renamed and the plan is one rename behind;
2. the plan predates them and describes what it expected to need;
3. the plan is describing a *different*, simpler pipeline than the one that was
   actually built, and the difference matters.

**先驗哪個、為什麼** (2), because it is answerable from a date and because if it
is true the interesting question is (3). `plan/W07.md`'s header says
2026-08-11 — day one of fourteen. `rats/` was written on 2026-09-10 and
2026-09-12. The plan is not one rename behind; it is a month ahead of a design
it could not have known about.

Then (3), which is the one worth the time. The plan's pipeline appraises the
**fixture**. The one that was built appraises the **528-byte measurement record
sliced out of the `MEASUREMENTS` message**, and `rats/README.md` says why in as
many words: feeding the fixture compares a document against itself, and it
deletes the conveyance, which is the entire subject of RATS. So the recipe is
not merely using old names. It is describing an experiment that cannot fail in
the way the week needs it to.

**根因** **A fourteen-week plan describes each week's work in the tools it
expects to need**, and six weeks in, the tools exist, are better, and have a
shape the plan could not have anticipated. The recipe is the first thing to
rot; the *question* it was written to answer does not rot at all.

And the question was already answered by the disk. `bench/data/w5-tamper-
20260910T092621Z` holds four real handshakes taken on 2026-09-10 with the
responder reading four different fixtures: `t0_clean` at SVN 7, `svn9` at 9,
`svn5` at 5, and `t1_meas` at 7 with one byte of measurement index 1 changed.
Those are the plan's S-eq, S-up, S-down and S-hash, end to end, already
provenanced, already committed. Nothing needed generating.

**教訓** Three, and the middle one is the week's.

*Read a plan for its question, not for its commands.* The four cases were the
point; `run_appraisal.sh` was a guess about how they would be produced.

★ *Changing a judgement is worth nothing; being able to show what the change
did is the whole of it.* So the old rule was **frozen** rather than deleted —
`rats/policy-v0-equality.rego`, the same file with `svn == ref` — and the four
captures are appraised under both. Eight cells, and exactly one is allowed to
move. Read the frozen column for S-up and S-down and they are the same line:
that is what "cannot tell an update from an attack" looks like as output rather
than as a sentence about output. `rats/rats_selftest.py` asserts that the two
policies differ in code only inside one marked region, and that check was fed a
policy with an unrelated check disabled and refused it.

And the honest half, which is sharper than the objection the plan anticipated.
The plan says the cost of `>=` is that it cannot stop a version an attacker
invented — true, and the digest rule handles it. The real cost is that
**`>=` only stops a rollback BELOW the reference value.** A device on version 9
pushed back to 7 satisfies `7 >= 7` and this policy says PASS. Closing that
needs a reference value that moves with each published firmware, which is a
property of the release process, or a verifier that remembers the highest
version it has seen, which needs state that a one-shot derivation does not have.
Both are beside the result in `docs/rats-pipeline.md` §5 rather than after it.

### Six packets, and a status code that named no flag

**現象** The first run of `harness/run_pair.sh`, built from `plan/W07` §2.2's
eighteen controlled flags, died immediately on every arm:

```
ERROR: libspdm_init_connection - 0x8001000a
```

Six packets. Both emulators echoed every flag back exactly as intended —
`req_asym - 0x0000`, `mut_auth - 0x00`, `asym - 0x00000080`. Nothing in either
log named a flag, and `harness/spdm_status.py` has no entry for that code.

**假設** 1. `--ver 1.4` asks for a version this pair does not fully implement;
2. `--other_param OPAQUE_FMT_1` drops a bit the responder requires, since the
   default carries `MULTI_KEY_CONN` as well;
3. one of the four mutual-authentication flags is refused in a combination the
   parser accepts;
4. the build is wrong in some way unrelated to flags.

**先驗哪個、為什麼** None of them individually. **Bisection, because the
hypothesis space is eighteen flags and four of them are new to this script**,
and because each test is a two-second handshake — the cheapest possible way to
turn four opinions into one fact. Five configurations: the full set, the set
with `--other_param` restored to its default, the set without `--other_param`
at all, the set without `--ver`, and the set without the two requester-signature
flags.

The last one worked. 22 packets, exit 0. A second bisection over the two flags
separately showed that either alone is fine and **only the pair is fatal**,
which turns a guess into a statement about a condition with an `&&` in it.

**根因** `libspdm/library/spdm_responder_lib/libspdm_rsp_algorithms.c`:

```c
if (MUT_AUTH_CAP is mutually supported || requester advertises EP_INFO_CAP_SIG) {
    algo_size     = libspdm_get_req_asym_signature_size(req_base_asym_alg);
    pqc_algo_size = libspdm_get_req_pqc_asym_signature_size(req_pqc_asym_alg);
    if (((algo_size == 0) && (pqc_algo_size == 0)) ||
        ((algo_size != 0) && (pqc_algo_size != 0))) {
        return INVALID_REQUEST;
    }
}
```

**Exactly one requester signature algorithm. Never zero, never both.**

And the trap is one level up: `--mut_auth` and `--basic_mut_auth` are *flow*
policy. They decide whether the encapsulated exchange runs. They do not clear
`MUT_AUTH_CAP` or `EP_INFO_CAP_SIG` out of `m_use_requester_capability_flags`,
and both bits are set by default — which the captures confirm rather than
assume, since `fields.py` lists both in the requester's advertised flags in
every arm of every run this project has ever taken.

So `plan/W07` §2.2, which was right about every other default it listed and was
itself the product of reading the source, contains one line that cannot work.

**教訓** The mechanism first: the requester's own algorithm is **pinned** to one
classical value in every arm rather than removed, which costs one 4-byte
`AlgStructure` entry that is byte-identical across all four arms, and the
per-message-type table proves it rather than a comment claiming it.

Then the rule, and it is a sharpening of a rule this project already had.
*Read the source, not the help* was already standing; it produced §2.2's list
and the list is otherwise correct. What it does not cover is this: **a value
the parser accepts is not a configuration the protocol accepts.** The argument
parser validates against a table of names; the thing that refuses this lives in
a different library, in a conditional with two capability flags in it, and
returns a status code that names none of them. Between "the flag parsed" and
"the handshake worked" there is a layer, and the only tool that sees into it is
a capture.

★ And the reason it was caught in two minutes rather than a day: the script
**refuses to record numbers from a run whose negotiated algorithms are not the
ones it declared.** That check was written for a different failure — a
responder silently choosing a different algorithm — and the first thing it ever
did was refuse a handshake that had not happened at all. A check written for
one failure mode catching a different one on its first use is the best evidence
available that it was worth writing.

Filed as upstream candidate thirteen. It is not being sent yet, because the
first change is still prepared-and-unsent and sending a second finding to a
project you have never spoken to is a way of having zero conversations.

### I predicted the difference would not move, and it moved by exactly nine signatures

**現象** The post-quantum A/B was run through both measurement flows. The
ratios came out at **8.99×** for `--meas_op ALL` and **6.01×** for
`ONE_BY_ONE`, which is what was expected: the index walk adds ~9,000 bytes of
traffic that is identical in both arms, and a constant added to both sides
pulls a ratio toward 1.

The prediction that went with it was that the **difference** would be
unchanged, because a constant added to both sides cancels. It was not:

```
--meas_op ALL          P2 - A0 = +52,407
--meas_op ONE_BY_ONE   P2 - A0 = +78,111
```

25,704 bytes unaccounted for.

**假設** 1. the two `ONE_BY_ONE` arms differ in something besides the
   algorithms — a contaminated arm, which would invalidate the whole table;
2. the extra traffic is not constant: the walk makes the post-quantum arm do
   something more than once;
3. an arithmetic or tooling error in how the totals were produced.

**先驗哪個、為什麼** (1), first and immediately, because it is the only one of
the three that would make every number published today worthless, and because
it is the cheapest to settle: `bench/pcapstat.py` reports bytes per message
type, and a contaminated arm shows up as *any* non-measurement message
differing between A0 and P2. Every one of them is equal —
`NEGOTIATE_ALGORITHMS` 48, `ALGORITHMS` 52, `DIGESTS` 300, `GET_CERTIFICATE`
48, `CHALLENGE` 44 — and `DELIVER_ENCAPSULATED_RESPONSE` is absent from both.
So (1) is out, and what remains is a real property of the flow.

**根因** Counted, not inferred, because the arithmetic alone would have been an
observation dressed as a measurement. Seventeen `MEASUREMENTS` responses in
each `ONE_BY_ONE` arm:

```
A0-obo   50  65  105 x5  161  169 x2  185  201 x5  281
P2-obo   50  65  105 x5  3374 3382 x2 185  3414 x5 3494
```

Eight are byte-identical between the arms. **Nine differ, and every one of the
nine differs by exactly 3,213** — 3374−161, 3382−169, 3414−201, 3494−281. That
is one ML-DSA-65 signature minus one ECDSA P-384 signature, 3,309 − 96, nine
times, 28,917 bytes.

`--meas_op ONE_BY_ONE` does not merely add constant traffic. It makes the
responder **sign nine times instead of once**.

**教訓** The result: a post-quantum signature is not a per-handshake cost. It is
a per-signed-response cost, and the flow decides how many of those there are.
Both ratios are published, each naming its flow, in `docs/pqc-cost.md` §4 —
because "post-quantum SPDM is N× bigger" without the flow beside it is a number
nobody can reproduce and nobody can falsify, and the two numbers here differ by
half.

The method, which is the part that generalises: **the useful prediction is the
one that is wrong in a specific number.** "The ratio will shrink" is
unfalsifiable — it shrank, and it would have taught nothing. "The difference
will be identical" was wrong by 25,704, and 25,704 divides by 3,213 exactly
nine times, which pointed straight at the cause. A prediction that cannot be
wrong arithmetically cannot be informative when it is right.

And the smaller one, which is this repository's eighth or ninth restatement of
the same thing: the per-message-type table settled hypothesis (1) in one glance
because two independent parsers already agree on it. The work that makes a
question cheap to answer is done before the question is asked.

### "Every capture is truncated", said the check that had just been written

**現象** `spdm_dump` stops partway through the post-quantum arm — its
`LIBSPDM_MAX_CERT_CHAIN_SIZE` is a compile-time constant — so `fields.py` sees
13,365 of 58,736 SPDM bytes, 22.8%. `bench/pcapstat.py` has reported that
shortfall since it was written; `fields.py --check`, which is the tool a
*document's* numbers are checked with, did not. So a line was added to say it.

It reported **every capture in the repository** as truncated, including ones
whose decode is provably complete.

**假設** 1. the truncation flag is being set wrongly by the parser;
2. the new line reads the right value and the value is wrong;
3. the new line does not read the value it thinks it does.

**先驗哪個、為什麼** (3), because (1) and (2) would have made
`bench/pcapstat.py` misbehave too, and it does not — it takes the truncation
branch for the post-quantum arm and the byte-for-byte branch for the classical
one, on the same data, in the same run. One consumer is right and one is wrong,
so the difference is in the consumers.

**根因** `flatten()` renders every value as a **string**, because its purpose is
comparing against a `<!--claim k=v-->` in a document. `"False"` is a true
string. The new line asked `if flat.get("source.decode_truncated")` and got
truthiness from a five-character string.

**教訓** The fix is one line — read the document, not its rendering — and the
shape is one this month has now produced four times: a check that fails for a
reason unrelated to what it checks. `ai` matching `gmail`. A SIGPIPE deciding a
branch. A count of `SPDM_ERROR` standing in for a count of large-response
errors, written *today*, in the same sitting. And this.

They have one thing in common and it is worth naming: **every one of them is a
value crossing a representation boundary** — a word into a regex, a process's
status into a pipeline's, a category into a total, a boolean into a string. The
check itself was right in all four cases. What was wrong was the assumption
that the thing being handed to it still meant what it meant one layer up.

There is no general mechanism for that, which is why the specific ones matter:
a self-test case per boundary. `bench/pcapstat.py --selftest` now builds three
`InvalidRequest` and two `LargeResponse` errors and requires them counted
apart, and four deliberate breaks were applied to a scratch copy to confirm it
refuses each of them. The string-truthiness one has no companion test and is
therefore the weakest of the four fixes, which is stated here rather than
discovered later.

### The badge was red for two days and the script was right

**現象** *"好像 run fail 用 gh 看一下"* — asked after everything else in this
entry was written, committed and pushed. `gh run list`:

```
failure  docs: the front doors of what week seven added   2026-09-14
failure  docs: the week's commands, in the quick reference 2026-09-14
failure  bench: the health check, after the flow moved     2026-09-14
failure  log: the paperwork that covered a different project 2026-09-12
failure  log: day eight, and a sentence reasoned not run    2026-09-12
failure  log: the two defects that exist somewhere else     2026-09-12
success  docs: a runbook command citing last week's run     2026-09-10
```

**Six consecutive red builds**, starting two days before any of today's work.
Every local run of `harness/verify_repo.sh` in that window passed, including
four today.

**假設** 1. something in today's eleven commits broke it;
2. it has been broken since 2026-09-12 and today is incidental;
3. the runner and this workstation differ in something neither reports.

**先驗哪個、為什麼** (2) first, and it is answerable before reading a single
log line: the first red run is `34702651918`, pushed on 2026-09-12, and today's
work did not exist then. That reorders everything — it is not a regression to
find, it is a state to explain. Then (3), by diffing the failures:

```
2026-09-12  FAIL rats/appraise.py self-test failed — a policy that cannot reject is not a policy
2026-09-14  FAIL rats/appraise.py self-test failed — a policy that cannot reject is not a policy
            FAIL opa is not installed, so the appraisal cannot be evaluated
```

One root cause, reported once and then twice. Nothing from this week added a
failure; the second line is 2026-09-13's own change making the same condition
louder.

**根因** **The `verify` job never installed `opa`.** Only the `rats` job did.

`harness/verify_repo.sh` hard-fails without `opa` — deliberately, since
2026-09-13, on the grounds that *a self-test that passes by not running is
worse than no self-test*. That reasoning is correct and the entry above this
one records measuring it. The job that runs that script had an environment
that could not satisfy it.

So two things were true at once and **neither was visible from the other**: the
script was right, and the job was wrong. Locally `opa` is on `PATH`, so every
local run agreed with the script. On the runner it is not, so every remote run
agreed with the job.

★ And `third_party/opa.pin` had been carrying this line the whole time:

```
consumed-by=rats/policy.rego,rats/appraise.py,harness/verify_repo.sh,.github/workflows/ci.yml
```

**The pin already named both the script that needs the tool and the workflow
that has to provide it.** The fact was written down, in the right file, before
the defect existed. Nothing read it.

**教訓** Three, and they are in increasing order of how much they generalise.

The fix: both jobs install `opa`, and the download URL is now read out of
`third_party/opa.pin` rather than written into the workflow, because two copies
of a version are two places for it to drift from the pin — which is the rule
this repository already had and had not applied to its own CI.

The mechanism: `harness/lib/ci_tools_check.py` states the invariant that was
violated — **a job must not run a tool it does not install** — and derives it
from `consumed-by=` rather than from a second list. It is given a copy of the
workflow with the install step deleted, which is the exact state of
2026-09-12, and required to refuse it; it names both jobs.

And the rule, which is the one worth keeping: **"it passes here" and "it passes
in CI" are different claims, and only one of them is the one being made.**
Every summary written this week said `verify_repo.sh` passes. Every one of them
was true, and none of them was the claim a reader of the badge would take from
it. The end-of-day sequence now ends with `gh run watch --exit-status` rather
than with `git push`, because a push is not a result.

There is a fourth, and it is uncomfortable enough to write down plainly. The
repository has a standing warning that **green is not protection**, repeated in
three documents. It had no warning about the opposite, which turns out to be
cheaper to fall into: **red and unread protects nothing either, and it looks
exactly like working.** Six builds is not an oversight, it is a habit, and the
habit was that the badge was something this project produced rather than
something it read.

**`TODO(me)`** — Gate 3 is closed. The version rule is `>=`, four captures
prove it moved exactly one verdict, and CI asserts the whole 2×4 table. What I
am not sure about is whether freezing the old policy is a pattern or a one-off:
it cost forty lines and a structural check, and it is the only reason the claim
"I changed one thing" is checkable. Doing it for every future judgement would
fill `rats/` with fossils. Not doing it leaves the next change unprovable.

**`TODO(me)`** — Gate 4 has two algorithm groups of six and the apparatus for
the other four. What is missing is not arms: it is that `bench/pcapstat.py`
cannot reassemble a certificate chain that arrived through the chunking layer,
so the chain length for every post-quantum arm comes from the decode alone —
one tool, not two. Week 8.

**`TODO(me)`** — `c-drills`. `d8` now exists: contract, tests, stub, validated
four ways. **Eight** drills waiting and **zero** finished. `DONE.txt` has been
empty for the ninth working day running, and the scorecard — the one number
this whole track exists to produce — has eight blank rows. The drills are not
the part of this project that is behind schedule; they are the part that has
not started.

**`TODO(me)`** — `docs/upstream/` now lists **thirteen** candidates and
**zero** submissions. The prepared one is two days older than it was.

**`TODO(me)`** — The badge. Six red builds went unread, and the mechanism
added today only catches the *next* job that runs a tool it does not install.
What I do not have is anything that notices a red build at all — the check
runs inside CI, so a CI failing for a new reason reports it to the same place
nobody was looking. The only fix I can see is the habit, which is now step four
of the daily sequence in `RUNBOOK.md` §11, and a habit is what this repository
replaces with a mechanism wherever it can.

**`TODO(me)`** — What I am least sure about right now: _______________


## 2026-09-14 · Day 10 · a flag that was accepted and ignored, twice, in two different programs

Gate 4 closed. Six algorithm groups, a DataTransferSize sweep on a build made to
have one, two figures, a chunk reassembler, and four upstream candidates. The
entry below is about one shape that turned up three times in one day, because
that is the part worth keeping.

### The parameter with no flag, and the flag that did nothing

**現象** `DataTransferSize` decides whether a message crosses the wire once or as
a chunking exchange, and a chunk costs a whole request/response round trip. It is
the parameter a BMC integrator tunes. `spdm-emu` has no flag for it: it is
`LIBSPDM_RECEIVER_BUFFER_SIZE` minus transport overhead, in a header.

So I patched one in, built a third flavour, and swept six values from 1,024 to
32,768. Twelve arms. Every one exited 0. Every one negotiated exactly the
algorithms it declared. **And every one advertised 32,768.**

**假設** Three, in the order I could test them.

1. **The flag never reached the parser.** Cheapest to check and the most common
   cause of "my flag did nothing" — a typo, or a parse arm that never fires.
2. **The flag reached the parser and the value was overwritten afterwards** by
   something later in initialisation.
3. **The flag reached the right place and the library refused it**, silently,
   because I ignored a return value.

**先驗哪個、為什麼** I checked ① first, and not because it was most likely. It was
because it is the only one of the three that is answered by a file I already had:
the requester's own log, already written, already committed. `grep` on it costs
nothing and eliminates a whole branch. It was there:
`data_transfer_size - 0x00000400`. So the parse fired and ① was gone in about
four seconds.

That left ② and ③, which are both "somewhere inside libspdm", and here I made the
mistake worth writing down: **I tried to answer them by reading.** I read
`libspdm_register_device_buffer_func`, then `libspdm_register_transport_layer_func`,
then `libspdm_check_context`, then every assignment to
`local_context.capability.data_transfer_size` in the library, then
`need_session_info_for_data`, then the capabilities message builder — to establish
that nothing overwrote my value. Which was *true*, and which is why reading could
never have found the answer: **③ is not visible in any of the code that runs. It
is visible only in the value I threw away.**

The thing that answered it in one incremental rebuild was four lines:

```c
libspdm_return_t dts_status = libspdm_set_data(...);
printf("data_transfer_size applied - 0x%08x status 0x%08x\n",
       m_use_data_transfer_size, (unsigned int)dts_status);
```

`status 0x80010002` — `LIBSPDM_STATUS_INVALID_STATE_LOCAL`. The field cannot be
set once the buffers are registered. Twenty minutes of reading, replaced by one
print of a return value I had discarded on the line I wrote it.

**根因** Two, and only one of them is in the patch.

The patch's own bug is that `libspdm_set_data` is the wrong mechanism for this
field, and the right one is to register a smaller receive buffer — which is where
libspdm derives the value from in the first place, so the documented route was
always the simpler one. Rewritten that way it worked first try, and the wire
agreed: `DataTransSize=0x00000400` on both sides.

The reason it *cost* twenty minutes is that **I ignored a `libspdm_return_t`.**
Every call in that library returns one. I wrote the call, did not assign the
result, and then went looking for an explanation in the places where an
explanation could not be.

**教訓** Three, and the third is the one I want to still believe in December.

**① A check earns its place by rejecting something, and this one did on its first
run.** I had added a `DTS=` clause to `check_negotiated.py` that hour, for a
reason that felt like box-ticking: DataTransferSize is not an algorithm, so the
existing negotiation check did not look at it, and it seemed wrong to read eleven
independent variables back off the wire and take the twelfth on trust. That clause
is the only thing standing between this repository and a published
"DataTransferSize sweep" in which the parameter never moved — twelve captures,
each honestly labelled with the value it was *asked* for, showing a beautiful
flat line. Exit codes would not have caught it. Byte totals would not: they *did*
differ between arms, because the arms differ in other ways. **What caught it was
reading the independent variable back out of the message that carries it.** I have
now written that rule into a harness three times — 2026-08-17 for algorithms,
2026-09-14 for this — and both times it found something, and both times I had
thought of it as diligence rather than as a load-bearing part of the experiment.
The rejected run is kept at `bench/data/w8-dts-sweep-20260914T132232Z` because
standing rule 11 asks for evidence that a check rejects, and a directory of twelve
refused captures is better evidence than an argument.

**② "Read the source before writing the flag" is not the whole rule. The other
half is: read the source to find out WHERE to look, then measure.** Week 1's
lesson was the opposite mistake — I read `--help` instead of the source and it
cost a day. The correction overshot. Today I read the source *instead of*
measuring, on a question the source structurally could not answer, because the
failing branch was a return value nobody stored. Reading tells you which
mechanisms exist. It does not tell you which one returned an error. The cheap
instrument beats the careful argument, and an incremental rebuild here is ninety
seconds.

**③ ★ The same shape appeared three times today, in three different programs, and
the third time was mine.** A flag that is accepted, confirmed, and then has no
effect:

- **`--cap` on `spdm_requester_emu`.** Parsed, validated against the requester's
  own capability table, echoed back as `cap - 0x8882f7c6`, stored in
  `m_use_capability_flags` — and only `spdm_responder_spdm.c:174` ever reads that
  variable. The requester ignores it, and tells you it accepted it.
- **Every invalid argument in `spdm-emu`** ends `print_usage(); exit(0)`. A typo
  in a flag produces a process that exited *successfully* without speaking SPDM.
  I have now seen this exact shape in DMTF's `CoRimTool.py verify` too, which on
  2026-09-12 reported failure on stdout and exited 0.
- **My own patch**, above. Accepted, echoed, refused, and silent about the
  refusal.

The common structure is that an acknowledgement was produced by a *different*
piece of code from the one that would have acted on it. `cap - 0x...` is printed
by the parser and consumed by nobody. `exit(0)` is written by the error path. My
`printf` reported the value I *asked* for and not the value that took effect. **So
the design rule is: never let a program confirm a request; let it report the
state.** `harness/run_pair.sh` does not print the flags it passed — it prints what
came back off the wire, and refuses the run when the two disagree. That is the
same rule, and it is why today's mistake cost twenty minutes instead of appearing
in a table.

### Two provenance holes, one of which was already written down

**現象** While auditing what the sweep's second build meant, I checked what a
`manifest.json` actually attests to. Two things it does not.

`libspdm` statically links **its own OpenSSL**, from a submodule: 3.5.5. The
system `openssl` is 3.0.13. ML-DSA, ML-KEM and SLH-DSA arrived in OpenSSL 3.5.
Every manifest recorded `openssl_cli: OpenSSL 3.0.13`, every pin said
`crypto=openssl`, and **the library that computed every post-quantum signature
this project has published appeared nowhere.** A reader taking the recorded
version for the backend would conclude the captures are impossible.

And separately: `harness/apply_device_patch.sh` has been leaving
`DEVICE_PATCH.txt` beside `BUILD_PIN.txt` since 2026-09-01, and nothing folded it
into a manifest. Every capture since then came from a binary that is the pinned
commit *plus a patch*, and said so nowhere. (Those captures are still valid — the
patch is inert unless `SPDM_MEASUREMENTS_FILE` is set, and the A/B clears it per
arm — but "still valid" is a thing the reader has to be able to check.)

**假設** Not needed. The interesting question was not what was wrong.

**先驗哪個、為什麼** The question worth asking was **why five weeks of end-of-day
audits did not catch it**, and the answer was in `RUNBOOK.md`. Its obstacles
table has said, since week 7:

> **一個專案裡兩個 OpenSSL,只有一個被釘住**
> *(two OpenSSLs in one project, only one of them pinned)*

**I knew. I wrote it down. In prose.** And then every audit for five weeks read
that line, understood it, and moved on, because the audits check that documents
agree with the repository and that document was *correct*.

**根因** A defect recorded as prose is not a defect that gets fixed. Standing rule
9 exists for exactly this and I had aimed it at the wrong half of the problem: it
requires a published *number* to be re-derivable by a machine, so that facts which
are only stated cannot rot. What it does not require is that a stated *gap* become
a check. So the gap stayed stated, correctly, for five weeks.

**教訓** ★ **The end-of-day audit asks "does what I wrote still match what is
true". It should also ask "is anything I wrote a description of something broken
that nobody is fixing".** Those find different defects. The first is about drift;
the second is about a note that is doing the job of a mechanism. `RUNBOOK.md`'s
obstacles table is full of the second kind by construction — that is what it is
*for* — so the useful discipline is to re-read that table weekly and ask, of every
row, whether it is a constraint (fine, leave it) or a debt (then it needs a
mechanism or a date). The OpenSSL row was a debt wearing a constraint's clothes.
It is now `crypto-openssl-vendored` and `crypto-openssl-version` in three pins,
and the row has been rewritten to say what is still genuinely blocked (signing my
own PQC certificates) rather than what has been fixed.

Two smaller things from the same audit, both worth a line:

- **`--pin-only`.** Backfilling those fields by rebuilding would have replaced the
  binaries behind every published capture in order to fix their provenance, which
  is a worse trade than leaving it wrong. So `build_spdm_emu.sh` gained a mode
  that rewrites a pin from the tree as it stands, carries `built-at` forward, and
  compiles nothing. It then failed silently on the one flavour with no pin yet:
  `sed` on a missing file exits 2, and `set -o pipefail` with `set -e` killed the
  script mid-assignment with nothing printed. The only flavour the option existed
  to serve was the only one it could not serve.
- **`GROUPS` is a bash special variable.** `GROUPS=(...)` is silently ignored and
  `${GROUPS[@]}` returns the current user's group IDs, so the first run of the new
  matrix generated arms called `1000-all`, `27-all` and `20-all`. `set -u` cannot
  catch it — the variable *is* set. Renamed to `ALGO_GROUPS`.

### What the six groups bought that two could not

Short, because the document says it properly. Three things came out of having six
arms instead of two, and none of them was visible at two.

**The gap is a function of the security level.** 8.99× at NIST category 3 and
**10.91×** at category 5, same flow. One matched pair gives a number; two give a
trend, and a trend is falsifiable in a way a number is not.

**Every signature length falls out of a message-size difference and lands on its
FIPS constant exactly.** `CHALLENGE_AUTH` is 142 bytes of content fixed by the
negotiated hash plus one signature. Subtract 142 from the six arms: 96, 132,
2,420, 3,309, 4,627, 7,856. ECDSA P-384 and P-521, ML-DSA 44/65/87,
SLH-DSA-SHA2-128s — **not one of those numbers is an input anywhere in this
pipeline.** This is the best thing measured this week and it was not planned. It
does two jobs at once: it says the instrument is calibrated, and it *proves* the
142 is constant across the arms rather than assuming it, because if the fixed part
moved the residuals would not land on published constants.

**The negotiation is free, byte for byte.** Six VCA-only arms, all 182 captured
bytes, identical whether the thing being agreed is ECDSA P-384 or
SLH-DSA-SHA2-128s. `ALGORITHMS` selects a bit. Then the same 152-byte SPDM
subtotal turned up inside every full capture, which makes two routes to one number
where I had expected to need the standalone arm to *produce* it. It produces
nothing; it corroborates.

And one expectation the plan had backwards. `plan/W08` said `CHUNK` is absent from
the emulator's default capabilities and must be added to observe chunking. It is
present on both sides — `key.c`, plainly. So I inverted the experiment and removed
it from the responder, expecting the post-quantum handshake to fail at certificate
retrieval. **It got cheaper: three fewer round trips and nine fewer bytes**,
because libspdm then windows `GET_CERTIFICATE` to `DataTransferSize` instead of
asking for the whole chain, being refused three times, and chunking. A capability
that is optional in the specification, on by default in the implementation, and
at this chain size a net cost. The finding is about libspdm's requester policy and
the document says so.

### Bookkeeping

**`TODO(me)`** — `docs/pqc-cost.md` was restructured today and its section numbers
moved. `LOG.md`'s 2026-09-14 Day 9 entry points at "§4" of the document as it
stood that morning. I am deliberately not editing that: a dated entry describes
what was true on its date, and rewriting history to keep a cross-reference tidy
costs more than the reference is worth. Every *current* pointer was re-checked
with `grep -rn 'pqc-cost.md.*§'`.

**`TODO(me)`** — SLH-DSA does not complete a handshake on this build. Certificate
retrieval and X.509 verification both work; both signed operations fail; the
`CHALLENGE_AUTH` arrives at exactly 142 + 7,856 bytes so the responder signed
correctly and at the right length. What is left is verification, and the status is
unrecoverable because `TARGET=Release` compiles libspdm's debug output out. **A
`Debug` build is the next step and it is a whole rebuild, so it is not today's.**
Filed as upstream candidate 16 with the bisection as evidence.

**`TODO(me)`** — MCTP packetisation is still computed, not measured. No
`CONFIG_MCTP` in this kernel and no QEMU installed. The chunk model is validated
against twelve captures over a 32× range; the MCTP arithmetic is validated against
nothing, and is labelled `[computed]` at every appearance. Gate 5's problem.

**`TODO(me)`** — `c-drills`. Eight drills waiting, **zero** finished, tenth
working day. `c-drills/mock/round1.md` now exists: two problems, forty-five
minutes, the rules, and a review sheet. The paper is mine to set and the answers
are not mine to write — the number that track exists to produce is how many
compile errors a paper version has when it is first typed in, and an
implementation written by anything but him sets that number to nothing.

**`TODO(me)`** — `docs/upstream/` lists **seventeen** candidates and **zero**
submissions. Four arrived today. The prepared one is three days older than it was.
Seventeen findings and no conversations is starting to be its own finding.

**`TODO(me)`** — What I am least sure about right now: _______________

---

## 2026-09-18 · Day 11 · the case chosen to discriminate, which discriminated nothing

Gate 5 closed, both routes. A handshake over a real Linux MCTP link with real
endpoint IDs, real routing, kernel-allocated tags and real packetisation; and an
SPDM message across a real PCIe DOE mailbox. `docs/fragmentation.md` no longer
opens §5 with *"No packet count here has been observed."*

Three things happened today that are worth keeping, and the order matters: the
first is about a blocker that was never a blocker, the second is about a claim
that had been published for three weeks and was arithmetically false, and the
third is about two runs of one experiment that disagreed for two different
reasons, neither of them the thing being measured.

The second is the one to read.

---

### 1. Eight weeks of "the kernel does not have it" was a sentence, not a constraint

**現象** Since 2026-08-11 every MCTP packet count in this repository has carried
a `[computed]` label, because:

```console
$ zcat /proc/config.gz | grep CONFIG_MCTP
# CONFIG_MCTP is not set
```

That is accurate and it was treated as the end of the matter. `docs/roadmap.md`
scheduled Gate 5 for week nine and the week-nine plan's own stop-loss said that
if the kernel had no `CONFIG_MCTP`, "the cost of changing kernels is too high —
skip it and record it in `env-baseline.md`."

**假設** Three ways to get a kernel that has it.

1. **Rebuild the host kernel.** Microsoft publishes the WSL2 source, twenty
   minutes, one line in `.wslconfig`, reversible.
2. **Extract a distribution kernel and boot it in QEMU.** Ubuntu's own 6.8 has
   `CONFIG_MCTP=y` and `CONFIG_MCTP_SERIAL=m` — I checked the `.config` in the
   headers package rather than assuming.
3. **Build a guest kernel with everything compiled in, and give the guest the
   host's filesystem as its root over virtio-9p.**

**先驗哪個、為什麼** Not the cheapest. The one whose failure mode I could live
with.

★ (1) is the shortest path by a wide margin and I rejected it before trying it,
for a reason that is the whole argument of this repository: **`host_kernel` is
recorded in twenty-five `manifest.json` files in `bench/data/`.** Replacing the
host kernel makes every one of those lines name a kernel that no longer exists
on the machine. ADR 0001 keeps two spdm-emu builds rather than one for exactly
this reason and ADR 0009 adds a third rather than rebuild `pqc` with different
buffers. **A kernel is a build.** The rule does not stop applying because the
artifact is bigger.

(2) needs modules, modules need an initramfs, and an initramfs is a dependency
chase with a boot failure at the end of each wrong guess. (3) removes that
entire class: 9p, virtio and MCTP all `=y`, no modules, no initramfs.

**根因** The blocker was never "this machine cannot run MCTP". It was **"this
machine's kernel cannot"**, and those are different sentences that happen to be
true at the same time. The subsystem did not have to be on the host. It had to
be somewhere the same binaries could run — and a guest whose root filesystem is
the host's own is somewhere the same binaries can run, from the same paths,
against the same certificates. `spdm_requester_emu`, built in week one,
unchanged.

Boot to payload: 5.6 seconds. Kernel build: thirteen minutes, once.

**教訓** **A constraint stated about one machine is not a constraint about the
work.** I spent eight weeks labelling numbers `[computed]` and writing careful
sentences about why they were not measured, and every one of those sentences was
true. None of them was the question. The question was "where can this run", and
I never asked it because the answer to "can this run here" was so clearly no.

The generalisation, which is the part I want to keep: when a capability is
missing, the useful move is not to look for a way to add it *here*. It is to ask
what the smallest thing is that must be true, and then to notice that "here" was
never in the requirement. The requirement was that the binaries, the
certificates and the analysis be the same. A virtual machine sharing the host's
filesystem satisfies that more exactly than a rebuilt host kernel would have,
because a rebuilt host kernel changes the thing all the previous evidence was
recorded against.

ADR 0010 is the decision. It says "a kernel is a build" in those words, because
that is the sentence that took eight weeks.

---

### 2. ★ The case chosen to separate two formulas, which separated nothing

This is the one worth the entry.

**現象** With a real link available, the first thing to do was not to run the
handshake. It was to calibrate: send messages of chosen lengths, count packets,
and check the formula `docs/fragmentation.md` has been publishing since
2026-08-28.

That document names the case that does the separating:

> `bench/exp04_fragmentation.py --selftest` contains the case that separates the
> two formulas rather than one they agree on: a 177-byte message at MTU 64 is
> **3** packets (`ceil(178/64)`), and the subtract-the-header version says 4
> (`ceil(177/59)`).

I put 177 in the calibration set because of that sentence, ran it, got 3
packets — and then, writing the table, computed `ceil(177/59)` to fill in the
"wrong formula" column.

**`59 × 3 = 177`.** It is 3. The two formulas agree at 177.

**假設** Three, and I could test all of them in under a minute, which is itself
the point.

1. **I have the wrong rival formula.** Maybe the subtract-the-header version is
   `ceil((L+1)/(MTU-4))` or `ceil(L/(MTU-4))`, and one of those gives 4 at 177.
2. **The selftest is checking something else and the prose is a bad summary.**
3. **The claim is simply false and nothing ever evaluated it.**

**先驗哪個、為什麼** (1), because it is the only one that would leave the
document correct, and because being wrong about which formula is the rival is a
more interesting error than being wrong about arithmetic. Two lines of Python:
`ceil(178/60) = 3`, `ceil(177/60) = 3`. No variant gives 4.

Then (2), by reading the selftest, which took ten seconds:

```python
if mctp_packets(177, 64) != 3:
    bad(...)
```

**根因** (3), and the mechanism is specific enough to be worth naming.

**The rival formula was never written down as code.** It existed in a comment
and in a paragraph of prose, and the assertion underneath it checked only that
*the right formula gave the right answer* — which it would have done just as
happily at 64, or at 128, or at any of the 300 lengths in 1..399 where the two
candidates agree. The test could not have failed for the reason it claimed to
exist. It was a check about one hypothesis, captioned as a comparison of two.

And the caption was load-bearing. The whole paragraph exists to make a
methodological point — *do not test where the hypotheses agree* — and it
illustrates that point with a case where they agree.

**教訓** This repository already has a rule for the shape next door. Standing
rule 11: *a check is worth what it rejects, and something has to prove it
rejects.* Rule 15: *a drill whose failure mode cannot occur teaches a
superstition.* Both are about checks. Neither covers this, because what failed
here was not a check — it was a **claim about two things, that only ever touched
one of them**.

★ So rule 18, added today: **a claim that two things differ has to evaluate both
of them.** Not describe the second one. Evaluate it, in code, in the same
process, and assert the difference.

The fix is not a corrected number. `mctp_packets_subtract_header()` is now a
function beside the real one; the selftest computes the separating lengths
(`[60, 61, 62, 63]` are the smallest) rather than naming one; 177 is pinned as a
case that must reproduce and must **not** discriminate, so the error cannot come
back quietly; and `--observed` now prints the rival's answer beside the model's
for every message in a capture and says how many of them actually separate the
two. The calibration run reports **7 of 12**. The post-quantum handshake reports
**14 of 46**. A capture that separated nothing would now say so in one line.

That last part is the bit I would not have thought of before today. It is not
enough for the *test suite* to discriminate. The **evidence** has to carry its
own discriminating power on its face, because the next person to read the table
is going to read the table and not the selftest.

What it cost: about twenty minutes, all of it after the measurement was already
correct. What it would have cost in an interview, asked "how do you know that
formula is right", is the whole answer.

---

### 3. Two runs of one experiment, two different numbers, neither of them the link

**現象** The first full run reported 953 MCTP packets for the post-quantum arm
and the model reproduced every message. I changed the calibration lengths and
re-ran. **920 packets**, and eighty-six complaints of the form:

```
packet 48: continuation for (8, 9, 0, True) with no SOM before it
```

A start-of-message packet missing is what a *lossy link* looks like from the far
end. I had built the link out of a pty pair, which has no flow control worth the
name, so that reading was available and comfortable.

**假設**

1. **The link dropped packets.** The pty buffer overflowed under a burst of
   nine hundred.
2. **The bridge lost them.** A `sendto` that returned short and was not checked.
3. **The capture lost them.** The measurement, not the thing measured.

**先驗哪個、為什麼** (3) first, and not because it was most likely — I thought
(1) was. Because it was the only one that would invalidate *the instrument*
rather than produce a finding about the link, and an instrument that is wrong
makes every other hypothesis untestable. Also it was the cheapest: the interface
counters were already in the sidecar.

`tx_dropped 0`, `rx_errors 0`, at both ends. The link had lost nothing. The
`AF_PACKET` socket had: a Python loop doing one `select` and one `recvfrom` per
packet cannot keep up with a burst of nine hundred, and the socket discards what
it cannot buffer. **33 packets, silently.**

Fixed — bigger buffer, drain to `EAGAIN` rather than one packet per `select`,
and `PACKET_STATISTICS` read at the end so a non-zero drop count fails the
capture — and re-ran.

**237 packets** where 368 were sent, and now *every* packet was an orphan
continuation. The first record in the file had `SOM` clear.

**根因** Two faults, found in the order they could be told apart, and the second
was hiding behind the first.

The second one: the capture started two thirds of the way through. The guest
runs `python3` out of a root filesystem exported over 9p, so the interpreter's
own start-up — every import, stat and read — crosses that. The generator was
started after `sleep 0.7`. **A sleep is not a synchronisation primitive**, and
the failure mode is not an error, it is a plausible number.

**教訓** Both faults produced *plausible output*. Not a crash, not a non-zero
exit — a packet count, in the right format, that a reader would have believed.
The first symptom of the second fault was a page of complaints about the link,
which is a diagnosis of the wrong subsystem produced confidently by a correct
analysis reading a broken input.

★ Rule 17, added today: **an instrument reports its own losses, or its output is
not a measurement.** The capture now reads the kernel's own drop counter and
refuses itself on a non-zero value; it creates a readiness file after `bind()`
and the traffic generator blocks on that file instead of on a duration; and
`--observed` compares the capture's packet count against the interface counters
for the same window.

★ And rule 13 earns its keep here, which is the detail I want on the record:
**the two faults are caught by different checks, and neither check can see the
other's fault.** The interface-counter comparison cannot detect a late start —
the counters are read when the capture starts, so a late start makes them agree
perfectly. The reassembly check cannot detect a uniform loss that happens to
take whole messages. Two failures, two mechanisms, and a suite with only one of
them would have reported twice the coverage it had.

This is the third time this project has found that a green result came from a
tool answering a slightly different question than the one asked. 2026-08-11 was
`$?` from three programs. 2026-09-14 was a flag parsed and never read. Today was
an instrument that could not report its own loss. **The shape is constant: the
thing that reports success is not the thing that was supposed to succeed.**

---

### What the day produced

| | |
|---|---|
| Gate 5, route ③ | both arms over a real MCTP link. **A0 115 packets, P2 953**, model reproduces every one, `tx_dropped` 0 |
| Gate 5, route ② | `lspci -vvv` sees a DOE capability; DOE Discovery enumerates three protocols; one `GET_VERSION` returns `VERSION` advertising 1.0–1.4 |
| ★ the control | the same two handshakes at the message layer are byte-identical to week eight's socket-line captures — 22/6,559 and 46/58,966, same per-message length sequence. **The transport changed nothing about the protocol** |
| ★ the transport result | **packet ratio 8.29× where the byte ratio is 9.11×**, because a transmission unit is charged whole. On a bus where per-packet cost dominates, 8.29 is the number to quote, and no socket capture can say so |
| new claims in `bench/claims.json` | five, including both controls, re-derived at tolerance 0 |
| new standing rules | 17 and 18 |
| new ADR | 0010 — a kernel is a build |
| retired sentence | *"No packet count here has been observed."* |

**A number that got smaller.** `docs/fragmentation.md` used to say the MCTP
column was `COMPUTED`. It now says `MEASURED since 2026-09-18` — at one
transmission unit. 128 and 256 are still computed and still labelled, because
`mctp-serial` fixes its MTU at 68 in the driver and no other value is reachable
on that binding. That is stated where the table is, not in a closing section.

---

**`TODO(me)`** — `c-drills`. Eight drills, **zero** finished, eleventh working
day, `SCORECARD.md` still eight empty rows, `mock/round1.md` set on 2026-09-14
and still not sat. This is now the largest gap in the repository by a wide
margin and its shape has not changed since Day 10: the project track is
producing work for a track that has never started. The implementations are not
mine to write — the number that track exists to produce is how many compile
errors a paper version has when it is first typed in, and an implementation
written by anything else sets that number to nothing.

**`TODO(me)`** — Two upstream changes are now prepared and not sent. The
`openbmc/spdm` README is written against the review that killed the 2025 attempt
and passes OpenBMC's own prettier and markdownlint; the DMTF `CoRimTool.py` fix
has been ready since 2026-09-12. **Eighteen findings and zero conversations.**
The number of findings is no longer the interesting quantity.

**`TODO(me)`** — SLH-DSA still does not complete a handshake on this build, and
the status is still unrecoverable under `TARGET=Release`. Unchanged from Day 10.

**`TODO(me)`** — The DOE route sends one message. A full handshake over DOE
needs either an in-kernel CMA-SPDM requester — which arrives in a later Linux
than 6.12 — or a userspace SPDM state machine, which is libspdm's job and not
`doe_probe`'s. Named rather than left as an absence.

**`TODO(me)`** — What I am least sure about right now: _______________

## 2026-09-20 · Day 12 · the instrument said I was wrong, and the instrument was wrong

Gate 6's upper half. DMTF's own conformance suite, run four ways against this
project's responder; libspdm's own fuzz targets, seeded from this project's own
captures and measured against the corpus upstream ships; and a coverage figure
so that "no crashes" has a denominator.

Two things are worth keeping and they point in opposite directions. The first is
a claim I was able to make stronger than expected — the suite reports four
failures and the device is not at fault, and that is **proved** rather than
argued. The second is a claim I had to withdraw: the sentence this week was
supposed to produce about fuzz seeds is false, and I have the numbers that say
so.

The second is the one to read.

---

### 1. Four FAILs, and how to tell whose fault they are

**現象** `SPDM-Responder-Validator`, at the submodule commit `spdm-emu 4.0.0-rc`
already pins, reports eight failing assertions against this responder. Four of
them are in `CHALLENGE_AUTH` and all four carry the same message:

```
test assertion 6.2.7  - FAIL response signature
test assertion 6.3.7  - FAIL response signature
test assertion 6.12.7 - FAIL response signature
test assertion 6.13.7 - FAIL response signature
```

A signature that does not verify is the worst thing a conformance report can
say about a device. It is also the thing a device owner is least equipped to
argue with.

**假設** Three, and the third is the one nobody reaches for first.

1. **The responder's signature is wrong.** Some transcript the responder
   includes and the specification does not, or an off-by-one in a length.
2. **The suite is testing something this configuration does not support**, and
   the FAIL is a capability question wearing a cryptography costume — the same
   shape as the other four failures, which are `MutAuthRequested` and are
   plainly configuration.
3. **The suite is wrong.** Not "the suite tests something optional", but: the
   assertion is unsatisfiable for a reason that lives inside the suite.

**先驗哪個、為什麼** None of them first. **The discriminating fact first**, and
it was free.

The case names encode which messages each case sends. Reading them out of the
source rather than from the documentation:

| case | mask | result |
|---|---|---|
| 6.1 `A1B1C1` | VCA + `GET_DIGESTS` + `GET_CERTIFICATE` | PASS |
| 6.2 `A1B2C1` | VCA only | **FAIL** |
| 6.3 `A1B3C1` | VCA + `GET_DIGESTS` | **FAIL** |
| 6.14 `A1B4C1` | VCA + `GET_CERTIFICATE` | PASS |

6.14 omits the digests and passes; 6.3 performs them and fails. **The
certificate fetch is necessary and sufficient and the digests are irrelevant.**
That single comparison removes hypothesis 1 almost entirely — a transcript
defect would not be conditional on whether the *requester* fetched a
certificate — and it points at a missing input rather than a wrong output.

Reading the source then gives the mechanism in three lines: the case's setup
fetches the chain at `:202`, the case body calls `libspdm_init_connection()` at
`:363`, that sends `GET_VERSION`, `GET_VERSION` calls `libspdm_reset_context()`,
and `libspdm_reset_context` frees `connection_info.peer_used_cert_chain[]`.

**And there I stopped, because a mechanism read out of source is a story.**
2026-09-12 is in this file because a story exactly that plausible — "the key is
constructed wrongly, therefore the verifier accepts nothing" — was true and
incomplete, and acting on it alone would have turned a verifier that accepts
nothing into one that accepts anything. Standing rule 19 came out of that day.
So the story does not get published; the arithmetic does.

**根因** `harness/challenge_verify.py` rebuilds `M1M2 = A || B || C` from the
capture and hands the verification to OpenSSL — this file owns structure,
OpenSSL owns cryptography, which is `certs/check_chain.py`'s division and its
words. ★ **It calibrates before it answers**: it verifies the nine connections
that *did* fetch the certificate and that the suite passes, and only if all nine
verify does it report on the two that did not.

```
calibration   9 of 9 verify
disputed      2 of 2 verify
  packet 284   M1M2  266 B (144 +   0 + 122)  -> True
  packet 306   M1M2  370 B (144 + 104 + 122)  -> True
```

The middle term is the finding in one number: 1,775 bytes of certificate
exchange in the transcripts that pass, **0** and **104** in the two that fail,
and the signatures over those shorter transcripts are good.

**So: the responder is correct, the specification is not involved, and the
conformance suite reports a conforming device as non-conforming.** Upstream
candidate ⑲.

**教訓** Two, and the second is the general one.

★ **A calibration step is what converts a tool's verdict into evidence.** The
verification tool could have been written to answer only the disputed question.
It would have produced the same `True` twice and been worth nothing, because a
reader cannot distinguish "the signatures are good" from "the transcript model
is wrong in a way that happens to verify". Checking it first against the case
everyone agrees about is what makes the disagreement mean something — and the
tool exits 1 without offering a verdict if the calibration fails, so the order
is a mechanism rather than an intention.

★★ **And the general one: when a measuring instrument disagrees with the thing
being measured, the instrument is a hypothesis too.** I have spent eleven weeks
building tools that check this project's claims. This is the first week one of
those tools was pointed at somebody else's tool, and the answer was that the
other one was wrong. The reflex when a respected reference implementation says
your device fails is to look at your device; the reflex that produced this
result was to ask what would have to be true for the suite to be right, notice
that it needed a public key it did not have, and then go and check.

---

### 2. A sentence I had planned to say, and the measurement that withdrew it

**現象** The plan for this week names the seed corpus as one of three things
the fuzzing half is worth doing for:

> *"My fuzz seeds are not random, they are messages extracted from my own real
> handshake pcaps. AFL needs a structurally valid input to mutate from —
> give it random bytes and it will spend millions of executions circling the
> version field of `GET_VERSION`."*

The first half is true and I built the exporter for it. The second half compares
against something nobody does.

**假設** Two readings of "better", and they are not the same claim.

1. **Better than random bytes.** Trivially true, and worthless: no one seeds a
   fuzzer with random bytes, so the comparison has no opponent.
2. **Better than the corpus libspdm already ships.** `unit_test/fuzzing/seeds/`,
   69 directories, 81 files, mostly one hand-written seed per target. This is
   the real rival and it is the one standing rule 18 requires to be evaluated:
   *a claim that two things differ has to evaluate both of them.*

**先驗哪個、為什麼** The second, because the first cannot fail. `afl-showmap -C`
executes an entire corpus and reports the union of the edges it reached —
deterministic, so a single value rather than a distribution, and comparable
across corpora by construction.

**根因** The first run drew seeds from the two published handshakes, `A0-all`
and `P2-all`. It lost.

```
  target                          upstream   mine   both   added
  test_spdm_responder_algorithms       601    378    601      +0
  test_spdm_responder_version          442    442    442      +0
```

378 against 601 on `algorithms`, and **zero** edges added to upstream's corpus.
Ten of seventeen targets could not be seeded at all.

The reason is not about fuzzing. **Two successful handshakes contain exactly one
well-formed message per type and nothing else** — no version mismatch, no
invalid parameter, no error path, because a handshake that took one would not
have completed. And ten targets were empty because no capture in this repository
contains a `KEY_EXCHANGE`: `harness/lib/arms.sh` pins `--exe_session NO_END`,
which does not include `EXE_SESSION_KEY_EX`, and **no arm of this project's A/B
has ever established a secure session.** That file has said so in its own
comment since it was written in week eight. It took a fuzz corpus to make the
consequence visible.

Adding one capture — the conformance run, which sends malformed and
version-mismatched requests *deliberately* — reversed it:

```
  test_spdm_responder_algorithms       601    685    711    +110
  test_spdm_responder_capabilities     436    535    535     +99
  test_spdm_responder_measurements    3630   3744   3744    +114
```

**Same tool, same method, different source run.** And even then, on three of
thirteen comparable targets my corpus still reaches fewer edges than upstream's
single hand-written seed, and on five the union exceeds both — the two corpora
are **complementary rather than ordered**, which is a more useful finding than
either of the two sentences I might have written.

**教訓** ★ **A seed is not good because it is real. It is good because the run
it came from went somewhere.** "Real" is a property of provenance and it feels
like a quality argument; it is not one. The quality argument is about coverage
of *behaviour*, and a capture of a run that succeeded is a capture of the happy
path by definition.

★★ And the methodological half: **the first run is committed, with its losing
numbers.** `w10-fuzz-20260919T185226Z` produced a table where my corpus adds
nothing, and deleting it and keeping only the run that won would have left a
page asserting exactly what this week disproved. The pair is the finding.

---

### 3. Deviations from `plan/W10`, with reasons

`CLAUDE.md` asks for the reason rather than the conclusion. The plan was
written on 2026-08-16; seven of its statements did not survive contact.

| plan said | actually | why it matters |
|---|---|---|
| the validator has **20 test groups** | the README documents 20; **12** have a source file. PSK, encapsulated, CSR, `SET_CERTIFICATE` and chunking have no implementation | saying "twenty groups" to anyone who has read the tree converts "has done this" into "has not read it" |
| `libspdm` has **six fuzz targets** | six target *families*, **about sixty-nine** individual targets | an order of magnitude, in the direction that makes upstream look less thorough than it is |
| my seeds beat random seeds | the rival is upstream's shipped corpus, and on three targets **it wins** | §2 |
| `spdm-emu`'s disclaimer, quoted and marked "✅ quoted correctly" | the quote in the plan is a paraphrase. The actual text is *"This package is only the sample code to show the concept. It does not have a full validation such as robustness functional test and fuzzing test. It does not meet the production quality yet."* | a paraphrase in quotation marks is the thing standing rule 7 exists to prevent, and it was marked as checked |
| Friday: check whether the `openbmc/spdm` change got a reply | it was never sent. `docs/upstream/README.md` rows 42–43 have said `TODO(me)` since September | nothing to check. What the day became instead is in §4 |
| run `./bin/test_spdm_fips` | it **refuses to run**: `LIBSPDM_FIPS_MODE` is `0` in `spdm_lib_config.h:139` and the test says *"valid only when LIBSPDM_FIPS_MODE is open"* rather than passing vacuously | good test design, and it means the FIPS vectors are **not** exercised here. `docs/threat-scope.md` says so |
| the `rats` CI job arrives in W11 | it has existed since 2026-09-12 | `CLAUDE.md` still carries the stale sentence; the file is the author's to change |
| DoD: `LOG.md ≥ 46`, `commit ≥ 96` | 13 entries and 170 commits before today | different counting bases. Entries here are per *day*, not per event. Recorded rather than silently ignored |

None of these changed the shape of the week. All seven are the same failure
mode — a planning document written before the tree was read — and the response
is the one this project already uses for version numbers: **the tree is the
truth and the document gets corrected.**

---

### 4. Three bugs I wrote today, and what each one cost

Worth recording because all three are in the harness rather than in the thing
being measured, and all three had the same symptom: **no error.**

**The proxy that never stopped.** `run_validator.sh` started
`harness/tamper_proxy.py` without `--once`. Its `run()` loops on `accept()`
forever, so the arm's handshake completed, its capture was written, and the
script hung on `wait` with every artifact correct. Cost: one aborted run,
removed because it had no manifest and therefore, by this repository's own rule
3, no result. The fix is one flag and eight lines of comment saying why.

**Sixty-nine fuzz targets counted as failing unit tests.** `run_coverage.sh`
discovered its test binaries as `test_*` in `build_cov/bin`. A GCC build of
libspdm also produces every fuzz target, uninstrumented, and a fuzz target run
with no argument prints `file error` and exits 1. The first run reported "77
unit tests, 6 failed" — and six failures would have gone into
`docs/negative-tests.md` as if the library were broken. The exclusion is now
taken from the directory names under `unit_test/fuzzing/` rather than from a
pattern.

**A `grep` that matched nothing.** Truncating the 24 MB of test chatter used a
`grep | grep -v | tail` pipeline inside a command group, under `set -e` and
`pipefail` from `lib/common.sh`. A test whose output format the pattern did not
match returned 1 and took the whole script down *between two passing tests*.
Symptom: a run directory with nine kilobytes in it and no manifest.

★ **All three produced a plausible-looking intermediate state rather than a
failure**, which is the property standing rule 17 was written about in September
for captures. It is not specific to captures.

---

### 5. What went right, recorded so it can be repeated

- **The control came first, again.** `proxy-inert` was run before
  `proxy-flip-sig` and asserted to reproduce the baseline exactly. Without it,
  the single regression in the tampered arm would be indistinguishable from a
  proxy that cannot forward a 1.6 MB conformance run.
- **The transcription was checked rather than trusted.** The `--cap` list minus
  `MUT_AUTH` is transcribed from `key.c`, and the assertion is not that the
  transcription is right — it is that the two captures' `Flags` words differ in
  `MUT_AUTH_CAP` and nothing else, **in every negotiated version**. A missing
  bit in the list fails that check by name.
- **The advisory identifiers stayed out.** `plan/W11` names four. None has been
  checked against a primary source from this machine, so `negative/negative.h`
  says so and W11 fetches them. A wrong identifier attached to a real class is
  worse than no identifier.
- **The freshness check happened immediately before the offer.** Both prepared
  upstream changes were re-checked today rather than assumed: `DMTF/spdm-emu` is
  still at `ea77f25`, `openbmc/spdm` still has no README and is zero commits
  further on, and the README's linters were re-run with configs fetched today.
  A change verified in September and sent in October is a change verified
  against a repository that no longer exists.

## 2026-09-22 · Day 13 · four identifiers that were right, and a URL that was not

Gate 6's lower half. The three advisory classes written as tests that can fail,
the identifiers checked against their primary sources, and — because the
question was there and the evidence was reachable — whether this project's own
two builds carry the defects.

Four things worth keeping. The first is the one I did not expect to be a
finding at all, and the last is a prediction of mine that the machinery
refused.

---

### 1. Every identifier was correct and the obvious URL returned 404

**現象** `plan/W11` names three GHSA identifiers and one CVE. W10 refused to
write any of them into a source file — standing rule 7 — so the first task of
the week was to check them. The first request returned 404. So did the second
and the third:

```
404  https://api.github.com/advisories/GHSA-m4wc-xmvg-369f
404  https://api.github.com/advisories/GHSA-j54w-759w-xj3m
404  https://api.github.com/advisories/GHSA-chjj-xvqx-c8w4
404  https://cveawg.mitre.org/api/cve/CVE-2026-61810
```

Four for four, from two independent databases.

**假設** Three, and they are not equally likely.

1. **The identifiers are wrong.** A plan written weeks ahead naming four
   plausible-looking advisory IDs is exactly the shape of a fabricated
   citation, and rule 7 exists because that shape is common.
2. **The advisories exist somewhere else.** GitHub's *global* database ingests
   advisories for packages in ecosystems it knows — npm, PyPI, Go. A C library
   built with CMake is in none of them.
3. **The request needs authentication.** Plausible for a rate limit, less so
   for a 404.

**先驗哪個、為什麼** (2), and on grounds that had nothing to do with the
advisories.

**A 404 from an aggregator and a 404 from the owner are different claims, and
only one of them had been made.** Every one of those URLs asks a database that
collects other people's advisories. The repository that publishes them had not
been asked, and asking it is one request.

The second reason is about the plan rather than the protocol: the surrounding
details were *internally consistent in a way fabrications usually are not*. The
CVSS vector `AV:A/AC:L/AT:P/PR:N/UI:N/VC:N/VI:H/VA:N` scores to 6.0 under the
4.0 metrics, the affected ranges `3.4–3.8.1` and `3.0–3.8.1` fit a real release
history, and the five internal anchor names were spelled the way a real
document spells them. A wrong identifier usually arrives with wrong
neighbours.

**根因** All three are **repository advisories** on `DMTF/libspdm`, published
through GitHub's per-repository security advisory feature, and never ingested
into the global database because libspdm is not in a package ecosystem it
covers. One request to `api.github.com/repos/DMTF/libspdm/security-advisories`
returned all five advisories the project has ever published, 2023 and 2026.

And the checking produced three facts I would have got wrong by assuming:

| | |
|---|---|
| **two of the three have no CVE at all**, and they are the two with the *higher* score — 6.9 against 6.0 | DMTF-2026-0001 says why: *"due to the unlikely chance of implementation in a production device, no CVE has been issued"* |
| `CVE-2026-61810` is in **neither** NVD nor MITRE's CVE Services | GitHub is a CNA and assigned it; the record had not propagated |
| libspdm 3.8.2 was published **133 seconds** after the advisory it fixes | 19:23:38Z and 19:25:51Z on 2026-04-03 |

**教訓** **Whether an identifier resolves is a property of the database you
asked, not of the identifier.** So a citation has to carry the URL that
*resolves*, and this repository now pins one per advisory
(`third_party/dmtf-2026-000N.pin`) with the retrieval digest and an
`in-global-advisory-database=no` field, because the absence is the part a
reader will trip over.

The stronger version, which is about how to answer a question rather than how
to cite one: **when a lookup fails, the next question is "did I ask the thing
that owns the answer", not "is the answer wrong".** I had three hypotheses and
the cheapest discriminating request settled it in twenty seconds, which is
2026-09-20's lesson arriving in a different costume — *the discriminating fact
first, and it was free*.

---

### 2. A capability that 96 captures advertise and an intersection reported absent

**現象** The exposure checker needs to know whether the responder advertises
`MEL_CAP` and `CHUNK_CAP`, because DMTF-2026-0002 requires both. Its first
version took the **intersection** of the responder flags over every committed
capture and reported `CHUNK_CAP` **absent** — which would have turned the
verdict from AFFECTED into PRESENT-NOT-REACHABLE.

**假設** (a) the responder genuinely does not advertise it; (b) the flags
parser is reading the wrong side of the exchange; (c) some captures clear it.

**先驗哪個、為什麼** (c), immediately, because **this repository contains arms
named after doing exactly that.** `A0-nochunk` and `P2-nochunk` exist so that
`docs/pqc-cost.md` can compare a chunked fetch against a windowed one; clearing
`CHUNK_CAP` is their entire purpose. The hypothesis was not a guess about the
data, it was a memory of why the data exists.

**根因** 96 of 98 captures advertise it. Two clear it deliberately. An
intersection over a set that includes deliberate negative controls reports the
controls as the configuration.

**教訓** **"The configuration lacks X" and "an experiment removed X" are
different facts, and a set intersection erases the difference.** The tool now
reports a count — `MEL_CAP and CHUNK_CAP advertised together in 96 of 98` — and
a precondition is satisfied when at least one capture shows all the bits it
needs, with the count printed beside the verdict.

★ And the general form, which is the half worth carrying: **a negative control
is data that is supposed to disagree, so any aggregate computed across a corpus
that contains one is computing something else.** This repository has spent ten
weeks building arms whose job is to differ. Every statistic over "all captures"
is now suspect by default, and the two that exist are counts rather than
intersections.

---

### 3. The first draft of the sanitizer demonstration did not compile, and that was the result

**現象** `negative/test_oversized_field.c` was meant to show that
AddressSanitizer reports an overflow out of a bare `char[64]` and says nothing
about the same overflow into the next member of an enclosing struct. It did not
build:

```
error: '__builtin___memcpy_chk' forming offset [64, 71] is out of the
bounds [0, 64] of object 'cn' with type 'char[64]' [-Werror=array-bounds=]
```

**假設** (a) the test is wrong; (b) `-Werror` is too strict for a deliberate
overflow; (c) the compiler is telling me something.

**先驗哪個、為什麼** (c), because of *which* builtin is named. `__builtin___
memcpy_chk` is `_FORTIFY_SOURCE`'s fortified `memcpy`, and it only appears when
the compiler can prove a size — so the diagnostic is not a style complaint, it
is a static bounds check that fired. And it fired on the **bare array** half
and not on the struct-member half, which is the same asymmetry the runtime
demonstration was written to show, one layer earlier.

**根因** `__builtin_object_size` of a sub-object reports the size of the object
that *encloses* it, so `f.cn` is 320 bytes to the fortifier and `cn` is 64. GCC
therefore rejects one and not the other — and it can only do either because the
length was a literal `72`.

**教訓** **The static check draws the same line the sanitizer draws, and it
only draws it when the length is a constant.** A firmware length is never a
constant: it is a field off the wire. So the demonstration makes the length
`volatile`, which is what makes it honest rather than a compiler exercise, and
`negative/asan_demo.sh` now asserts both halves at run time so that a toolchain
upgrade changing either answer turns the build red instead of quietly
invalidating a paragraph in `docs/negative-tests.md`.

★ The line worth keeping: **three layers were supposed to be watching this
overflow — the compiler, the sanitizer, and the bound in the code — and each of
them watches a different subset.** Which is rule 11 pointed at the instruments
rather than at the code: *a check is worth what it rejects*, and until this
week nothing here had established what AddressSanitizer rejects.

---

### 4. ★ A prediction of mine that the machinery refused

**現象** Each negative test declares, in advance, exactly which cases a given
deliberately-wrong implementation must move. `test_transcript_coverage.c`
defect 3 — *the whole message is demanded, authenticator included* — was
declared to move cases 0, 4 and 6, the three that expect `NEG_OK`. The runner
refused it:

```
[3] **BAD**  the signature appended to its own
             got      NEG_OK   <-- the input was ACCEPTED
WRONG DOOR   1 case(s) moved that were not predicted to
```

**假設** (a) the runner's set comparison is wrong; (b) case 3 is redundant with
another case; (c) the prediction is wrong.

**先驗哪個、為什麼** (c), because the other seven defects had just passed on the
same comparison code, and because the report named the direction: the
unpredicted case was **ACCEPTED**, not merely moved. A comparison bug does not
produce a coherent severity. And "accepted" is a specific enough claim to check
by hand in one line.

**根因** Case 3 feeds a transcript whose last slice covers the whole `FINISH`
including its signature — and defect 3 demands exactly that. **The one mistake
refuses every correct transcript and accepts the one incoherent one**, because
covering-the-authenticator is both what it wrongly requires and what case 3
wrongly does.

**教訓** I had reasoned about a defect in one direction — *what will it
refuse* — and a defect has two. The declaration is now `{0, 3, 4, 6}` with
`{3}` as the accepted subset, and the comment beside it says which came first.

★ **That is the mechanism doing the job the rule was written for.** Standing
rule 11 says a check is worth what it rejects. Rule 13 says two breaks caught
by one check are one check. Both were satisfiable by hand for nine weeks and
neither was ever exercised against *my own reasoning* until the prediction was
written down where a build could disagree with it. **The difference between a
discipline and a mechanism is whether it can tell you that you are wrong on a
Tuesday.**

---

### And one thing that was spent rather than learned

`negative/test_offset_length.c` and `negative/test_oversized_field.c` contain
worked, correct versions of what `c-drills` D2 and D8 ask for. Writing them
this week **cost those two drills their measurement** — particularly D2's
second question, *which version did you reach for first*, which was the only
evidence in this repository about what gets reached for under time pressure.

It was a deliberate trade with a cheap alternative that was not taken: doing
the two drills first, on paper, would have cost twenty-five minutes and kept
both. `c-drills/SCORECARD.md` records it as a decision with its price rather
than leaving two rows that quietly mean something else than the other six.

**教訓** — and it is a scheduling one rather than a technical one:
**when two pieces of work share a subject and one of them is a measurement of
me, the measurement goes first, because it is the only one of the two that
cannot be redone.**

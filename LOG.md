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
noticing why: the queue was not shortened, it was simply entered earlier, for
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
through `| tee` without `set -o pipefail` or `PIPESTATUS` reports success for
a build that failed. That second point is worth more than the first: it is a
silent-wrong-answer class of bug, and it is the same class as the reason
`bench/data/*/manifest.json` exists.

### Things the environment cannot do, recorded now rather than discovered later

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
argument had not taken, nothing else is worth investigating. The emulator
echoes `exe_conn - 0x0000001e`, and the header defines
`DIGEST 0x2 | CERT 0x4 | CHAL 0x8 | MEAS 0x10` = `0x1e`. Parsed correctly.
That eliminated (b) and made (c) the only hypothesis consistent with an error
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
specific function and gives its type — a stale cache produces missing files or
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

**假設** (a) the post-quantum handshake genuinely stopped after
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
`InvalidRequset` errors and 17 `MEASUREMENTS`. That looks like the emulator
walking measurement indices and being told most do not exist. Whether that is
the emulator's choice or something the specification implies is a question for
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

**現象** `README.md` states the `stable` flavor is libspdm 3.8.2. So do four
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
   a number that contradicts its own source is the most expensive kind of error
   it can carry** — more expensive than a wrong measurement, because it
   discredits the mechanism rather than one result. The failure mode is
   specific: facts that are only ever *stated* have nothing checking them,
   while facts that are *computed* are checked every run. Where the two overlap,
   the stated one is the one that rots.

Fixed here, and the correction was not only the digit. The tables now name both
`spdm-emu` and `libspdm`, because naming only the one that is not pinned is
what made the drift possible; and the cost of the pinning rule — which ADR 0001
gave as "3.8.0 lacks the two 2026 advisory fixes" — was moved into `README.md`
and `RUNBOOK.md` next to the table, rather than left in ADR 0001 for a reader
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
names a CVE or GHSA identifier at all. Two further things fell out that matter
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
   a stranger reads first, and that is the act that made it my assertion rather
   than an inherited one. **I wrote the previous entry — about facts that are
   only ever stated having nothing to check them — and then committed exactly
   that failure one commit later.** Knowing the failure mode is not the same as
   being immune to it, which is the argument for mechanisms over intentions and
   is the reason `prov_begin` exists. There is no equivalent mechanism for
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

**假設** For (1): (a) the files were deleted after the run, (b) they were never
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
  existing measurement list, then query measurement one by one."* A requester
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
   the SPDM 1.2 transcript rule directly — and where it does not, the behaviour
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
the size is a whole group being dropped (`--dhe NONE`: one fewer
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

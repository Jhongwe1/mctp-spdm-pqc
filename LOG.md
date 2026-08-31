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
what I read, what I concluded, how the drill went. They are left blank rathe
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

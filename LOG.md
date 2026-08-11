# Engineering log

Working notes, newest last. Each technical entry uses the same five parts:

**現象** what was observed ·
**假設** what it could have been ·
**先驗哪個、為什麼** which hypothesis was tested first and on what grounds ·
**根因** what it actually was ·
**教訓** what changes as a result

The third line is the one that matters. Anyone can list what they tried.
Choosing *which* thing to try first, and being able to say why, is the whole
content of the question "how do you debug".

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

**`TODO(me)`** — CLA status. It goes to `manager@lfprojects.org`, and signing
it inside Gerrit is *not* the same thing. Confirm whether it was already sent
for the other project; if so record the date here, if not send it today and
keep the sent copy under `docs/upstream/`. This has a waiting time attached,
which is the only reason it is urgent on day one.

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

# Change 0004 — `spdm-emu` has no run-time `DataTransferSize`

- **Repo:** `DMTF/spdm-emu` (GitHub pull request)
- **Files:** eight — `spdm_emu_common/{spdm_emu.c,spdm_emu.h,key.c}`, the
  requester and responder `*_spdm.c`, the validator and attester samples'
  `*_spdm.c`, and `doc/spdm_emu.md`. `+78 −7`.
- **Status: PREPARED, NOT SENT, 2026-09-29.** The commit is unsigned; the
  sign-off and the push are the author's (§7).
- **Found:** 2026-09-14, building the DataTransferSize sweep behind Figure 3
  ([`README.md`](README.md) ⑰, [`../pqc-cost.md`](../pqc-cost.md) §9).
- **Branch:** `$LAB_DIR/work/spdm-emu-pr`, `data-transfer-size-flag`, commit
  `eb294e4`, on upstream `main` at `eff07cf` (the `4.0.0-rc2` tag). Built and
  tested in `$LAB_DIR/work/spdm-emu-upstream`; the committed diff has the same
  `patch-id` as the tested one, `04cda517f2d84454`.

## 0. Why it is worth a maintainer's time

`DataTransferSize` decides whether a message crosses the transport whole or as
a series of `CHUNK_GET`/`CHUNK_RESPONSE` exchanges, each a full round trip. It
is the parameter an integrator of a buffer-constrained endpoint actually sizes,
and on this project's post-quantum arm, moving it over a 32× range moved the
bytes 3.1% and the round trips from 59 to none. `spdm-emu` fixes it at build
time: libspdm derives it from the receiver buffer registered with
`libspdm_register_device_buffer_func()`, minus the transport header and tail.
So exercising chunking at another value, or emulating a small endpoint, means
another build — which is what this project did, as a third build flavor
([ADR 0009](../decisions/0009-a-third-build-flavor.md)).

`libspdm_set_data()` is not a way round it: in libspdm 4.0.0-rc2 it has no case
for `LIBSPDM_DATA_CAPABILITY_DATA_TRANSFER_SIZE` at all. Registering a smaller
receive buffer is the route the library itself takes.

## 1. What it does

`--data_transfer_size <bytes>`, accepted from **42** — DSP0274's
MinDataTransferSize, paragraph 273 of 1.4.1 — up to the build's own
`LIBSPDM_DATA_TRANSFER_SIZE`, so it can lower the advertised value and never
raise it past the buffer.

Three details, each of which was wrong or missing in this project's own version
of the patch and was found by rebuilding it on upstream's head:

| | the rule | where it comes from | this project's `pqc-dts` patch |
|:-:|---|---|---|
| 1 | the receive buffer is the new value **plus the overhead the chosen transport registers** — 64 + 64 for MCTP, PCI_DOE and TCP, **none for NONE** | `libspdm_register_device_buffer_func()`; the NONE branch of each `*_init` | subtracted 128 everywhere, so NONE advertised 128 bytes more than asked |
| 2 | without `CHUNK_CAP`, `MaxSPDMmsgSize` **equals** `DataTransferSize` | DSP0274 1.4.1, the `MaxSPDMmsgSize` field of `GET_CAPABILITIES` and `CAPABILITIES`; enforced by the peer in `libspdm_req_get_capabilities.c` and `libspdm_rsp_capabilities.c` | left `MaxSPDMmsgSize` at the build value: the peer refuses `CAPABILITIES` |
| 3 | without `CHUNK_CAP`, `MaxSPDMmsgSize` must also be **at least the sender's** data transfer size, so the sender buffer follows | libspdm's context check, `libspdm_com_context_data.c` | never reached it, because of 2 |

The third was missed by the first build of this change as well: with `CHUNK_CAP`
cleared its responder exited before listening and printed nothing, because a
Release build compiles out the check's message. Reading the check against the
build's numbers found it — the sender's data transfer size, 4,352, against a
maximum of 1,024 — and the second build, with the sender buffer following,
starts and completes.

It applies to all four programs that call `process_args()` and register
buffers — the two emulators and the validator and attester samples — because a
flag that one of them parses, echoes and ignores is the defect this project had
just withdrawn a candidate for misdiagnosing (⑭). Without the option, nothing
changes.

## 2. The commit

```
spdm_emu: add --data_transfer_size option

DataTransferSize decides whether a message crosses the transport in one
piece or as a series of CHUNK_GET/CHUNK_RESPONSE round trips, and it is
the value an integrator of a buffer-constrained endpoint has to size.
spdm-emu fixes it at build time: libspdm derives it from the receiver
buffer registered with libspdm_register_device_buffer_func(), minus the
transport header and tail, so trying another value means another build.

Add --data_transfer_size <bytes>.  It lowers the value an endpoint
advertises in CAPABILITIES by registering a smaller receiver buffer.
It accepts 42, the MinDataTransferSize of DSP0274, up to the build's
own LIBSPDM_DATA_TRANSFER_SIZE, so an endpoint can never advertise more
than its buffer holds.  The buffer size accounts for the header and
tail that each transport registers, which is none for NONE, so the
advertised value is exact on every transport.

An endpoint without CHUNK_CAP must advertise a MaxSPDMmsgSize equal to
its DataTransferSize (DSP0274, the MaxSPDMmsgSize field of
GET_CAPABILITIES and CAPABILITIES), and libspdm's context check also
requires MaxSPDMmsgSize to be at least the sender's data transfer size.
So in that case both follow the new value.

The option applies to the requester and responder emulators and to the
validator and attester samples, which parse the same options.  Without
it, nothing changes.

Tested: GCC 13.3, Release, CRYPTO=openssl: builds under -Wall -Werror,
        no new warnings.
Tested: without the option, the ML-DSA-65 and ECDSA-P384 handshakes
        (--meas_op ALL) match the unpatched build in packets, bytes and
        per-message-type counts; so does ML-DSA-65 with
        --data_transfer_size 4608, the default.
Tested: 1024 on both sides: 1024 in both CAPABILITIES messages over
        MCTP and PCI_DOE (pcap) and over TCP and NONE (-v trace).  The
        ML-DSA-65 handshake completes with 59 CHUNK_GET, not 12.
Tested: 42 on both sides: the ECDSA-P384 handshake completes, with
        211 CHUNK_GET and 6 CHUNK_SEND.
Tested: CHUNK_CAP cleared on either side, with 1024 on that side: it
        advertises 1024/1024, and the handshake completes, reading the
        certificate chain in 6 GET_CERTIFICATE instead of 3.
Tested: spdm_device_validator_sample with 1024 sends it in its
        GET_CAPABILITIES.
Tested: 41, 4609, abc, 1024x, -1 and a missing value are rejected.

Assisted-by: Claude Code:claude-opus-5-5
```

## 3. The runs behind the `Tested:` lines

Scratch runs on 2026-09-29, not evidence for this repository: `spdm-emu`
`eff07cf`, `libspdm` `a6994ee` (both `4.0.0-rc2`), OpenSSL 3.5.5, GCC 13.3,
`-DARCH=x64 -DTOOLCHAIN=GCC -DTARGET=Release -DCRYPTO=openssl`, with this
project's eighteen controlled flags from `harness/lib/arms.sh` and
`--meas_op ALL`. **ctl** is the unpatched build of the same tree.
`DataTransferSize` and `MaxSPDMmsgSize` are read out of the `GET_CAPABILITIES`
and `CAPABILITIES` messages themselves: from the pcap for MCTP and PCI_DOE, and
from the emulator's own `-v` trace for TCP and NONE, which it cannot capture.

| run | build | flag | req DTS/Max | rsp DTS/Max | rc | bytes | packets | CHUNK_GET |
|---|---|---|---|---|:-:|--:|--:|--:|
| ML-DSA-65 | ctl | — | 4608/163840 | 4608/163840 | 0 | 58,966 | 46 | 12 |
| ML-DSA-65 | new | — | 4608/163840 | 4608/163840 | 0 | 58,966 | 46 | 12 |
| ECDSA-P384 | ctl | — | 4608/163840 | 4608/163840 | 0 | 6,559 | 22 | 0 |
| ECDSA-P384 | new | — | 4608/163840 | 4608/163840 | 0 | 6,559 | 22 | 0 |
| ML-DSA-65 | new | `4608` both | 4608/163840 | 4608/163840 | 0 | 58,966 | 46 | 12 |
| ML-DSA-65 | new | `1024` both | 1024/163840 | 1024/163840 | 0 | 60,394 | 140 | 59 |
| ML-DSA-65 | new | `0x400` both | 1024/163840 | 1024/163840 | 0 | 60,394 | 140 | 59 |
| ML-DSA-65, PCI_DOE | new | `1024` both | 1024/163840 | 1024/163840 | 0 | | | |
| ML-DSA-65, TCP | new | `1024` both | 1024/163840 | 1024/163840 | 0 | | | |
| ML-DSA-65, NONE | new | `1024` both | 1024/163840 | 1024/163840 | 0 | | | |
| ECDSA-P384 | new | `42` both | 42/163840 | 42/163840 | 0 | 13,108 | 450 | 211 |
| ECDSA-P384, responder without `CHUNK_CAP` | new | `1024` responder | 4608/163840 | **1024/1024** | 0 | 6,685 | 28 | 0 |
| ECDSA-P384, requester without `CHUNK_CAP` | new | `1024` requester | **1024/1024** | 4608/163840 | 0 | 6,685 | 28 | 0 |
| ECDSA-P384, responder without `CHUNK_CAP` | **pqc-dts** (this project's old patch) | `1024` responder | 32768/163840 | **1024/32768** | **1** | 72 | 4 | 0 |
| validator sample | new | `1024` validator | 1024/1024 and 1024/163840 among its 77 | 4608/163840 | cut at 25 s | | | |

- Per-message-type counts, not only totals, are identical in the inert rows.
- The two rows without `CHUNK_CAP` read the certificate chain in six
  `GET_CERTIFICATE` instead of three, windowed to 1024, and nothing is chunked.
- The `pqc-dts` row stops at `CAPABILITIES`: `libspdm_init_connection -
  0x80010005`. That is defect 2 in §1, measured on the build that made Figure 3.
- The validator run was stopped by a timeout after 25 seconds on purpose: its
  own `GET_CAPABILITIES` messages were the question, and they carry the value.
  `1024/1024` is the suite building a request of its own from the value it was
  given (`spdm_responder_test_2_capabilities.c:1175` sets `MaxSPDMmsgSize` to
  it). It also sent `1025/1025` once, from a case whose origin was not traced.
- Invalid values: `41`, `4609`, `abc`, `1024x`, `-1` and a missing value each
  print `invalid --data_transfer_size …` and the usage. They exit 0, like every
  other invalid option in `process_args()` (candidate 15), deliberately: one
  change should not also change the file's convention.

**Twice in these runs an exit status of 0 was a run that never happened.**
`--pcap` with `--trans NONE` or `--trans TCP` is refused with the usage and
`exit(0)`, so the first TCP run reported success with no capture and no
handshake. The table above uses the `-v` trace for both, and every row was read
for the messages it claims, not for its status.

## 4. Related upstream threads, found by searching before writing this

Searched on 2026-09-29 at 14:11 UTC for `data_transfer_size` and
`DataTransferSize` in `DMTF/spdm-emu` issues and pull requests:

- **#358** (open, `bug`, 2024-07-28): *spdm_responder_emu/spdm_requester_emu
  fails if transport NONE is selected* — `max_spdm_msg_size (4608) must be
  greater than or equal to data_transfer_size (4736)`. Still reproducible on
  4.0.0-rc2, now only with `CHUNK_CAP` cleared. This change is a workaround for
  it (with the option set, the two are equal on NONE too) and not the fix: the
  default path is untouched. The fix is one line once this change's helper
  exists, and should be its own pull request referencing #358.
- **#458** (closed 2026-08-28): the validator and attester samples advertised
  `MaxSPDMmsgSize 0x28000` without `CHUNK_CAP`. Closed as no longer
  reproducing. This change leaves those samples' maximum-message logic alone
  and only lowers their receive buffer when asked.
- **#329** (open): responder-side detection of an inconsistent
  `DataTransferSize` for SPDM 1.0/1.1 requesters. Unrelated.

No issue or pull request proposes a run-time `DataTransferSize`.

## 5. What is deliberately NOT in this change

- **The fix for #358.** Separate, and a behaviour change on the default path.
- **Exit status on invalid input.** Candidate 15; 91 sites.
- **`MSVC`.** Built and run with GCC on Linux only. The change uses `strtoul`
  and nothing platform-specific, and upstream's CI builds Windows too; that is
  where it would show.
- **`uncrustify`.** The repository has `.uncrustify.cfg` for 0.69 and
  `script/format_nix.sh`; neither is run by its CI, and 0.69 is not installed
  here. The code follows the surrounding layout by hand.

## 6. The pull-request body

> ### Add `--data_transfer_size` to set the advertised DataTransferSize at run time
>
> `DataTransferSize` decides whether a message is sent whole or as
> `CHUNK_GET`/`CHUNK_RESPONSE` round trips. In spdm-emu it comes from
> `LIBSPDM_RECEIVER_BUFFER_SIZE` at build time, so trying chunking at another
> value, or emulating an endpoint with a small receive buffer, needs a rebuild.
>
> This adds `--data_transfer_size <bytes>` (42 up to the build's
> `LIBSPDM_DATA_TRANSFER_SIZE`; it can only lower the value). It registers a
> smaller receive buffer, which is where libspdm derives the advertised value
> from. It is wired into the two emulators and the validator and attester
> samples, which share the option parser.
>
> Two details worth a look:
>
> - The buffer is computed per transport, since NONE registers no header or
>   tail, so the advertised value is exact on MCTP, PCI_DOE, TCP and NONE.
> - Without `CHUNK_CAP`, DSP0274 requires `MaxSPDMmsgSize` to equal
>   `DataTransferSize`, and libspdm's context check requires `MaxSPDMmsgSize` to
>   be at least the sender's data transfer size; in that case both follow the
>   new value.
>
> Without the option nothing changes: the ML-DSA-65 and ECDSA-P384 handshakes
> match the unpatched build in packets, bytes and per-message-type counts. With
> `--data_transfer_size 1024` on both sides, both `CAPABILITIES` carry 1024 and
> the ML-DSA-65 handshake takes 59 `CHUNK_GET` round trips instead of 12. At 42,
> the minimum, an ECDSA-P384 handshake still completes. The full list is in the
> commit message.
>
> Related: with this option set, `--trans NONE` also works without `CHUNK_CAP`,
> which #358 reports failing; the default path is unchanged, so #358 itself is
> not fixed here. Invalid values exit 0 like the other options in
> `process_args()`.

## 7. The checklist, and sending it

```
 ── mechanised: bash harness/check_upstream_commit.sh ~/spdm-lab/work/spdm-emu-pr ──
☑ Assisted-by present, no AI in Signed-off-by, no Co-authored-by
☑ subject 41 chars, body within 72, Tested: lines
☑ one commit, clean tree, no file executable without a #! line
☐ exactly one Signed-off-by, matching the author      ← the author's

 ── only the author can tick these ──────────────────────────────────────
☐ the diff read line by line; doc/spdm_emu.md is CRLF and stays CRLF (191/191)
☐ ON THE DAY: upstream main has not gained a DataTransferSize option, and
    #358 has not been fixed in a way that conflicts
☐ ON THE DAY: the branch applies to main; if main moved, rebuild and re-run §3
☐ decide the order: 0003 first (small, same file as the merged #524) and this
    one after it is answered, or both at once
```

```bash
cd ~/spdm-lab/work/spdm-emu-pr
git checkout data-transfer-size-flag
git fetch origin && git log --oneline -1 origin/main     # still eff07cf?
git show --stat HEAD && git show HEAD                  # read it once more
git commit --amend -s --no-edit                         # the DCO sign-off: yours
bash /mnt/c/Users/Key20/Desktop/mctp-spdm-pqc/harness/check_upstream_commit.sh .
git push fork data-transfer-size-flag
# then open the pull request with the body in §6
```

## 8. After it is sent

```
- URL:
- Opened:
- Commit:
- Review round trips:
- Outcome:
```

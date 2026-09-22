# Three advisories, checked against their sources — and against this project's own builds

> **This project performs protocol-level correctness validation. It is not a
> security assessment.** Nothing below is a vulnerability report. All three
> advisories are published, and all three are fixed upstream. What is new here
> is the checking: what the identifiers actually resolve to, and whether the
> two trees this repository pins carry the fixes.

<!-- exposure: bench/data/w11-exposure-20260921T190638Z -->

| | |
|---|---|
| pins | [`third_party/dmtf-2026-0001.pin`](../third_party/dmtf-2026-0001.pin), [`dmtf-2026-0002.pin`](../third_party/dmtf-2026-0002.pin), [`dmtf-2026-0003.pin`](../third_party/dmtf-2026-0003.pin) |
| run | [`w11-exposure-20260921T190638Z`](../bench/data/w11-exposure-20260921T190638Z) |
| tools | [`harness/run_exposure.sh`](../harness/run_exposure.sh), [`harness/check_advisories.py`](../harness/check_advisories.py) |
| the classes, as tests | [`negative/`](../negative/), and [`docs/negative-tests.md`](negative-tests.md) §6 |

```bash
python3 harness/check_advisories.py --selftest                    # can it still say yes
python3 harness/check_advisories.py --check docs/advisories.md    # do the verdicts below hold
```

---

## 1. What the identifiers resolve to, which is not what a reader expects

`plan/W11` named four identifiers. Week 10 refused to write any of them into
the source files, because standing rule 7 — *nothing is cited that has not been
checked against the primary source* — applies to a security advisory more than
to anything else: a wrong identifier attached to a real class invites a reader
to look it up and find something unrelated.

Week 11 checked them. **All four are correct.** And checking them found
something worth more than the confirmation.

| | DMTF-2026-0001 | DMTF-2026-0002 | DMTF-2026-0003 |
|---|---|---|---|
| GHSA | `GHSA-j54w-759w-xj3m` | `GHSA-m4wc-xmvg-369f` | `GHSA-chjj-xvqx-c8w4` |
| CVE | **none** | **none** | `CVE-2026-61810` |
| published | 2026-02-10 | 2026-04-03 | 2026-07-03 |
| CWE | CWE-20 | CWE-680 | CWE-325 |
| CVSS 4.0 | **6.9** | **6.9** | **6.0** |
| affected | libspdm 3.0 – 3.8.1 | libspdm 3.4 – 3.8.1 | **DSP0274 1.4.0** |
| patched | 3.8.2, 4.0 | 3.8.2, 4.0 | **DSP0274 1.4.1** |
| retrieval digest | `022cd39169bc1b32be6999ebd480307f19b3a798dfe574c8899ac3462105a770` | `474efd7a6298be2b30fa90b0934e34c7d1527a7d83bbe8be32bd55acc932d986` | `ab3bdffafc22d6c0a20bd2f277d95d34fa5619ac5a2241183e41f9eb772105b4` |

### 1.1 Three things that are true and that a version number does not say

**★ Two of the three have no CVE, and they are the two with the higher score.**
DMTF-2026-0001 says why, in its own words:

> Though a CVE severity score is provided, due to the unlikely chance of
> implementation in a production device, no CVE has been issued.

So a CVE is a judgement about deployment, not a threshold on a number. Anyone
who filters a feed on "has a CVE" drops the two 6.9s and keeps the 6.0.

**★ None of the three is in GitHub's global advisory database.** They are
*repository* advisories on `DMTF/libspdm`. The URL a reader tries first —

```
https://github.com/advisories/GHSA-m4wc-xmvg-369f      404
https://github.com/DMTF/libspdm/security/advisories/GHSA-m4wc-xmvg-369f   200
```

— does not resolve for any of them. libspdm is not in a package ecosystem the
global database ingests, so the advisories never leave the repository.

**★ `CVE-2026-61810` was in neither of the two places a CVE lives.** On the
retrieval date:

| queried | answer |
|---|---|
| `api.github.com/repos/DMTF/libspdm/security-advisories` | the record, HTTP 200 |
| `cveawg.mitre.org/api/cve/CVE-2026-61810` | HTTP 404 |
| `services.nvd.nist.gov/rest/json/cves/2.0?cveId=CVE-2026-61810` | `totalResults: 0` |

GitHub is a CNA and assigned it; MITRE's CVE Services and NVD had not published
it. A reader handed the identifier and told to look it up finds nothing.

**This is the whole argument for rule 7 in one table.** Every one of those
statements would have been wrong if it had been assumed, and each one is the
kind of thing that gets repeated in an interview answer without ever being
checked.

### 1.2 One detail that is not a finding and is worth having

libspdm **3.8.2** was published at `2026-04-03T19:25:51Z`. DMTF-2026-0002 was
published at `19:23:38Z` the same day. **One hundred and thirty-three seconds
apart** — the advisory and its fix went out together, which is what a
coordinated disclosure looks like from the outside.

---

## 2. What the two published fixes actually are

Both are small, and both are small in a way that is worth reading.

### 2.1 DMTF-2026-0002 — one character of parenthesis

```diff
- if ((uint64_t)(offset + length) > spdm_mel_len) {
+ if (((uint64_t)offset + length) > spdm_mel_len) {
```

**The widening cast was already there.** `offset` and `length` are both
`uint32_t`, so in the first version the addition happens in `unsigned int`, it
wraps, and the cast then widens a value that has already lost the carry. In the
second, one operand is widened *first*, so the addition happens in 64 bits and
cannot wrap.

A reviewer scanning for "is there a cast" finds one in both. That is exactly
why [`negative/test_offset_length.c`](../negative/test_offset_length.c) asserts
the behaviour instead of inspecting the text, and why **its defect 1 is this
expression rather than a paraphrase of it.**

★ And the same expression is not equally wrong at every field width.
`GET_CERTIFICATE` carries 16-bit Offset and Length, and `uint16_t` operands are
promoted to `int` before the addition, so the sum is representable and the
naive check refuses correctly. The advisory is against the 32-bit message.
Defects 1 and 2 of that test separate the two, and the separation is asserted
rather than described.

★ **Neither sanitizer would have found it.** Unsigned overflow is *defined*
behaviour in C, so UndefinedBehaviorSanitizer is silent by design;
AddressSanitizer only speaks when the bad index is dereferenced, which here
happens inside a copy that the caller believes is bounded.

### 2.2 DMTF-2026-0001 — the check was there, and it ran after the write

The defective code copied the attribute name, then `=`, then the value, then
`,`, decrementing a signed counter as it went, and then asked:

```c
if (buff_len < 0) { ... return false; }
```

By the time that is false the bytes are in the buffer. The published fix
deletes it and puts a check in *front* of the copy that accounts for everything
the copy will write — the name, the `=`, the value, the `,` and the terminator:

```c
if (buff_len < (int32_t)(cur->name_len + 1 + obj_len + 1 + 1))
```

★ **The refusal the old code returned was the right refusal.** A test that
compared status codes would have seen nothing. That is why
[`negative/test_oversized_field.c`](../negative/test_oversized_field.c) grew a
status code of its own — `NEG_ERR_FIELD_WRITE_ESCAPED_BUFFER` — and why every
destination in it sits in front of a guard region the test reads by hand. The
code was added *after* reading this patch; the week-10 specification could not
express the outcome, which is the most useful thing reading a real fix produced.

### 2.3 DMTF-2026-0003 — a defect in a document

Its own section: [`docs/transcript.md`](transcript.md).

---

## 3. ★ Is *this* project affected

Two build flavors, three advisories, six answers. Nothing below is inferred
from a version string.

<!--verdict stable/DMTF-2026-0002=AFFECTED-->
<!--verdict stable/DMTF-2026-0001=PRESENT-NOT-REACHABLE-->
<!--verdict stable/DMTF-2026-0003=NOT-APPLICABLE-->
<!--verdict pqc/DMTF-2026-0002=NOT-AFFECTED-->
<!--verdict pqc/DMTF-2026-0001=NOT-AFFECTED-->
<!--verdict pqc/DMTF-2026-0003=NOT-APPLICABLE-->

| | `stable` — libspdm 3.8.0 | `pqc` — libspdm 4.0.0-rc |
|---|---|---|
| **DMTF-2026-0001** | **PRESENT-NOT-REACHABLE** | NOT-AFFECTED |
| **DMTF-2026-0002** | **AFFECTED** | NOT-AFFECTED |
| **DMTF-2026-0003** | NOT-APPLICABLE | NOT-APPLICABLE |

### 3.1 How each verdict was reached, and why five ways instead of one

A version in the affected range is the *first* of five observations, and the
other four routinely disagree with it.

| # | question | answered by |
|:--|---|---|
| 1 | is the pinned version inside the affected range | the advisory |
| 2 | is the fix **commit** an ancestor of the pinned commit | GitHub's `compare` API |
| 3 | is the fixed **line** in the source on disk | `grep`, on the file the compiler read |
| 4 | is the vulnerable code **linked** | the `.a` the emulator build produced |
| 5 | do the advisory's own preconditions hold | capability bits off the captures, and what an assert compiles to |

**2 and 3 are deliberately redundant.** Standing rule 12: where two routes
reach the same quantity they are made to agree. `check_advisories.py` prints
`DISAGREEMENT` and exits non-zero rather than choosing, because one route that
is wrong looks exactly like one that is right. On this evidence both routes
agree in all four cases where both apply.

### 3.2 `stable` / DMTF-2026-0002 — **AFFECTED**, and all five preconditions say so

| | |
|---|---|
| version | 3.8.0, inside `3.4 – 3.8.1` |
| ancestry | the 3.8.2 fix is `behind` by 14 commits and the 4.0 fix by 348 — neither is an ancestor |
| the line | `if ((uint64_t)(offset + length) > spdm_mel_len)` is present verbatim, `libspdm_rsp_measurement_extension_log.c:128` |
| `MEL_CAP` | advertised in **98 of 98** committed captures |
| `CHUNK_CAP` | advertised in **96 of 98** — the two that do not are the `nochunk` arms, which clear it on purpose |
| `libspdm_copy_mem()` | **does not stop the copy** |

The last row is the one worth reading twice. `libspdm_copy_mem()` does check:

```c
if (src_len > dst_len) {
    LIBSPDM_ASSERT(0);
}
while (src_len-- != 0) {
    *(dst++) = *(src++);
}
```

★ **The check is spelled `LIBSPDM_ASSERT`, and the copy happens anyway.**
This project builds `TARGET=Release`, which reaches `CMakeLists.txt:886`:

```cmake
add_compile_options(-DLIBSPDM_DEBUG_ENABLE=0)
```

and `debuglib.h` then defines `LIBSPDM_ASSERT(expression)` as **nothing at
all**. So the bound is in the source, absent from the binary, and the loop below
it runs either way. That is the advisory's third precondition, and it is met not
by a mistake but by a build type.

**What it does not mean.** No measurement in this repository is affected. The
defect is reached through `GET_MEASUREMENT_EXTENSION_LOG`, and **no committed
capture contains that request** — `check_advisories.py` re-derives that from the
decodes rather than taking anyone's word for it. The twenty-two message codes
that do appear are in `docs/handshake-walkthrough.md`. The honest summary is:
*a responder in this lab would answer that request unsafely, and nothing here
has ever asked it.*

### 3.3 `stable` / DMTF-2026-0001 — **PRESENT-NOT-REACHABLE**

Version in range, fix absent by both routes, `CSR_CAP` advertised in 98 of 98
captures — and the defect is in `os_stub/cryptlib_mbedtls/pk/x509.c`, while the
emulator links `libcryptlib_openssl.a`.

★ **Present in the tree and present in the binary are different facts**, and
only the second one can be attacked. All three back ends — `cryptlib_mbedtls`,
`cryptlib_null`, `cryptlib_openssl` — are checked out in both flavors; exactly
one is linked.

★ And the more useful version of that sentence: **the same protocol library has
a different attack surface under a different crypto back end.** Post-quantum
support exists only under OpenSSL. So "should this device move to ML-DSA" is not
only an algorithm question — it is a question about which back end, and
therefore which set of defects, the device inherits. `docs/pqc-cost.md` measures
the bytes; this is the part of the cost that is not bytes.

### 3.4 `pqc` — **NOT-AFFECTED** for both

The 4.0 fix commits are ancestors (`ahead by 94` and `ahead by 151`), and the
repaired lines are in the tree: `((uint64_t)offset + length)` at
`libspdm_rsp_measurement_extension_log.c:132`, and the
`/*check total space needed...*/` block at `x509.c:1804`.

The 3.8.2 fix commits report `diverged` against this head, which is correct and
is why the tool takes *either* patch being an ancestor as sufficient: 4.0.0-rc
is not a descendant of the 3.8 branch, and demanding that it be one would report
a patched tree as unpatched.

### 3.5 DMTF-2026-0003 — **NOT-APPLICABLE**, and why that is not a dodge

The affected product is a specification. Any implementation that follows
DSP0274 1.4.0 exactly has the defect, so "is my library patched" is not the
question. The question is whether this project computes a FINISH transcript at
all, and it does not: **nothing here has ever established a secure session**,
which `docs/threat-scope.md` level 2 has said since 2026-09-20.

So the class is modelled rather than run —
[`negative/test_transcript_coverage.c`](../negative/test_transcript_coverage.c)
— and [`docs/transcript.md`](transcript.md) reads both versions of the
specification instead.

---

## 4. What this section is not

- **Not an audit of libspdm.** Six verdicts about two checkouts on one laptop.
  libspdm is on OSS-Fuzz, ships about sixty-nine AFL targets and runs CodeQL and
  Coverity; nothing here improves on that.
- **Not a vulnerability report.** Every advisory here is published and fixed.
  The one AFFECTED verdict is about a deliberately-pinned old version in a lab,
  and the fix for it is `git checkout 3.8.2`.
- **Not a claim that the `pqc` flavor is safe.** It is a claim that two specific
  published fixes are in it, reached two ways.
- **Not automatic.** `--refresh` re-fetches the advisories and reports drift
  against the pins, and it runs in the weekly `upstream` job rather than in
  `verify`, because a pull request should not go red because somebody else
  edited a web page.

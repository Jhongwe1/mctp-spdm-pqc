#!/usr/bin/env bash
#
# harness/verify_repo.sh — everything CI checks, runnable locally.
#
#     bash harness/verify_repo.sh
#
# Run this before committing. It is the same set of checks as
# .github/workflows/ci.yml, so a green run here means a green run there, and
# finding out locally costs seconds rather than a push and a wait.
#
# It touches nothing outside the repository and builds no upstream code.

set -uo pipefail
_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${_HERE}/lib/common.sh"
set +e

FAILED=0
step() { printf '\n\033[34m--- %s\033[0m\n' "$*"; }
good() { printf '  \033[32mok\033[0m   %s\n' "$*"; }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$*"; FAILED=1; }

cd "$REPO_ROOT" || exit 1

step "shellcheck"
if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck -x -S warning harness/*.sh certs/*.sh; then
        good "no warnings or errors"
    else
        bad "shellcheck reported problems"
    fi
else
    printf '  --   shellcheck not installed (apt: shellcheck) — skipped\n'
fi

step "python syntax"
if python3 -m py_compile harness/pcapcount.py harness/lib/_manifest.py certs/check_chain.py; then
    good "harness python compiles"
else
    bad "python syntax error"
fi

step "no private key material is tracked"
# .gitignore excludes *.key, and for one commit's worth of time it also did not
# exclude end_responder.key.pem, because that pattern matches the END of a name
# and gen_chain.sh had written a second spelling. The rule looked like it
# covered the case and did not.
#
# So the guarantee is not a pattern any more. This reads every file git is
# actually tracking and refuses a PEM private-key header in any of them. A
# pattern describes what someone expected to write; this describes what is
# there. Costs about a second.
python3 - <<'PY'
import pathlib, subprocess, sys

# Assembled rather than written out, and the first version of this check was not
# — so it found a private-key header in the only file that had one: itself. A
# checker that spells out what it forbids becomes an instance of it. Built from
# pieces, the header never appears as a byte sequence in any tracked file, and
# the check's answer about this file is the true one.
RULE = b"-" * 5
def marker(kind: bytes) -> bytes:
    return RULE + b"BEGIN " + kind + b"PRIVATE KEY" + RULE

MARKERS = tuple(marker(k) for k in
                (b"", b"RSA ", b"EC ", b"DSA ", b"OPENSSH ", b"ENCRYPTED "))
MARKERS += (RULE + b"BEGIN PGP " + b"PRIVATE KEY BLOCK" + RULE,)

tracked = subprocess.run(["git", "ls-files", "-z"], capture_output=True, check=False)
names = [n for n in tracked.stdout.split(b"\0") if n]
found, scanned = [], 0
for raw in names:
    path = pathlib.Path(raw.decode("utf-8", "surrogateescape"))
    if not path.is_file():
        continue
    try:
        blob = path.read_bytes()
    except OSError:
        continue
    scanned += 1
    for marker in MARKERS:
        if marker in blob:
            found.append(f"{path}  contains {marker.decode()}")
            break

for line in found:
    print("  " + line)
print(f"  {scanned} tracked file(s) scanned")
sys.exit(1 if found else 0)
PY
[ $? -eq 0 ] && good "no tracked file carries a private-key header" \
             || bad "a private key is committed — remove it and rotate it"

step "the certificate chain is well formed, and the checker can still reject"
# certs/gen_chain.sh builds this project's own three-layer chain, and
# certs/check_chain.py reads it out of DER rather than out of a pretty-printer.
# Both halves run here: the committed chain has to pass, and the checker has to
# be observed rejecting four different breaks through four different checks —
# because a suite where two breaks are caught by the same check is claiming
# more coverage than it has, and this one was, until the order of two checks
# was swapped.
if [ -f certs/out/bundle_responder.certchain.der ]; then
    if python3 certs/check_chain.py certs/out >/dev/null 2>&1; then
        good "the committed chain links to its root and carries both identity OIDs"
    else
        python3 certs/check_chain.py certs/out 2>&1 | sed 's/^/  /' | tail -20
        bad "certs/out does not pass its own checker"
    fi
    if python3 certs/check_chain.py certs/out --self-test 2>&1 | sed 's/^/  /'; then
        good "four breaks, four distinct checks, every one rejected"
    else
        bad "the chain checker accepted something it should have refused"
    fi
else
    printf '  --   certs/out holds no chain — skipped (bash certs/gen_chain.sh)\n'
fi

step "pcapcount self-test"
python3 - <<'PY'
import json, pathlib, struct, subprocess, sys, tempfile
hdr = struct.pack('<IHHiIII', 0xa1b2c3d4, 2, 4, 0, 0, 65535, 1)
rec = lambda n: struct.pack('<IIII', 1700000000, 0, n, n) + b'\xaa' * n
p = pathlib.Path(tempfile.mkdtemp()) / 'two.pcap'
p.write_bytes(hdr + rec(4) + rec(6))
out = subprocess.run([sys.executable, 'harness/pcapcount.py', str(p), '--json'],
                     capture_output=True, text=True)
if out.returncode != 0:
    print('  pcapcount failed:', out.stderr.strip()); sys.exit(1)
s = json.loads(out.stdout)['summary']
for key, want in (('packets', 2), ('captured_bytes_total', 10), ('linktype', 1)):
    if s[key] != want:
        print(f'  {key}: got {s[key]}, want {want}'); sys.exit(1)
if s['byte_order'] != 'little-endian' or s['truncated']:
    print('  header parsed wrong:', s); sys.exit(1)
print('  parsed 2 packets / 10 bytes from a hand-built capture')
PY
[ $? -eq 0 ] && good "parser agrees with a capture built byte by byte" \
             || bad "pcapcount self-test failed"

step "c-drills compile and run"
if make -C c-drills --no-print-directory >/dev/null 2>&1; then
    good "every drill compiles under -Werror + ASan + UBSan"
    if make -C c-drills --no-print-directory test 2>&1 | tail -3 | sed 's/^/  /'; then
        good "drills marked complete in DONE.txt pass"
    else
        bad "a completed drill failed"
    fi
else
    make -C c-drills --no-print-directory 2>&1 | tail -20 | sed 's/^/  /'
    bad "a drill does not compile"
fi

step "python syntax (analysis tools)"
if python3 -m py_compile harness/fields.py bench/pcapstat.py device/gen_measurements.py; then
    good "fields.py, pcapstat.py and gen_measurements.py compile"
else
    bad "an analysis tool has a syntax error"
fi

step "the measurement source module compiles, rejects, and agrees with its writer"
# device/measurement_source.c is compiled twice: here on its own under two
# sanitizers, and inside libspdm's sample secret library where nothing can run
# it. Only the first of those fits in CI, which is why the module takes no
# libspdm dependency at all.
#
# `test` runs 66 checks, of which the ones that matter feed the loader eleven
# malformed fixtures and require ELEVEN DIFFERENT reason codes — standing rule
# 13 — and then require every value of ms_status_t to have been observed, so an
# error code nothing provokes is a failing build.
#
# `interop` byte-compares what the C builder writes with what
# device/gen_measurements.py writes for the same defaults. The format has two
# implementations and standing rule 12 says two routes to one quantity are made
# to agree; without this the drift would surface as a responder quietly serving
# upstream's synthetic values during a tamper run.
if make -C device --no-print-directory test 2>&1 | tail -2 | sed 's/^/  /'; then
    good "the loader's self-test passes under -Werror + ASan + UBSan"
else
    make -C device --no-print-directory test 2>&1 | tail -25 | sed 's/^/  /'
    bad "the measurement source self-test failed"
fi
if make -C device --no-print-directory interop 2>&1 | head -2 | sed 's/^/  /'; then
    good "the C reader and the Python writer produce identical bytes"
else
    bad "gen_measurements.py and the C builder disagree about the file format"
fi
make -C device --no-print-directory clean >/dev/null 2>&1 || true

step "the measurement record walk can still fail"
# fields.py now reports what is INSIDE a measurement record, not just its
# length, because "the record is still 528 bytes" is exactly what a successful
# tamper looks like. The walk is over-determined three ways — the block count
# must equal NumberOfBlocks, the walk must consume MeasurementRecordLength
# exactly, and each block's MeasurementSize must equal 3 plus its own DMTF
# value size — so a correct record is built here and then broken once per
# equation, and each break must be REPORTED rather than turned into eight
# plausible blocks.
python3 - <<'PY'
import json, pathlib, subprocess, sys, tempfile

# ALGORITHMS has to be here even though nothing below is signed: reconstruct()
# refuses to place a MEASUREMENTS message for a connection whose signature
# algorithm it cannot name, and refusing is the right behaviour — an offset
# derived from an unknown signature size is a guess. Leaving it out made this
# test report "a correct record did not close", which was true and was about
# the fixture rather than the code.
ALGS = ("1 (1) MCTP(5) RSP->REQ SPDM(14, 0x63) SPDM_ALGORITHMS "
        "(Hash=0x00000002(SHA_384), MeasHash=0x00000008(SHA_512), "
        "Asym=0x00000080(ECDSA_P384), ReqAsym=0x0008(RSAPSS_3072)) ")
GM = ("2 (1) MCTP(5) REQ->RSP SPDM(14, 0xe0) SPDM_GET_MEASUREMENTS "
      "(Attr=0x00(), MeasOp=0xff(All), SlotID=0x00) ")
MS = ("3 (1) MCTP(5) RSP->REQ SPDM(14, 0x60) SPDM_MEASUREMENTS "
      "(NumOfBlocks=0x02, MeasRecordLen=0x00000000, ContentChange=0x20(NoChange), "
      "SlotID=0x00) ")


def block(raw):
    return "\n".join(f"    {i:04x}: " + " ".join(f"{b:02x}" for b in raw[i:i + 32])
                     for i in range(0, len(raw), 32))


def mblock(index, vtype, value, size=None, vsize=None):
    size = 3 + len(value) if size is None else size
    vsize = len(value) if vsize is None else vsize
    return (bytes([index, 0x01, size & 0xFF, size >> 8, vtype,
                   vsize & 0xFF, vsize >> 8]) + value)


def message(nblocks, record):
    body = bytes([0x14, 0x60, 0x00, 0x20, nblocks,
                  len(record) & 0xFF, (len(record) >> 8) & 0xFF,
                  (len(record) >> 16) & 0xFF]) + record
    return body + bytes(32) + b"\x00\x00"        # nonce, OpaqueLength = 0


def walk(nblocks, record):
    d = pathlib.Path(tempfile.mkdtemp())
    algs = bytes([0x14, 0x63]) + bytes(34)
    req = bytes([0x14, 0xE0, 0x00, 0xFF])
    rsp = message(nblocks, record)
    (d / "t.decode.txt").write_text(
        "spdm_dump version 0.1\n"
        "PcapFile: Magic - 'a1b2c3d4', version2.4, DataLink - 291 (MCTP),"
        " MaxPacketSize - 65536\n" + ALGS + "\n" + GM + "\n" + MS + "\n",
        encoding="utf-8")
    (d / "t.hex.txt").write_text(
        ALGS + "\n  SPDM Message:\n" + block(algs) + "\n"
        + GM + "\n  SPDM Message:\n" + block(req) + "\n"
        + MS + "\n  SPDM Message:\n" + block(rsp) + "\n", encoding="utf-8")
    out = subprocess.run([sys.executable, "harness/fields.py",
                          str(d / "t.decode.txt"), "--json"],
                         capture_output=True, text=True)
    if out.returncode != 0:
        print("  fields.py failed:", out.stderr.strip())
        return None
    return json.loads(out.stdout)["layout"]["measurement_record"]


good_record = (mblock(0x01, 0x00, bytes(range(8)))
               + mblock(0x10, 0x87, (7).to_bytes(8, "little")))

rec = walk(2, good_record)
if rec is None or not rec["closes"]:
    print("  a correct record did not close:", rec and rec["why"])
    sys.exit(1)
if rec["blocks"]["0x10"]["value_uint64"] != 7 or rec["blocks_walked"] != 2:
    print("  the intact walk disagrees with what was built:", rec)
    sys.exit(1)
print(f"  intact: closes — {rec['blocks_walked']} blocks, svn "
      f"{rec['secure_version_number']}, {rec['record_bytes']} bytes")

seen = {}
for name, nblocks, record in (
    ("NumberOfBlocks disagrees", 3, good_record),
    # MeasurementSize 11 FITS in the record — it is the same size the first
    # block legitimately has — but says 3 + 4 rather than 3 + 8. If this case
    # is written with a size that overflows the record instead, the length
    # check catches it first and the equation being tested here never runs.
    # That is what the first version of this test did, and the distinctness
    # check below did not notice because the two sentences differed by a digit.
    ("MeasurementSize disagrees with the value size", 2,
     mblock(0x01, 0x00, bytes(8), vsize=4) + mblock(0x10, 0x87, bytes(8))),
    ("a block runs past the record", 2,
     mblock(0x01, 0x00, bytes(8), size=900) + mblock(0x10, 0x87, bytes(8))),
    ("a block header is cut short", 2, good_record + b"\x01\x01"),
):
    rec = walk(nblocks, record)
    if rec is None:
        sys.exit(1)
    if rec["closes"]:
        print(f"  ACCEPTED A BROKEN RECORD: {name}")
        sys.exit(1)
    key = rec["why_kind"]
    if key is None:
        print(f"  {name}: refused without saying which check refused it")
        sys.exit(1)
    if key in seen:
        print(f"  BOTH '{seen[key]}' and '{name}' are caught by '{key}';")
        print("  one of the equations between them has never rejected anything")
        sys.exit(1)
    seen[key] = name
    print(f"  {name}: rejected by {key} — {rec['why']}")
print(f"  4 breaks, {len(seen)} distinct checks — none redundant")
PY
[ $? -eq 0 ] && good "the record walk closes on a correct record and on nothing else" \
             || bad "the measurement record walk accepted something it should have rejected"

step "every experiment run is attributed"
missing=0
shopt -s nullglob
for d in bench/data/*/; do
    case "$d" in bench/data/_scratch/*) continue ;; esac
    [ -f "${d}manifest.json" ] || { printf '  UNATTRIBUTED: %s\n' "$d"; missing=1; }
done
if [ "$missing" -eq 0 ]; then
    good "$(find bench/data -maxdepth 2 -name manifest.json 2>/dev/null | wc -l) run(s), all carrying provenance"
else
    bad "a run directory has no manifest.json (see docs/decisions/0003)"
fi

step "every artifact still hashes to what its manifest signed for"
# A manifest lists each artifact with its SHA-256. Three things can break that
# promise, and only the first one is obvious:
#
#   the file is gone;
#   the file is present but not tracked, so a fresh clone never receives it —
#     which is worse than absence, because the mechanism reports success. This
#     is not hypothetical: .gitignore's `*.log` quietly excluded twelve evidence
#     files that three manifests had already signed for;
#   the file is present, tracked, and no longer the file that was hashed.
#
# The third is why the digest is recomputed rather than the path merely checked.
# "Do not edit anything under bench/data" is a rule a person can forget by week
# six; a digest cannot. Line endings are pinned to LF in .gitattributes for
# every text file precisely so this comparison means the same thing on every
# platform.
python3 - <<'PY'
import hashlib, json, pathlib, subprocess, sys

tracked = set(subprocess.run(
    ["git", "ls-files", "bench/data"], capture_output=True, text=True, check=False
).stdout.split())

problems, checked = [], 0
manifests = sorted(pathlib.Path("bench/data").glob("*/manifest.json"))
for man in manifests:
    data = json.loads(man.read_text(encoding="utf-8"))
    for art in data.get("artifacts", []):
        rel = f"{man.parent.as_posix()}/{art['path']}"
        path = pathlib.Path(rel)
        if not path.exists():
            problems.append(f"MISSING   {rel}")
            continue
        if rel not in tracked:
            problems.append(f"UNTRACKED {rel}  (attested with a sha256 but not committed)")
            continue
        checked += 1
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if digest != art["sha256"]:
            problems.append(f"ALTERED   {rel}")
            problems.append(f"          manifest: {art['sha256']}")
            problems.append(f"          on disk : {digest}")
        elif path.stat().st_size != art["bytes"]:
            problems.append(f"SIZE      {rel}: manifest {art['bytes']}, on disk {path.stat().st_size}")

for p in problems:
    print("  " + p)
print(f"  {checked} artifact(s) across {len(manifests)} manifest(s) re-hashed")
sys.exit(1 if problems else 0)
PY
[ $? -eq 0 ] && good "every attested artifact is present, tracked, and unaltered" \
             || bad "an artifact no longer matches the manifest that attests to it"

step "scope statement precedes the build badge"
# Two checks. The first reads README.md with all whitespace collapsed, so the
# sentence is found whether or not Markdown wrapped it across source lines —
# the first version of this check searched for the sentence on one line and
# reported a false failure the moment the paragraph was reflowed.
# The second uses a short single-line anchor to compare positions.
if tr '\n' ' ' < README.md | tr -s ' ' \
     | grep -q 'protocol-level correctness validation.\{0,10\}It is not a security assessment'; then
    good "scope sentence present"
else
    bad "README.md does not state the scope in the expected words"
fi
scope=$(grep -n 'security assessment' README.md | head -1 | cut -d: -f1)
badge=$(grep -n 'actions/workflows/ci.yml/badge.svg' README.md | head -1 | cut -d: -f1)
if [ -z "$scope" ]; then
    bad "no scope anchor found in README.md"
elif [ -n "$badge" ] && [ "$scope" -gt "$badge" ]; then
    bad "scope statement (line $scope) comes after the badge (line $badge)"
else
    good "scope at line $scope, badge at line ${badge:-none}"
fi

step "every document quoting a specification quotes the pinned one"
# A pin carrying `sha256=` and `quoted-in=` names a document that is NOT
# vendored — the DMTF specifications this week cites live outside the repo,
# because they are not ours to redistribute. What is inside the repo is the
# digest of the exact file that was read, and the documents that cite it.
#
# Those two can drift apart in the direction that matters: someone re-downloads
# a specification, updates the pin, and six documents keep quoting the old
# digest. CLAUDE.md asks a person to grep for the old version number after
# moving a pin, because that has already happened once on 2026-08-16. This is
# the same instruction with the remembering taken out.
python3 - <<'PY'
import pathlib, sys

problems, checked = [], 0
pins = sorted(pathlib.Path("third_party").glob("*.pin"))
for pin in pins:
    fields = {}
    for line in pin.read_text(encoding="utf-8").splitlines():
        if line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        fields[k.strip()] = v.strip()
    digest, quoted = fields.get("sha256"), fields.get("quoted-in")
    if not digest or not quoted:
        continue
    for rel in (q.strip() for q in quoted.split(",") if q.strip()):
        target = pathlib.Path(rel)
        if not target.exists():
            problems.append(f"{pin.name}: quoted-in names {rel}, which does not exist")
            continue
        if digest not in target.read_text(encoding="utf-8", errors="replace"):
            problems.append(f"{rel} does not carry the sha256 in {pin.name}")
            problems.append(f"          pin says {digest}")
            continue
        checked += 1
        print(f"  {rel} quotes {pin.name} at {digest[:16]}…")

if checked == 0:
    print("  no pin declares a quoted-in= file")
for line in problems:
    print("  " + line)
sys.exit(1 if problems else 0)
PY
[ $? -eq 0 ] && good "no document quotes a specification digest the pin disagrees with" \
             || bad "a pinned specification and a document that cites it have drifted apart"

step "the capability-bit names were checked against the pinned libspdm"
# fields.py names capability bits from a table transcribed by hand out of
# libspdm's spdm.h, and section 10 of the walkthrough names what that leaves
# open: --check cannot notice a bit upstream renamed, because a wrong name stays
# consistent with itself and no capture disagrees with it.
#
# `fields.py --verify-tables <spdm.h>` compares the two directly, but it needs
# the upstream source and CI has none. So the comparison is pinned. This step
# checks the pin: the header must have been read at the same libspdm commit the
# captures came from, and the tables must still have the number of entries that
# comparison found. Move the emulator pin without re-reading the header, or add
# a bit by hand, and the build goes red asking for the check to be re-run.
python3 - <<'PY'
import pathlib, sys


def pinned(path):
    out = {}
    for line in pathlib.Path(path).read_text(encoding="utf-8").splitlines():
        if line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        out[key.strip()] = value.strip()
    return out


header_pin = pathlib.Path("third_party/spdm-h.pin")
if not header_pin.exists():
    print("  third_party/spdm-h.pin is missing")
    print("  run: python3 harness/fields.py --verify-tables <spdm.h> --write-pin")
    sys.exit(1)

hp, ep = pinned(header_pin), pinned("third_party/spdm-emu-pqc.pin")
if hp.get("libspdm") != ep.get("libspdm"):
    print(f"  the bit names were checked against libspdm {hp.get('libspdm', '?')[:7]}")
    print(f"  the captures were produced by libspdm     {ep.get('libspdm', '?')[:7]}")
    print("  re-run: python3 harness/fields.py --verify-tables <spdm.h> --write-pin")
    sys.exit(1)

sys.path.insert(0, "harness")
import fields as F                                          # noqa: E402

local = sum(1 for side, _bit in F.LOCAL_BIT_NAMES if side == "requester")
want_req, want_rsp = int(hp["requester-bits"]) + local, int(hp["responder-bits"])
if (len(F.REQ_FLAGS), len(F.RSP_FLAGS)) != (want_req, want_rsp):
    print(f"  the tables hold {len(F.REQ_FLAGS)} requester and {len(F.RSP_FLAGS)} "
          f"responder bits; the pin was written against {want_req} and {want_rsp}")
    print("  a bit was added or removed without re-reading the header")
    sys.exit(1)

print(f"  libspdm {hp['libspdm'][:7]}, spdm.h {hp['sha256'][:16]}…, "
      f"read {hp['verified-at']}")
print(f"  {want_req} requester and {want_rsp} responder capability bits")
PY
[ $? -eq 0 ] && good "the bit names come from the same libspdm as the captures" \
             || bad "the capability tables and the pinned libspdm have drifted apart"

step "two tools agree on how many bytes went down the wire"
# pcapcount.py owns the capture file and fields.py never opens one. That
# separation is what lets them check each other, because neither can be wrong in
# a way the other would repeat.
#
# Every record in these captures carries five bytes of transport framing ahead
# of the SPDM message — the four-byte mctp_header_t plus the MCTP message-type
# byte, taken apart in docs/transports.md — and nothing is ever fragmented. So
# for an MCTP capture whose decode is complete:
#
#     pcap captured bytes  ==  SPDM message bytes  +  5 x messages
#
# This is added after the double count it would have caught, not before, and it
# is worth saying which: it finds nothing today. It is here so that the next
# disagreement between these two tools is found by the build rather than by
# someone noticing a number looks large.
python3 - <<'PY'
import json, pathlib, subprocess, sys

FRAMING = 5
checked, skipped, problems = [], [], []


def tool(script, *args):
    out = subprocess.run([sys.executable, script, *args], capture_output=True, text=True)
    if out.returncode != 0:
        raise SystemExit(f"  {script} failed on {args[0]}: {out.stderr.strip()}")
    return json.loads(out.stdout)


for decode in sorted(pathlib.Path("bench/data").glob("*/*.decode.txt")):
    name = f"{decode.parent.name}/{decode.name}"
    hexfile = decode.with_name(decode.name.replace(".decode.txt", ".hex.txt"))
    pcap = decode.with_name(decode.name.replace(".decode.txt", ".pcap"))
    if not hexfile.exists() or not pcap.exists():
        skipped.append(f"{name}: no hex dump or no capture beside it")
        continue
    f = tool("harness/fields.py", str(decode), "--json")
    if f["source"]["decode_truncated"]:
        skipped.append(f"{name}: {f['source']['truncation_reason']}")
        continue
    if f["transport"]["link_type"] != "MCTP":
        skipped.append(f"{name}: link type is {f['transport']['link_type']}")
        continue
    p = tool("harness/pcapcount.py", str(pcap), "--json")["summary"]
    if f["messages"]["decoded"] != p["packets"]:
        problems.append(f"{name}: {p['packets']} packets but {f['messages']['decoded']} decoded")
        continue
    want = f["message_bytes"]["total"] + FRAMING * p["packets"]
    if p["captured_bytes_total"] != want:
        problems.append(f"{name}: capture holds {p['captured_bytes_total']} bytes, "
                        f"{f['message_bytes']['total']} + {FRAMING} x {p['packets']} = {want}")
        continue
    checked.append(f"{name}: {p['captured_bytes_total']} = "
                   f"{f['message_bytes']['total']} + {FRAMING} x {p['packets']}")

for line in checked:
    print("  " + line)
for line in skipped:
    print(f"  --   skipped {line}")
for line in problems:
    print("  " + line)
if not checked:
    print("  no capture could be cross-checked")
    sys.exit(1)
sys.exit(1 if problems else 0)
PY
[ $? -eq 0 ] && good "the pcap layer and the SPDM layer account for the same bytes" \
             || bad "pcapcount.py and fields.py disagree about a capture"

step "a second parser reaches the same per-message byte counts"
# The step above compares one total against another total, which is one
# equation over a whole capture: a message counted 200 bytes too large and
# another 200 too small would satisfy it.
#
# bench/pcapstat.py closes that gap. It walks the capture file itself, strips
# the five bytes of MCTP framing, reads the RequestResponseCode out of each
# SPDM header and totals per message type — never opening a decode.
# fields.py reaches the same per-type totals from spdm_dump's hex output and
# never opens a capture. Requiring agreement PER TYPE is eighteen equations on
# the walkthrough capture instead of one.
#
# A truncated decode is reported rather than failed: spdm_dump stops partway
# through the post-quantum arm, so the two tools are genuinely not looking at
# the same thing there, and pcapstat prints how much of the capture the decoder
# does not see instead of demanding that a prefix equal a whole.
fails=0
total=0
shopt -s nullglob
for pcap in bench/data/*/*.pcap; do
    total=$((total + 1))
    if ! out="$(python3 bench/pcapstat.py "$pcap" --check 2>&1)"; then
        printf '%s\n' "$out" | grep -E '^\s+FAIL' | sed 's/^/  /'
        printf '  in %s\n' "$pcap"
        fails=$((fails + 1))
    fi
done
if [ "$total" -eq 0 ]; then
    bad "no capture to cross-check"
elif [ "$fails" -eq 0 ]; then
    good "$total capture(s): pcapstat.py and fields.py agree message type by message type"
else
    bad "$fails capture(s) where the two parsers disagree"
fi

step "the stock measurement record is the same in every baseline ever taken"
# docs/tamper.md's whole argument rests on one digest: the 528-byte measurement
# record a responder produces when nothing has been done to it. Two claims lean
# on it — "the added lines change nothing when no fixture is named", and "a
# fixture holding upstream's own values reproduces upstream's own record" — and
# both are comparisons against a number that would be worthless if it drifted.
#
# It has not drifted. The record holds no nonce and no timestamp, so it is a
# run-invariant, and this asserts that over every baseline run in the
# repository plus the two tamper arms that must equal them. Four runs, four
# dates, both certificate chains, and a binary built before the patch existed
# alongside one built after it.
#
# Derived from the DECODES rather than from the committed fields.json, so it
# keeps working on runs whose derivations predate a change to fields.py — which
# is precisely the situation this repository was in on 2026-09-01.
python3 - <<'PY'
import json, pathlib, subprocess, sys

seen = {}
for decode in sorted(pathlib.Path("bench/data").glob("*/*.decode.txt")):
    run = decode.parent.name
    arm = decode.name.replace(".decode.txt", "")
    stock = ("baseline" in run) or (arm in ("t0_none", "t0_clean"))
    if not stock:
        continue
    if not decode.with_name(arm + ".hex.txt").exists():
        continue
    out = subprocess.run([sys.executable, "harness/fields.py", str(decode), "--json"],
                         capture_output=True, text=True)
    if out.returncode != 0:
        continue
    got = json.loads(out.stdout)
    if got["source"]["decode_truncated"]:
        continue
    rec = (got.get("layout") or {}).get("measurement_record")
    if not rec or rec["blocks_walked"] != 8:
        continue
    if not rec["closes"]:
        print(f"  {run}/{arm}: the record does not close — {rec['why']}")
        sys.exit(1)
    seen.setdefault(rec["sha256"], []).append(f"{run}/{arm}")

if not seen:
    print("  no eight-block measurement record found in any baseline")
    sys.exit(1)
for digest, where in sorted(seen.items(), key=lambda kv: -len(kv[1])):
    print(f"  {digest[:16]}…  {len(where)} arm(s)")
    for w in where:
        print(f"      {w}")
if len(seen) != 1:
    print("  the stock measurement record is NOT the same everywhere")
    sys.exit(1)
runs = {w.split("/")[0] for w in next(iter(seen.values()))}
print(f"  one digest across {len(runs)} run(s)")
PY
[ $? -eq 0 ] && good "every untampered capture carries the same measurement record" \
             || bad "the stock measurement record differs between runs"

step "every fields.json a document cites is still reproducible"
# harness/capture.sh writes a *.fields.json beside each capture, and
# prov_finish hashes it into manifest.json alongside the pcap. But a pcap is
# evidence and a fields.json is a DERIVATION, and a derivation committed beside
# its inputs can disagree with the tool that produced it. It did: after the
# double count was fixed on 2026-08-28, the committed JSON still said 15,803
# where fields.py had begun saying 11,291, and the manifest attested to the
# stale one. Nothing noticed, because the manifest checks that a file has not
# been altered, which is a different question from whether it is still true.
#
# So a derivation has to be reproducible from its inputs, and this checks it.
# `source.decode_file` is excluded because it records the absolute path the
# capture ran from, which is a property of the machine and not of the result.
#
# Scope, deliberately: the run directories that a document actually cites,
# found by reading their <!-- capture: --> directives rather than from a list
# that would go stale exactly the way this did. Runs no document cites keep the
# guarantee their manifest gives them — that they are unaltered — which is all
# this repository has ever claimed about them.
python3 - <<'PY'
import json, pathlib, re, subprocess, sys

CAPTURE_RE = re.compile(r"<!--\s*capture:\s*(?P<path>\S+)\s*-->")

cited = set()
for doc in sorted(pathlib.Path("docs").rglob("*.md")):
    fenced = False
    for line in doc.read_text(encoding="utf-8").splitlines():
        if line.lstrip().startswith("```"):
            fenced = not fenced
            continue
        if fenced:
            continue
        found = CAPTURE_RE.search(line)
        if found:
            path = pathlib.Path(found.group("path"))
            if path.parts[:2] == ("bench", "data") and path.parent.is_dir():
                cited.add(path.parent)

if not cited:
    print("  no document cites a run directory — nothing to check")
    sys.exit(0)

problems, checked = [], 0
for run in sorted(cited):
    for stored in sorted(run.glob("*.fields.json")):
        decode = stored.with_name(stored.name.replace(".fields.json", ".decode.txt"))
        if not decode.exists():
            problems.append(f"{stored}: no decode beside it to reproduce it from")
            continue
        out = subprocess.run([sys.executable, "harness/fields.py", str(decode), "--json"],
                             capture_output=True, text=True)
        if out.returncode != 0:
            problems.append(f"{stored}: fields.py failed on its decode")
            continue
        fresh, old = json.loads(out.stdout), json.loads(stored.read_text(encoding="utf-8"))
        for side in (fresh, old):
            side.get("source", {}).pop("decode_file", None)
        if fresh == old:
            checked += 1
            continue
        keys = sorted({k for k in set(fresh) | set(old) if fresh.get(k) != old.get(k)})
        problems.append(f"{stored}: differs in {', '.join(keys)}")
        problems.append("          re-run: bash harness/capture.sh --name "
                        f"{run.name.rsplit('-', 1)[0]}, then point the document at the new run")

print(f"  {checked} derivation(s) across {len(cited)} cited run(s) reproduce exactly")
for line in problems:
    print("  " + line)
sys.exit(1 if problems else 0)
PY
[ $? -eq 0 ] && good "a committed derivation still equals what the tool produces" \
             || bad "a committed fields.json no longer matches its own decode"

step "the layout reconstruction can still fail"
# The walkthrough's offsets are checked by rebuilding each signed response and
# requiring the bytes left over to equal the signature size the negotiation
# implies. A check is worth exactly what it rejects, so this builds a correct
# CHALLENGE_AUTH by hand, confirms it closes at the offsets the document
# publishes, and then breaks it three ways — one byte short, a RequesterContext
# that does not echo the request, and a different signature algorithm — and
# requires every one to be reported rather than accepted.
python3 - <<'PY'
import json, pathlib, subprocess, sys, tempfile

H, S = 48, 96                       # SHA-384, ECDSA-P384
CTX = bytes(range(0x11, 0x19))      # the RequesterContext the request sends

ALGS = ("1 (1) MCTP(5) RSP->REQ SPDM(14, 0x63) SPDM_ALGORITHMS "
        "(Hash=0x00000002(SHA_384), MeasHash=0x00000008(SHA_512), "
        "Asym={asym}, ReqAsym=0x0008(RSAPSS_3072)) ")
CHAL = ("2 (1) MCTP(5) REQ->RSP SPDM(14, 0x83) SPDM_CHALLENGE "
        "(SlotID=0x00, HashType=0xff(AllHash)) ")
AUTH = ("3 (1) MCTP(5) RSP->REQ SPDM(14, 0x03) SPDM_CHALLENGE_AUTH "
        "(Attr=0x80(BasicMutAuth, SlotID=0x00), SlotMask=0x13) ")


def block(raw):
    return "\n".join(f"    {i:04x}: " + " ".join(f"{b:02x}" for b in raw[i:i + 32])
                     for i in range(0, len(raw), 32))


def reconstruct(asym, chal_raw, auth_raw):
    d = pathlib.Path(tempfile.mkdtemp())
    algs, algs_raw = ALGS.format(asym=asym), bytes([0x14, 0x63]) + bytes(34)
    (d / "t.decode.txt").write_text(
        "spdm_dump version 0.1\n"
        "PcapFile: Magic - 'a1b2c3d4', version2.4, DataLink - 291 (MCTP),"
        " MaxPacketSize - 65536\n" + algs + "\n" + CHAL + "\n" + AUTH + "\n",
        encoding="utf-8")
    (d / "t.hex.txt").write_text(
        algs + "\n  SPDM Message:\n" + block(algs_raw) + "\n"
        + CHAL + "\n  SPDM Message:\n" + block(chal_raw) + "\n"
        + AUTH + "\n  SPDM Message:\n" + block(auth_raw) + "\n", encoding="utf-8")
    out = subprocess.run([sys.executable, "harness/fields.py",
                          str(d / "t.decode.txt"), "--json"],
                         capture_output=True, text=True)
    if out.returncode != 0:
        print("  fields.py failed:", out.stderr.strip())
        return None
    return json.loads(out.stdout)["layout"]


good_chal = bytes([0x14, 0x83, 0x00, 0xFF]) + bytes(32) + CTX
good_auth = (bytes([0x14, 0x03, 0x80, 0x13]) + bytes(H) + bytes(32) + bytes(H)
             + b"\x00\x00" + CTX + bytes(S))

lay = reconstruct("0x00000080(ECDSA_P384)", good_chal, good_auth)
if lay is None or lay["closed"] != 1:
    print("  a correct CHALLENGE_AUTH did not close:", lay and lay["unexplained"])
    sys.exit(1)
ca = lay["challenge_auth"]
if (ca["nonce_offset"], ca["signature_bytes"],
        ca["summary_hash_sized_by"]) != (52, 96, "BaseHashAlgo"):
    print("  the intact reconstruction disagrees with the document:", ca)
    sys.exit(1)
print(f"  intact: closes — nonce at {ca['nonce_offset']}, "
      f"signature {ca['signature_bytes']} B, summary hash by {ca['summary_hash_sized_by']}")

for name, asym, chal, auth in (
    ("one byte short", "0x00000080(ECDSA_P384)", good_chal, good_auth[:-1]),
    ("context does not echo", "0x00000080(ECDSA_P384)", good_chal,
     good_auth[:134] + bytes([good_auth[134] ^ 0xFF]) + good_auth[135:]),
    ("signature algorithm changed", "0x00000010(ECDSA_P256)", good_chal, good_auth),
):
    lay = reconstruct(asym, chal, auth)
    if lay is None:
        sys.exit(1)
    if lay["closed"] != 0 or not lay["unexplained"]:
        print(f"  ACCEPTED A BROKEN CASE: {name} -> closed={lay['closed']}")
        sys.exit(1)
    print(f"  {name}: rejected")
PY
[ $? -eq 0 ] && good "the reconstruction closes on a correct message and on nothing else" \
             || bad "the layout reconstruction accepted a message it should have rejected"

step "the certificate reconstruction can still fail"
# CHALLENGE_AUTH is over-determined by one equation. CERTIFICATE is over-
# determined by four, and each of the four has to be shown rejecting something
# on its own or it is decoration:
#
#   closure     the message length against its header plus PortionLength
#   agreement   the chain's own Length against PortionLength + RemainderLength
#   structure   the certificates as a whole number of DER SEQUENCEs, consumed
#               to the last byte
#   digest      RootHash against the hash of the first certificate, computed
#
# The fourth is reported rather than enforced, because DSP0274 permits a chain
# whose root is not among its certificates — so the test requires the field to
# turn FALSE rather than requiring the message to be refused. A check that
# cannot say "no" and a check that says "no" wrongly are different failures and
# this suite has to distinguish them.
python3 - <<'PY'
import hashlib, json, pathlib, subprocess, sys, tempfile

H = 48                                   # SHA-384, which the ALGORITHMS line below negotiates

ALGS = ("1 (1) MCTP(5) RSP->REQ SPDM(14, 0x63) SPDM_ALGORITHMS "
        "(Hash=0x00000002(SHA_384), MeasHash=0x00000008(SHA_512), "
        "Asym=0x00000080(ECDSA_P384), ReqAsym=0x0008(RSAPSS_3072)) ")
GET = ("2 (1) MCTP(5) REQ->RSP SPDM(14, 0x82) SPDM_GET_CERTIFICATE "
       "(SlotID=0x00, LargeCert=0x80, Attr=0x00(), Offset=0x00000000, "
       "Length=0x00027ff0) ")
CERT = ("3 (1) MCTP(5) RSP->REQ SPDM(14, 0x02) SPDM_CERTIFICATE "
        "(SlotID=0x00, LargeCert=0x80, Attr=0x01(DEVICE), PortLen=0x00000295, "
        "RemLen=0x00000000) ")


def seq(body: bytes) -> bytes:
    """A DER SEQUENCE with a minimally encoded length — a stand-in certificate."""
    n = len(body)
    if n < 0x80:
        return bytes([0x30, n]) + body
    width = (n.bit_length() + 7) // 8
    return bytes([0x30, 0x80 | width]) + n.to_bytes(width, "big") + body


def _stretched(cert: bytes) -> bytes:
    """The same bytes, declaring one more content byte than it carries.

    Byte 3 is the low half of the two-byte DER length in `30 82 01 2C ...`, so
    raising it turns 300 into 301 without moving anything. Same buffer length,
    same chain length, one certificate that no longer fits.
    """
    out = bytearray(cert)
    out[3] += 1
    return bytes(out)


CERTS = [seq(b"\xAA" * 100), seq(b"\xBB" * 200), seq(b"\xCC" * 300)]
BLOB = b"".join(CERTS)
ROOT = hashlib.sha384(CERTS[0]).digest()


DIG = ("4 (1) MCTP(5) RSP->REQ SPDM(14, 0x01) SPDM_DIGESTS "
       "(SupportedSlotMask=0x01, ProvisionedSlotMask=0x01) ")


def digests(slots=1, extra=4, pad=0):
    """4 + n x (H + extra) bytes, plus `pad` the reconstruction must not accept."""
    return (bytes([0x14, 0x01, (1 << slots) - 1, (1 << slots) - 1])
            + bytes(slots * (H + extra) + pad))


def build(chain_len=None, portion=None, remainder=0, root=None, blob=None,
          trim=0, req_len=16):
    blob = BLOB if blob is None else blob
    root = ROOT if root is None else root
    chain = (chain_len if chain_len is not None else 4 + H + len(blob))
    body = chain.to_bytes(4, "little") + root + blob
    port = portion if portion is not None else len(body)
    rsp = (bytes([0x14, 0x02, 0x80, 0x01]) + bytes(4)
           + port.to_bytes(4, "little") + remainder.to_bytes(4, "little") + body)
    if trim:
        rsp = rsp[:-trim]
    req = (bytes([0x14, 0x82, 0x80, 0x00]) + bytes(4)
           + (0).to_bytes(4, "little") + (0x27FF0).to_bytes(4, "little"))[:req_len]
    return req, rsp


def block(raw):
    return "\n".join(f"    {i:04x}: " + " ".join(f"{b:02x}" for b in raw[i:i + 32])
                     for i in range(0, len(raw), 32))


def run(req, rsp, dig=None):
    dig = digests() if dig is None else dig
    d = pathlib.Path(tempfile.mkdtemp())
    algs_raw = bytes([0x14, 0x63]) + bytes(34)
    (d / "t.decode.txt").write_text(
        "spdm_dump version 0.1\n"
        "PcapFile: Magic - 'a1b2c3d4', version2.4, DataLink - 291 (MCTP),"
        " MaxPacketSize - 65536\n" + ALGS + "\n" + GET + "\n" + CERT + "\n" + DIG + "\n",
        encoding="utf-8")
    (d / "t.hex.txt").write_text(
        ALGS + "\n  SPDM Message:\n" + block(algs_raw) + "\n"
        + GET + "\n  SPDM Message:\n" + block(req) + "\n"
        + CERT + "\n  SPDM Message:\n" + block(rsp) + "\n"
        + DIG + "\n  SPDM Message:\n" + block(dig) + "\n", encoding="utf-8")
    out = subprocess.run([sys.executable, "harness/fields.py",
                          str(d / "t.decode.txt"), "--json"],
                         capture_output=True, text=True)
    if out.returncode != 0:
        print("  fields.py failed:", out.stderr.strip())
        return None
    return json.loads(out.stdout)["layout"]


lay = run(*build())
if lay is None:
    sys.exit(1)
cert = lay["certificate"]
if not cert or not cert.get("closes"):
    print("  a correct CERTIFICATE did not close:", lay["unexplained"])
    sys.exit(1)
want = {"chain_offset": 16, "chain_length": 4 + H + len(BLOB),
        "root_hash_offset": 20, "certificates": 3,
        "certificate_bytes": [len(c) for c in CERTS],
        "root_hash_matches_first_certificate": True, "large_form": True}
wrong = {k: (cert.get(k), v) for k, v in want.items() if cert.get(k) != v}
if wrong:
    print("  the intact reconstruction disagrees with the document:", wrong)
    sys.exit(1)
print(f"  intact: closes — chain at {cert['chain_offset']}, Length "
      f"{cert['chain_length']} = {cert['portion_length']} + {cert['remainder_length']}, "
      f"{cert['certificates']} certificates "
      f"{'+'.join(str(n) for n in cert['certificate_bytes'])}, RootHash verified")

# DIGESTS is reconstructed from two hypotheses that differ by 4 bytes per slot,
# and only one can close. That is what turns "the requester dropped two slots"
# into an exact 104 bytes rather than an observation, so it needs a length that
# neither hypothesis explains and a refusal to guess between them.
d = lay["digests"]
if not d or (d["slots"], d["per_slot_bytes"], d["total_bytes"]) != (1, H + 4, 4 + H + 4):
    print("  a correct DIGESTS did not close:", d)
    sys.exit(1)
print(f"  intact: DIGESTS {d['total_bytes']} B = 4 + {d['slots']} x "
      f"({d['digest_bytes']} + {d['per_slot_extra']}), "
      f"per-slot extra read as {d['per_slot_extra_is']}")
for pad, why in ((1, "one byte more than either hypothesis"),
                 (-2, "two bytes short, matching neither")):
    lay2 = run(*build(), dig=digests(pad=pad))
    if lay2 is None:
        sys.exit(1)
    if lay2["digests"] is not None:
        print(f"  ACCEPTED A BROKEN DIGESTS: {why}")
        sys.exit(1)
    print(f"  DIGESTS {why}: rejected")

# And the second hypothesis has to be live, or the first is hard-coded and the
# "two hypotheses, one closes" claim is decoration. A DIGESTS four bytes shorter
# is not broken: it is the same message without the per-slot key information,
# and the reconstruction has to read it as that rather than refuse it.
lay2 = run(*build(), dig=digests(extra=0))
if lay2 is None or not lay2["digests"] or lay2["digests"]["per_slot_extra"] != 0:
    print("  the digests-only hypothesis never closes:", lay2 and lay2["digests"])
    sys.exit(1)
print(f"  DIGESTS without per-slot key information: read as "
      f"{lay2['digests']['total_bytes']} B = 4 + 1 x ({H} + 0)")

caught = {}
for name, kwargs, expect in (
    ("one byte short", dict(trim=1), "reject"),
    ("chain Length disagrees with the two portion fields",
     dict(chain_len=4 + H + len(BLOB) + 8), "reject"),
    # The declared length is raised by one and the buffer is left alone, so the
    # chain is still exactly as long as both length fields say it is: only the
    # DER walk can find this. Written the other way round first — a byte
    # removed and a byte appended — which changed nothing at all, because the
    # byte removed and the byte appended were the same value. The test passed
    # by not testing anything.
    ("a certificate declaring one byte too many",
     dict(blob=CERTS[0] + CERTS[1] + _stretched(CERTS[2])), "reject"),
    ("GET_CERTIFICATE the wrong length for its Param1", dict(req_len=8), "reject"),
    ("RootHash altered", dict(root=bytes(48)), "flip"),
):
    lay = run(*build(**kwargs))
    if lay is None:
        sys.exit(1)
    got = lay["certificate"]
    if expect == "reject":
        if got is not None or not lay["unexplained"]:
            print(f"  ACCEPTED A BROKEN CASE: {name}")
            sys.exit(1)
        caught[name] = lay["unexplained"][0].split(":", 1)[1].strip()[:44]
        print(f"  {name}: rejected")
    else:
        if got is None:
            print(f"  {name}: refused the message instead of reporting the mismatch")
            sys.exit(1)
        if got["root_hash_matches_first_certificate"] is not False:
            print(f"  {name}: RootHash mismatch was not noticed")
            sys.exit(1)
        print(f"  {name}: reported as a mismatch, message still parsed")

if len(set(caught.values())) != len(caught):
    print("  two breaks are caught by the same check:", caught)
    sys.exit(1)
print(f"  {len(caught)} rejections through {len(set(caught.values()))} distinct checks")
PY
[ $? -eq 0 ] && good "the certificate reconstruction closes on a correct chain and on nothing else" \
             || bad "the certificate reconstruction accepted a chain it should have rejected"

step "every document that cites a capture still agrees with it"
# These documents are made almost entirely of stated facts, which is the
# category this project has twice caught itself getting wrong. So their numbers
# are not typed in: each is marked up as <!--claim key=value--> and re-derived
# here from the decode file the document names. A number that drifts from its
# capture is a failed build, not something a reader might notice.
#
# Discovered by reading which documents make claims, not from a list. A list is
# how docs/certchain.md would have been added and left unchecked, which is the
# same failure docs/decisions/0004 is about, one level up.
#
# Selected on the CLAIM marker rather than the capture directive, and the
# difference matters. The obvious selector was the capture directive, and it
# picked up ADR 0004 — which quotes the directive's syntax in prose while
# asserting nothing, so it failed for having no claims. Selecting on claims is
# also the complete rule: no claim can escape, because any document containing
# one is selected by containing it.
# Three outcomes, not two. A document that merely QUOTES the markup — LOG.md
# explaining what a claim looks like, RUNBOOK.md showing the syntax in a
# sentence — asserts nothing and must not be failed for it; a document that
# names a capture and asserts nothing is a different thing and is failed.
# fields.py --check says which with exit 2 against exit 1, because "verified"
# and "did not participate" are different facts and one status cannot carry
# both. The first version of this step had two outcomes and reported LOG.md as
# contradicting a capture.
found=0
skipped=0
while IFS= read -r doc; do
    python3 harness/fields.py --check "$doc"
    case $? in
        0) found=$((found + 1)); good "$doc" ;;
        2) skipped=$((skipped + 1)) ;;
        *) bad "$doc contradicts a capture it cites" ;;
    esac
done < <(git ls-files '*.md' | xargs grep -l '<!--claim ' 2>/dev/null | sort)
if [ "$found" -eq 0 ]; then
    bad "no document asserts anything against a capture — the mechanism reaches nothing"
else
    good "$found document(s) checked, $skipped that only quote the markup"
fi

step "the tamper proxy can still refuse to change a byte"
# The proxy is the only thing in this repository that produces a successful
# cryptographic rejection, and it does it by changing one byte of a message it
# has parsed. If its parse is wrong the byte lands somewhere else, the arm
# still fails, and the wrong sentence gets written about why.
#
# So its refusals are the check, not its successes. --self-test feeds the
# parser thirteen broken messages, requires each to be refused by the
# specifically named check that should catch it, and fails if any registered
# check was never exercised. One of the thirteen is the field list in
# plan/W05's own text, which omits RequesterContext.
if out="$(python3 harness/tamper_proxy.py --self-test 2>&1)"; then
    printf '%s\n' "$out" | tail -3 | sed 's/^/  /'
    good "every registered refusal fires, and the flip lands where the walk says"
else
    printf '%s\n' "$out" | sed 's/^/  /'
    bad "harness/tamper_proxy.py --self-test failed"
fi

step "a libspdm status can be named, and a C errno cannot be mistaken for one"
# Table 1's most load-bearing cell is a status code that two arms share. Naming
# it from a table is only safe if the table is right and the line shape is not
# over-matched: the emulators print "receive_platform_data Error - 2" through
# the same macro, and reading that 2 as a libspdm status would name a layer
# that had no opinion about anything.
if out="$(python3 harness/spdm_status.py --self-test 2>&1)"; then
    printf '%s\n' "$out" | tail -2 | sed 's/^/  /'
    good "severity and source are computed, names are checked against the header"
else
    printf '%s\n' "$out" | sed 's/^/  /'
    bad "harness/spdm_status.py --self-test failed"
fi

step "three tools agree on how big the certificate chain is"
# certs/check_chain.py adds up the DER files on disk and never opens a capture.
# harness/fields.py reads spdm_dump's decode and never opens a certificate.
# bench/pcapstat.py walks the capture file and opens neither. Three routes to
# one number, sharing no input:
#
#     4 + RootHash + sum of the certificates  ==  the chain's own Length field
#                                             ==  the sum of every PortionLength
#
# The third route arrived in week five, with cert_roundtrips, and it found
# something the other two could not: the 4.0.0-rc responder sends the chain in
# ONE message where the 3.8.0 responder sends it in two, and the number of
# round trips is a property of the exchange rather than of the certificates.
python3 - <<'PY'
import json, pathlib, subprocess, sys

def tool(script, *args):
    out = subprocess.run([sys.executable, script, *args],
                         capture_output=True, text=True)
    if out.returncode not in (0, 1):
        raise SystemExit(f"  {script} failed: {out.stderr.strip()[:200]}")
    return json.loads(out.stdout)

bundle = pathlib.Path("certs/out/bundle_responder.certchain.der")
on_disk = bundle.stat().st_size if bundle.exists() else None
if on_disk is None:
    print("  certs/out is not staged; the disk route is skipped")

checked, chunked, problems = [], [], []
for pcap in sorted(pathlib.Path("bench/data").glob("*/*.pcap")):
    name = f"{pcap.parent.name}/{pcap.name}"
    stats = tool("bench/pcapstat.py", str(pcap), "--json")["summary"]
    cert = stats["certificates"]
    if cert["roundtrips"] == 0:
        continue
    if not cert["slots"]:
        # A chain larger than the negotiated DataTransferSize comes back inside
        # CHUNK_RESPONSE rather than CERTIFICATE, so there is no chain to
        # reassemble here. Reported, because a silent zero looks like a bug.
        if stats["by_type"].get("SPDM_CHUNK_RESPONSE"):
            chunked.append(f"{name}: {cert['roundtrips']} round trip(s), the "
                           "chain came back in CHUNK_RESPONSE messages")
        elif stats["by_type"].get("SPDM_ERROR"):
            # t3_cert: the responder validated its own chain, could not, and
            # answered SPDM_ERROR instead of serving the slot. There is no
            # chain because none was ever sent, which is the finding rather
            # than a failure to parse one.
            chunked.append(f"{name}: {cert['roundtrips']} round trip(s) "
                           "answered with SPDM_ERROR, so no chain was sent")
        else:
            problems.append(f"{name}: {cert['roundtrips']} GET_CERTIFICATE and "
                            "no chain reassembled")
        continue
    for c in cert["slots"]:
        if not c["closes"]:
            problems.append(f"{name} slot {c['slot']}: {c['why']}")
            continue
        if c["length_field"] != c["chain_bytes"]:
            problems.append(f"{name} slot {c['slot']}: Length field "
                            f"{c['length_field']} != {c['chain_bytes']}")
    ours = [c for c in cert["slots"]
            if c["closes"] and c["certificates_bytes"] == on_disk]
    if ours:
        checked.append(f"{name}: slot {ours[0]['slot']} carries 4 + "
                       f"{cert['root_hash_bytes']} + {on_disk} = "
                       f"{ours[0]['chain_bytes']} bytes in "
                       f"{ours[0]['messages']} message(s), "
                       f"{cert['roundtrips']} round trip(s)")

for line in checked:
    print("  " + line)
for line in chunked:
    print("  --   " + line)
for line in problems:
    print("  " + line)
if on_disk is not None and not checked:
    print(f"  no capture carries a chain whose certificates total {on_disk} bytes")
    sys.exit(1)
sys.exit(1 if problems else 0)
PY
[ $? -eq 0 ] && good "the DER files, the decode and the capture agree on the chain" \
             || bad "the three routes to the chain's size disagree"

step "an in-flight tamper is still rejected, and the device-side one still is not"
# This is the assertion the whole tamper directory exists to make, written as a
# negative: the build turns RED if a tampered measurement stops being refused.
# It reads the primary evidence rather than the table tamper.sh printed — the
# requester's own log for the status, and the committed fields.json for what
# reached the wire — so it is checking the run, not the summary of it.
#
# Four things have to hold, and the third is the one people find surprising:
#
#   t0_proxy    forwarded unchanged: no error, and the control's record
#   t2a_record  the signed CONTENT changed in flight: refused
#   t2b_sig     the SIGNATURE changed in flight:      refused, SAME status
#   t1_meas     changed at the DEVICE:                NOT refused, and the
#               record on the wire differs from the control
#
# t1_meas is asserted to keep passing. It is not a gap in the harness; it is
# the measurement that says why Gate 3 exists, and if it ever starts failing
# that is a change in libspdm worth stopping for.
python3 - <<'PY'
import json, pathlib, subprocess, sys

def status(log):
    out = subprocess.run([sys.executable, "harness/spdm_status.py", str(log),
                          "--json"], capture_output=True, text=True)
    if out.returncode not in (0, 1) or not out.stdout.strip():
        return None
    got = json.loads(out.stdout)
    return got if isinstance(got, dict) else None

def record(fields_json):
    if not fields_json.exists():
        return None
    d = json.loads(fields_json.read_text())
    return ((d.get("layout") or {}).get("measurement_record") or {}).get("sha256")

WANT = {
    "t0_proxy":   ("no status", "same record"),
    "t1_meas":    ("no status", "different record"),
    "t2a_record": ("VERIF_FAIL", "different record"),
    "t2b_sig":    ("VERIF_FAIL", "same record"),
}

demonstrated, problems, seen = 0, [], 0
for run in sorted(pathlib.Path("bench/data").glob("*-tamper-*")):
    control = record(run / "t0_clean.fields.json")
    if control is None:
        continue
    present = {c for c in WANT if (run / f"{c}.req.log").exists()}
    if not present:
        continue
    seen += 1
    print(f"  {run.name}")
    rejections = {}
    for case in sorted(present):
        st = status(run / f"{case}.req.log")
        rec = record(run / f"{case}.fields.json")
        got_status = "no status" if st is None else (st["name"] or st["status"])
        got_record = ("no record" if rec is None else
                      "same record" if rec == control else "different record")
        want_status, want_record = WANT[case]
        ok = got_status == want_status and got_record == want_record
        if st is not None and st["name"] == "VERIF_FAIL":
            rejections[case] = st["status"]
        print(f"    {'ok  ' if ok else 'FAIL'} {case:<11} {got_status:<12} "
              f"{got_record}")
        if not ok:
            problems.append(f"{run.name}/{case}: wanted {want_status} and "
                            f"{want_record}, got {got_status} and {got_record}")
    if {"t2a_record", "t2b_sig"} <= present:
        codes = set(rejections.values())
        if len(codes) == 1 and rejections:
            print(f"    ok   both in-flight tampers refused with the same "
                  f"status, {codes.pop()}")
            demonstrated += 1
        else:
            problems.append(f"{run.name}: the two in-flight tampers did not "
                            f"share one status: {rejections}")

    # The proxy and the capture are two witnesses to the same byte, and they
    # never see each other: the proxy reported what it read and what it wrote
    # while the connection was open, and fields.py read what the requester
    # ended up with, out of a file, afterwards. So for t2a_record:
    #
    #   proxy "before"  ==  the control's record   the responder sent the right one
    #   proxy "after"   ==  the record in the pcap  the requester got the wrong one
    #
    # Either half failing means the byte that changed is not the byte anybody
    # thinks changed, and that is not a distinction an exit code carries.
    report = run / "t2a_record.proxy.json"
    if report.exists():
        pr = json.loads(report.read_text()).get("tamper") or {}
        wire = record(run / "t2a_record.fields.json")
        before_ok = pr.get("record_sha256_before") == control
        after_ok = pr.get("record_sha256_after") == wire
        print(f"    {'ok  ' if before_ok else 'FAIL'} t2a_record  the proxy read "
              f"the control's record off the wire "
              f"({(pr.get('record_sha256_before') or '-')[:16]}…)")
        print(f"    {'ok  ' if after_ok else 'FAIL'} t2a_record  and what it "
              f"wrote is what the capture holds "
              f"({(pr.get('record_sha256_after') or '-')[:16]}…)")
        if not before_ok:
            problems.append(f"{run.name}/t2a_record: the responder's record was "
                            f"not the control's")
        if not after_ok:
            problems.append(f"{run.name}/t2a_record: the proxy's output digest "
                            f"is not the one in the capture")

if seen == 0:
    print("  no tamper run in bench/data carries these arms")
    sys.exit(1)
if demonstrated == 0:
    print("  no run demonstrates an in-flight tamper being rejected")
    sys.exit(1)
for line in problems:
    print("  " + line)
sys.exit(1 if problems else 0)
PY
[ $? -eq 0 ] && good "tampering in flight is refused; tampering at the device is not" \
             || bad "the tamper detection this repository claims did not hold"

step "the three gate tables agree, and they agree about which week it is"
# README.md, docs/roadmap.md and RUNBOOK.md each carry a table of the nine
# gates, in two languages and three formats. On 2026-09-10 the RUNBOOK's first
# screen was nine days stale, and the person it misled was the author: it said
# the three tamper points had not been started while section 8.8 of the same
# file explained all three.
#
# Worth being exact about what this catches, because the first version of this
# check would NOT have caught that day. The three tables' STATE columns all
# said "in progress" for G2 and were all correct. What had rotted was the prose
# beside the state, and the week number at the top of the RUNBOOK, and there is
# no mechanism for prose — 2026-09-01 in LOG.md is the entry that says so.
#
# The week number is mechanisable, and it is the load-bearing half: a reader
# who is told "week three finished" stops reading before the section that
# explains week four. So both halves are checked, and only one of them is the
# reason this step exists.
#
# CLAUDE.md's end-of-day list already said to keep two of the tables in step.
# That is a discipline; this is a mechanism, and the difference between them
# was nine days.
python3 - <<'PY'
import re, sys

STATES = {
    "complete": "complete", "in progress": "in progress",
    "not started": "not started",
    "完成": "complete", "進行中": "in progress",
    "未開始": "not started",
}
FILES = ["README.md", "docs/roadmap.md", "RUNBOOK.md"]
ROW = re.compile(r"^\|\s*\*{0,2}(G[0-8])\*{0,2}\s*\|(?P<rest>.*)\|\s*$")

def states(path):
    out = {}
    for line in open(path, encoding="utf-8"):
        m = ROW.match(line.rstrip())
        if not m:
            continue
        rest = m.group("rest")
        hits = [(rest.find(k), v) for k, v in STATES.items() if k in rest]
        if not hits:
            out[m.group(1)] = "UNSTATED"
            continue
        out[m.group(1)] = min(hits)[1]
    return out

tables = {f: states(f) for f in FILES}
gates = sorted(set().union(*(set(t) for t in tables.values())))
width = max(len(f) for f in FILES)
for f in FILES:
    row = " ".join(f"{g}:{tables[f].get(g, '-')[:11]:<11}" for g in gates)
    print(f"  {f:<{width}}  {row}")

bad = 0
for g in gates:
    got = {f: tables[f].get(g) for f in FILES}
    if len(set(got.values())) != 1:
        print(f"  {g} disagrees: " + ", ".join(f"{f}={v}" for f, v in got.items()))
        bad += 1
    elif set(got.values()) == {"UNSTATED"}:
        print(f"  {g} carries no recognised state in any table")
        bad += 1
    elif None in got.values():
        print(f"  {g} is missing from " +
              ", ".join(f for f, v in got.items() if v is None))
        bad += 1
if not gates:
    print("  no gate table found in any of the three files")
    bad += 1

# The week number, from the sentence each file states it in.
WEEK = {
    "README.md": r"[Tt]his is week (\d+) of a 14-week programme",
    "RUNBOOK.md": r"W0*(\d+)\s*收工",
}
weeks = {}
for f, pattern in WEEK.items():
    m = re.search(pattern, open(f, encoding="utf-8").read())
    weeks[f] = int(m.group(1)) if m else None
    print(f"  {f:<{width}}  says week {weeks[f]}")
if None in weeks.values():
    for f, w in weeks.items():
        if w is None:
            print(f"  {f} no longer states which week it is, in the form "
                  f"/{WEEK[f]}/")
    bad += 1
elif len(set(weeks.values())) != 1:
    print("  the two files disagree about which week it is: "
          + ", ".join(f"{f}={w}" for f, w in weeks.items()))
    bad += 1

sys.exit(1 if bad else 0)
PY
[ $? -eq 0 ] && good "nine gates, three tables, one answer each, and one week" \
             || bad "the gate tables disagree about what exists"

step "every figure still renders from the data it claims to show"
# CLAUDE.md and figures/README.md have said since 2026-08-11 that no figure
# here is drawn by hand, and README.md's repository layout has listed the
# directory since the same day. The directory was empty until 2026-09-10, which
# is the "table indexing a directory" shape of the rot this repository keeps
# finding, aimed at a directory with nothing in it.
#
# So the rule now has something to hold. harness/mkfigures.py re-renders each
# figure from certs/check_chain.py, harness/fields.py and bench/pcapstat.py and
# this step requires the committed file to be identical. A figure whose numbers
# stopped being true fails the build rather than staying beautiful.
if out="$(python3 harness/mkfigures.py --check 2>&1)"; then
    printf '%s\n' "$out" | sed 's/^/  /'
    good "the committed figures are what the data renders to"
else
    printf '%s\n' "$out" | sed 's/^/  /'
    bad "a figure no longer matches the data it was rendered from"
fi

step "the drills track reports itself"
# The project track has spent five weeks generating work for a track that has
# completed nothing, and until now that was a sentence in LOG.md rather than a
# number anywhere. A sentence does not get read on a day nobody is looking for
# it.
#
# This does not fail the build. Whether to spend an evening on paper is not a
# decision a script gets to make, and a check that fails for a reason nobody
# intends to fix teaches people to ignore red. What it does assert is the one
# thing that would be dishonest: a drill in DONE.txt whose compile-error count
# was never recorded. DONE.txt is what CI runs and SCORECARD.md is the only
# thing in this repository that measures the author rather than the system.
python3 - <<'PY'
import pathlib, re, sys

drills = sorted(p.stem for p in pathlib.Path("c-drills").glob("d*_*.c"))
done = [ln.strip() for ln in pathlib.Path("c-drills/DONE.txt").read_text().splitlines()
        if ln.strip() and not ln.strip().startswith("#")]
scorecard = pathlib.Path("c-drills/SCORECARD.md").read_text()

print(f"  {len(drills)} drill(s) with a contract, tests and a stub: "
      + ", ".join(d.split('_')[0] for d in drills))
print(f"  {len(done)} in DONE.txt" + (": " + ", ".join(done) if done else ""))
if len(done) < len(drills):
    print(f"  --   {len(drills) - len(done)} written and not yet finished. The "
          "implementations are not the harness's to write.")

bad = 0
for name in done:
    if name not in drills:
        print(f"  {name} is in DONE.txt and has no source file")
        bad += 1
        continue
    key = name.split("_")[0].upper()
    row = re.search(rf"^\|\s*{key}\s*\|.*$", scorecard, re.M | re.I)
    if not row:
        print(f"  {name} is finished and has no row in SCORECARD.md")
        bad += 1
        continue
    cells = [c.strip() for c in row.group(0).split("|")]
    # columns: '', #, Drill, Date, Paper time, Compile errors, ...
    if len(cells) < 7 or not cells[6]:
        print(f"  {name} is finished and its compile-error count is blank")
        bad += 1
sys.exit(1 if bad else 0)
PY
[ $? -eq 0 ] && good "every finished drill carries the number it exists to produce" \
             || bad "a drill is claimed finished without its measurement"

step "private material is not tracked"
# plan/ and archive/ hold the schedule this work is executed against; study/
# holds a question bank and its answers, which is a record of what one person
# does not yet know. All three are the author's, none is the repository's, and
# `git add -A` does not distinguish. So the mechanism does.
if git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    leaked="$(git ls-files plan archive study 2>/dev/null)"
    if [ -n "$leaked" ]; then
        printf '%s\n' "$leaked" | sed 's/^/  /'
        bad "private material is staged or tracked"
    else
        good "plan/, archive/ and study/ are untracked"
    fi
fi

printf '\n'
if [ "$FAILED" -eq 0 ]; then
    hdr "all checks passed"
else
    hdr "checks failed — fix the FAIL lines above"
fi
exit "$FAILED"

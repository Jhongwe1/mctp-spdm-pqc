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
if python3 -m py_compile harness/fields.py; then
    good "harness/fields.py compiles"
else
    bad "harness/fields.py has a syntax error"
fi

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

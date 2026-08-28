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
    if shellcheck -x -S warning harness/*.sh; then
        good "no warnings or errors"
    else
        bad "shellcheck reported problems"
    fi
else
    printf '  --   shellcheck not installed (apt: shellcheck) — skipped\n'
fi

step "python syntax"
if python3 -m py_compile harness/pcapcount.py harness/lib/_manifest.py; then
    good "harness python compiles"
else
    bad "python syntax error"
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

step "the handshake walkthrough still agrees with its capture"
# The walkthrough is a document made almost entirely of stated facts, which is
# the category this project has twice caught itself getting wrong. So its
# numbers are not typed in: each is marked up as <!--claim key=value--> and
# re-derived here from the decode file the document names. A number that drifts
# from its capture is a failed build, not something a reader might notice.
if [ -f docs/handshake-walkthrough.md ]; then
    if python3 harness/fields.py --check docs/handshake-walkthrough.md; then
        good "every claim in the walkthrough matches the capture it cites"
    else
        bad "docs/handshake-walkthrough.md contradicts its own capture"
    fi
else
    printf '  --   docs/handshake-walkthrough.md not written yet — skipped\n'
fi

step "planning material is not tracked"
if git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    leaked="$(git ls-files plan archive 2>/dev/null)"
    if [ -n "$leaked" ]; then
        printf '%s\n' "$leaked" | sed 's/^/  /'
        bad "private planning files are staged or tracked"
    else
        good "plan/ and archive/ are untracked"
    fi
fi

printf '\n'
if [ "$FAILED" -eq 0 ]; then
    hdr "all checks passed"
else
    hdr "checks failed — fix the FAIL lines above"
fi
exit "$FAILED"

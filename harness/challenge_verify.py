#!/usr/bin/env python3
"""Verify a CHALLENGE_AUTH signature from a capture, to decide who was wrong.

    python3 harness/challenge_verify.py bench/data/w10-validator-*/caps-default.pcap
    python3 harness/challenge_verify.py <pcap> --json out.json
    python3 harness/challenge_verify.py --self-test

Why this exists
---------------
DMTF's conformance suite reports four FAILs against this responder under the
message "response signature", all of them in CHALLENGE_AUTH, and all of them in
the two cases whose message mask omits GET_CERTIFICATE (6.2 and 6.3, and their
1.2 twins 6.12 and 6.13). The cases that fetch the certificate pass, including
the one that fetches the certificate and NOT the digests. So the discriminator
is the certificate fetch and not the digests.

Reading the suite's source says why. Each case calls libspdm_init_connection at
the top, which sends GET_VERSION, which calls libspdm_reset_context, which frees
the peer certificate chain the case's own setup had fetched. A case whose mask
then omits GET_CERTIFICATE reaches
libspdm_verify_challenge_auth_signature with no peer chain, and that function
returns false at its first step -- libspdm_x509_get_cert_from_cert_chain on an
empty buffer -- before any signature arithmetic happens.

That is a story, and docs/roadmap.md's standing rules are unkind to stories:
rule 19 exists because a story about two defects masking each other was wrong
until somebody ran the check. So this file does not argue. It takes the bytes
off the wire, rebuilds the transcript the signature covers, and asks OpenSSL
whether the signature is good.

How it avoids being right by accident
-------------------------------------
A tool that verifies a signature nobody disputes proves nothing about the one
that is disputed. So every run does BOTH, and the disputed answer is only
reported when the undisputed one came out right:

  * a segment that fetched the certificate -- the suite says PASS. If this
    file cannot verify that one, its model of the transcript is wrong and it
    says so and stops. That is the calibration.
  * a segment that did not -- the suite says FAIL. Its verdict is the finding.

The division of labour is certs/check_chain.py's, in that file's words: this
file owns structure and OpenSSL owns cryptography. Nothing here implements
ECDSA. What it implements is M1M2, which is a concatenation.

    M1M2 = A || B || C
      A = GET_VERSION VERSION GET_CAPABILITIES CAPABILITIES
          NEGOTIATE_ALGORITHMS ALGORITHMS
      B = the GET_DIGESTS/DIGESTS/GET_CERTIFICATE/CERTIFICATE exchanges, if any
      C = CHALLENGE, and CHALLENGE_AUTH up to but not including its signature

    signature = ECDSA(BaseAsymSel) over Hash(BaseHashSel)(M1M2), for SPDM 1.0
    and 1.1. libspdm_asym_verify_ex adds a signing-context prefix from 1.2
    onward, which this file does not implement -- so it refuses a 1.2+ segment
    rather than verifying the wrong bytes.

Only the FIRST CHALLENGE of a connection is verified, and that is not a
shortcut. libspdm_verify_challenge_auth_signature calls
libspdm_reset_message_b and libspdm_reset_message_c immediately after computing
M1M2, so a second CHALLENGE on the same connection is signed over a transcript
this file has no independent record of.

Exit codes: 0 every verification this file attempted came out as the suite's
own result predicted, or the dispute was resolved and reported; 1 the
calibration failed, so no verdict is offered; 2 bad arguments.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import subprocess
import sys
import tempfile

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "bench"))
sys.path.insert(0, str(REPO_ROOT / "harness"))

GET_VERSION, VERSION = 0x84, 0x04
GET_CAPABILITIES, CAPABILITIES = 0xE1, 0x61
NEGOTIATE_ALGORITHMS, ALGORITHMS = 0xE3, 0x63
GET_DIGESTS, DIGESTS = 0x81, 0x01
GET_CERTIFICATE, CERTIFICATE = 0x82, 0x02
CHALLENGE, CHALLENGE_AUTH = 0x83, 0x03
ERROR = 0x7F
CHUNK_SEND, CHUNK_GET = 0x85, 0x86

A_SEQUENCE = [GET_VERSION, VERSION, GET_CAPABILITIES, CAPABILITIES,
              NEGOTIATE_ALGORITHMS, ALGORITHMS]
B_CODES = {GET_DIGESTS, DIGESTS, GET_CERTIFICATE, CERTIFICATE}

SPDM_NONCE_SIZE = 32
SPDM_REQ_CONTEXT_SIZE = 8

# Signature width and the digest OpenSSL is told to use, BY ALGORITHM NAME.
#
# The bit values are deliberately absent: bench/pcapstat.py owns the bit-to-name
# tables and this file asks it, because a second copy of BASE_ASYM is a second
# place for ECDSA_P384 to be 0x100 instead of 0x80. It was, in the first draft
# of this file, and every segment in the capture was refused for an algorithm
# the responder had never selected.
#
# What is left here are two FIPS constants per curve, which is the same pair
# docs/pqc-cost.md checks every signature length in Table 2 against.
ASYM_SIG = {
    "ECDSA_P256": (64, "sha256"),
    "ECDSA_P384": (96, "sha384"),
    "ECDSA_P521": (132, "sha512"),
}


class Refused(Exception):
    """This file will not answer this question, and says which one."""


# ----------------------------------------------------------------- capture --

def read_messages(pcap: pathlib.Path) -> list[dict]:
    import pcapstat

    summary, packets = pcapstat.read_pcap(pcap)
    framing = pcapstat.framing_bytes(summary["linktype"])
    if framing is None:
        raise Refused(f"link type {summary['linktype']} is not one this tool frames")
    raw = pcap.read_bytes()

    out = []
    for p in packets:
        body = raw[p["file_offset"]:p["file_offset"] + p["captured_bytes"]]
        if len(body) < framing + 4:
            continue
        if body[pcapstat.MCTP_HEADER_BYTES] != pcapstat.MCTP_TYPE_SPDM:
            continue
        msg = body[framing:]
        out.append({"packet": p["index"] + 1, "code": msg[1],
                    "version": msg[0], "bytes": msg})
    return out


def segments(msgs: list[dict]) -> list[list[dict]]:
    """One list per connection. A connection begins at a GET_VERSION request."""
    out: list[list[dict]] = []
    for m in msgs:
        if m["code"] == GET_VERSION:
            out.append([])
        if out:
            out[-1].append(m)
    return out


def certificate_chains(msgs: list[dict]) -> dict[int, bytes]:
    """slot -> the assembled cert_chain, for every slot the capture completes.

    CERTIFICATE carries PortionLength bytes of the chain and says how much
    remains, so a chain arrives in one or more responses and is done when
    RemainderLength reaches zero. A slot whose last response never says zero is
    left out rather than half-built.
    """
    partial: dict[int, bytearray] = {}
    done: dict[int, bytes] = {}
    for m in msgs:
        if m["code"] != CERTIFICATE:
            continue
        b = m["bytes"]
        if len(b) < 8:
            continue
        slot = b[2] & 0x0F
        portion = int.from_bytes(b[4:6], "little")
        remainder = int.from_bytes(b[6:8], "little")
        if len(b) < 8 + portion:
            continue
        partial.setdefault(slot, bytearray()).extend(b[8:8 + portion])
        if remainder == 0:
            done.setdefault(slot, bytes(partial[slot]))
            partial[slot] = bytearray()
    return done


def der_certificates(blob: bytes) -> list[bytes]:
    """Split a DER run into its top-level SEQUENCEs, by length, not by search."""
    out, off = [], 0
    while off < len(blob):
        if blob[off] != 0x30:
            break
        n = blob[off + 1]
        if n < 0x80:
            hdr, length = 2, n
        else:
            k = n & 0x7F
            if k == 0 or off + 2 + k > len(blob):
                break
            hdr, length = 2 + k, int.from_bytes(blob[off + 2:off + 2 + k], "big")
        if off + hdr + length > len(blob):
            break
        out.append(blob[off:off + hdr + length])
        off += hdr + length
    return out


def leaf_certificate(chain: bytes, hash_bytes: int) -> bytes:
    """The last certificate of an SPDM cert_chain.

    spdm_cert_chain_t: Length(2) Reserved(2) RootHash(H), then the DER run. The
    header is skipped by arithmetic rather than by looking for the first 0x30,
    because a root hash can contain that byte.
    """
    head = 4 + hash_bytes
    if len(chain) <= head:
        raise Refused(f"a {len(chain)}-byte chain cannot hold a {head}-byte header")
    declared = int.from_bytes(chain[0:2], "little")
    if declared != len(chain):
        raise Refused(f"cert_chain.Length is {declared} and the assembled chain "
                      f"is {len(chain)} bytes")
    certs = der_certificates(chain[head:])
    if not certs:
        raise Refused("no DER certificate follows the chain header")
    if sum(len(c) for c in certs) != len(chain) - head:
        raise Refused("the certificates do not tile the chain exactly")
    return certs[-1]


# ------------------------------------------------------------- transcripts --

def negotiated(seg: list[dict]) -> dict:
    """BaseAsymSel and BaseHashSel, read back off this connection's ALGORITHMS.

    Standing rule 8: the independent variable is read from the response, not
    from the flag that asked for it. Here it also sizes three fields -- the
    certificate chain hash, the measurement summary hash and the signature --
    so getting it from anywhere else would put every offset out by the
    difference between two curves.
    """
    import pcapstat

    alg = next((m for m in seg if m["code"] == ALGORITHMS), None)
    if alg is None:
        raise Refused("no ALGORITHMS response in this connection")
    b = alg["bytes"]
    if len(b) < 20:
        raise Refused(f"a {len(b)}-byte ALGORITHMS response is too short")

    asym_bit = int.from_bytes(b[12:16], "little")
    hash_bit = int.from_bytes(b[16:20], "little")
    asym_name = pcapstat.BASE_ASYM.get(asym_bit)
    hash_name = pcapstat.BASE_HASH_NAMES.get(hash_bit)
    if asym_name is None or asym_name not in ASYM_SIG:
        raise Refused(f"BaseAsymSel 0x{asym_bit:08x} "
                      f"({asym_name or 'unnamed'}) is not one this tool sizes")
    hash_bytes = pcapstat.BASE_HASH_BYTES.get(hash_name or "")
    if hash_bytes is None:
        raise Refused(f"BaseHashSel 0x{hash_bit:08x} "
                      f"({hash_name or 'unnamed'}) is not one this tool sizes")
    return {"asym": asym_name, "sig_bytes": ASYM_SIG[asym_name][0],
            "openssl_digest": ASYM_SIG[asym_name][1],
            "hash": hash_name, "hash_bytes": hash_bytes}


def build(seg: list[dict]) -> dict:
    """One connection -> the M1M2 the first CHALLENGE_AUTH in it was signed over."""
    codes = [m["code"] for m in seg]
    for bad, why in ((ERROR, "an ERROR response"),
                     (CHUNK_SEND, "a chunking exchange"),
                     (CHUNK_GET, "a chunking exchange")):
        if bad in codes:
            raise Refused(f"{why} is in this connection and this tool does not "
                          "model its effect on the transcript")
    if CHALLENGE not in codes:
        raise Refused("no CHALLENGE in this connection")

    alg = negotiated(seg)

    # A, in the order the specification fixes rather than the order they were
    # captured in. They are the same order; requiring it is what notices when
    # they are not.
    a_msgs = []
    want = list(A_SEQUENCE)
    for m in seg:
        if want and m["code"] == want[0]:
            a_msgs.append(m)
            want.pop(0)
    if want:
        raise Refused("the Version-Capabilities-Algorithms exchange is "
                      f"incomplete: missing code 0x{want[0]:02x}")

    first_challenge = next(i for i, m in enumerate(seg) if m["code"] == CHALLENGE)
    if len(seg) <= first_challenge + 1 or seg[first_challenge + 1]["code"] != CHALLENGE_AUTH:
        raise Refused("the message after CHALLENGE is not CHALLENGE_AUTH")

    chal = seg[first_challenge]
    auth = seg[first_challenge + 1]
    version = auth["version"]
    if version > 0x11:
        raise Refused(f"SPDM 0x{version:02x} signs over a 1.2 signing context "
                      "prefix, which this tool does not build")

    b_msgs = [m for m in seg[:first_challenge] if m["code"] in B_CODES]

    # -- where the signature starts, by closure rather than by assumption ----
    H = alg["hash_bytes"]
    msh = 0 if chal["bytes"][3] == 0 else H
    fixed = 4 + H + SPDM_NONCE_SIZE + msh
    body = auth["bytes"]
    if len(body) < fixed + 2:
        raise Refused(f"a {len(body)}-byte CHALLENGE_AUTH cannot hold "
                      f"{fixed} bytes of fixed fields and an OpaqueDataLength")
    opaque = int.from_bytes(body[fixed:fixed + 2], "little")
    sig_off = fixed + 2 + opaque
    if version >= 0x13:
        sig_off += SPDM_REQ_CONTEXT_SIZE
    left = len(body) - sig_off
    if left != alg["sig_bytes"]:
        raise Refused(
            f"the bytes after OpaqueData are {left} and {alg['asym']} signs "
            f"{alg['sig_bytes']}: the layout did not close, so the signature "
            "offset is not known and nothing is verified")

    m1m2 = b"".join(m["bytes"] for m in a_msgs) \
         + b"".join(m["bytes"] for m in b_msgs) \
         + chal["bytes"] + body[:sig_off]

    return {
        "packet": auth["packet"],
        "spdm_version": f"{version >> 4}.{version & 0xF}",
        "slot": chal["bytes"][2] & 0x0F,
        "measurement_summary_hash_type": f"0x{chal['bytes'][3]:02x}",
        "fetched_digests": any(m["code"] == DIGESTS for m in b_msgs),
        "fetched_certificate": any(m["code"] == CERTIFICATE for m in b_msgs),
        "algorithms": alg,
        "a_bytes": sum(len(m["bytes"]) for m in a_msgs),
        "b_bytes": sum(len(m["bytes"]) for m in b_msgs),
        "c_bytes": len(chal["bytes"]) + sig_off,
        "m1m2_bytes": len(m1m2),
        "m1m2": m1m2,
        "signature": body[sig_off:],
        "opaque_data_length": opaque,
    }


# ------------------------------------------------------------- the openssl --

def raw_to_der(sig: bytes) -> bytes:
    """r||s, fixed width and big endian, as the DER SEQUENCE OpenSSL expects."""
    half = len(sig) // 2

    def integer(v: bytes) -> bytes:
        v = v.lstrip(b"\x00") or b"\x00"
        if v[0] & 0x80:
            v = b"\x00" + v
        return bytes([0x02, len(v)]) + v

    body = integer(sig[:half]) + integer(sig[half:])
    if len(body) < 0x80:
        return bytes([0x30, len(body)]) + body
    return bytes([0x30, 0x81, len(body)]) + body


def openssl_verify(m1m2: bytes, sig: bytes, leaf_der: bytes, digest: str) -> tuple[bool, str]:
    with tempfile.TemporaryDirectory() as td:
        d = pathlib.Path(td)
        (d / "leaf.der").write_bytes(leaf_der)
        (d / "m1m2.bin").write_bytes(m1m2)
        (d / "sig.der").write_bytes(raw_to_der(sig))
        r = subprocess.run(
            ["openssl", "x509", "-in", "leaf.der", "-inform", "DER",
             "-pubkey", "-noout"], cwd=d, capture_output=True, text=True)
        if r.returncode != 0:
            return False, f"openssl x509 could not read the leaf: {r.stderr.strip()}"
        (d / "pub.pem").write_text(r.stdout)
        r = subprocess.run(
            ["openssl", "dgst", f"-{digest}", "-verify", "pub.pem",
             "-signature", "sig.der", "m1m2.bin"],
            cwd=d, capture_output=True, text=True)
        out = (r.stdout + r.stderr).strip()
        return r.returncode == 0 and "Verified OK" in r.stdout, out


# ------------------------------------------------------------------ report --

def analyse(pcap: pathlib.Path) -> dict:
    msgs = read_messages(pcap)
    chains = certificate_chains(msgs)

    results = []
    for seg in segments(msgs):
        try:
            b = build(seg)
        except (Refused, StopIteration):
            continue
        chain = chains.get(b["slot"])
        row = {k: v for k, v in b.items() if k not in ("m1m2", "signature")}
        if chain is None:
            row["verified"] = None
            row["detail"] = (f"no complete certificate chain for slot {b['slot']} "
                             "anywhere in this capture")
            results.append(row)
            continue
        try:
            leaf = leaf_certificate(chain, b["algorithms"]["hash_bytes"])
        except Refused as why:
            row["verified"] = None
            row["detail"] = str(why)
            results.append(row)
            continue
        okay, detail = openssl_verify(b["m1m2"], b["signature"], leaf,
                                      b["algorithms"]["openssl_digest"])
        row["verified"] = okay
        row["detail"] = detail
        row["leaf_sha256"] = hashlib.sha256(leaf).hexdigest()[:16]
        results.append(row)

    calibration = [r for r in results if r["fetched_certificate"]]
    disputed = [r for r in results if not r["fetched_certificate"]]
    return {
        "file": str(pcap),
        "connections": len(segments(msgs)),
        "verifiable_first_challenges": len(results),
        "calibration": calibration,
        "disputed": disputed,
        "results": results,
    }


def report(doc: dict) -> int:
    print(f"  {doc['file']}")
    print(f"  connections in the capture                  {doc['connections']}")
    print(f"  first CHALLENGE_AUTH this tool can rebuild  "
          f"{doc['verifiable_first_challenges']}")

    cal = doc["calibration"]
    dis = doc["disputed"]
    if not cal:
        print("  FAIL   no connection fetched a certificate, so there is nothing "
              "to calibrate against and no verdict is offered")
        return 1

    cal_ok = sum(1 for r in cal if r["verified"] is True)
    print(f"\n  calibration -- connections that DID fetch the certificate, which "
          f"the suite passes")
    print(f"    {cal_ok} of {len(cal)} verify")
    for r in cal[:3]:
        print(f"      packet {r['packet']:<6} SPDM {r['spdm_version']} slot "
              f"{r['slot']}  {r['algorithms']['asym']}/{r['algorithms']['hash']}  "
              f"M1M2 {r['m1m2_bytes']} B ({r['a_bytes']}+{r['b_bytes']}+"
              f"{r['c_bytes']})  -> {r['verified']}")
    if cal_ok != len(cal):
        print("  FAIL   this tool cannot verify a signature the suite accepts, so "
              "its model of the transcript is wrong and it offers no verdict on "
              "the disputed ones")
        for r in cal:
            if r["verified"] is not True:
                print(f"      packet {r['packet']}: {r['detail']}")
        return 1
    print("    ok   the transcript model reproduces a signature the suite accepts")

    if not dis:
        print("\n  no connection omitted the certificate fetch: nothing disputed "
              "in this capture")
        return 0

    dis_ok = sum(1 for r in dis if r["verified"] is True)
    print(f"\n  disputed -- connections that did NOT fetch the certificate, which "
          f"the suite fails at \"response signature\"")
    print(f"    {dis_ok} of {len(dis)} verify")
    for r in dis:
        print(f"      packet {r['packet']:<6} SPDM {r['spdm_version']} slot "
              f"{r['slot']}  M1M2 {r['m1m2_bytes']} B ({r['a_bytes']}+"
              f"{r['b_bytes']}+{r['c_bytes']})  -> {r['verified']}")
    if dis_ok == len(dis):
        print("\n    The responder's signatures are good. The suite's FAIL is "
              "about an input the suite itself did not fetch, not about the "
              "device.")
    elif dis_ok == 0:
        print("\n    The responder's signatures do NOT verify here either. The "
              "suite's FAIL stands and the root cause is in the responder.")
    else:
        print("\n    Mixed, which neither hypothesis predicts. Do not quote this "
              "until it is explained.")
    return 0


# --------------------------------------------------------------- self test --

def selftest() -> int:
    bad = 0

    def ok(cond, msg):
        nonlocal bad
        print(("  ok   " if cond else "  FAIL ") + msg)
        if not cond:
            bad = 1

    print("-- r||s becomes the DER OpenSSL wants")
    # 0x02 0x30 <48> twice is 100 bytes of body, so the SEQUENCE header is
    # 30 64. Getting this expectation wrong once is why it is written as the
    # arithmetic rather than as a number.
    ok(raw_to_der(b"\x01" * 48 + b"\x02" * 48)[:2] == bytes([0x30, 2 * (2 + 48)]),
       "a P-384 pair with no high bits is a 100-byte SEQUENCE body")
    d = raw_to_der(b"\xff" * 48 + b"\x01" * 48)
    ok(d[2:4] == b"\x02\x31" and d[4] == 0x00,
       "a high bit gets the leading zero that keeps the INTEGER positive")
    d = raw_to_der(b"\x00" * 47 + b"\x05" + b"\x01" * 48)
    ok(d[2:5] == b"\x02\x01\x05",
       "leading zeros are stripped rather than encoded")

    print("-- the DER walk splits by length, not by searching for 0x30")
    a = bytes([0x30, 0x03, 0x30, 0x01, 0x00])
    b = bytes([0x30, 0x02, 0xAA, 0xBB])
    ok(der_certificates(a + b) == [a, b],
       "a SEQUENCE whose body contains 0x30 is one certificate, not two")
    long = bytes([0x30, 0x82, 0x01, 0x00]) + b"\x00" * 256
    ok(der_certificates(long) == [long], "a two-byte length is read as one")

    print("-- the chain header is skipped by arithmetic")
    certs = bytes([0x30, 0x02, 0x11, 0x22]) + bytes([0x30, 0x02, 0x33, 0x44])
    root = bytes([0x30] * 48)          # a root hash that is all 0x30
    chain = (len(certs) + 4 + 48).to_bytes(2, "little") + b"\x00\x00" + root + certs
    ok(leaf_certificate(chain, 48) == bytes([0x30, 0x02, 0x33, 0x44]),
       "the leaf is the LAST certificate, and a 0x30-filled root hash is skipped")

    # The two rejections have to be reachable independently. A trailing byte
    # alone trips the LENGTH check, not the tiling one, so the second mutation
    # keeps cert_chain.Length honest and leaves a byte the DER walk cannot
    # account for. Without that, the tiling check would be unreachable and
    # would still look tested -- docs/roadmap.md standing rule 13.
    def _trailing_byte(c: bytes) -> bytes:
        grown = c + b"\x00"
        return len(grown).to_bytes(2, "little") + grown[2:]

    for name, mutate, why in (
        ("length disagrees", lambda c: (len(c) + 1).to_bytes(2, "little") + c[2:],
         "cert_chain.Length"),
        ("certificates do not tile", _trailing_byte, "tile"),
    ):
        try:
            leaf_certificate(mutate(chain), 48)
            ok(False, f"{name}: accepted, and should not have been")
        except Refused as said:
            ok(why in str(said), f"{name}: refused -- {said}")

    print("-- and a signature over the wrong bytes does not verify")
    have_openssl = subprocess.run(["openssl", "version"],
                                  capture_output=True).returncode == 0
    if not have_openssl:
        ok(False, "openssl is not on PATH, so the end-to-end check cannot run")
        return bad
    with tempfile.TemporaryDirectory() as td:
        d = pathlib.Path(td)
        subprocess.run(["openssl", "ecparam", "-name", "secp384r1", "-genkey",
                        "-noout", "-out", "k.pem"], cwd=d, capture_output=True)
        subprocess.run(["openssl", "req", "-new", "-x509", "-key", "k.pem",
                        "-subj", "/CN=selftest", "-days", "1", "-sha384",
                        "-outform", "DER", "-out", "c.der"],
                       cwd=d, capture_output=True)
        (d / "msg.bin").write_bytes(b"the transcript")
        subprocess.run(["openssl", "dgst", "-sha384", "-sign", "k.pem",
                        "-out", "sig.der", "msg.bin"], cwd=d, capture_output=True)
        der = (d / "sig.der").read_bytes()
        leaf = (d / "c.der").read_bytes()

        # DER back to r||s, so the same path this file uses on a capture is the
        # one under test rather than a shortcut around it.
        body = der[2:] if der[1] < 0x80 else der[3:]
        rl = body[1]
        r_i = body[2:2 + rl].rjust(48, b"\x00")[-48:]
        sl = body[2 + rl + 1]
        s_i = body[2 + rl + 2:2 + rl + 2 + sl].rjust(48, b"\x00")[-48:]
        raw = r_i + s_i

        good, _ = openssl_verify(b"the transcript", raw, leaf, "sha384")
        ok(good, "a good signature over the right transcript verifies")
        bad_msg, _ = openssl_verify(b"the transcripT", raw, leaf, "sha384")
        ok(not bad_msg, "the same signature over a transcript one bit different "
                        "does not")
        flipped = bytearray(raw)
        flipped[-1] ^= 0x01
        bad_sig, _ = openssl_verify(b"the transcript", bytes(flipped), leaf, "sha384")
        ok(not bad_sig, "a signature with one byte changed does not")

    return bad


def main() -> int:
    ap = argparse.ArgumentParser(
        description="verify CHALLENGE_AUTH signatures out of a capture")
    ap.add_argument("pcap", type=pathlib.Path, nargs="?")
    ap.add_argument("--json", type=pathlib.Path)
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()

    if args.self_test:
        return selftest()
    if not args.pcap:
        ap.print_help()
        return 2

    try:
        doc = analyse(args.pcap)
    except Refused as why:
        print(f"  REFUSED  {args.pcap}: {why}", file=sys.stderr)
        return 1
    if args.json:
        args.json.write_text(json.dumps(doc, indent=2) + "\n", encoding="utf-8")
    return report(doc)


if __name__ == "__main__":
    sys.exit(main())

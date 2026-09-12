#!/usr/bin/env python3
"""CBOR and COSE_Sign1, in the subset a signed CoRIM needs, with no packages.

    python3 rats/cose.py selftest
    python3 rats/cose.py sign   -i payload.cbor --key K.key --kid 42 -o signed.corim
    python3 rats/cose.py verify -i signed.corim --key K.pub          -o payload.cbor
    python3 rats/cose.py inspect -i signed.corim

Why this file exists rather than `pip install pycose`
-----------------------------------------------------
Three reasons, in the order they were discovered rather than the order they
matter:

1. **The published recipe does not run.** DMTF ships the tools this project's
   plan is built on — `spdm_emu/spdm_device_verifier_tool/` — and their
   `requirements.txt` pins no upper bounds. Installed today, `cbor2` resolves
   to 6.1.4, which decodes the contents of a `CBORTag` as *immutable*
   containers; `pycose`'s `CoseMessage.decode()` requires `isinstance(obj,
   list)` and raises. The measured consequence is that **pycose cannot decode
   its own `encode()` output** — 79 bytes, byte-identical through a round trip,
   `TypeError: Bytes cannot be decoded as COSE message`. Pinning `cbor2==5.6.5`
   fixes it. See `docs/rats-pipeline.md` for the bisection.

2. **A second, independent defect sits behind the first.** With `cbor2` pinned,
   `CoRimTool.py verify` still refuses every signature it produced, because it
   builds the verification key as `EC2Key(crv='P_256', d=<the 64-byte public
   point>)` — the public key passed where the private scalar goes. One line.
   `docs/upstream/README.md` carries the report.

3. **CI has neither.** The job that matters in this repository is the one that
   turns red when a tampered measurement stops being rejected, and it runs on a
   GitHub runner with no `spdm-emu` checkout, no WSL, and no local patches. A
   verifier that cannot run there is a verifier that never fails.

So this file owns the CI path, and DMTF's tools are cross-checked against it
once, locally, with the results committed as fixtures — `rats/interop/`. That
is the same arrangement `pcapcount.py` and `fields.py` already have: two routes
to the same quantity, required to agree. `docs/roadmap.md` standing rule 12.

What is NOT here
----------------
**No cryptography.** Signing and verifying are `openssl` subprocesses, because
this repository already depends on `openssl` for `certs/`, and because an
ECDSA implementation written here would be a second one to get right with
nothing checking it. What this file does is the *encoding* either side of the
signature: build the exact byte string COSE says is signed, hand it to
`openssl`, and convert between OpenSSL's DER `(r, s)` and COSE's fixed-width
`r ‖ s`.

That conversion is the only place a mistake here can be silent, so it is the
one `selftest` attacks hardest.

Deterministic encoding, and the one place it is deliberately not
----------------------------------------------------------------
Integers take their shortest form and strings are definite-length, which is
RFC 8949 §4.2.1 core deterministic encoding. Map keys are **not** sorted by
default, and that is not an oversight: `cbor2.dumps()` — which DMTF's
`CoRimTool.py json_to_cbor` calls — emits keys in insertion order, and this
project's interoperability check feeds the *same JSON file* to both tools and
requires the *same bytes* out. Sorting here would make that comparison
impossible to pass for a reason that has nothing to do with either tool being
wrong. `--sort-keys` is available and nothing in this project uses it.

Exit codes: 0 ok · 1 verification failed · 2 bad arguments or malformed input

★ 1 is a *verdict*, not an error. A verifier whose only channel is stdout is a
verifier no shell script can use, and that is a defect this project found
upstream before writing this line — `CoRimTool.py verify` prints "Signature
verification failed" and exits 0.
"""

from __future__ import annotations

import argparse
import contextlib
import io
import os
import subprocess
import sys
import tempfile
from pathlib import Path

# --------------------------------------------------------------- CBOR -------
#
# RFC 8949. Major type in the top three bits, argument in the low five:
#
#   0 unsigned    1 negative    2 bytes    3 text
#   4 array       5 map         6 tag      7 simple/float
#
# The low five bits are the value itself when below 24, and otherwise say how
# many bytes of big-endian argument follow: 24 -> 1, 25 -> 2, 26 -> 4, 27 -> 8.
# 31 means indefinite length, which this file neither writes nor accepts —
# a CoRIM has no use for it, and accepting it would mean two encodings of the
# same document, which defeats the byte comparison this file exists to support.

CBOR_UINT, CBOR_NEGINT, CBOR_BYTES, CBOR_TEXT = 0, 1, 2, 3
CBOR_ARRAY, CBOR_MAP, CBOR_TAG, CBOR_SIMPLE = 4, 5, 6, 7


class Tag:
    """A CBOR tag: a number and the single item it decorates."""

    __slots__ = ("tag", "value")

    def __init__(self, tag: int, value):
        self.tag = tag
        self.value = value

    def __repr__(self):
        return f"Tag({self.tag}, {self.value!r})"

    def __eq__(self, other):
        return (isinstance(other, Tag)
                and self.tag == other.tag and self.value == other.value)


class CborError(ValueError):
    pass


def _head(major: int, arg: int) -> bytes:
    if arg < 0:
        raise CborError("negative argument in a CBOR head")
    if arg < 24:
        return bytes([major << 5 | arg])
    if arg < 0x100:
        return bytes([major << 5 | 24, arg])
    if arg < 0x10000:
        return bytes([major << 5 | 25]) + arg.to_bytes(2, "big")
    if arg < 0x100000000:
        return bytes([major << 5 | 26]) + arg.to_bytes(4, "big")
    if arg < 0x10000000000000000:
        return bytes([major << 5 | 27]) + arg.to_bytes(8, "big")
    raise CborError(f"{arg} does not fit in a 64-bit CBOR argument")


def dumps(obj, sort_keys: bool = False) -> bytes:
    """Encode one item. See the module docstring on why keys are not sorted."""
    if obj is True:
        return b"\xf5"
    if obj is False:
        return b"\xf4"
    if obj is None:
        return b"\xf6"
    if isinstance(obj, Tag):
        return _head(CBOR_TAG, obj.tag) + dumps(obj.value, sort_keys)
    if isinstance(obj, int):
        return (_head(CBOR_UINT, obj) if obj >= 0
                else _head(CBOR_NEGINT, -1 - obj))
    if isinstance(obj, (bytes, bytearray)):
        return _head(CBOR_BYTES, len(obj)) + bytes(obj)
    if isinstance(obj, str):
        u = obj.encode("utf-8")
        return _head(CBOR_TEXT, len(u)) + u
    if isinstance(obj, (list, tuple)):
        return _head(CBOR_ARRAY, len(obj)) + b"".join(
            dumps(i, sort_keys) for i in obj)
    if isinstance(obj, dict):
        pairs = [(dumps(k, sort_keys), dumps(v, sort_keys))
                 for k, v in obj.items()]
        if sort_keys:
            pairs.sort(key=lambda kv: kv[0])
        return _head(CBOR_MAP, len(pairs)) + b"".join(k + v for k, v in pairs)
    raise CborError(f"cannot encode {type(obj).__name__} as CBOR")


def _read_arg(buf: bytes, off: int) -> tuple[int, int, int]:
    """Return (major, argument, offset after the head)."""
    if off >= len(buf):
        raise CborError(f"truncated at {off}: expected an item")
    ib = buf[off]
    major, low = ib >> 5, ib & 0x1F
    off += 1
    if low < 24:
        return major, low, off
    if low == 31:
        raise CborError(f"indefinite length at {off - 1} is not accepted here")
    if low > 27:
        raise CborError(f"reserved additional information {low} at {off - 1}")
    n = 1 << (low - 24)
    if off + n > len(buf):
        raise CborError(f"truncated at {off}: {n} argument byte(s) needed")
    return major, int.from_bytes(buf[off:off + n], "big"), off + n


def _load(buf: bytes, off: int):
    major, arg, off = _read_arg(buf, off)
    if major == CBOR_UINT:
        return arg, off
    if major == CBOR_NEGINT:
        return -1 - arg, off
    if major in (CBOR_BYTES, CBOR_TEXT):
        if off + arg > len(buf):
            raise CborError(f"truncated at {off}: {arg} byte(s) declared")
        raw = buf[off:off + arg]
        return (bytes(raw) if major == CBOR_BYTES
                else raw.decode("utf-8")), off + arg
    if major == CBOR_ARRAY:
        out = []
        for _ in range(arg):
            item, off = _load(buf, off)
            out.append(item)
        return out, off
    if major == CBOR_MAP:
        out = {}
        for _ in range(arg):
            k, off = _load(buf, off)
            v, off = _load(buf, off)
            if isinstance(k, (list, dict)):
                raise CborError("a map key that is itself a container")
            out[k] = v
        return out, off
    if major == CBOR_TAG:
        inner, off = _load(buf, off)
        return Tag(arg, inner), off
    # major 7: only the three simple values this file has a use for.
    if arg == 20:
        return False, off
    if arg == 21:
        return True, off
    if arg == 22:
        return None, off
    raise CborError(f"simple value {arg} is not supported")


def loads(buf: bytes, allow_trailing: bool = False):
    item, off = _load(bytes(buf), 0)
    if off != len(buf) and not allow_trailing:
        raise CborError(f"{len(buf) - off} trailing byte(s) after the item")
    return item


# ------------------------------------------------------ DER <-> raw r||s ----
#
# OpenSSL emits an ECDSA signature as DER SEQUENCE { INTEGER r, INTEGER s }.
# COSE (RFC 8152 §8.1) carries it as the two integers concatenated, each padded
# on the left to the curve's byte length. The conversion is short, it is the
# only arithmetic in this file, and it has three ways of being quietly wrong:
#
#   * a DER INTEGER is signed, so a value whose top bit is set is prefixed with
#     0x00. Copying the DER bytes straight into the fixed-width field makes a
#     33-byte r roughly half the time.
#   * going the other way, a raw half whose top bit is set needs that 0x00 put
#     back, or OpenSSL reads a negative integer and rejects a valid signature.
#   * a raw half with leading zeros must have them *stripped* before the DER
#     INTEGER is built, because DER forbids a non-minimal integer, and OpenSSL's
#     parser is strict about it.
#
# Each of the three is a case in `selftest`, because each one fails on about
# half of all signatures and passes on the other half — the single worst
# failure distribution a check can have.

def _der_int(v: bytes) -> bytes:
    v = v.lstrip(b"\x00") or b"\x00"
    if v[0] & 0x80:
        v = b"\x00" + v
    return b"\x02" + bytes([len(v)]) + v


def _der_len(n: int) -> bytes:
    return bytes([n]) if n < 0x80 else b"\x81" + bytes([n])


def raw_to_der(raw: bytes) -> bytes:
    if len(raw) % 2:
        raise ValueError(f"a raw ECDSA signature has an even length, not {len(raw)}")
    half = len(raw) // 2
    body = _der_int(raw[:half]) + _der_int(raw[half:])
    return b"\x30" + _der_len(len(body)) + body


def der_to_raw(der: bytes, half: int) -> bytes:
    if not der or der[0] != 0x30:
        raise ValueError("not a DER SEQUENCE")
    off = 2 if der[1] < 0x80 else 3
    out = b""
    for _ in range(2):
        if der[off] != 0x02:
            raise ValueError("not a DER INTEGER inside the signature")
        n = der[off + 1]
        v = der[off + 2:off + 2 + n].lstrip(b"\x00")
        if len(v) > half:
            raise ValueError(f"an integer of {len(v)} bytes in a {half}-byte field")
        out += v.rjust(half, b"\x00")
        off += 2 + n
    return out


# ------------------------------------------------------------ COSE_Sign1 ----
#
#   COSE_Sign1 = [ protected: bstr .cbor header_map,
#                  unprotected: header_map,
#                  payload: bstr / nil,
#                  signature: bstr ]
#
# tagged #6.18. What is signed is not the message: it is
#
#   Sig_structure = [ "Signature1", body_protected, external_aad, payload ]
#
# encoded as CBOR. The protected header goes in as the *byte string that was
# transmitted*, never as a re-encoding of the parsed map — two encoders that
# disagree about map order would then produce a signature neither can verify,
# and the failure would look like a bad key.

COSE_SIGN1_TAG = 18
ALG_ES256 = -7
HDR_ALG, HDR_CONTENT_TYPE, HDR_KID, HDR_META = 1, 3, 4, 8

# draft-ietf-rats-corim: a signed manifest is #6.500(#6.502(COSE-Sign1-corim)),
# not a bare COSE_Sign1. DMTF's CoRimTool.py writes those two tags and this
# file did not, which is how the first interoperability run found it: each tool
# rejected the other's file before looking at a signature. Writing them is
# opt-in (`--corim`); reading them is automatic, because a file that is
# unambiguously one or the other should not need to be told apart by a flag.
CORIM_TAG = 500
SIGNED_CORIM_TAG = 502

CURVE_HALF = {ALG_ES256: 32}
ALG_DIGEST = {ALG_ES256: "sha256"}
ALG_NAME = {ALG_ES256: "ES256"}


def sig_structure(protected: bytes, payload: bytes, aad: bytes = b"") -> bytes:
    return dumps(["Signature1", protected, aad, payload])


def _openssl(args: list[str], stdin: bytes | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(["openssl", *args], input=stdin,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          check=False)


def sign1(payload: bytes, protected_map: dict, key_path: Path,
          alg: int = ALG_ES256, corim: bool = False) -> bytes:
    """Produce a tagged COSE_Sign1 over `payload`, optionally as a CoRIM."""
    protected_map = dict(protected_map)
    protected_map[HDR_ALG] = alg
    protected = dumps(protected_map)
    tbs = sig_structure(protected, payload)

    r = _openssl(["dgst", f"-{ALG_DIGEST[alg]}", "-sign", str(key_path)], tbs)
    if r.returncode != 0:
        raise RuntimeError("openssl could not sign: "
                           + r.stderr.decode("utf-8", "replace").strip())
    raw = der_to_raw(r.stdout, CURVE_HALF[alg])
    msg = Tag(COSE_SIGN1_TAG, [protected, {}, payload, raw])
    return dumps(Tag(CORIM_TAG, Tag(SIGNED_CORIM_TAG, msg)) if corim else msg)


def parse1(blob: bytes) -> tuple[bytes, dict, bytes, bytes]:
    """Split a tagged COSE_Sign1 into (protected bstr, header map, payload, sig).

    Accepts a bare #6.18 and a CoRIM-wrapped #6.500(#6.502(#6.18)) alike.
    """
    item = loads(blob)
    if isinstance(item, Tag) and item.tag == CORIM_TAG:
        item = item.value
        if not isinstance(item, Tag) or item.tag != SIGNED_CORIM_TAG:
            raise CborError("a corim tag that does not hold a signed-corim "
                            "(#6.502)")
        item = item.value
    if not isinstance(item, Tag) or item.tag != COSE_SIGN1_TAG:
        raise CborError(f"not a tagged COSE_Sign1 (tag "
                        f"{item.tag if isinstance(item, Tag) else 'none'})")
    body = item.value
    if not isinstance(body, list) or len(body) != 4:
        raise CborError("a COSE_Sign1 is an array of exactly four items")
    protected, unprotected, payload, signature = body
    for name, v, want in (("protected", protected, bytes),
                          ("payload", payload, bytes),
                          ("signature", signature, bytes),
                          ("unprotected", unprotected, dict)):
        if not isinstance(v, want):
            raise CborError(f"the {name} field is {type(v).__name__}, "
                            f"expected {want.__name__}")
    phdr = loads(protected) if protected else {}
    if not isinstance(phdr, dict):
        raise CborError("the protected header does not hold a map")
    return protected, phdr, payload, signature


def verify1(blob: bytes, pub_path: Path) -> tuple[bytes, dict]:
    """Return (payload, protected header) or raise VerifyFailed."""
    protected, phdr, payload, signature = parse1(blob)
    alg = phdr.get(HDR_ALG)
    if alg not in ALG_DIGEST:
        raise VerifyFailed(f"unsupported or absent alg {alg!r} in the "
                           f"protected header")
    half = CURVE_HALF[alg]
    if len(signature) != 2 * half:
        raise VerifyFailed(f"{ALG_NAME[alg]} signs {2 * half} bytes and this "
                           f"message carries {len(signature)}")

    tbs = sig_structure(protected, payload)
    der = raw_to_der(signature)
    # openssl dgst -verify wants the signature in a file, not on stdin, because
    # stdin is already carrying the data being verified.
    fd, sigfile = tempfile.mkstemp(prefix="cose-sig-")
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(der)
        r = _openssl(["dgst", f"-{ALG_DIGEST[alg]}", "-verify", str(pub_path),
                      "-signature", sigfile], tbs)
    finally:
        os.unlink(sigfile)
    if r.returncode != 0:
        raise VerifyFailed(
            (r.stdout + r.stderr).decode("utf-8", "replace").strip()
            or "openssl rejected the signature")
    return payload, phdr


class VerifyFailed(Exception):
    """The signature did not verify. A verdict, not a malfunction."""


# ---------------------------------------------------------------- CLI -------

def _describe(phdr: dict) -> str:
    bits = []
    alg = phdr.get(HDR_ALG)
    bits.append(f"alg {ALG_NAME.get(alg, alg)}")
    if HDR_KID in phdr:
        kid = phdr[HDR_KID]
        bits.append("kid " + (kid.decode("utf-8", "replace")
                              if isinstance(kid, bytes) else str(kid)))
    if HDR_CONTENT_TYPE in phdr:
        bits.append(str(phdr[HDR_CONTENT_TYPE]))
    return ", ".join(bits)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("sign", help="wrap a payload in a COSE_Sign1")
    s.add_argument("-i", "--input", type=Path, required=True)
    s.add_argument("-o", "--output", type=Path, required=True)
    s.add_argument("--key", type=Path, required=True, help="PEM private key")
    s.add_argument("--kid", required=True, help="key identifier, carried verbatim")
    s.add_argument("--content-type", default="application/rim+cbor")
    s.add_argument("--corim", action="store_true",
                   help="wrap in #6.500(#6.502(...)), which is what a signed "
                        "CoRIM is and what CoRimTool.py writes")

    v = sub.add_parser("verify", help="check a COSE_Sign1 and write its payload")
    v.add_argument("-i", "--input", type=Path, required=True)
    v.add_argument("-o", "--output", type=Path)
    v.add_argument("--key", type=Path, required=True, help="PEM public key")

    n = sub.add_parser("inspect", help="print a COSE_Sign1's shape, no key needed")
    n.add_argument("-i", "--input", type=Path, required=True)

    sub.add_parser("selftest", help="every encoder and conversion, both ways")

    args = ap.parse_args()

    if args.cmd == "selftest":
        return selftest()

    if args.cmd == "sign":
        payload = args.input.read_bytes()
        phdr = {HDR_CONTENT_TYPE: args.content_type,
                HDR_KID: args.kid.encode("utf-8")}
        blob = sign1(payload, phdr, args.key, corim=args.corim)
        args.output.write_bytes(blob)
        phdr[HDR_ALG] = ALG_ES256
        print(f"{args.output}: {len(blob)} bytes, {_describe(phdr)}"
              + (", wrapped as a signed CoRIM" if args.corim else ""))
        return 0

    if args.cmd == "inspect":
        protected, phdr, payload, signature = parse1(args.input.read_bytes())
        print(f"protected : {len(protected)} bytes, {_describe(phdr)}")
        print(f"payload   : {len(payload)} bytes")
        print(f"signature : {len(signature)} bytes")
        return 0

    try:
        payload, phdr = verify1(args.input.read_bytes(), args.key)
    except VerifyFailed as e:
        print(f"signature NOT verified: {e}", file=sys.stderr)
        return 1
    except (CborError, ValueError) as e:
        print(f"malformed: {e}", file=sys.stderr)
        return 2
    if args.output:
        args.output.write_bytes(payload)
    print(f"signature verified: {_describe(phdr)}, payload {len(payload)} bytes")
    return 0


# ------------------------------------------------------------- selftest -----
#
# Standing rule 11: a check is worth what it rejects, and something has to
# prove it rejects. Encoders are the easiest place in a repository to be
# confidently wrong, because a wrong encoder and a matching wrong decoder agree
# with each other forever. So round trips are the weakest test here and are
# only half of it; the other half is fixed vectors from RFC 8949 Appendix A,
# which no code in this file produced.

RFC8949_VECTORS = [
    (0, "00"), (1, "01"), (10, "0a"), (23, "17"), (24, "1818"), (25, "1819"),
    (100, "1864"), (1000, "1903e8"), (1000000, "1a000f4240"),
    (-1, "20"), (-10, "29"), (-100, "3863"), (-1000, "3903e7"),
    (b"", "40"), (b"\x01\x02\x03\x04", "4401020304"),
    ("", "60"), ("a", "6161"), ("IETF", "6449455446"),
    ("ü", "62c3bc"), ("水", "63e6b0b4"),
    ([], "80"), ([1, 2, 3], "83010203"),
    ([1, [2, 3], [4, 5]], "8301820203820405"),
    ({}, "a0"), ({1: 2, 3: 4}, "a201020304"),
    ({"a": 1, "b": [2, 3]}, "a26161016162820203"),
    (["a", {"b": "c"}], "826161a161626163"),
    (True, "f5"), (False, "f4"), (None, "f6"),
    (Tag(1, 1363896240), "c11a514b67b0"),
    ([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
      21, 22, 23, 24, 25], "98190102030405060708090a0b0c0d0e0f101112131415161718181819"),
]


def selftest() -> int:
    fails = 0
    checks = 0

    def eq(got, want, what):
        nonlocal fails, checks
        checks += 1
        if got != want:
            fails += 1
            print(f"  FAIL {what}\n        got  {got!r}\n        want {want!r}")

    def refuses(fn, what):
        nonlocal fails, checks
        checks += 1
        try:
            fn()
        except (CborError, ValueError):
            return
        fails += 1
        print(f"  FAIL {what}: accepted, and should not have")

    print("RFC 8949 Appendix A vectors, encode and decode")
    for value, hexs in RFC8949_VECTORS:
        want = bytes.fromhex(hexs)
        eq(dumps(value), want, f"encode {value!r}")
        eq(loads(want), value, f"decode {hexs}")

    print("encodings this file must refuse")
    refuses(lambda: loads(bytes.fromhex("9f018200030405ff")), "indefinite-length array")
    refuses(lambda: loads(bytes.fromhex("5f42010243030405ff")), "indefinite-length bytes")
    refuses(lambda: loads(bytes.fromhex("83010203" "04")), "an item with trailing bytes")
    refuses(lambda: loads(bytes.fromhex("830102")), "an array shorter than it declares")
    refuses(lambda: loads(bytes.fromhex("1c")), "reserved additional information 28")
    refuses(lambda: loads(bytes.fromhex("4401")), "a byte string shorter than it declares")
    refuses(lambda: dumps(1.5), "a float, which nothing here needs")
    refuses(lambda: dumps(2 ** 64), "an integer too large for a CBOR argument")

    print("map key order is preserved, and sorting is available and unused")
    eq(dumps({3: 0, 1: 0}), bytes.fromhex("a2030001 00".replace(" ", "")),
       "insertion order")
    eq(dumps({3: 0, 1: 0}, sort_keys=True), bytes.fromhex("a2010003 00".replace(" ", "")),
       "sorted order")

    print("DER <-> raw r||s, including every case that fails half the time")
    half = 32
    cases = [
        (b"\x01" * 32 + b"\x02" * 32, "both halves ordinary"),
        (b"\x80" + b"\x00" * 31 + b"\x7f" + b"\xff" * 31, "r needs a 0x00, s does not"),
        (b"\x00" * 31 + b"\x01" + b"\x00" * 31 + b"\x02", "both halves have leading zeros"),
        (b"\xff" * 32 + b"\xff" * 32, "both halves need a 0x00"),
        (b"\x00" * 32 + b"\x00" * 32, "both halves are zero"),
    ]
    for raw, what in cases:
        der = raw_to_der(raw)
        eq(der[0], 0x30, f"{what}: SEQUENCE tag")
        eq(der_to_raw(der, half), raw, f"{what}: round trip")
        # DER integers must be minimal, or OpenSSL refuses the signature.
        off = 2 if der[1] < 0x80 else 3
        for _ in range(2):
            n = der[off + 1]
            body = der[off + 2:off + 2 + n]
            checks += 1
            if len(body) > 1 and body[0] == 0 and not (body[1] & 0x80):
                fails += 1
                print(f"  FAIL {what}: a non-minimal DER INTEGER {body.hex()}")
            off += 2 + n
    refuses(lambda: raw_to_der(b"\x01" * 31), "an odd-length raw signature")
    refuses(lambda: der_to_raw(b"\x02\x01\x00", 32), "DER that is not a SEQUENCE")
    refuses(lambda: der_to_raw(raw_to_der(b"\xff" * 64), 16),
            "a 32-byte integer poured into a 16-byte field")

    print("Sig_structure is the four items COSE says, in order")
    eq(sig_structure(b"\xa1\x01\x26", b"hi", b""),
       dumps(["Signature1", b"\xa1\x01\x26", b"", b"hi"]),
       "Sig_structure shape")

    print("sign and verify against openssl, and every way of breaking it")
    if not _have_openssl():
        print("  --   openssl not on PATH; the signature half is skipped")
    else:
        with tempfile.TemporaryDirectory(prefix="cose-selftest-") as d:
            d = Path(d)
            key, pub, other, otherpub = (d / "k.key", d / "k.pub",
                                         d / "o.key", d / "o.pub")
            for k, p in ((key, pub), (other, otherpub)):
                _openssl(["ecparam", "-name", "prime256v1", "-genkey",
                          "-noout", "-out", str(k)])
                _openssl(["ec", "-in", str(k), "-pubout", "-out", str(p)])

            payload = dumps({"measurement": "spdm", "n": 528})
            blob = sign1(payload, {HDR_KID: b"42",
                                   HDR_CONTENT_TYPE: "application/rim+cbor"}, key)
            got, phdr = verify1(blob, pub)
            eq(got, payload, "a signature this file produced verifies")
            eq(phdr.get(HDR_KID), b"42", "the kid survives the round trip")

            # Five breaks, and they must be refused for five different reasons:
            # a wrong key, a changed payload, a changed protected header, a
            # changed signature, and a signature of the wrong length. Standing
            # rule 13 — four breaks caught by one check is one check.
            protected, _, pl, sig = parse1(blob)
            breaks = [
                ("a signature from a different key",
                 lambda: verify1(blob, otherpub)),
                ("a payload changed after signing",
                 lambda: verify1(dumps(Tag(COSE_SIGN1_TAG,
                                           [protected, {}, pl + b"\x00", sig])), pub)),
                ("a protected header changed after signing",
                 lambda: verify1(dumps(Tag(COSE_SIGN1_TAG,
                                           [dumps({HDR_ALG: ALG_ES256}), {}, pl, sig])), pub)),
                ("one bit of the signature flipped",
                 lambda: verify1(dumps(Tag(COSE_SIGN1_TAG,
                                           [protected, {}, pl,
                                            bytes([sig[0] ^ 1]) + sig[1:]])), pub)),
                ("a signature of the wrong length",
                 lambda: verify1(dumps(Tag(COSE_SIGN1_TAG,
                                           [protected, {}, pl, sig[:-1]])), pub)),
            ]
            for what, fn in breaks:
                checks += 1
                try:
                    fn()
                except VerifyFailed:
                    continue
                except (CborError, ValueError) as e:
                    print(f"  FAIL {what}: refused, but as malformed input ({e}) "
                          f"rather than as a failed verification")
                    fails += 1
                    continue
                fails += 1
                print(f"  FAIL {what}: VERIFIED, and must not have")
            print(f"    {len(breaks)} break(s), all refused as failed verification")

            # And the failure this project found upstream, reproduced here so
            # that a regression toward it is a failing build rather than a
            # rediscovery: a verifier must not report success by exit code
            # while printing a failure.
            checks += 1
            buf = io.StringIO()
            with contextlib.redirect_stderr(buf):
                rc = main_with(["verify", "-i", str(_write(d / "bad.corim",
                                dumps(Tag(COSE_SIGN1_TAG,
                                          [protected, {}, pl, bytes([sig[0] ^ 1]) + sig[1:]])))),
                                "--key", str(pub)])
            if rc == 0:
                fails += 1
                print("  FAIL a failed verification exited 0")

    print()
    print(f"{checks} checks, {fails} failed")
    return 1 if fails else 0


def _write(path: Path, blob: bytes) -> Path:
    path.write_bytes(blob)
    return path


def main_with(argv: list[str]) -> int:
    saved, sys.argv = sys.argv, ["cose.py", *argv]
    try:
        return main()
    finally:
        sys.argv = saved


def _have_openssl() -> bool:
    try:
        return _openssl(["version"]).returncode == 0
    except FileNotFoundError:
        return False


if __name__ == "__main__":
    raise SystemExit(main())

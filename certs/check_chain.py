#!/usr/bin/env python3
"""Check a three-layer SPDM certificate chain, from its DER rather than its rendering.

    python3 certs/check_chain.py certs/out
    python3 certs/check_chain.py certs/out --json
    python3 certs/check_chain.py certs/out --self-test

Why this parses DER instead of grepping `openssl x509 -text`
------------------------------------------------------------
The obvious check is

    openssl x509 -in end_responder.cert -text -noout | grep -A3 'Subject Alternative Name'

and it answers a weaker question than it looks like it does. It asks whether
OpenSSL's *pretty-printer* mentioned a string. It cannot tell a critical
extension from a non-critical one, cannot tell which of two otherNames carries
which OID, and cannot notice that the OID bytes encode something other than
what the configuration file asked for — because the printer decodes the OID and
prints the decoded form, so a wrong OID looks like a different right OID.

So the OIDs are located here by walking the certificate's own DER: SEQUENCE by
SEQUENCE down to the extensions, matching on the encoded OID bytes, and reading
the otherName's UTF8String out of its own tag-length-value. That is the same
habit as the rest of this repository — prove the offset, do not transcribe it —
applied to X.509 instead of to a captured message.

What it deliberately does not do
--------------------------------
It does not implement signature verification. `openssl verify` is called for
that, because reimplementing ECDSA to check one's own certificates would be a
way of being wrong in private. The division is the same one harness/ uses:
this file owns structure, openssl owns cryptography, and where both can reach
the same fact they are made to agree.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile

# ---------------------------------------------------------------- the OIDs --
#
# Encoded form, not dotted form. Matching on bytes means a mis-encoded OID
# cannot be rescued by a decoder that guesses, and it is what the certificate
# actually contains.

OID_DMTF_DEVICE_INFO = "1.3.6.1.4.1.412.274.1"       # DSP0274 1.4.0 §425
OID_DMTF_HW_IDENTITY = "1.3.6.1.4.1.412.274.2"       # DSP0274 1.4.0 §10.9.2.2.1
OID_DMTF_SPDM_EXT = "1.3.6.1.4.1.412.274.6"          # id-DMTF-spdm-extension
OID_PCIE_DEVICE_ID = "2.23.147"                      # plan/W03 §2.2 — UNVERIFIED
OID_SUBJECT_ALT_NAME = "2.5.29.17"
OID_BASIC_CONSTRAINTS = "2.5.29.19"

# DSP0274 Table 39. The chain that goes on the wire is a 4-byte little-endian
# Length, then RootHash, then the DER concatenation. H is whatever the
# connection negotiated; these captures negotiate SHA-384.
CHAIN_HEADER_BYTES = 4
DEFAULT_HASH = ("SHA_384", 48, hashlib.sha384)


# ------------------------------------------------------------------- DER ----

class DerError(Exception):
    pass


def der_tlv(buf: bytes, i: int) -> tuple[int, int, int, int]:
    """Read one tag-length-value at `i`. Returns (tag, header_len, body_len, body_start)."""
    if i >= len(buf):
        raise DerError(f"offset {i} is past the end of {len(buf)} bytes")
    tag = buf[i]
    if tag & 0x1F == 0x1F:
        raise DerError(f"multi-byte tag at {i}; nothing here should have one")
    if i + 1 >= len(buf):
        raise DerError(f"a tag at {i} with no length byte")
    lead = buf[i + 1]
    if lead < 0x80:
        return tag, 2, lead, i + 2
    if lead == 0x80:
        raise DerError(f"indefinite length at {i}, which DER forbids")
    count = lead & 0x7F
    if count > 4 or i + 2 + count > len(buf):
        raise DerError(f"a {count}-byte length at {i} that does not fit")
    body = int.from_bytes(buf[i + 2:i + 2 + count], "big")
    if body < 0x80 or count != max(1, (body.bit_length() + 7) // 8):
        raise DerError(f"a non-minimal DER length at {i}")
    return tag, 2 + count, body, i + 2 + count


def der_children(buf: bytes, start: int, end: int):
    """Every TLV directly inside [start, end)."""
    i = start
    while i < end:
        tag, hdr, body, bstart = der_tlv(buf, i)
        if bstart + body > end:
            raise DerError(f"a value at {i} runs past its container")
        yield tag, i, bstart, body
        i = bstart + body


def der_oid(buf: bytes, start: int, length: int) -> str:
    """Decode an OBJECT IDENTIFIER body to dotted form."""
    if length == 0:
        raise DerError("an empty OID")
    raw = buf[start:start + length]
    first = raw[0]
    parts = [str(first // 40), str(first % 40)]
    value, seen = 0, False
    for b in raw[1:]:
        if not seen and b == 0x80:
            raise DerError("a non-minimal OID arc")
        value = (value << 7) | (b & 0x7F)
        seen = True
        if not b & 0x80:
            parts.append(str(value))
            value, seen = 0, False
    if seen:
        raise DerError("an OID that ends mid-arc")
    return ".".join(parts)


def certificate_extensions(der: bytes) -> dict[str, dict]:
    """Every extension of an X.509 certificate, keyed by dotted OID.

    Certificate ::= SEQUENCE { tbsCertificate, signatureAlgorithm, signature }
    TBSCertificate ::= SEQUENCE { [0] version, serialNumber, ..., [3] extensions }
    """
    _tag, _hdr, body, bstart = der_tlv(der, 0)
    tbs = next(der_children(der, bstart, bstart + body))
    if tbs[0] != 0x30:
        raise DerError("the first element of a Certificate is not a SEQUENCE")
    _t, _off, tbs_start, tbs_len = tbs

    out: dict[str, dict] = {}
    for tag, off, cstart, clen in der_children(der, tbs_start, tbs_start + tbs_len):
        if tag != 0xA3:                     # [3] EXPLICIT Extensions
            continue
        seq = next(der_children(der, cstart, cstart + clen))
        if seq[0] != 0x30:
            raise DerError("the [3] extensions element does not hold a SEQUENCE")
        _t, _o, sstart, slen = seq
        for _etag, eoff, estart, elen in der_children(der, sstart, sstart + slen):
            fields = list(der_children(der, estart, estart + elen))
            if not fields or fields[0][0] != 0x06:
                raise DerError(f"an extension at {eoff} does not begin with an OID")
            oid = der_oid(der, fields[0][2], fields[0][3])
            critical = False
            idx = 1
            if len(fields) > idx and fields[idx][0] == 0x01:      # BOOLEAN
                critical = der[fields[idx][2]] != 0x00
                idx += 1
            if len(fields) <= idx or fields[idx][0] != 0x04:      # OCTET STRING
                raise DerError(f"extension {oid} has no extnValue OCTET STRING")
            vstart, vlen = fields[idx][2], fields[idx][3]
            out[oid] = {"critical": critical, "value_offset": vstart, "value_bytes": vlen}
    return out


def subject_alt_names(der: bytes, ext: dict) -> list[dict]:
    """Every otherName in a SubjectAltName extension, with its OID and UTF8 value.

    GeneralNames ::= SEQUENCE OF GeneralName
    GeneralName ::= otherName [0] IMPLICIT AnotherName | ...
    AnotherName ::= SEQUENCE { type-id OBJECT IDENTIFIER, value [0] EXPLICIT ANY }
    """
    seq = next(der_children(der, ext["value_offset"], ext["value_offset"] + ext["value_bytes"]))
    if seq[0] != 0x30:
        raise DerError("SubjectAltName does not hold a SEQUENCE")
    _t, _o, sstart, slen = seq
    names = []
    for tag, off, nstart, nlen in der_children(der, sstart, sstart + slen):
        if tag != 0xA0:                      # not an otherName
            names.append({"kind": f"GeneralName tag 0x{tag:02x}", "oid": None, "value": None})
            continue
        parts = list(der_children(der, nstart, nstart + nlen))
        if len(parts) != 2 or parts[0][0] != 0x06 or parts[1][0] != 0xA0:
            raise DerError(f"an otherName at {off} is not OID + [0] EXPLICIT value")
        oid = der_oid(der, parts[0][2], parts[0][3])
        inner = next(der_children(der, parts[1][2], parts[1][2] + parts[1][3]))
        itag, _io, istart, ilen = inner
        if itag != 0x0C:                     # UTF8String
            raise DerError(f"otherName {oid} holds tag 0x{itag:02x}, not a UTF8String")
        names.append({"kind": "otherName", "oid": oid,
                      "value": der[istart:istart + ilen].decode("utf-8", "replace")})
    return names


def der_sequences(buf: bytes):
    """Split a certificate bundle into its certificates. Must consume it exactly."""
    out, i = [], 0
    while i < len(buf):
        tag, hdr, body, _bstart = der_tlv(buf, i)
        if tag != 0x30:
            raise DerError(f"byte {i} is 0x{tag:02x}, not a SEQUENCE tag")
        if i + hdr + body > len(buf):
            raise DerError(f"the certificate at {i} runs past the end of the bundle")
        out.append((i, hdr + body))
        i += hdr + body
    if not out:
        raise DerError("the bundle holds no certificates")
    return out


# ---------------------------------------------------------------- openssl ---

def openssl(*args, cwd=None) -> tuple[int, str]:
    r = subprocess.run(["openssl", *args], capture_output=True, text=True, cwd=cwd)
    return r.returncode, (r.stdout + r.stderr).strip()


def cert_name(path: pathlib.Path, which: str) -> str | None:
    rc, out = openssl("x509", "-in", str(path), "-noout", f"-{which}")
    return out.split("=", 1)[1].strip() if rc == 0 and "=" in out else None


# ------------------------------------------------------------------ checks --

class Report:
    def __init__(self) -> None:
        self.problems: list[str] = []
        self.facts: dict = {}
        self.lines: list[str] = []

    def ok(self, text: str) -> None:
        self.lines.append(f"  \033[32mok\033[0m   {text}")

    def bad(self, text: str) -> None:
        self.lines.append(f"  \033[31mFAIL\033[0m {text}")
        self.problems.append(text)

    def note(self, text: str) -> None:
        self.lines.append(f"  --   {text}")


LAYERS = [
    ("ca", "root", True),
    ("inter", "intermediate", True),
    ("end_responder", "leaf (responder)", False),
    ("end_requester", "leaf (requester)", False),
]

BUNDLES = [
    ("bundle_responder.certchain.der", ["ca", "inter", "end_responder"]),
    ("bundle_requester.certchain.der", ["ca", "inter", "end_requester"]),
]


def check(chain_dir: pathlib.Path) -> Report:
    r = Report()
    hash_name, hash_size, hash_fn = DEFAULT_HASH

    # -- 1. everything is present -------------------------------------------
    der: dict[str, bytes] = {}
    for stem, label, _is_ca in LAYERS:
        path = chain_dir / f"{stem}.cert.der"
        if not path.exists():
            r.bad(f"{label}: {path.name} is missing")
            return r
        der[stem] = path.read_bytes()
    r.ok(f"four certificates present: "
         + ", ".join(f"{s}.cert.der {len(der[s])} B" for s, _l, _c in LAYERS))
    r.facts["certificate_bytes"] = {s: len(der[s]) for s, _l, _c in LAYERS}

    # -- 2. the chain links up, by name and then by signature ---------------
    names = {stem: (cert_name(chain_dir / f"{stem}.cert", "subject"),
                    cert_name(chain_dir / f"{stem}.cert", "issuer"))
             for stem, _l, _c in LAYERS}
    root_subj, root_iss = names["ca"]
    if root_subj != root_iss:
        r.bad(f"the root is not self-signed: subject {root_subj!r}, issuer {root_iss!r}")
    else:
        r.ok(f"root is self-signed — {root_subj}")
    for child in ("inter",):
        if names[child][1] != root_subj:
            r.bad(f"{child} is issued by {names[child][1]!r}, not by the root")
        else:
            r.ok(f"{child} is issued by the root")
    for child in ("end_responder", "end_requester"):
        if names[child][1] != names["inter"][0]:
            r.bad(f"{child} is issued by {names[child][1]!r}, not by the intermediate")
        else:
            r.ok(f"{child} is issued by the intermediate")

    for leaf in ("end_responder", "end_requester"):
        rc, out = openssl("verify", "-CAfile", str(chain_dir / "ca.cert"),
                          "-untrusted", str(chain_dir / "inter.cert"),
                          str(chain_dir / f"{leaf}.cert"))
        if rc != 0:
            r.bad(f"openssl verify rejects {leaf}: {out.splitlines()[-1] if out else 'no output'}")
        else:
            r.ok(f"openssl verify accepts {leaf} through the intermediate to the root")

    # -- 3. DSP0274 Table 48, read out of the DER ---------------------------
    for stem, label, is_ca in LAYERS:
        try:
            exts = certificate_extensions(der[stem])
        except DerError as exc:
            r.bad(f"{label}: cannot read its extensions — {exc}")
            continue
        bc = exts.get(OID_BASIC_CONSTRAINTS)
        if bc is None:
            r.bad(f"{label}: no basicConstraints (DSP0274 Table 48 makes it mandatory)")
            continue
        # BasicConstraints ::= SEQUENCE { cA BOOLEAN DEFAULT FALSE, ... }
        inner = list(der_children(der[stem], bc["value_offset"],
                                  bc["value_offset"] + bc["value_bytes"]))
        seq = inner[0]
        kids = list(der_children(der[stem], seq[2], seq[2] + seq[3]))
        got_ca = bool(kids) and kids[0][0] == 0x01 and der[stem][kids[0][2]] != 0x00
        if got_ca != is_ca:
            r.bad(f"{label}: basicConstraints CA is {got_ca}, expected {is_ca}")
        elif not is_ca and not bc["critical"]:
            r.bad(f"{label}: basicConstraints is not critical, and Table 48 requires CA:FALSE "
                  f"to be meaningful")
        else:
            r.ok(f"{label}: basicConstraints CA:{str(got_ca).upper()}"
                 + (" (critical)" if bc["critical"] else ""))

        rc, out = openssl("x509", "-in", str(chain_dir / f"{stem}.cert"), "-noout", "-serial")
        serial = int(out.split("=", 1)[1], 16) if rc == 0 and "=" in out else -1
        if serial <= 0:
            r.bad(f"{label}: serial number is {serial}; Table 48 requires a positive integer")

    # -- 4. the identity OIDs, located in the DER ---------------------------
    for stem, label in (("end_responder", "leaf (responder)"),
                        ("end_requester", "leaf (requester)")):
        exts = certificate_extensions(der[stem])
        san = exts.get(OID_SUBJECT_ALT_NAME)
        if san is None:
            r.bad(f"{label}: no subjectAltName")
            continue
        try:
            names_found = subject_alt_names(der[stem], san)
        except DerError as exc:
            r.bad(f"{label}: subjectAltName does not parse — {exc}")
            continue
        by_oid = {n["oid"]: n["value"] for n in names_found if n["oid"]}
        r.facts.setdefault("subject_alt_names", {})[stem] = by_oid

        dmtf = by_oid.get(OID_DMTF_DEVICE_INFO)
        if dmtf is None:
            r.bad(f"{label}: no otherName under {OID_DMTF_DEVICE_INFO} (DSP0274 §425)")
        elif len(dmtf.split(":")) != 3:
            r.bad(f"{label}: id-DMTF-device-info is {dmtf!r}; §425 requires exactly three "
                  f"colon-separated fields")
        else:
            r.ok(f"{label}: id-DMTF-device-info = {dmtf}  (DSP0274 §425, three fields)")

        pcie = by_oid.get(OID_PCIE_DEVICE_ID)
        if pcie is None:
            r.bad(f"{label}: no otherName under {OID_PCIE_DEVICE_ID}")
        else:
            r.note(f"{label}: {OID_PCIE_DEVICE_ID} = {pcie}")
            r.note("       ^ attributed to PCIe r6.1 §6.31.3 by plan/W03 and NOT verified "
                   "against that specification")

        ext = exts.get(OID_DMTF_SPDM_EXT)
        if ext is None:
            r.bad(f"{label}: no id-DMTF-spdm-extension ({OID_DMTF_SPDM_EXT})")
        else:
            found = []
            outer = next(der_children(der[stem], ext["value_offset"],
                                      ext["value_offset"] + ext["value_bytes"]))
            for _t, _o, istart, ilen in der_children(der[stem], outer[2], outer[2] + outer[3]):
                for tag, _oo, ostart, olen in der_children(der[stem], istart, istart + ilen):
                    if tag == 0x06:
                        found.append(der_oid(der[stem], ostart, olen))
            if OID_DMTF_HW_IDENTITY not in found:
                r.bad(f"{label}: id-DMTF-spdm-extension holds {found}, "
                      f"not {OID_DMTF_HW_IDENTITY}")
            else:
                r.ok(f"{label}: id-DMTF-hardware-identity present (DSP0274 §10.9.2.2.1)")

    # -- 5. the bundles, and what they will look like on the wire ------------
    for name, stems in BUNDLES:
        path = chain_dir / name
        if not path.exists():
            r.bad(f"{name} is missing")
            continue
        raw = path.read_bytes()

        # The order of the next two checks is load-bearing, and it was the wrong
        # way round first. Comparing the bundle against the concatenation of the
        # four files catches everything the DER walk would catch — so with that
        # comparison first, the walk never rejected anything and was arithmetic
        # that happened to agree. Walking first gives each check something only
        # it can find: the walk catches a bundle that is malformed, the
        # comparison catches one that is well formed and holds the wrong
        # certificates. The self-test below breaks it both ways to keep it so.
        try:
            seqs = der_sequences(raw)
        except DerError as exc:
            r.bad(f"{name}: does not parse as DER certificates — {exc}")
            continue
        want = b"".join(der[s] for s in stems)
        if raw != want:
            r.bad(f"{name} parses, but is not {' ‖ '.join(stems)} concatenated")
            continue
        if [n for _o, n in seqs] != [len(der[s]) for s in stems]:
            r.bad(f"{name}: parses as {[n for _o, n in seqs]}, "
                  f"expected {[len(der[s]) for s in stems]}")
            continue

        # The prediction. harness/fields.py reads the same quantity out of a
        # capture without ever opening one of these files; the two are required
        # to agree, and disagreeing is how a swapped chain is caught.
        on_wire = CHAIN_HEADER_BYTES + hash_size + len(raw)
        root_hash = hash_fn(der[stems[0]]).hexdigest()
        r.ok(f"{name}: {len(seqs)} certificates, "
             f"{' + '.join(str(n) for _o, n in seqs)} = {len(raw)} bytes")
        r.ok(f"{' ' * len(name)}  on the wire: {CHAIN_HEADER_BYTES} + {hash_size} + "
             f"{len(raw)} = {on_wire} bytes, RootHash {root_hash[:16]}…")
        r.facts.setdefault("bundles", {})[name] = {
            "bundle_bytes": len(raw),
            "certificates": [n for _o, n in seqs],
            "chain_length_on_wire": on_wire,
            "root_hash_algorithm": hash_name,
            "root_hash": root_hash,
        }
    return r


# --------------------------------------------------------------- self-test --
#
# A check is worth exactly what it rejects. These four breaks are the ones that
# matter: an identity OID that is no longer the OID it claims, a chain whose
# certificates were reordered, a bundle a byte short, and a signature that no
# longer verifies. Each is applied to a copy of the real chain, and each must be
# reported. A check that has never been observed failing is a check nobody has
# reason to believe.

def _flip(path: pathlib.Path, offset: int) -> None:
    raw = bytearray(path.read_bytes())
    raw[offset] ^= 0xFF
    path.write_bytes(bytes(raw))


def self_test(chain_dir: pathlib.Path) -> int:
    base = check(chain_dir)
    if base.problems:
        print("  the chain does not pass on its own; fix that before breaking it")
        for p in base.problems:
            print(f"    {p}")
        return 1
    print("  intact: accepted")

    failures = 0
    caught_by: dict[str, str] = {}
    for label, mutate in (
        ("the DMTF device-info OID altered", _break_oid),
        ("root and intermediate swapped in the bundle", _break_order),
        ("the bundle one byte short", _break_truncate),
        ("the leaf's signature altered", _break_signature),
    ):
        with tempfile.TemporaryDirectory() as tmp:
            work = pathlib.Path(tmp) / "out"
            shutil.copytree(chain_dir, work)
            why = mutate(work)
            if why:
                print(f"  {label}: could not construct — {why}")
                failures += 1
                continue
            broken = check(work)
            if not broken.problems:
                print(f"  ACCEPTED A BROKEN CHAIN: {label}")
                failures += 1
                continue
            first = broken.problems[0]
            caught_by[label] = first
            print(f"  {label}: rejected — {first}")

    # Four rejections are not four checks. If two breaks are caught by the same
    # message then one of the checks between them has still never been observed
    # doing anything, and the suite is reporting more coverage than it has.
    seen: dict[str, str] = {}
    for label, message in caught_by.items():
        key = message.split(":")[0] + "|" + message.split("—")[0][-40:]
        if key in seen:
            print(f"  BOTH '{seen[key]}' and '{label}' are caught by the same check;")
            print("  one of the checks between them has still never rejected anything")
            failures += 1
        seen[key] = label
    if not failures:
        print(f"  {len(caught_by)} breaks, {len(seen)} distinct checks — none redundant")
    return failures


def _break_oid(work: pathlib.Path) -> str | None:
    der = (work / "end_responder.cert.der").read_bytes()
    exts = certificate_extensions(der)
    san = exts.get(OID_SUBJECT_ALT_NAME)
    if san is None:
        return "no subjectAltName to break"
    # Find the encoded OID inside the first otherName and change its last arc.
    seq = next(der_children(der, san["value_offset"], san["value_offset"] + san["value_bytes"]))
    for tag, _off, nstart, nlen in der_children(der, seq[2], seq[2] + seq[3]):
        if tag != 0xA0:
            continue
        oid_tlv = next(der_children(der, nstart, nstart + nlen))
        last = oid_tlv[2] + oid_tlv[3] - 1
        raw = bytearray(der)
        raw[last] ^= 0x07                    # same length, different OID
        (work / "end_responder.cert.der").write_bytes(bytes(raw))
        _rebundle(work)
        return None
    return "no otherName found"


def _break_order(work: pathlib.Path) -> str | None:
    a = (work / "ca.cert.der").read_bytes()
    b = (work / "inter.cert.der").read_bytes()
    c = (work / "end_responder.cert.der").read_bytes()
    (work / "bundle_responder.certchain.der").write_bytes(b + a + c)
    return None


def _break_truncate(work: pathlib.Path) -> str | None:
    p = work / "bundle_responder.certchain.der"
    p.write_bytes(p.read_bytes()[:-1])
    return None


def _break_signature(work: pathlib.Path) -> str | None:
    p = work / "end_responder.cert"
    der_path = work / "end_responder.cert.der"
    raw = bytearray(der_path.read_bytes())
    raw[-1] ^= 0xFF                          # inside the signature BIT STRING
    der_path.write_bytes(bytes(raw))
    rc, out = openssl("x509", "-in", str(der_path), "-inform", "DER", "-out", str(p))
    if rc != 0:
        return f"could not re-encode the broken certificate: {out}"
    _rebundle(work)
    return None


def _rebundle(work: pathlib.Path) -> None:
    (work / "bundle_responder.certchain.der").write_bytes(
        (work / "ca.cert.der").read_bytes()
        + (work / "inter.cert.der").read_bytes()
        + (work / "end_responder.cert.der").read_bytes())


# ------------------------------------------------------------------- main ---

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("chain_dir", type=pathlib.Path, nargs="?",
                    default=pathlib.Path(__file__).resolve().parent / "out")
    ap.add_argument("--json", action="store_true", help="machine-readable facts")
    ap.add_argument("--self-test", action="store_true",
                    help="break the chain four ways and require each to be rejected")
    args = ap.parse_args()

    if not args.chain_dir.is_dir():
        print(f"no such directory: {args.chain_dir}", file=sys.stderr)
        print("run: bash certs/gen_chain.sh", file=sys.stderr)
        return 2

    if not shutil.which("openssl"):
        print("openssl is not on PATH", file=sys.stderr)
        return 2

    if args.self_test:
        return 1 if self_test(args.chain_dir) else 0

    report = check(args.chain_dir)
    if args.json:
        print(json.dumps(report.facts, indent=2, sort_keys=True))
        return 1 if report.problems else 0

    print(f"chain: {args.chain_dir}")
    for line in report.lines:
        print(line)
    print()
    if report.problems:
        print(f"\033[31m{len(report.problems)} problem(s)\033[0m")
        return 1
    print("\033[32mthe chain is well formed and links to its root\033[0m")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Name the libspdm status an emulator printed, instead of quoting a number.

    python3 harness/spdm_status.py <run>/t2a_record.req.log
    python3 harness/spdm_status.py <run>/t2a_record.req.log --json
    python3 harness/spdm_status.py <run>/t2a_record.req.log --all
    python3 harness/spdm_status.py --decode 0x80020001
    python3 harness/spdm_status.py --self-test

Why a tool and not a grep
-------------------------
`spdm_requester_emu` reports failures as

    ERROR: do_measurement_via_spdm - 80020001

and `80020001` is the whole finding. It is a `libspdm_return_t`, which packs
three fields (`spdm_return_status.h:37-55`):

    bits 31-28  severity   0x0 success · 0x4 warning · 0x8 error
    bits 23-16  source     which layer decided
    bits 15-0   code

so severity and source are decodable from the number alone, and this file does
that arithmetically rather than from a table — a status this project has never
seen still gets read correctly, and is reported as unnamed rather than as
unknown. Only the *name* needs the table below.

That distinction is the point of the file. The two rows of Table 1 that fail in
flight both print `80020001`, and the sentence worth writing about them is not
"they both failed" but **"they were both refused by the same layer for the same
reason, and the wire is the only thing that tells them apart"**. A number
cannot say that. `ERROR/CRYPTO/VERIF_FAIL` can.

The severity field is also why `docs/tamper.md`'s case 3b exists at all:
`VERIF_NO_AUTHORITY` is `0x40020003`, and `0x4` is a warning. A caller testing
`LIBSPDM_STATUS_IS_ERROR` never sees it.

What owns what
--------------
`docs/roadmap.md` standing rule 12: one tool per input. This one owns an
emulator's **log**. It never opens a capture, a decode or a certificate, and
nothing else in this repository parses a log for a status.

Exit codes: 0 a status was found · 1 none in the file · 2 unreadable arguments
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

# spdm_return_status.h:37-55.
SEVERITY = {0x0: "SUCCESS", 0x4: "WARNING", 0x8: "ERROR"}
SOURCE = {                              # :46-52
    0x00: "SUCCESS",
    0x01: "CORE",
    0x02: "CRYPTO",
    0x03: "CERT_PARSE",
    0x04: "TRANSPORT",
    0x05: "MEAS_COLLECT",
    0x06: "RNG",
}

# Names only. Generated from the pinned header on 2026-09-10 and pasted, with
# each definition's line number, so a version bump can be checked line by line
# rather than re-derived from memory:
#
#   python3 - <<'PY'  (see LOG.md 2026-09-10)
#
# Everything else about a status — its severity, its source, whether a caller
# testing IS_ERROR would see it — is computed, not looked up.
NAMES = {
    0x00000000: "SUCCESS",                          # :58
    0x40010014: "OVERRIDDEN_PARAMETER",             # :149
    0x40020003: "VERIF_NO_AUTHORITY",               # :167
    0x80010001: "INVALID_PARAMETER",                # :72
    0x80010002: "UNSUPPORTED_CAP",                  # :77
    0x80010003: "INVALID_STATE_LOCAL",              # :81
    0x80010004: "INVALID_STATE_PEER",               # :85
    0x80010005: "INVALID_MSG_FIELD",                # :89
    0x80010006: "INVALID_MSG_SIZE",                 # :93
    0x80010007: "NEGOTIATION_FAIL",                 # :97
    0x80010008: "BUSY_PEER",                        # :101
    0x80010009: "NOT_READY_PEER",                   # :105
    0x8001000A: "ERROR_PEER",                       # :109
    0x8001000B: "RESYNCH_PEER",                     # :113
    0x8001000C: "BUFFER_FULL",                      # :117
    0x8001000D: "BUFFER_TOO_SMALL",                 # :121
    0x8001000E: "SESSION_NUMBER_EXCEED",            # :125
    0x8001000F: "SESSION_MSG_ERROR",                # :129
    0x80010010: "ACQUIRE_FAIL",                     # :133
    0x80010011: "SESSION_TRY_DISCARD_KEY_UPDATE",   # :137
    0x80010012: "RESET_REQUIRED_PEER",              # :141
    0x80010013: "PEER_BUFFER_TOO_SMALL",            # :145
    0x80020000: "CRYPTO_ERROR",                     # :155
    0x80020001: "VERIF_FAIL",                       # :159
    0x80020002: "SEQUENCE_NUMBER_OVERFLOW",         # :163
    0x80020004: "FIPS_FAIL",                        # :171
    0x80030000: "INVALID_CERT",                     # :177
    0x80040000: "SEND_FAIL",                        # :183
    0x80040001: "RECEIVE_FAIL",                     # :187
    0x80050000: "MEAS_INVALID_INDEX",               # :193
    0x80050001: "MEAS_INTERNAL_ERROR",              # :197
    0x80060000: "LOW_ENTROPY",                      # :203
}

# spdm_requester_emu and spdm_responder_emu both print through EMU_ERR, which
# gives "ERROR: <what> - <hex>". The hex has no 0x and is not zero-padded to a
# fixed width, so anchoring on the dash rather than on a width.
LINE = re.compile(r"ERROR:\s*(?P<what>[^\-]+?)\s*-\s*(?P<status>[0-9a-fA-F]{1,8})\s*$")


def decode(status: int) -> dict:
    severity = (status >> 28) & 0xF
    source = (status >> 16) & 0xFF
    return {
        "status": f"{status:08x}",
        "name": NAMES.get(status),
        "severity": SEVERITY.get(severity, f"0x{severity:x}"),
        "severity_value": severity,
        "source": SOURCE.get(source, f"0x{source:02x}"),
        "source_value": source,
        "code": (status & 0xFFFF),
        # What a caller doing the thing spdm_requester_emu does would conclude.
        "is_error": severity == 0x8,
        "is_warning": severity == 0x4,
    }


def render(entry: dict) -> str:
    name = entry["name"] or "unnamed in the pinned header"
    where = f" from {entry['what']}" if entry.get("what") else ""
    return (f"{entry['status']} {name} "
            f"({entry['severity']}/{entry['source']}/0x{entry['code']:04x})"
            f"{where}")


def scan(path: Path) -> list[dict]:
    out = []
    for n, line in enumerate(path.read_text(errors="replace").splitlines(), 1):
        m = LINE.search(line.rstrip())
        if not m:
            continue
        entry = decode(int(m.group("status"), 16))
        entry["what"] = m.group("what").strip()
        entry["line"] = n
        out.append(entry)
    return out


def self_test() -> int:
    """The four statuses this project has actually seen, and one it has not."""
    cases = [
        (0x80020001, "VERIF_FAIL", "ERROR", "CRYPTO", True),
        (0x40020003, "VERIF_NO_AUTHORITY", "WARNING", "CRYPTO", False),
        (0x8001000A, "ERROR_PEER", "ERROR", "CORE", True),
        (0x00000000, "SUCCESS", "SUCCESS", "SUCCESS", False),
        (0x80070009, None, "ERROR", "0x07", True),
    ]
    bad = 0
    for value, name, severity, source, is_error in cases:
        d = decode(value)
        good = (d["name"] == name and d["severity"] == severity
                and d["source"] == source and d["is_error"] == is_error)
        bad += 0 if good else 1
        print(f"  {'ok  ' if good else 'FAIL'}  {value:#010x} -> {render(d)}")

    # The line shape, including the one that is not a status at all. "Error - 2"
    # is a C errno printed by the same macro, and reading it as a libspdm status
    # would name a layer that had no opinion.
    lines = [
        ("ERROR: do_measurement_via_spdm - 80020001", "80020001"),
        ("ERROR: do_authentication_via_spdm - 8001000a", "8001000a"),
        ("ERROR: receive_platform_data Error - 2", "00000002"),
        ("connect success!", None),
    ]
    for text, want in lines:
        m = LINE.search(text)
        got = f"{int(m.group('status'), 16):08x}" if m else None
        good = got == want
        bad += 0 if good else 1
        print(f"  {'ok  ' if good else 'FAIL'}  {text!r} -> {got}")

    print(f"\n  {len(NAMES)} names, severity and source computed for any value")
    return 1 if bad else 0


def main() -> int:
    ap = argparse.ArgumentParser(
        description="name the libspdm status in an emulator log")
    ap.add_argument("log", nargs="?", type=Path)
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--all", action="store_true",
                    help="every status in the file, not just the last")
    ap.add_argument("--decode", metavar="STATUS",
                    help="decode one status without reading a log")
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()

    if args.self_test:
        return self_test()

    if args.decode is not None:
        entry = decode(int(args.decode, 16))
        print(json.dumps(entry, indent=2) if args.json else render(entry))
        return 0

    if args.log is None:
        ap.error("give a log file, --decode or --self-test")
    if not args.log.is_file():
        print(f"no such file: {args.log}", file=sys.stderr)
        return 2

    found = scan(args.log)
    if args.json:
        print(json.dumps(found if args.all else (found[-1:] or [None])[0],
                         indent=2))
    else:
        for entry in (found if args.all else found[-1:]):
            print(render(entry))
        if not found:
            print("-")
    return 0 if found else 1


if __name__ == "__main__":
    sys.exit(main())

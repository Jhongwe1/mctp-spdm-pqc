#!/usr/bin/env python3
"""Read DMTF's conformance suite log, and compare two runs of it assertion by assertion.

    python3 harness/validator_report.py --parse test.log --json out.json --label caps-default
    python3 harness/validator_report.py --compare a.json b.json --json diff.json
    python3 harness/validator_report.py --caps-delta a.pcap b.pcap --expect-only MUT_AUTH_CAP
    python3 harness/validator_report.py --audit-config <validator-src> <emu-config.c>
    python3 harness/validator_report.py --markdown a.json
    python3 harness/validator_report.py --self-test

Why a parser rather than grep -c
--------------------------------
`grep -c PASS test.log` answers a question nobody asked. Three reasons, all of
them read out of
`common_test_framework/library/common_test_utility_lib/common_test_utility_lib.c`
at the submodule commit in `third_party/spdm-emu-pqc.pin`:

  * **NOT_TESTED is neither.** `common_test_record_test_suite_result` increments
    `total_pass` on PASS and `total_fail` on FAIL and does nothing at all on
    NOT_TESTED. So the suite's own footer under-counts the assertions it
    recorded, and the gap is exactly the assertions that never got to run. That
    gap is the most interesting number in the file and no count of PASS
    contains it.

  * **A skipped case leaves no assertion behind.** It prints one line and
    records nothing, so a case that is in the suite and not in the
    configuration is invisible to any count of results. Three of them are.

  * **The same assertion id occurs many times.** `6.1.7` appears once per slot
    per measurement-hash-type. Counting ids would report nine assertions as
    one; counting lines would make two runs incomparable the moment one of them
    returns early. So an assertion's identity here is `group.case.assertion#n`,
    where `n` is its ordinal within that id in that run, and the comparison is
    keyed on it.

What the comparison is for
--------------------------
`docs/roadmap.md` standing rule 11: a check is worth what it rejects. A
conformance suite observed only passing has not been shown able to fail, so
`harness/run_validator.sh` runs it once through an inert proxy and once through
a proxy that flips one byte of one signature, and requires this tool to find
that exactly the assertion named "response signature" moved. `--compare`
therefore reports four categories rather than a count, and
`--require-regressed-message` turns the requirement into an exit status:

    regressed    PASS -> FAIL          the calibration wants these, and only these
    improved     FAIL -> PASS          a calibration that produces one is not calibrated
    disappeared  present -> absent     the early return after a FAIL; confined to its case
    appeared     absent -> present     a case that could not run before and now can

Exit codes: 0 ok, 1 a requested assertion did not hold, 2 bad arguments.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys
import tempfile

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "bench"))
sys.path.insert(0, str(REPO_ROOT / "harness"))

# ---------------------------------------------------------------- parsing ---

# "    test assertion 6.2.7 - FAIL response signature"
RE_ASSERT = re.compile(
    r"^\s*test assertion (\d+)\.(\d+)\.(\d+) - (PASS|FAIL|NOT_TESTED)(?: (.*))?$")
# "  test case 2.7 (spdm_test_case_capabilities_success_13) - skipped"
RE_CASE = re.compile(
    r"^\s*test case (\d+)\.(\d+) \(([^)]*)\) - (skipped|start|stop|setup enter|"
    r"setup exit \((\d+)\)|teardown enter|teardown exit)$")
# "test group 7 (spdm_test_group_measurements) - start"
# Upstream spells the group form "setup exiit"; matching what it prints rather
# than what it meant is the only way this parser survives the day it is fixed.
RE_GROUP = re.compile(
    r"^test group (\d+) \(([^)]*)\) - (skipped|start|stop|setup enter|"
    r"setup exi+t \((\d+)\)|teardown enter|teardown exit)$")
RE_MSG = re.compile(r"^\s*test msg: (.*)$")
# "test suite (spdm_responder_conformance_test) - pass: 1077, fail: 8"
RE_SUITE_TOTAL = re.compile(r"^test suite \(([^)]*)\) - pass: (\d+), fail: (\d+)$")
RE_GROUP_TOTAL = re.compile(r"^test group (\d+) \(([^)]*)\) - pass: (\d+), fail: (\d+)$")
RE_CASE_TOTAL = re.compile(
    r"^\s+test case (\d+)\.(\d+) \(([^)]*)\) - pass: (\d+), fail: (\d+)$")
RE_LIBSPDM = re.compile(r"^LIBSPDM_(MAJOR|MINOR|PATCH)_VERSION : 0x([0-9A-Fa-f]{2})$")


class Rejected(Exception):
    """The log does not say what a conformance log says."""


def parse(text: str, label: str = "") -> dict:
    """test.log -> a structure whose every number came from a line of it."""
    lines = text.splitlines()

    assertions: list[dict] = []
    cases: dict[str, dict] = {}
    groups: dict[str, dict] = {}
    skipped_cases: list[dict] = []
    skipped_groups: list[dict] = []
    footer = {"suite": None, "groups": {}, "cases": {}}
    libspdm = {}
    seen: dict[str, int] = {}
    context: list[str] = []
    saw_done = False

    for raw in lines:
        m = RE_LIBSPDM.match(raw)
        if m:
            libspdm[m.group(1).lower()] = int(m.group(2), 16)
            continue

        if raw == "test result done":
            saw_done = True
            continue

        m = RE_MSG.match(raw)
        if m:
            context.append(m.group(1).strip())
            continue

        m = RE_ASSERT.match(raw)
        if m:
            g, c, a, result, msg = m.groups()
            key = f"{g}.{c}.{a}"
            seen[key] = seen.get(key, 0) + 1
            assertions.append({
                "id": key,
                "occurrence": seen[key],
                "key": f"{key}#{seen[key]}",
                "group": int(g),
                "case": int(c),
                "assertion": int(a),
                "result": result,
                "message": (msg or "").strip(),
                # Only the messages since the last assertion. The suite prints
                # "test slot - 0x01" once and then several assertions under it,
                # so carrying the whole history would attribute every earlier
                # slot to the last one.
                "context": list(context),
            })
            context = []
            continue

        m = RE_CASE.match(raw)
        if m:
            g, c, name, what = m.group(1), m.group(2), m.group(3), m.group(4)
            cases.setdefault(f"{g}.{c}", {"name": name, "group": int(g),
                                          "case": int(c), "events": []})
            cases[f"{g}.{c}"]["events"].append(what)
            if what == "skipped":
                skipped_cases.append({"id": f"{g}.{c}", "name": name})
            if what.startswith("setup exit"):
                context = []
            continue

        m = RE_GROUP.match(raw)
        if m:
            g, name, what = m.group(1), m.group(2), m.group(3)
            groups.setdefault(g, {"name": name, "group": int(g), "events": []})
            groups[g]["events"].append(what)
            if what == "skipped":
                skipped_groups.append({"id": g, "name": name})
            continue

        m = RE_SUITE_TOTAL.match(raw)
        if m:
            footer["suite"] = {"name": m.group(1), "pass": int(m.group(2)),
                               "fail": int(m.group(3))}
            continue

        m = RE_CASE_TOTAL.match(raw)
        if m:
            footer["cases"][f"{m.group(1)}.{m.group(2)}"] = {
                "name": m.group(3), "pass": int(m.group(4)), "fail": int(m.group(5))}
            continue

        m = RE_GROUP_TOTAL.match(raw)
        if m:
            footer["groups"][m.group(1)] = {
                "name": m.group(2), "pass": int(m.group(3)), "fail": int(m.group(4))}
            continue

    # -- the rejections. A parser that cannot refuse anything is a regex. ----
    if not saw_done:
        raise Rejected("no 'test result done' line: the suite did not finish, so "
                       "any count taken from this file is of a truncated run")
    if footer["suite"] is None:
        raise Rejected("no 'test suite (...) - pass: N, fail: M' footer")
    if not assertions:
        raise Rejected("no assertions recorded at all")

    counts = {"PASS": 0, "FAIL": 0, "NOT_TESTED": 0}
    for a in assertions:
        counts[a["result"]] += 1

    # The suite's own footer, recomputed from the lines above it. They must
    # agree, and when they do not it is this file that is wrong, not the suite:
    # both numbers come from the same run and only one of them is re-derived.
    if counts["PASS"] != footer["suite"]["pass"]:
        raise Rejected(f"counted {counts['PASS']} PASS lines, footer says "
                       f"{footer['suite']['pass']}")
    if counts["FAIL"] != footer["suite"]["fail"]:
        raise Rejected(f"counted {counts['FAIL']} FAIL lines, footer says "
                       f"{footer['suite']['fail']}")

    # Groups that ran and recorded nothing. The footer says "pass: 0, fail: 0",
    # which reads like a group with no assertions rather than what it is: a
    # group every one of whose cases could not start.
    silent = sorted(
        (int(g) for g, v in footer["groups"].items()
         if v["pass"] == 0 and v["fail"] == 0
         and any(a["group"] == int(g) for a in assertions)),
    )

    return {
        "label": label,
        "libspdm": libspdm,
        "suite": footer["suite"]["name"],
        "counts": counts,
        "assertions_recorded": len(assertions),
        "footer_pass_plus_fail": footer["suite"]["pass"] + footer["suite"]["fail"],
        "not_tested_invisible_to_footer": counts["NOT_TESTED"],
        "groups_present": sorted(int(g) for g in groups),
        "groups_silent": silent,
        "cases_skipped": skipped_cases,
        "groups_skipped": skipped_groups,
        "footer": footer,
        "assertions": assertions,
    }


def summarise(doc: dict) -> str:
    c = doc["counts"]
    out = []
    out.append(f"  suite              {doc['suite']}")
    lv = doc.get("libspdm") or {}
    if lv:
        out.append("  libspdm            "
                   f"{lv.get('major', 0)}.{lv.get('minor', 0)}.{lv.get('patch', 0)}")
    out.append(f"  assertions         {doc['assertions_recorded']}")
    out.append(f"    PASS             {c['PASS']}")
    out.append(f"    FAIL             {c['FAIL']}")
    out.append(f"    NOT_TESTED       {c['NOT_TESTED']}   "
               "(counted by neither half of the suite's own footer)")
    out.append(f"  cases skipped      {len(doc['cases_skipped'])}"
               + ("   " + ", ".join(s["id"] for s in doc["cases_skipped"])
                  if doc["cases_skipped"] else ""))
    if doc["groups_silent"]:
        out.append("  groups that ran and recorded no pass or fail   "
                   + ", ".join(str(g) for g in doc["groups_silent"]))
    fails = [a for a in doc["assertions"] if a["result"] == "FAIL"]
    if fails:
        out.append("  failures:")
        for a in fails:
            out.append(f"    {a['id']:<10} {a['message']}")
    return "\n".join(out)


# -------------------------------------------------------------- comparing ---

def compare(a: dict, b: dict) -> dict:
    ai = {x["key"]: x for x in a["assertions"]}
    bi = {x["key"]: x for x in b["assertions"]}

    regressed, improved, disappeared, appeared, other = [], [], [], [], []

    for k, x in ai.items():
        y = bi.get(k)
        if y is None:
            disappeared.append(x)
            continue
        if x["result"] == y["result"]:
            continue
        if x["result"] == "PASS" and y["result"] == "FAIL":
            regressed.append({"key": k, "id": x["id"], "message": y["message"],
                              "context": y["context"]})
        elif x["result"] == "FAIL" and y["result"] == "PASS":
            improved.append({"key": k, "id": x["id"], "message": x["message"]})
        else:
            other.append({"key": k, "id": x["id"],
                          "from": x["result"], "to": y["result"],
                          "message": y["message"]})
    for k, y in bi.items():
        if k not in ai:
            appeared.append(y)

    touched = {r["id"].rsplit(".", 1)[0] for r in regressed}
    stray = sorted({d["id"].rsplit(".", 1)[0] for d in disappeared} - touched)

    return {
        "a": a.get("label") or "a",
        "b": b.get("label") or "b",
        "counts": {"a": a["counts"], "b": b["counts"]},
        "regressed": regressed,
        "improved": improved,
        "disappeared": [{"key": d["key"], "id": d["id"], "result": d["result"]}
                        for d in disappeared],
        "appeared": [{"key": d["key"], "id": d["id"], "result": d["result"]}
                     for d in appeared],
        "changed_other": other,
        "cases_with_a_regression": sorted(touched),
        "cases_that_lost_assertions_without_one": stray,
    }


def print_compare(d: dict) -> None:
    print(f"  {d['a']}  ->  {d['b']}")
    for name in ("regressed", "improved", "disappeared", "appeared", "changed_other"):
        print(f"    {name:<16} {len(d[name])}")
    for r in d["regressed"]:
        ctx = ("; ".join(r["context"])) if r.get("context") else ""
        print(f"      PASS->FAIL  {r['id']:<10} {r['message']}"
              + (f"   [{ctx}]" if ctx else ""))
    for r in d["improved"]:
        print(f"      FAIL->PASS  {r['id']:<10} {r['message']}")
    if d["cases_that_lost_assertions_without_one"]:
        print("    cases that lost assertions without a regression of their own: "
              + ", ".join(d["cases_that_lost_assertions_without_one"]))


# ------------------------------------------------------- capability delta ---

SPDM_CAPABILITIES_CODE = 0x61


def responder_flag_words(pcap: pathlib.Path) -> dict[str, list[int]]:
    """Every Flags word the responder advertised, bucketed by SPDM version.

    Not pcapstat.capabilities(), which stops at the FIRST CAPABILITIES in a
    capture. That is right for a capture with one handshake in it and wrong
    here: a validator run contains one per test case, at several negotiated
    versions, and the question being asked is whether ALL of them moved by one
    bit and no other.

    It reads the bytes through pcapstat's pcap reader and then locates the
    field itself, rather than through pcapstat.messages(), which strips the
    message bytes off each entry before returning. That division is the one
    docs/roadmap.md standing rule 12 asks for: the file format has one owner,
    and a second tool reaching the same quantity does it by its own route.

    spdm.h's spdm_capabilities_response_t, valid for 1.0 through 1.4 because
    every later field was taken out of a reserved run rather than appended in
    front of Flags:

        version(1) code(1) param1(1) param2(1)
        reserved(1) ct_exponent(1) reserved2(2)
        flags(4)                                  <- offset 8, little endian
    """
    import pcapstat

    summary, packets = pcapstat.read_pcap(pcap)
    framing = pcapstat.framing_bytes(summary["linktype"])
    if framing is None:
        return {}
    raw = pcap.read_bytes()

    out: dict[str, list[int]] = {}
    for p in packets:
        body = raw[p["file_offset"]:p["file_offset"] + p["captured_bytes"]]
        if len(body) < framing + 12:
            continue
        if body[pcapstat.MCTP_HEADER_BYTES] != pcapstat.MCTP_TYPE_SPDM:
            continue
        msg = body[framing:]
        if len(msg) < 12 or msg[1] != SPDM_CAPABILITIES_CODE:
            continue
        out.setdefault(pcapstat.spdm_version(msg[0]), []).append(
            int.from_bytes(msg[8:12], "little"))
    return out


def caps_delta(pcap_a: pathlib.Path, pcap_b: pathlib.Path,
               expect_only: str | None) -> int:
    from fields import RSP_FLAGS

    names = {bit: name for bit, name, _since in RSP_FLAGS}
    a = responder_flag_words(pcap_a)
    b = responder_flag_words(pcap_b)

    print(f"  {pcap_a.name}")
    print(f"  {pcap_b.name}")
    if not a or not b:
        print("  FAIL   one of the captures carries no CAPABILITIES response")
        return 1

    shared = sorted(set(a) & set(b))
    if not shared:
        print(f"  FAIL   no SPDM version in common: {sorted(a)} against {sorted(b)}")
        return 1

    bad = 0
    moved_expected_somewhere = 0
    for ver in shared:
        wa, wb = set(a[ver]), set(b[ver])
        if len(wa) != 1 or len(wb) != 1:
            print(f"  FAIL   version {ver}: an arm advertised more than one Flags "
                  f"word ({[hex(x) for x in sorted(wa)]} against "
                  f"{[hex(x) for x in sorted(wb)]})")
            bad = 1
            continue
        va, vb = wa.pop(), wb.pop()
        diff = va ^ vb
        moved = [names.get(bit, f"bit 0x{bit:08x}")
                 for bit in sorted(names) if diff & bit]
        unknown = diff & ~sum(names)
        if unknown:
            moved.append(f"unnamed bits 0x{unknown:08x}")
        print(f"    {ver}   0x{va:08x} -> 0x{vb:08x}   moved: "
              + (", ".join(moved) if moved else "nothing"))
        if expect_only is None:
            continue
        # "nothing moved" is the right answer for an early version: the
        # responder's Flags word is narrower at 1.0 than at 1.4 because the
        # later bits do not exist there, and MUT_AUTH_CAP is one of them
        # (0x37 at 1.0 against 0xb99afbf7 at 1.4 on this build). So a version
        # that cannot carry the bit must not be required to move it -- and a
        # comparison where NO version moves it is still a failure, which is
        # what keeps this from being satisfied by comparing a capture with
        # itself.
        if moved == [expect_only]:
            moved_expected_somewhere += 1
        elif moved:
            print(f"      FAIL   only {expect_only} was allowed to move here")
            bad = 1
    if expect_only is not None:
        if moved_expected_somewhere == 0:
            print(f"  FAIL   no negotiated version moved {expect_only} at all")
            bad = 1
        elif not bad:
            print(f"  ok   {expect_only} moved in {moved_expected_somewhere} of "
                  f"{len(shared)} negotiated version(s) and nothing else moved "
                  f"anywhere")
    return bad


# ---------------------------------------------------------- config audit ----

RE_CASE_ID_DEF = re.compile(
    r"^#define\s+(SPDM_RESPONDER_TEST_CASE_[A-Z0-9_]+)\s")
RE_CASE_IN_TABLE = re.compile(r"^\s*\{(SPDM_RESPONDER_TEST_CASE_[A-Z0-9_]+),")
RE_CASE_IN_CONFIG = re.compile(r"\{(SPDM_RESPONDER_TEST_CASE_[A-Z0-9_]+),")


def audit_config(validator_src: pathlib.Path, emu_config: pathlib.Path) -> int:
    """Cases the suite implements that the sample program never asks for.

    The suite's README lists twenty test groups. Twelve have source files. Of
    the cases inside those twelve, three are in the library's own
    common_test_case_t tables and absent from spdm-emu's
    spdm_device_validator_config.c, so the program everybody runs skips them
    and prints one line each saying so.

    This is a fact about two files, so it is checked against those two files
    rather than asserted in prose. docs/roadmap.md standing rule 9.
    """
    lib = validator_src / "library" / "spdm_responder_conformance_test_lib"
    if not lib.is_dir():
        print(f"  no such directory: {lib}")
        return 2

    implemented: dict[str, str] = {}
    for src in sorted(lib.glob("spdm_responder_test_*.c")):
        for line in src.read_text(errors="replace").splitlines():
            m = RE_CASE_IN_TABLE.match(line)
            if m:
                implemented[m.group(1)] = src.name

    registered = set(RE_CASE_IN_CONFIG.findall(
        emu_config.read_text(errors="replace")))

    missing = sorted(set(implemented) - registered)
    extra = sorted(registered - set(implemented))

    print(f"  implemented by the suite      {len(implemented)}")
    print(f"  registered by the sample      {len(registered)}")
    if extra:
        print("  registered and NOT implemented (these would be silent):")
        for name in extra:
            print(f"    {name}")
    if missing:
        print("  implemented and NOT registered -- the sample never runs these:")
        for name in missing:
            print(f"    {name:<58} {implemented[name]}")
    else:
        print("  every implemented case is registered")
    return 0


# ------------------------------------------------------------- markdown -----

def markdown(doc: dict) -> str:
    rows = ["| Group | Name | PASS | FAIL | NOT_TESTED | Cases skipped |",
            "|---:|---|---:|---:|---:|---|"]
    by_group: dict[int, dict] = {}
    for a in doc["assertions"]:
        slot = by_group.setdefault(a["group"], {"PASS": 0, "FAIL": 0, "NOT_TESTED": 0})
        slot[a["result"]] += 1
    skipped_by_group: dict[int, list[str]] = {}
    for s in doc["cases_skipped"]:
        skipped_by_group.setdefault(int(s["id"].split(".")[0]), []).append(s["id"])
    for g in sorted(by_group):
        name = (doc["footer"]["groups"].get(str(g)) or {}).get("name", "")
        v = by_group[g]
        rows.append(f"| {g} | `{name}` | {v['PASS']} | {v['FAIL']} | "
                    f"{v['NOT_TESTED']} | "
                    f"{', '.join(skipped_by_group.get(g, [])) or '--'} |")
    c = doc["counts"]
    rows.append(f"| **total** | | **{c['PASS']}** | **{c['FAIL']}** | "
                f"**{c['NOT_TESTED']}** | "
                f"**{len(doc['cases_skipped'])}** |")
    return "\n".join(rows)


# ------------------------------------------------------------- self test ----

GOOD = """\
LIBSPDM_MAJOR_VERSION : 0x04
LIBSPDM_MINOR_VERSION : 0x00
LIBSPDM_PATCH_VERSION : 0x00
test_suite_config (cfg)
test_suite (t)
test group 1 (g_one) - start
  test case 1.1 (c_one) - setup enter
  test case 1.1 (c_one) - setup exit (1)
  test case 1.1 (c_one) - start
    test msg: test slot - 0x00
    test assertion 1.1.1 - PASS size - 10
    test assertion 1.1.2 - PASS signature
    test msg: test slot - 0x01
    test assertion 1.1.1 - PASS size - 10
    test assertion 1.1.2 - PASS signature
  test case 1.1 (c_one) - stop
  test case 1.2 (c_two) - skipped
test group 1 (g_one) - stop
test group 2 (g_two) - start
  test case 2.1 (c_three) - setup enter
  test case 2.1 (c_three) - setup exit (0)
    test assertion 2.1.0 - NOT_TESTED case_setup_func fail
test group 2 (g_two) - stop

test suite (t) - pass: 4, fail: 0
test group 1 (g_one) - pass: 4, fail: 0
  test case 1.1 (c_one) - pass: 4, fail: 0
  test case 1.2 (c_two) - pass: 0, fail: 0
test group 2 (g_two) - pass: 0, fail: 0
  test case 2.1 (c_three) - pass: 0, fail: 0
test result done
"""

# The same run with the SECOND occurrence of 1.1.2 failing, and the assertions
# that would have followed it inside that case gone. That is the shape a real
# early return leaves, and it is what the calibration has to recognise.
FLIPPED = GOOD.replace(
    """    test msg: test slot - 0x01
    test assertion 1.1.1 - PASS size - 10
    test assertion 1.1.2 - PASS signature
""",
    """    test msg: test slot - 0x01
    test assertion 1.1.1 - PASS size - 10
    test assertion 1.1.2 - FAIL response signature
""").replace("test suite (t) - pass: 4, fail: 0",
             "test suite (t) - pass: 3, fail: 1").replace(
    "test group 1 (g_one) - pass: 4, fail: 0",
    "test group 1 (g_one) - pass: 3, fail: 1").replace(
    "  test case 1.1 (c_one) - pass: 4, fail: 0",
    "  test case 1.1 (c_one) - pass: 3, fail: 1")


def selftest() -> int:
    bad = 0

    def ok(cond, msg):
        nonlocal bad
        print(("  ok   " if cond else "  FAIL ") + msg)
        if not cond:
            bad = 1

    print("-- the parser agrees with the suite's own footer")
    g = parse(GOOD, "good")
    ok(g["counts"] == {"PASS": 4, "FAIL": 0, "NOT_TESTED": 1},
       f"counts {g['counts']}")
    ok(g["not_tested_invisible_to_footer"] == 1,
       "the NOT_TESTED assertion is counted by neither half of the footer")
    ok([s["id"] for s in g["cases_skipped"]] == ["1.2"],
       "the skipped case is named, though it recorded no assertion")
    ok(g["groups_silent"] == [2],
       "group 2 ran, recorded no pass or fail, and is reported as such")
    ok(len({a["key"] for a in g["assertions"]}) == 5,
       "the repeated assertion id 1.1.1 is two distinct keys, not one")

    print("-- and refuses a log that does not say what it appears to say")
    for name, text, why in (
        ("truncated", GOOD.replace("test result done\n", ""),
         "no 'test result done'"),
        ("footer drifted", GOOD.replace("pass: 4, fail: 0", "pass: 5, fail: 0", 1),
         "counted 4 PASS lines, footer says 5"),
        ("no assertions", "\n".join(
            l for l in GOOD.splitlines() if "test assertion" not in l) + "\n",
         "no assertions recorded"),
    ):
        try:
            parse(text)
            ok(False, f"{name}: accepted, and should not have been")
        except Rejected as why_said:
            ok(why[:20] in str(why_said), f"{name}: refused -- {why_said}")

    print("-- the comparison separates a flip from a cascade")
    f = parse(FLIPPED, "flipped")
    d = compare(g, f)
    ok(len(d["regressed"]) == 1 and d["regressed"][0]["id"] == "1.1.2",
       f"exactly one regression, and it is 1.1.2: {[r['id'] for r in d['regressed']]}")
    ok(d["regressed"][0]["message"] == "response signature",
       "the regression carries the message the calibration requires")
    ok(d["improved"] == [], "no assertion improved")
    ok(d["cases_that_lost_assertions_without_one"] == [],
       "no case lost assertions without a regression of its own")

    print("-- and the reverse comparison is not the same comparison")
    r = compare(f, g)
    ok(len(r["improved"]) == 1 and r["regressed"] == [],
       "flipped -> good is one improvement and no regression")

    print("-- --require-regressed-message rejects the wrong message")
    ok(require_message(d, "response signature") == 0,
       "the right message is accepted")
    ok(require_message(d, "certificate chain") == 1,
       "a message that no regression carries is refused")
    ok(require_message(compare(g, g), "response signature") == 1,
       "a comparison with no regression at all is refused")

    print("-- the markdown table adds up to the counts")
    md = markdown(g)
    ok("**4**" in md and "**1**" in md, "totals row carries the parsed counts")

    print("-- a round trip through JSON changes nothing")
    with tempfile.TemporaryDirectory() as td:
        p = pathlib.Path(td) / "x.json"
        p.write_text(json.dumps(g), encoding="utf-8")
        again = json.loads(p.read_text(encoding="utf-8"))
        ok(compare(g, again)["regressed"] == [] and
           compare(g, again)["disappeared"] == [],
           "a document compared with its own reload is empty in every category")

    return bad


def require_message(d: dict, needle: str) -> int:
    if not d["regressed"]:
        return 1
    if d["improved"]:
        return 1
    return 0 if all(needle in r["message"] for r in d["regressed"]) else 1


# ------------------------------------------------------------------ main ----

def main() -> int:
    ap = argparse.ArgumentParser(
        description="read and compare SPDM-Responder-Validator logs")
    ap.add_argument("--parse", type=pathlib.Path, metavar="TEST_LOG")
    ap.add_argument("--label", default="")
    ap.add_argument("--json", type=pathlib.Path, metavar="OUT")
    ap.add_argument("--compare", type=pathlib.Path, nargs=2, metavar=("A", "B"))
    ap.add_argument("--require-regressed-message", metavar="TEXT",
                    help="exit non-zero unless there is at least one PASS->FAIL, "
                         "every one of them carries TEXT, and nothing improved")
    ap.add_argument("--caps-delta", type=pathlib.Path, nargs=2,
                    metavar=("A_PCAP", "B_PCAP"))
    ap.add_argument("--expect-only", metavar="FLAG",
                    help="with --caps-delta: the ONLY responder capability bit "
                         "allowed to differ between the two captures")
    ap.add_argument("--audit-config", type=pathlib.Path, nargs=2,
                    metavar=("VALIDATOR_SRC", "EMU_CONFIG_C"))
    ap.add_argument("--markdown", type=pathlib.Path, metavar="ASSERTIONS_JSON")
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()

    if args.self_test:
        return selftest()

    if args.parse:
        try:
            doc = parse(args.parse.read_text(errors="replace"), args.label)
        except Rejected as why:
            print(f"  REFUSED  {args.parse}: {why}", file=sys.stderr)
            return 1
        if args.json == pathlib.Path("-"):
            # To stdout, for harness/check_claims.py, which re-derives a
            # published count by re-parsing the committed test.log rather than
            # by reading the assertions.json this same run wrote. Those are two
            # different claims: one says the number came out of the log, the
            # other says two files agree.
            print(json.dumps(doc, indent=2))
            return 0
        if args.json:
            args.json.write_text(json.dumps(doc, indent=2) + "\n", encoding="utf-8")
        print(summarise(doc))
        return 0

    if args.compare:
        a = json.loads(args.compare[0].read_text(encoding="utf-8"))
        b = json.loads(args.compare[1].read_text(encoding="utf-8"))
        d = compare(a, b)
        if args.json:
            args.json.write_text(json.dumps(d, indent=2) + "\n", encoding="utf-8")
        print_compare(d)
        if args.require_regressed_message:
            rc = require_message(d, args.require_regressed_message)
            print("  " + ("ok   " if rc == 0 else "FAIL ")
                  + f"every regression carries {args.require_regressed_message!r}, "
                    "there is at least one, and nothing improved")
            return rc
        return 0

    if args.caps_delta:
        return caps_delta(args.caps_delta[0], args.caps_delta[1], args.expect_only)

    if args.audit_config:
        return audit_config(args.audit_config[0], args.audit_config[1])

    if args.markdown:
        print(markdown(json.loads(args.markdown.read_text(encoding="utf-8"))))
        return 0

    ap.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""harness/check_advisories.py — is this project's own build affected, and how was that decided.

    python3 harness/check_advisories.py --exposure RUNDIR     print the verdicts
    python3 harness/check_advisories.py --check DOC           verify a document's verdicts
    python3 harness/check_advisories.py --selftest            rule 11: can it still say yes
    python3 harness/check_advisories.py --refresh             re-fetch the advisories (network)

WHY A TOOL AND NOT A PARAGRAPH
------------------------------
Three advisories were published against libspdm and DSP0274 in 2026. Two name
version ranges, and this repository pins two libspdm commits. The tempting
answer is to compare version strings, and it is wrong in both directions:

  * a pinned commit is not a release. 4.0.0-rc is not "4.0", and whether the
    fix for a 4.0 advisory is in it is a question about ancestry.
  * a version in the affected range is not a device that can be attacked. The
    2026-0001 code is in cryptlib_mbedtls, which is in the tree and is NOT the
    back end this project links; present and reachable are different facts.

So the verdict is assembled from five independent observations, listed in
harness/run_exposure.sh, and two of them are deliberately redundant: upstream's
own answer about ancestry, and a grep of the source the compiler actually read.
Standing rule 12 — where two routes reach the same quantity they are made to
agree. If they disagree this prints DISAGREEMENT and exits non-zero rather than
choosing, because a single route that is wrong looks exactly like one that is
right.

WHAT IT DOES NOT CLAIM
----------------------
Nothing here is an audit of libspdm, and a verdict of AFFECTED is not a report
of a vulnerability in somebody's product: it is a statement about a build in a
lab on one laptop, assembled from published advisories the vendor has already
fixed. The three advisories are all patched upstream. What this measures is
whether this repository's own pinned trees carry the fixes.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
THIRD_PARTY = REPO / "third_party"
BENCH = REPO / "bench" / "data"

ADVISORIES = ["DMTF-2026-0001", "DMTF-2026-0002", "DMTF-2026-0003"]

# The request each libspdm advisory is reached through. A capture that never
# carries one is a capture the defect could not have touched, and that is
# checkable rather than assertable.
REACHED_BY = {
    "DMTF-2026-0001": "SPDM_GET_CSR",
    "DMTF-2026-0002": "SPDM_GET_MEASUREMENT_EXTENSION_LOG",
}

VERDICT_RE = re.compile(
    r"<!--\s*verdict\s+(?P<key>[A-Za-z0-9_./-]+)\s*=\s*(?P<val>[A-Z-]+)\s*-->")
EXPOSURE_RE = re.compile(r"<!--\s*exposure:\s*(?P<run>[^\s]+)\s*-->")


# ---------------------------------------------------------------------------
# reading what is already committed


def read_pin(name: str) -> dict:
    path = THIRD_PARTY / f"{name}.pin"
    out = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        out[k.strip()] = v.strip()
    return out


def responder_flags() -> tuple[dict[str, int], int]:
    """How many committed captures show the Responder advertising each bit.

    ★ The first version of this took the INTERSECTION over all 98 captures and
    got the wrong answer: it reported CHUNK_CAP as absent, because twelve arms
    of the week-eight matrix clear it ON PURPOSE — that is what `A0-nochunk`
    and `P2-nochunk` are for — and the week-ten conformance arm clears
    MUT_AUTH_CAP for the same kind of reason.

    A bit cleared by an experiment is not a bit the configuration lacks. So
    what comes back is a count per bit, and a precondition is satisfied when
    there is at least one capture advertising every bit it needs, with the
    count printed beside it. "86 of 98" is a fact; "absent" was not.
    """
    counts: dict[str, int] = {}
    seen = 0
    for path in sorted(BENCH.glob("*/*.fields.json")):
        try:
            doc = json.loads(path.read_text(encoding="utf-8"))
        except (ValueError, OSError):
            continue
        flags = doc.get("capabilities", {}).get("responder", {}).get("flags")
        if not isinstance(flags, list):
            continue
        seen += 1
        for f in flags:
            if isinstance(f, str):
                counts[f] = counts.get(f, 0) + 1
    return counts, seen


def captures_with_all(bits: tuple[str, ...]) -> tuple[int, int]:
    """Captures advertising EVERY one of these bits at once, out of the total.

    Two bits each present in most captures are not two bits present together in
    any of them, and DMTF-2026-0002 needs MEL_CAP and CHUNK_CAP at the same
    time. So the conjunction is counted rather than inferred.
    """
    both = total = 0
    for path in sorted(BENCH.glob("*/*.fields.json")):
        try:
            doc = json.loads(path.read_text(encoding="utf-8"))
        except (ValueError, OSError):
            continue
        flags = doc.get("capabilities", {}).get("responder", {}).get("flags")
        if not isinstance(flags, list):
            continue
        total += 1
        if all(b in flags for b in bits):
            both += 1
    return both, total


def messages_seen() -> set[str]:
    """Every SPDM message code that appears in any committed decode."""
    out: set[str] = set()
    for path in sorted(BENCH.glob("*/*.decode.txt")):
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        out.update(re.findall(r"SPDM_[A-Z0-9_]+", text))
    return out


def read_exposure(run: pathlib.Path) -> dict:
    path = run / "exposure.json"
    if not path.is_file():
        sys.exit(f"{path} does not exist — run harness/run_exposure.sh first")
    return json.loads(path.read_text(encoding="utf-8"))


# ---------------------------------------------------------------------------
# the verdict


def fix_state(ev: dict) -> tuple[str, list[str]]:
    """Reconcile the two routes to 'is the fix in this tree'.

    Returns ("present" | "absent" | "disagreement", notes).
    """
    by_line = None
    if ev.get("fixed_line_present") and not ev.get("defective_line_present"):
        by_line = True
    elif ev.get("defective_line_present") and not ev.get("fixed_line_present"):
        by_line = False

    anc = [ev.get("ancestry_3_8_2"), ev.get("ancestry_4_0")]
    known = [a for a in anc if a in ("ahead", "identical", "behind", "diverged")]
    by_anc = None
    if known:
        by_anc = any(a in ("ahead", "identical") for a in known)

    notes = [
        f"source line: {'fixed' if by_line else 'defective' if by_line is False else 'indeterminate'}",
        f"ancestry: 3.8.2 fix {anc[0]}, 4.0 fix {anc[1]}",
    ]
    if by_line is None and by_anc is None:
        return "indeterminate", notes
    if by_line is None:
        return ("present" if by_anc else "absent"), notes + ["decided by ancestry alone"]
    if by_anc is None:
        return ("present" if by_line else "absent"), notes + ["decided by the source alone"]
    if by_line != by_anc:
        return "disagreement", notes + ["★ the two routes disagree"]
    return ("present" if by_line else "absent"), notes + ["both routes agree"]


def verdict_for(advisory: str, flavor: str, fl: dict,
                flags: dict[str, int], msgs: set[str],
                conj=None) -> tuple[str, list[str]]:
    """One verdict. `flags` maps a capability bit to how many captures show it;
    `conj(bits)` answers how many show all of them at once."""
    if conj is None:
        conj = captures_with_all
    ev = fl.get("advisories", {}).get(advisory, {})

    if advisory == "DMTF-2026-0003":
        return "NOT-APPLICABLE", [
            "the affected product is DSP0274 1.4.0, a document, not a library",
            "it is reached through the FINISH transcript, and nothing in this "
            "project has ever established a secure session "
            "(docs/threat-scope.md level 2)",
            "so there is no transcript here to under-cover; "
            "negative/test_transcript_coverage.c models the rule instead",
        ]

    state, notes = fix_state(ev)
    if state == "disagreement":
        return "DISAGREEMENT", notes
    if state == "indeterminate":
        return "INDETERMINATE", notes
    if state == "present":
        return "NOT-AFFECTED", notes + ["the published fix is in this tree"]

    # The fix is absent. Now the preconditions, which decide whether that
    # matters at all.
    pre: list[str] = list(notes)
    blocked: list[str] = []

    if advisory == "DMTF-2026-0001":
        n, total = conj(("CSR_CAP",))
        pre.append(f"CSR_CAP advertised in {n} of {total} committed capture(s)")
        if n == 0:
            blocked.append("no committed capture shows the responder "
                           "advertising CSR_CAP")
        linked = fl.get("cryptlib_linked", "")
        pre.append(f"crypto back end linked: {linked or 'unknown'}")
        if "mbedtls" not in linked:
            blocked.append(
                "the defect is in cryptlib_mbedtls and this build links "
                f"{linked or 'another back end'} — the code is in the tree "
                "and not in the binary")

    if advisory == "DMTF-2026-0002":
        n, total = conj(("MEL_CAP", "CHUNK_CAP"))
        pre.append(f"MEL_CAP and CHUNK_CAP advertised together in {n} of "
                   f"{total} committed capture(s)")
        if n == 0:
            blocked.append("no committed capture shows the responder "
                           "advertising MEL_CAP and CHUNK_CAP at once")
        stops = not (fl.get("assert_expands_to_nothing")
                     and fl.get("copy_mem_copies_after_assert"))
        pre.append(
            "libspdm_copy_mem() stops an oversized copy: "
            + ("yes" if stops else
               "NO — the check is LIBSPDM_ASSERT, TARGET=%s defines "
               "LIBSPDM_DEBUG_ENABLE=0 at CMakeLists.txt:%s, the macro expands "
               "to nothing, and the copy loop runs regardless"
               % (fl.get("build_target"),
                  fl.get("debug_enable_zero_at_cmakelists_line"))))
        if stops:
            blocked.append("libspdm_copy_mem() would refuse the oversized copy")

    reached = REACHED_BY.get(advisory)
    if reached:
        pre.append(
            f"{reached} in any committed capture: "
            + ("yes" if reached in msgs else "no — no experiment here has "
               "ever sent it"))

    if blocked:
        return "PRESENT-NOT-REACHABLE", pre + blocked
    return "AFFECTED", pre + ["every precondition the advisory names holds"]


RELEVANT_BITS = ("MEL_CAP", "CHUNK_CAP", "CSR_CAP")


def all_verdicts(exposure: dict) -> dict:
    flags, nfiles = responder_flags()
    msgs = messages_seen()
    out = {"_flags": {b: flags.get(b, 0) for b in RELEVANT_BITS},
           "_flag_files": nfiles, "verdicts": {}}
    for flavor, fl in exposure.get("flavors", {}).items():
        for adv in ADVISORIES:
            v, why = verdict_for(adv, flavor, fl, flags, msgs)
            out["verdicts"][f"{flavor}/{adv}"] = {"verdict": v, "why": why}
    return out


# ---------------------------------------------------------------------------
# the three entry points


def cmd_exposure(run: pathlib.Path) -> int:
    exposure = read_exposure(run)
    res = all_verdicts(exposure)

    n = res["_flag_files"]
    print(f"  over {n} committed capture(s), the Responder advertised")
    for bit, count in res["_flags"].items():
        print(f"    {bit:<10} in {count} of {n}")
    both, _ = captures_with_all(("MEL_CAP", "CHUNK_CAP"))
    print(f"    MEL_CAP and CHUNK_CAP together in {both} of {n} "
          f"— the rest are arms that cleared one on purpose")
    print()

    bad = 0
    for key, item in res["verdicts"].items():
        print(f"  {item['verdict']:<22} {key}")
        for line in item["why"]:
            print(f"      {line}")
        print()
        if item["verdict"] in ("DISAGREEMENT", "INDETERMINATE"):
            bad += 1
    if bad:
        print(f"  {bad} verdict(s) could not be decided from the evidence")
    return 1 if bad else 0


def cmd_check(doc: pathlib.Path) -> int:
    text = doc.read_text(encoding="utf-8")
    m = EXPOSURE_RE.search(text)
    if not m:
        print(f"  {doc} carries no <!-- exposure: RUNDIR --> directive")
        return 1
    run = REPO / m.group("run")
    res = all_verdicts(read_exposure(run))

    checked = failures = 0
    for line_no, line in enumerate(text.splitlines(), 1):
        for hit in VERDICT_RE.finditer(line):
            key, want = hit.group("key"), hit.group("val")
            got = res["verdicts"].get(key)
            checked += 1
            if got is None:
                print(f"  FAIL line {line_no}: no verdict is computed for '{key}'")
                failures += 1
            elif got["verdict"] != want:
                print(f"  FAIL line {line_no}: {key} says {want}, "
                      f"the evidence says {got['verdict']}")
                failures += 1
    if checked == 0:
        print(f"  {doc} states no verdict this tool can check")
        return 1
    print(f"  {checked - failures}/{checked} verdicts match the evidence "
          f"in {run.name}")
    return 1 if failures else 0


def cmd_selftest() -> int:
    """Standing rule 11: it has to be able to say something else.

    Every branch that can produce a verdict is fed evidence that should produce
    a DIFFERENT one, and the run fails if the answer does not move. A tool that
    reports NOT-AFFECTED for everything would pass a check that only ever asked
    it about a patched tree.
    """
    nomsg: set[str] = set()
    flags: dict[str, int] = {"MEL_CAP": 98, "CHUNK_CAP": 86, "CSR_CAP": 98}

    def conj_all(_bits):        # every bit advertised somewhere
        return (86, 98)

    def conj_none(_bits):       # the capability never appears
        return (0, 98)

    absent = {"fixed_line_present": False, "defective_line_present": True,
              "ancestry_3_8_2": "behind", "ancestry_4_0": "behind"}
    present = {"fixed_line_present": True, "defective_line_present": False,
               "ancestry_3_8_2": "ahead", "ancestry_4_0": "ahead"}
    split = {"fixed_line_present": True, "defective_line_present": False,
             "ancestry_3_8_2": "behind", "ancestry_4_0": "behind"}

    vulnerable_build = {
        "cryptlib_linked": "libcryptlib_mbedtls.a",
        "build_target": "Release",
        "debug_enable_zero_at_cmakelists_line": 886,
        "assert_expands_to_nothing": True,
        "copy_mem_copies_after_assert": True,
    }

    cases = [
        ("a tree without the fix, every precondition met",
         "DMTF-2026-0002", dict(vulnerable_build,
                                advisories={"DMTF-2026-0002": absent}),
         conj_all, "AFFECTED"),
        ("the same tree with the fix in it",
         "DMTF-2026-0002", dict(vulnerable_build,
                                advisories={"DMTF-2026-0002": present}),
         conj_all, "NOT-AFFECTED"),
        ("no fix, but no capture shows MEL_CAP and CHUNK_CAP together",
         "DMTF-2026-0002", dict(vulnerable_build,
                                advisories={"DMTF-2026-0002": absent}),
         conj_none, "PRESENT-NOT-REACHABLE"),
        ("no fix, but the assert is compiled in",
         "DMTF-2026-0002", dict(vulnerable_build,
                                assert_expands_to_nothing=False,
                                advisories={"DMTF-2026-0002": absent}),
         conj_all, "PRESENT-NOT-REACHABLE"),
        ("no fix, mbedtls back end linked",
         "DMTF-2026-0001", dict(vulnerable_build,
                                advisories={"DMTF-2026-0001": absent}),
         conj_all, "AFFECTED"),
        ("no fix, OpenSSL back end linked",
         "DMTF-2026-0001", dict(vulnerable_build,
                                cryptlib_linked="libcryptlib_openssl.a",
                                advisories={"DMTF-2026-0001": absent}),
         conj_all, "PRESENT-NOT-REACHABLE"),
        ("the source says fixed and upstream says the commit is not in",
         "DMTF-2026-0002", dict(vulnerable_build,
                                advisories={"DMTF-2026-0002": split}),
         conj_all, "DISAGREEMENT"),
        ("a document, not a library",
         "DMTF-2026-0003", dict(vulnerable_build, advisories={}),
         conj_all, "NOT-APPLICABLE"),
    ]

    failures = 0
    for name, adv, fl, conj, want in cases:
        got, _ = verdict_for(adv, "selftest", fl, flags, nomsg, conj=conj)
        ok = got == want
        print(f"  {'ok  ' if ok else 'FAIL'}  {want:<22} {name}")
        if not ok:
            print(f"        got {got}")
            failures += 1

    seen = {c[4] for c in cases}
    print(f"\n  {len(cases) - failures}/{len(cases)} cases, "
          f"{len(seen)} distinct verdicts reachable")
    if len(seen) < 5:
        print("  a selftest that cannot reach every verdict is not a selftest")
        failures += 1
    return 1 if failures else 0


def cmd_refresh() -> int:
    """Re-fetch the three advisories and report any drift from the pins.

    Deliberately not part of `verify`. A pull request should not go red because
    somebody else edited a web page; the weekly `upstream` job runs this, which
    is where a change in the outside world belongs.
    """
    import hashlib
    import urllib.request

    url = "https://api.github.com/repos/DMTF/libspdm/security-advisories"
    req = urllib.request.Request(url, headers={
        "Accept": "application/vnd.github+json",
        "User-Agent": "mctp-spdm-pqc check_advisories",
    })
    with urllib.request.urlopen(req, timeout=60) as fh:   # noqa: S310
        records = json.load(fh)

    drift = 0
    for name in ADVISORIES:
        pin = read_pin(name.lower())
        ghsa = pin["ghsa-id"]
        rec = next((r for r in records if r.get("ghsa_id") == ghsa), None)
        if rec is None:
            print(f"  GONE    {name}: {ghsa} is no longer in the response")
            drift += 1
            continue
        blob = json.dumps(rec, indent=2, ensure_ascii=False) + "\n"
        digest = hashlib.sha256(blob.encode()).hexdigest()
        if digest == pin.get("sha256"):
            print(f"  same    {name}  {ghsa}")
            continue
        print(f"  DRIFT   {name}  {ghsa}")
        print(f"            pin  sha256={pin.get('sha256')}  "
              f"updated-at={pin.get('updated-at')}")
        print(f"            now  sha256={digest}  "
              f"updated-at={rec.get('updated_at')}")
        for field, key in (("cve-id", "cve_id"), ("severity", "severity")):
            was, now = pin.get(field), rec.get(key) or "NONE"
            if was != now:
                print(f"            {field}: {was} -> {now}")
        drift += 1
    print(f"\n  {len(ADVISORIES) - drift} unchanged, {drift} drifted")
    return 0    # drift is news, not a failure


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--exposure", metavar="RUNDIR", type=pathlib.Path)
    g.add_argument("--check", metavar="DOC", type=pathlib.Path)
    g.add_argument("--selftest", action="store_true")
    g.add_argument("--refresh", action="store_true")
    args = ap.parse_args()

    if args.selftest:
        return cmd_selftest()
    if args.refresh:
        return cmd_refresh()
    if args.check:
        return cmd_check(args.check)
    return cmd_exposure(args.exposure)


if __name__ == "__main__":
    sys.exit(main())

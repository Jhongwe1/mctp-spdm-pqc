#!/usr/bin/env python3
"""Re-derive every published cross-capture number from the captures it names.

    python3 harness/check_claims.py                 # check bench/claims.json
    python3 harness/check_claims.py --show          # print what each derives to
    python3 harness/check_claims.py --selftest      # and require it to reject

What this is for, and what it is NOT a second copy of
-----------------------------------------------------
`harness/fields.py --check` already re-derives every number a document quotes,
from the capture named beside it. It binds one claim to ONE capture, which is
the right shape for "the measurement record is 528 bytes" and the wrong shape
for the numbers a comparison produces: a ratio has two captures and a delta has
two, and neither belongs to either of them.

So this file owns cross-capture quantities and nothing else. A number derivable
from a single capture should be a `<!--claim k=v-->` in the document that
states it, checked by fields.py, and adding it here as well would create a
second place for it to be right.

Why a value may be null
-----------------------
A claim with `"value": null` is one this project has NOT measured. It is not a
placeholder for a number someone intends to produce; it is a statement that the
quantity is named, the derivation is written, and the answer is not known yet —
usually because a tool cannot reach it. `--show` prints what each derivation
produces, so filling one in is copying a computed number rather than typing a
remembered one, and `claimed: false` keeps it out of the assertion until then.

Tolerances
----------
Every tolerance here is 0.0, and that is a claim of its own. These are BYTES and
ROUND TRIPS re-derived from captures that are committed to the repository, so
there is nothing for a tolerance to absorb: the same file gives the same answer
or the file changed. A non-zero tolerance on a deterministic quantity is a
check that has been asked not to fail.

Exit codes: 0 every claimed value re-derives  ·  1 one does not  ·  2 bad input
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CLAIMS = REPO / "bench" / "claims.json"

_CACHE: dict[tuple[str, str], dict] = {}


class Unreachable(Exception):
    """The derivation names something this repository cannot produce."""


def tool_output(tool: str, capture: str) -> dict:
    """Run one analysis tool over one capture, once per process."""
    key = (tool, capture)
    if key in _CACHE:
        return _CACHE[key]

    if tool == "pcapstat":
        target = REPO / f"{capture}.pcap"
        argv = [sys.executable, str(REPO / "bench" / "pcapstat.py"),
                str(target), "--json"]
        pick = lambda d: d["summary"]          # noqa: E731
    elif tool == "fields":
        target = REPO / f"{capture}.decode.txt"
        argv = [sys.executable, str(REPO / "harness" / "fields.py"),
                str(target), "--json"]
        pick = lambda d: d                     # noqa: E731
    else:
        raise Unreachable(f"no tool called {tool!r}")

    if not target.exists():
        raise Unreachable(f"{target.relative_to(REPO).as_posix()} is not in the repository")
    r = subprocess.run(argv, capture_output=True, text=True)
    if r.returncode != 0:
        raise Unreachable(f"{tool} failed on {capture}: {r.stderr.strip()[:200]}")
    _CACHE[key] = pick(json.loads(r.stdout))
    return _CACHE[key]


def dotted(doc, path: str):
    """Walk a dotted path, and say which segment was missing rather than None.

    A derivation that silently yields None would make a claim unfalsifiable in
    the worst direction: the check would report 'could not derive' for a typo
    and for a genuinely absent measurement in the same words.
    """
    cur = doc
    for i, seg in enumerate(path.split(".")):
        if isinstance(cur, list):
            try:
                cur = cur[int(seg)]
                continue
            except (ValueError, IndexError):
                raise Unreachable(f"{'.'.join(path.split('.')[:i])} has no element {seg}")
        if not isinstance(cur, dict) or seg not in cur:
            here = ".".join(path.split(".")[:i]) or "the document"
            raise Unreachable(f"{here} has no key {seg!r}")
        cur = cur[seg]
    if cur is None:
        raise Unreachable(f"{path} is null in the tool's output")
    return cur


def term(spec: dict) -> float:
    return float(dotted(tool_output(spec["tool"], spec["capture"]), spec["path"]))


def rats_expected_fail_rate(spec: dict) -> float:
    """Of the arms a specification says MUST be rejected, how many were.

    Read from the committed verdicts rather than by re-running the appraisal, so
    that this file needs no policy engine; rats/appraise.py matrix --check is
    what re-derives those verdicts, and CI runs it first.
    """
    expect = json.loads((REPO / spec["expected"]).read_text(encoding="utf-8"))
    out_dir = REPO / spec["verdicts"]
    want_fail = [a for a, v in expect["arms"].items() if v["outcome"] == "fail"]
    if not want_fail:
        raise Unreachable(f"{spec['expected']} names no arm that must fail, so a "
                          f"detection rate over it would be 0/0")
    got = 0
    for arm in want_fail:
        f = out_dir / f"{arm}.verdict.json"
        if not f.exists():
            raise Unreachable(f"no committed verdict for {arm}")
        v = json.loads(f.read_text(encoding="utf-8"))
        if (v.get("result") or {}).get("verdict") == "fail":
            got += 1
    return got / len(want_fail)


def derive(d: dict) -> float:
    kind = d["kind"]
    if kind == "ratio":
        den = term(d["denominator"])
        if den == 0:
            raise Unreachable("the denominator derives to zero")
        return term(d["numerator"]) / den
    if kind == "delta":
        return term(d["minuend"]) - term(d["subtrahend"])
    if kind == "value":
        return term(d["of"])
    if kind == "rats_expected_fail_rate":
        return rats_expected_fail_rate(d)
    raise Unreachable(f"no derivation called {kind!r}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--claims", type=Path, default=CLAIMS)
    ap.add_argument("--show", action="store_true",
                    help="print what every derivation produces, claimed or not")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()

    if args.selftest:
        return selftest()

    doc = json.loads(args.claims.read_text(encoding="utf-8"))
    claims = doc["claims"]
    failures = 0
    checked = 0
    unclaimed = 0

    print(f"  claims  : {args.claims.relative_to(REPO).as_posix()}")
    for name, c in claims.items():
        try:
            got = derive(c["derivation"])
        except Unreachable as e:
            if c.get("value") is None:
                unclaimed += 1
                print(f"  --    {name}: not measured — {e}")
                continue
            print(f"  FAIL  {name}: a claimed value cannot be re-derived — {e}")
            failures += 1
            continue

        if c.get("value") is None:
            unclaimed += 1
            print(f"  --    {name}: derives to {got:.6g}, and claims nothing")
            continue

        want = float(c["value"])
        tol = float(c.get("tolerance_pct", 0.0)) / 100.0
        slack = abs(want) * tol
        checked += 1
        if abs(got - want) <= slack:
            print(f"  ok    {name}: {got:.6g}")
        else:
            print(f"  FAIL  {name}: published {want:.6g}, re-derives to {got:.6g}"
                  + (f" (tolerance {c['tolerance_pct']}%)" if tol else
                     " — tolerance is zero because this is a byte count"))
            failures += 1

    if args.show:
        print()
        for name, c in claims.items():
            print(f"  {name}\n      {c.get('meaning', '')}")

    print()
    print(f"{checked} claimed value(s) re-derived, {unclaimed} named and not "
          f"measured, {failures} failed")
    return 1 if failures else 0


def selftest() -> int:
    """Require the checker to reject a number that has drifted.

    Standing rule 11. The interesting direction is a claim that is WRONG rather
    than absent: an absent one is loud by construction, and a wrong one is the
    thing this file exists to catch.
    """
    doc = json.loads(CLAIMS.read_text(encoding="utf-8"))
    claimed = [(n, c) for n, c in doc["claims"].items() if c.get("value") is not None]
    if not claimed:
        print("  no claim carries a value yet, so nothing can be drifted")
        return 0

    fails = 0
    name, c = claimed[0]
    for factor, what in ((1.01, "one percent high"), (0.99, "one percent low")):
        drifted = json.loads(json.dumps(doc))
        drifted["claims"][name]["value"] = float(c["value"]) * factor
        import tempfile
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False,
                                         encoding="utf-8") as fh:
            json.dump(drifted, fh)
            path = fh.name
        r = subprocess.run([sys.executable, __file__, "--claims", path],
                           capture_output=True, text=True)
        Path(path).unlink(missing_ok=True)
        if r.returncode == 0:
            print(f"  FAIL a value {what} was accepted: {name}")
            fails += 1
        else:
            print(f"  ok   a value {what} is refused: {name}")

    r = subprocess.run([sys.executable, __file__], capture_output=True, text=True)
    if r.returncode != 0:
        print("  FAIL the unmodified claims file does not pass")
        print(r.stdout[-800:])
        fails += 1
    else:
        print("  ok   the unmodified claims file passes")
    print()
    print(f"3 checks, {fails} failed")
    return 1 if fails else 0


if __name__ == "__main__":
    raise SystemExit(main())

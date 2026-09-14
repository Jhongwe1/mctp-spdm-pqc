#!/usr/bin/env python3
"""Refuse a CI job that runs a pinned tool its runner will not have.

    python3 harness/lib/ci_tools_check.py            # this repository
    python3 harness/lib/ci_tools_check.py <root>     # a copy, for the self-test

Why this exists
---------------
Added 2026-09-14, after the build badge had been red for two days and nobody
had looked at it.

`harness/verify_repo.sh` hard-fails when `opa` is absent. That is deliberate
and it is the right behaviour — 2026-09-13: a self-test that passes by not
running is worse than no self-test. The `verify` job runs that script, and it
never installed `opa`. So the most important check in the repository failed on
every push, for exactly the reason it was designed to fail, inside a job whose
environment could not satisfy it.

Two things were true at once and neither was visible from the other: the script
was right, and the job was wrong.

What is checked
---------------
The invariant is not about `opa`:

> **A job must not run a tool it does not install.**

`third_party/*.pin` already records which files consume which tool, in its
`consumed-by=` field, and `opa.pin` already named both `harness/verify_repo.sh`
and `.github/workflows/ci.yml` before any of this was written. So the
requirement is derived from the pin rather than restated here. A second list
would be a second thing to keep in step with the first, which is the shape of
the defect being fixed.

For every pin that names the workflow as a consumer, and for every job in that
workflow whose steps mention another of that pin's consumers, the job must also
contain a step that installs the tool.

Exit codes: 0 every pairing is installed where it is run · 1 one is not ·
2 the workflow could not be read
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

WORKFLOW = Path(".github/workflows/ci.yml")

# A job header is a two-space-indented key under `jobs:`. A YAML parser would be
# more correct and is not present on a bare runner; this file's shape is fixed,
# and GitHub itself rejects a malformed workflow on every push, so a parse error
# here would be the second report of the same fact rather than the first.
JOB_RE = re.compile(r"^  ([A-Za-z0-9_-]+):$", re.M)


def jobs_of(text: str) -> dict[str, str]:
    head, _, rest = text.partition("\njobs:")
    if not rest:
        return {}
    marks = [(m.start(), m.group(1)) for m in JOB_RE.finditer(rest)]
    out = {}
    for i, (off, name) in enumerate(marks):
        end = marks[i + 1][0] if i + 1 < len(marks) else len(rest)
        out[name] = rest[off:end]
    return out


def pin_fields(path: Path) -> dict[str, str]:
    fields = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        fields[key.strip()] = value.strip()
    return fields


def main() -> int:
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(".")
    ci = root / WORKFLOW
    if not ci.exists():
        print(f"  no {WORKFLOW.as_posix()} — nothing to check")
        return 2

    jobs = jobs_of(ci.read_text(encoding="utf-8"))
    if not jobs:
        print(f"  FAIL {WORKFLOW.as_posix()} declares no jobs this check can read")
        return 2

    problems: list[str] = []
    pairings = 0

    for pin in sorted((root / "third_party").glob("*.pin")):
        fields = pin_fields(pin)
        tool = fields.get("tool")
        consumed = [c.strip() for c in fields.get("consumed-by", "").split(",")
                    if c.strip()]
        if not tool:
            continue
        if WORKFLOW.as_posix() not in [c.replace("\\", "/") for c in consumed]:
            continue

        # Everything the pin names except the workflow itself: a job that runs
        # one of these is a job that needs the tool on PATH.
        runnable = [c for c in consumed if not c.endswith((".yml", ".yaml"))]

        for name, job in sorted(jobs.items()):
            runs = sorted({c for c in runnable if Path(c).name in job})
            if not runs:
                continue
            pairings += 1
            installs = (re.search(r"name:.*[Ii]nstall.*" + re.escape(tool), job)
                        is not None) or (f"{tool} version" in job)
            if installs:
                continue
            problems.append(
                f"job '{name}' runs {', '.join(runs)} and never installs "
                f"{tool}. {pin.name} names both, so the pin knew before CI did")

    for p in problems:
        print(f"  FAIL {p}")
    if problems:
        return 1
    if pairings:
        print(f"  {pairings} job/tool pairing(s), each installed where it is run")
    else:
        print("  --   no pinned tool names both a job's script and the workflow")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

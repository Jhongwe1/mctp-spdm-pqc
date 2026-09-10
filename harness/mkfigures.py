#!/usr/bin/env python3
"""Draw the figures, from the data, so they cannot drift away from it.

    python3 harness/mkfigures.py               # write figures/
    python3 harness/mkfigures.py --check       # regenerate and require no change
    python3 harness/mkfigures.py --list        # what each figure is made of

Why a script and not a drawing
------------------------------
`CLAUDE.md` and `figures/README.md` both say every figure here is produced by a
script from a run directory, and none is drawn by hand. The rule is not about
tooling. A hand-drawn figure carries numbers that were correct on the day it
was exported, and nothing afterwards notices when they stop being — which is
the same failure this repository has spent two weeks finding in prose.

So every number that appears in a figure is read from the same place the
documents read theirs, and `--check` re-renders and requires the committed file
to be byte-identical. `harness/verify_repo.sh` runs it.

`figures/` was empty from 2026-08-11 until 2026-09-10 while `README.md`'s
repository layout listed it, which is the "table indexing a directory" shape of
the same problem, aimed at a directory with nothing in it.

Why SVG, and why it looks the way it does
-----------------------------------------
GitHub renders an SVG referenced from Markdown as an image, which means no CSS
from the page reaches it and `prefers-color-scheme` inside it does not apply.
So the figure carries its own light background rather than inheriting one, and
the text is dark enough to read against it in either theme. Fonts are a generic
stack: this project's host has no CJK fonts installed, which is one of the
reasons everything on a figure here is in English, and depending on a font
somebody else may not have is the other.

Exit codes: 0 ok · 1 --check found a difference · 2 the inputs are missing
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
FIGURES = REPO / "figures"

# ── the palette, chosen to be legible on a white page and on a dark one ──────
INK = "#1f2933"
MUTED = "#52606d"
FAINT = "#9aa5b1"
PAPER = "#fbfcfd"
LINE = "#7b8794"
ACCENT = "#2b6cb0"
WIRE = "#276749"
MONO = "ui-monospace, SFMono-Regular, Menlo, Consolas, monospace"
SANS = "system-ui, -apple-system, Segoe UI, Helvetica, Arial, sans-serif"


class Missing(Exception):
    """An input a figure needs is not here."""


def _tool(script: str, *args: str) -> dict:
    out = subprocess.run([sys.executable, str(REPO / script), *args],
                         capture_output=True, text=True)
    if out.returncode not in (0, 1) or not out.stdout.strip():
        raise Missing(f"{script} produced nothing: {out.stderr.strip()[:160]}")
    return json.loads(out.stdout)


def _esc(text: str) -> str:
    return (text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))


def _text(x, y, s, *, size=13, fill=INK, family=SANS, weight="normal",
          anchor="start") -> str:
    return (f'<text x="{x}" y="{y}" font-family="{family}" font-size="{size}" '
            f'font-weight="{weight}" fill="{fill}" text-anchor="{anchor}">'
            f'{_esc(s)}</text>')


def _box(x, y, w, h, *, stroke=LINE, fill="#ffffff", width=1.4) -> str:
    return (f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="6" '
            f'fill="{fill}" stroke="{stroke}" stroke-width="{width}"/>')


# ─────────────────────────────────────────── figure 1 ────────────────────────


def figure_1() -> tuple[str, list[str]]:
    """The chain, its three certificates, and what it costs on the wire.

    Sources, and the point is that there are three of them:
      certs/check_chain.py  the DER files on disk — never opens a capture
      harness/fields.py     spdm_dump's decode    — never opens a certificate
      bench/pcapstat.py     the capture file      — opens neither
    """
    sources: list[str] = []

    chain = _tool("certs/check_chain.py", str(REPO / "certs/out"), "--json")
    sources.append("certs/check_chain.py, from certs/out/*.der")
    bundle = chain["bundles"]["bundle_responder.certchain.der"]
    sizes = bundle["certificates"]
    names = ["ca.cert.der", "inter.cert.der", "end_responder.cert.der"]
    roles = ["self-signed root", "intermediate", "leaf — signs CHALLENGE_AUTH"]
    root_hash = bundle["root_hash"]
    hash_name = bundle["root_hash_algorithm"]
    on_wire = bundle["chain_length_on_wire"]
    der_total = bundle["bundle_bytes"]
    san = chain["subject_alt_names"]["end_responder"]["1.3.6.1.4.1.412.274.1"]

    # The same number, read off a capture by a tool that never sees a
    # certificate. Which capture is data, not a constant: the newest committed
    # tamper run's clean arm.
    runs = sorted((REPO / "bench/data").glob("*-tamper-*"))
    if not runs:
        raise Missing("no tamper run in bench/data to read the wire length from")
    run = runs[-1]
    fields = json.loads((run / "t0_clean.fields.json").read_text())
    sources.append(f"harness/fields.py, from {run.name}/t0_clean")
    chains = [c for c in (fields.get("layout") or {}).get("chains", [])
              if c.get("direction") == "RSP->REQ" and c.get("slot") == 0]
    if not chains:
        raise Missing(f"{run.name}/t0_clean carries no slot-0 chain")
    measured = chains[0]["chain_length"]

    stats = _tool("bench/pcapstat.py", str(run / "t0_clean.pcap"), "--json")
    sources.append(f"bench/pcapstat.py, from {run.name}/t0_clean.pcap")
    slots = [s for s in stats["summary"]["certificates"]["slots"]
             if s["slot"] == 0 and s["closes"]]
    if not slots:
        raise Missing("pcapstat reassembled no slot-0 chain")
    reassembled = slots[0]["chain_bytes"]
    roundtrips = stats["summary"]["certificates"]["roundtrips"]
    hash_bytes = stats["summary"]["certificates"]["root_hash_bytes"]

    W, H = 780, 560
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" '
           f'viewBox="0 0 {W} {H}" role="img" '
           f'aria-label="The three-layer certificate chain and its size on the wire">',
           f'<rect width="{W}" height="{H}" fill="{PAPER}"/>']

    out.append(_text(32, 40, "Figure 1 — the chain, and what it costs on the wire",
                     size=18, weight="600"))
    out.append(_text(32, 62,
                     "Three certificates generated by certs/gen_chain.sh; every "
                     "number below is read, not drawn.", size=12, fill=MUTED))

    # ── the three certificates ──────────────────────────────────────────────
    bx, by, bw, bh, gap = 32, 92, 330, 62, 26
    for i, (name, role, size) in enumerate(zip(names, roles, sizes)):
        y = by + i * (bh + gap)
        out.append(_box(bx, y, bw, bh))
        out.append(_text(bx + 16, y + 25, name, size=13, family=MONO,
                         weight="600"))
        out.append(_text(bx + 16, y + 44, role, size=11.5, fill=MUTED))
        out.append(_text(bx + bw - 16, y + 36, f"{size} B", size=15,
                         family=MONO, fill=ACCENT, weight="600", anchor="end"))
        if i < len(names) - 1:
            ay = y + bh
            out.append(f'<line x1="{bx + 60}" y1="{ay}" x2="{bx + 60}" '
                       f'y2="{ay + gap}" stroke="{LINE}" stroke-width="1.4"/>')
            out.append(f'<polygon points="{bx + 56},{ay + gap - 7} '
                       f'{bx + 64},{ay + gap - 7} {bx + 60},{ay + gap}" '
                       f'fill="{LINE}"/>')
            out.append(_text(bx + 74, ay + 18, "signs", size=11, fill=MUTED))

    leaf_y = by + 2 * (bh + gap)
    out.append(_text(bx + 16, leaf_y + bh + 22,
                     "SubjectAltName, otherName 1.3.6.1.4.1.412.274.1",
                     size=10.5, fill=FAINT))
    out.append(_text(bx + 16, leaf_y + bh + 38, san, size=11, family=MONO,
                     fill=MUTED))

    # ── the wire arithmetic ─────────────────────────────────────────────────
    wx, wy, ww = 418, 92, 330
    out.append(_box(wx, wy, ww, 214, stroke=WIRE, fill="#ffffff"))
    out.append(_text(wx + 18, wy + 28, "in one CERTIFICATE message", size=13,
                     weight="600", fill=WIRE))
    rows = [
        ("4", "Length", "uint32, the chain's own size"),
        (f"{hash_bytes}", "RootHash", f"{hash_name} of ca.cert.der"),
        (f"{der_total}", "certificates",
         " + ".join(str(s) for s in sizes)),
    ]
    ry = wy + 56
    for value, label, note in rows:
        out.append(_text(wx + 78, ry, value, size=14, family=MONO, anchor="end",
                         weight="600"))
        out.append(_text(wx + 92, ry, label, size=12.5))
        out.append(_text(wx + 92, ry + 16, note, size=10.5, fill=FAINT))
        ry += 44
    out.append(f'<line x1="{wx + 18}" y1="{ry - 26}" x2="{wx + ww - 18}" '
               f'y2="{ry - 26}" stroke="{LINE}" stroke-width="1"/>')
    out.append(_text(wx + 78, ry, str(on_wire), size=18, family=MONO,
                     anchor="end", weight="700", fill=WIRE))
    out.append(_text(wx + 92, ry, "bytes on the wire", size=13, weight="600"))
    out.append(_text(wx + 92, ry + 17,
                     f"in {roundtrips} GET_CERTIFICATE round trips", size=10.5,
                     fill=FAINT))

    out.append(_text(wx + 18, wy + 246, f"RootHash  {root_hash[:32]}…", size=10.5,
                     family=MONO, fill=MUTED))

    # ── three tools, one number ─────────────────────────────────────────────
    ax, ay = 32, 452
    out.append(_box(ax, ay, W - 64, 78, stroke=ACCENT, fill="#ffffff"))
    out.append(_text(ax + 18, ay + 24,
                     "The same number, by three routes that share no input",
                     size=13, weight="600", fill=ACCENT))
    trio = [
        ("certs/check_chain.py", "the DER files", on_wire),
        ("harness/fields.py", "spdm_dump's decode", measured),
        ("bench/pcapstat.py", "the capture file", reassembled),
    ]
    tx = ax + 18
    for tool, what, value in trio:
        out.append(_text(tx, ay + 48, tool, size=11, family=MONO))
        out.append(_text(tx, ay + 64, what, size=10.5, fill=FAINT))
        out.append(_text(tx + 196, ay + 50, str(value), size=14, family=MONO,
                         weight="700", fill=ACCENT, anchor="end"))
        tx += 236

    out.append("</svg>")
    return "\n".join(out) + "\n", sources


FIGURES_BY_NAME = {
    "fig1-certificate-chain.svg": figure_1,
}


def main() -> int:
    ap = argparse.ArgumentParser(description="render figures/ from the data")
    ap.add_argument("--check", action="store_true",
                    help="regenerate and require the committed file to match")
    ap.add_argument("--list", action="store_true",
                    help="print what each figure is made of")
    args = ap.parse_args()

    FIGURES.mkdir(exist_ok=True)
    differed = 0
    for name, builder in sorted(FIGURES_BY_NAME.items()):
        path = FIGURES / name
        try:
            svg, sources = builder()
        except Missing as why:
            print(f"  {name}: {why}", file=sys.stderr)
            return 2
        if args.list:
            print(f"  {name}")
            for s in sources:
                print(f"      {s}")
            continue
        if args.check:
            have = path.read_text(encoding="utf-8") if path.exists() else None
            if have == svg:
                print(f"  ok    {name} still renders to what is committed "
                      f"({len(svg)} bytes)")
            else:
                differed += 1
                if have is None:
                    print(f"  FAIL  {name} is not committed")
                else:
                    print(f"  FAIL  {name} no longer matches its data "
                          f"({len(have)} bytes committed, {len(svg)} rendered)")
            continue
        path.write_text(svg, encoding="utf-8", newline="\n")
        print(f"  wrote {path.relative_to(REPO)}  ({len(svg)} bytes)")
        for s in sources:
            print(f"      from {s}")
    return 1 if differed else 0


if __name__ == "__main__":
    sys.exit(main())

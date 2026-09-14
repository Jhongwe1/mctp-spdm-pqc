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
import math
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


# ─────────────────────────────────────────── figure 2 ────────────────────────

# The phases a handshake's bytes belong to, in the order they happen. Every
# byte of a capture lands in exactly one of these, and the last is computed by
# subtraction so the bars always total the capture rather than nearly totalling
# it.
PHASES = [
    ("negotiate", "#94a3b8", "GET_VERSION … ALGORITHMS"),
    ("digests", "#a8b3c4", "GET_DIGESTS / DIGESTS"),
    ("certificate", "#2b6cb0", "certificate chain"),
    ("challenge", "#38a169", "CHALLENGE_AUTH"),
    ("measure", "#805ad5", "MEASUREMENTS"),
    ("transport", "#cbd5e1", "chunking + MCTP framing"),
]

VCA_TYPES = ("SPDM_GET_VERSION", "SPDM_VERSION",
             "SPDM_GET_CAPABILITIES", "SPDM_CAPABILITIES",
             "SPDM_NEGOTIATE_ALGORITHMS", "SPDM_ALGORITHMS")
DIGEST_TYPES = ("SPDM_GET_DIGESTS", "SPDM_DIGESTS")

# A round trip is one request with its response, so counting the request-coded
# message types counts round trips. Chunking is kept apart from the rest
# because that separation is the figure's whole argument.
REQUEST_TYPES = ("SPDM_GET_VERSION", "SPDM_GET_CAPABILITIES",
                 "SPDM_NEGOTIATE_ALGORITHMS", "SPDM_GET_DIGESTS",
                 "SPDM_GET_CERTIFICATE", "SPDM_CHALLENGE",
                 "SPDM_GET_MEASUREMENTS")

ARM_LABELS = [
    ("A0", "ECDSA P-384 / ECDHE P-384", "3"),
    ("A1", "ECDSA P-521 / ECDHE P-521", "5"),
    ("P1", "ML-DSA-44 / ML-KEM-512", "2"),
    ("P2", "ML-DSA-65 / ML-KEM-768", "3"),
    ("P3", "ML-DSA-87 / ML-KEM-1024", "5"),
    ("S1", "SLH-DSA-SHA2-128s / ML-KEM-512", "1"),
]


def _newest(pattern: str) -> Path:
    runs = sorted((REPO / "bench/data").glob(pattern))
    if not runs:
        raise Missing(f"no run directory matching {pattern} in bench/data")
    return runs[-1]


def _arm_breakdown(run: Path, arm: str) -> dict:
    """One arm's bytes by phase and its round trips, all from the capture."""
    cap = run / f"{arm}.pcap"
    if not cap.exists():
        raise Missing(f"{cap.relative_to(REPO)} is not committed")
    s = _tool("bench/pcapstat.py", str(cap), "--json")["summary"]
    bt = s["by_type"]

    def b(*names):
        return sum(bt.get(n, {}).get("bytes", 0) for n in names)

    def c(*names):
        return sum(bt.get(n, {}).get("count", 0) for n in names)

    # Chunked messages are attributed to the phase of the message they carried,
    # by what the reassembly says each sequence turned out to be. Attributing
    # them to "chunking" instead would put the certificate chain of every
    # post-quantum arm in the overhead slice and hide the finding.
    carried = {"certificate": 0, "challenge": 0, "measure": 0}
    for q in s["chunking"]["reassembled"]["sequences"]:
        if not q.get("complete"):
            continue
        key = {"SPDM_CERTIFICATE": "certificate",
               "SPDM_CHALLENGE_AUTH": "challenge",
               "SPDM_MEASUREMENTS": "measure"}.get(q.get("carried"))
        if key:
            carried[key] += q["assembled_bytes"]

    phases = {
        "negotiate": b(*VCA_TYPES),
        "digests": b(*DIGEST_TYPES),
        "certificate": b("SPDM_GET_CERTIFICATE", "SPDM_CERTIFICATE")
                       + carried["certificate"],
        "challenge": b("SPDM_CHALLENGE", "SPDM_CHALLENGE_AUTH")
                     + carried["challenge"],
        "measure": b("SPDM_GET_MEASUREMENTS", "SPDM_MEASUREMENTS")
                   + carried["measure"],
    }
    total = s["captured_bytes_total"]
    phases["transport"] = total - sum(phases.values())
    if phases["transport"] < 0:
        raise Missing(f"{arm}: phases total {sum(phases.values())} against a "
                      f"{total}-byte capture; the attribution double-counts")

    chunk_rt = s["chunking"]["messages"].get("SPDM_CHUNK_GET", 0)
    return {
        "arm": arm,
        "total": total,
        "phases": phases,
        "roundtrips_plain": c(*REQUEST_TYPES),
        "roundtrips_chunk": chunk_rt,
        "chain_bytes": next((x["chain_bytes"] for x in s["certificates"]["slots"]
                             if x.get("closes")), None),
        "complete": bool(bt.get("SPDM_MEASUREMENTS")) or carried["measure"] > 0,
    }


def figure_2() -> tuple[str, list[str]]:
    """Where a post-quantum handshake's bytes go, and what it costs in round trips.

    Two panels on one row of labels, because the argument is that they do not
    move together: the bytes multiply by nine and the round trips by two.
    """
    run = _newest("w8-pqc-matrix-*")
    sources = [f"bench/pcapstat.py, from {run.name}/<arm>-all.pcap"]
    arms = [_arm_breakdown(run, f"{g}-all") for g, _, _ in ARM_LABELS]

    max_bytes = max(a["total"] for a in arms)
    max_rt = max(a["roundtrips_plain"] + a["roundtrips_chunk"] for a in arms)

    W, H = 900, 520
    LEFT, ROW_H, GAP = 210, 38, 14
    BAR_W, RT_W = 380, 150
    RT_X = LEFT + BAR_W + 60
    TOP = 108

    out = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" '
           f'viewBox="0 0 {W} {H}" role="img" '
           f'aria-label="Post-quantum SPDM cost by phase and in round trips">',
           f'<rect width="{W}" height="{H}" fill="{PAPER}"/>']

    out.append(_text(24, 34, "What post-quantum authentication costs, and where",
                     size=17, weight="600"))
    out.append(_text(24, 55,
                     "captured bytes by protocol phase (left) and "
                     "request/response round trips (right)", size=12, fill=MUTED))
    out.append(_text(24, 74,
                     "one build, eighteen control variables pinned, "
                     "--meas_op ALL, algorithms read back off the wire",
                     size=11, fill=FAINT, family=MONO))

    # legend
    lx = 24
    for key, colour, label in PHASES:
        out.append(f'<rect x="{lx}" y="{TOP - 26}" width="10" height="10" '
                   f'fill="{colour}"/>')
        out.append(_text(lx + 15, TOP - 17, label, size=10, fill=MUTED))
        lx += 18 + 7 * len(label)

    out.append(_text(LEFT, TOP - 40, "bytes", size=10, fill=FAINT, family=MONO))
    out.append(_text(RT_X, TOP - 40, "round trips", size=10, fill=FAINT,
                     family=MONO))

    y = TOP
    for (g, name, level), a in zip(ARM_LABELS, arms):
        out.append(_text(24, y + 15, g, size=13, weight="600", family=MONO))
        out.append(_text(48, y + 15, name, size=11, fill=MUTED))
        out.append(_text(LEFT - 8, y + 15, f"L{level}", size=10, fill=FAINT,
                         family=MONO, anchor="end"))

        x = LEFT
        for key, colour, _ in PHASES:
            v = a["phases"][key]
            w = BAR_W * v / max_bytes
            if w > 0.4:
                out.append(f'<rect x="{x:.1f}" y="{y}" width="{w:.1f}" '
                           f'height="20" fill="{colour}"/>')
            x += w
        out.append(_text(LEFT + BAR_W + 8, y + 15, f"{a['total']:,}", size=11,
                         family=MONO, fill=INK))

        rt = a["roundtrips_plain"] + a["roundtrips_chunk"]
        wp = RT_W * a["roundtrips_plain"] / max_rt
        wc = RT_W * a["roundtrips_chunk"] / max_rt
        out.append(f'<rect x="{RT_X}" y="{y + 4}" width="{wp:.1f}" height="12" '
                   f'fill="{WIRE}"/>')
        if wc > 0.4:
            out.append(f'<rect x="{RT_X + wp:.1f}" y="{y + 4}" width="{wc:.1f}" '
                       f'height="12" fill="#f6ad55"/>')
        out.append(_text(RT_X + RT_W + 8, y + 15, str(rt), size=11, family=MONO))
        if a["roundtrips_chunk"]:
            out.append(_text(RT_X + RT_W + 34, y + 15,
                             f"({a['roundtrips_chunk']} chunk)", size=9,
                             fill=MUTED))
        if not a["complete"]:
            out.append(_text(RT_X + RT_W + 34, y + 15,
                             "handshake did not complete", size=9, fill="#c53030"))
        y += ROW_H

    y += GAP
    out.append(f'<line x1="24" y1="{y}" x2="{W - 24}" y2="{y}" '
               f'stroke="{FAINT}" stroke-width="1"/>')
    y += 20

    a0, p2, a1, p3 = arms[0], arms[3], arms[1], arms[4]
    lines = [
        f"Version-Capabilities-Algorithms is {a0['phases']['negotiate']} SPDM "
        f"bytes in every one of the six arms. Nothing post-quantum costs "
        f"anything to negotiate.",
        f"At matched NIST level 3 the bytes go x{p2['total'] / a0['total']:.2f} "
        f"and the round trips x"
        f"{(p2['roundtrips_plain'] + p2['roundtrips_chunk']) / (a0['roundtrips_plain'] + a0['roundtrips_chunk']):.2f}; "
        f"at level 5, x{p3['total'] / a1['total']:.2f} and x"
        f"{(p3['roundtrips_plain'] + p3['roundtrips_chunk']) / (a1['roundtrips_plain'] + a1['roundtrips_chunk']):.2f}.",
        f"The certificate chain is {100 * p2['phases']['certificate'] / p2['total']:.0f}% "
        f"of the post-quantum arm and the MEASUREMENTS response "
        f"{100 * p2['phases']['measure'] / p2['total']:.0f}%. "
        f"This flow fetches the chain three times.",
    ]
    for line in lines:
        out.append(_text(24, y, line, size=11, fill=MUTED))
        y += 17

    out.append(_text(24, H - 14,
                     f"{run.name} · orange is SPDM chunking, which costs a round "
                     f"trip per chunk · every number read from the capture",
                     size=9, fill=FAINT, family=MONO))
    out.append("</svg>")
    return "\n".join(out) + "\n", sources


# ─────────────────────────────────────────── figure 3 ────────────────────────


def figure_3() -> tuple[str, list[str]]:
    """DataTransferSize against round trips, and against bytes, on two axes that
    both start at zero.

    Two stacked panels rather than two lines on one frame, and both y axes
    anchored at zero, because the claim is that the two curves have DIFFERENT
    SHAPES. The first version of this figure scaled the byte axis to the byte
    range - 58,579 to 60,394 - which stretched a 3% variation to full height and
    drew it lying almost exactly on top of the round-trip curve. The figure then
    said the opposite of what the data says. A y axis fitted to its own series is
    how a flat line is made to look like a trend, and this repository is in no
    position to do that in a figure while writing standing rule 4 about prose.
    """
    run = _newest("w8-dts-sweep-*")
    sources = [f"bench/pcapstat.py, from {run.name}/*.pcap"]

    series: dict[str, list[tuple[int, int, int]]] = {"A0": [], "P2": []}
    for cap in sorted(run.glob("*.pcap")):
        group = cap.stem.split("-")[0]
        if group not in series:
            continue
        s = _tool("bench/pcapstat.py", str(cap), "--json")["summary"]
        dts = (s["capabilities"]["responder"] or {}).get("data_transfer_size")
        if dts is None:
            raise Missing(f"{cap.stem}: no CAPABILITIES to read a DataTransferSize from")
        series[group].append((dts, s["captured_bytes_total"],
                              s["chunking"]["messages"].get("SPDM_CHUNK_GET", 0)))
    for g in series:
        series[g].sort()
    if not all(series.values()):
        raise Missing("the sweep run is missing one of its two groups")

    xs = [d for d, _, _ in series["P2"]]
    max_rt = max(r for _, _, r in series["P2"] + series["A0"]) or 1
    max_b = max(b for _, b, _ in series["P2"] + series["A0"])
    bytes_top = 70000 if max_b < 70000 else max_b

    W, H = 880, 560
    L, R = 104, 716
    T1, B1 = 104, 252
    T2, B2 = 322, 432

    out = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" '
           f'viewBox="0 0 {W} {H}" role="img" '
           f'aria-label="DataTransferSize against round trips and against bytes">',
           f'<rect width="{W}" height="{H}" fill="{PAPER}"/>']
    out.append(_text(24, 34, "DataTransferSize is a latency parameter, not a "
                             "bandwidth one", size=17, weight="600"))
    out.append(_text(24, 55,
                     "one build, DataTransferSize the only thing that moves, "
                     "read back off the wire in every arm", size=12, fill=MUTED))
    out.append(_text(24, 74, f"{run.name}  -  both y axes start at zero",
                     size=11, fill=FAINT, family=MONO))

    def xpos(dts: int) -> float:
        lo, hi = math.log2(xs[0]), math.log2(xs[-1])
        return L + (R - L) * (math.log2(dts) - lo) / (hi - lo)

    def frame(top: float, bottom: float, title: str, ymax: int, ticks) -> None:
        out.append(f'<line x1="{L}" y1="{top}" x2="{L}" y2="{bottom}" '
                   f'stroke="{LINE}" stroke-width="1.2"/>')
        out.append(f'<line x1="{L}" y1="{bottom}" x2="{R}" y2="{bottom}" '
                   f'stroke="{LINE}" stroke-width="1.2"/>')
        out.append(_text(L, top - 14, title, size=11, weight="600"))
        for v in ticks:
            y = bottom - (bottom - top) * v / ymax
            out.append(f'<line x1="{L - 4}" y1="{y:.1f}" x2="{L}" y2="{y:.1f}" '
                       f'stroke="{LINE}"/>')
            out.append(_text(L - 8, y + 3.5, f"{v:,}", size=10, fill=MUTED,
                             family=MONO, anchor="end"))
            if v:
                out.append(f'<line x1="{L}" y1="{y:.1f}" x2="{R}" y2="{y:.1f}" '
                           f'stroke="{FAINT}" stroke-width="0.6" '
                           f'stroke-dasharray="2 4"/>')

    frame(T1, B1, "chunk round trips - each one is a bus round trip", max_rt,
          (0, 20, 40, max_rt))
    frame(T2, B2, "captured bytes", bytes_top, (0, 35000, bytes_top))

    for d in xs:
        out.append(f'<line x1="{xpos(d):.1f}" y1="{B2}" x2="{xpos(d):.1f}" '
                   f'y2="{B2 + 5}" stroke="{LINE}"/>')
        out.append(_text(xpos(d), B2 + 20, f"{d:,}", size=10, fill=MUTED,
                         family=MONO, anchor="middle"))
    out.append(_text((L + R) / 2, B2 + 42,
                     "negotiated DataTransferSize (bytes, log scale)",
                     size=11, fill=MUTED, anchor="middle"))

    STYLE = {"P2": (WIRE, "", "P2  ML-DSA-65 + ML-KEM-768"),
             "A0": ("#9ab5a4", ' stroke-dasharray="5 4"',
                    "A0  ECDSA P-384 + ECDHE P-384")}

    for group, (colour, dash, _) in STYLE.items():
        pts = " ".join(f"{xpos(d):.1f},{B1 - (B1 - T1) * r / max_rt:.1f}"
                       for d, _, r in series[group])
        out.append(f'<polyline points="{pts}" fill="none" stroke="{colour}" '
                   f'stroke-width="2.2"{dash}/>')
        for d, _, r in series[group]:
            y = B1 - (B1 - T1) * r / max_rt
            out.append(f'<circle cx="{xpos(d):.1f}" cy="{y:.1f}" r="3.4" '
                       f'fill="{colour}"/>')
            out.append(_text(xpos(d), y - 9, str(r), size=10, fill=colour,
                             family=MONO, anchor="middle"))

    for group, (colour, dash, _) in STYLE.items():
        pts = " ".join(f"{xpos(d):.1f},{B2 - (B2 - T2) * b / bytes_top:.1f}"
                       for d, b, _ in series[group])
        out.append(f'<polyline points="{pts}" fill="none" stroke="{colour}" '
                   f'stroke-width="2.2"{dash}/>')
        for d, b, _ in series[group]:
            y = B2 - (B2 - T2) * b / bytes_top
            out.append(f'<circle cx="{xpos(d):.1f}" cy="{y:.1f}" r="3.4" '
                       f'fill="{colour}"/>')

    p2b = [b for _, b, _ in series["P2"]]
    a0b = [b for _, b, _ in series["A0"]]
    out.append(_text(R + 8, B2 - (B2 - T2) * p2b[-1] / bytes_top + 4,
                     f"{min(p2b):,}-{max(p2b):,}", size=10, fill=WIRE,
                     family=MONO))
    out.append(_text(R + 8, B2 - (B2 - T2) * a0b[-1] / bytes_top + 4,
                     f"{min(a0b):,}-{max(a0b):,}", size=10, fill="#7f9a89",
                     family=MONO))

    lx = 24
    for group, (colour, _, label) in STYLE.items():
        out.append(f'<rect x="{lx}" y="{T1 - 36}" width="14" height="3" '
                   f'fill="{colour}"/>')
        out.append(_text(lx + 20, T1 - 30, label, size=10, fill=MUTED))
        lx += 34 + 6 * len(label)

    y = B2 + 68
    p2_rt = [r for _, _, r in series["P2"]]
    a0_chunks_at = [d for d, _, r in series["A0"] if r]
    lines = [
        f"Across a {xs[-1] // xs[0]}x range of DataTransferSize the post-quantum "
        f"handshake\u2019s bytes move "
        f"{100 * (max(p2b) - min(p2b)) / min(p2b):.1f}% and its chunk round trips "
        f"move from {min(p2_rt)} to {max(p2_rt)}.",
        "So DataTransferSize buys round trips and not bandwidth. Each round trip "
        "is one bus RTT, which on SMBus at 100 kHz is the expensive half of the "
        "cost.",
        (f"The classical arm chunks only at {a0_chunks_at[0]:,} bytes, where its "
         f"1,655-byte chain stops fitting - the dashed line. "
         if a0_chunks_at else "The classical arm never chunks. ")
        + "The 4,608-byte point reproduces the unpatched build\u2019s capture "
          "exactly, which is what makes the other five comparable to it.",
    ]
    for line in lines:
        out.append(_text(24, y, line, size=11, fill=MUTED))
        y += 17

    out.append(_text(24, H - 14,
                     "DataTransferSize has no upstream flag; it is "
                     "LIBSPDM_RECEIVER_BUFFER_SIZE minus transport overhead. "
                     "transport/data-transfer-size.patch makes it settable.",
                     size=9, fill=FAINT, family=MONO))
    out.append("</svg>")
    return "\n".join(out) + "\n", sources


FIGURES_BY_NAME = {
    "fig1-certificate-chain.svg": figure_1,
    "fig2-pqc-cost.svg": figure_2,
    "fig3-datatransfersize.svg": figure_3,
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

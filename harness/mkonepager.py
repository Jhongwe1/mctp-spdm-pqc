#!/usr/bin/env python3
"""The one-page summary, drawn from the evidence like the figures are.

    python3 harness/mkonepager.py            # write docs/one-pager.svg
    python3 harness/mkonepager.py --check    # regenerate and require no change

What it is for
--------------
A sheet of A4 that stays on an interviewer's desk after the interview: the
scope statement under the title, Table 1, Figure 2, what was and was not done,
and the two CI guarantees. It is in Chinese because the people it is handed to
read Chinese first; the figure embedded in it stays in English, like every
figure in this repository.

Why it is generated
-------------------
Every measured number on it is read from the same places the README's numbers
are read from — bench/claims.json, the tamper run's cases.tsv, the RATS
verdicts, the DataTransferSize sweep and the manifests of those runs — and
`--check` requires the committed file to be byte-identical to a fresh render,
so the page cannot drift from the evidence the way a document edited in a word
processor would. `harness/verify_repo.sh` runs the check.

What is typed by hand is the prose, and the few facts no data file holds (the
upstream line, the date). Where a sentence of prose is only true while the data
says something — "2a and 2b print the same status", "row 1 completes" — the
data is checked first, and the page refuses to render rather than print a
sentence its evidence no longer supports.

Fonts
-----
The text is text, not outlines, so it renders with the viewer's own CJK font:
Microsoft JhengHei on Windows, PingFang on macOS, Noto Sans CJK on Linux. This
repository's own host has none installed, which is why the byte check is on
the SVG source and the visual check is a render on a machine that has one.
Line breaks are computed here from a width estimate, conservatively, because an
SVG has no text flow of its own.

Exit codes: 0 ok · 1 --check found a difference · 2 an input is missing, or
the data no longer supports the page
"""

from __future__ import annotations

import argparse
import csv
import importlib.util
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
OUT = REPO / "docs" / "one-pager.svg"

# What the page says that no data file holds. Change these by hand, and the
# --check will then require the committed page to be regenerated.
AUTHOR = "Chung-Wei Lan"
REPO_URL = "github.com/Jhongwe1/mctp-spdm-pqc"
AS_OF = "2026-09-29"
UPSTREAM = (
    "DMTF/spdm-emu #524 已合併（2026-09-28，b015187，含於 4.0.0-rc2）：CoRimTool 的 verify "
    "連正確的簽章都拒絕，而它的驗證結果又被丟棄——兩個缺陷互相掩蓋，只修一個會變成全部接受。"
    "#526（同一工具的結束碼）與 #527（執行期設定 DataTransferSize）已送出、待審；"
    "openbmc/spdm 94773 審查中（patchset 3）。"
)

_spec = importlib.util.spec_from_file_location("mkfigures", REPO / "harness" / "mkfigures.py")
mkfigures = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(mkfigures)
Missing = mkfigures.Missing

# ── page geometry: A4 at 96 px per inch ──────────────────────────────────────
W, H = 794, 1123
X0, X1 = 40, 754
# The title's cap height starts about 38 px down; the last line may end no
# lower than the same distance from the bottom edge. Printers lose 4-5 mm at
# the edges, so a page that fits only with a 5 mm margin does not fit.
BOTTOM = H - 38
INK, MUTED, FAINT, LINE = "#1f2933", "#52606d", "#7b8794", "#cbd2d9"
ACCENT, WIRE, RED, PAPER = "#2b6cb0", "#276749", "#b42318", "#ffffff"
CJK = ("'Noto Sans TC','Microsoft JhengHei','PingFang TC','Noto Sans CJK TC',"
       "'Source Han Sans TC','Heiti TC',sans-serif")
MONO = "Consolas,Menlo,'DejaVu Sans Mono',monospace"


def esc(s: str) -> str:
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def text(x, y, s, *, size=12, fill=INK, weight="normal", family=CJK,
         anchor="start") -> str:
    return (f'<text x="{x}" y="{y}" font-family="{family}" font-size="{size}" '
            f'font-weight="{weight}" fill="{fill}" text-anchor="{anchor}">'
            f'{esc(s)}</text>')


def width(s: str, size: float, mono: bool = False) -> float:
    """A conservative width estimate: CJK a full em, Latin a bit over half,
    and a monospace face 0.6 em a character, a little over Consolas's 0.55."""
    if mono:
        return len(s) * 0.6 * size
    w = 0.0
    for ch in s:
        o = ord(ch)
        if o >= 0x2E80 or ch in "，。：；（）「」、":
            w += 1.0
        elif ch == " ":
            w += 0.32
        elif ch in "il.,:;'|!":
            w += 0.32
        elif ch.isupper() or ch in "mwMW@%":
            w += 0.72
        else:
            w += 0.58
    return w * size


# Chinese line-breaking rules (禁則): a closing mark never starts a line and an
# opening mark never ends one. The first render put a lone 。 on a line of its
# own and began two lines with ，and 、, none of which the width arithmetic
# could see.
CLOSING = set("，。、：；！？）」』》〉")
OPENING = set("（「『《〈")


def wrap(s: str, size: float, maxw: float, mono: bool = False) -> list[str]:
    """Break at any CJK character or at a space; never inside a Latin word.
    A closing mark hangs past maxw rather than start a line (by at most one
    em, inside the page margin); an opening mark moves to the next line."""
    tokens = re.findall(r"[A-Za-z0-9_.\-/#×%+<>=]+|\s|.", s)
    lines, cur = [], ""
    for t in tokens:
        if width(cur + t, size, mono) <= maxw or (t in CLOSING and cur.strip()):
            cur += t
            continue
        carry = ""
        while cur and cur[-1] in OPENING:
            carry, cur = cur[-1] + carry, cur[:-1]
        if cur.strip():
            lines.append(cur.rstrip())
        cur = carry + t.lstrip()
    if cur.strip():
        lines.append(cur.rstrip())
    return lines


def para(out, x, y, s, *, size=12, maxw=None, lh=None, **kw) -> tuple[float, float]:
    """Draw a wrapped paragraph from baseline y. Returns (next baseline, the
    last line's baseline), so a caller can know where the ink actually ends."""
    maxw = maxw or (X1 - x)
    lh = lh or round(size * 1.5)
    last = y
    for line in wrap(s, size, maxw):
        out.append(text(x, y, line, size=size, **kw))
        last = y
        y += lh
    return y, last


# ── the data ─────────────────────────────────────────────────────────────────


def claims() -> dict:
    d = json.loads((REPO / "bench" / "claims.json").read_text(encoding="utf-8"))
    return {k: v["value"] for k, v in d["claims"].items()}


def sweep_arms(sweep: Path, prefix: str) -> list[dict]:
    """Each arm of the DataTransferSize sweep, read from its capture: the size
    both sides advertised in CAPABILITIES — the independent variable read back
    off the wire, not taken from the flag that asked for it — the bytes, and
    the chunk round trips. Sorted by that size."""
    arms = []
    for cap in sorted(sweep.glob(f"{prefix}*.pcap")):
        s = mkfigures._tool("bench/pcapstat.py", str(cap), "--json")["summary"]
        caps = s.get("capabilities") or {}
        sizes = {(caps.get(side) or {}).get("data_transfer_size") for side in ("requester", "responder")}
        if len(sizes) != 1 or None in sizes:
            raise Missing(f"{cap.relative_to(REPO)}: the two sides did not advertise one "
                          f"DataTransferSize ({sorted(map(str, sizes))})")
        arms.append({"arm": cap.stem, "dts": sizes.pop(), "bytes": s["captured_bytes_total"],
                     "chunks": (s.get("chunking") or {}).get("messages", {}).get("SPDM_CHUNK_GET", 0)})
    return sorted(arms, key=lambda a: a["dts"])


def build_of(run: Path) -> dict:
    """What a run says it was built from — its manifest, not the pin as it is now."""
    m = json.loads((run / "manifest.json").read_text(encoding="utf-8"))
    up = m.get("upstream") or {}
    for key in ("flavor", "spdm_emu_short", "libspdm_short", "libspdm_ref"):
        if not up.get(key):
            raise Missing(f"{run.name}/manifest.json names no upstream {key}")
    return up


TAMPER_ROWS = [
    # case, row, what was changed, who notices
    ("t0_clean", "—", "沒改（對照組）", "—"),
    ("t1_meas", "1", "裝置上的量測值，在簽章之前", "只有 RATS 驗證者"),
    ("t2a_record", "2a", "量測紀錄，在傳輸中", "量測簽章"),
    ("t2b_sig", "2b", "簽章本身，在傳輸中", "量測簽章"),
    ("t3_cert", "3", "裝置送出的憑證", "裝置自己"),
    ("t3b_foreign", "3b", "換成別人的憑證鏈（位元組沒壞）", "requester 的權威檢查"),
]
SPDM_OUTCOME = {
    "completed": "握手完成",
    "MEASUREMENTS-rejected": "MEASUREMENTS 後拒絕",
    "no-CERTIFICATE-served": "從未送出 CERTIFICATE",
}


def tamper_table() -> tuple[Path, list[list[str]]]:
    runs = sorted((REPO / "bench" / "data").glob("*-tamper-*"))
    if not runs:
        raise Missing("no tamper run in bench/data")
    run = runs[-1]
    with open(run / "cases.tsv", encoding="utf-8") as fh:
        cases = {r["case"]: r for r in csv.DictReader(fh, delimiter="\t")}
    rows = []
    for case, row, what, who in TAMPER_ROWS:
        c = cases.get(case)
        if c is None:
            raise Missing(f"{run.name}/cases.tsv has no {case}")
        spdm = SPDM_OUTCOME.get(c["verdict"], c["verdict"])
        if c["anchor"] == "MISMATCH":
            spdm += "（只有警告）"
        status = c["status"] if c["status"] not in ("", "-") else "—"
        v = json.loads((REPO / "rats" / "out" / f"{case}.verdict.json").read_text(encoding="utf-8"))
        if v.get("outcome") == "no-evidence":
            rats = "沒有量測可比"
        else:
            checks = v["result"]["checks"]
            failed = [k.replace("SPDM_", "") for k, ok in checks.items() if not ok]
            rats = "PASS" if not failed else "FAIL（" + "、".join(failed) + "）"
        rows.append([row, what, who, spdm, status, rats])
    return run, rows


def require_the_prose(rows: list[list[str]]) -> None:
    """The paragraph under Table 1 states these; if one stops being true, stop."""
    by = {r[0]: r for r in rows}
    if by["1"][3] != "握手完成" or not by["1"][5].startswith("FAIL"):
        raise Missing("row 1 no longer completes in SPDM and fails in RATS; "
                      "the note under Table 1 says it does")
    if by["2a"][4] != by["2b"][4] or by["2a"][4] == "—":
        raise Missing("rows 2a and 2b no longer print the same status; the note says they do")
    if not by["2a"][5].startswith("FAIL") or by["2b"][5] != "PASS":
        raise Missing("RATS no longer fails 2a and passes 2b; the note says it does")


# ── the page ─────────────────────────────────────────────────────────────────


def render() -> str:
    cl = claims()
    tamper_run, rows = tamper_table()
    require_the_prose(rows)
    matrix = mkfigures._newest("w8-pqc-matrix-*")
    sweep = mkfigures._newest("w8-dts-sweep-*")
    a0 = mkfigures._arm_breakdown(matrix, "A0-all")
    fig2 = (REPO / "figures" / "fig2-pqc-cost.svg").read_text(encoding="utf-8")
    m = re.match(r"<svg[^>]*>", fig2)
    if not m or not fig2.rstrip().endswith("</svg>"):
        raise Missing("figures/fig2-pqc-cost.svg is not the SVG mkfigures.py writes")
    fig2_body = fig2[m.end():fig2.rstrip().rfind("</svg>")]
    expected = json.loads((REPO / "rats" / "out" / "expected.json").read_text(encoding="utf-8"))
    n_arms = len(expected["arms"])

    # The versions, from the runs the page draws on. Table 1 and Figure 2 are
    # said to share one build, so they must.
    bt, bm, bs = build_of(tamper_run), build_of(matrix), build_of(sweep)
    same = ("flavor", "spdm_emu_short", "libspdm_short")
    if any(bt[k] != bm[k] for k in same):
        raise Missing(f"{tamper_run.name} and {matrix.name} were built differently; "
                      "the footer says Table 1 and Figure 2 share a build")
    if any(bs[k] != bt[k] for k in ("spdm_emu_short", "libspdm_short")):
        raise Missing(f"{sweep.name} is on other upstream commits; the footer says it is not")
    pin = (REPO / "third_party" / f"spdm-emu-{bt['flavor']}.pin").read_text(encoding="utf-8")
    openssl = re.search(r"^crypto-openssl-version=(\S+)", pin, re.M)
    if not openssl:
        raise Missing(f"third_party/spdm-emu-{bt['flavor']}.pin names no OpenSSL version")

    # Sentences below state these as facts; if the data stops supporting one,
    # the page refuses to render rather than print it.
    if cl["cert_roundtrips_mldsa65"] != cl["cert_roundtrips_ecdsa384"]:
        raise Missing("GET_CERTIFICATE round trips differ between the arms now; "
                      "the cost paragraph says they are equal")
    p2 = sweep_arms(sweep, "P2-")
    if len(p2) < 2:
        raise Missing(f"{sweep.name} has no DataTransferSize range for P2")
    lo, hi = p2[0], p2[-1]
    if lo["chunks"] != cl["dts_sweep_chunk_roundtrips_at_the_smallest"]:
        raise Missing(f"{sweep.name}: the smallest P2 arm does not have the claimed chunk count")
    if lo["bytes"] / hi["bytes"] != cl["dts_sweep_byte_spread_fraction"]:
        raise Missing(f"{sweep.name}: the byte spread is no longer the claimed one")
    ctl = mkfigures._tool("bench/pcapstat.py", str(tamper_run / "t0_clean.pcap"),
                          "--json")["summary"]["algorithms"]
    if not ctl.get("spdm_version"):
        raise Missing(f"{tamper_run.name}/t0_clean.pcap: no negotiated SPDM version")
    neg = ctl["negotiated"]
    alg_line = (f"SPDM {ctl['spdm_version']}、{'/'.join(neg['Asym'])}、雜湊 "
                f"{'/'.join(neg['Hash'])}、量測雜湊 {'/'.join(neg['MeasHash'])}，"
                f"由 ALGORITHMS 讀回")

    out = [f'<svg xmlns="http://www.w3.org/2000/svg" width="210mm" height="297mm" '
           f'viewBox="0 0 {W} {H}" role="img" aria-label="SPDM 裝置證明實驗室 一頁摘要">',
           f'<rect width="{W}" height="{H}" fill="{PAPER}"/>']

    # ── header, and the scope statement directly under the title ───────────
    out.append(text(X0, 62, "SPDM 裝置證明實驗室", size=28, weight="700"))
    out.append(text(X1, 48, AUTHOR, size=13, weight="600", anchor="end"))
    out.append(text(X1, 66, REPO_URL, size=11, fill=MUTED, family=MONO, anchor="end"))
    out.append(f'<rect x="{X0}" y="80" width="{X1 - X0}" height="34" rx="4" '
               f'fill="#fff4f2" stroke="{RED}" stroke-width="1.2"/>')
    out.append(text(X0 + 14, 102, "範圍：我做的是協定流程層級的正確性驗證，不是安全性評估。",
                    size=14, weight="700", fill=RED))
    y, _ = para(out, X0, 136,
                "用 DMTF 的參考實作（libspdm / spdm-emu）跑完整的 SPDM 裝置證明握手，把三個問題變成"
                "可重算的數字：改一個位元組，誰會發現？拿到量測值之後要跟什麼比？後量子簽章在線上要付多少？",
                size=11.5, fill=MUTED, lh=17)

    # ── Table 1 ──────────────────────────────────────────────────────────────
    y += 9
    out.append(text(X0, y, "表 1　改一個位元組，誰會發現", size=15, weight="700"))
    y += 9
    ts = 10
    cols = [(X0, 26, "#"), (X0 + 26, 170, "改了什麼"), (X0 + 196, 118, "誰會發現"),
            (X0 + 314, 136, "SPDM 的結果"), (X0 + 450, 126, "狀態碼"), (X0 + 576, 138, "RATS 判定")]
    out.append(f'<rect x="{X0}" y="{y}" width="{X1 - X0}" height="22" fill="#eef2f6"/>')
    for x, _, h in cols:
        out.append(text(x + 6, y + 15, h, size=10.5, weight="700", fill=MUTED))
    y += 22
    for r in rows:
        monos = [bool(re.fullmatch(r"[0-9a-f]{8} [A-Z_]+|—", v)) for v in r]
        cells = [wrap(v, ts, w - 12, mono) for (x, w, _), v, mono in zip(cols, r, monos)]
        hgt = max(len(c) for c in cells) * 14 + 8
        emphasis = r[0] in ("1", "2a", "2b")
        if emphasis:
            out.append(f'<rect x="{X0}" y="{y}" width="{X1 - X0}" height="{hgt}" fill="#f6f8fa"/>')
        for (x, w, _), lines, v, mono in zip(cols, cells, r, monos):
            colour = RED if v.startswith("FAIL") else (WIRE if v == "PASS" else INK)
            for i, line in enumerate(lines):
                out.append(text(x + 6, y + 15 + 14 * i, line, size=ts,
                                family=MONO if mono else CJK, fill=colour,
                                weight="600" if emphasis and x == X0 else "normal"))
        y += hgt
        out.append(f'<line x1="{X0}" y1="{y}" x2="{X1}" y2="{y}" stroke="{LINE}"/>')
    y += 16
    y, _ = para(out, X0, y,
                "2a 與 2b 在 requester 印出同一個狀態碼，原因卻相反；RATS 的判定把兩者分開——2a 的紀錄"
                "被改了（FAIL），2b 的紀錄完好、壞的是線路（PASS）。第 1 列 SPDM 全數通過：SPDM 證明"
                "「是誰說的、途中沒被改」，不證明「說的對不對」，所以才需要驗證者。",
                size=11, fill=MUTED, lh=16)
    y, _ = para(out, X0, y + 1,
                f"來源：bench/data/{tamper_run.name}（cases.tsv、每個 arm 的 capture 與 manifest）"
                f"與 rats/out/*.verdict.json。{alg_line}。",
                size=9.5, fill=FAINT, lh=13)

    # ── Figure 2, embedded as committed, without its own caption lines ─────
    y += 11
    out.append(text(X0, y, "圖 2　後量子驗證的成本在哪裡", size=15, weight="700"))
    y += 8
    # The chart alone: the figure's own three lines of prose and its caption
    # are below y=358, and the paragraph after it on this page says the same
    # with the numbers read from the same captures.
    fw = X1 - X0
    fh = round(fw * 358 / 900)
    out.append(f'<svg x="{X0}" y="{y}" width="{fw}" height="{fh}" viewBox="0 0 900 358">'
               f'{fig2_body}</svg>')
    out.append(f'<rect x="{X0}" y="{y}" width="{fw}" height="{fh}" fill="none" '
               f'stroke="{LINE}"/>')
    y += fh + 18

    # ── what, and what not ──────────────────────────────────────────────────
    ratio3 = cl["pqc_handshake_ratio_level3_meas_op_all"]
    ratio5 = cl["pqc_handshake_ratio_level5_meas_op_all"]
    items = [
        ("做了什麼",
         "我做的：tamper harness 與在傳輸中改一個位元組的 proxy、pcap 分析器（pcapstat、fields、"
         "pcapcount）、RATS 流水線（COSE 簽署的 CoRIM 參考值 → OPA 政策 → 判定）、把三類 2026 "
         "advisory 寫成會失敗的負面測試、上游變更。不是我做的：SPDM 協定、chunking、後量子演算法"
         f"（libspdm {bt['libspdm_ref']} 與 OpenSSL {openssl.group(1)}）、DMTF 的一致性測試套件。"),
        ("最難的一題",
         "拿到量測值之後要跟什麼比？那不在 SPDM 的範圍，是 RATS（RFC 9334）。我把範例政策的 SVN "
         "檢查從「相等」改成「不低於參考值」：合法升級通過、降到參考值以下被拒。代價寫在旁邊：沒有"
         "降到參考值以下的降版（9 降回 7，參考值是 7）它看不見——無狀態的比對不知道裝置以前是幾版。"),
        ("後量子的真成本",
         f"位元組：NIST 第 3 級 ×{ratio3:.2f}、第 5 級 ×{ratio5:.2f}。但 GET_CERTIFICATE 的來回"
         f"兩邊都是 {cl['cert_roundtrips_mldsa65']} 次；多出來的是 chunk 層的 "
         f"{cl['pqc_chunk_roundtrips_mldsa65']} 次來回（古典 {a0['roundtrips_chunk']} 次）。"
         f"DataTransferSize 放大 {hi['dts'] // lo['dts']} 倍，位元組只動 "
         f"{100 * (cl['dts_sweep_byte_spread_fraction'] - 1):.1f}%，"
         f"chunk 來回卻從 {lo['chunks']} 降到 {hi['chunks']}。平台成本 ≈ 來回次數"
         f" × 匯流排 RTT × endpoint 數；RTT 與驗簽時間沒有量。"),
        ("第三方背書", UPSTREAM),
        ("沒做什麼",
         "沒有真裝置（emulator 與 QEMU）、沒有 HSM、沒有側通道或故障注入、沒有形式化分析、沒有量測"
         "任何 secure session、沒有公布任何延遲數字——兩個本機行程量到的是排程，不是密碼學。"),
    ]
    label_w = 100
    for label, body in items:
        out.append(text(X0, y, label, size=11.5, weight="700", fill=ACCENT))
        y, _ = para(out, X0 + label_w, y, body, size=11, maxw=X1 - X0 - label_w, lh=16)
        y += 5

    # ── the two guarantees, and where every number came from ───────────────
    y += 1
    out.append(f'<line x1="{X0}" y1="{y}" x2="{X1}" y2="{y}" stroke="{INK}" stroke-width="1.2"/>')
    y += 20
    guarantees = [
        "本頁的量測數字都由程式從 committed 的證據讀出；CI 從 pcap 重算每個公布的比值與計數"
        "（容差 0）、重跑每個 RATS 判定，並重新產生本頁、要求逐位元組相同。",
        f"CI 要求被篡改過的量測被判 FAIL：{n_arms} 個 arm 各有其必須得到的判定，任何一個變了，"
        f"build 就變紅。",
    ]
    for g in guarantees:
        out.append(text(X0, y, "▸", size=11.5, weight="600"))
        y, _ = para(out, X0 + 14, y, g, size=11.5, weight="600", lh=17)
        y += 2
    _, last = para(out, X0, y + 2,
                   f"版本：表 1 與圖 2 為 {bt['flavor']} flavor（spdm-emu {bt['spdm_emu_short']} / "
                   f"libspdm {bt['libspdm_short']}，{bt['libspdm_ref']}）；DataTransferSize 掃描為 "
                   f"{bs['flavor']} flavor（同兩個 commit，加一個 patch）。每個量測數字都對應一份 capture "
                   f"與其 manifest.json。本頁由 harness/mkonepager.py 產生，資料截至 {AS_OF}。",
                   size=9.5, fill=FAINT, lh=13)
    ink_ends = last + round(9.5 * 0.25)
    if ink_ends > BOTTOM:
        raise Missing(f"the page overflows A4: the last line ends at {ink_ends}, "
                      f"the margin allows {BOTTOM} ({ink_ends - BOTTOM} px to cut)")
    out.append(f"<!-- the last line ends at y={ink_ends} of {H}; the margin allows {BOTTOM} -->")
    out.append("</svg>")
    return "\n".join(out) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(description="render docs/one-pager.svg from the evidence")
    ap.add_argument("--check", action="store_true",
                    help="regenerate and require the committed file to match")
    args = ap.parse_args()
    try:
        svg = render()
    except Missing as why:
        print(f"  one-pager: {why}", file=sys.stderr)
        return 2
    if args.check:
        have = OUT.read_text(encoding="utf-8") if OUT.exists() else None
        if have == svg:
            print(f"  ok    docs/one-pager.svg still renders to what is committed ({len(svg)} bytes)")
            return 0
        print("  FAIL  docs/one-pager.svg " + ("is not committed" if have is None else
              f"no longer matches its data ({len(have)} bytes committed, {len(svg)} rendered)"))
        return 1
    OUT.write_text(svg, encoding="utf-8", newline="\n")
    print(f"  wrote docs/one-pager.svg ({len(svg)} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

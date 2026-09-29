#!/usr/bin/env bash
#
# harness/demo.sh — the four-minute demo, run for real, in the order it is told.
#
#     bash harness/demo.sh              # every segment, no pauses: the dry run
#     bash harness/demo.sh --pause      # wait for Enter between segments: recording
#     bash harness/demo.sh --only 3     # one segment
#
# What it is
# ----------
# plan/W13 §4 lays out a demo video: the scope in the first twenty seconds, then
# a tamper caught, a verifier naming the rule it applied, the post-quantum A/B,
# the DOE capability, and the limitations last. This script is that video's
# terminal, so that the recording is of commands that run rather than of a
# rehearsal of them.
#
#   1  scope                          0:00-0:20
#   2  one byte, in flight            0:20-1:30   live handshakes through the proxy
#   3  what SPDM cannot see           1:30-2:30   a device-side tamper, and RATS
#   4  what post-quantum costs        2:30-3:30   the committed A/B, re-run live
#   5  a real DOE mailbox             3:30-4:00   committed evidence, not re-run
#   6  where this stops               4:00-4:30
#
# Every handshake below is live, on the pinned pqc build, and every judgement is
# read from what it produced — the requester's own status line, the capture,
# the verdict — never from an exit code. And every segment states what it must
# show and checks it: if a live run stops agreeing with README.md's Table 1 or
# Table 2, the script says which and exits 1. So the dry run is not a rehearsal
# either; it is the last check before a camera is pointed at it. Its first run
# caught this script's own bug: the appraisal reads the record's bytes from
# spdm_dump's -x output beside the decode, and only the decode had been made.
#
# What it is not
# --------------
# Evidence. It writes to ${LAB_DIR}/scratch-demo, keeps no manifest, and writes
# nothing into this repository. The numbers it prints are the published ones
# re-derived live, and the published ones stay what they are.
#
# Exit codes: 0 every segment showed what it must · 1 one did not · 2 a
# prerequisite is missing

_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "${_HERE}/lib/common.sh"
# shellcheck source=lib/handshake.sh
. "${_HERE}/lib/handshake.sh"
# shellcheck source=lib/arms.sh
. "${_HERE}/lib/arms.sh"

PAUSE=0
ONLY=""
while [ $# -gt 0 ]; do
    case "$1" in
        --pause) PAUSE=1; shift ;;
        --only)  ONLY="${2:?--only needs a segment number}"; shift 2 ;;
        -h|--help) sed -n '3,9p' "$0"; exit 0 ;;
        *) printf 'unknown argument %s\n' "$1" >&2; exit 2 ;;
    esac
done

FLAVOR="pqc"
BIN="$(flavor_bin "$FLAVOR")"
S="${LAB_DIR}/scratch-demo"
MATRIX="${REPO_ROOT}/bench/data/w8-pqc-matrix-20260914T131557Z"
DOE="${REPO_ROOT}/bench/data/w9-doe-20260917T193247Z"
SPDM_DUMP="${WORK_DIR}/spdm-dump/build/bin/spdm_dump"
PROXY_PORT="${SPDM_PROXY_PORT:-2324}"
# The tamper cases' flags, which are tamper.sh's: the rows of Table 1 are only
# comparable with a demo taken on the same connection phase. The commas are the
# emulator's separator inside one value, not array syntax.
# shellcheck disable=SC2054
ARGS=(--exe_conn DIGEST,CERT,CHAL,MEAS --exe_session NO_END --meas_op ALL --slot_count 1)

missing=""
[ -x "${BIN}/spdm_responder_emu" ] || missing="${missing} the ${FLAVOR} build (bash harness/build_spdm_emu.sh ${FLAVOR});"
[ -f "$(flavor_dir "$FLAVOR")/DEVICE_PATCH.txt" ] || missing="${missing} the device patch (bash harness/apply_device_patch.sh ${FLAVOR} --build);"
[ -x "$SPDM_DUMP" ] || missing="${missing} spdm_dump (bash harness/build_spdm_dump.sh);"
command -v opa >/dev/null 2>&1 || missing="${missing} opa (third_party/opa.pin);"
if [ -n "$missing" ]; then
    printf 'demo: missing:%s\n' "$missing" >&2
    exit 2
fi

rm -rf "$S"
mkdir -p "$S"
FAILS=0
PROXY_PID=""

# ── presentation ──────────────────────────────────────────────────────────────

gap()  { printf '\n'; }
say()  { printf '  %s\n' "$*"; }
show() { printf '%s  $ %s%s\n' "$_C_DIM" "$*" "$_C_RESET"; }
good() { printf '%s  ✓ %s%s\n' "$_C_GRN" "$*" "$_C_RESET"; }
bad()  { printf '%s  ✗ %s%s\n' "$_C_RED" "$*" "$_C_RESET"; FAILS=$((FAILS + 1)); }

segment() {  # number title timecode
    if [ -n "$ONLY" ] && [ "$ONLY" != "$1" ]; then return 1; fi
    if [ "$PAUSE" -eq 1 ] && [ "$1" != "1" ] && [ -z "$ONLY" ]; then
        printf '\n%s  [Enter] %s%s' "$_C_DIM" "$2" "$_C_RESET"
        read -r _ </dev/tty || true
    fi
    hdr "$1/6  ·  $2    ($3)"
    return 0
}

# ── one handshake, and what it left behind ────────────────────────────────────

# shellcheck disable=SC2317  # reached through the EXIT trap
proxy_stop() {
    if [ -n "$PROXY_PID" ] && kill -0 "$PROXY_PID" 2>/dev/null; then
        kill "$PROXY_PID" 2>/dev/null || true
    fi
    PROXY_PID=""
}
trap proxy_stop EXIT

# handshake <name> <chain-dir> <fixture> [tamper_proxy args...] — sets RC.
# Leaves <name>.pcap, .decode.txt and .hex.txt: the appraisal reads the record's
# bytes from the -x dump beside the decode (harness/fields.py), so both are made.
handshake() {
    local name="$1" dir="$2" fixture="$3"; shift 3
    local waited=0
    # HS_* are read by lib/handshake.sh, not here.
    # shellcheck disable=SC2034
    HS_REQUESTER_EXTRA=()
    if [ "$#" -gt 0 ]; then
        python3 "${REPO_ROOT}/harness/tamper_proxy.py" --listen "$PROXY_PORT" \
            --forward "$HS_PORT" "$@" --report "${S}/${name}.proxy.json" --once \
            > "${S}/${name}.proxy.log" 2>&1 &
        PROXY_PID=$!
        until grep -qE "[:.]${PROXY_PORT}[[:space:]]" <<<"$(ss -ltn 2>/dev/null || true)"; do
            waited=$((waited + 1))
            if [ "$waited" -gt 100 ] || ! kill -0 "$PROXY_PID" 2>/dev/null; then
                bad "the proxy never listened — ${S}/${name}.proxy.log"
                RC=99; return
            fi
            sleep 0.1
        done
        # shellcheck disable=SC2034
        HS_REQUESTER_EXTRA=(--port "$PROXY_PORT")
    fi
    # shellcheck disable=SC2034
    HS_RESPONDER_ENV=("SPDM_MEASUREMENTS_FILE=${fixture}")
    RC=0
    hs_run "$dir" "${S}/${name}" "${ARGS[@]}" > /dev/null 2>&1 || RC=$?
    # shellcheck disable=SC2034
    HS_RESPONDER_ENV=()
    # shellcheck disable=SC2034
    HS_REQUESTER_EXTRA=()
    if [ -n "$PROXY_PID" ]; then
        wait "$PROXY_PID" 2>/dev/null || true
        PROXY_PID=""
    fi
    if [ -s "${S}/${name}.pcap" ]; then
        "$SPDM_DUMP" -r "${S}/${name}.pcap"    > "${S}/${name}.decode.txt" 2>&1 || true
        "$SPDM_DUMP" -r "${S}/${name}.pcap" -x > "${S}/${name}.hex.txt"    2>&1 || true
    fi
}

packets() { python3 "${REPO_ROOT}/harness/pcapcount.py" "$1" --json 2>/dev/null \
                | python3 -c 'import json,sys; print(json.load(sys.stdin)["summary"]["packets"])' \
                2>/dev/null || printf '0'; }

# The status the requester printed, named — or "-" when it printed none. Read
# the way tamper.sh reads it: the tool's output decides, not its exit status.
status() {
    local out
    out="$(python3 "${REPO_ROOT}/harness/spdm_status.py" "$1" 2>/dev/null)" || true
    case "$out" in ""|"-") printf -- '-' ;; *) printf '%s' "$out" ;; esac
}

# What the proxy changed, from its own report: which byte, from what to what,
# and whether the measurement record's digest moved.
tampered() {
    python3 - "$1" <<'PY' 2>/dev/null || printf '     (no proxy report)\n'
import json, sys
t = json.load(open(sys.argv[1]))["tamper"]
same = t["record_sha256_before"] == t["record_sha256_after"]
print(f"     proxy: {t['target']}: {t['byte_before']} -> {t['byte_after']}")
print(f"     record sha256 {t['record_sha256_before'][:12]}… -> {t['record_sha256_after'][:12]}…"
      f"  ({'unchanged' if same else 'CHANGED'})")
PY
}

verdict_of() { sed -n 's/^VERDICT *//p' "$1" 2>/dev/null; }

# ═════════════════════════════════════════════════════════════════════════════

if segment 1 "scope" "0:00-0:20"; then
    gap
    say "SPDM Device Attestation Lab — github.com/Jhongwe1/mctp-spdm-pqc"
    gap
    say "Scope. This project performs protocol-level correctness validation."
    say "       It is not a security assessment."
    gap
    say "DMTF's reference implementation — libspdm 4.0.0-rc, spdm-emu — run end to end."
    say "Everything below runs live on this machine. Nothing is written to the repository."
fi

# The chain and the clean fixture are needed by 2 and 3.
if [ -z "$ONLY" ] || [ "$ONLY" = 2 ] || [ "$ONLY" = 3 ]; then
    CLEAN_DIR="$(bash "${REPO_ROOT}/certs/stage_chain.sh" "$FLAVOR" 2>/dev/null)" \
        || { printf 'demo: could not stage certs/out (see certs/stage_chain.sh)\n' >&2; exit 2; }
    python3 "${REPO_ROOT}/device/gen_measurements.py" --out "${S}/clean.measurements.bin" \
        > "${S}/clean.fixture.txt" 2>&1 || { printf 'demo: could not write the fixture\n' >&2; exit 2; }
fi

if segment 2 "one byte, in flight" "0:20-1:30"; then
    gap
    say "The requester asks the device for its measurements; the device signs them."
    say "A proxy on the link can change one byte of the answer."
    gap
    show "requester → proxy → responder, nothing changed"
    handshake control "$CLEAN_DIR" "${S}/clean.measurements.bin" --passthrough
    st="$(status "${S}/control.req.log")"
    printf '     requester exit %s · %s packets · status %s\n' "$RC" "$(packets "${S}/control.pcap")" "$st"
    if [ "$RC" -eq 0 ] && [ "$st" = "-" ]; then good "the handshake completes"; else bad "the control did not complete"; fi

    gap
    show "again — the proxy changes one byte of measurement 1, after the device signed it"
    handshake row2a "$CLEAN_DIR" "${S}/clean.measurements.bin" --flip-record 1:36
    tampered "${S}/row2a.proxy.json"
    st2a="$(status "${S}/row2a.req.log")"
    printf '     requester: %s\n' "$st2a"

    gap
    show "again — the proxy changes one byte of the signature instead"
    handshake row2b "$CLEAN_DIR" "${S}/clean.measurements.bin" --flip-signature -1
    tampered "${S}/row2b.proxy.json"
    st2b="$(status "${S}/row2b.req.log")"
    printf '     requester: %s\n' "$st2b"

    gap
    if [ "${st2a%% *}" = "80020001" ] && [ "${st2b%% *}" = "80020001" ]; then
        good "two opposite tampers, one status: 80020001 VERIF_FAIL"
        say "SPDM reports THAT integrity failed — not which side of the signature the byte was on."
    else
        bad "Table 1 says both in-flight rows print 80020001; this run printed '${st2a}' and '${st2b}'"
    fi
fi

if segment 3 "what SPDM cannot see" "1:30-2:30"; then
    gap
    show "one byte of measurement 1 changed ON THE DEVICE, before it is hashed and signed"
    python3 "${REPO_ROOT}/device/gen_measurements.py" --out "${S}/row1.measurements.bin" \
        --flip-block 1 --flip-offset 36 > "${S}/row1.fixture.txt" 2>&1 || bad "the row 1 fixture"
    grep -A1 '^flipped' "${S}/row1.fixture.txt" | sed 's/^ */     /' || true
    handshake row1 "$CLEAN_DIR" "${S}/row1.measurements.bin"
    st1="$(status "${S}/row1.req.log")"
    printf '     requester exit %s · %s packets · status %s\n' "$RC" "$(packets "${S}/row1.pcap")" "$st1"
    if [ "$RC" -eq 0 ] && [ "$st1" = "-" ]; then
        good "SPDM completes with no error of any kind: the device signs what it measures"
    else
        bad "Table 1 row 1 completes in SPDM; this run did not"
    fi

    gap
    say "So compare what arrived with what it should be — RATS, RFC 9334:"
    say "a signed CoRIM reference value, and an OPA policy."
    show "python3 rats/appraise.py appraise row1.decode.txt"
    v1=0
    python3 "${REPO_ROOT}/rats/appraise.py" appraise "${S}/row1.decode.txt" \
        > "${S}/row1.verdict.txt" 2>&1 || v1=$?
    grep -E '^  (pass|FAIL)  |^        [a-z_]+: |^VERDICT|^ +blocked by|^cannot' "${S}/row1.verdict.txt" \
        | sed 's/^/   /' || true

    # 2a and 2b were captured in segment 2; run alone, this segment takes them.
    rows=""
    for c in control row2a row2b; do
        if [ ! -f "${S}/${c}.decode.txt" ]; then
            case "$c" in
                control) handshake control "$CLEAN_DIR" "${S}/clean.measurements.bin" --passthrough ;;
                row2a)   handshake row2a "$CLEAN_DIR" "${S}/clean.measurements.bin" --flip-record 1:36 ;;
                row2b)   handshake row2b "$CLEAN_DIR" "${S}/clean.measurements.bin" --flip-signature -1 ;;
            esac
        fi
        python3 "${REPO_ROOT}/rats/appraise.py" appraise "${S}/${c}.decode.txt" \
            > "${S}/${c}.verdict.txt" 2>&1 || true
        rows="${rows} ${c}=$(verdict_of "${S}/${c}.verdict.txt")"
    done
    gap
    printf '     the same verifier on segment 2:  control %s · row 2a %s · row 2b %s\n' \
        "$(verdict_of "${S}/control.verdict.txt")" "$(verdict_of "${S}/row2a.verdict.txt")" \
        "$(verdict_of "${S}/row2b.verdict.txt")"
    if [ "$v1" -eq 1 ] && grep -q 'blocked by SPDM_HASH_CHECK' "${S}/row1.verdict.txt" \
       && [ "$rows" = " control=PASS row2a=FAIL row2b=PASS" ]; then
        good "it catches row 1, and tells 2a (the record changed) from 2b (the link broke)"
    else
        bad "rats/out/expected.json says row 1 FAIL by SPDM_HASH_CHECK and PASS FAIL PASS; got row 1 exit ${v1},${rows}"
    fi
fi

if segment 4 "what post-quantum costs" "2:30-3:30"; then
    gap
    say "Two arms of the committed matrix. Their command lines differ in the algorithm only:"
    for arm in A0 P2; do
        grep '^requester:' "${MATRIX}/${arm}-all.cmdline.txt" \
            | awk '{for (i = 3; i <= NF; i++) { if ($i ~ /^--/) printf "%s%s", (i > 3 ? "\n" : ""), $i; else printf " %s", $i } print ""}' \
            > "${S}/${arm}.flags"
    done
    show "diff A0-all.cmdline.txt P2-all.cmdline.txt   (one flag per line)"
    # diff exits 1 because the files differ, which is the point; pipefail would
    # otherwise end the demo on its own best line.
    { diff "${S}/A0.flags" "${S}/P2.flags" || true; } | grep -E '^[<>]' | grep -v -- '--pcap' \
        | sed 's/^/     /' || true
    printf '     (the other %s flags are identical)\n' \
        "$(comm -12 <(sort "${S}/A0.flags") <(sort "${S}/P2.flags") | wc -l)"
    for arm in A0 P2; do
        flags=""
        for g in "${ALGO_GROUPS[@]}"; do
            if [ "${g%%|*}" = "$arm" ]; then flags="$(printf '%s' "$g" | cut -d'|' -f2)"; fi
        done
        show "run ${arm} live, on the pinned build"
        read -r -a armv <<<"$flags"
        rc=0
        hs_run "$BIN" "${S}/${arm}" "${COMMON[@]}" --meas_op ALL "${armv[@]}" > /dev/null 2>&1 || rc=$?
        [ "$rc" -eq 0 ] || bad "${arm} did not complete (exit ${rc})"
    done
    python3 - "${S}/A0.pcap" "${S}/P2.pcap" "${MATRIX}/A0-all.pcap" "${MATRIX}/P2-all.pcap" \
        "${REPO_ROOT}/bench/pcapstat.py" "$_C_GRN" "$_C_RED" "$_C_RESET" <<'PY' || FAILS=$((FAILS + 1))
import json, subprocess, sys
live_a0, live_p2, com_a0, com_p2, pcapstat, green, red, reset = sys.argv[1:9]
def row(p):
    out = subprocess.run([sys.executable, pcapstat, p, "--json"], capture_output=True, text=True)
    s = json.loads(out.stdout)["summary"]
    return {
        "captured bytes": s["captured_bytes_total"],
        "certificate chain bytes": s["certificates"]["slots"][0]["chain_bytes"],
        "GET_CERTIFICATE round trips": s["certificates"]["roundtrips"],
        "chunk round trips": (s.get("chunking") or {}).get("messages", {}).get("SPDM_CHUNK_GET", 0),
    }
a0, p2, ca0, cp2 = (row(p) for p in (live_a0, live_p2, com_a0, com_p2))
print(f"\n     {'':30}{'A0 ECDSA-P384':>15}{'P2 ML-DSA-65':>15}")
for k in a0:
    print(f"     {k:30}{a0[k]:>15,}{p2[k]:>15,}")
print(f"     {'bytes, P2 / A0':30}{'':>15}{p2['captured bytes'] / a0['captured bytes']:>14.2f}x")
same = a0 == ca0 and p2 == cp2
print(f"{green if same else red}  {'✓' if same else '✗'} "
      f"{'every count identical to the committed captures' if same else 'DIFFERENT from the committed captures'}{reset}")
print()
print("  Nine times the bytes — and GET_CERTIFICATE is 3 and 3. The chain no longer fits one")
print("  message, so it comes in chunks: 12 round trips against 0, each one a bus round trip.")
sys.exit(0 if same else 1)
PY
fi

if segment 5 "a real DOE mailbox" "3:30-4:00"; then
    gap
    say "From a QEMU guest on 2026-09-17 (${DOE#"${REPO_ROOT}"/}), not re-run here:"
    show "lspci -vvv   (in the guest)"
    grep -E 'Data Object Exchange|DOECap|Kernel driver' "${DOE}/lspci-vvv.txt" | sed 's/^[[:space:]]*/     /' || true
    show "transport/doe_probe — GET_VERSION through the mailbox"
    grep -E 'request payload|response payload|VERSION:|versions advertised|^ +0000' "${DOE}/doe-spdm.txt" \
        | sed 's/^/   /' || true
    if grep -q 'Data Object Exchange' "${DOE}/lspci-vvv.txt"; then
        good "one SPDM message pair through config space; the full handshake ran on the socket and AF_MCTP"
    else
        bad "the committed DOE capture no longer shows the capability"
    fi
fi

if segment 6 "where this stops" "4:00-4:30"; then
    gap
    say "1  No real hardware. Emulators and QEMU throughout; no board, no HSM."
    say "2  No latency numbers. Two processes on one host measure scheduling, not cryptography."
    say "3  Not a security assessment. No side channels, no fault injection, no formal"
    say "   analysis — and no secure session was measured."
fi

gap
if [ "$FAILS" -eq 0 ]; then
    ok "every segment showed what it must (outputs in ${S}, not evidence)"
    exit 0
fi
printf '%s FAIL %s %s segment check(s) did not hold — do not record until they do\n' \
    "$_C_RED" "$_C_RESET" "$FAILS" >&2
exit 1

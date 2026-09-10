#!/usr/bin/env bash
#
# harness/tamper.sh — change one byte, and record which layer noticed.
#
#     bash harness/tamper.sh                      # every case, ~1 minute
#     bash harness/tamper.sh --only t3_cert
#     bash harness/tamper.sh --name w5-tamper
#
# What this is
# ------------
# Ten handshakes that differ from each other in exactly one thing each, against
# one control. The control is not taken here: it is a capture this repository
# committed on 2026-08-31, before the code under test existed, and the reason
# is in "the control came first" below.
#
#   t0_none      no fixture at all — the patched binary on upstream's own path
#   t0_clean     a fixture whose contents equal what upstream synthesises
#   t0_proxy     the clean fixture, routed through the tamper proxy in
#                passthrough mode — the control for the proxy itself
#   t1_meas      the same fixture with ONE BYTE of measurement index 1 flipped
#                on the DEVICE, before the responder hashes and signs it
#   t2a_record   the clean fixture, and one byte of measurement index 1's value
#                flipped ON THE WIRE, after the responder signed it
#   t2b_sig      the clean fixture, and one byte of the SIGNATURE flipped on
#                the wire
#   t3_cert      the clean fixture, and one byte of the SUB CA certificate
#                inside the chain the responder serves
#   t3b_foreign  a well-formed chain from an authority the requester was never
#                given — the case t3_cert turned out to make necessary
#   svn5         the clean fixture with secure version number 5
#   svn9                                             ...and 9
#
# Every arm runs the same binary, the same flags, the same certificate chain
# and the same slot count. What differs is named in the case list and nothing
# else, which is what lets a difference in the result be attributed.
#
# Three tamper points, and why point 2 is two arms
# ------------------------------------------------
# SPDM protects three things by three independent mechanisms, and the point of
# the exercise is that they fail differently:
#
#   1  the measurement value at the device  — t1_meas
#   2  the bytes in flight                  — t2a_record and t2b_sig, through
#                                             harness/tamper_proxy.py
#   3  a certificate in the chain           — t3_cert
#
# Point 2 is split because the plan this project is executed against predicted
# that points 1 and 2 would produce the SAME error message from different root
# causes, and point 1 turned out to produce no error at all: a measurement
# changed at the device is signed by the device. So the pair that actually
# demonstrates "same message, different cause" is inside point 2 — the signed
# CONTENT changed (t2a_record) against the SIGNATURE changed (t2b_sig) — and
# it is a stronger pair than the planned one, because both halves reach a
# verifier and the difference between them is nothing but which side of the
# signature the byte was on.
#
# t0_proxy is the control for the proxy and is not a tamper point. Without it,
# "the handshake failed" in t2a and t2b could as easily mean "the proxy cannot
# forward 1.9 KB of certificate without corrupting it" as "the verifier
# rejected what it was sent", and nothing in an exit code tells the two apart.
#
# The control came first
# ----------------------
# "The fixture path changes nothing when it is not used" is the load-bearing
# claim of the whole change, and it cannot be checked against a capture taken
# afterwards by the same person who wanted it to be true.
#
# It does not have to be. The 528-byte measurement record is deterministic —
# it holds no nonce and no timestamp — and the same SHA-256 appears in six arms
# across three capture runs on 2026-08-16, 08-28 and 08-31. So the control is
# bench/data/w3-baseline-.../selfsigned.decode.txt: same flags, same chain,
# taken from a binary built before this patch was written, already committed
# with its own manifest. This script reads the digest out of it rather than
# holding a copy, so the comparison is between two captures and not between a
# capture and a constant somebody typed.
#
# What is asserted about the responder, and why it is read back
# -------------------------------------------------------------
# That a fixture was USED is read out of the responder's own stderr, which is
# committed as <case>.rsp.log, and not inferred from the fact that a variable
# was exported. A fixture that failed to load falls back to upstream's
# synthetic values silently as far as the wire is concerned: the handshake
# succeeds, the record is upstream's, and the run would report "the tamper had
# no effect" for a tamper that never happened. That is the same class of
# mistake as 2026-08-11's 5.94x, and the rule from it is standing rule 8 —
# confirm the independent variable from the far side.

set -uo pipefail
_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "${_HERE}/lib/common.sh"
# shellcheck source=lib/provenance.sh
. "${_HERE}/lib/provenance.sh"
# shellcheck source=lib/handshake.sh
. "${_HERE}/lib/handshake.sh"
set +e          # arms are expected to fail; each is judged on its evidence

RUN_NAME="w5-tamper"
ONLY=""
FLAVOR="pqc"
CONTROL="bench/data/w4-baseline-20260901T054208Z/selfsigned.decode.txt"

while [ $# -gt 0 ]; do
    case "$1" in
        --name)    RUN_NAME="${2:?--name needs a value}"; shift 2 ;;
        --only)    ONLY="${2:?--only needs a case name}"; shift 2 ;;
        --control) CONTROL="${2:?--control needs a decode file}"; shift 2 ;;
        -h|--help) sed -n '3,20p' "$0"; exit 0 ;;
        *)         die "unknown argument '$1'" ;;
    esac
done

# The connection phase these cases exercise, identical to the baseline arms so
# the control is comparable. See capture.sh for why --exe_session is pinned.
CONN="DIGEST,CERT,CHAL,MEAS"
SESSION="NO_END"
ARGS=(--exe_conn "$CONN" --exe_session "$SESSION" --meas_op ALL --slot_count 1)
TAB=$'\t'

# ------------------------------------------------------------- preflight ----

need python3
[ -d "$(flavor_bin "$FLAVOR")" ] || die "no build for '${FLAVOR}'
  bash harness/build_spdm_emu.sh ${FLAVOR}"

PATCH_STAMP="$(flavor_dir "$FLAVOR")/DEVICE_PATCH.txt"
[ -f "$PATCH_STAMP" ] || die "the device patch is not applied to the ${FLAVOR} tree.
  bash harness/apply_device_patch.sh ${FLAVOR} --build
  Without it the responder has no way to read a fixture and every case here
  would quietly measure upstream's synthetic values."

SPDM_DUMP=""
if command -v spdm_dump >/dev/null 2>&1; then
    SPDM_DUMP="$(command -v spdm_dump)"
elif [ -x "${WORK_DIR}/spdm-dump/build/bin/spdm_dump" ]; then
    SPDM_DUMP="${WORK_DIR}/spdm-dump/build/bin/spdm_dump"
fi
[ -n "$SPDM_DUMP" ] || die "spdm_dump not built — bash harness/build_spdm_dump.sh"

[ -f "${REPO_ROOT}/${CONTROL}" ] || die "no control capture at ${CONTROL}
  Pass --control <a decode file from an arm with the same flags and chain>."

# ------------------------------------------------------------- utilities ----

# jget <json-file> <dotted.path> — one field, or the empty string.
jget() {
    python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
for k in sys.argv[2].split("."):
    if isinstance(d,list):
        try: d=d[int(k)]
        except Exception: print(""); raise SystemExit
    elif isinstance(d,dict) and k in d: d=d[k]
    else: print(""); raise SystemExit
print("" if d is None else d)' "$1" "$2" 2>/dev/null
}

pcap_field() {
    python3 "${REPO_ROOT}/harness/pcapcount.py" "$1" --json 2>/dev/null \
        | python3 -c "import json,sys; print(json.load(sys.stdin)['summary']['$2'])" \
          2>/dev/null || printf '0'
}

hdr "tamper  ·  ${RUN_NAME}"

# ------------------------------------------- the control, read not assumed --

CONTROL_JSON="$(mktemp)"
if ! python3 "${REPO_ROOT}/harness/fields.py" "${REPO_ROOT}/${CONTROL}" --json \
        > "$CONTROL_JSON" 2>/dev/null; then
    rm -f "$CONTROL_JSON"
    die "could not read the control capture ${CONTROL}"
fi
CONTROL_RECORD="$(jget "$CONTROL_JSON" layout.measurement_record.sha256)"
CONTROL_SVN="$(jget "$CONTROL_JSON" layout.measurement_record.secure_version_number)"
CONTROL_BYTES="$(jget "$CONTROL_JSON" layout.measurement_record.record_bytes)"
rm -f "$CONTROL_JSON"
[ -n "$CONTROL_RECORD" ] || die "the control capture carries no measurement record"

log "control  ${CONTROL}"
dim "    record ${CONTROL_BYTES} bytes, svn ${CONTROL_SVN}"
dim "    sha256 ${CONTROL_RECORD}"

# ------------------------------------------------------------ provenance ----

prov_begin "$RUN_NAME" "$FLAVOR"
prov_pin_file "$PATCH_STAMP" DEVICE_PATCH.txt device_patch
prov_pin_file "${WORK_DIR}/spdm-dump/BUILD_PIN.txt" BUILD_PIN.spdm-dump.txt spdm_dump
prov_note control_capture "$CONTROL"
prov_note control_record_sha256 "$CONTROL_RECORD"

RESULTS="${PROV_RUN_DIR}/cases.tsv"
printf 'case\texit\tpackets\tslots\tcert\tchal\tmeas\tanchor\trecord_sha256\tsvn\tfixture\tproxy\tstatus\tverdict\n' \
    > "$RESULTS"

# req_status <req.log> — the libspdm status the requester last reported, named.
#
# The number is the finding: the two in-flight tamper arms print the same one,
# from the same layer, for causes that are opposites. harness/spdm_status.py
# owns emulator logs and holds the only copy of the name table.
req_status() {
    local out
    out="$(python3 "${REPO_ROOT}/harness/spdm_status.py" "$1" 2>/dev/null)" || out=""
    case "$out" in
        ""|"-") printf '-' ;;
        *)      printf '%s %s' "${out%% *}" "$(printf '%s' "$out" | awk '{print $2}')" ;;
    esac
}

# ------------------------------------------------------------- the proxy ----
#
# Set PROXY_ARGS immediately before a run_case that should go through it, and
# run_case clears it — the same discipline as HS_RESPONDER_ENV, and for the
# same reason: an arm that silently inherited the previous arm's tamper would
# be a two-variable experiment reported as a one-variable one.
#
# The proxy listens before the responder exists and connects upstream only when
# a client arrives, so the start order does not matter and there is no race to
# lose. It is given --once, so it exits when the connection closes and its exit
# status is available to be read: 0 means it did what it was asked, 1 means it
# was asked to change a byte and refused or never saw a MEASUREMENTS. That
# status is evidence, and a case is not judged without it.

PROXY="${REPO_ROOT}/harness/tamper_proxy.py"
PROXY_PORT="${SPDM_PROXY_PORT:-2324}"
PROXY_ARGS=()
PROXY_PID=""

proxy_wait_listening() {
    local waited=0
    while [ "$waited" -lt 100 ]; do
        kill -0 "$PROXY_PID" 2>/dev/null || return 1
        if command -v ss >/dev/null 2>&1; then
            # Captured, not piped: lib/handshake.sh's hs_port_is_listening says
            # what the pipeline form costs, and this was written in it.
            grep -qE "[:.]${PROXY_PORT}[[:space:]]" \
                <<<"$(ss -ltn 2>/dev/null || true)" && return 0
        else
            sleep 1; return 0
        fi
        sleep 0.1
        waited=$((waited + 1))
    done
    return 1
}

proxy_cleanup() {
    if [ -n "$PROXY_PID" ] && kill -0 "$PROXY_PID" 2>/dev/null; then
        kill "$PROXY_PID" 2>/dev/null || true
        sleep 0.2
        kill -9 "$PROXY_PID" 2>/dev/null || true
    fi
    PROXY_PID=""
}
trap 'proxy_cleanup' EXIT

# anchor_state <fields.json> <sandbox-dir> — does the chain the responder served
# on slot 0 root in the certificate the requester was configured to trust?
#
# Both halves are knowable here and neither is a guess: the requester's anchor
# is <sandbox>/ecp384/ca.cert.der, which is the file
# libspdm_read_responder_root_public_certificate opens (read_pub_cert.c), and
# the chain's root hash is reconstructed from the capture by fields.py. They
# are hashed with the algorithm the connection negotiated, read out of the same
# capture rather than assumed to be SHA-384.
#
# This column exists because libspdm reports the mismatch as a WARNING —
# LIBSPDM_STATUS_VERIF_NO_AUTHORITY, severity 0x4, "provided cert is valid but
# is not authoritative" — and spdm_requester_emu tests only
# LIBSPDM_STATUS_IS_ERROR. A handshake can therefore complete against a chain
# whose root the requester was never given, and nothing in an exit code, a log
# line or a packet count says so. This makes it a fact the table carries.
anchor_state() {
    local json="$1" dir="$2"
    local anchor="${dir}/ecp384/ca.cert.der"
    [ -f "$json" ] || { printf '-'; return; }
    [ -f "$anchor" ] || { printf '-'; return; }
    python3 -c '
import hashlib, json, sys
d = json.load(open(sys.argv[1]))
L = d.get("layout") or {}
name = (L.get("hash_name") or "").lower().replace("_", "")
fn = {"sha256": hashlib.sha256, "sha384": hashlib.sha384,
      "sha512": hashlib.sha512}.get(name)
chains = [c for c in L.get("chains", [])
          if c.get("direction") == "RSP->REQ" and c.get("slot") == 0]
if fn is None or not chains:
    print("-"); raise SystemExit
want = fn(open(sys.argv[2], "rb").read()).hexdigest()
print("match" if chains[0]["root_hash"] == want else "MISMATCH")' \
        "$json" "$anchor" 2>/dev/null || printf '?'
}

# --------------------------------------------------------------- fixtures ---
#
# Written into the run directory rather than into device/, so prov_finish
# hashes each one and the manifest records the exact bytes each responder read.
# ADR 0005: a generated input is evidence, and the fixture is the input the
# whole experiment varies.

GEN="${REPO_ROOT}/device/gen_measurements.py"
FIXTURE=""

# make_fixture <name> [extra args...] — sets $FIXTURE.
#
# Sets a variable rather than echoing one, so that a refusal from the generator
# stops the whole run. In a command substitution `die` exits the subshell and
# the caller carries on with an empty path, which is exactly the silent
# fallback this script exists to make impossible.
make_fixture() {
    local name="$1"; shift
    local out="${PROV_RUN_DIR}/${name}.measurements.bin"
    FIXTURE=""
    if ! prov_run python3 "$GEN" --out "$out" "$@" \
            > "${PROV_RUN_DIR}/${name}.fixture.txt" 2>&1; then
        sed 's/^/    /' "${PROV_RUN_DIR}/${name}.fixture.txt" >&2
        die "could not build the ${name} fixture"
    fi
    FIXTURE="$out"
}

# ------------------------------------------------------------ the chains ----

log "staging this project's chain"
CLEAN_DIR="$(bash "${REPO_ROOT}/certs/stage_chain.sh" "$FLAVOR" 2>/dev/null)" \
    || die "could not stage certs/out — see certs/stage_chain.sh for why
  (a fresh clone has certificates but no private keys)"
prov_note chain_sandbox "$CLEAN_DIR"
prov_note chain_sha256 \
    "$(sha256sum "${REPO_ROOT}/certs/out/bundle_responder.certchain.der" | cut -d' ' -f1)"

# Which byte, and why that byte, is certs/check_chain.py's answer: it owns
# certificate bytes. It returns the middle of the intermediate's own ECDSA s
# value, so the certificate still parses and every field still says what it
# said — only the root's signature over it stops verifying.
LOCATE_JSON="${PROV_RUN_DIR}/chain-locate.json"
if ! prov_run python3 "${REPO_ROOT}/certs/check_chain.py" "${REPO_ROOT}/certs/out" \
        --locate --json > "$LOCATE_JSON" 2>/dev/null; then
    die "could not locate the intermediate certificate inside the bundle"
fi

CERT_FLIP=""
CERT_MEANING=""
for i in 0 1 2; do
    if [ "$(jget "$LOCATE_JSON" "certificates.${i}.name")" = "inter" ]; then
        CERT_FLIP="$(jget "$LOCATE_JSON" "certificates.${i}.flip_offset_in_bundle")"
        CERT_MEANING="$(jget "$LOCATE_JSON" "certificates.${i}.flip_meaning")"
        break
    fi
done
[ -n "$CERT_FLIP" ] || die "no certificate named 'inter' in the bundle"

TAMPERED_DIR="${WORK_DIR}/selfsigned-${FLAVOR}-tampered"
rm -rf "$TAMPERED_DIR"
cp -a "$CLEAN_DIR" "$TAMPERED_DIR"
python3 - "$TAMPERED_DIR/ecp384/bundle_responder.certchain.der" "$CERT_FLIP" <<'PY'
import sys, hashlib, pathlib
p = pathlib.Path(sys.argv[1]); off = int(sys.argv[2])
b = bytearray(p.read_bytes())
b[off] ^= 0x01
p.write_bytes(bytes(b))
print(f"flipped byte {off} -> sha256 {hashlib.sha256(bytes(b)).hexdigest()}")
PY
cp -f "$TAMPERED_DIR/ecp384/bundle_responder.certchain.der" \
      "${PROV_RUN_DIR}/t3_cert.bundle_responder.certchain.der"
prov_note cert_flip_offset "$CERT_FLIP"
prov_note cert_flip_meaning "$CERT_MEANING"
prov_note cert_flip_sha256 \
    "$(sha256sum "$TAMPERED_DIR/ecp384/bundle_responder.certchain.der" | cut -d' ' -f1)"
ok "sub CA byte ${CERT_FLIP}: ${CERT_MEANING}"

# ── a chain the device can validate and the verifier does not trust ─────────
#
# This case was not planned. It exists because t3_cert measured something
# other than what it was built to measure: a flipped byte never reaches the
# wire, because the reference responder validates its own chain when it loads
# it and simply stops offering the slot. Nothing wrong is ever SENT, so the
# requester's chain verification is not exercised at all — and "the certificate
# layer rejected it" would have been the wrong sentence to write about it.
#
# So: leave the chain internally perfect and change WHOSE it is. The responder
# serves DMTF's own ecp384 chain, signing with DMTF's leaf key, while the
# requester keeps this project's root as its trust anchor — the anchor comes
# from ecp384/ca.cert.der, which is a different file and is left alone
# (libspdm_read_responder_root_public_certificate, read_pub_cert.c).
#
# That is the counterfeit-part shape rather than the corrupted-file shape: a
# well-formed chain from an authority nobody told the verifier to trust. It is
# not a fourth tamper point and it is not in Table 1's three; it is the case
# that had to exist for the certificate layer's rejection to be observed at
# all, and the pcap tells the two apart by one message type.

FOREIGN_DIR="${WORK_DIR}/selfsigned-${FLAVOR}-foreign"
UPSTREAM_ECP384="$(flavor_bin "$FLAVOR")/ecp384"
rm -rf "$FOREIGN_DIR"
cp -a "$CLEAN_DIR" "$FOREIGN_DIR"
for f in bundle_responder.certchain.der end_responder.cert.der end_responder.key; do
    [ -f "${UPSTREAM_ECP384}/${f}" ] || die "upstream ${f} is missing from ${UPSTREAM_ECP384}"
    cp -f "${UPSTREAM_ECP384}/${f}" "${FOREIGN_DIR}/ecp384/${f}"
done
chmod 0600 "${FOREIGN_DIR}/ecp384/end_responder.key"
prov_note foreign_chain_sha256 \
    "$(sha256sum "${FOREIGN_DIR}/ecp384/bundle_responder.certchain.der" | cut -d' ' -f1)"
prov_note foreign_anchor_sha256 \
    "$(sha256sum "${FOREIGN_DIR}/ecp384/ca.cert.der" | cut -d' ' -f1)"
ok "foreign chain staged — responder serves DMTF's, requester anchors on ours"

# ---------------------------------------------------------------- an arm ----

# run_case <name> <chain-dir> <fixture-path-or-empty> <expected-svn-or-empty> <note>
run_case() {
    local name="$1" dir="$2" fixture="$3" want_svn="$4" note="$5"
    local prefix="${PROV_RUN_DIR}/${name}"
    local rc=0 pkts json chal meas cert slots anchor record svn loaded errored verdict fixnote
    local proxy_rc=0 proxy_note="-" proxy_report="" status="-"

    if [ -n "$ONLY" ] && [ "$ONLY" != "$name" ]; then
        PROXY_ARGS=()
        return 0
    fi

    log "case '${name}' — ${note}"

    if [ "${#PROXY_ARGS[@]}" -gt 0 ]; then
        proxy_report="${prefix}.proxy.json"
        prov_cmd python3 "$PROXY" --listen "$PROXY_PORT" --forward "$HS_PORT" \
            "${PROXY_ARGS[@]}" --report "$proxy_report" --once
        python3 "$PROXY" --listen "$PROXY_PORT" --forward "$HS_PORT" \
            "${PROXY_ARGS[@]}" --report "$proxy_report" --once \
            > "${prefix}.proxy.log" 2>&1 &
        PROXY_PID=$!
        dim "    proxy ${PROXY_PORT} -> ${HS_PORT}  ${PROXY_ARGS[*]}"
        if ! proxy_wait_listening; then
            proxy_cleanup
            die "the proxy never listened on ${PROXY_PORT} — see ${prefix}.proxy.log"
        fi
        HS_REQUESTER_EXTRA=(--port "$PROXY_PORT")
    fi
    PROXY_ARGS=()

    HS_RESPONDER_ENV=()
    if [ -n "$fixture" ]; then
        HS_RESPONDER_ENV=("SPDM_MEASUREMENTS_FILE=${fixture}")
        dim "    responder env SPDM_MEASUREMENTS_FILE=$(basename "$fixture")"
    else
        dim "    no fixture — the responder never opens a file"
    fi
    dim "    cwd ${dir}"

    hs_run "$dir" "$prefix" "${ARGS[@]}"
    rc=$?
    # Cleared immediately, so a case that forgets to set it cannot inherit the
    # previous case's fixture — which would be a two-variable arm reported as a
    # one-variable one. Read by lib/handshake.sh, not by anything here.
    # shellcheck disable=SC2034
    HS_RESPONDER_ENV=()
    # shellcheck disable=SC2034
    HS_REQUESTER_EXTRA=()

    # The proxy's own exit status, read before anything else is judged. It is
    # the only thing that can say "the byte this case is named after was never
    # changed", and a tamper case that silently did not tamper looks exactly
    # like a tamper that was not detected.
    if [ -n "$PROXY_PID" ]; then
        wait "$PROXY_PID"
        proxy_rc=$?
        PROXY_PID=""
        if [ -f "$proxy_report" ]; then
            if [ "$(jget "$proxy_report" mode)" = "passthrough" ]; then
                proxy_note="passthrough"
            elif [ "$(jget "$proxy_report" tamper.applied)" = "True" ]; then
                proxy_note="flip@$(jget "$proxy_report" tamper.offset_in_spdm_message)"
            else
                proxy_note="REFUSED"
            fi
        else
            proxy_note="NO-REPORT"
        fi
        [ "$proxy_rc" -eq 0 ] || proxy_note="${proxy_note}/rc${proxy_rc}"
    fi

    pkts="$(pcap_field "${prefix}.pcap" packets)"

    if [ -s "${prefix}.pcap" ]; then
        prov_cmd "$SPDM_DUMP" -r "${prefix}.pcap"
        "$SPDM_DUMP" -r "${prefix}.pcap" > "${prefix}.decode.txt" 2>&1
        prov_cmd "$SPDM_DUMP" -r "${prefix}.pcap" -x
        "$SPDM_DUMP" -r "${prefix}.pcap" -x > "${prefix}.hex.txt" 2>&1
        python3 "${REPO_ROOT}/harness/fields.py" "${prefix}.decode.txt" --json \
            > "${prefix}.fields.json" 2>/dev/null || rm -f "${prefix}.fields.json"
    fi

    json="${prefix}.fields.json"
    chal="0"; meas="0"; cert="0"; slots="-"; record=""; svn=""
    if [ -f "$json" ]; then
        chal="$(jget "$json" messages.by_type.SPDM_CHALLENGE_AUTH)"; chal="${chal:-0}"
        meas="$(jget "$json" messages.by_type.SPDM_MEASUREMENTS)";  meas="${meas:-0}"
        cert="$(jget "$json" messages.by_type.SPDM_CERTIFICATE)";   cert="${cert:-0}"
        # The slot mask is what says whether the DEVICE would serve the chain
        # at all. It is the difference between "the requester refused what it
        # was sent" and "nothing was ever sent", and the two look identical in
        # an exit code.
        slots="$(jget "$json" layout.digests.provisioned_slot_mask)"; slots="${slots:--}"
        record="$(jget "$json" layout.measurement_record.sha256)"
        svn="$(jget "$json" layout.measurement_record.secure_version_number)"
    fi
    anchor="$(anchor_state "$json" "$dir")"
    status="$(req_status "${prefix}.req.log")"

    # Did the responder read the fixture? Its own stderr says so.
    #
    # The loader is lazy: it opens the file the first time a measurement is
    # asked for, which is exactly what a device does when it reads its own
    # flash on demand. So a case that never reaches GET_MEASUREMENTS has not
    # loaded a fixture and MUST NOT be marked as having failed to. Reporting
    # "NOT-LOADED" there would be a red flag for the wrong reason, and a red
    # flag that fires when nothing is wrong is how real ones stop being read.
    loaded="$(grep -c 'measurement_source: loaded' "${prefix}.rsp.log" 2>/dev/null)"
    loaded="${loaded:-0}"
    errored=0
    if grep 'measurement_source:' "${prefix}.rsp.log" 2>/dev/null \
            | grep -qv 'measurement_source: loaded'; then
        errored=1
    fi

    fixnote="-"
    if [ -n "$fixture" ]; then
        if [ "$errored" -eq 1 ]; then
            fixnote="LOAD-ERROR"
        elif [ "$loaded" -gt 0 ]; then
            fixnote="loaded"
        elif [ "$meas" = "0" ]; then
            fixnote="unreached"
        else
            fixnote="NOT-LOADED"
        fi
    elif [ "$loaded" -gt 0 ] || [ "$errored" -eq 1 ]; then
        fixnote="UNEXPECTED"
    else
        fixnote="none"
    fi

    # The verdict is about evidence, never about $?. Standing rule: an exit
    # code answers a broader question than the one being asked, and on
    # 2026-08-11 three tools in one day answered slightly different questions
    # with one.
    #
    # The MEASUREMENTS-rejected branch was added on 2026-09-10 because the
    # first run of the two proxy arms reported "stopped-after-CHALLENGE" for
    # them — and the meas column beside it said 1. The message had arrived and
    # its signature had not verified, which is a different sentence about a
    # different layer, and the vocabulary had no word for it. A verdict that
    # names the wrong stage is worse than no verdict, because it reads like an
    # observation.
    verdict="?"
    if [ "$chal" != "0" ] && [ "$meas" != "0" ] && [ "$rc" -eq 0 ]; then
        verdict="completed"
    elif [ "$cert" = "0" ]; then
        verdict="no-CERTIFICATE-served"
    elif [ "$chal" = "0" ]; then
        verdict="stopped-after-CERTIFICATE"
    elif [ "$meas" != "0" ]; then
        verdict="MEASUREMENTS-rejected"
    else
        verdict="stopped-after-CHALLENGE"
    fi
    # An svn assertion only means something where a record reached the wire.
    if [ -n "$want_svn" ] && [ "$meas" != "0" ] && [ "$svn" != "$want_svn" ]; then
        verdict="${verdict}/svn-mismatch"
    fi
    if [ "$fixnote" = "LOAD-ERROR" ] || [ "$fixnote" = "NOT-LOADED" ] \
       || [ "$fixnote" = "UNEXPECTED" ]; then
        verdict="${verdict}/FIXTURE-${fixnote}"
    fi
    # A proxy that refused, crashed or never saw the message it was aimed at
    # invalidates the arm outright, however the handshake turned out.
    case "$proxy_note" in
        -|passthrough|flip@*) : ;;
        *) verdict="${verdict}/PROXY-${proxy_note}" ;;
    esac

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$name" "$rc" "$pkts" "$slots" "$cert" "$chal" "$meas" "$anchor" \
        "${record:0:16}" "${svn:--}" "$fixnote" "$proxy_note" "$status" \
        "$verdict" >> "$RESULTS"

    if [ "$verdict" = "completed" ]; then
        ok "${name}: ${verdict}, ${pkts} packets, record ${record:0:16}…, svn ${svn:--}"
    else
        warn "${name}: ${verdict}, ${pkts} packets, status ${status}"
    fi
}

# ----------------------------------------------------------- the cases ------

run_case t0_none "$CLEAN_DIR" "" "" \
    "no fixture: the patched binary on upstream's own path"

make_fixture t0_clean
F_CLEAN="$FIXTURE"
run_case t0_clean "$CLEAN_DIR" "$F_CLEAN" "7" \
    "a fixture holding exactly what upstream synthesises"

# One byte, in the middle of measurement index 1's 72-byte pre-image. Not the
# hash on the wire: the value the responder hashes. The 64-byte SHA-512 in the
# record is recomputed by upstream from the changed input, and everything
# downstream of it — record length, block sizes, signature — is upstream's.
make_fixture t1_meas --flip-block 1 --flip-offset 36
run_case t1_meas "$CLEAN_DIR" "$FIXTURE" "7" \
    "one byte of measurement index 1 flipped"

# ── point 2: the same measurement, changed on the other side of the signature ─
#
# t0_proxy first, and its job is to be boring. It runs the clean fixture through
# the proxy with nothing changed, and its measurement record digest has to equal
# the control's. Only then does a failure in the two arms below mean what their
# names say. A proxy that mangled a 1.9 KB CERTIFICATE would break every arm it
# touched, and "the tamper was detected" is exactly what that looks like from
# an exit code.
PROXY_ARGS=(--passthrough)
run_case t0_proxy "$CLEAN_DIR" "$F_CLEAN" "7" \
    "clean measurements, forwarded through the proxy unchanged"

# t2a: measurement index 1 again, offset 36 again — but this is byte 36 of the
# VALUE ON THE WIRE, which is the hash, where t1_meas changed byte 36 of the
# 72-byte PRE-IMAGE the responder hashes. Same index, same offset, two
# different objects on two different sides of the signature, and that is the
# whole experiment: the difference in outcome cannot be attributed to what was
# changed, only to when.
PROXY_ARGS=(--flip-record 1:36)
run_case t2a_record "$CLEAN_DIR" "$F_CLEAN" "7" \
    "one byte of measurement index 1's value flipped in flight"

# t2b: the last byte of the signature itself. The signed content is untouched
# and the signature is not, which is the mirror image of t2a. If libspdm
# reports these two differently that is a finding; if it reports them
# identically that is the finding the plan predicted, arriving one row later
# than it expected.
PROXY_ARGS=(--flip-signature -1)
run_case t2b_sig "$CLEAN_DIR" "$F_CLEAN" "7" \
    "the last byte of the measurement signature flipped in flight"

run_case t3_cert "$TAMPERED_DIR" "$F_CLEAN" "7" \
    "clean measurements, one byte of the sub CA certificate flipped"

run_case t3b_foreign "$FOREIGN_DIR" "$F_CLEAN" "7" \
    "a well-formed chain from an authority the requester does not trust"

make_fixture svn5 --svn 5
run_case svn5 "$CLEAN_DIR" "$FIXTURE" "5" "secure version number 5"

make_fixture svn9 --svn 9
run_case svn9 "$CLEAN_DIR" "$FIXTURE" "9" "secure version number 9"

# ------------------------------------------------------------- the table ----

hdr "cases"
if command -v column >/dev/null 2>&1; then
    column -t -s "$TAB" "$RESULTS" | sed 's/^/  /'
else
    awk -F'\t' '{printf "  %-12s %-5s %-8s %-6s %-5s %-5s %-5s %-9s %-18s %-4s %-10s %-12s %-22s %s\n", \
                 $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14}' "$RESULTS"
fi

printf '\n'
hdr "what the control says"
printf '  control record sha256 : %s\n' "$CONTROL_RECORD"
printf '  from                  : %s\n' "$CONTROL"
printf '\n'
awk -F'\t' -v ctl="${CONTROL_RECORD:0:16}" 'NR>1 {
    same = ($9 == ctl) ? "SAME as control" : ($9 == "" ? "no record on the wire" : "DIFFERENT");
    printf "  %-12s %s\n", $1, same
}' "$RESULTS"

printf '\n'
hdr "whose certificate the requester accepted"
printf '  The anchor column compares the root of the chain served on slot 0 with\n'
printf '  the certificate the requester was configured to trust. MISMATCH beside a\n'
printf '  completed handshake is not a harness bug: libspdm reports it as a\n'
printf '  WARNING (LIBSPDM_STATUS_VERIF_NO_AUTHORITY) and spdm_requester_emu tests\n'
printf '  only LIBSPDM_STATUS_IS_ERROR. See docs/tamper.md.\n'
printf '\n'
awk -F'\t' 'NR>1 && $8 == "MISMATCH" {
    printf "  %-12s completed against a chain rooted in an unprovisioned CA\n", $1
}' "$RESULTS"

printf '\n'
hdr "what the proxy changed, and where it says it changed it"
printf '  Offsets are given three ways because a reader meets them three ways:\n'
printf '  inside the SPDM message, inside the socket payload (one byte later,\n'
printf '  the MCTP message type), and inside a pcap record (four more, the\n'
printf '  header spdm_emu synthesises). See harness/tamper_proxy.py.\n'
printf '\n'
for _r in "${PROV_RUN_DIR}"/*.proxy.json; do
    [ -f "$_r" ] || continue
    _n="$(basename "$_r" .proxy.json)"
    if [ "$(jget "$_r" mode)" = "passthrough" ]; then
        printf '  %-12s forwarded %s frames unchanged\n' "$_n" \
            "$(( $(jget "$_r" frames.requester_to_responder) + \
                 $(jget "$_r" frames.responder_to_requester) ))"
        continue
    fi
    printf '  %-12s %s\n' "$_n" "$(jget "$_r" tamper.target)"
    printf '  %-12s   %s -> %s at SPDM %s / payload %s / pcap %s\n' "" \
        "$(jget "$_r" tamper.byte_before)" "$(jget "$_r" tamper.byte_after)" \
        "$(jget "$_r" tamper.offset_in_spdm_message)" \
        "$(jget "$_r" tamper.offset_in_socket_payload)" \
        "$(jget "$_r" tamper.offset_in_pcap_record)"
    printf '  %-12s   signature %s B at %s, sized by %s read off the wire\n' "" \
        "$(jget "$_r" measurements.signature_bytes)" \
        "$(jget "$_r" measurements.signature_offset)" \
        "$(jget "$_r" negotiated.base_asym_name)"
done

prov_finish

hdr "done  ·  ${PROV_RUN_ID}"
printf '  run dir : %s\n' "$PROV_RUN_DIR"
printf '  read it : python3 harness/fields.py %s/t1_meas.decode.txt\n' "$PROV_RUN_DIR"

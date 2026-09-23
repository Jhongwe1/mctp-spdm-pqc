#!/usr/bin/env bash
#
# harness/census.sh — which committed captures contain which SPDM messages,
# including the captures nothing in this repository had ever decoded.
#
#     bash harness/census.sh
#
# Why this exists
# ---------------
# 2026-09-23. Seven documents, and the reason check_advisories.py gave for one
# verdict, said that no secure session had ever been established in this
# repository, and the evidence behind them was every committed decode. But 20 of the 152 committed captures had no
# decode at all, and two of those 20 hold a completed session: the week-1 run
# that left --exe_session at its default (SPDM 1.4, mutual authentication,
# encrypted records after FINISH_RSP), and the conformance suite's arm that
# clears MUT_AUTH_CAP. A census over the decodes had been a census over the
# captures somebody chose to decode.
#
# So every committed .pcap without a decode of the same name beside it is
# decoded here, by the pinned spdm_dump, into a new run directory, and
# census.tsv lists EVERY committed capture with the counts the session and
# advisory claims rest on:
#
#   decode         "beside" (an existing <arm>.decode.txt), the file written
#                  here, or "unreadable" — spdm_dump decoded no message at all
#   key_exchange   KEY_EXCHANGE requests      a session was attempted
#   finish_rsp     FINISH_RSP responses       a session was established
#   secured        SecuredSPDM records        traffic inside a session
#   get_mel        GET_MEASUREMENT_EXTENSION_LOG   reaches DMTF-2026-0002
#   get_csr        GET_CSR                         reaches DMTF-2026-0001
#   versions       every SPDM version byte on the wire, e.g. 10 11 12 14
#
# ★ "unreadable" is decided by what came out, not by spdm_dump's exit status.
# Handed an AF_MCTP link capture, spdm_dump prints the pcap header and then its
# own usage text — a refusal that looks like output. Zero decoded messages is
# the test, which is standing rule 2 applied to the decoder: the exit code is
# not the verdict. Those captures are counted by harness/pcapcount.py instead
# (docs/transports.md), and are listed here so that "every capture" can be
# checked to mean every capture.
#
# harness/check_advisories.py reads every */*.decode.txt, so its message census
# covers the decodes written here. harness/verify_repo.sh requires every
# committed capture to have a decode beside it or a row in the newest
# census.tsv, which is what stops the next undecoded capture from becoming the
# next blind spot.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
# shellcheck source=lib/provenance.sh
. "${REPO_ROOT}/harness/lib/provenance.sh"
set +e

if command -v spdm_dump >/dev/null 2>&1; then
    SPDM_DUMP="$(command -v spdm_dump)"
elif [ -x "${WORK_DIR}/spdm-dump/build/bin/spdm_dump" ]; then
    SPDM_DUMP="${WORK_DIR}/spdm-dump/build/bin/spdm_dump"
fi
[ -n "${SPDM_DUMP:-}" ] || die "spdm_dump not built — bash harness/build_spdm_dump.sh"

hdr "census of every committed capture"

prov_begin w12-census pqc
prov_pin_file "${WORK_DIR}/spdm-dump/BUILD_PIN.txt" BUILD_PIN.spdm-dump.txt spdm_dump
prov_note spdm_dump_binary "$SPDM_DUMP"

TSV="${PROV_RUN_DIR}/census.tsv"
printf 'capture\tdecode\tmessages\tkey_exchange\tfinish_rsp\tsecured\tget_mel\tget_csr\tversions\n' > "$TSV"

# grep -c prints 0 and exits 1 when nothing matches, and the count is what is
# wanted, so the status is discarded on purpose rather than by accident.
count() { grep -c -E -- "$1" "$2" 2>/dev/null; true; }

total=0 beside=0 here=0 unreadable=0
while IFS= read -r pcap; do
    total=$((total + 1))
    rel="${pcap#bench/data/}"
    existing="${REPO_ROOT}/${pcap%.pcap}.decode.txt"
    if [ -f "$existing" ]; then
        src="$existing"
        how="beside"
        beside=$((beside + 1))
    else
        name="$(dirname "$rel")__$(basename "$rel" .pcap).decode.txt"
        src="${PROV_RUN_DIR}/${name}"
        prov_cmd "$SPDM_DUMP" -r "$pcap"
        "$SPDM_DUMP" -r "${REPO_ROOT}/${pcap}" > "$src" 2>&1
        how="$name"
    fi

    msgs="$(count 'MCTP\([0-9]+\)' "$src")"
    if [ "$msgs" = 0 ]; then
        how="unreadable"
        unreadable=$((unreadable + 1))
        [ "$src" = "$existing" ] || rm -f "$src"
        printf '%s\tunreadable\t0\t\t\t\t\t\t\n' "$rel" >> "$TSV"
        continue
    fi
    [ "$how" = beside ] || here=$((here + 1))

    versions="$(grep -o -E 'SPDM\(1[0-9],' "$src" | tr -d 'SPDM(,' | sort -u | tr '\n' ' ')"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$rel" "$how" "$msgs" \
        "$(count 'SPDM_KEY_EXCHANGE \(' "$src")" \
        "$(count 'SPDM_FINISH_RSP' "$src")" \
        "$(count 'SecuredSPDM\(' "$src")" \
        "$(count 'SPDM_GET_MEASUREMENT_EXTENSION_LOG' "$src")" \
        "$(count 'SPDM_GET_CSR' "$src")" \
        "${versions% }" >> "$TSV"
done < <(git -C "$REPO_ROOT" ls-files -- 'bench/data/*.pcap' | sort)

prov_note captures_total "$total"
prov_note captures_decoded_beside "$beside"
prov_note captures_decoded_here "$here"
prov_note captures_unreadable "$unreadable"
prov_finish

log "census written to ${TSV#"${REPO_ROOT}"/}"
printf '  %s captures: %s decoded beside, %s decoded here, %s unreadable by spdm_dump\n' \
    "$total" "$beside" "$here" "$unreadable"
printf '\n  captures that hold a session, a MEL request or a CSR request:\n'
awk -F'\t' 'NR > 1 && ($4 + $5 + $6 + $7 + $8) > 0 {
    printf "    %-58s KEY_EX %3s  FINISH_RSP %2s  secured %3s  MEL %s  CSR %s  v%s\n",
           $1, $4, $5, $6, $7, $8, $9 }' "$TSV"

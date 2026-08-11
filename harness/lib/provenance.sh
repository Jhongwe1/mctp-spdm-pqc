# shellcheck shell=bash
#
# harness/lib/provenance.sh — stamp every experiment run with where it came from.
#
# The honesty rule this project works under is that every number it publishes
# must point at a capture file and name the exact upstream build that produced
# it. That is a rule a person forgets by week six. So it is a mechanism here,
# not a discipline: any script that records a result opens a run directory,
# and closing it writes a manifest.json containing the upstream commit hashes,
# the full command lines, the tool versions, and a SHA-256 of every artifact.
#
# Usage:
#     . harness/lib/provenance.sh
#     prov_begin healthcheck pqc
#     prov_note  spdm_version 1.3
#     prov_run   ./spdm_requester_emu --exe_conn DIGEST,CERT   # records + runs
#     prov_finish
#
# After prov_begin, $PROV_RUN_DIR is a fresh directory under bench/data/.
# Write every artifact there and prov_finish will hash it.

# ---------------------------------------------------------------------------

prov_begin() {
    local name="${1:?prov_begin needs a run name}"
    local flavor="${2:-unknown}"

    PROV_NAME="$name"
    PROV_FLAVOR="$flavor"
    PROV_STARTED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    PROV_RUN_ID="${name}-$(date -u +%Y%m%dT%H%M%SZ)"
    PROV_RUN_DIR="${REPO_ROOT}/bench/data/${PROV_RUN_ID}"

    mkdir -p "$PROV_RUN_DIR"

    PROV_META="${PROV_RUN_DIR}/.provenance.meta"
    PROV_CMDS="${PROV_RUN_DIR}/.provenance.cmds"
    : > "$PROV_META"
    : > "$PROV_CMDS"

    prov_note run_id       "$PROV_RUN_ID"
    prov_note name         "$name"
    prov_note flavor       "$flavor"
    prov_note started_at   "$PROV_STARTED"
    prov_note host_os      "$(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || uname -sr)"
    prov_note host_kernel  "$(uname -r)"
    prov_note host_arch    "$(uname -m)"
    prov_note host_nproc   "$(nproc 2>/dev/null || echo unknown)"
    prov_note gcc          "$(gcc -dumpfullversion -dumpversion 2>/dev/null || echo absent)"
    prov_note python       "$(python3 --version 2>&1 | awk '{print $2}')"
    prov_note openssl_cli  "$(openssl version 2>/dev/null || echo absent)"

    # The repo's own state. A result produced from a dirty tree is still valid,
    # but the reader deserves to know it was not a clean checkout.
    if git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
        prov_note repo_commit "$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo none)"
        if [ -n "$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null)" ]; then
            prov_note repo_dirty true
        else
            prov_note repo_dirty false
        fi
    fi

    # Fold in the upstream build pin, so each field lands in the manifest as a
    # first-class key (libspdm, spdm-emu, libspdm-version, ...).
    local pin
    pin="$(flavor_pin "$flavor" 2>/dev/null || true)"
    if [ -n "$pin" ] && [ -f "$pin" ]; then
        cp "$pin" "${PROV_RUN_DIR}/BUILD_PIN.txt"
        local line key val
        while IFS= read -r line; do
            [ -n "$line" ] || continue
            key="${line%%=*}"; val="${line#*=}"
            prov_note "upstream_${key//-/_}" "$val"
        done < "$pin"
    else
        prov_note upstream_pin "MISSING — results from this run cannot be attributed"
    fi
}

# prov_note <key> <value>   — record one metadata field.
prov_note() {
    printf '%s\t%s\n' "$1" "${2-}" >> "$PROV_META"
}

# prov_cmd <argv...>        — record a command line without running it.
prov_cmd() {
    local q="" a
    for a in "$@"; do q+="${q:+ }$(printf '%q' "$a")"; done
    printf '%s\n' "$q" >> "$PROV_CMDS"
}

# prov_run <argv...>        — record a command line, then run it.
prov_run() {
    prov_cmd "$@"
    "$@"
}

# prov_finish               — hash every artifact and write manifest.json.
prov_finish() {
    prov_note finished_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    python3 "${REPO_ROOT}/harness/lib/_manifest.py" \
        --run-dir "$PROV_RUN_DIR" \
        --meta    "$PROV_META" \
        --cmds    "$PROV_CMDS" \
        --out     "${PROV_RUN_DIR}/manifest.json"

    rm -f "$PROV_META" "$PROV_CMDS"

    printf 'provenance: %s\n' "${PROV_RUN_DIR}/manifest.json"
}

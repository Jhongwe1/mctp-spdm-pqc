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

    # Read the working tree's state BEFORE creating the run directory.
    #
    # Creating it first makes the tree dirty by definition, so repo_dirty was
    # recorded as true on every run this project has ever produced — including
    # runs from a genuinely clean checkout. A field that cannot say anything but
    # one value is not evidence, and it is worse than an absent field because a
    # reader has no way to tell it apart from a real observation.
    local dirty="unknown"
    if git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
        if [ -n "$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null)" ]; then
            dirty=true
        else
            dirty=false
        fi
    fi

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

    # The repo's own state, as it was before this run touched it. A result
    # produced from a dirty tree is still valid, but the reader deserves to know
    # it was not a clean checkout — which means the answer has to be capable of
    # being "no".
    if git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
        prov_note repo_commit "$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo none)"
        prov_note repo_dirty "$dirty"
    fi

    # Fold in the upstream build pin, so each field lands in the manifest as a
    # first-class key (libspdm, spdm-emu, libspdm-version, ...).
    prov_pin "$flavor" BUILD_PIN.txt
}

# prov_pin <flavor> <dest-filename>
#
# Copy a build flavor's BUILD_PIN.txt into the run directory and fold every
# key=value line into the manifest.
#
# A run may involve more than one build. The post-quantum comparison needs the
# pqc flavor and the released pair side by side, and every capture is read back
# by spdm_dump, which is a third binary with its own libspdm. Recording only the
# primary one would leave the others as unattributed dependencies of a published
# number — which is the thing this file exists to prevent.
prov_pin() {
    local flavor="${1:?prov_pin needs a flavor}" dest="${2:-BUILD_PIN.txt}"
    local pin
    pin="$(flavor_pin "$flavor" 2>/dev/null || true)"
    prov_pin_file "$pin" "$dest" "$flavor"
}

# prov_pin_file <path> <dest-filename> <label>
#
# The same, for a pin file that does not belong to a build flavor — spdm-dump,
# for instance. Keys are prefixed with the label so two pins cannot collide in
# the manifest.
prov_pin_file() {
    local src="${1:-}" dest="${2:?prov_pin_file needs a destination}" label="${3:?needs a label}"
    local prefix line key val

    # The primary flavor keeps the bare upstream_ prefix it has always had, so
    # existing manifests and anything reading them stay valid.
    if [ "$dest" = "BUILD_PIN.txt" ]; then
        prefix="upstream"
    else
        prefix="upstream_${label//-/_}"
    fi

    if [ -n "$src" ] && [ -f "$src" ]; then
        cp "$src" "${PROV_RUN_DIR}/${dest}"
        while IFS= read -r line; do
            [ -n "$line" ] || continue
            case "$line" in \#*) continue ;; esac
            key="${line%%=*}"; val="${line#*=}"
            prov_note "${prefix}_${key//-/_}" "$val"
        done < "$src"
    else
        prov_note "${prefix}_pin" "MISSING — results depending on ${label} cannot be attributed"
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

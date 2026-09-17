#!/bin/bash
set -u
OUT=/run/out
rc=0
note() { printf '\n======== %s\n' "$*"; }

note "kernel"
uname -srm

note "the device the guest enumerated"
lspci -nn | tee "$OUT/lspci.txt"

BDF=$(lspci -D -n | awk '$2 ~ /^0108:/ {print $1; exit}')
if [ -z "$BDF" ]; then
    echo "no NVMe class device found"
    lspci -D -n
    exit 3
fi
echo "NVMe at $BDF"
echo "$BDF" > "$OUT/bdf.txt"

# ★ The demo frame. A DOE capability in `lspci -vvv` is the guest's own
# enumeration of config space, and it is there whether or not anything ever
# drives the mailbox -- which is exactly why it is not the whole claim.
note "lspci -vvv, in full"
lspci -vvv -s "$BDF" > "$OUT/lspci-vvv.txt" 2>&1
if grep -qiE 'Data Object Exchange|DOE' "$OUT/lspci-vvv.txt"; then
    echo "Data Object Exchange capability present:"
    grep -iA6 -E 'Data Object Exchange|\[DOE\]' "$OUT/lspci-vvv.txt" | head -20
else
    echo "no DOE capability reported by lspci"
    echo "  (pciutils may be older than the capability; the probe checks config space directly)"
    rc=1
fi

note "extended capability walk and the two DOE protocols"
"$OUT/doe_probe" --device "$BDF" --verbose --discovery 2>&1 | tee "$OUT/doe-discovery.txt"
[ "${PIPESTATUS[0]}" -eq 0 ] || rc=1

note "one SPDM message across the mailbox"
"$OUT/doe_probe" --device "$BDF" --verbose --spdm 2>&1 | tee "$OUT/doe-spdm.txt"
[ "${PIPESTATUS[0]}" -eq 0 ] || rc=1

sync
exit $rc

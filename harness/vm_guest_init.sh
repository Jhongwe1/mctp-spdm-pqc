#!/bin/bash
#
# harness/vm_guest_init.sh — PID 1 inside the week-nine guest.
#
# The kernel built by harness/build_guest_kernel.sh has no initramfs and its
# root filesystem is the host's, exported over virtio-9p and mounted read-only.
# So this runs as process 1 with nothing mounted except that root, and its job
# is to make the guest usable, hand control to a script the host generated, and
# then make sure the machine stops.
#
# Three properties matter, and each of them is a way this can go wrong:
#
#   * IT MUST ALWAYS POWER OFF. If init returns, the kernel panics; if it
#     hangs, qemu runs until the orchestrator's timeout kills it and the run
#     looks like a hang rather than a failure. So the shutdown is in a trap and
#     runs whatever happened.
#
#   * THE ROOT IS READ-ONLY. Nothing here may create a directory outside the
#     tmpfs it mounts first, which is why the output share lands under /run and
#     not at /out: /run is tmpfs by then, / never becomes writable.
#
#   * THE EXIT STATUS HAS TO SURVIVE. A guest that fails cannot return a code
#     to the host across a power cycle, so the payload's status is written into
#     the share as a file and the host reads it from there. Standing rule: the
#     exit code is not the verdict, the evidence is.
#
# It is deliberately generic. Everything specific to a run is in the generated
# /run/out/guest_cmd.sh, which the orchestrator writes and then archives into
# the run directory, so the thing that ran is also the thing that is kept.

set -u
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
export HOME=/root
OUT=/run/out

finish() {
    status=$?
    sync
    printf 'guest_init: powering off (status %s)\n' "$status"
    # poweroff(8) needs an init system to talk to; there is none here, so go
    # straight at the kernel. The first is clean, the second is the fallback.
    /sbin/poweroff -f 2>/dev/null
    echo o > /proc/sysrq-trigger 2>/dev/null
    # If even that did not work, stop rather than return into a panic.
    while true; do sleep 60; done
}
trap finish EXIT

mount -t proc     proc     /proc     2>/dev/null
mount -t sysfs    sysfs    /sys      2>/dev/null
mount -t devtmpfs devtmpfs /dev      2>/dev/null
mkdir -p /dev/pts 2>/dev/null
mount -t devpts   devpts   /dev/pts  2>/dev/null

# devtmpfs gives you device nodes and nothing else. On a normal system these
# four symlinks are made by the distribution's /dev setup or by udev, and
# nothing here runs either. Without /dev/fd, bash process substitution — the
# `< <(...)` in the generated payload — fails with "No such file or directory"
# on every iteration of a polling loop, which is exactly how this was found.
ln -sfn /proc/self/fd   /dev/fd     2>/dev/null
ln -sfn /proc/self/fd/0 /dev/stdin  2>/dev/null
ln -sfn /proc/self/fd/1 /dev/stdout 2>/dev/null
ln -sfn /proc/self/fd/2 /dev/stderr 2>/dev/null
mount -t tmpfs    tmpfs    /tmp      2>/dev/null
mount -t tmpfs    tmpfs    /run      2>/dev/null
mount -t tmpfs    tmpfs    /var/tmp  2>/dev/null

mkdir -p "$OUT"
if ! mount -t 9p -o trans=virtio,version=9p2000.L,msize=262144,access=any \
        w9out "$OUT"; then
    printf 'guest_init: could not mount the output share\n'
    exit 1
fi

printf 'guest_init: %s\n' "$(uname -srm)"
printf 'guest_init: AF_MCTP is %s\n' \
    "$(grep -q '^CONFIG_MCTP=y' /proc/config.gz 2>/dev/null && echo probable || echo 'checked below')"

if [ ! -f "$OUT/guest_cmd.sh" ]; then
    printf 'guest_init: no guest_cmd.sh in the share\n'
    echo 127 > "$OUT/guest_status"
    exit 1
fi

bash "$OUT/guest_cmd.sh" > "$OUT/guest.log" 2>&1
rc=$?
echo "$rc" > "$OUT/guest_status"
printf 'guest_init: payload exited %s\n' "$rc"
tail -40 "$OUT/guest.log"
sync
exit 0

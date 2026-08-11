# ADR 0002 — WSL2 for development, Docker for reproduction, one set of scripts

**Status:** accepted · **Date:** 2026-08-11 · **Gate:** G0

## Context

Development happens on Windows 11. `libspdm` and `spdm-emu` build with CMake
against GCC and are exercised on Linux upstream. Three environments were
available: a native Windows toolchain, Docker Desktop, and WSL2 with
Ubuntu 24.04.

Two requirements pull in different directions:

- Day-to-day work needs to be fast. Building `libspdm` means building OpenSSL,
  which is tens of thousands of small compilation units.
- The result needs to be reproducible by someone else, on a machine that is
  not this one, without a conversation.

## Decision

**WSL2 (Ubuntu 24.04) is the development environment. A pinned Docker image is
the reproducibility contract. Both run the same scripts, unmodified.**

Nothing in `harness/` may depend on which of the two it is running under. The
scripts locate the repository from their own path, take the build tree
location from `LAB_DIR`, and require no absolute paths.

Two consequences are handled in the scripts rather than left to the reader:

**Build trees live on the Linux filesystem.** `LAB_DIR` defaults to
`~/spdm-lab`, never under `/mnt/c`. WSL2 reaches NTFS through a 9P protocol
layer, and small-file operations across it cost one to two orders of magnitude
more than on ext4. The repository itself may live anywhere, including a
Windows path — it is small, and it is not what gets compiled.

**Line endings are forced to LF at the repository level.** The working tree may
be on NTFS while every script is executed by bash. `.gitattributes` sets
`eol=lf` and had to exist before the first `git add`, because after that the
index has already recorded whatever it first saw. A single CR in a shell script
produces `$'\r': command not found`, and in a shebang it produces a failure
with no useful message at all.

Scripts are invoked as `bash harness/foo.sh`, not `./harness/foo.sh`, so that
a working tree which did not preserve the executable bit still works.

## Consequences

**Good**

- The fast path and the reproducible path cannot drift apart, because they are
  the same code.
- CI is a third instance of the same thing rather than a special case, so a
  green CI run is evidence that a stranger's clone would also work.
- The documented fallback for an unrecoverable local build ("stop after ninety
  minutes and use the container") requires no new instructions.

**Bad**

- Windows users must install WSL2 or Docker. Documented as the first step of
  the runbook rather than treated as an obstacle.
- The Docker image needs its base pinned by digest and refreshed deliberately,
  or it silently stops being the same environment.

## Alternatives rejected

- **Native Windows + MinGW.** The upstream CMake toolchain files target MSVC on
  Windows and GCC on Linux; MinGW is neither. Every problem hit would be a
  problem nobody upstream has.
- **Docker as the primary environment.** Docker Desktop on Windows runs its
  Linux containers inside WSL2. Choosing it as primary adds a layer without
  removing one, and slows the edit-build-run loop for no benefit that WSL2 does
  not already provide.
- **A remote Linux machine.** Removes the offline path, and adds a dependency
  on something that can be unavailable on the evening a deadline lands.

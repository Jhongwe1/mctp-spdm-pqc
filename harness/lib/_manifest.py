#!/usr/bin/env python3
"""Emit manifest.json for one experiment run. Called by harness/lib/provenance.sh.

Kept in Python rather than jq because JSON escaping from bash is a source of
silent corruption, and because python3 is already a hard requirement of this
project while jq is not present in every container this has to run in.

Every regular file in the run directory is hashed. That is the point: the
manifest is what lets a reader confirm that the capture file next to a table is
the capture file the table was computed from.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

CHUNK = 1 << 20


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(CHUNK):
            digest.update(chunk)
    return digest.hexdigest()


def read_meta(path: Path) -> dict:
    """Tab-separated key/value pairs. Later keys win, so a script can revise."""
    meta: dict[str, str] = {}
    if not path.exists():
        return meta
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        key, _, value = line.partition("\t")
        meta[key] = value
    return meta


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--run-dir", type=Path, required=True)
    ap.add_argument("--meta", type=Path, required=True)
    ap.add_argument("--cmds", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)
    args = ap.parse_args()

    meta = read_meta(args.meta)

    commands = []
    if args.cmds.exists():
        commands = [l for l in args.cmds.read_text(encoding="utf-8").splitlines() if l.strip()]

    artifacts = []
    for path in sorted(args.run_dir.rglob("*")):
        if not path.is_file():
            continue
        # Skip our own bookkeeping and the manifest we are about to write.
        if path.name.startswith(".provenance") or path == args.out:
            continue
        artifacts.append(
            {
                "path": str(path.relative_to(args.run_dir)),
                "bytes": path.stat().st_size,
                "sha256": sha256_of(path),
            }
        )

    manifest = {
        "schema": "mctp-spdm-pqc/provenance/v1",
        "run": {k: v for k, v in meta.items() if not k.startswith("upstream_")},
        "upstream": {
            k[len("upstream_"):]: v for k, v in meta.items() if k.startswith("upstream_")
        },
        "commands": commands,
        "artifacts": artifacts,
        "artifact_count": len(artifacts),
        "artifact_bytes": sum(a["bytes"] for a in artifacts),
    }

    args.out.write_text(json.dumps(manifest, indent=2, sort_keys=False) + "\n",
                        encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Which pinned tools have a newer upstream release?

Reads layer.toml — the realm's single source of truth — and asks each tool's
repository for its latest release tag. Prints one `name<TAB>old<TAB>new` line
per tool that moved, and nothing when nothing moved.

Deliberately NOT a diff of the workflow file: pins live in layer.toml, and a
scanner that read them from anywhere else would be a second place the realm is
defined (varve REQ-PEL-MANIFEST-001).

Fail-loud by design. This feeds an AUTONOMOUS deposit, so "I could not ask" must
never look like "nothing moved" — a scanner that silently reported no movement
would freeze the realm while appearing healthy. Any repository that cannot be
queried is an error, and the caller stops.
"""
import json
import os
import subprocess
import sys
import tomllib


def latest_release(repo: str) -> str:
    """The repository's latest release tag, or raise."""
    out = subprocess.run(
        ["gh", "release", "view", "--repo", repo, "--json", "tagName"],
        capture_output=True, text=True,
    )
    if out.returncode != 0:
        raise RuntimeError(f"{repo}: {out.stderr.strip()[:160]}")
    tag = json.loads(out.stdout)["tagName"]
    if not tag:
        raise RuntimeError(f"{repo}: latest release has an empty tag")
    return tag


def main() -> int:
    manifest = tomllib.load(open("layer.toml", "rb"))
    moved, failures = [], []
    for tool in manifest.get("tool", []):
        name = tool["name"]
        repo = tool.get("repo", f"pulseengine/{name}")
        pinned = tool["version"]
        try:
            newest = latest_release(repo)
        except Exception as e:  # noqa: BLE001 — every failure is the same answer: stop
            failures.append(str(e))
            continue
        if newest != pinned:
            moved.append((name, pinned, newest))
        print(f"  {name:<16} pinned {pinned:<12} latest {newest}", file=sys.stderr)

    if failures:
        for f in failures:
            print(f"::error::could not ask upstream: {f}", file=sys.stderr)
        print(
            "::error::refusing to report movement from an incomplete scan — "
            "'I could not ask' is not 'nothing moved', and an autonomous "
            "depositor acting on the difference would freeze the realm while "
            "looking healthy",
            file=sys.stderr,
        )
        return 1

    for name, old, new in moved:
        print(f"{name}\t{old}\t{new}")
    print(f"{len(moved)} tool(s) moved", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())

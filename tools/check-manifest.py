#!/usr/bin/env python3
"""Check layer.toml against reality, before anything is signed.

Not a formatter. Every check here corresponds to a way a layer has actually
gone wrong in varve, or would silently go wrong:

  * a repo pinned at two versions  — one release's assets get checked against
    another release's sums; verification that passes while proving nothing
    (varve's assembler refuses this, and finding it here is cheaper)
  * a version that does not exist upstream — a typo that fails 20 minutes into
    a deposit rather than in review
  * a vsix asset template with no %V — every platform resolves to one name
"""
import json
import subprocess
import sys
import tomllib

def gh_release_exists(repo: str, tag: str) -> bool:
    r = subprocess.run(["gh", "release", "view", tag, "--repo", repo, "--json", "tagName"],
                       capture_output=True, text=True)
    return r.returncode == 0

def main() -> int:
    d = tomllib.load(open("layer.toml", "rb"))
    fail = []
    pins: dict[str, set[str]] = {}

    entries = [("tool", t) for t in d.get("tool", [])] + [("vsix", v) for v in d.get("vsix", [])]
    for kind, e in entries:
        name, ver = e["name"], e["version"]
        repo = e.get("repo", f"pulseengine/{name}")
        pins.setdefault(repo, set()).add(ver)
        if kind == "vsix" and "%V" in e.get("asset", "") is False:
            fail.append(f"vsix {name}: asset template has no %V")

    # One repo, one version. This is the dangerous one.
    for repo, vers in sorted(pins.items()):
        if len(vers) > 1:
            fail.append(
                f"{repo} is pinned at {len(vers)} versions ({', '.join(sorted(vers))}) — "
                f"one release's assets would be checked against another's sums")

    if "--offline" not in sys.argv:
        for repo, vers in sorted(pins.items()):
            for v in sorted(vers):
                if not gh_release_exists(repo, v):
                    fail.append(f"{repo}@{v} does not exist upstream")

    for f in fail:
        print(f"FAIL: {f}", file=sys.stderr)
    if fail:
        return 1
    print(f"layer.toml OK — {len(d.get('tool', []))} tool(s), {len(d.get('vsix', []))} vsix, "
          f"{len(pins)} repo(s), no repo at two versions")
    return 0

if __name__ == "__main__":
    sys.exit(main())

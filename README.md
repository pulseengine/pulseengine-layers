# pulseengine-layers

Layer assembly for the **`pulseengine`** realm. This repo holds *what* the
realm vouches for; [`pulseengine/varve`](https://github.com/pulseengine/varve)
holds *how*.

## The one file that matters

[`layer.toml`](layer.toml) **is** the layer. Bumping a tool version is a change
to that file and nothing else — no workflow edit, no varve commit. Before this
repo existed the tool list lived in an `env:` block inside varve's own
`deposit-layer.yml`, which meant bumping a tool was a commit to the tool that
installs tools, and varve's release cadence was coupled to every upstream bump.

```sh
python3 tools/check-manifest.py            # before you open the PR
python3 tools/check-manifest.py --offline  # no network; skips existence checks
```

That check exists because of things that have actually gone wrong: a repo
pinned at two versions means one release's assets get checked against another
release's sums — verification that passes while proving nothing. varve's
assembler refuses it; catching it in review is cheaper.

## The assembler is borrowed, never copied

The varve binary **and** the assembler come from a varve release, pinned in
`layer.toml`'s `[varve] version`. Nothing is vendored here.

That is deliberate. The assembler is system-tested in varve (REQ-SYSTEST-002)
against recorded release metadata, with its own mutation proving the gate goes
red — and none of that testing is worth anything to a realm running a *copy*.
If you find yourself wanting to patch the assembler locally, that is a signal
varve needs a change, not that this repo needs a fork.

The workflow verifies the varve release it downloads (cosign, against varve's
`release.yml` identity) before extracting it. The tool that vouches for a
layer's contents gets the same treatment it gives them.

## Custody

This repo holds **one** realm's signing key, as a secret, and it is the only
place that key is used. A second realm gets a second repository — two roots in
one settings page is exactly the custody failure this split exists to prevent,
and varve has no key rotation, so unpicking it later is not cheap.

`varve docs root-ceremony` is the procedure. `varve docs ci` has the two
patterns for getting a key into CI without ever writing it to the workspace.

## Handover — read this before continuing

This repo is **bootstrapped, not finished.** What works: the manifest, its
check, the rivet artifacts, the workflow's fetch-and-verify of a pinned varve
release, and — since varve v0.31.0 — the assembly step itself.

**The adapter that was the blocker no longer needs writing.** `varve-producer
deposit --manifest layer.toml` reads *this file* directly. There is no
`TARBALL_TOOLS` translation to build, and one must not be built: that encoding
cannot express a payload `layout`, so an `sdk` entry translated through it
silently becomes an ordinary tarball and the tree gets mined for a binary.
`varve layer-spec` is the old path and this workflow does not call it.

What is still open:

1. **`VARVE_ROLLING_KEY` is not provisioned here.** It is still in varve's
   settings. Do not remove it there until this repo has published a layer
   successfully — a migration that removes the old path before the new one
   works leaves the realm unable to publish at all.
2. **`packages: write` on `GITHUB_TOKEN` is not the same as write access to
   the destination package.** The realm publishes to
   `ghcr.io/pulseengine/varve/layers`, a package created by *another*
   repository. Until `pulseengine/varve/layers` grants this repo write access
   in its package settings, the first `oras blob push` fails with 403. Nothing
   is published before that point (the immutability check is a read and runs
   first), so the failure is safe — but it is the first thing to check when
   the first dispatch goes red.
3. **No layer has been published from this repo yet.** The next layer is
   `2026.09.2`, counter `3` — derived from the published registry, not chosen:
   the newest tag is `2026.09.1` and its baseline line-status is counter `2`
   on line `2026.09`.
4. **`with-device` is left out of the layer**, and `layer.toml` says why at
   length: jess's release *tag* and the payload's *version* are different
   numbers, and layer.toml has one `version` field serving as both. Restoring
   the entry needs a varve change, not an edit here.

## Traceability

`rivet validate` runs here with the **same schema set as varve**
(`common`, `dev`, `stpa`, `stpa-sec`, `aspice`, `supply-chain`, `research`), so
claims made here can be linked to varve's requirements rather than living in a
separate vocabulary. Requirements are in [`artifacts/`](artifacts/).

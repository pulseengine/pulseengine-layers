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
check, the rivet artifacts, and the workflow's fetch-and-verify of a pinned
varve release. What does not:

1. **The `layer.toml` → deposit-spec adapter does not exist.** varve's
   assembler reads its tool list from `TARBALL_TOOLS` / `VSIX_PACKAGES` /
   `WSC_VERSION` env vars. Something must translate this manifest into them.
   The deposit workflow currently `exit 1`s at that step with a pointer here,
   rather than pretending to work.
   - The natural home is **varve**, beside the assembler, so it is covered by
     the same system gate. A translator living here would be untested code on
     the trust path.
   - varve's assembler now also accepts `COMPOSES` and tolerates an empty
     `WSC_VERSION`/`VSIX_PACKAGES` (added when a second realm proved
     unbuildable without it).
2. **`VARVE_ROLLING_KEY` is not provisioned here.** It is still in varve's
   settings. Do not remove it there until this repo has published a layer
   successfully — a migration that removes the old path before the new one
   works leaves the realm unable to publish at all.
3. **No layer has been published from this repo yet.** The next layer is
   `2026.08.4`, counter `5` — derived from the published registry, not chosen.

## Traceability

`rivet validate` runs here with the **same schema set as varve**
(`common`, `dev`, `stpa`, `stpa-sec`, `aspice`, `supply-chain`, `research`), so
claims made here can be linked to varve's requirements rather than living in a
separate vocabulary. Requirements are in [`artifacts/`](artifacts/).

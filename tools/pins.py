#!/usr/bin/env python3
"""What layer.toml pins, and which tag each pin asks for.

THE one answer to those two questions. They were answered separately in three
places — the scanner, the scanner's inline rewrite, and check-manifest.py — and
all three got the hub case wrong in the same way, because each re-derived the
rule from the field names rather than from what the fields MEAN.

Two rules, and the second is the one that keeps being missed:

  * The sections are whatever top-level arrays the manifest defines. Never a
    list written in code: `[[crate]]` and `[[docs]]` were carried by a layer
    and ignored by every tool here, so their pins would have frozen while the
    rest of the realm moved on, silently.

  * `version` is what the payload IS; the tag to ASK a forge for is `release`
    when the entry has one. A hub ships a payload under its own number —
    pulseengine/jess tags `v0.7.2` and ships `with-device` at `0.2.2` (varve
    REQ-PAYLOADID-001) — so reading `version` as a tag makes that payload
    permanently "moved" for the scanner and permanently "missing upstream" for
    the checker. Both were live.
"""


def sections(manifest: dict) -> list[str]:
    """Every payload section the manifest defines, in its own order."""
    return [k for k, v in manifest.items() if isinstance(v, list)]


def entries(manifest: dict):
    """Every payload entry, as (section, entry)."""
    return [(s, e) for s in sections(manifest) for e in manifest[s]]


def repo_of(entry: dict) -> str:
    """The `owner/repo` an entry comes from; `pulseengine/<name>` by default."""
    return entry.get("repo", f"pulseengine/{entry['name']}")


def asked_tag(entry: dict) -> str:
    """The release tag this entry asks a forge for."""
    return entry.get("release", entry["version"])


def tracks_tag(entry: dict) -> bool:
    """Does this entry's `version` follow the release tag?

    True with no `release` (the version IS the tag), or when the two agree once
    a leading `v` is discounted. False for a hub payload, whose number is its
    own and cannot be derived from a tag.
    """
    release = entry.get("release")
    if release is None:
        return True
    return entry["version"].lstrip("v") == release.lstrip("v")

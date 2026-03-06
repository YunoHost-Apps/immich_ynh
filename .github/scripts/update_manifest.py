#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
update_manifest.py
Updates manifest.toml from the upstream global JSON (meta/global.json).

What it does:
  - Sets top-level `version` to "<IMMICH_VERSION>~ynh1"
  - Sets `[resources.nodejs].version` to NODE_VERSION
  - For each distro present in JSON (e.g., bookworm, trixie, ...), updates:
      [resources.sources.immich_prebuilt_<distro>].<arch>.url
      [resources.sources.immich_prebuilt_<distro>].<arch>.sha256
    (Arch supported: amd64, arm64 if present in JSON)
  - Does NOT add the "file" key (keeps schema clean)
  - Preserves comments and ordering (tomlkit)
  - Writes back only if content changed (idempotent)

Environment variables (provided by the workflow):
  - IMMICH_VERSION (required)
  - NODE_VERSION   (required)

Author: ewilly
"""

import os
import sys
import json
from pathlib import Path
from typing import Dict, Any
import tomlkit


MANIFEST_PATH = Path("manifest.toml")
GLOBAL_JSON   = Path("meta/global.json")

TOP_KEYS = {
    "immich_version",
    "node_version",
    "pnpm_version",
    "python_version",
    "mise_version",
    "exec_time",
    "peak_ram",
    "disk_used",
}

ARCHES = ("amd64", "arm64")


def fail(msg: str) -> None:
    print(f"::error::{msg}", file=sys.stderr)
    sys.exit(1)


def load_json(p: Path) -> Dict[str, Any]:
    if not p.exists():
        fail(f"JSON file not found: {p}")
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except Exception as e:
        fail(f"Failed to parse JSON {p}: {e}")


def load_toml(p: Path):
    if not p.exists():
        fail(f"TOML file not found: {p}")
    try:
        return tomlkit.parse(p.read_text(encoding="utf-8"))
    except Exception as e:
        fail(f"Failed to parse TOML {p}: {e}")


def ensure_table(container, key: str):
    """Ensure a toml table exists under container[key], and return it."""
    if key not in container or not isinstance(container[key], tomlkit.items.Table):
        container[key] = tomlkit.table()
    return container[key]


def main() -> None:
    immich_version = os.environ.get("IMMICH_VERSION")
    node_version   = os.environ.get("NODE_VERSION")

    if not immich_version:
        fail("IMMICH_VERSION is required.")
    if not node_version:
        fail("NODE_VERSION is required.")

    data = load_json(GLOBAL_JSON)
    doc  = load_toml(MANIFEST_PATH)

    # 1) Top-level version: <immich>~ynh1
    doc["version"] = f"{immich_version}~ynh1"

    # 2) NodeJS version
    try:
        doc["resources"]["nodejs"]["version"] = node_version
    except Exception:
        fail("Missing [resources.nodejs.version] in manifest.toml")

    # 3) Sources per distro
    try:
        resources = doc["resources"]
        sources   = resources["sources"]
    except Exception:
        fail("Missing [resources.sources] in manifest.toml")

    # Iterate over JSON entries; skip known top-level meta keys
    for key, block in data.items():
        if key in TOP_KEYS:
            continue
        if not isinstance(block, dict):
            # Skip non-object entries (defensive)
            continue

        distro = key
        table_name = f"immich_prebuilt_{distro}"  # <-- FIXED (no 'versions')

        table = ensure_table(sources, table_name)

        # Update per-arch fields if present in JSON
        for arch in ARCHES:
            url_k = f"{arch}_url"
            sha_k = f"{arch}_sha256"

            has_any = (url_k in block) or (sha_k in block)
            if not has_any:
                continue  # nothing to update for this arch/distro

            arch_table = ensure_table(table, arch)

            if url_k in block and block[url_k]:
                arch_table["url"] = block[url_k]
            if sha_k in block and block[sha_k]:
                arch_table["sha256"] = block[sha_k]

            # NOTE: We intentionally DO NOT write ".file" to keep manifest schema minimal.

    # Write back only if content changed (idempotent)
    original = MANIFEST_PATH.read_text(encoding="utf-8")
    new_text = tomlkit.dumps(doc)
    if new_text != original:
        MANIFEST_PATH.write_text(new_text, encoding="utf-8")
        print("✔ manifest.toml updated (version, nodejs, sources).")
    else:
        print("✔ No changes detected (idempotent).")


if __name__ == "__main__":
    main()

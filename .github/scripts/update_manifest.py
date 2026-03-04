#!/usr/bin/env python3
import os
import json
from pathlib import Path
import tomlkit

# Environment variables (provided by workflow)
IMMICH_VERSION = os.environ["IMMICH_VERSION"]
NODE_VERSION   = os.environ["NODE_VERSION"]

manifest_path = Path("manifest.toml")
global_json   = Path("meta/global.json")

# Load TOML
doc = tomlkit.parse(manifest_path.read_text(encoding="utf-8"))

# Load global manifest JSON
data = json.loads(global_json.read_text(encoding="utf-8"))

# 1) Update top-level version
doc["version"] = f"{IMMICH_VERSION}~ynh1"

# 2) Update nodejs version
doc["resources"]["nodejs"]["version"] = NODE_VERSION

# 3) Update distro sections
sources = doc["resources"]["sources"]

# Keys to ignore at the top of the JSON
top_keys = {
    "immich_version",
    "node_version",
    "pnpm_version",
    "python_version",
    "mise_version",
}

for key, block in data.items():
    if key in top_keys:
        continue  # Skip version sections

    distro = key
    table_name = f"immich_prebuilt_versions_{distro}"

    # Ensure table exists
    if table_name not in sources:
        sources[table_name] = tomlkit.table()

    table = sources[table_name]

    # For each arch (amd64, arm64)
    for arch in ("amd64", "arm64"):
        file_k = f"{arch}_file"
        url_k  = f"{arch}_url"
        sha_k  = f"{arch}_sha256"

        if file_k not in block:
            continue  # no data for this arch/distro

        arch_table = table.get(arch)
        if arch_table is None:
            arch_table = tomlkit.table()
            table[arch] = arch_table

        arch_table["file"]   = block[file_k]
        arch_table["url"]    = block[url_k]
        arch_table["sha256"] = block[sha_k]

# Write updated manifest
manifest_path.write_text(tomlkit.dumps(doc), encoding="utf-8")

print("✔ manifest.toml updated successfully (global + multi-arch)")

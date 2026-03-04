#!/usr/bin/env python3
import json, re, os
from pathlib import Path
import tomlkit

# Read environment variables
immich_version = os.environ["IMMICH_VERSION"]
node_version   = os.environ["NODE_VERSION"]

manifest_path = Path("manifest.toml")
doc = tomlkit.parse(manifest_path.read_text(encoding="utf-8"))

# 1) Set global version
doc["version"] = f"{immich_version}~ynh1"

# 2) Update nodejs version
doc["resources"]["nodejs"]["version"] = node_version

# 3) Update prebuilt metadata for each distro
meta_dir = Path("meta")

for meta_file in sorted(meta_dir.glob("meta-*.json")):
    meta = json.loads(meta_file.read_text())
    tar = meta["tar"]
    jsn = meta["json"]

    # Extract distro from tar filename
    # Example: immich-v2.6.0-bookworm-amd64.tar.gz -> "bookworm"
    m = re.search(r"-([a-z0-9]+)-amd64\.tar\.gz$", tar["file"])
    if not m:
        continue

    distro = m.group(1)

    # JSON metadata block
    key_json = f"immich_prebuilt_versions_{distro}"
    doc["resources"]["sources"].setdefault(key_json, {})
    doc["resources"]["sources"][key_json]["url"]    = jsn["url"]
    doc["resources"]["sources"][key_json]["sha256"] = jsn["sha256"]

    # TAR metadata block
    key_tar = f"immich_prebuilt_{distro}"
    doc["resources"]["sources"].setdefault(key_tar, {})
    doc["resources"]["sources"][key_tar]["url"]    = tar["url"]
    doc["resources"]["sources"][key_tar]["sha256"] = tar["sha256"]

# Write manifest
manifest_path.write_text(tomlkit.dumps(doc), encoding="utf-8")
print("✔ manifest.toml updated successfully")

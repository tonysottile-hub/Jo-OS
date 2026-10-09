#!/usr/bin/env python3
"""Reject visually redundant media packages before documentary rendering.

Usage: python3 orchestration/qa/visual_diversity.py manifest.json
Manifest must contain an array 'assets' (or 'media') of objects with a
local path/file_path and optional source_url/title. No network calls.
"""
import hashlib
import json
import pathlib
import re
import sys

def canonical_title(value):
    s = str(value or "").lower()
    s = re.sub(r"\.(tiff?|jpe?g|png|webp)$", "", s)
    s = re.sub(r"\b(?:original|thumb|thumbnail|large|small|scan|copy)\b", "", s)
    return re.sub(r"[^a-z0-9]+", " ", s).strip()

def inspect(manifest):
    assets = manifest.get("assets", manifest.get("media", []))
    if not isinstance(assets, list):
        raise ValueError("assets must be an array")
    unique, duplicates = {}, []
    for item in assets:
        if not isinstance(item, dict):
            raise ValueError("each asset must be an object")
        path = item.get("path") or item.get("file_path")
        if not path or not pathlib.Path(path).is_file():
            raise ValueError("missing local media file: " + str(path))
        digest = hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest()
        source = item.get("source_url") or item.get("url") or ""
        # Wikimedia's Special:FilePath and thumbnail URLs can encode the same
        # filename; use an explicit work_id when available for robust grouping.
        identity = canonical_title(item.get("work_id") or item.get("source_title") or item.get("title") or pathlib.Path(path).stem)
        key = identity or digest
        if key in unique or digest in [x["sha256"] for x in unique.values()]:
            duplicates.append({"path": path, "identity": key})
        else:
            unique[key] = {"path": path, "sha256": digest, "source_url": source}
    return {"total_assets": len(assets), "distinct_works": len(unique),
            "duplicates": duplicates, "passed": len(unique) >= 5 and not duplicates}

if __name__ == "__main__":
    try:
        result = inspect(json.loads(pathlib.Path(sys.argv[1]).read_text()))
        print(json.dumps(result, indent=2))
        sys.exit(0 if result["passed"] else 1)
    except (IndexError, OSError, ValueError, KeyError) as exc:
        print(json.dumps({"passed": False, "error": str(exc)}))
        sys.exit(2)

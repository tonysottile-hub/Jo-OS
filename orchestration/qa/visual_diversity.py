#!/usr/bin/env python3
"""Pre-render source diversity gate for Unmapped America.

Usage: python3 orchestration/qa/visual_diversity.py manifest.json
Works on the existing render manifest's media_sources metadata, without
requiring local media files. Blocks duplicate representations of the same
historical work and rejects a one-category documentary visual package.
"""
import json
import pathlib
import re
import sys
from urllib.parse import unquote, urlparse

def identity(source):
    title = unquote(str(source.get("title") or source.get("source_url") or source.get("url") or ""))
    title = title.split("File:")[-1].split("/")[-1]
    title = re.sub(r"\.(?:tiff?|jpe?g|png|webp)(?:\?.*)?$", "", title, flags=re.I)
    return re.sub(r"[^a-z0-9]+", " ", title.lower()).strip()

def category(source):
    title = str(source.get("title", "")).lower()
    if "map" in title or "atlas" in title or "plat" in title:
        return "map"
    if "photograph" in title or "photo" in title:
        return "photo"
    if "postcard" in title:
        return "postcard"
    if "newspaper" in title:
        return "newspaper"
    return "other"

def inspect(manifest):
    sources = manifest.get("media_sources")
    if not isinstance(sources, list) or not sources:
        return {"passed": False, "error": "media_sources metadata missing; cannot verify source diversity"}
    if not all(isinstance(s, dict) for s in sources):
        return {"passed": False, "error": "invalid media_sources entries"}
    identities = [identity(s) for s in sources]
    if not all(identities):
        return {"passed": False, "error": "source identity missing"}
    counts = {i: identities.count(i) for i in set(identities)}
    duplicates = sorted(i for i, count in counts.items() if count > 1)
    categories = sorted({category(s) for s in sources})
    # Five distinct works and two media categories are conservative minimums,
    # not a substitute for final human perceptual review.
    passed = len(counts) >= 5 and len(categories) >= 2 and not duplicates and categories != ["other"]
    return {"passed": passed, "total_assets": len(sources),
            "distinct_works": len(counts), "duplicate_works": duplicates,
            "media_categories": categories, "requires_human_review": True}

if __name__ == "__main__":
    try:
        result = inspect(json.loads(pathlib.Path(sys.argv[1]).read_text()))
        print(json.dumps(result, indent=2))
        sys.exit(0 if result["passed"] else 1)
    except (IndexError, OSError, ValueError, TypeError) as exc:
        print(json.dumps({"passed": False, "error": str(exc)}))
        sys.exit(2)

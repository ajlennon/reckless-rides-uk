#!/usr/bin/env python3
"""Sync YouTube privacy status from API into *_UPLOAD.json (for public-only map)."""
from __future__ import annotations

import argparse
import importlib.util
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROCESSED = ROOT / "evidence" / "processed"


def load_youtube_module():
    spec = importlib.util.spec_from_file_location(
        "youtube_upload", ROOT / "scripts" / "youtube-upload.py"
    )
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def main() -> int:
    parser = argparse.ArgumentParser(description="Sync YouTube privacy into UPLOAD.json")
    parser.add_argument(
        "incident",
        nargs="?",
        help="DEB base name or UPLOAD.json (default: all with video_id)",
    )
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    paths = sorted(PROCESSED.glob("*_UPLOAD.json"))
    if args.incident:
        base = args.incident.replace("_UPLOAD.json", "")
        paths = [p for p in paths if p.name.startswith(base)]

    video_map: list[tuple[Path, str]] = []
    for path in paths:
        meta = json.loads(path.read_text())
        vid = (meta.get("youtube") or {}).get("video_id", "")
        if vid:
            video_map.append((path, vid))

    if not video_map:
        print("No videos to sync.")
        return 0

    yt_mod = load_youtube_module()
    youtube = yt_mod.get_youtube_service()
    ids = [v for _, v in video_map]
    privacy_by_id: dict[str, str] = {}

    for i in range(0, len(ids), 50):
        chunk = ids[i : i + 50]
        resp = youtube.videos().list(part="status", id=",".join(chunk)).execute()
        for item in resp.get("items", []):
            privacy_by_id[item["id"]] = item["status"]["privacyStatus"]

    updated = 0
    for path, vid in video_map:
        live = privacy_by_id.get(vid)
        if not live:
            print(f"skip {path.name}: not found on YouTube", file=sys.stderr)
            continue
        meta = json.loads(path.read_text())
        yt = meta.setdefault("youtube", {})
        old = yt.get("privacy", "")
        if old == live:
            continue
        yt["privacy"] = live
        if args.dry_run:
            print(f"would update {path.name}: {old!r} -> {live!r}")
        else:
            path.write_text(json.dumps(meta, indent=2) + "\n")
            print(f"updated {path.name}: {old!r} -> {live!r}")
        updated += 1

    print(f"Done: {updated} file(s) changed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

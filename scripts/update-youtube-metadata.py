#!/usr/bin/env python3
"""Update title, description, and tags on existing YouTube videos from *_UPLOAD.json."""
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
        "youtube_upload",
        ROOT / "scripts" / "youtube-upload.py",
    )
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def resolve_upload_json(arg: str) -> Path:
    p = Path(arg)
    if p.is_file():
        return p.resolve()
    base = arg.replace("_UPLOAD.json", "").replace(".json", "")
    candidate = PROCESSED / f"{base}_UPLOAD.json"
    if candidate.is_file():
        return candidate
    raise FileNotFoundError(f"Upload metadata not found: {arg}")


def iter_upload_jsons() -> list[Path]:
    return sorted(PROCESSED.glob("*_UPLOAD.json"))


def update_video(youtube_mod, upload_path: Path, dry_run: bool) -> bool:
    meta = json.loads(upload_path.read_text())
    yt = meta.get("youtube") or {}
    video_id = yt.get("video_id", "")
    if not video_id and meta.get("youtube_url"):
        import re

        m = re.search(r"(?:[?&]v=|youtu\.be/)([^&?#]+)", meta["youtube_url"])
        if m:
            video_id = m.group(1)
    if not video_id:
        print(f"skip {upload_path.name}: no video_id", file=sys.stderr)
        return False

    tags = yt.get("tags", [])
    if isinstance(tags, str):
        tags = [t.strip() for t in tags.split(",") if t.strip()]

    title = yt.get("title", "")
    description = yt.get("description", "")
    category_id = str(yt.get("categoryId", "22"))

    print(f"Update   : {meta.get('base_name', upload_path.stem)}")
    print(f"Video ID : {video_id}")
    print(f"Title    : {title}")
    if dry_run:
        print("Dry run — no API call.")
        return True

    youtube = youtube_mod.get_youtube_service()
    try:
        youtube.videos().update(
            part="snippet",
            body={
                "id": video_id,
                "snippet": {
                    "title": title,
                    "description": description,
                    "tags": tags,
                    "categoryId": category_id,
                },
            },
        ).execute()
        print(f"Updated  : https://www.youtube.com/watch?v={video_id}")
        return True
    except youtube_mod.HttpError as e:
        print(f"YouTube API error for {video_id}: {e}", file=sys.stderr)
        return False


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Update YouTube title/description/tags from *_UPLOAD.json",
    )
    parser.add_argument(
        "incident",
        nargs="?",
        help="DEB base name or path to *_UPLOAD.json (omit with --all)",
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="Update every incident with a video_id in evidence/processed/",
    )
    parser.add_argument("--dry-run", action="store_true", help="Print only; no API calls")
    args = parser.parse_args()

    if args.all:
        paths = iter_upload_jsons()
    elif args.incident:
        paths = [resolve_upload_json(args.incident)]
    else:
        parser.error("Provide an incident id or --all")

    youtube_mod = load_youtube_module()
    ok = 0
    for path in paths:
        if update_video(youtube_mod, path, args.dry_run):
            ok += 1
        print()
    print(f"Done: {ok}/{len(paths)} updated.")
    return 0 if ok == len(paths) else 1


if __name__ == "__main__":
    sys.exit(main())

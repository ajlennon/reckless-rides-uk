#!/usr/bin/env python3
"""Create YouTube playlist if missing and add all uploaded incidents to it."""
from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROCESSED = ROOT / "evidence" / "processed"
PLAYLIST_FILE = ROOT / "channel" / "upload-playlist.txt"


def load_youtube_module():
    spec = importlib.util.spec_from_file_location(
        "youtube_upload", ROOT / "scripts" / "youtube-upload.py"
    )
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def main() -> int:
    title = PLAYLIST_FILE.read_text().strip() if PLAYLIST_FILE.is_file() else ""
    if not title:
        print("No playlist title in channel/upload-playlist.txt", file=sys.stderr)
        return 1

    yt_mod = load_youtube_module()
    youtube = yt_mod.get_youtube_service()
    pid = yt_mod.ensure_playlist_id(youtube, title)
    print(f"Playlist: {title} ({pid})")

    added = 0
    for path in sorted(PROCESSED.glob("*_UPLOAD.json")):
        meta = json.loads(path.read_text())
        vid = (meta.get("youtube") or {}).get("video_id", "")
        if not vid:
            continue
        try:
            yt_mod.add_to_playlist(youtube, pid, vid)
            print(f"  added {path.name} -> {vid}")
            added += 1
        except Exception as exc:  # noqa: BLE001 — duplicate or API edge cases
            if "duplicate" in str(exc).lower() or "already" in str(exc).lower():
                print(f"  skip {path.name} (already in playlist)")
            else:
                print(f"  skip {path.name}: {exc}", file=sys.stderr)

    print(f"Done: {added} video(s) added to playlist.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

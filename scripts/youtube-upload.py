#!/usr/bin/env python3
"""Upload a DEB incident PUBLISH.mp4 to YouTube using *_UPLOAD.json metadata."""
from __future__ import annotations

import argparse
import csv
import json
import subprocess
import sys
from pathlib import Path

from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError
from googleapiclient.http import MediaFileUpload

SCOPES = [
    "https://www.googleapis.com/auth/youtube.upload",
    "https://www.googleapis.com/auth/youtube",
]
ROOT = Path(__file__).resolve().parent.parent
CONFIG_DIR = ROOT / "config"
CLIENT_SECRET = CONFIG_DIR / "client_secret.json"
TOKEN_FILE = CONFIG_DIR / "youtube-token.json"


def resolve_path(path_str: str) -> Path:
    p = Path(path_str)
    if not p.is_absolute():
        p = ROOT / p
    return p.resolve()


def get_youtube_service():
    creds = None
    if TOKEN_FILE.exists():
        creds = Credentials.from_authorized_user_file(str(TOKEN_FILE), SCOPES)
    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            creds.refresh(Request())
        else:
            if not CLIENT_SECRET.exists():
                print(
                    f"Missing {CLIENT_SECRET}\n"
                    "Copy config/client_secret.json.example and complete OAuth setup "
                    "(see README — YouTube upload automation).",
                    file=sys.stderr,
                )
                sys.exit(1)
            flow = InstalledAppFlow.from_client_secrets_file(str(CLIENT_SECRET), SCOPES)
            creds = flow.run_local_server(port=0)
        TOKEN_FILE.parent.mkdir(parents=True, exist_ok=True)
        TOKEN_FILE.write_text(creds.to_json())
    return build("youtube", "v3", credentials=creds)


def resolve_upload_json(arg: str) -> Path:
    p = Path(arg)
    if p.is_file():
        return p.resolve()
    base = arg.replace("_UPLOAD.json", "").replace(".json", "")
    candidate = ROOT / "evidence" / "processed" / f"{base}_UPLOAD.json"
    if candidate.is_file():
        return candidate
    raise FileNotFoundError(f"Upload metadata not found: {arg}")


def check_publish_format(video_path: Path) -> None:
    """Warn if video may be classified as a YouTube Short (not 16:9 landscape)."""
    try:
        out = subprocess.check_output(
            [
                "ffprobe", "-v", "error", "-select_streams", "v:0",
                "-show_entries", "stream=width,height", "-of", "csv=p=0",
                str(video_path),
            ],
            text=True,
        ).strip()
        w, h = (int(x) for x in out.split(","))
        if w < h or w < 1280:
            print(
                f"WARNING: {video_path.name} is {w}x{h} — may upload as a Short. "
                "Run ./scripts/republish-incident.sh to letterbox to 1920x1080.",
                file=sys.stderr,
            )
        elif (w, h) != (1920, 1080):
            print(f"Note: publish dimensions {w}x{h} (expected 1920x1080).", file=sys.stderr)
    except (subprocess.CalledProcessError, ValueError, FileNotFoundError):
        pass


def find_playlist_id(youtube, title: str) -> str | None:
    token = None
    while True:
        req = youtube.playlists().list(
            part="snippet",
            mine=True,
            maxResults=50,
            pageToken=token,
        )
        resp = req.execute()
        for item in resp.get("items", []):
            if item["snippet"]["title"] == title:
                return item["id"]
        token = resp.get("nextPageToken")
        if not token:
            return None


def add_to_playlist(youtube, playlist_id: str, video_id: str) -> None:
    youtube.playlistItems().insert(
        part="snippet",
        body={
            "snippet": {
                "playlistId": playlist_id,
                "resourceId": {"kind": "youtube#video", "videoId": video_id},
            }
        },
    ).execute()


def update_register(incident_id: str, base_name: str, youtube_url: str) -> None:
    register = ROOT / "register" / "incidents.csv"
    if register.exists():
        rows = []
        with register.open(newline="") as f:
            reader = csv.DictReader(f)
            fieldnames = reader.fieldnames or []
            for row in reader:
                if row.get("incident_id") == incident_id:
                    row["youtube_url"] = youtube_url
                rows.append(row)
        with register.open("w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(rows)

    manifest = ROOT / "register" / "manifests" / f"{base_name}_MANIFEST.json"
    if manifest.exists():
        data = json.loads(manifest.read_text())
        data["youtube_url"] = youtube_url
        manifest.write_text(json.dumps(data, indent=2) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser(description="Upload DEB incident to YouTube (private by default).")
    parser.add_argument(
        "incident",
        help="DEB base name or path to *_UPLOAD.json",
    )
    parser.add_argument(
        "--public",
        action="store_true",
        help="Upload as public (requires --confirm-public-bypass; not recommended)",
    )
    parser.add_argument(
        "--confirm-public-bypass",
        action="store_true",
        help="Acknowledge upload skips private review gate (use only if intentional)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print metadata only; do not upload",
    )
    args = parser.parse_args()

    if args.public and not args.confirm_public_bypass:
        print(
            "Refusing --public without --confirm-public-bypass.\n"
            "Workflow: upload private, review in YouTube Studio, then set public manually.",
            file=sys.stderr,
        )
        return 1

    upload_path = resolve_upload_json(args.incident)
    meta = json.loads(upload_path.read_text())
    yt = meta["youtube"]
    video_path = resolve_path(meta["files"]["upload_video"])
    if not video_path.is_file():
        print(f"Missing publish file: {video_path}", file=sys.stderr)
        return 1

    privacy = "public" if args.public else yt.get("privacy", "private")
    tags = yt.get("tags", [])
    if isinstance(tags, str):
        tags = [t.strip() for t in tags.split(",") if t.strip()]

    print(f"Incident : {meta.get('incident_id')} ({meta.get('base_name')})")
    print(f"Video    : {video_path}")
    print(f"Title    : {yt['title']}")
    print(f"Privacy  : {privacy}")

    check_publish_format(video_path)

    if args.dry_run:
        print("Dry run — no upload.")
        return 0

    youtube = get_youtube_service()
    body = {
        "snippet": {
            "title": yt["title"],
            "description": yt["description"],
            "tags": tags,
            "categoryId": str(yt.get("categoryId", "22")),
        },
        "status": {
            "privacyStatus": privacy,
            "selfDeclaredMadeForKids": bool(yt.get("madeForKids", False)),
        },
    }

    media = MediaFileUpload(str(video_path), chunksize=1024 * 1024, resumable=True)
    try:
        request = youtube.videos().insert(part="snippet,status", body=body, media_body=media)
        response = None
        while response is None:
            status, response = request.next_chunk()
            if status:
                pct = int(status.progress() * 100)
                print(f"Uploading… {pct}%")
        video_id = response["id"]
        url = f"https://www.youtube.com/watch?v={video_id}"
        print(f"Uploaded : {url}")

        playlist_name = yt.get("playlist")
        if playlist_name:
            pid = find_playlist_id(youtube, playlist_name)
            if pid:
                add_to_playlist(youtube, pid, video_id)
                print(f"Playlist : {playlist_name}")
            else:
                print(f"Playlist not found (create in Studio): {playlist_name}", file=sys.stderr)

        meta["youtube_url"] = url
        upload_path.write_text(json.dumps(meta, indent=2) + "\n")
        update_register(meta.get("incident_id", ""), meta.get("base_name", ""), url)

        if privacy == "private":
            print("\nReview in YouTube Studio (confirm under Videos, not Shorts), then set PUBLIC.")
        return 0
    except HttpError as e:
        print(f"YouTube API error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())

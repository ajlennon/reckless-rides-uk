#!/usr/bin/env python3
"""Build YouTube *_UPLOAD.json from channel/ branding templates."""
from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CHANNEL = ROOT / "channel"


def read_channel(name: str) -> str:
    path = CHANNEL / name
    return path.read_text().strip() if path.is_file() else ""


def read_tags() -> list[str]:
    return [t.strip() for t in read_channel("upload-tags.txt").split(",") if t.strip()]


def read_playlist() -> str:
    return read_channel("upload-playlist.txt") or "2026 Incidents"


def rel_path(path_str: str) -> str:
    p = Path(path_str).resolve()
    try:
        return str(p.relative_to(ROOT.resolve()))
    except ValueError:
        return str(p)


def lon_for_map(lat: str, lon: str, lon_tag: str) -> str:
    if lat and lon and lon_tag.endswith("W") and not str(lon).startswith("-"):
        return f"-{str(lon).lstrip('-')}"
    return lon


def build_title(utc_recorded: str, bst_recorded: str) -> str:
    tmpl = read_channel("upload-title-template.txt") or (
        "Reckless Rides UK — incident — {datetime}"
    )
    dt = bst_recorded or utc_recorded
    title = (
        tmpl.replace("{datetime}", dt)
        .replace("{utc}", utc_recorded)
        .replace("{bst}", bst_recorded or utc_recorded)
    )
    return title[:100]


def build_description(
    utc_recorded: str,
    bst_recorded: str,
    lat: str,
    lon: str,
    lat_tag: str,
    lon_tag: str,
    device: str,
    notes: str,
    police_ref: str = "[pending]",
) -> str:
    header = read_channel("video-description-header.txt")
    footer = read_channel("video-description-footer.txt")
    lon_m = lon_for_map(lat, lon, lon_tag)
    map_url = f"https://www.google.com/maps?q={lat},{lon_m}" if lat and lon_m else ""

    parts: list[str] = []
    if header:
        parts.append(header)
        parts.append("")
    parts.append(
        f"Recorded: {utc_recorded}" + (f" ({bst_recorded})" if bst_recorded else "")
    )
    if lat and lon:
        lat_disp = lat_tag[:-1] if lat_tag else lat
        lon_disp = lon_tag[:-1] if lon_tag else str(abs(float(lon)))
        hem_lat = lat_tag[-1] if lat_tag else "N"
        hem_lon = lon_tag[-1] if lon_tag else ("W" if float(lon) < 0 else "E")
        parts += [
            f"GPS: {lat_disp}°{hem_lat}, {lon_disp}°{hem_lon}",
            f"Map: {map_url}",
        ]
    if device:
        parts.append(f"Device: {device}")
    if notes:
        parts += ["", f"Notes: {notes}"]
    parts += ["", f"Police report: {police_ref or '[pending]'}"]
    controller_line = read_channel("data-controller-line.txt")
    ico_line = read_channel("ico-registration-line.txt")
    if controller_line:
        parts += ["", controller_line]
    if ico_line:
        parts.append(ico_line)
    if footer:
        parts += ["", footer]
    return "\n".join(parts)


def youtube_block_from_existing(existing: dict | None) -> dict:
    existing = existing or {}
    return {
        "title": existing.get("title", ""),
        "description": existing.get("description", ""),
        "tags": existing.get("tags", read_tags()),
        "privacy": existing.get("privacy", "private"),
        "privacy_after_review": existing.get("privacy_after_review", "public"),
        "categoryId": existing.get("categoryId", "22"),
        "madeForKids": existing.get("madeForKids", False),
        "playlist": existing.get("playlist", read_playlist()),
        "video_id": existing.get("video_id", ""),
        "url": existing.get("url", ""),
        "studio_url": existing.get("studio_url", ""),
        "uploaded_utc": existing.get("uploaded_utc", ""),
        "privacy_at_upload": existing.get("privacy_at_upload", ""),
    }


def merge_youtube_ids(yt_block: dict, youtube_url: str) -> dict:
    url = youtube_url or yt_block.get("url", "")
    if url and not yt_block.get("video_id"):
        match = re.search(r"(?:[?&]v=|youtu\.be/)([^&?#]+)", url)
        if match:
            yt_block["video_id"] = match.group(1)
            yt_block["url"] = url
    if yt_block.get("video_id") and not yt_block.get("studio_url"):
        yt_block["studio_url"] = (
            f"https://studio.youtube.com/video/{yt_block['video_id']}/edit"
        )
    return yt_block


def build_upload_json(
    incident_id: str,
    base_name: str,
    utc_recorded: str,
    bst_recorded: str,
    lat: str,
    lon: str,
    lat_tag: str,
    lon_tag: str,
    pub_path: str,
    proc_path: str,
    device: str,
    notes: str,
    police_ref: str = "",
    youtube_url: str = "",
    existing_youtube: dict | None = None,
) -> dict:
    lon_m = lon_for_map(lat, lon, lon_tag)
    map_url = (
        f"https://www.google.com/maps?q={lat},{lon_m}" if lat and lon_m else ""
    )
    title = build_title(utc_recorded, bst_recorded)
    description = build_description(
        utc_recorded,
        bst_recorded,
        lat,
        lon,
        lat_tag,
        lon_tag,
        device,
        notes,
        police_ref or "[pending]",
    )
    yt_block = youtube_block_from_existing(existing_youtube)
    yt_block["title"] = title
    yt_block["description"] = description
    yt_block["tags"] = read_tags()
    yt_block["playlist"] = read_playlist()
    yt_block = merge_youtube_ids(yt_block, youtube_url)

    return {
        "schema": "dangerous-ebikers-youtube-upload/v1",
        "incident_id": incident_id,
        "base_name": base_name,
        "files": {
            "upload_video": rel_path(pub_path),
            "processed_video": rel_path(proc_path),
        },
        "youtube": yt_block,
        "incident": {
            "recorded_utc": utc_recorded,
            "recorded_bst": bst_recorded,
            "latitude": lat,
            "longitude": lon_m if lat and lon else lon,
            "location_label": f"{lat_tag}_{lon_tag}" if lat_tag and lon_tag else "",
            "map_url": map_url,
            "device": device,
        },
        "police_ref": police_ref,
        "youtube_url": youtube_url or yt_block.get("url", ""),
        "notes": notes,
    }


def bst_from_utc(utc_recorded: str) -> str:
    if not utc_recorded:
        return ""
    try:
        return subprocess.check_output(
            [
                "bash",
                "-c",
                f"TZ=Europe/London date -d '{utc_recorded}' '+%Y-%m-%d %H:%M:%S %Z'",
            ],
            text=True,
        ).strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return ""


def from_manifest(manifest_path: Path) -> dict:
    manifest = json.loads(manifest_path.read_text())
    base = manifest["base_name"]
    loc = manifest.get("location", {})
    lat = loc.get("latitude", "")
    lon = loc.get("longitude", "")
    label = loc.get("label", "")
    lat_tag = label.split("_")[0] if label else ""
    lon_tag = label.split("_")[1] if label and "_" in label else ""
    utc_recorded = manifest.get("recorded_utc", "")
    bst_recorded = manifest.get("recorded_bst", "") or bst_from_utc(utc_recorded)
    notes = manifest.get("notes", "")
    pub_path = manifest["files"]["publish"]["path"]
    proc_path = manifest["files"]["processed"]["path"]
    device = manifest.get("source_device", {}).get("model", "")
    yt_block = manifest.get("youtube") or {}
    youtube_url = manifest.get("youtube_url", "") or yt_block.get("url", "")

    existing_upload = {}
    upload_path = ROOT / "evidence" / "processed" / f"{base}_UPLOAD.json"
    if upload_path.is_file():
        existing_upload = json.loads(upload_path.read_text()).get("youtube", {})

    merged_existing = {**existing_upload, **yt_block}

    return build_upload_json(
        manifest["incident_id"],
        base,
        utc_recorded,
        bst_recorded,
        lat,
        lon,
        lat_tag,
        lon_tag,
        pub_path,
        proc_path,
        device,
        notes,
        manifest.get("police_ref", ""),
        youtube_url,
        merged_existing,
    )


def main() -> None:
    if len(sys.argv) < 2:
        print(
            "Usage: upload_metadata.py from-manifest <MANIFEST.json>\n"
            "       upload_metadata.py write <UPLOAD.json> <args...>",
            file=sys.stderr,
        )
        sys.exit(1)

    cmd = sys.argv[1]
    if cmd == "from-manifest":
        manifest_path = Path(sys.argv[2]).resolve()
        upload = from_manifest(manifest_path)
        base = upload["base_name"]
        out = ROOT / "evidence" / "processed" / f"{base}_UPLOAD.json"
        out.write_text(json.dumps(upload, indent=2) + "\n")
        print(f"Wrote {out}")
        return

    if cmd == "write":
        (
            upload_path,
            incident_id,
            base_name,
            utc_recorded,
            bst_recorded,
            lat,
            lon,
            lat_tag,
            lon_tag,
            pub_path,
            proc_path,
            device,
            notes,
        ) = sys.argv[2:]
        upload = build_upload_json(
            incident_id,
            base_name,
            utc_recorded,
            bst_recorded,
            lat,
            lon,
            lat_tag,
            lon_tag,
            pub_path,
            proc_path,
            device,
            notes,
        )
        Path(upload_path).write_text(json.dumps(upload, indent=2) + "\n")
        return

    print(f"Unknown command: {cmd}", file=sys.stderr)
    sys.exit(1)


if __name__ == "__main__":
    main()

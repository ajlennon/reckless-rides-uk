# Dangerous eBikers — evidence workspace

Private workspace for ingesting Meta glasses clips, anonymising for YouTube, and keeping controlled originals for police handover.

**YouTube:** [@Dangerous-eBikers](https://www.youtube.com/@Dangerous-eBikers)

## Layout

```
dangerous-ebikers/
  branding/              Channel art and watermark (safe to keep in git)
  channel/               Copy-paste text for YouTube Studio
  evidence/
    originals/           Full metadata, identifiable faces — POLICE ONLY
    processed/           Face-blurred review copies + *_UPLOAD.json metadata
    publish/             Metadata-stripped — upload these to YouTube
    export/              Optional zip bundles for 101 handover
  register/
    incidents.csv        Master log (gitignored — copy from .example on first run)
    manifests/           Per-incident JSON with SHA-256 hashes
  scripts/
    ingest-incident.sh              Ingest pipeline
    regenerate-upload-metadata.sh   Rebuild *_UPLOAD.json from manifest
```

## Filename convention

Each incident gets a sequential ID and consistent prefix:

```
DEB-{UTC}_{LAT}_{LON}_{NNN}_{ROLE}.{ext}
```

Example:

```
DEB-20260623T080303Z_53.4092N_2.9778W_001_ORIGINAL.mov   ← police evidence
DEB-20260623T080303Z_53.4092N_2.9778W_001_PROCESSED.mp4  ← review (blurred)
DEB-20260623T080303Z_53.4092N_2.9778W_001_UPLOAD.json   ← YouTube title/description/tags
DEB-20260623T080303Z_53.4092N_2.9778W_001_PUBLISH.mp4   ← YouTube upload
DEB-20260623T080303Z_53.4092N_2.9778W_001_MANIFEST.json ← register/manifests/
```

- **DEB** — dossier prefix for handover
- **UTC** — `com.apple.quicktime.creationdate` from glasses
- **LAT/LON** — from ISO6709 GPS tag
- **NNN** — incident sequence (`001`, `002`, …) from `register/incidents.csv`
- **ROLE** — `ORIGINAL` | `PROCESSED` | `PUBLISH` | `UPLOAD` (JSON metadata, lives with processed)

## Prerequisites

```bash
pip3 install --user deface
# ffmpeg/ffprobe already on system
```

## Ingest a new clip

Copy or transfer from glasses/LocalSend, then:

```bash
./scripts/ingest-incident.sh /path/to/video.MOV "optional notes"
```

This will:

1. Copy the source to `evidence/originals/` with the controlled name
2. Blur faces (`deface`) → `evidence/processed/`
3. Strip metadata (`ffmpeg -map_metadata -1`) → `evidence/publish/`
4. Write `evidence/processed/*_UPLOAD.json` (YouTube title, description, tags)
5. Write `register/manifests/*_MANIFEST.json` (SHA-256 per file)
6. Append a row to `register/incidents.csv`

**Upload only `*_PUBLISH.mp4` to YouTube (unlisted).** Use the paired `*_UPLOAD.json` in `evidence/processed/` for title, description, and tags.  
**Give police `*_ORIGINAL` + manifest** if you report via 101.

Regenerate upload metadata after editing channel templates:

```bash
./scripts/regenerate-upload-metadata.sh DEB-20260623T080303Z_53.4092N_2.9778W_001
```

After upload, edit `incidents.csv` and the manifest JSON to add `police_ref` and `youtube_url`.

## Police handover

For each reported incident, provide:

- `evidence/originals/DEB-…_ORIGINAL.mov`
- `register/manifests/DEB-…_MANIFEST.json`
- `register/incidents.csv` (or a printout of the matching row)

Manifest includes SHA-256 hashes so integrity can be checked.

Optional export:

```bash
INC=DEB-20260623T080303Z_53.4092N_002.9778W_001
zip -j "evidence/export/${INC}_police_bundle.zip" \
  "evidence/originals/${INC}_ORIGINAL.mov" \
  "register/manifests/${INC}_MANIFEST.json"
```

## Channel copy

Studio text lives in `channel/` — `description.txt`, `guidelines.txt`, `upload-tags.txt`, etc.

## Privacy & UK compliance

Evidence media and the incident register are **gitignored**. Do not commit originals or publish copies.

**Legal & GDPR approach:** see [`UK-COMPLIANCE.md`](UK-COMPLIANCE.md) — living document covering data protection, publication risks, retention, and per-incident checklist. Review every six months or when practices change.

# Dangerous eBikers

Public documentation, compliance standards, and ingest tooling for the [@Dangerous-eBikers](https://www.youtube.com/@Dangerous-eBikers) YouTube channel — timestamped evidence of illegal pavement e-bike riding in the UK.

**Video evidence is never stored in this repository** (see `.gitignore`).

## Compliance & standards (public)

**Link this section from your YouTube channel About box.**

| Document | Audience | URL |
|----------|----------|-----|
| **[Compliance & standards statement](COMPLIANCE-STATEMENT.md)** | Complainants, YouTube, police | `https://github.com/ajlennon/dangerous-ebikers/blob/main/COMPLIANCE-STATEMENT.md` |
| [UK compliance record](UK-COMPLIANCE.md) | Full GDPR/legal operating detail | `https://github.com/ajlennon/dangerous-ebikers/blob/main/UK-COMPLIANCE.md` |
| [Publication workflow](#publication-workflow-privacy--compliance) | How clips are anonymised before going public | This README |

**Privacy / takedown / feedback:** [ajlennon@gmail.com](mailto:ajlennon@gmail.com)

We welcome constructive feedback to ensure we meet all legal and platform obligations.

## Publication workflow (privacy & compliance)

Mandatory path from capture to upload. **Never skip the manual gates.** Full legal context: [`UK-COMPLIANCE.md`](UK-COMPLIANCE.md).

```mermaid
flowchart TD
    subgraph capture ["1 · Capture"]
        A["Record in public<br/>(Ray-Ban Meta glasses)"]
        B["Transfer to PC<br/>(LocalSend / import)"]
    end

    subgraph ingest ["2 · ingest-incident.sh"]
        C["Assign DEB incident ID<br/>from GPS + timestamp"]
        D["ORIGINAL.mov · evidence/originals/<br/>FULL metadata + faces"]
        E["PROCESSED.mp4 · deface face blur"]
        F["PUBLISH.mp4 · 16:9 letterbox<br/>metadata stripped"]
        G["UPLOAD.json · title / description / tags"]
        H["MANIFEST.json + incidents.csv<br/>SHA-256 chain of custody"]
    end

    subgraph gates ["3 · Manual compliance gates"]
        I{"Faces adequately<br/>blurred?"}
        J{"Children visible or<br/>anonymisation failed?"}
        K{"Title & description<br/>factual · no names?"}
        Q["DO NOT PUBLISH<br/>re-blur · mute · or withhold"]
    end

    subgraph publish ["4 · YouTube"]
        L["Upload PUBLISH.mp4<br/>PRIVATE + privacy footer"]
        M["YouTube PRIVATE<br/>awaiting your review"]
        S{"Final review<br/>on YouTube?"}
        T["Set PUBLIC manually<br/>in YouTube Studio"]
        U["YouTube PUBLIC"]
    end

    subgraph police ["Police only (never YouTube)"]
        N["101 report<br/>ORIGINAL + manifest"]
        O["evidence/export/<br/>optional zip bundle"]
    end

    subgraph ongoing ["5 · Ongoing obligations"]
        P["Privacy complaint / SAR / objection"]
        R["Take down YouTube clip<br/>delete or retain originals per policy"]
    end

    A --> B --> C
    C --> D
    C --> E --> F
    C --> G
    C --> H
    E --> I
    I -->|No| Q
    I -->|Yes| J
    J -->|Yes| Q
    J -->|No| K
    K -->|No| Q
    K -->|Yes| L --> M
    M --> S
    S -->|Fail| R
    S -->|Pass| T --> U
    D -.->|optional| N
    N -.-> O
    U --> P --> R

    style D fill:#2d3748,stroke:#e53e3e,color:#fff
    style Q fill:#742a2a,stroke:#e53e3e,color:#fff
    style M fill:#4a5568,stroke:#a0aec0,color:#fff
    style U fill:#1a365d,stroke:#63b3ed,color:#fff
    style N fill:#22543d,stroke:#68d391,color:#fff
```

| Stage | Privacy / legal control |
|-------|-------------------------|
| **ORIGINAL** | Never uploaded; gitignored; identifiable data retained only for police / defence |
| **PROCESSED** | Face blur (`deface`); human review before any publish decision |
| **PUBLISH** | No embedded GPS/device metadata; **1920×1080 letterbox**; only this file goes to YouTube |
| **UPLOAD.json** | Factual text from templates; default **`private`**; set **`public`** in Studio after review |
| **MANIFEST** | Integrity hashes; documents what was shared with police |
| **Gates** | See [UK-COMPLIANCE.md §12](UK-COMPLIANCE.md#12-per-incident-checklist) checklist |
| **Complaints** | See [UK-COMPLIANCE.md §9](UK-COMPLIANCE.md#9-individual-rights--procedure) |

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
    ingest-incident.sh              Full ingest pipeline
    republish-incident.sh           Re-letterbox + metadata (fix Shorts / wrong aspect)
    regenerate-upload-metadata.sh   Rebuild *_UPLOAD.json from manifest
    upload-incident.sh              Upload *_PUBLISH.mp4 via YouTube API
    youtube-upload.py               Upload implementation
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
pip3 install --user -r requirements-youtube.txt   # for automated YouTube upload
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
3. Strip metadata and **letterbox to 16:9** (1920×1080) → `evidence/publish/` — avoids YouTube Shorts classification
4. Write `evidence/processed/*_UPLOAD.json` (YouTube title, description, tags)
5. Write `register/manifests/*_MANIFEST.json` (SHA-256 per file)
6. Append a row to `register/incidents.csv`

**Upload `*_PUBLISH.mp4` to YouTube as `private`.** After review on YouTube, set **`public`** manually in Studio.  
**Give police `*_ORIGINAL` + manifest** if you report via 101.

### YouTube upload (automated)

**One-time setup** (Google Cloud):

1. [Google Cloud Console](https://console.cloud.google.com/) → create project → enable **YouTube Data API v3**
2. **OAuth consent screen** → External → add scopes `youtube.upload` and `youtube` → add your Google account as **test user**
3. **Credentials** → Create **OAuth client ID** → **Desktop app** → download JSON
4. Save as `config/client_secret.json` (see `config/client_secret.json.example`)
5. First upload opens a browser to authorise; token saved to `config/youtube-token.json` (gitignored)

Create playlist **`2026 Incidents`** in YouTube Studio once (script adds videos to it by name).

**After ingest + review of `*_PROCESSED.mp4`:**

```bash
# Dry run
./scripts/upload-incident.sh DEB-20260623T080303Z_53.4092N_2.9778W_001 --dry-run

# Upload private (default)
./scripts/upload-incident.sh DEB-20260623T080303Z_53.4092N_2.9778W_001
```

Updates `*_UPLOAD.json`, `register/incidents.csv`, and manifest with the YouTube URL. Default quota ~6 uploads/day.

**Manual alternative:** YouTube Studio → upload `*_PUBLISH.mp4` using text from `*_UPLOAD.json`.

Regenerate upload metadata after editing channel templates:

```bash
./scripts/regenerate-upload-metadata.sh DEB-20260623T080303Z_53.4092N_2.9778W_001
```

### Fix Shorts / wrong aspect ratio

Portrait clips from the glasses may be classified as **YouTube Shorts** (limited description visibility). The ingest pipeline letterboxes to **1920×1080**. If you uploaded before that fix:

1. Delete the Short in YouTube Studio (or leave private and ignore)
2. Rebuild publish copy and metadata:

```bash
./scripts/republish-incident.sh DEB-20260623T080303Z_53.4092N_2.9778W_001
./scripts/upload-incident.sh DEB-20260623T080303Z_53.4092N_2.9778W_001
```

3. Confirm the new upload appears under **Content → Videos**, not **Shorts**

After upload, add `police_ref` to `incidents.csv` and the manifest when reported via 101.

## YouTube & legal compliance (summary)

This project is designed to stay within **UK GDPR** and **YouTube Community Guidelines**. Key controls:

| Area | What we do |
|------|------------|
| **GDPR** | Legitimate interests + minimisation; face blur; private-first upload; takedown process |
| **Harassment** | No naming, no vigilante language, no repeated targeting of one rider |
| **Privacy** | Originals never published; metadata stripped; contact on every video |
| **YouTube CGT** | Factual titles; moderate comments; engage with platform notices |
| **Shorts risk** | 16:9 letterbox so descriptions and compliance footer are searchable |

Full detail: [`COMPLIANCE-STATEMENT.md`](COMPLIANCE-STATEMENT.md) (external) and [`UK-COMPLIANCE.md`](UK-COMPLIANCE.md) (operating record).

**Before scaling:** complete ICO registration self-assessment and sign Appendix A LIA in `UK-COMPLIANCE.md`.

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

**Legal & GDPR approach:** [`UK-COMPLIANCE.md`](UK-COMPLIANCE.md) — public operating record (review every six months).

**External statement** (complainants, YouTube, police): [`COMPLIANCE-STATEMENT.md`](COMPLIANCE-STATEMENT.md) — share as PDF, link, or paste into correspondence to demonstrate standards and openness to feedback.

# FileLister — Roadmap & Status

Single source of truth for what's built and what's planned. Update this file as
features land or plans change.

Status legend: ✅ Done · 🚧 In progress / uncommitted · 📋 Planned

Latest version: **v1.18.0** (committed & pushed to `origin/main`). Latest GitHub *release*: **v1.13.0** (v1.14–v1.18 are tagged commits awaiting releases).

---

## Core (Local)

| Feature | Status | Notes |
|---|---|---|
| Files mode — duplicate file detection | ✅ | SHA-256 content match (v1.0) |
| Filters, sorting, Quick Look preview | ✅ | v1.0 |
| Storage statistics (status bar) | ✅ | v1.0 |
| Mandatory binary (byte) verification before deletion | ✅ | v1.0 safety check |
| Detailed file-reading progress monitoring | ✅ | v1.0 |
| Icons, stats, dynamic list cleanup, minimalist menu | ✅ | v1.0 |
| Auto-scan, Ignore flag, operation log, larger empty states | ✅ | v1.1.0 |
| Files options — Deep Scan, Media-only, No Hidden, Symlinks | ✅ | |
| Confidence scoring | ✅ | v1.5.0, refined v1.6.0 |
| Symlink duplicate detection | ✅ | v1.4.0 |
| Folders mode — duplicate folder clusters | ✅ | v1.5.0; union-find on file hashes, match-ratio threshold |
| Folders — interactive merge, safe merge, "Copy to new folder" | ✅ | v1.8.0 |
| Folders — Review One-by-One, Merge All, rename kept folder | ✅ | |
| Folders — collision-aware file renaming | ✅ | v1.7.0 |
| Diff preview UX | ✅ | v1.5.0, polished v1.6.0 |
| Photos mode — similar-photo detection, best-copy, export | ✅ | v1.9.0; perceptual hashing + EXIF corroboration |
| 3-mode shell (Files · Folders · Photos) | ✅ | v1.8.1 |
| Multi-folder scanning (across / within scope) | ✅ | v1.8.0 |
| Merge / operation logging (JSON + HTML + PDF) | ✅ | v1.8.0; PDF added v1.9.1 |
| Undo / Restore last operation | ✅ | v1.9.1 |
| In-app Operation History (logs viewer) | ✅ | v1.10.0 |
| Help menu + window with annotated screenshots | ✅ | v1.0 / v1.3.0 |
| App icon, custom title-bar identity | ✅ | v1.3.0 |

### Licensing

| Feature | Status | Notes |
|---|---|---|
| License key system with trial limitations | ✅ | v1.0 |
| Pro licensing, deactivation | ✅ | v1.0 "Phase 2" |
| Secure email-bound licensing algorithm | ✅ | v1.2-era rework (CryptoKit) |

---

## OneDrive (Cloud)

Being rolled out per mode, one bit at a time. `quickXorHash` plays the role of
SHA-256 for cloud content matching.

| Feature | Status | Notes |
|---|---|---|
| Connect / sign out, account display | ✅ | v1.11.0 |
| Folder picker (browse + select OneDrive folders) | ✅ | v1.12.0 |
| Scan limits (max files / max GB) in Settings | ✅ | |
| **Files** — cloud duplicate detection | ✅ | v1.11.0 |
| **Files** — Quick Look preview w/ download progress | ✅ | v1.12.0 |
| **Files** — per-file / per-group / delete-all to recycle bin | ✅ | v1.12.0; confirmation sheets added v1.18.0 |
| **Files** — operation logging + reveal log | ✅ | |
| **Folders** — duplicate folder cluster detection | ✅ | v1.13.0; reuses local union-find on crawled files |
| **Folders** — in-place merge (move uniques → keep, recycle others, rename, review, merge-all, log dropdown) | ✅ | v1.13.0; verified against a real account. Graph `PATCH parentReference` / `DELETE` / `PATCH name` |
| **Folders** — "Copy to new folder" (safe merge, cloud→cloud) | ✅ | v1.17.0; [#3](https://github.com/luisdanielsilva/FileLister/issues/3). Async Graph `copy` + monitor poll; pick/create destination ("New Folder") + copy-mode confirmation sheets; originals untouched |
| **Folders** — safe merge to a **local** folder (download/export) | 📋 | [#3](https://github.com/luisdanielsilva/FileLister/issues/3); deferred — needs keep-folder inventory + bulk-download UI |
| **Folders** — delete redundant folders only | 📋 | Lower-risk variant; may be obsoleted by the in-place merge |
| **Photos** — cloud similar-photo detection | 📋 | [#4](https://github.com/luisdanielsilva/FileLister/issues/4). Not started; needs image/thumbnail download + perceptual hashing |

### Remote provider abstraction ([#6](https://github.com/luisdanielsilva/FileLister/issues/6) — Local vs Remote)

Generalizing the OneDrive code into a provider-agnostic **Remote** layer so other backends drop in without touching scan/merge logic.

| Phase | Status | Notes |
|---|---|---|
| Phase 1 — `RemoteProvider` protocol + `RemoteEngine`; OneDrive conforms; mode bar reads "Local / Remote" | ✅ | v1.17.0. Auth/identity extracted; listing/crawl/mutations still inline (pulled up in Phase 3) |
| Phase 2 — multi-connection mgmt (Keychain, picker, Settings tab, default, ⌥-click) | ✅ | v1.18.0. [#7](https://github.com/luisdanielsilva/FileLister/issues/7). RemoteConnectionStore; token purge on quit; provider label in logs |
| Phase 3 — Google Drive provider (proves the abstraction) | 📋 | [#8](https://github.com/luisdanielsilva/FileLister/issues/8) |
| Phase 4 — FTP/FTPS provider | 📋 | [#9](https://github.com/luisdanielsilva/FileLister/issues/9) |
| Protect locally-synced files from remote deletion | 📋 | [#13](https://github.com/luisdanielsilva/FileLister/issues/13); data-loss safeguard |

---

## Build / Tooling

| Item | Status | Notes |
|---|---|---|
| `build_release.sh` — clean, build Release, launch app | ✅ | Version bump / commit / GitHub release done manually as needed |

---

## Release History (chronological)

| Version | Highlights |
|---|---|
| v1.0 | Duplicate file detection (SHA-256), filters, sorting, Quick Look; storage stats; mandatory binary verification before deletion; file-reading progress; license key + trial; Pro licensing & deactivation; custom title bar; Help window |
| v1.1.0 | Auto-scan, Ignore flag, operation log, UI optimization, larger empty states |
| v1.2 (era) | Secure email-bound licensing algorithm (CryptoKit) |
| v1.3.0 | App icon, auto-scan polish, Help menu with annotated screenshots |
| v1.4.0 | Symlink duplicate detection |
| v1.5.0 | Folder duplicate detection, confidence scoring, diff preview |
| v1.6.0 | Diff preview UX polish & confidence scoring refinements |
| v1.7.0 | Collision-aware file renaming & folder merge UX refinements |
| v1.8.0 | Multi-folder scanning, interactive & safe merge, folder clustering, merge logging |
| v1.8.1 | 3-mode shell (Files · Folders · Photos) |
| v1.9.0 | Photos mode — similar-photo detection, best-copy, export + full operation logging |
| v1.9.1 | Undo/Restore last operation + PDF log output |
| v1.10.0 | In-app Operation History (logs viewer) |
| v1.11.0 | OneDrive (Files): connect + cloud duplicate detection & delete |
| v1.12.0 | OneDrive folder selection, cloud preview/progress, per-file delete; Help & entitlement fixes |
| v1.13.0 | OneDrive Folders: duplicate cluster detection + in-place merge (verified) |
| v1.14.0 | Two-row Options/Actions toolbar (prevents control crowding) |
| v1.15.0 | Collapsible folder clusters + merge-composition pie chart |
| v1.16.0 | Independent Files/Folders scanner engines, per-mode folder selection & state, Clean All pie |
| v1.17.0 | Remote provider protocol (Phase 1 of #6); OneDrive safe merge "Copy to new folder" (cloud→cloud) + create-destination + confirmation sheets |
| v1.18.0 | Multi-connection remote management (#7 / Phase 2 of #6): RemoteConnectionStore, per-connection Keychain slots, connection picker (⌥-click), Settings → Connections tab, token purge on quit; Files mode delete confirmation sheets |

> Note: the web portal / marketing site and licensing tools shared this repo early
> on, then were split into separate repositories (mid-April 2026). Their commits are
> omitted here; this roadmap tracks the macOS app only.

---

## Notes & Conventions

- OneDrive rollout order: **Files → Folders → Photos**, each shipped in small steps.
- Folder merge mirrors local semantics exactly, including recycling an "other"
  folder wholesale (match-ratio threshold is the safeguard).
- Destructive cloud operations send items to the **OneDrive recycle bin** (not hard delete).
- "Copy to new folder" (safe merge) is **non-destructive**: it copies the merged result into a chosen folder and leaves all originals in place.

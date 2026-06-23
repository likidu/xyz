# Downloads — Account entry + Downloads Manager (real registry)

Date: 2026-06-23
Design source: Claude Design project `Xyz for Symbian Belle` —
`screens-account.jsx`, `screens-download.jsx`, `belle.css` (`小宇宙 Belle.html`).

## Goal

1. Add a **Downloads** nav row to the Account page (`HomePage.qml`): icon tile +
   "Downloads" + a live subtitle ("N episodes · NNN MB on device") + right chevron.
2. Add a **Downloads Manager** page (`DownloadsPage.qml`): a phone-memory storage
   meter, the in-flight download (if any), and the list of on-device episodes.
3. Back both with **real data**: a new C++ `DownloadRegistry` that persists per-episode
   download metadata, tracks the active download via `PlayerController`, and exposes the
   list + storage figures to QML.

## Non-goals

- No concurrent downloads — `PlayerController`/`EpisodeDownloader` fetch one at a time.
- No background/queued download service; an in-flight download is the one the player owns.
- Cached audio left over from before this feature (no stored metadata) is **not**
  retro-adopted into the list. The registry is the source of truth from first run forward.
- No new translations runtime; strings use `qsTr` with English sources, matching the
  existing pages (the design's bilingual `L({en,zh})` maps to `qsTr`).

## Architecture

### New unit: `DownloadRegistry` (QML context property `downloads`)

Single responsibility: **own the set of downloaded episodes and the storage figures the
Downloads UI renders.** Constructed in `main.cpp` as `DownloadRegistry downloads(&storage, &player)`
and exposed via `setContextProperty("downloads", &downloads)`.

- **Persistence.** A JSON array under StorageManager key `"downloads.index"`, (de)serialized
  with the vendored `QJson::Serializer`/`QJson::Parser` (Qt 4 has no `QJsonDocument`; same
  path `XyzApiClient` uses). Loaded once in the constructor.
- **Entry shape** (one `QVariantMap` per episode):
  `eid, title, show, durationText, coverUrl, sizeText, sizeBytes, audioUrl, addedAt, done`.
- **Active-download tracking.** Connects to `player` signals:
  - `stateChanged` → on transition to **Idle/Error** while an entry is pending (`m_activeEid`
    set): if `player.isDownloaded(activeEid)` mark that entry `done`, capture real
    `sizeBytes`/`sizeText`; otherwise (cancel/fail) drop the pending entry. Then clear
    `m_activeEid`, persist, recompute meter, emit `itemsChanged`.
  - `downloadDeleted` → `refresh()` (reconcile: prune entries whose file is gone).
  - Live per-item progress is **not** mirrored — the one active row binds directly to
    `player.downloadProgress` in QML (single in-flight download).

### Touch points on existing units (surgical)

- **`EpisodeDownloader`**: add public `QString storageDir()` returning the cached `audioDir()`
  (so the registry can locate the drive for the disk query). `cachedSizeBytes()` is already public.
- **`PlayerController`**: add two `Q_INVOKABLE` passthroughs that keep `EpisodeDownloader`
  encapsulated under its single owner:
  - `qint64 downloadedSizeBytes(const QString &eid)` → `m_downloader.cachedSizeBytes(eid)`
  - `QString downloadStorageDir()` → `m_downloader.storageDir()`
- **`EpisodePage.qml`**: at the existing `player.download(audioUrl, eid)` call site, add a
  sibling `downloads.note({...})` recording the metadata the page already holds (eid, title,
  show, durationText, coverUrl, audioSizeText, audioUrl). No change to the working
  download/play/delete state machine.
- **`HomePage.qml`**: add the Downloads nav row; emit a new `downloadsRequested` signal.
- **`AppWindow.qml`**: add `DownloadsPage { id: downloadsPage }`; on `HomePage.downloadsRequested`
  push it; on `DownloadsPage.episodeRequested(item)` open `episodePage` (reuses the existing
  play/delete flow — tapping a downloaded row opens its episode).
- **Build**: `Xyz.pro` gains `src/DownloadRegistry.{h,cpp}`, `qml/DownloadsPage.qml`,
  `gfx/icon-chevron.svg`; `symbian:LIBS += -lefsrv` for the volume query. `qml.qrc` gains the
  page and the icon.

### `DownloadRegistry` interface

```
Q_PROPERTY QVariantList items        // newest-first; keys above (+ done)
Q_PROPERTY int          count        // number of done (on-device) episodes
Q_PROPERTY QString      downloadsText // formatted sum of done sizes ("248 MB")
Q_PROPERTY qint64       diskTotalBytes
Q_PROPERTY qint64       diskFreeBytes
Q_PROPERTY qint64       downloadsBytes
  // all NOTIFY changed()

Q_INVOKABLE void note(const QVariantMap &meta)  // record/refresh as downloading
Q_INVOKABLE void remove(const QString &eid)     // player.deleteDownload(eid) + drop entry
Q_INVOKABLE void clearAll()                     // remove every entry's file + clear
Q_INVOKABLE void refresh()                      // reconcile + recompute meter
```

### Storage meter (real)

- `downloadsBytes` = Σ `sizeBytes` of `done` entries (reconciled against the filesystem in
  `refresh()` via `player.isDownloaded` / `downloadedSizeBytes`).
- `diskTotalBytes` / `diskFreeBytes`: native `RFs::Volume()` → `TVolumeInfo` (`iSize`/`iFree`)
  for the drive of `player.downloadStorageDir()`, guarded by `#ifdef Q_OS_SYMBIAN` exactly
  like `MemoryMonitor`'s HAL block. Off-device returns `0` and the QML meter degrades
  gracefully (shows the downloads figure, hides the GB total).
- Bar segments (QML): `seg-dl` = `downloadsBytes/diskTotalBytes`,
  `seg-os` = `(total-free-downloads)/total`, remainder = free. Legend: Downloads NNN MB ·
  Other · Free N.NN GB.

## DownloadsPage.qml layout (mirrors SubscriptionsPage)

`Page` (`hidesToolBar: true`) → `BelleHeader` (back + trash action) → `ListView` whose
`header` Component holds the storage-meter card, the optional active-download row, and the
"On device N" subhead; `delegate` renders each on-device row (cover image, 2-line title,
show · duration · size, check + dots). Bottom `BelleTabBar` (person active). Tapping a row →
`episodeRequested(item)`; tapping the active row's ✕ → `player.cancelDownload()`; header trash
→ confirm dialog → `downloads.clearAll()`.

QML-1.1 compliance: section split (active vs on-device) computed in a root-level
`recompute()` helper (no block bindings, no nested function decls); full-delegate `MouseArea`
for the row tap target (per the list-row-tap-target rule).

## Verification

- Builds clean for the simulator target.
- Run `Xyz.exe`; screenshot (a) the Account page showing the Downloads nav row with a live
  subtitle, (b) the Downloads page showing the meter + empty/seeded list. Because the
  registry persists via SQLite, a seeded `downloads.index` value (or a real download in the
  sim) exercises the list and meter.
- Record the native disk-query experiment in `docs/DEVICE_NOTES.md`.

## Risks

- `RFs::Volume` may report card vs phone drive depending on where `audioDir()` resolves;
  acceptable — we query the drive downloads actually live on.
- MMF file locks on delete are already handled by `PlayerController::deleteDownload`'s retry;
  the registry reuses it rather than calling `QFile::remove` directly.

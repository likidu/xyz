# Downloads Page Implementation Plan

> **For agentic workers:** Steps use checkbox (`- [ ]`) syntax for tracking. This
> project has **no unit-test harness** (Qt 4.7 / QML 1.1 / Symbian); the verification
> loop is **build the simulator target → run `Xyz.exe` → observe/screenshot**. "Run the
> test" steps below mean exactly that.

**Goal:** Add a Downloads entry to the Account page and a Downloads Manager page, backed
by a real `DownloadRegistry` that persists download metadata and reports storage usage.

**Architecture:** New `DownloadRegistry` C++ object (`downloads` context property) persists
a JSON list of downloaded episodes via StorageManager + qjson, watches `PlayerController`
to flip a pending entry to `done` on completion, and exposes the list + disk/downloads
figures to QML. The Downloads page mirrors `SubscriptionsPage` (Page + BelleHeader +
ListView + BelleTabBar). Tapping a row reuses the existing EpisodePage play/delete flow.

**Tech Stack:** Qt 4.7, QML 1.1, Symbian Components 1.1, vendored qjson, SQLite KV
(StorageManager), native `RFs`/`TVolumeInfo` for disk space.

## Global Constraints (verbatim from project rules)

- NEVER write the `position` property on a QML `Audio` element. Drive playback via `player`.
- Data-cage dirs lie about `exists()`/`mkpath()`; use I/O probes (already handled in
  `EpisodeDownloader`). Downloads live in a PUBLIC dir, not `/private/<uid>`.
- QML 1.1: no block expressions in property bindings; no named function declarations inside
  non-root elements (declare at Page root); no negative anchor margins.
- SVG icons: Symbian renders by `viewBox`; to resize, set width/height AND viewBox and wrap
  paths in `<g transform="scale(f)">`.
- Tappable ListView rows need ONE full-delegate `MouseArea` behind the content.
- Strings use `qsTr` with English sources (matches existing pages).
- After any audio/media/platform-API experiment, record it in `docs/DEVICE_NOTES.md`.

## File Structure

- Create `src/DownloadRegistry.h` / `.cpp` — the registry (persistence, active-tracking, meter).
- Modify `src/EpisodeDownloader.h` — add public `storageDir()`.
- Modify `src/PlayerController.h/.cpp` — add `downloadedSizeBytes()`, `downloadStorageDir()`.
- Modify `src/main.cpp` — construct + expose `downloads`.
- Modify `Xyz.pro` — sources, `-lefsrv`, new qml/icon in OTHER_FILES.
- Create `qml/DownloadsPage.qml` — the Downloads Manager screen.
- Create `qml/gfx/icon-chevron.svg` — right chevron for the nav row.
- Modify `qml/HomePage.qml` — Downloads nav row + `downloadsRequested` signal.
- Modify `qml/AppWindow.qml` — wire `downloadsPage` navigation.
- Modify `qml/EpisodePage.qml` — `downloads.note({...})` at the download call site.
- Modify `qml/qml.qrc` — register `DownloadsPage.qml` + `icon-chevron.svg`.

---

### Task 1: EpisodeDownloader + PlayerController accessors

**Files:**
- Modify: `src/EpisodeDownloader.h` (public `storageDir()`)
- Modify: `src/PlayerController.h`, `src/PlayerController.cpp`

**Produces:** `PlayerController::downloadedSizeBytes(const QString&) -> qint64`,
`PlayerController::downloadStorageDir() -> QString` (both `Q_INVOKABLE`).

- [ ] **Step 1:** In `EpisodeDownloader.h`, add a public method next to the cache queries:
  `QString storageDir() { return audioDir(); }`.
- [ ] **Step 2:** In `PlayerController.h`, after `deleteDownload`, declare:
  `Q_INVOKABLE qint64 downloadedSizeBytes(const QString &eid);`
  `Q_INVOKABLE QString downloadStorageDir();`
- [ ] **Step 3:** In `PlayerController.cpp`, implement:
  `qint64 PlayerController::downloadedSizeBytes(const QString &eid){return m_downloader.cachedSizeBytes(eid);}`
  `QString PlayerController::downloadStorageDir(){return m_downloader.storageDir();}`
- [ ] **Step 4 (verify):** Builds in Task 4's compile. Commit with Task 2.

---

### Task 2: DownloadRegistry C++ class

**Files:**
- Create: `src/DownloadRegistry.h`, `src/DownloadRegistry.cpp`
- Modify: `Xyz.pro` (add sources; `symbian:LIBS += -lefsrv`)

**Interfaces — Consumes:** `PlayerController` signals `stateChanged()`, `downloadDeleted()`;
methods `isDownloaded`, `downloadedSizeBytes`, `downloadStorageDir`, `deleteDownload`,
`currentEid()`, state enum via `downloadingState()`. `StorageManager::setValue/value`.
**Produces:** context property `downloads` with the interface in the spec.

- [ ] **Step 1:** Write `DownloadRegistry.h`:

```cpp
#ifndef DOWNLOADREGISTRY_H
#define DOWNLOADREGISTRY_H

#include <QtCore/QObject>
#include <QtCore/QString>
#include <QtCore/QVariantList>
#include <QtCore/QVariantMap>

class StorageManager;
class PlayerController;

// Source of truth for downloaded episodes + phone-memory figures shown on the
// Downloads page. Persists metadata as JSON in StorageManager; watches the player
// to flip the in-flight entry to done. One download at a time (player's limit).
class DownloadRegistry : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList items READ items NOTIFY itemsChanged)
    Q_PROPERTY(int count READ count NOTIFY itemsChanged)
    Q_PROPERTY(QString downloadsText READ downloadsText NOTIFY itemsChanged)
    Q_PROPERTY(qint64 diskTotalBytes READ diskTotalBytes NOTIFY meterChanged)
    Q_PROPERTY(qint64 diskFreeBytes READ diskFreeBytes NOTIFY meterChanged)
    Q_PROPERTY(qint64 downloadsBytes READ downloadsBytes NOTIFY meterChanged)

public:
    explicit DownloadRegistry(StorageManager *storage, PlayerController *player,
                              QObject *parent = 0);

    QVariantList items() const { return m_items; }
    int count() const;
    QString downloadsText() const;
    qint64 diskTotalBytes() const { return m_diskTotal; }
    qint64 diskFreeBytes() const { return m_diskFree; }
    qint64 downloadsBytes() const;

    Q_INVOKABLE void note(const QVariantMap &meta);
    Q_INVOKABLE void remove(const QString &eid);
    Q_INVOKABLE void clearAll();
    Q_INVOKABLE void refresh();

signals:
    void itemsChanged();
    void meterChanged();

private slots:
    void onPlayerStateChanged();
    void onDownloadDeleted();

private:
    void load();
    void save();
    int indexOf(const QString &eid) const;
    void recomputeMeter();
    static QString formatBytes(qint64 bytes);
    void queryDisk(qint64 &total, qint64 &free, const QString &dir);

    StorageManager *m_storage;
    PlayerController *m_player;
    QVariantList m_items;       // each: eid,title,show,durationText,coverUrl,
                                //       sizeText,sizeBytes,audioUrl,addedAt,done
    QString m_activeEid;        // entry currently downloading (done==false)
    qint64 m_diskTotal;
    qint64 m_diskFree;
};

#endif
```

- [ ] **Step 2:** Write `DownloadRegistry.cpp` — load/save via qjson, `note/remove/clearAll/refresh`,
  player wiring, and the native disk query. Key shapes:
  - constructor: `load(); connect(player, SIGNAL(stateChanged()), SLOT(onPlayerStateChanged())); connect(player, SIGNAL(downloadDeleted()), SLOT(onDownloadDeleted())); refresh();`
  - `note(meta)`: upsert by eid with `done=false, progress n/a`; set `m_activeEid=eid`;
    prepend if new; `save(); emit itemsChanged();`
  - `onPlayerStateChanged()`: if `m_activeEid` non-empty and player no longer downloading
    (`m_player->property("state").toInt() != m_player->downloadingState()`): if
    `m_player->isDownloaded(m_activeEid)` → set entry `done=true`,
    `sizeBytes=m_player->downloadedSizeBytes(eid)`, `sizeText=formatBytes(...)`; else erase
    the pending entry. Clear `m_activeEid`; `save(); recomputeMeter(); emit itemsChanged();`
  - `onDownloadDeleted()`: `refresh();`
  - `remove(eid)`: erase entry; `m_player->deleteDownload(eid)`; `save(); recomputeMeter(); emit itemsChanged();`
  - `clearAll()`: for each eid `m_player->deleteDownload(eid)`; clear list; save; recompute; emit.
  - `refresh()`: drop `done` entries where `!m_player->isDownloaded(eid)`; refresh each
    entry's sizeBytes from disk; `recomputeMeter(); emit itemsChanged();`
  - `recomputeMeter()`: `queryDisk(m_diskTotal, m_diskFree, m_player->downloadStorageDir()); emit meterChanged();`
  - `downloadsBytes()`: Σ sizeBytes of done entries.
  - `queryDisk`: `#ifdef Q_OS_SYMBIAN` RFs::Connect → parse drive from `dir` → `RFs::Volume(vol, driveNum)` → `total=vol.iSize; free=vol.iFree;` `#else` set 0/0.
- [ ] **Step 3:** In `Xyz.pro`: add `src/DownloadRegistry.cpp` to SOURCES, header to HEADERS,
  and `symbian:LIBS += -lefsrv`.
- [ ] **Step 4 (verify):** compiled in Task 4.

---

### Task 3: Wire registry into main.cpp

**Files:** Modify `src/main.cpp`.

- [ ] **Step 1:** `#include "DownloadRegistry.h"`.
- [ ] **Step 2:** After `XyzApiClient xyzApiClient(&storage);` add
  `DownloadRegistry downloads(&storage, &player);`
- [ ] **Step 3:** Add `view.rootContext()->setContextProperty("downloads", &downloads);`
- [ ] **Step 4 (verify):** compiled in Task 4.

---

### Task 4: First compile of the C++ layer

- [ ] **Step 1:** Build the simulator target (Task 6 build command). Fix compile errors
  (qjson Serializer/Parser signature, RFs includes `<f32file.h>`).
- [ ] **Step 2 (commit):** `git add src Xyz.pro && git commit -m "feat(downloads): DownloadRegistry backend + player accessors"`

---

### Task 5: Account nav row + chevron + EpisodePage hook

**Files:** Create `qml/gfx/icon-chevron.svg`; Modify `qml/HomePage.qml`, `qml/EpisodePage.qml`,
`qml/qml.qrc`, `Xyz.pro`, `qml/AppWindow.qml`.

- [ ] **Step 1:** Create `qml/gfx/icon-chevron.svg` (right chevron, viewBox trick):
```xml
<svg width="20" height="20" viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
<g transform="scale(0.8333)">
<path d="M9 5l7 7-7 7" stroke="#6e6e78" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>
</g>
</svg>
```
- [ ] **Step 2:** `qml.qrc`: add `<file>DownloadsPage.qml</file>` and `<file>gfx/icon-chevron.svg</file>`.
- [ ] **Step 3:** `HomePage.qml`: add `signal downloadsRequested`; insert the Downloads nav-row
  card (panel gradient, icon tile with `gfx/icon-download.svg`, title "Downloads", subtitle
  bound to `downloads.count`/`downloads.downloadsText`, `gfx/icon-chevron.svg`) above the
  Sign-out button; full-area `MouseArea` → `page.downloadsRequested()`.
- [ ] **Step 4:** `EpisodePage.qml`: at the Download `MouseArea.onClicked`, after
  `player.download(page.audioUrl, page.eid)` add a `downloads.note({...})` call with
  `eid,title,show,durationText,coverUrl,sizeText,audioUrl` from page properties.
- [ ] **Step 5:** `AppWindow.qml`: add `DownloadsPage { id: downloadsPage; onTabSelected: window.handleTab(index); onEpisodeRequested: { episodePage.openWith(item); pageStack.push(episodePage); } }`; on `HomePage.onDownloadsRequested: pageStack.push(downloadsPage)`.
- [ ] **Step 6:** `Xyz.pro`: add `qml/DownloadsPage.qml` to OTHER_FILES.

---

### Task 6: DownloadsPage.qml

**Files:** Create `qml/DownloadsPage.qml`.

- [ ] **Step 1:** Build the page: `Page{hidesToolBar:true; objectName:"DownloadsPage";
  signal episodeRequested(variant item); signal tabSelected(int index)}` with root-level
  helpers `recompute()` (split `downloads.items` into `activeItem`/`onDeviceItems`),
  `openItem(m)` (→ `episodeRequested({eid,coverUrl,title,durationText,whenText:""})`). On
  `PageStatus.Active`: `downloads.refresh(); recompute()`. `Connections{target:downloads;
  onItemsChanged: page.recompute()}`.
- [ ] **Step 2:** BelleHeader (title "Downloads", `actionIconSource:"gfx/icon-trash-white.svg"`,
  `onBackClicked: pageStack.pop()`, `onActionClicked: page.confirmingClear=true`).
- [ ] **Step 3:** ListView (model `page.onDeviceItems`) with `header` Component = storage meter
  card + active-download row (visible when `activeItem`) + "On device" subhead; row delegate
  = cover Image + 2-line title + show·duration·size + check + dots, full-delegate MouseArea
  → `page.openItem(modelData)`. Storage meter binds to `downloads.diskTotalBytes` etc.,
  degrading when total is 0.
- [ ] **Step 4:** Clear-all confirm dialog (reuse EpisodePage's scrim/dialog pattern) →
  `downloads.clearAll()`. Active row ✕ → `player.cancelDownload()`. Empty state text.
- [ ] **Step 5:** BelleTabBar `activeIndex:3`.
- [ ] **Step 6 (verify):** Build, run `Xyz.exe`, screenshot Account nav row + Downloads page.
- [ ] **Step 7 (commit):** `git add qml Xyz.pro && git commit -m "feat(downloads): Account nav row + Downloads Manager page"`

---

### Task 7: Verify flow + document

- [ ] **Step 1:** Seed a `downloads.index` value (or perform a real download in the sim) to
  exercise the list + meter; screenshot.
- [ ] **Step 2:** Add a dated entry to `docs/DEVICE_NOTES.md` for the native `RFs::Volume`
  disk-space query (and any simulator caveats).
- [ ] **Step 3 (commit):** `git add docs && git commit -m "docs: downloads verification + disk-query note"`

## Self-Review

- Spec coverage: Account row (T5), Downloads page (T6), registry/persistence/active-tracking
  (T2), disk meter (T2), player passthroughs (T1), navigation (T5), EpisodePage hook (T5),
  verification + DEVICE_NOTES (T7). ✓
- Type consistency: `downloadedSizeBytes`/`downloadStorageDir`/`storageDir` used identically
  in T1↔T2; `note/remove/clearAll/refresh` + `items/count/downloadsText/disk*Bytes` consistent
  T2↔T5↔T6. ✓

## Results (2026-06-23)

**Done and simulator-verified.** Built clean for the simulator (Debug). Ran `Xyz.exe`,
screenshotted both screens (seeded with two cached files + one in-flight entry):

- **Account page** — Downloads nav row renders with the icon tile, "Downloads", live
  subtitle "**2 episodes · 89.0 MB on device**" (registry summed the real 34 + 55 MB files),
  and the right chevron, sitting above Sign out / Self-test.
- **Downloads page** — "Phone memory **353.92 / 926.14 GB**" + segmented bar + legend
  ("Downloads 89.0 MB · Other · Free 572.21 GB"); a "Downloading" section with the active row
  (live `player.downloadProgress`) + cancel ✕; an "On device (2)" list with per-file sizes,
  show·duration, check + dots. Tapping a row opens its EpisodePage; header trash → confirm →
  clearAll.

**Bug found + fixed during verification:** QML `font.pixelSize` is an **int** — the design's
fractional sizes (11.5 / 12.5) threw "Invalid property assignment: int expected" and made the
whole page (and window) fail to load. Rounded to 12 / 13.

**Commits:** spec+plan → backend (`DownloadRegistry` + accessors) → QML (Account row +
Downloads page) → docs.

**Not yet on device:** the native `RFs::Volume` disk query is simulator-verified via the
`GetDiskFreeSpaceEx` fallback; the Symbian path runs only on the C7 — to be confirmed on the
next device run (see `docs/DEVICE_NOTES.md` 2026-06-23). Covers are blank in the seeded shots
only because the seed used empty `coverUrl`; real episodes carry cover art.

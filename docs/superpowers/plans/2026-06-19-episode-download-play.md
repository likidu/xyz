# Episode page — two-step Download → Play Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the episode page's inert "Play" CTA to a real two-step, offline-first flow — explicitly download an episode to device storage, then play the cached local file — with all visual states from the design.

**Architecture:** Add the audio URL to the data layer (`XyzApiClient` + mock). Extend the device-verified `EpisodeDownloader`/`PlayerController` with a download-only path + cache queries (the existing `playEpisode` is reused for the Play step and plays the cache instantly). Replace the inert `.ep-play` block in `EpisodePage.qml` with a state-driven CTA bound to `player`.

**Tech Stack:** Qt 4.7.4 / QML 1.1 / Symbian Components 1.1; C++ managers exposed via `setContextProperty` (`player`, `xyzApi`, `audioEngine`); RVCT (device) + MinGW (simulator); mock via `scripts/mock-content.ps1`.

**Verification reality:** No unit-test harness exists. Each task is verified by: (a) compiling the relevant target, (b) running the **simulator** build against the **mock** and reading `C:/Data/Xyz/logs/xyz.log`, and (c) on-device checks for anything audio (MMF is fragile; a reboot may be needed before trusting a failure — DEVICE_NOTES 2026-06-19). Build commands:
- Simulator: `pwsh scripts/build-simulator.ps1 -Config Debug` → launcher `build-simulator/debug/Xyz.run.ps1`.
- Device SIS: `pwsh scripts/build-sis.ps1 -Config Release -Arch armv5`.
- **rcc caveat:** editing only `.qml`/`.qrc`/svg does NOT retrigger rcc — delete `build-simulator/<cfg>/rcc/qrc_qml.cpp` + `obj/qrc_qml.o` (or build `-Clean`) before rebuilding.

---

## Task 1: Verify the audio enclosure field against the live API

**Goal:** Confirm the real field path for the audio URL (and whether inbox items carry it / any size field) before coding. Do not trust the mock (mock-diverges lesson).

**Files:** none (investigation).

- [ ] **Step 1: Extract the access token from the simulator DB**

The sim DB is at `%LOCALAPPDATA%\Nokia\QtSimulator\data\xyz.db`, `kv` table. Dump it with the bundled Python 2.6:

```bash
/c/Python26/python -c "import sqlite3,os; db=os.path.join(os.environ['LOCALAPPDATA'],'Nokia','QtSimulator','data','xyz.db'); c=sqlite3.connect(db); [print(k,'=',v[:40]) for (k,v) in c.execute('select key,value from kv')]"
```

Expected: rows including an access-token entry (e.g. `accessToken`/`x-jike-access-token`). Copy its value.

- [ ] **Step 2: Call the live inbox endpoint with the real token**

```bash
TOKEN='<paste-token>'
curl -s -X POST https://api.xiaoyuzhoufm.com/v1/inbox/list \
 -H 'User-Agent: Xiaoyuzhou/2.57.1 (build:1576; iOS 17.4.1)' \
 -H 'Market: AppStore' -H 'App-BuildNo: 1576' -H 'OS: ios' \
 -H 'Manufacturer: Apple' -H 'BundleID: app.podcast.cosmos' \
 -H 'Model: iPhone14,2' -H 'app-permissions: 4' -H 'App-Version: 2.57.1' \
 -H 'OS-Version: 17.4.1' -H 'Accept: */*' -H 'Content-Type: application/json' \
 -H 'Accept-Language: zh-Hans-CN;q=1.0' -H 'Timezone: Asia/Shanghai' \
 -H 'x-jike-device-id: 81ADBFD6-6921-482B-9AB9-A29E7CC7BB55' \
 -H "x-jike-access-token: $TOKEN" \
 -d '{"limit":"3"}' > /c/Users/liya/AppData/Local/Temp/xyz-inbox.json
/c/Python26/python -c "import json;d=json.load(open(r'C:/Users/liya/AppData/Local/Temp/xyz-inbox.json'));e=d['data'][0];print('keys:',sorted(e.keys()));print('enclosure:',e.get('enclosure'))"
```

Expected: HTTP 200 JSON; an episode object with an `enclosure` containing a `url` (typically an `.m4a`). Note whether `enclosure` is present on inbox items and whether it (or the episode) carries a byte size.

- [ ] **Step 3: Record the finding**

Confirm the field path used by Tasks 2–3. **Default assumption: `enclosure.url`.** If the real path differs (e.g. nested elsewhere), update the `enclosure`→`url` reads in Task 3's `shapeInboxItem`/`shapeEpisode` accordingly. No commit.

---

## Task 2: Add `enclosure` to the mock so the simulator can exercise the flow

**Files:**
- Modify: `scripts/mock-content.ps1`

The mock must (a) put an `enclosure.url` on inbox items + the episode object, and (b) actually serve a small audio file at that URL so the full download→play loop works in the simulator.

- [ ] **Step 1: Give inbox items + the episode an enclosure URL**

In `$inbox`, add `enclosure` to each episode item (point at the mock's own audio route, keyed by eid):

```powershell
  @{ type="EPISODE"; eid="e1"; title="Summit: The Weekly Orbit 6.6";
     description="Hosts: Luma / Vega / Pico / Radish. Headlines: State of Play drops a wave of new titles.";
     duration=7800; pubDate="2026-06-13T09:00:00.000Z"; playCount=143; commentCount=1;
     enclosure=@{ url="http://localhost:8099/audio/e1.wav" };
     image=@{ thumbnailUrl=$img; smallPicUrl=$img } },
  @{ type="EPISODE"; eid="e2"; title="183. Reading the Stars: Poems at the Edge of Night";
     description="Did the poets really turn away from the cold light of dusk? This episode makes the case.";
     duration=6900; pubDate="2026-06-12T18:00:00.000Z"; playCount=7941; commentCount=120;
     enclosure=@{ url="http://localhost:8099/audio/e2.wav" };
     image=@{ thumbnailUrl=$img; smallPicUrl=$img } }
```

In `$episode` (the `data` map), add the same:

```powershell
  duration=6900; pubDate="2026-06-12T18:00:00.000Z"; playCount=7941; commentCount=128;
  enclosure=@{ url="http://localhost:8099/audio/e2.wav" };
  image=@{ thumbnailUrl=$img; smallPicUrl=$img; middlePicUrl=$img };
```

- [ ] **Step 2: Serve a tiny WAV for `/audio/*` requests**

Add a generated PCM-silence WAV before the request loop:

```powershell
# Minimal 0.4s mono 8kHz 8-bit PCM WAV (~3.2KB) so the download+play loop is testable.
function New-SilenceWav {
  $sr=8000; $secs=0.4; $n=[int]($sr*$secs)
  $ms=New-Object System.IO.MemoryStream
  $bw=New-Object System.IO.BinaryWriter($ms)
  $bw.Write([Text.Encoding]::ASCII.GetBytes("RIFF")); $bw.Write([int](36+$n))
  $bw.Write([Text.Encoding]::ASCII.GetBytes("WAVE")); $bw.Write([Text.Encoding]::ASCII.GetBytes("fmt "))
  $bw.Write([int]16); $bw.Write([int16]1); $bw.Write([int16]1)
  $bw.Write([int]$sr); $bw.Write([int]$sr); $bw.Write([int16]1); $bw.Write([int16]8)
  $bw.Write([Text.Encoding]::ASCII.GetBytes("data")); $bw.Write([int]$n)
  for ($i=0;$i -lt $n;$i++){ $bw.Write([byte]128) }   # 128 = silence for 8-bit PCM
  $bw.Flush(); return $ms.ToArray()
}
$wav = New-SilenceWav
```

Then add an `/audio` branch in the handler (before the JSON branches), writing bytes with the audio content-type:

```powershell
  if ($path -like "*/audio/*") {
    $ctx.Response.ContentType = "audio/wav"
    $ctx.Response.OutputStream.Write($wav, 0, $wav.Length)
    $ctx.Response.Close()
    continue
  }
```

- [ ] **Step 3: Verify the mock serves both**

Run: `pwsh -File scripts/mock-content.ps1` (new shell), then:

```bash
curl -s http://localhost:8099/v1/inbox/list | /c/Python26/python -c "import sys,json;print(json.load(sys.stdin)['data'][0]['enclosure'])"
curl -s -o /c/Users/liya/AppData/Local/Temp/e2.wav http://localhost:8099/audio/e2.wav && ls -l /c/Users/liya/AppData/Local/Temp/e2.wav
```

Expected: prints `{'url': 'http://localhost:8099/audio/e2.wav'}` and a ~3.2 KB `e2.wav`.

- [ ] **Step 4: Commit**

```bash
git add scripts/mock-content.ps1
git commit -m "mock: serve episode enclosure URL + tiny WAV for download-to-play testing"
```

---

## Task 3: Parse `audioUrl` in `XyzApiClient`

**Files:**
- Modify: `src/XyzApiClient.cpp` (`shapeInboxItem` ~line 425, `shapeEpisode` ~line 482)

- [ ] **Step 1: Add `audioUrl` to `shapeInboxItem`**

Before `return out;` in `shapeInboxItem` (after the `commentCount` insert at ~line 423):

```cpp
    // Audio enclosure URL — drives the episode page's download/play CTA.
    out.insert(QString::fromLatin1("audioUrl"),
               item.value(QString::fromLatin1("enclosure")).toMap()
                   .value(QString::fromLatin1("url")).toString());
```

- [ ] **Step 2: Add `audioUrl` to `shapeEpisode`**

Before `return out;` in `shapeEpisode` (after the `commentCount` insert at ~line 482):

```cpp
    out.insert(QString::fromLatin1("audioUrl"),
               item.value(QString::fromLatin1("enclosure")).toMap()
                   .value(QString::fromLatin1("url")).toString());
```

- [ ] **Step 3: Build the simulator + confirm the URL is parsed**

Run:
```
pwsh scripts/build-simulator.ps1 -Config Debug
```
Expected: "Build succeeded". Then run mock + app (Task 7 Step 6 has the launch recipe) and confirm in `C:/Data/Xyz/logs/xyz.log` that opening an episode logs a non-empty `audioUrl` (the Download button appears — see Task 7). For an isolated check now, temporarily add under `XYZ_DEBUG` in `shapeInboxItem`:
```cpp
#ifdef XYZ_DEBUG
    qDebug() << "shapeInboxItem audioUrl:" << out.value(QString::fromLatin1("audioUrl")).toString();
#endif
```
Remove the temporary log before committing.

- [ ] **Step 4: Commit**

```bash
git add src/XyzApiClient.cpp
git commit -m "feat: expose audioUrl (enclosure.url) from XyzApiClient shapers"
```

---

## Task 4: `EpisodeDownloader` cache queries (no transfer)

**Files:**
- Modify: `src/EpisodeDownloader.h`
- Modify: `src/EpisodeDownloader.cpp`

- [ ] **Step 1: Declare the cache-query methods (header)**

In `EpisodeDownloader.h`, after `void cancel();` (~line 30):

```cpp
    // Cache queries that do NOT start a transfer (drive the episode page's
    // download/play state). cachedPath returns the existing <eid>.<ext> file or "".
    QString cachedPath(const QString &eid);
    bool isCached(const QString &eid);
    qint64 cachedSizeBytes(const QString &eid);
    bool removeCached(const QString &eid);
```

(Non-const: they resolve `audioDir()`, which caches `m_audioDir`.)

- [ ] **Step 2: Implement them (cpp)**

Append to `EpisodeDownloader.cpp` (after `extensionForUrl`, end of file):

```cpp
QString EpisodeDownloader::cachedPath(const QString &eid)
{
    const QString dir = audioDir();
    if (dir.isEmpty() || eid.isEmpty())
        return QString();
    // The cached filename is <eid>.<ext>; the extension depends on the source URL,
    // so match any non-.part file beginning with the eid. (audioDir() is a PUBLIC
    // path, so entryList is reliable here -- unlike the /private data cage.)
    QDir d(dir);
    const QStringList hits = d.entryList(QStringList() << (eid + QLatin1String(".*")),
                                         QDir::Files);
    for (int i = 0; i < hits.size(); ++i) {
        if (!hits.at(i).endsWith(QLatin1String(".part")))
            return d.filePath(hits.at(i));
    }
    return QString();
}

bool EpisodeDownloader::isCached(const QString &eid)
{
    return !cachedPath(eid).isEmpty();
}

qint64 EpisodeDownloader::cachedSizeBytes(const QString &eid)
{
    const QString path = cachedPath(eid);
    return path.isEmpty() ? 0 : QFileInfo(path).size();
}

bool EpisodeDownloader::removeCached(const QString &eid)
{
    const QString path = cachedPath(eid);
    return path.isEmpty() ? false : QFile::remove(path);
}
```

- [ ] **Step 3: Build to confirm it compiles**

Run: `pwsh scripts/build-simulator.ps1 -Config Debug`
Expected: "Build succeeded" (functional check happens via Task 5/7).

- [ ] **Step 4: Commit**

```bash
git add src/EpisodeDownloader.h src/EpisodeDownloader.cpp
git commit -m "feat: EpisodeDownloader cache queries (isCached/size/remove)"
```

---

## Task 5: `PlayerController` download-only verbs

**Files:**
- Modify: `src/PlayerController.h`
- Modify: `src/PlayerController.cpp`

- [ ] **Step 1: Declare the verbs + state (header)**

In `PlayerController.h`, after `Q_INVOKABLE void seek(int positionMs);` (~line 64):

```cpp
    // Two-step (download, then play) for the episode page.
    Q_INVOKABLE void download(const QUrl &url, const QString &eid);  // download only
    Q_INVOKABLE void cancelDownload();
    Q_INVOKABLE bool isDownloaded(const QString &eid);
    Q_INVOKABLE QString downloadedSizeText(const QString &eid);
    Q_INVOKABLE void deleteDownload(const QString &eid);
```

Add a private helper after `void maybeStartPlayback();` (~line 92):

```cpp
    static QString formatBytes(qint64 bytes);
```

Add a member after `bool m_waitingToPlay;` (~line 96):

```cpp
    bool m_downloadOnly;        // download() without auto-play
```

- [ ] **Step 2: Initialize the flag (ctor)**

In `PlayerController.cpp` ctor init list, after `, m_waitingToPlay(false)` (~line 9):

```cpp
    , m_downloadOnly(false)
```

- [ ] **Step 3: Implement the verbs (cpp)**

After `playEpisode(...)` (~line 55), add:

```cpp
void PlayerController::download(const QUrl &url, const QString &eid)
{
    m_downloader.cancel();
    m_waitingToPlay = false;
    m_downloadOnly = true;              // do not auto-play when this finishes
    if (m_currentEid != eid) { m_currentEid = eid; emit currentEidChanged(); }
    setErrorString(QString());
    setDownloadProgress(0.0);
    setState(Downloading);
    qDebug() << "PlayerController: download-only eid=" << eid << "url=" << url.toString();
    m_downloader.start(url, eid);
}

void PlayerController::cancelDownload()
{
    m_downloader.cancel();
    m_waitingToPlay = false;
    m_downloadOnly = false;
    setDownloadProgress(0.0);
    setState(Idle);
}

bool PlayerController::isDownloaded(const QString &eid)
{
    return m_downloader.isCached(eid);
}

QString PlayerController::downloadedSizeText(const QString &eid)
{
    return formatBytes(m_downloader.cachedSizeBytes(eid));
}

void PlayerController::deleteDownload(const QString &eid)
{
    if (eid == m_currentEid) {
        m_downloader.cancel();
        if (m_audio) m_audio->reset();
        m_waitingToPlay = false;
        m_downloadOnly = false;
        setDownloadProgress(0.0);
        setState(Idle);
    }
    m_downloader.removeCached(eid);
}

QString PlayerController::formatBytes(qint64 bytes)
{
    if (bytes <= 0) return QString();
    const double mb = double(bytes) / (1024.0 * 1024.0);
    if (mb >= 1.0)
        return QString::fromLatin1("%1 MB").arg(mb, 0, 'f', 1);
    return QString::fromLatin1("%1 KB").arg(double(bytes) / 1024.0, 0, 'f', 0);
}
```

- [ ] **Step 4: Branch `onDownloadFinished` for download-only**

Replace `onDownloadFinished` (~lines 82-99) with:

```cpp
void PlayerController::onDownloadFinished(const QString &localPath)
{
    if (!m_audio)
        return;
    if (m_currentSourcePath != localPath) {
        m_currentSourcePath = localPath;
        emit currentSourcePathChanged();
    }
    setDownloadProgress(1.0);

    if (m_downloadOnly) {
        m_downloadOnly = false;
        qDebug() << "PlayerController: download-only finished" << localPath;
        setState(Idle);            // cached & ready; the page shows Play + on-device
        return;
    }

    setState(Preparing);
    qDebug() << "PlayerController: download ready, loading" << localPath;
    // Defer play() until the media is loaded. On Symbian, play()-before-loaded races
    // MMF's audio-output acquisition and fails with KErrInUse (-14): the clip buffers
    // (mediaStatus 6) but never sounds and position/duration stay 0.
    m_waitingToPlay = true;
    m_audio->setSource(QUrl::fromLocalFile(localPath));
    maybeStartPlayback();   // in case it's already loaded (e.g. replay)
}
```

- [ ] **Step 5: Build to confirm it compiles**

Run: `pwsh scripts/build-simulator.ps1 -Config Debug`
Expected: "Build succeeded".

- [ ] **Step 6: Commit**

```bash
git add src/PlayerController.h src/PlayerController.cpp
git commit -m "feat: PlayerController two-step download verbs (download/cancel/isDownloaded/delete)"
```

---

## Task 6: New icons + qrc

**Files:**
- Create: `qml/gfx/icon-download.svg`, `qml/gfx/icon-check.svg`, `qml/gfx/icon-trash.svg`
- Modify: `qml/qml.qrc`

(Cancel reuses the existing `gfx/icon-x.svg`; Play reuses `gfx/icon-play-white.svg`; the equalizer is animated QML, no SVG.) SVGs use a `viewBox` matching the existing 24×24 icons (per the Symbian viewBox sizing rule).

- [ ] **Step 1: Create `qml/gfx/icon-download.svg`**

```svg
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="#a98cff"><path d="M12 3a1 1 0 0 1 1 1v7h2.5L12 15.8 8.5 11H11V4a1 1 0 0 1 1-1zM5 18h14v2H5z"/></svg>
```

- [ ] **Step 2: Create `qml/gfx/icon-check.svg`**

```svg
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="#a98cff"><path d="M9.5 16.2 5.3 12l-1.4 1.4 5.6 5.6 12-12-1.4-1.4z"/></svg>
```

- [ ] **Step 3: Create `qml/gfx/icon-trash.svg`**

```svg
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="#5d5d66"><path d="M9 3h6l1 2h4v2H4V5h4l1-2zM6 8h12l-1 12H7L6 8z"/></svg>
```

- [ ] **Step 4: Register them in `qml/qml.qrc`**

After `<file>gfx/icon-grid.svg</file>` (~line 32):

```xml
        <file>gfx/icon-download.svg</file>
        <file>gfx/icon-check.svg</file>
        <file>gfx/icon-trash.svg</file>
```

- [ ] **Step 5: Build (force rcc) + confirm icons embed**

```
pwsh scripts/build-simulator.ps1 -Config Debug -Clean
```
Expected: "Build succeeded" (a `-Clean` build regenerates the qrc so the new svgs embed).

- [ ] **Step 6: Commit**

```bash
git add qml/gfx/icon-download.svg qml/gfx/icon-check.svg qml/gfx/icon-trash.svg qml/qml.qrc
git commit -m "feat: add download/check/trash icons for episode download-to-play CTA"
```

---

## Task 7: `EpisodePage.qml` — stateful Download → Play CTA

**Files:**
- Modify: `qml/EpisodePage.qml`

- [ ] **Step 1: Add state properties**

After `property string whenText: ""` (~line 21):

```qml
    property string audioUrl: ""
    property bool downloaded: false
    property string downloadedSize: ""
    // CTA mode, derived: "download" | "downloading" | "preparing" | "playing" | "paused" | "ready"
    property string mode: page.ctaMode()
```

- [ ] **Step 2: Seed `audioUrl` + reset cache fields in `openWith`**

In `openWith(item)`, add `page.audioUrl = item.audioUrl;` after the `whenText` seed, and reset the cache fields alongside the cleared fetch fields:

```qml
        page.whenText = item.whenText;
        page.audioUrl = item.audioUrl;
        // clear fetched fields so the previous episode never lingers behind a load
        page.showTitle = "";
        page.notes = "";
        page.commentCountText = "";
        page.commentModel = [];
        page.detailLoaded = false;
        page.downloaded = false;
        page.downloadedSize = "";
```

- [ ] **Step 3: Add root helper functions**

After `subLine()` (~line 50), add (functions at root only — QML 1.1 rule):

```qml
    function refreshDownloaded() {
        page.downloaded = (page.eid !== "" && player.isDownloaded(page.eid));
        page.downloadedSize = page.downloaded ? player.downloadedSizeText(page.eid) : "";
    }

    function ctaMode() {
        if (player.currentEid === page.eid) {
            if (player.state === player.downloadingState) return "downloading";
            if (player.state === player.preparingState) return "preparing";
            if (player.state === player.playingState) return "playing";
            if (player.state === player.pausedState) return "paused";
        }
        return page.downloaded ? "ready" : "download";
    }

    function ctaStatusVisible() {
        return page.downloaded && page.mode !== "download" && page.mode !== "downloading";
    }
```

- [ ] **Step 4: Refresh download state on activation + player changes**

Extend `onStatusChanged` to refresh on activation:

```qml
    onStatusChanged: {
        if (status === PageStatus.Active && page.eid !== "" && !page.detailLoaded) {
            xyzApi.fetchEpisode(page.eid);
        }
        if (status === PageStatus.Active) {
            page.refreshDownloaded();
        }
    }
```

Add a `Connections` block right after the existing `Connections { target: xyzApi ... }` block (~line 72):

```qml
    Connections {
        target: player
        // When a download-only completes, state returns to Idle -> re-check the cache.
        onStateChanged: page.refreshDownloaded();
    }
```

- [ ] **Step 5: Replace the inert CTA block**

Replace the entire `// ---- Play CTA (inert — player deferred) ----` `Item { ... }` (current ~lines 163-201) with the stateful CTA:

```qml
            // ---- download / play CTA ----
            Item {
                id: ctaWrap
                width: contentCol.width
                height: page.ctaStatusVisible() ? 100 : 66

                // (a) not cached -> Download
                Rectangle {
                    visible: page.mode === "download"
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.leftMargin: 14; anchors.rightMargin: 14
                    anchors.top: parent.top; anchors.topMargin: 6
                    height: 46; radius: 6
                    color: Theme.panel2
                    border.width: 1; border.color: Theme.accent
                    Row {
                        anchors.centerIn: parent; spacing: 8
                        Image { source: "gfx/icon-download.svg"; width: 20; height: 20; smooth: true; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: qsTr("Download"); font.pixelSize: 15; font.bold: true; color: Theme.accentBright; anchors.verticalCenter: parent.verticalCenter }
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: page.audioUrl !== ""
                        onClicked: player.download(page.audioUrl, page.eid)
                    }
                }

                // (b) downloading -> progress + cancel
                Rectangle {
                    visible: page.mode === "downloading"
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.leftMargin: 14; anchors.rightMargin: 14
                    anchors.top: parent.top; anchors.topMargin: 6
                    height: 46; radius: 6; clip: true
                    color: Theme.panel
                    border.width: 1; border.color: Theme.hairlineStrong
                    Rectangle {
                        anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                        width: parent.width * player.downloadProgress
                        color: Theme.accentDeep
                    }
                    Text {
                        anchors.left: parent.left; anchors.leftMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("Downloading"); font.pixelSize: 15; font.bold: true; color: Theme.text
                    }
                    Text {
                        id: dlPct
                        anchors.right: dlCancel.left; anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        text: Math.round(player.downloadProgress * 100) + "%"
                        font.pixelSize: 13; color: Theme.accentBright
                    }
                    Image {
                        id: dlCancel
                        source: "gfx/icon-x.svg"; width: 14; height: 14; smooth: true
                        anchors.right: parent.right; anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: { player.cancelDownload(); page.refreshDownloaded(); }
                    }
                }

                // (c) cached, idle/paused/preparing -> Play / Resume
                Rectangle {
                    visible: page.mode === "ready" || page.mode === "paused" || page.mode === "preparing"
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.leftMargin: 14; anchors.rightMargin: 14
                    anchors.top: parent.top; anchors.topMargin: 6
                    height: 46; radius: 6
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Theme.accentBright }
                        GradientStop { position: 1.0; color: Theme.accentDeep }
                    }
                    Row {
                        anchors.centerIn: parent; spacing: 10
                        Image { source: "gfx/icon-play-white.svg"; width: 22; height: 22; smooth: true; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            text: page.mode === "paused" ? qsTr("Resume") : (page.mode === "preparing" ? qsTr("Loading…") : qsTr("Play"))
                            font.pixelSize: 15; font.bold: true; color: "#ffffff"; anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            if (page.mode === "paused") player.resume();
                            else if (page.mode === "ready") player.playEpisode(page.audioUrl, page.eid, page.epTitle);
                        }
                    }
                }

                // (d) playing -> equalizer (tap to pause)
                Rectangle {
                    id: playingBtn
                    visible: page.mode === "playing"
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.leftMargin: 14; anchors.rightMargin: 14
                    anchors.top: parent.top; anchors.topMargin: 6
                    height: 46; radius: 6
                    color: "#338b6dff"
                    border.width: 1; border.color: Theme.accent
                    Text {
                        id: playingLabel
                        anchors.centerIn: parent; anchors.horizontalCenterOffset: -14
                        text: qsTr("Playing"); font.pixelSize: 15; font.bold: true; color: Theme.accentBright
                    }
                    Item {
                        id: eq
                        width: 17; height: 15
                        anchors.left: playingLabel.right; anchors.leftMargin: 9
                        anchors.verticalCenter: parent.verticalCenter
                        Repeater {
                            model: 4
                            Rectangle {
                                width: 3; radius: 1; color: Theme.accentBright
                                x: index * 5
                                anchors.bottom: parent.bottom
                                height: 5
                                SequentialAnimation on height {
                                    running: playingBtn.visible
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 14; duration: 320 + index * 70; easing.type: Easing.InOutSine }
                                    NumberAnimation { to: 5;  duration: 320 + index * 70; easing.type: Easing.InOutSine }
                                }
                            }
                        }
                    }
                    MouseArea { anchors.fill: parent; onClicked: player.pause() }
                }

                // on-device status + delete (under the button when cached)
                Row {
                    id: dlStatus
                    visible: page.ctaStatusVisible()
                    anchors.left: parent.left; anchors.leftMargin: 14
                    anchors.top: parent.top; anchors.topMargin: 60
                    spacing: 6
                    Image { source: "gfx/icon-check.svg"; width: 14; height: 14; smooth: true; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: qsTr("On device"); font.pixelSize: 12; color: Theme.accentBright; anchors.verticalCenter: parent.verticalCenter }
                    Text { visible: page.downloadedSize !== ""; text: "· " + page.downloadedSize; font.pixelSize: 12; color: Theme.textDim; anchors.verticalCenter: parent.verticalCenter }
                }
                Item {
                    id: dlDelete
                    visible: page.ctaStatusVisible()
                    anchors.right: parent.right; anchors.rightMargin: 8
                    anchors.verticalCenter: dlStatus.verticalCenter
                    width: delRow.width + 16; height: 36
                    Row {
                        id: delRow; anchors.centerIn: parent; spacing: 5
                        Image { source: "gfx/icon-trash.svg"; width: 14; height: 14; smooth: true; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: qsTr("Delete"); font.pixelSize: 12; color: Theme.textFaint; anchors.verticalCenter: parent.verticalCenter }
                    }
                    MouseArea { anchors.fill: parent; onClicked: { player.deleteDownload(page.eid); page.refreshDownloaded(); } }
                }
            }
```

- [ ] **Step 6: Build (force rcc) + run against the mock**

```
pwsh scripts/build-simulator.ps1 -Config Debug -Clean
pwsh -File scripts/mock-content.ps1        # separate shell, leave running
$env:XYZ_API_BASE = "http://localhost:8099"; pwsh build-simulator/debug/Xyz.run.ps1
```
(If a token isn't seeded, the app lands on login — seed the sim DB `kv` token as in prior sessions, or log in.) Open Updates → tap an episode.

Expected flow on the episode page:
1. CTA shows **Download** (audioUrl populated from the mock).
2. Tap → **Downloading** with a growing fill + `%`; ✕ cancels.
3. Completes → **Play** button + "✓ On device · <KB/MB>" with **Delete**.
4. Tap Play → **Playing** with animated equalizer (audio plays via the desktop backend; on-device audio is verified in Task 8). Tap → pauses → **Resume**.
5. Delete → returns to **Download**.

Check `C:/Data/Xyz/logs/xyz.log` is free of QML binding errors.

- [ ] **Step 7: Commit**

```bash
git add qml/EpisodePage.qml
git commit -m "feat: episode page two-step Download->Play CTA wired to player"
```

---

## Task 8: Device verification + DEVICE_NOTES

**Files:**
- Modify: `docs/DEVICE_NOTES.md`

- [ ] **Step 1: Build + install the SIS**

```
pwsh scripts/build-sis.ps1 -Config Release -Arch armv5 -Clean
```
Transfer `build-symbian/<arch>-release/Xyz_selfsigned.sis` via Bluetooth and install. (Reboot the phone first if any prior audio test misbehaved — DEVICE_NOTES 2026-06-19.)

- [ ] **Step 2: Verify the full flow on a real episode**

Log in, open a real episode, and confirm: Download shows real progress; "On device · size" appears with the real file size; Play plays the cached `.m4a` **with audio**; Pause/Resume work; Delete removes it and the CTA returns to Download; reopening a cached episode shows Play instantly (no re-download).

- [ ] **Step 3: Record results in DEVICE_NOTES.md**

Add a dated `## 2026-06-19 — Episode page two-step download→play` entry: what worked, any MMF error codes, and any device-specific tuning (icon sizing, tap targets). Then:

```bash
git add docs/DEVICE_NOTES.md
git commit -m "docs: device notes for episode two-step download->play"
```

---

## Self-Review

**Spec coverage:**
- Data layer audioUrl (XyzApiClient + mock + live verify) → Tasks 1–3. ✓
- EpisodeDownloader cache lookups → Task 4. ✓
- PlayerController download-only verbs (download/cancel/isDownloaded/sizeText/delete, no auto-play) → Task 5. ✓
- EpisodePage state machine + eid guard (`player.currentEid === page.eid`) → Task 7 (`ctaMode`). ✓
- Icons/theme → Task 6 (tokens already in Theme.js; new svgs added). ✓
- Decisions: no-autoplay (Task 5 `m_downloadOnly`), size-from-disk (Task 4 `cachedSizeBytes` + Task 5 `formatBytes`), no seek/time (Task 7 has no scrubber), per-episode delete in / mini-player & now-playing & downloads-manager out. ✓
- Device verification → Task 8. ✓

**Type consistency:** `download/cancelDownload/isDownloaded/downloadedSizeText/deleteDownload` and `cachedPath/isCached/cachedSizeBytes/removeCached` are used identically across Tasks 4/5/7. `mode` strings ("download"/"downloading"/"preparing"/"playing"/"paused"/"ready") match between `ctaMode`, `ctaStatusVisible`, and the CTA `visible` bindings.

**Placeholder scan:** none — every code step shows complete code. The only conditional is Task 1→3 (`enclosure.url` path), which has an explicit default and an adjust-if-different instruction.

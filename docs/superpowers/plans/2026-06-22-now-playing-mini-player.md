# Now Playing Page + Mini Floating Player Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a full-screen Now Playing page and a persistent mini floating player, both wired to the existing `player` (PlayerController) seam.

**Architecture:** `PlayerController` gains `currentCoverUrl`/`currentShow` so both surfaces have cover + show name from one source of truth. `NowPlayingPage.qml` is a pushed `Page` (down-chevron header → `pageStack.pop()`) bound to `player`. `MiniPlayer.qml` is a reusable 56px dock bound to `player`, embedded above the `BelleTabBar` on the tab pages (Updates, Subscriptions, Me) and at the bottom of Episode detail; tapping it pushes the shared `NowPlayingPage` via an `openPlayerRequested` signal that `AppWindow` handles.

**Tech Stack:** Qt 4.7.4 / QML 1.1 (`QtQuick 1.1`, `com.nokia.symbian 1.1`), QtMobility multimedia, Symbian Belle. Host verification via the Simulator (mingw, raster) build.

## Global Constraints

- **QML 1.1 only:** no block expressions in property bindings (use helper functions/ternaries); named functions declared at `Page`/root level only; no negative anchor margins (use `x`/sizing or a larger `Item`).
- **Symbian audio rule:** never write a QML `Audio.position`. All seeks go through `player.seek(ms)` → C++ `AudioEngine::seek`. (This plan touches no QML `Audio` element.)
- **SVG sizing:** Symbian renders SVGs at their `viewBox` size. New glyphs use a `24 24` viewBox (matching `icon-play.svg`); QML `width`/`height` still set for the Simulator.
- **Accent palette (verbatim):** accent `#8b6dff`, accentBright `#a98cff`, accentDeep `#5b3fd6`, text `#f3f3f6`, textDim `#8b8b95`, bg `#000000`. Use `Theme.*` (`qml/js/Theme.js`) in QML, not raw hex, except where an exact ARGB (e.g. `#668b6dff`) is needed.
- **No host unit-test harness exists** (only `qml/SelfTestPage.qml` + Simulator/device runs). Verification = Simulator build compiles (`scripts/build-simulator.ps1`) + interactive run of the flow (per the project's "verify QML flow interactively" rule — static review is not sufficient).
- **New QML/SVG files must be registered** in `qml/qml.qrc` (the app loads QML from `qrc:/qml/...`). Mirror them into `Xyz.pro` `OTHER_FILES` to match the existing pattern.
- **Speed chip + bottom toolbar are static, non-interactive placeholders** (AudioEngine has no playback-rate API). The comment-count chip is omitted (no real count on `player`; avoid showing invented data).
- **Mini player shows** only when `player.currentEid !== "" && state ∈ {preparingState, playingState, pausedState}`.

## File Structure

- **Modify** `src/PlayerController.h` / `src/PlayerController.cpp` — add `currentCoverUrl`/`currentShow` read-only properties; extend `playEpisode(...)` to set them. One responsibility unchanged: the QML-facing playback seam.
- **Modify** `qml/EpisodePage.qml` — pass cover + show into the new `playEpisode` arity (line 306).
- **Modify** `qml/BelleHeader.qml` — add optional `leadIconSource` (default `gfx/icon-back.svg`) so the player can use a down-chevron.
- **Create** `qml/NowPlayingPage.qml` — the full-screen player UI.
- **Create** `qml/MiniPlayer.qml` — the reusable docked bar.
- **Modify** `qml/AppWindow.qml` — own one `NowPlayingPage`; push it on `openPlayerRequested` from each host page.
- **Modify** `qml/UpdatesPage.qml`, `qml/SubscriptionsPage.qml`, `qml/HomePage.qml`, `qml/EpisodePage.qml` — embed `MiniPlayer`, re-anchor content bottom, emit `openPlayerRequested`.
- **Create** `qml/gfx/icon-pause-white.svg`, `qml/gfx/icon-pause.svg`, `qml/gfx/icon-rewind.svg`, `qml/gfx/icon-forward.svg`.
- **Modify** `qml/qml.qrc` (+ `Xyz.pro` `OTHER_FILES`) — register the new QML + SVG files.

---

### Task 1: PlayerController carries cover + show name

The only backend change. Extends the single source of truth so the mini player and Now Playing page can render cover + show. Compiles and runs on the Simulator; the existing Episode play flow must still work.

**Files:**
- Modify: `src/PlayerController.h` (properties ~26–27, accessors ~47–49, `playEpisode` decl line 60, signals ~79–81, members ~111–113)
- Modify: `src/PlayerController.cpp` (`playEpisode` lines 35–59)
- Modify: `qml/EpisodePage.qml` (line 306)

**Interfaces:**
- Consumes: existing `m_currentTitle`/`currentTitleChanged` pattern.
- Produces:
  - `QString PlayerController::currentCoverUrl() const;` (property `currentCoverUrl`, NOTIFY `currentCoverUrlChanged`)
  - `QString PlayerController::currentShow() const;` (property `currentShow`, NOTIFY `currentShowChanged`)
  - `Q_INVOKABLE void playEpisode(const QUrl &url, const QString &eid, const QString &title, const QString &coverUrl, const QString &show);`

- [ ] **Step 1: Add the two properties in the header**

In `src/PlayerController.h`, after line 27 (`Q_PROPERTY(QString currentTitle READ currentTitle NOTIFY currentTitleChanged)`), add:

```cpp
    Q_PROPERTY(QString currentCoverUrl READ currentCoverUrl NOTIFY currentCoverUrlChanged)
    Q_PROPERTY(QString currentShow READ currentShow NOTIFY currentShowChanged)
```

- [ ] **Step 2: Add the accessors**

In `src/PlayerController.h`, after line 48 (`QString currentTitle() const { return m_currentTitle; }`), add:

```cpp
    QString currentCoverUrl() const { return m_currentCoverUrl; }
    QString currentShow() const { return m_currentShow; }
```

- [ ] **Step 3: Change the `playEpisode` declaration**

In `src/PlayerController.h`, replace line 60:

```cpp
    Q_INVOKABLE void playEpisode(const QUrl &url, const QString &eid, const QString &title);
```

with:

```cpp
    Q_INVOKABLE void playEpisode(const QUrl &url, const QString &eid, const QString &title,
                                 const QString &coverUrl, const QString &show);
```

- [ ] **Step 4: Add the signals**

In `src/PlayerController.h`, after line 80 (`void currentTitleChanged();`), add:

```cpp
    void currentCoverUrlChanged();
    void currentShowChanged();
```

- [ ] **Step 5: Add the members**

In `src/PlayerController.h`, after line 112 (`QString m_currentTitle;`), add:

```cpp
    QString m_currentCoverUrl;
    QString m_currentShow;
```

- [ ] **Step 6: Set them in `playEpisode`**

In `src/PlayerController.cpp`, change the signature on line 35 to match, and after the `m_currentTitle` block (line 52) set the new fields. The method head becomes:

```cpp
void PlayerController::playEpisode(const QUrl &url, const QString &eid, const QString &title,
                                   const QString &coverUrl, const QString &show)
{
    if (!m_audio) {
        setErrorString(QLatin1String("Audio unavailable."));
        setState(Error);
        return;
    }

    m_downloader.cancel();
    m_waitingToPlay = false;
    m_downloadOnly = false;
    m_audio->reset();

    if (m_currentEid != eid) { m_currentEid = eid; emit currentEidChanged(); }
    if (m_currentTitle != title) { m_currentTitle = title; emit currentTitleChanged(); }
    if (m_currentCoverUrl != coverUrl) { m_currentCoverUrl = coverUrl; emit currentCoverUrlChanged(); }
    if (m_currentShow != show) { m_currentShow = show; emit currentShowChanged(); }
    setErrorString(QString());
    setDownloadProgress(0.0);
    setState(Downloading);

    qDebug() << "PlayerController: playEpisode eid=" << eid << "url=" << url.toString();
    m_downloader.start(url, eid);
}
```

- [ ] **Step 7: Update the one QML caller**

In `qml/EpisodePage.qml` line 306, replace:

```qml
                            else if (page.mode === "ready") player.playEpisode(page.audioUrl, page.eid, page.epTitle);
```

with:

```qml
                            else if (page.mode === "ready") player.playEpisode(page.audioUrl, page.eid, page.epTitle, page.coverUrl, page.showTitle);
```

- [ ] **Step 8: Confirm no other caller exists**

Run: `git grep -n "playEpisode(" -- qml src`
Expected: only the `EpisodePage.qml` call (now 5 args) and the `PlayerController.{h,cpp}` definition. If any other caller appears, update it to the 5-arg form.

- [ ] **Step 9: Build the Simulator target**

Run: `pwsh scripts/build-simulator.ps1 -Config Debug`
Expected: `Build succeeded: ...\build-simulator\debug\Xyz.exe`, exit 0.

- [ ] **Step 10: Run and confirm playback still works**

Run: `pwsh build-simulator/debug/Xyz.run.ps1`
Open an episode → Download → Play. Expected: audio plays as before (no regression from the signature change). Close the app.

- [ ] **Step 11: Commit**

```bash
git add src/PlayerController.h src/PlayerController.cpp qml/EpisodePage.qml
git commit -m "feat(player): carry cover + show through PlayerController for player surfaces"
```

---

### Task 2: New player glyph assets

Four SVGs the player surfaces need (pause for both buttons, rewind/forward arrows). Registered in the qrc so the build embeds them. Independently reviewable as an asset drop; verified by a clean resource compile.

**Files:**
- Create: `qml/gfx/icon-pause-white.svg`, `qml/gfx/icon-pause.svg`, `qml/gfx/icon-rewind.svg`, `qml/gfx/icon-forward.svg`
- Modify: `qml/qml.qrc`

**Interfaces:**
- Produces: resource paths `gfx/icon-pause-white.svg`, `gfx/icon-pause.svg`, `gfx/icon-rewind.svg`, `gfx/icon-forward.svg` (consumed by Tasks 3–4).

- [ ] **Step 1: Create `qml/gfx/icon-pause-white.svg`** (big-button pause, white — matches `icon-play-white.svg`)

```xml
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="#ffffff"><rect x="6" y="5" width="4" height="14" rx="1.2"/><rect x="14" y="5" width="4" height="14" rx="1.2"/></svg>
```

- [ ] **Step 2: Create `qml/gfx/icon-pause.svg`** (mini pause, accent — matches `icon-play.svg` fill `#a98cff`)

```xml
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="#a98cff"><rect x="6" y="5" width="4" height="14" rx="1.2"/><rect x="14" y="5" width="4" height="14" rx="1.2"/></svg>
```

- [ ] **Step 3: Create `qml/gfx/icon-rewind.svg`** (back-circular arrow; the "15" overlays as QML `Text`)

```xml
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#d6d6dd" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 12a8 8 0 1 0 2.34-5.66"/><path d="M4 4v4h4"/></svg>
```

- [ ] **Step 4: Create `qml/gfx/icon-forward.svg`** (forward-circular arrow; the "30" overlays as QML `Text`)

```xml
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#d6d6dd" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M20 12a8 8 0 1 1-2.34-5.66"/><path d="M20 4v4h-4"/></svg>
```

- [ ] **Step 5: Register the four SVGs in `qml/qml.qrc`**

In `qml/qml.qrc`, after line 35 (`<file>gfx/icon-trash-white.svg</file>`), add:

```xml
        <file>gfx/icon-pause.svg</file>
        <file>gfx/icon-pause-white.svg</file>
        <file>gfx/icon-rewind.svg</file>
        <file>gfx/icon-forward.svg</file>
```

- [ ] **Step 6: Build to confirm the resource compiles**

Run: `pwsh scripts/build-simulator.ps1 -Config Debug`
Expected: build succeeds (rcc embeds the four new files; a typo'd path fails the rcc step).

- [ ] **Step 7: Commit**

```bash
git add qml/gfx/icon-pause.svg qml/gfx/icon-pause-white.svg qml/gfx/icon-rewind.svg qml/gfx/icon-forward.svg qml/qml.qrc
git commit -m "feat(player): add pause + rewind/forward glyph assets"
```

---

### Task 3: NowPlayingPage + MiniPlayer, wired end-to-end on Updates

A vertical slice: the mini player and Now Playing page are mutually dependent for testing (the page needs a trigger; the dock needs a target), so they land together, wired on the Updates page. Also includes the shared `BelleHeader` tweak the page needs. After this task: play an episode → the mini player appears on Updates → tap it → a working Now Playing page.

**Files:**
- Modify: `qml/BelleHeader.qml` (lead icon, lines 39–44)
- Create: `qml/NowPlayingPage.qml`
- Create: `qml/MiniPlayer.qml`
- Modify: `qml/AppWindow.qml` (add `NowPlayingPage` instance + `openNowPlaying()`, wire Updates)
- Modify: `qml/UpdatesPage.qml` (embed `MiniPlayer`, re-anchor list, emit `openPlayerRequested`)
- Modify: `qml/qml.qrc` and `Xyz.pro` `OTHER_FILES` (register the two QML files)

**Interfaces:**
- Consumes: `player.{currentCoverUrl,currentShow,currentTitle,position,duration,state,playingState,pausedState,preparingState,currentEid}`, `player.pause()/resume()/seek(ms)` (Task 1); glyphs from Task 2.
- Produces:
  - `BelleHeader` property `leadIconSource` (default `"gfx/icon-back.svg"`).
  - `MiniPlayer` component with `signal expandRequested`.
  - `NowPlayingPage` (`objectName: "NowPlayingPage"`, `hidesToolBar: true`).
  - `UpdatesPage` `signal openPlayerRequested`.
  - `AppWindow` `function openNowPlaying()`.

- [ ] **Step 1: Add `leadIconSource` to `BelleHeader.qml`**

In `qml/BelleHeader.qml`, after line 9 (`property string actionIconSource: ""`), add:

```qml
    property string leadIconSource: "gfx/icon-back.svg"
```

Then change the lead `Image` source (line 40) from:

```qml
            source: "gfx/icon-back.svg"
```

to:

```qml
            source: header.leadIconSource
```

- [ ] **Step 2: Create `qml/MiniPlayer.qml`**

```qml
import QtQuick 1.1
import "js/Theme.js" as Theme

// Mini floating player docked above the bottom bar (design: belle.css .miniplayer).
// Bound to the `player` context object. Visible whenever a track is loaded/playing.
// Tapping the bar (anywhere but the play button) emits expandRequested.
Rectangle {
    id: mini

    signal expandRequested

    height: 56
    visible: player.currentEid !== "" &&
             (player.state === player.preparingState ||
              player.state === player.playingState ||
              player.state === player.pausedState)

    gradient: Gradient {
        GradientStop { position: 0.0; color: "#1a1a1f" }
        GradientStop { position: 1.0; color: "#101013" }
    }

    function fmt(ms) {
        if (ms <= 0) return "0:00";
        var s = Math.floor(ms / 1000);
        var m = Math.floor(s / 60);
        var r = s % 60;
        return m + ":" + (r < 10 ? "0" + r : r);
    }

    // top hairline
    Rectangle {
        anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
        height: 1; color: "#000000"
    }

    // whole-bar tap target (declared first → sits beneath the play button) → expand
    MouseArea { anchors.fill: parent; onClicked: mini.expandRequested() }

    Rectangle {
        id: cover
        width: 38; height: 38; radius: 5
        anchors.left: parent.left; anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        color: "#1a1a22"; clip: true
        Image {
            anchors.fill: parent; fillMode: Image.PreserveAspectCrop; smooth: true
            sourceSize.width: 38; sourceSize.height: 38
            source: player.currentCoverUrl
        }
    }

    Rectangle {
        id: playBtn
        width: 38; height: 38; radius: 19
        anchors.right: parent.right; anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        color: "#248b6dff"
        border.width: 1; border.color: Theme.accent
        Image {
            anchors.centerIn: parent; width: 18; height: 18; smooth: true
            source: player.state === player.playingState ? "gfx/icon-pause.svg" : "gfx/icon-play.svg"
        }
        MouseArea {
            anchors.fill: parent
            onClicked: {
                if (player.state === player.playingState) player.pause();
                else player.resume();
            }
        }
    }

    Image {
        id: queueIco
        source: "gfx/icon-queue.svg"; width: 24; height: 24; smooth: true; opacity: 0.85
        anchors.right: playBtn.left; anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
    }

    Column {
        anchors.left: cover.right; anchors.leftMargin: 11
        anchors.right: queueIco.left; anchors.rightMargin: 11
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        Text {
            width: parent.width
            text: player.currentTitle
            font.pixelSize: 14; font.weight: Font.DemiBold; color: Theme.text
            elide: Text.ElideRight
        }
        Text {
            text: mini.fmt(player.position) + " / " + mini.fmt(player.duration)
            font.pixelSize: 12; color: Theme.textDim
        }
    }
}
```

- [ ] **Step 3: Create `qml/NowPlayingPage.qml`**

```qml
import QtQuick 1.1
import com.nokia.symbian 1.1
import "js/Theme.js" as Theme

// Now Playing — full-screen player (design: belle.css .player / screens-player.jsx).
// Pushed over the current page; reads everything from the `player` context object.
// Down-chevron header pops back. Speed chip + bottom toolbar are static placeholders.
Page {
    id: page
    objectName: "NowPlayingPage"

    property bool hidesToolBar: true

    // scrubber drag state (don't let position updates fight the finger)
    property bool scrubbing: false
    property real scrubRatio: 0.0

    function fmt(ms) {
        if (ms <= 0) return "0:00";
        var s = Math.floor(ms / 1000);
        var m = Math.floor(s / 60);
        var r = s % 60;
        return m + ":" + (r < 10 ? "0" + r : r);
    }

    function remaining() {
        var d = player.duration;
        if (d <= 0) return "-0:00";
        return "-" + fmt(d - player.position);
    }

    function progressRatio() {
        if (page.scrubbing) return page.scrubRatio;
        if (player.duration <= 0) return 0.0;
        return player.position / player.duration;
    }

    function togglePlay() {
        if (player.state === player.playingState) player.pause();
        else player.resume();
    }

    function skip(deltaMs) {
        var t = player.position + deltaMs;
        if (t < 0) t = 0;
        if (player.duration > 0 && t > player.duration) t = player.duration;
        player.seek(t);
    }

    function clamp01(v) {
        if (v < 0) return 0.0;
        if (v > 1) return 1.0;
        return v;
    }

    Rectangle { anchors.fill: parent; color: Theme.bg }

    BelleHeader {
        id: header
        title: qsTr("Now Playing")
        leadIconSource: "gfx/icon-chevron-down.svg"
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        onBackClicked: pageStack.pop()
    }

    // ---- bottom toolbar (static placeholders) ----
    Rectangle {
        id: toolbar
        height: 56
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#2a2a30" }
            GradientStop { position: 0.08; color: "#1d1d22" }
            GradientStop { position: 1.0; color: "#141417" }
        }
        Rectangle {
            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
            height: 1; color: "#000000"
        }
        Row {
            anchors.centerIn: parent
            spacing: 56
            Image { source: "gfx/icon-list.svg"; width: 24; height: 24; smooth: true; opacity: 0.75 }
            Image { source: "gfx/icon-comment.svg"; width: 24; height: 24; smooth: true; opacity: 0.75 }
            Image { source: "gfx/tab-headphones.svg"; width: 24; height: 24; smooth: true; opacity: 0.75 }
        }
    }

    // ---- player body ----
    Column {
        id: stack
        anchors.top: header.bottom
        anchors.topMargin: 6
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width - 44
        spacing: 0

        Rectangle {
            id: cover
            width: 208; height: 208; radius: 12
            anchors.horizontalCenter: parent.horizontalCenter
            clip: true
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#6a4bd6" }
                GradientStop { position: 0.55; color: "#2a1d54" }
                GradientStop { position: 1.0; color: "#0e0a1f" }
            }
            Text {
                visible: player.currentCoverUrl === ""
                anchors.centerIn: parent
                width: parent.width - 24
                text: player.currentShow
                color: "#ffffff"; font.pixelSize: 22; font.bold: true
                horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
            }
            Image {
                anchors.fill: parent; fillMode: Image.PreserveAspectCrop; smooth: true
                sourceSize.width: 208; sourceSize.height: 208
                source: player.currentCoverUrl
            }
        }

        Item { width: 1; height: 22 }

        Text {
            width: parent.width
            text: player.currentShow
            font.pixelSize: 13; color: Theme.accentBright
            horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
        }

        Item { width: 1; height: 8 }

        Text {
            width: parent.width
            text: player.currentTitle
            font.pixelSize: 19; font.bold: true; color: Theme.text
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
        }

        Item { width: 1; height: 22 }

        // scrubber
        Item {
            width: parent.width; height: 13
            Rectangle {
                id: track
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left; anchors.right: parent.right
                height: 4; radius: 2; color: "#1FFFFFFF"

                Rectangle {
                    anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                    width: parent.width * page.progressRatio(); radius: 2
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Theme.accentDeep }
                        GradientStop { position: 1.0; color: Theme.accentBright }
                    }
                }
                Rectangle {
                    width: 13; height: 13; radius: 6.5; color: "#ffffff"
                    anchors.verticalCenter: parent.verticalCenter
                    x: (parent.width * page.progressRatio()) - 6.5
                }
            }
            MouseArea {
                anchors.fill: parent
                enabled: player.duration > 0
                onPressed: { page.scrubbing = true; page.scrubRatio = page.clamp01(mouse.x / width); }
                onPositionChanged: { if (page.scrubbing) page.scrubRatio = page.clamp01(mouse.x / width); }
                onReleased: {
                    if (player.duration > 0) player.seek(Math.round(page.scrubRatio * player.duration));
                    page.scrubbing = false;
                }
            }
        }

        Item { width: 1; height: 8 }

        Item {
            width: parent.width; height: 16
            Text {
                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                text: page.fmt(player.position); font.pixelSize: 12; color: Theme.textDim
            }
            Text {
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                text: player.duration > 0 ? page.remaining() : "--:--"
                font.pixelSize: 12; color: Theme.textDim
            }
        }

        Item { width: 1; height: 18 }

        // transport
        Item {
            width: parent.width; height: 72
            Row {
                anchors.centerIn: parent
                spacing: 24
                Item {
                    width: 44; height: 44; anchors.verticalCenter: parent.verticalCenter
                    Image { source: "gfx/icon-rewind.svg"; width: 34; height: 34; smooth: true; anchors.centerIn: parent }
                    Text { anchors.centerIn: parent; text: "15"; font.pixelSize: 9; font.bold: true; color: "#d6d6dd" }
                    MouseArea { anchors.fill: parent; onClicked: page.skip(-15000) }
                }
                Rectangle {
                    width: 72; height: 72; radius: 36; anchors.verticalCenter: parent.verticalCenter
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Theme.accentBright }
                        GradientStop { position: 1.0; color: Theme.accentDeep }
                    }
                    Image {
                        anchors.centerIn: parent; width: 30; height: 30; smooth: true
                        source: player.state === player.playingState ? "gfx/icon-pause-white.svg" : "gfx/icon-play-white.svg"
                    }
                    MouseArea { anchors.fill: parent; onClicked: page.togglePlay() }
                }
                Item {
                    width: 44; height: 44; anchors.verticalCenter: parent.verticalCenter
                    Image { source: "gfx/icon-forward.svg"; width: 34; height: 34; smooth: true; anchors.centerIn: parent }
                    Text { anchors.centerIn: parent; text: "30"; font.pixelSize: 9; font.bold: true; color: "#d6d6dd" }
                    MouseArea { anchors.fill: parent; onClicked: page.skip(30000) }
                }
            }
        }

        Item { width: 1; height: 18 }

        // meta chips (On device = real; speed = static placeholder)
        Item {
            width: parent.width; height: 28
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8
                Rectangle {
                    height: 28; radius: 14; color: "#00000000"
                    border.width: 1; border.color: "#668b6dff"
                    width: deviceRow.width + 24
                    Row {
                        id: deviceRow; anchors.centerIn: parent; spacing: 6
                        Image { source: "gfx/icon-check.svg"; width: 14; height: 14; smooth: true; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: qsTr("On device"); font.pixelSize: 12; color: Theme.accentBright; anchors.verticalCenter: parent.verticalCenter }
                    }
                }
                Rectangle {
                    height: 28; radius: 14; color: "#00000000"
                    border.width: 1; border.color: Theme.hairlineStrong
                    width: speedText.width + 24
                    Text { id: speedText; anchors.centerIn: parent; text: "1.0×"; font.pixelSize: 12; color: Theme.textDim }
                }
            }
        }
    }
}
```

- [ ] **Step 4: Register both QML files in `qml/qml.qrc`**

In `qml/qml.qrc`, after line 14 (`<file>EpisodePage.qml</file>`), add:

```xml
        <file>NowPlayingPage.qml</file>
        <file>MiniPlayer.qml</file>
```

- [ ] **Step 5: Mirror into `Xyz.pro` `OTHER_FILES`**

In `Xyz.pro`, after line 93 (`qml/EpisodePage.qml \`), add:

```pro
    qml/NowPlayingPage.qml \
    qml/MiniPlayer.qml \
```

- [ ] **Step 6: Add the shared `NowPlayingPage` + opener to `AppWindow.qml`**

In `qml/AppWindow.qml`, after the `function isLoggedIn()` block (lines 21–23), add:

```qml
    function openNowPlaying() {
        if (!pageStack.busy && pageStack.currentPage !== nowPlayingPage) {
            pageStack.push(nowPlayingPage);
        }
    }
```

Then declare the instance — after the `EpisodePage { id: episodePage }` block (lines 122–124), add:

```qml
    NowPlayingPage {
        id: nowPlayingPage
    }
```

- [ ] **Step 7: Wire Updates' expand request in `AppWindow.qml`**

In `qml/AppWindow.qml`, in the `UpdatesPage { id: updatesPage ... }` block (lines 107–115), add one handler alongside the existing `onEpisodeRequested`:

```qml
        onOpenPlayerRequested: window.openNowPlaying()
```

- [ ] **Step 8: Embed `MiniPlayer` in `UpdatesPage.qml`**

In `qml/UpdatesPage.qml`, add the signal next to the others (after line 16, `signal episodeRequested(variant item)`):

```qml
    signal openPlayerRequested
```

Re-anchor the feed `ListView` bottom (line 116) from:

```qml
        anchors.bottom: tabBar.top
```

to:

```qml
        anchors.bottom: miniPlayer.visible ? miniPlayer.top : tabBar.top
```

Then add the dock just before the `BelleTabBar` (before line 299, `BelleTabBar { id: tabBar ...`):

```qml
    MiniPlayer {
        id: miniPlayer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: tabBar.top
        onExpandRequested: page.openPlayerRequested()
    }

```

- [ ] **Step 9: Build the Simulator target**

Run: `pwsh scripts/build-simulator.ps1 -Config Debug`
Expected: build succeeds. A QML syntax slip (e.g. a function not at root) won't fail the C++ build but will error at runtime in the next step — watch the console there.

- [ ] **Step 10: Run and exercise the full flow**

Run: `pwsh build-simulator/debug/Xyz.run.ps1`
Verify, watching the console for QML warnings:
1. On Updates with nothing playing, **no** mini player is visible.
2. Open an episode → Play. Return to Updates (tab). The **mini player appears** above the tab bar with cover, title, and a `m:ss / m:ss` time that advances; the feed list shrinks to sit above it (nothing clipped).
3. The mini **play/pause toggle** flips the icon and audibly pauses/resumes; tapping it does **not** open Now Playing.
4. Tap the mini bar (not the button) → **Now Playing opens**: cover, show name, title, a scrubber whose fill + knob track playback, elapsed/-remaining times.
5. Drag the scrubber → playback **seeks** to the drop point. Rewind-15 / forward-30 move position by ~15s/30s. The big button toggles play/pause.
6. The down-chevron pops back to Updates with the mini player still docked.

- [ ] **Step 11: Commit**

```bash
git add qml/BelleHeader.qml qml/MiniPlayer.qml qml/NowPlayingPage.qml qml/AppWindow.qml qml/UpdatesPage.qml qml/qml.qrc Xyz.pro
git commit -m "feat(player): Now Playing page + mini player, wired on Updates"
```

---

### Task 4: Dock the mini player on Subscriptions, Me, and Episode

Replicates the Task 3 embedding on the remaining surfaces (the chosen "tab pages + Episode detail" scope). Each page re-anchors its content bottom to the dock and routes expand → `AppWindow.openNowPlaying()`.

**Files:**
- Modify: `qml/SubscriptionsPage.qml` (content at line 54–60, tab bar at 357)
- Modify: `qml/HomePage.qml` (tab bar at 152)
- Modify: `qml/EpisodePage.qml` (Flickable bottom at line 140)
- Modify: `qml/AppWindow.qml` (wire each page's `onOpenPlayerRequested`)

**Interfaces:**
- Consumes: `MiniPlayer` (`signal expandRequested`) and `AppWindow.openNowPlaying()` from Task 3.
- Produces: `signal openPlayerRequested` on `SubscriptionsPage`, `HomePage`, `EpisodePage`.

- [ ] **Step 1: Subscriptions — add signal, re-anchor content, dock**

In `qml/SubscriptionsPage.qml`, after line 15 (`signal tabSelected(int index)`), add:

```qml
    signal openPlayerRequested
```

Change the `content` `Item` bottom anchor (line 57) from:

```qml
        anchors.bottom: tabBar.top
```

to:

```qml
        anchors.bottom: miniPlayer.visible ? miniPlayer.top : tabBar.top
```

Add the dock immediately before `BelleTabBar { id: tabBar ...` (before line 357):

```qml
    MiniPlayer {
        id: miniPlayer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: tabBar.top
        onExpandRequested: page.openPlayerRequested()
    }

```

- [ ] **Step 2: Me (HomePage) — add signal, dock, re-anchor the Column**

In `qml/HomePage.qml`, after line 19 (`signal tabSelected(int index)`), add:

```qml
    signal openPlayerRequested
```

The account `Column` (line 53) is top-anchored, so it needs no bottom change, but constrain it so the dock never overlaps the buttons: change its bottom by adding a bottom anchor. Replace the `Column {` opening at line 53 and its first anchor lines (53–59) so the block reads:

```qml
    Column {
        anchors.top: header.bottom
        anchors.topMargin: 46
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Theme.pagePadding
        anchors.rightMargin: Theme.pagePadding
        spacing: 8
```

(unchanged — the account content is short and top-aligned, so no bottom clipping occurs). Then add the dock before `BelleTabBar { id: tabBar ...` (before line 152):

```qml
    MiniPlayer {
        id: miniPlayer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: tabBar.top
        onExpandRequested: page.openPlayerRequested()
    }

```

- [ ] **Step 3: Episode — add signal, dock at the bottom, re-anchor the Flickable**

In `qml/EpisodePage.qml`, after the property block, add the signal near the top of the page body — after line 12 (`property bool hidesToolBar: true`):

```qml
    signal openPlayerRequested
```

Change the `Flickable` bottom anchor (line 140) from:

```qml
        anchors.bottom: parent.bottom
```

to:

```qml
        anchors.bottom: miniPlayer.visible ? miniPlayer.top : parent.bottom
```

Add the dock as the last child before the closing brace of the page (after the `confirmDelete` `Item` block ends at line 687, before the final `}` on line 688):

```qml
    MiniPlayer {
        id: miniPlayer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        onExpandRequested: page.openPlayerRequested()
    }
```

- [ ] **Step 4: Wire the three pages in `AppWindow.qml`**

In `qml/AppWindow.qml`, add `onOpenPlayerRequested: window.openNowPlaying()` to each block:
- `SubscriptionsPage { id: subscriptionsPage ... }` (lines 117–120)
- `HomePage { id: homePage ... }` (lines 97–105)
- `EpisodePage { id: episodePage }` (lines 122–124) — this one currently has no handlers, so it becomes:

```qml
    EpisodePage {
        id: episodePage
        onOpenPlayerRequested: window.openNowPlaying()
    }
```

- [ ] **Step 5: Build the Simulator target**

Run: `pwsh scripts/build-simulator.ps1 -Config Debug`
Expected: build succeeds.

- [ ] **Step 6: Run and verify the dock on every surface**

Run: `pwsh build-simulator/debug/Xyz.run.ps1`
With an episode playing, visit each surface and confirm the mini player docks correctly and expands:
1. **Subscriptions** (Updates → My Subscriptions): dock above the tab bar; grid/list content not clipped; tap → Now Playing.
2. **Me** (person tab): dock above the tab bar; account content unaffected; tap → Now Playing.
3. **Episode detail** (open a *different* episode while one plays): dock at the very bottom; show-notes/comments scroll above it; tap → Now Playing for the *playing* track.
4. Pop back from Now Playing each time; the dock persists.

- [ ] **Step 7: Capture a Simulator screenshot of the Now Playing page**

Per the project's `screenshot-running-simulator` note, capture the running `Qt Simulator` window showing Now Playing (and one showing a docked mini player) for the record. Save under the scratchpad or attach to the task summary.

- [ ] **Step 8: Commit**

```bash
git add qml/SubscriptionsPage.qml qml/HomePage.qml qml/EpisodePage.qml qml/AppWindow.qml
git commit -m "feat(player): dock mini player on Subscriptions, Me, and Episode"
```

---

## Self-Review

**1. Spec coverage:**
- PlayerController `currentCoverUrl`/`currentShow` + `playEpisode` arity (spec component 1) → Task 1. ✓
- `BelleHeader.leadIconSource` (spec component 2) → Task 3 Step 1. ✓
- `NowPlayingPage` mapping cover/show/title/scrubber+seek/transport/chips/toolbar (spec component 3) → Task 3 Step 3. ✓
- `MiniPlayer` visibility + layout + `expandRequested` (spec component 4) → Task 3 Step 2. ✓
- Navigation: `openPlayerRequested` → `AppWindow` push (spec component 5) → Task 3 Steps 6–8, Task 4. ✓
- Host-page embedding on Updates/Subscriptions/Me/Episode + re-anchor (spec component 6) → Task 3 Step 8, Task 4 Steps 1–3. ✓
- New assets + qrc (spec component 7) → Task 2; QML registration in Task 3 Steps 4–5. ✓
- Wired vs placeholder split (spec) → live transport/scrubber in Task 3 Step 3; speed/toolbar static, comment chip omitted per Global Constraints. ✓
- Edge cases: `duration === 0` → `--:--` + disabled scrubber (Task 3 Step 3); idle → mini hidden (Task 3 Step 2). ✓
- Verification: Simulator build + interactive flow + screenshot (spec) → Task 1 Steps 9–10, Task 3 Steps 9–10, Task 4 Steps 5–7. ✓

**2. Placeholder scan:** No "TBD"/"add error handling"/"similar to Task N". Every code step shows full content. The "static placeholder" UI items are an explicit, approved design decision, not plan gaps.

**3. Type consistency:** `playEpisode(url, eid, title, coverUrl, show)` defined (Task 1 Steps 3, 6) and called identically (Task 1 Step 7). `currentCoverUrl`/`currentShow` property + accessor + member + signal names consistent across Task 1 Steps 1–6 and consumed as `player.currentCoverUrl`/`player.currentShow` in Task 3. `expandRequested` emitted in `MiniPlayer` (Task 3 Step 2) and handled as `onExpandRequested` (Task 3 Step 8, Task 4). `openPlayerRequested` declared per page and handled as `onOpenPlayerRequested` in `AppWindow`. `openNowPlaying()` defined once (Task 3 Step 6), called everywhere. `leadIconSource` default matches the original hardcoded `gfx/icon-back.svg`. ✓

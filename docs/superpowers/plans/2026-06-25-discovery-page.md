# Discovery Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Discovery page (发现) reachable from the compass tab, showing four recommendation sections sourced from the official discovery feed, with episode cards that tap through to the existing `EpisodePage`.

**Architecture:** A new `fetchDiscovery()` on the native `XyzApiClient` chains **three sequential** `POST /v1/discovery-feed/list` calls (default → `discoveryTopic` → `mediumDiscoveryPictorial`) — sequential because the client is single-reply (`m_reply` + `abortActiveRequest()` cancels any in-flight call). Each reply is shaped into ordered section buckets; only `targetType=="EPISODE"` modules are kept. A new `discoverySections` property feeds a QML `DiscoveryPage.qml` that renders section headers + episode cards (ported from the design's `.card`). The compass tab (index 0), currently inert, is wired to push the page.

**Tech Stack:** Qt 4.7 / C++ (native client, vendored qjson), QML 1.1 + Symbian Components 1.1, PowerShell mock + Qt Simulator for verification.

## Global Constraints

- **QML 1.1 only:** no block expressions in property bindings (use ternary/helper); no named function declarations inside non-root elements (declare at `Page` root only); no negative anchor margins; all `font.pixelSize` values are **integers**.
- **Never write the `position` property on a QML `Audio` element** (irrelevant here — playback goes through `audioEngine`/`player`, untouched by this work).
- **Cover images:** real `Image { source: modelData.coverUrl }` over HTTPS (the engine's `SslIgnoringNam` handles cert errors). Use `sourceSize` hints.
- **Type scale (device-readable):** card title ~16–17, show line ~13, meta ~13–14, section title ~18–20. Do **not** copy the smaller mock CSS px values verbatim.
- **String table:** native shaping reuses existing helpers (`pickImageUrl`, `relativeTime`, the `(durationSec + 30) / 60` minute formatter, the `>99 → "99+"` comment rule). Do not duplicate them.
- **No unit-test harness exists in this repo.** Verification is **build-clean + mock-driven Qt Simulator run + visual confirmation** (per the project's established pattern — `scripts/mock-content.ps1`), plus a dated `docs/DEVICE_NOTES.md` entry. This is intentional, not an omission.

---

## File Structure

- `src/XyzApiClient.h` — add discovery property/signal, request enum values, members, method decls.
- `src/XyzApiClient.cpp` — add `fetchDiscovery()`, sequential-chain helpers, shaping; extend `onReplyFinished()` dispatch + discovery-aware error routing.
- `scripts/mock-content.ps1` — add a body-aware discovery branch returning three distinct **officially-nested** payloads.
- `qml/DiscoveryPage.qml` — **new** page: section list + episode cards + states + tab bar + mini player.
- `qml/qml.qrc` — register `DiscoveryPage.qml`.
- `qml/AppWindow.qml` — instantiate `DiscoveryPage`, wire `handleTab(0)`.
- `docs/DEVICE_NOTES.md` — dated verification entry.

---

## Task 1: Native client — `fetchDiscovery()` + sequential chaining + shaping

**Files:**
- Modify: `src/XyzApiClient.h`
- Modify: `src/XyzApiClient.cpp`

**Interfaces:**
- Consumes: existing `startPost()`, `pickImageUrl()`, `relativeTime()`, `setBusy()`, `setErrorMessage()`, `onReplyFinished()`.
- Produces (relied on by Task 3):
  - QML property `QVariantList discoverySections` + signal `discoveryLoaded()`.
  - `Q_INVOKABLE void fetchDiscovery()`.
  - Each section map: `{ "title": QString, "subtitle": QString, "items": QVariantList }`.
  - Each item map: `{ "eid", "coverUrl", "title", "showName", "durationText", "whenText", "commentCount" }` (all QString) — a superset of what `EpisodePage.openWith` seeds.

- [ ] **Step 1: Declare the property, signal, enum values, methods, and members in the header**

In `src/XyzApiClient.h`, add the property after the `hasMoreComments` property (line 27):

```cpp
    Q_PROPERTY(QVariantList discoverySections READ discoverySections NOTIFY discoveryLoaded)
```

Add the getter after `hasMoreComments()` (line 39):

```cpp
    QVariantList discoverySections() const;
```

Add the invokable after `loadMoreComments()` (line 46):

```cpp
    Q_INVOKABLE void fetchDiscovery();
```

Add the signal after `commentsLoaded();` (line 54):

```cpp
    void discoveryLoaded();
```

Extend the `RequestType` enum (line 63-64) to:

```cpp
    enum RequestType { NoneRequest, InboxRequest, SubscriptionsRequest,
                       EpisodeRequest, CommentsRequest, MoreCommentsRequest,
                       DiscoveryDefault, DiscoveryTopic, DiscoveryHot };
```

Add method decls in the private helpers block, after `shapeComment(...)` (line 76):

```cpp
    void startDiscoveryPhase(int phase);
    void finishDiscoveryPhase(const QVariantList &sections);
    QVariantList shapeDiscoverySections(const QVariant &root) const;
    QVariantMap shapeDiscoveryEpisode(const QVariantMap &episode) const;
```

Add members after `m_commentsTotal;` (line 95):

```cpp
    QVariantList m_discoverySections;
    QVariantList m_discBuckets[3];
    int m_discPhase;
```

- [ ] **Step 2: Initialize `m_discPhase` and add the getter in the .cpp**

In `src/XyzApiClient.cpp`, add `m_discPhase(0)` to the constructor initializer list (after `m_commentsTotal(0)` on line 48):

```cpp
    , m_commentsTotal(0)
    , m_discPhase(0)
```

Add the getter next to the others (after line 61):

```cpp
QVariantList XyzApiClient::discoverySections() const { return m_discoverySections; }
```

- [ ] **Step 3: Add `fetchDiscovery()` and the two chaining helpers**

In `src/XyzApiClient.cpp`, after `loadMoreComments()` (line 126), add:

```cpp
// Discovery feed: three sequential POSTs to the same endpoint, each selecting a
// different set of sections via loadMoreKey. Sequential (not concurrent) because the
// client is single-reply. Results land in ordered buckets and emit once at the end.
void XyzApiClient::fetchDiscovery()
{
    m_discBuckets[0].clear();
    m_discBuckets[1].clear();
    m_discBuckets[2].clear();
    m_discPhase = 0;
    startDiscoveryPhase(0);
}

void XyzApiClient::startDiscoveryPhase(int phase)
{
    QVariantMap body;
    body.insert(QString::fromLatin1("returnAll"), QString::fromLatin1("false"));
    RequestType type = DiscoveryDefault;
    if (phase == 1) {
        body.insert(QString::fromLatin1("loadMoreKey"), QString::fromLatin1("discoveryTopic"));
        type = DiscoveryTopic;
    } else if (phase == 2) {
        body.insert(QString::fromLatin1("loadMoreKey"), QString::fromLatin1("mediumDiscoveryPictorial"));
        type = DiscoveryHot;
    }
    startPost(type, QString::fromLatin1("/v1/discovery-feed/list"), body);
}

// Store this phase's sections, then either fire the next phase or finalize + emit.
void XyzApiClient::finishDiscoveryPhase(const QVariantList &sections)
{
    if (m_discPhase >= 0 && m_discPhase < 3) {
        m_discBuckets[m_discPhase] = sections;
    }
    if (m_discPhase < 2) {
        ++m_discPhase;
        startDiscoveryPhase(m_discPhase);   // keeps busy == true across the chain
        return;
    }
    QVariantList all;
    all += m_discBuckets[0];
    all += m_discBuckets[1];
    all += m_discBuckets[2];
    m_discoverySections = all;
    setBusy(false);
    if (all.isEmpty() && m_errorMessage.isEmpty()) {
        setErrorMessage(QString::fromLatin1("No discovery content."));
    }
    emit discoveryLoaded();
}
```

- [ ] **Step 4: Dispatch discovery replies (success + error routing) in `onReplyFinished()`**

In `src/XyzApiClient.cpp`, just after the line `m_requestType = NoneRequest;` (line 251), add the discovery flag:

```cpp
    const bool isDiscovery = (type == DiscoveryDefault || type == DiscoveryTopic || type == DiscoveryHot);
```

In the non-2xx error block, make the discovery chain tolerant — add this as the **first** statement inside `if (statusCode < 200 || statusCode >= 300) {` (line 263), before `QString detail;`:

```cpp
        if (isDiscovery) { finishDiscoveryPhase(QVariantList()); return; }
```

In the parse-failure block, add the same guard as the **first** statement inside `if (!ok) {` (line 294), before `setErrorMessage(...)`:

```cpp
        if (isDiscovery) { finishDiscoveryPhase(QVariantList()); return; }
```

Add the success dispatch — place it right before the final `setBusy(false);` at the end of `onReplyFinished()` (line 361), after the comments block:

```cpp
    if (isDiscovery) {
        finishDiscoveryPhase(shapeDiscoverySections(root));
        return;
    }
```

(401 is intentionally left to the existing global `sessionExpired` path — an expired token should stop the chain and re-login.)

- [ ] **Step 5: Add the shaping functions**

In `src/XyzApiClient.cpp`, after `shapeComment()` (end of file, line 564), add:

```cpp
// Discovery responses are double-nested: data.data[] holds feed entries; each
// DISCOVERY_COLLECTION entry holds a data[] of modules. We keep only EPISODE-target
// modules (episode-only decision) and turn each into a {title, subtitle, items} section.
QVariantList XyzApiClient::shapeDiscoverySections(const QVariant &root) const
{
    QVariantList sections;
    const QVariantMap top = root.toMap();
    const QVariantList entries = top.value(QString::fromLatin1("data")).toMap()
                                    .value(QString::fromLatin1("data")).toList();
    for (int i = 0; i < entries.size(); ++i) {
        const QVariantMap entry = entries.at(i).toMap();
        if (entry.value(QString::fromLatin1("type")).toString()
            != QString::fromLatin1("DISCOVERY_COLLECTION")) {
            continue;   // skip NEW_POWER and other non-collection entries
        }
        const QVariantList modules = entry.value(QString::fromLatin1("data")).toList();
        for (int j = 0; j < modules.size(); ++j) {
            const QVariantMap mod = modules.at(j).toMap();
            if (mod.value(QString::fromLatin1("targetType")).toString()
                != QString::fromLatin1("EPISODE")) {
                continue;   // skip PODCAST modules — no podcast detail page yet
            }
            QVariantList items;
            const QVariantList targets = mod.value(QString::fromLatin1("target")).toList();
            for (int k = 0; k < targets.size(); ++k) {
                const QVariantMap episode = targets.at(k).toMap()
                                               .value(QString::fromLatin1("episode")).toMap();
                if (episode.isEmpty()) {
                    continue;
                }
                items.append(shapeDiscoveryEpisode(episode));
            }
            if (items.isEmpty()) {
                continue;
            }
            QVariantMap section;
            section.insert(QString::fromLatin1("title"),
                           mod.value(QString::fromLatin1("title")).toString());
            section.insert(QString::fromLatin1("subtitle"),
                           mod.value(QString::fromLatin1("description")).toString());
            section.insert(QString::fromLatin1("items"), items);
            sections.append(section);
        }
    }
    return sections;
}

// One episode → the card/tap map. Superset of EpisodePage.openWith's seed; showName
// and commentCount drive the card foot.
QVariantMap XyzApiClient::shapeDiscoveryEpisode(const QVariantMap &episode) const
{
    QVariantMap out;
    out.insert(QString::fromLatin1("eid"), episode.value(QString::fromLatin1("eid")).toString());

    QString cover = pickImageUrl(episode.value(QString::fromLatin1("image")).toMap());
    const QVariantMap podcast = episode.value(QString::fromLatin1("podcast")).toMap();
    if (cover.isEmpty()) {
        cover = pickImageUrl(podcast.value(QString::fromLatin1("image")).toMap());
    }
    out.insert(QString::fromLatin1("coverUrl"), cover);
    out.insert(QString::fromLatin1("title"), episode.value(QString::fromLatin1("title")).toString());
    out.insert(QString::fromLatin1("showName"), podcast.value(QString::fromLatin1("title")).toString());

    const int durationSec = episode.value(QString::fromLatin1("duration")).toInt();
    out.insert(QString::fromLatin1("durationText"),
               QString::fromLatin1("%1 min").arg((durationSec + 30) / 60));
    out.insert(QString::fromLatin1("whenText"),
               relativeTime(episode.value(QString::fromLatin1("pubDate")).toString()));

    const int comments = episode.value(QString::fromLatin1("commentCount")).toInt();
    out.insert(QString::fromLatin1("commentCount"),
               comments > 99 ? QString::fromLatin1("99+") : QString::number(comments));
    return out;
}
```

- [ ] **Step 6: Build the simulator target and confirm it compiles clean**

Run:
```
pwsh -File scripts/build-simulator.ps1 -Config Debug
```
Expected: ends with `[INFO] Build succeeded: ...\Xyz.exe` and no compiler errors. (This is the deliverable check — there is no unit-test target.)

- [ ] **Step 7: Commit**

```bash
git add src/XyzApiClient.h src/XyzApiClient.cpp
git commit -m "feat(discovery): native fetchDiscovery with 3-call sequential chaining + shaping"
```

---

## Task 2: Mock discovery endpoint in `scripts/mock-content.ps1`

**Files:**
- Modify: `scripts/mock-content.ps1`

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: `POST /v1/discovery-feed/list` returns three distinct **officially-nested** payloads selected by the request body's `loadMoreKey` — used to verify Task 1 + Task 3 in the simulator.

- [ ] **Step 1: Add three nested discovery payloads**

In `scripts/mock-content.ps1`, after the `$comments = ... ConvertTo-Json` block (line 54), add:

```powershell
# discovery-feed/list is double-nested (data.data[]) and selected by loadMoreKey.
function New-DiscEpisode($eid, $title, $show, $dur, $when, $comments) {
  @{ episode = @{ type="EPISODE"; eid=$eid; title=$title; duration=$dur;
       pubDate=$when; commentCount=$comments;
       image=@{ thumbnailUrl=$img; smallPicUrl=$img };
       podcast=@{ title=$show; image=@{ smallPicUrl=$img; thumbnailUrl=$img } } };
     recommendation="" }
}
function New-DiscModule($title, $desc, $items) {
  @{ title=$title; moduleType="X"; targetType="EPISODE"; description=$desc; target=$items }
}
function New-DiscPayload($modules) {
  @{ code=200; msg="OK"; data=@{ data=@(
       @{ type="DISCOVERY_COLLECTION"; data=$modules }
     ); loadMoreKey="pick" } } | ConvertTo-Json -Depth 12
}

$discDefault = New-DiscPayload @(
  (New-DiscModule "大家都在听" "" @(
     (New-DiscEpisode "d1" "Why we drift toward the cosmos" "Cosmic Drift" 3480 "2026-06-23T09:00:00.000Z" 1200),
     (New-DiscEpisode "d2" "Three years remote, five lessons" "Code & Coffee" 2520 "2026-06-24T09:00:00.000Z" 863))),
  (New-DiscModule "编辑精选" "Hand-picked by our editors" @(
     (New-DiscEpisode "d3" "Songs that quietly healed you" "Late Night Radio" 3960 "2026-06-21T09:00:00.000Z" 2400)))
)
$discTopic = New-DiscPayload @(
  (New-DiscModule "中年人运动全面指南" "How do we approach movement in our prime years?" @(
     (New-DiscEpisode "d4" "After 100km across one city" "City Walks" 2220 "2026-06-20T09:00:00.000Z" 517),
     (New-DiscEpisode "d5" "If a black hole could speak" "Interstellar Nights" 2940 "2026-06-18T09:00:00.000Z" 1000)))
)
$discHot = New-DiscPayload @(
  (New-DiscModule "最热榜" "" @(
     (New-DiscEpisode "d6" "The science of flavor in a pour-over" "Useless Beauty" 1980 "2026-06-17T09:00:00.000Z" 402)))
)
```

- [ ] **Step 2: Route the discovery path by reading the request body**

In the request loop, add a discovery branch **before** the existing `$body = if (...)` chain (line 80). Replace lines 80-83:

```powershell
  $body = if ($path -like "*subscription*") { $subs }
          elseif ($path -like "*episode*") { $episode }
          elseif ($path -like "*comment*") { $comments }
          else { $inbox }
```

with:

```powershell
  $body = if ($path -like "*discovery-feed*") {
            $reader = New-Object System.IO.StreamReader($ctx.Request.InputStream)
            $raw = $reader.ReadToEnd(); $reader.Close()
            if ($raw -like "*discoveryTopic*") { $discTopic }
            elseif ($raw -like "*mediumDiscoveryPictorial*") { $discHot }
            else { $discDefault }
          }
          elseif ($path -like "*subscription*") { $subs }
          elseif ($path -like "*episode*") { $episode }
          elseif ($path -like "*comment*") { $comments }
          else { $inbox }
```

- [ ] **Step 3: Verify the mock returns the three distinct payloads**

Start the mock in one shell:
```
pwsh -File scripts/mock-content.ps1
```
In another shell, confirm each loadMoreKey selects the right section title:
```
(Invoke-WebRequest -Method Post -Uri http://localhost:8099/v1/discovery-feed/list -Body '{"returnAll":"false"}' -ContentType 'application/json').Content
(Invoke-WebRequest -Method Post -Uri http://localhost:8099/v1/discovery-feed/list -Body '{"loadMoreKey":"discoveryTopic"}' -ContentType 'application/json').Content
(Invoke-WebRequest -Method Post -Uri http://localhost:8099/v1/discovery-feed/list -Body '{"loadMoreKey":"mediumDiscoveryPictorial"}' -ContentType 'application/json').Content
```
Expected: the first contains `大家都在听` and `编辑精选`; the second contains `中年人运动全面指南`; the third contains `最热榜`. Each is shaped `data.data[0].data[].target[].episode`. Stop the mock (Ctrl+C) when done.

- [ ] **Step 4: Commit**

```bash
git add scripts/mock-content.ps1
git commit -m "test(discovery): body-aware discovery-feed mock with 3 nested payloads"
```

---

## Task 3: `DiscoveryPage.qml` + qrc registration + navigation wiring + end-to-end verification

**Files:**
- Create: `qml/DiscoveryPage.qml`
- Modify: `qml/qml.qrc`
- Modify: `qml/AppWindow.qml`
- Modify: `docs/DEVICE_NOTES.md`

**Interfaces:**
- Consumes (from Task 1): `xyzApi.fetchDiscovery()`, `xyzApi.discoverySections`, `xyzApi.discoveryLoaded`, `xyzApi.busy`, `xyzApi.errorMessage`; each section `{title, subtitle, items[]}`, each item `{eid, coverUrl, title, showName, durationText, whenText, commentCount}`.
- Consumes (existing): `EpisodePage.openWith(item)`, `BelleTabBar`, `MiniPlayer`, `Theme.js`.
- Produces: a `DiscoveryPage` reachable via the compass tab; `episodeRequested(item)` bubbled to `AppWindow`.

- [ ] **Step 1: Create `qml/DiscoveryPage.qml`**

This mirrors `UpdatesPage.qml`'s structure (load-guard, states, tab bar, mini player) and ports the design's `.sec-head` + `.card`. Note the QML-1.1-safe nested model: the outer `Repeater` iterates sections; an inner `Repeater` iterates `modelData.items`. Inner delegates reference the section via a captured `property var section` to avoid `modelData` shadowing.

```qml
import QtQuick 1.1
import com.nokia.symbian 1.1
import "js/Theme.js" as Theme

// Discovery — recommendation feed (design: screens-feed.jsx FeedCards).
// Sections from /v1/discovery-feed/list (3 calls) via the native xyzApi client.
Page {
    id: page
    objectName: "DiscoveryPage"

    property bool hidesToolBar: true
    property bool loadedOnce: false

    signal tabSelected(int index)
    signal episodeRequested(variant item)
    signal openPlayerRequested

    function load() {
        if (page.loadedOnce) {
            return;
        }
        xyzApi.fetchDiscovery();
    }

    onStatusChanged: {
        if (status === PageStatus.Active) {
            page.load();
        }
    }

    // Mark loaded only on success, so an aborted/failed chain retries on next activation.
    Connections {
        target: xyzApi
        onDiscoveryLoaded: page.loadedOnce = true
    }

    Rectangle { anchors.fill: parent; color: Theme.bg }

    // ---- glossy title bar ----
    Rectangle {
        id: titleBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 56
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.chromeHi }
            GradientStop { position: 0.06; color: "#232328" }
            GradientStop { position: 0.6; color: "#1a1a1e" }
            GradientStop { position: 1.0; color: Theme.chromeLo }
        }
        Text {
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            text: qsTr("Discover")
            font.pixelSize: 24
            font.bold: true
            color: Theme.text
        }
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: "#000000"
        }
    }

    // ---- sections ----
    Flickable {
        id: scroller
        anchors.top: titleBar.bottom
        anchors.bottom: miniPlayer.visible ? miniPlayer.top : tabBar.top
        anchors.left: parent.left
        anchors.right: parent.right
        clip: true
        contentWidth: width
        contentHeight: sectionsColumn.height

        Column {
            id: sectionsColumn
            width: scroller.width

            Repeater {
                model: xyzApi.discoverySections

                // One section: header (title + optional subtitle) then its episode cards.
                Column {
                    width: sectionsColumn.width
                    property variant section: modelData

                    // section header
                    Item {
                        width: parent.width
                        height: secCol.height + 28
                        Column {
                            id: secCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
                            anchors.top: parent.top
                            anchors.topMargin: 18
                            spacing: 5
                            Text {
                                width: parent.width
                                text: section.title
                                font.pixelSize: 19
                                font.bold: true
                                color: Theme.accentBright
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                visible: section.subtitle.length > 0
                                text: section.subtitle
                                font.pixelSize: 13
                                color: Theme.textDim
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }
                        }
                    }

                    // episode cards
                    Repeater {
                        model: section.items

                        Item {
                            width: sectionsColumn.width
                            height: card.height + 10

                            Rectangle {
                                id: card
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                height: cardCol.height
                                radius: 8
                                border.width: 1
                                border.color: Theme.hairline
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: Theme.panel2 }
                                    GradientStop { position: 1.0; color: Theme.panel }
                                }

                                Column {
                                    id: cardCol
                                    anchors.left: parent.left
                                    anchors.right: parent.right

                                    // card top: cover + show + title
                                    Item {
                                        width: parent.width
                                        height: cardTop.height + 24
                                        Row {
                                            id: cardTop
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.leftMargin: 12
                                            anchors.rightMargin: 12
                                            anchors.top: parent.top
                                            anchors.topMargin: 12
                                            spacing: 12

                                            Rectangle {
                                                width: 76
                                                height: 76
                                                radius: 7
                                                color: "#1a1a22"
                                                clip: true
                                                Image {
                                                    anchors.fill: parent
                                                    fillMode: Image.PreserveAspectCrop
                                                    smooth: true
                                                    sourceSize.width: 76
                                                    sourceSize.height: 76
                                                    source: modelData.coverUrl
                                                }
                                            }
                                            Column {
                                                width: parent.width - 88
                                                spacing: 5
                                                Text {
                                                    width: parent.width
                                                    text: modelData.showName
                                                    font.pixelSize: 13
                                                    color: Theme.accentBright
                                                    elide: Text.ElideRight
                                                }
                                                Text {
                                                    width: parent.width
                                                    text: modelData.title
                                                    font.pixelSize: 16
                                                    font.bold: true
                                                    color: Theme.text
                                                    wrapMode: Text.WordWrap
                                                    maximumLineCount: 3
                                                    elide: Text.ElideRight
                                                }
                                            }
                                        }
                                    }

                                    // card foot: duration · comments · when
                                    Rectangle {
                                        width: parent.width
                                        height: 1
                                        color: Theme.hairline
                                    }
                                    Item {
                                        width: parent.width
                                        height: 40
                                        Row {
                                            anchors.left: parent.left
                                            anchors.leftMargin: 12
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 14
                                            Row {
                                                spacing: 5
                                                anchors.verticalCenter: parent.verticalCenter
                                                Image { source: "gfx/tab-headphones.svg"; width: 15; height: 15; smooth: true; opacity: 0.7; anchors.verticalCenter: parent.verticalCenter }
                                                Text { text: modelData.durationText; font.pixelSize: 13; color: Theme.textDim; anchors.verticalCenter: parent.verticalCenter }
                                            }
                                            Row {
                                                spacing: 5
                                                anchors.verticalCenter: parent.verticalCenter
                                                Image { source: "gfx/icon-comment.svg"; width: 15; height: 15; smooth: true; opacity: 0.7; anchors.verticalCenter: parent.verticalCenter }
                                                Text { text: modelData.commentCount; font.pixelSize: 13; color: Theme.textDim; anchors.verticalCenter: parent.verticalCenter }
                                            }
                                        }
                                        Text {
                                            anchors.right: parent.right
                                            anchors.rightMargin: 12
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: modelData.whenText
                                            font.pixelSize: 13
                                            color: Theme.textFaint
                                        }
                                    }
                                }
                            }

                            // press feedback (non-interactive wash) + single whole-card
                            // tap target on top. Card content (Text/Image) never grabs the
                            // mouse, so one MouseArea catches a tap anywhere on the card.
                            Rectangle {
                                anchors.fill: card
                                radius: 8
                                color: Theme.accent
                                opacity: cardTap.pressed ? 0.10 : 0
                            }
                            MouseArea {
                                id: cardTap
                                anchors.fill: card
                                onClicked: page.episodeRequested(modelData)
                            }
                        }
                    }
                }
            }

            // bottom spacer so the last card clears the toolbar
            Item { width: parent.width; height: 16 }
        }
    }

    // ---- states ----
    BusyIndicator {
        running: xyzApi.busy && xyzApi.discoverySections.length === 0
        visible: running
        width: 48
        height: 48
        anchors.centerIn: scroller
    }
    Text {
        visible: !xyzApi.busy && xyzApi.errorMessage.length > 0 && xyzApi.discoverySections.length === 0
        anchors.centerIn: scroller
        width: scroller.width - 48
        text: xyzApi.errorMessage
        color: Theme.errorColor
        font.pixelSize: 13
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
    }
    Text {
        visible: !xyzApi.busy && xyzApi.errorMessage.length === 0 && xyzApi.discoverySections.length === 0 && page.loadedOnce
        anchors.centerIn: scroller
        text: qsTr("Nothing to discover yet")
        color: Theme.textDim
        font.pixelSize: 14
    }

    MiniPlayer {
        id: miniPlayer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: tabBar.top
        onExpandRequested: page.openPlayerRequested()
    }

    BelleTabBar {
        id: tabBar
        activeIndex: 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        onTabSelected: page.tabSelected(index)
    }
}
```

- [ ] **Step 2: Register the page in `qml/qml.qrc`**

Add after the `UpdatesPage.qml` line (line 12):

```xml
        <file>DiscoveryPage.qml</file>
```

- [ ] **Step 3: Instantiate and wire the page in `qml/AppWindow.qml`**

Add the instance after the `UpdatesPage { ... }` block (after line 156):

```qml
    DiscoveryPage {
        id: discoveryPage
        onTabSelected: window.handleTab(index)
        onEpisodeRequested: {
            episodePage.openWith(item);
            pageStack.push(episodePage);
        }
        onOpenPlayerRequested: window.openNowPlaying()
    }
```

Replace the `handleTab` body (lines 54-65) — wire index 0, and from the Discovery page index 1 must `pop` back to Updates like other non-Updates pages. New body:

```qml
    function handleTab(index) {
        if (index === 0) {
            if (!pageStack.busy && pageStack.currentPage !== discoveryPage) {
                pageStack.push(discoveryPage);
            }
        } else if (index === 1) {
            while (pageStack.currentPage !== updatesPage && pageStack.depth > 1) {
                pageStack.pop();
            }
        } else if (index === 2) {
            if (!pageStack.busy && pageStack.currentPage !== homePage) {
                pageStack.push(homePage);
            }
        }
    }
```

- [ ] **Step 4: Build**

Run:
```
pwsh -File scripts/build-simulator.ps1 -Config Debug
```
Expected: `[INFO] Build succeeded: ...\Xyz.exe`. (The `.qrc` change is compiled in; QML syntax is validated at runtime in Step 5.)

- [ ] **Step 5: Run the end-to-end flow in the simulator against the mock**

Per the screenshot-running-simulator + verify-QML-flow memories — a build is **not** proof; run it.

1. Start the mock: `pwsh -File scripts/mock-content.ps1`
2. In the app's shell set the base + a stored token so content calls are authorized:
   `$env:XYZ_API_BASE = "http://localhost:8099"`
   (Sign in via the SMS flow against the auth mock if needed, or seed `auth.accessToken` in storage; the mock ignores the token value.)
3. Launch the built `Xyz.exe` with the simulator runtime on PATH + `QT_PLUGIN_PATH` (use the generated `build-simulator/debug/Xyz.run.ps1` launcher).
4. Tap the **compass tab (left)**. Confirm:
   - Four sections render in order: **大家都在听**, **编辑精选**, **中年人运动全面指南** (with its subtitle), **最热榜**.
   - The subtitle line appears only on the topic section.
   - Cover thumbnails load over HTTP(S).
   - Tapping a card opens `EpisodePage` with the correct title/cover seeded; back returns to Discovery.
   - Switching to Updates (middle tab) and back to Discovery does not refetch (loadedOnce guard) and shows no flicker.
5. Capture a screenshot of the Discovery page (PrintWindow on the `Qt Simulator` window) for the record.

Expected: all four checks pass. If a section is missing, inspect the raw mock response shape (`data.data[].data[].target[].episode`) against `shapeDiscoverySections`.

- [ ] **Step 6: Record the verification in `docs/DEVICE_NOTES.md`**

Append a dated entry:

```markdown
## 2026-06-25 — Discovery page (multi-section discovery-feed)

Implemented the Discovery tab: `xyzApi.fetchDiscovery()` chains 3 sequential
`POST /v1/discovery-feed/list` calls (default, `discoveryTopic`,
`mediumDiscoveryPictorial`) — sequential because the client is single-reply.
Episode-only: only `targetType=="EPISODE"` modules become sections; PODCAST
modules are skipped (no podcast detail page). Response is double-nested
(`data.data[]`), unlike inbox's single `data[]`.

Verified in the Qt Simulator against `scripts/mock-content.ps1` (body-aware
discovery branch): four sections render in order, topic subtitle shows, covers
load, cards tap through to EpisodePage. [Attach screenshot path.]

Not yet tested on real device / live API — verify section titles + nesting
against the live endpoint before trusting (mock has diverged from real before).
```

- [ ] **Step 7: Commit**

```bash
git add qml/DiscoveryPage.qml qml/qml.qrc qml/AppWindow.qml docs/DEVICE_NOTES.md
git commit -m "feat(discovery): DiscoveryPage UI + compass-tab wiring"
```

---

## Self-Review

**Spec coverage:**
- 4 sections / 3 aggregated calls → Task 1 (`fetchDiscovery` chain) + Task 2 (mock). ✓
- Episode-only filtering → Task 1 `shapeDiscoverySections` (`targetType=="EPISODE"`). ✓
- Live API section titles → Task 1 uses `mod.value("title")`. ✓
- Real cover images → Task 3 card `Image { source: modelData.coverUrl }`. ✓
- Card → EpisodePage tap-through with superset map → Task 1 item shape + Task 3 `episodeRequested` + AppWindow `openWith`. ✓
- Compass tab wiring (index 0 no longer inert) → Task 3 `handleTab`. ✓
- Error only if all 3 fail; partial render → Task 1 `finishDiscoveryPhase` tolerant routing. ✓
- BusyIndicator / error / empty states → Task 3 states block. ✓
- Header "Discover/发现", subtitle from `description` → Task 3 title bar + section subtitle. ✓
- Verification via mock + sim + DEVICE_NOTES → Task 2 Step 3, Task 3 Steps 5-6. ✓
- Out-of-scope (podcast page, pagination, pull-to-refresh, FeedList) → not implemented. ✓

**Placeholder scan:** No TBD/TODO; every code step shows complete code. ✓

**Type consistency:** `discoverySections`/`discoveryLoaded`/`fetchDiscovery`/`startDiscoveryPhase`/`finishDiscoveryPhase`/`shapeDiscoverySections`/`shapeDiscoveryEpisode` and enum values `DiscoveryDefault/Topic/Hot` are spelled identically in header decls (T1.S1), definitions (T1.S3/S5), and dispatch (T1.S4). Section keys `title/subtitle/items` and item keys `eid/coverUrl/title/showName/durationText/whenText/commentCount` match between producer (T1.S5) and consumer (T3.S1). ✓

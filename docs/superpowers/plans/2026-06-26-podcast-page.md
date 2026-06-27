# Podcast (Show) Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a podcast (show) detail page — hero, subscriber row, and a paginated list of the show's episodes — reachable from Subscriptions and the Episode page, wired to the live Xiaoyuzhou API.

**Architecture:** A new pushed detail page `PodcastPage.qml` (sibling to `EpisodePage`), seeded from the tapped item for instant paint, then fed by new `XyzApiClient` methods that mirror the existing inbox/episode/comments code paths exactly. Reads only this pass: subscribe pill is display-only; the Popular filter and subscribe-write are deferred.

**Tech Stack:** Qt 4.7 / QML 1.1 (Symbian Components 1.1), C++ `XyzApiClient` over `QNetworkAccessManager`, QJson parser, simulator build via `scripts/build-simulator.ps1`.

## Global Constraints

- **No unit-test harness exists.** Each task's verification = clean simulator build + (where applicable) live-API replay + in-sim flow. Build command: `pwsh scripts/build-simulator.ps1 -Config Debug`.
- **QML 1.1 rules:** no block expressions in property bindings (use ternaries/helpers); declare functions only at the `Page`/root level; no negative anchor margins; `font.pixelSize` must be an int.
- **Proxy double-wrap:** inside `onReplyFinished` the outer wrap is already stripped — `top.value("data")` is the real upstream payload, with `loadMoreKey`/`total` as siblings at `top` (exactly like comments).
- **Tappable rows:** one full-delegate `MouseArea` behind content (not partial/nested).
- **New .qml/.svg files must be registered in `qml/qml.qrc`** or they silently fail to load. No `.pro` change is needed (only existing `XyzApiClient.{h,cpp}` are modified; new assets go through the qrc).
- **C++ string idiom:** wrap literals in `QString::fromLatin1("…")` as the surrounding code does.
- **Theme tokens** (`qml/js/Theme.js`): `bg, panel, panel2, chromeHi, chromeLo, hairline, hairlineStrong, text, textBody, textDim, textFaint, accent, accentBright, accentDeep, errorColor`.

---

### Task 1: C++ — podcast detail fetch + `pid` surfacing

**Files:**
- Modify: `src/XyzApiClient.h`
- Modify: `src/XyzApiClient.cpp`

**Interfaces:**
- Consumes: existing `startGet`, `pickImageUrl`, `onReplyFinished` unwrap (`top`, `rawItems`).
- Produces: `Q_PROPERTY QVariantMap podcast` (+ `podcastLoaded()`), `Q_INVOKABLE void fetchPodcast(const QString &pid)`; `shapeSubscription`/`shapeEpisode` now include a `pid` field.

- [ ] **Step 1: Declare the podcast detail API in the header**

In `src/XyzApiClient.h`, add the property after the `episode` property (line 24):

```cpp
    Q_PROPERTY(QVariantMap podcast READ podcast NOTIFY podcastLoaded)
```

Add the getter after `QVariantMap episode() const;` (line 37):

```cpp
    QVariantMap podcast() const;
```

Add the invokable after `fetchEpisode` (line 45):

```cpp
    Q_INVOKABLE void fetchPodcast(const QString &pid);
```

Add the signal after `episodeLoaded();` (line 56):

```cpp
    void podcastLoaded();
```

Add to the `RequestType` enum (line 67) — append `PodcastRequest`:

```cpp
    enum RequestType { NoneRequest, InboxRequest, SubscriptionsRequest,
                       EpisodeRequest, CommentsRequest, MoreCommentsRequest,
                       DiscoveryRequest, RefreshRequest, PodcastRequest };
```

Add the shaper declaration near `shapeEpisode` (line 89):

```cpp
    QVariantMap shapePodcast(const QVariantMap &item) const;
```

Add the member near `m_episode` (line 120):

```cpp
    QVariantMap m_podcast;
```

- [ ] **Step 2: Implement the getter, fetch, dispatch, shaper, and pid surfacing**

In `src/XyzApiClient.cpp`, add the getter next to `episode()`:

```cpp
QVariantMap XyzApiClient::podcast() const { return m_podcast; }
```

Add the fetch method next to `fetchEpisode` (after line 94) — a GET with the pid as a query param, mirroring `fetchEpisode`:

```cpp
// Podcast (show) detail is a GET with the pid as a query param (no body) —
// /v1/podcast/get?pid=, confirmed from the ultrazg/xyz Go source (handlers/podcast.go).
void XyzApiClient::fetchPodcast(const QString &pid)
{
    if (pid.isEmpty()) {
        return;
    }
    startGet(PodcastRequest,
             QString::fromLatin1("/v1/podcast/get?pid=") + QString(QUrl::toPercentEncoding(pid)));
}
```

Add the dispatch branch in `onReplyFinished`, immediately after the `EpisodeRequest` block (after line 466) — the payload is a map under `data`, like episode/get:

```cpp
    if (type == PodcastRequest) {
        QVariantMap raw = top.value(QString::fromLatin1("data")).toMap();
        if (raw.isEmpty()) {
            raw = top;
        }
        m_podcast = shapePodcast(raw);
        setBusy(false);
        emit podcastLoaded();
        return;
    }
```

Add a file-static grouped-thousands helper and the shaper immediately above `XyzApiClient::shapeEpisode` (line 676):

```cpp
// "68035" -> "68,035" for the subscriber count.
static QString formatCount(qlonglong n)
{
    QString s = QString::number(n);
    int i = s.length() - 3;
    while (i > 0) {
        s.insert(i, QLatin1Char(','));
        i -= 3;
    }
    return s;
}

QVariantMap XyzApiClient::shapePodcast(const QVariantMap &item) const
{
    QVariantMap out;
    out.insert(QString::fromLatin1("pid"), item.value(QString::fromLatin1("pid")).toString());
    out.insert(QString::fromLatin1("name"), item.value(QString::fromLatin1("title")).toString());
    out.insert(QString::fromLatin1("desc"), item.value(QString::fromLatin1("description")).toString());
    out.insert(QString::fromLatin1("coverUrl"),
               pickImageUrl(item.value(QString::fromLatin1("image")).toMap()));

    // Author = the first podcaster (fall back to the legacy "author" string).
    const QVariantList podcasters = item.value(QString::fromLatin1("podcasters")).toList();
    QString author;
    QString authorAvatar;
    if (!podcasters.isEmpty()) {
        const QVariantMap p = podcasters.at(0).toMap();
        author = p.value(QString::fromLatin1("nickname")).toString();
        authorAvatar = pickImageUrl(p.value(QString::fromLatin1("avatar")).toMap()
                                     .value(QString::fromLatin1("picture")).toMap());
    }
    if (author.isEmpty()) {
        author = item.value(QString::fromLatin1("author")).toString();
    }
    out.insert(QString::fromLatin1("author"), author);
    out.insert(QString::fromLatin1("authorAvatarUrl"), authorAvatar);

    out.insert(QString::fromLatin1("subscriberText"),
               formatCount(item.value(QString::fromLatin1("subscriptionCount")).toLongLong()));
    out.insert(QString::fromLatin1("episodeCountText"),
               QString::number(item.value(QString::fromLatin1("episodeCount")).toInt()));
    out.insert(QString::fromLatin1("isSubscribed"),
               item.value(QString::fromLatin1("subscriptionStatus")).toString()
                   == QLatin1String("ON"));
    return out;
}
```

Surface `pid` on the subscription item — in `shapeSubscription`, just before `return out;` (line 673):

```cpp
    out.insert(QString::fromLatin1("pid"), item.value(QString::fromLatin1("pid")).toString());
```

Surface `pid` on the episode item — in `shapeEpisode`, just before `return out;` (line 711). The `podcast` local already exists (line 681); fall back to its pid:

```cpp
    QString pid = item.value(QString::fromLatin1("pid")).toString();
    if (pid.isEmpty()) {
        pid = podcast.value(QString::fromLatin1("pid")).toString();
    }
    out.insert(QString::fromLatin1("pid"), pid);
```

- [ ] **Step 3: Build and verify it compiles clean**

Run: `pwsh scripts/build-simulator.ps1 -Config Debug`
Expected: ends with `[INFO] Build succeeded: …\Xyz.exe`, no compiler errors.

- [ ] **Step 4: Replay the live endpoint to confirm the response shape**

Using the replay-with-sim-token practice (read `auth.accessToken` from the simulator's `xyz.db`, send with the iOS headers documented in `docs/API_NOTES.md:78-99`), GET `https://api.xiaoyuzhoufm.com/v1/podcast/get?pid=<a known pid from your subscriptions>`.
Expected: a JSON object containing `title`, `description`, `image`, `subscriptionCount`, `episodeCount`, `subscriptionStatus`, `podcasters[]`. Confirm the field names match `shapePodcast`. (If the proxy is used instead, expect one extra `data` wrap — the client strips it.)

- [ ] **Step 5: Commit**

```bash
git add src/XyzApiClient.h src/XyzApiClient.cpp
git commit -m "feat(podcast): fetch podcast detail + surface pid on subs/episodes"
```

---

### Task 2: C++ — paginated podcast episode list

**Files:**
- Modify: `src/XyzApiClient.h`
- Modify: `src/XyzApiClient.cpp`

**Interfaces:**
- Consumes: existing `startPost`, `relativeTime`, `pickImageUrl`, `onReplyFinished` unwrap.
- Produces: `Q_PROPERTY QVariantList podcastEpisodes`, `Q_PROPERTY bool hasMorePodcastEpisodes` (+ `podcastEpisodesLoaded()`), `Q_INVOKABLE void fetchPodcastEpisodes(const QString &pid)`, `Q_INVOKABLE void loadMorePodcastEpisodes()`. Each shaped episode has `eid, coverUrl, title, desc, durationText, whenText, plays, cmt` (the first five are exactly what `EpisodePage.openWith` reads).

- [ ] **Step 1: Declare the episode-list API in the header**

In `src/XyzApiClient.h`, add the properties after the new `podcast` property:

```cpp
    Q_PROPERTY(QVariantList podcastEpisodes READ podcastEpisodes NOTIFY podcastEpisodesLoaded)
    Q_PROPERTY(bool hasMorePodcastEpisodes READ hasMorePodcastEpisodes NOTIFY podcastEpisodesLoaded)
```

Add the getters after `QVariantMap podcast() const;`:

```cpp
    QVariantList podcastEpisodes() const;
    bool hasMorePodcastEpisodes() const;
```

Add the invokables after `fetchPodcast`:

```cpp
    Q_INVOKABLE void fetchPodcastEpisodes(const QString &pid);
    // Append the next page using the loadMoreKey from the last episode-list fetch.
    Q_INVOKABLE void loadMorePodcastEpisodes();
```

Add the signal after `podcastLoaded();`:

```cpp
    void podcastEpisodesLoaded();
```

Extend the `RequestType` enum — append two types:

```cpp
    enum RequestType { NoneRequest, InboxRequest, SubscriptionsRequest,
                       EpisodeRequest, CommentsRequest, MoreCommentsRequest,
                       DiscoveryRequest, RefreshRequest, PodcastRequest,
                       PodcastEpisodesRequest, MorePodcastEpisodesRequest };
```

Add the shaper declaration after `shapePodcast`:

```cpp
    QVariantMap shapePodcastEpisode(const QVariantMap &item) const;
```

Add the members after `m_podcast`:

```cpp
    QVariantList m_podcastEpisodes;
    // Episode-list pagination: the pid of the current show, the opaque loadMoreKey
    // to echo back for the next page (empty when there are no more), and the total.
    QString m_podcastEpisodesPid;
    QVariantMap m_podcastEpisodesKey;
    int m_podcastEpisodesTotal;
```

- [ ] **Step 2: Initialize the int member**

In the `XyzApiClient` constructor initializer list in `src/XyzApiClient.cpp`, add `m_podcastEpisodesTotal(0)` alongside the existing `m_commentsTotal(0)` initializer (match the surrounding style).

- [ ] **Step 3: Implement getters, fetch, load-more, dispatch, and shaper**

In `src/XyzApiClient.cpp`, add the getters next to `podcast()`:

```cpp
QVariantList XyzApiClient::podcastEpisodes() const { return m_podcastEpisodes; }
bool XyzApiClient::hasMorePodcastEpisodes() const { return !m_podcastEpisodesKey.isEmpty(); }
```

Add the fetch + load-more next to `fetchPodcast` — a copy of the comments-pagination shape (`/v1/episode/list`, `loadMoreKey` echoed back):

```cpp
// Episodes for a show (first page). order=desc is newest-first; loadMoreKey is the
// opaque cursor object {pubDate,id,direction} the API returns and we echo back.
void XyzApiClient::fetchPodcastEpisodes(const QString &pid)
{
    if (pid.isEmpty()) {
        return;
    }
    m_podcastEpisodesPid = pid;
    m_podcastEpisodesKey.clear();
    m_podcastEpisodesTotal = 0;

    QVariantMap body;
    body.insert(QString::fromLatin1("pid"), pid);
    body.insert(QString::fromLatin1("order"), QString::fromLatin1("desc"));
    body.insert(QString::fromLatin1("limit"), QString::fromLatin1("20"));
    startPost(PodcastEpisodesRequest, QString::fromLatin1("/v1/episode/list"), body);
}

void XyzApiClient::loadMorePodcastEpisodes()
{
    if (m_busy || m_podcastEpisodesPid.isEmpty() || m_podcastEpisodesKey.isEmpty()) {
        return;
    }
    QVariantMap body;
    body.insert(QString::fromLatin1("pid"), m_podcastEpisodesPid);
    body.insert(QString::fromLatin1("order"), QString::fromLatin1("desc"));
    body.insert(QString::fromLatin1("limit"), QString::fromLatin1("20"));
    body.insert(QString::fromLatin1("loadMoreKey"), m_podcastEpisodesKey);
    startPost(MorePodcastEpisodesRequest, QString::fromLatin1("/v1/episode/list"), body);
}
```

Add the dispatch branch in `onReplyFinished`, immediately after the new `PodcastRequest` block — same structure as `CommentsRequest`/`MoreCommentsRequest`:

```cpp
    if (type == PodcastEpisodesRequest || type == MorePodcastEpisodesRequest) {
        QVariantList shaped;
        for (int i = 0; i < rawItems.size(); ++i) {
            shaped.append(shapePodcastEpisode(rawItems.at(i).toMap()));
        }
        if (type == MorePodcastEpisodesRequest) {
            m_podcastEpisodes += shaped;   // append the next page
        } else {
            m_podcastEpisodes = shaped;    // first page replaces
        }
        if (top.contains(QString::fromLatin1("total"))) {
            m_podcastEpisodesTotal = top.value(QString::fromLatin1("total")).toInt();
        }
        // loadMoreKey is absent on the last page → empty map → hasMore false.
        m_podcastEpisodesKey = top.value(QString::fromLatin1("loadMoreKey")).toMap();
        setBusy(false);
        emit podcastEpisodesLoaded();
        return;
    }
```

Add the shaper next to `shapePodcast`:

```cpp
QVariantMap XyzApiClient::shapePodcastEpisode(const QVariantMap &item) const
{
    QVariantMap out;
    out.insert(QString::fromLatin1("eid"), item.value(QString::fromLatin1("eid")).toString());
    out.insert(QString::fromLatin1("coverUrl"),
               pickImageUrl(item.value(QString::fromLatin1("image")).toMap()));
    out.insert(QString::fromLatin1("title"), item.value(QString::fromLatin1("title")).toString());
    out.insert(QString::fromLatin1("desc"), item.value(QString::fromLatin1("description")).toString());

    const int durationSec = item.value(QString::fromLatin1("duration")).toInt();
    out.insert(QString::fromLatin1("durationText"),
               QString::fromLatin1("%1 min").arg((durationSec + 30) / 60));
    out.insert(QString::fromLatin1("whenText"),
               relativeTime(item.value(QString::fromLatin1("pubDate")).toString()));
    out.insert(QString::fromLatin1("plays"),
               QString::number(item.value(QString::fromLatin1("playCount")).toInt()));
    out.insert(QString::fromLatin1("cmt"),
               QString::number(item.value(QString::fromLatin1("commentCount")).toInt()));
    return out;
}
```

- [ ] **Step 4: Build and verify it compiles clean**

Run: `pwsh scripts/build-simulator.ps1 -Config Debug`
Expected: `[INFO] Build succeeded: …\Xyz.exe`, no errors.

- [ ] **Step 5: Replay the live endpoint to confirm shape + pagination**

Replay `POST https://api.xiaoyuzhoufm.com/v1/episode/list` with body `{"pid":"<known pid>","order":"desc","limit":"20"}` (sim token + iOS headers, as in Task 1 Step 4).
Expected: `data` is an array of episode objects (`eid, title, description, duration, pubDate, playCount, commentCount, image`); a sibling `loadMoreKey` `{pubDate,id,direction:"NEXT"}` and `total` are present. Re-send with `"loadMoreKey":<that object>` and confirm the next page differs.

- [ ] **Step 6: Commit**

```bash
git add src/XyzApiClient.h src/XyzApiClient.cpp
git commit -m "feat(podcast): paginated episode list for a show (episode/list)"
```

---

### Task 3: `PodcastPage.qml` + icons + qrc registration

**Files:**
- Create: `qml/PodcastPage.qml`
- Create: `qml/gfx/icon-bell.svg`
- Create: `qml/gfx/icon-headphone.svg`
- Modify: `qml/qml.qrc`

**Interfaces:**
- Consumes: `xyzApi.podcast`, `xyzApi.podcastEpisodes`, `xyzApi.hasMorePodcastEpisodes`, `xyzApi.fetchPodcast`, `xyzApi.fetchPodcastEpisodes`, `xyzApi.loadMorePodcastEpisodes`, `xyzApi.busy`, `xyzApi.errorMessage`; `BelleHeader`, `MiniPlayer`, `Theme.js`.
- Produces: `PodcastPage` with `function openWith(podId, seed)`, `signal episodeRequested(variant item)`, `signal openPlayerRequested`. Each `episodeRequested` item carries `eid, coverUrl, title, durationText, whenText` (consumed by `EpisodePage.openWith`).

- [ ] **Step 1: Add the two line icons**

First read `qml/gfx/icon-comment.svg` to copy its exact `<svg …>` opening tag (viewBox + fill convention) so the meta-row icons render at a consistent size/color. Then create the two icons with the same wrapper. Fetch the Remix line glyphs (per the remixicon practice) — `headphone-line` and `notification-3-line` from `https://cdn.jsdelivr.net/npm/remixicon@4.5.0/icons/...` — drop their `<path>` data into the matching wrapper, and set the fill to the same concrete color `icon-comment.svg` uses (the `textDim` family, `#8b8b95`). Save as:
- `qml/gfx/icon-headphone.svg` (plays count)
- `qml/gfx/icon-bell.svg` (subscribe row)

(If a glyph's `viewBox` differs from `icon-comment.svg`, follow the CLAUDE.md SVG rule: change `width`/`height` **and** `viewBox` together, wrapping the path in `<g transform="scale(...)">`.)

- [ ] **Step 2: Register the page and icons in the qrc**

In `qml/qml.qrc`, add `<file>PodcastPage.qml</file>` after the `EpisodePage.qml` line, and add the two icons in the `gfx/` block:

```xml
        <file>EpisodePage.qml</file>
        <file>PodcastPage.qml</file>
```
```xml
        <file>gfx/icon-bell.svg</file>
        <file>gfx/icon-headphone.svg</file>
```

- [ ] **Step 3: Create `qml/PodcastPage.qml`**

```qml
import QtQuick 1.1
import com.nokia.symbian 1.1
import "js/Theme.js" as Theme

// Podcast (show) detail — hero, subscriber row, paginated episode list.
// (design: screens-podcast.jsx + .pod-* / .up-* in belle.css).
// Hero is seeded from the tapped item (subscription cell / episode show-link) for
// instant paint; the show detail + episode list come from a live fetch by pid.
// Reads only: the Subscribe pill is display-only; the Popular chip is inert.
Page {
    id: page
    objectName: "PodcastPage"

    property bool hidesToolBar: true
    signal episodeRequested(variant item)
    signal openPlayerRequested

    // ---- identity / seed ----
    property string pid: ""
    property string name: ""
    property string coverUrl: ""

    // ---- filled from the podcast/get fetch ----
    property string descText: ""
    property string author: ""
    property string authorAvatarUrl: ""
    property string subscriberText: ""
    property string episodeCountText: ""
    property bool isSubscribed: false
    property bool detailLoaded: false

    // ---- episode list ----
    property variant episodes: []
    property bool episodesLoaded: false
    property bool loadingMore: false

    // Seed the hero from the tapped item, clear stale state, then fetch on activation.
    // seed may be a subscription item ({name, coverUrl}) or a built {name, coverUrl}.
    function openWith(podId, seed) {
        page.pid = podId;
        page.name = (seed && seed.name) ? seed.name : "";
        page.coverUrl = (seed && seed.coverUrl) ? seed.coverUrl : "";
        page.descText = "";
        page.author = "";
        page.authorAvatarUrl = "";
        page.subscriberText = "";
        page.episodeCountText = "";
        page.isSubscribed = false;
        page.detailLoaded = false;
        page.episodes = [];
        page.episodesLoaded = false;
        page.loadingMore = false;
    }

    onStatusChanged: {
        if (status === PageStatus.Active && page.pid !== "" && !page.detailLoaded) {
            xyzApi.fetchPodcast(page.pid);
        }
    }

    // Detail first; the episode list is fetched after it lands (the client serves one
    // request at a time, so a concurrent call would abort the detail fetch).
    Connections {
        target: xyzApi
        onPodcastLoaded: {
            page.name = xyzApi.podcast.name;
            page.coverUrl = xyzApi.podcast.coverUrl;
            page.descText = xyzApi.podcast.desc;
            page.author = xyzApi.podcast.author;
            page.authorAvatarUrl = xyzApi.podcast.authorAvatarUrl;
            page.subscriberText = xyzApi.podcast.subscriberText;
            page.episodeCountText = xyzApi.podcast.episodeCountText;
            page.isSubscribed = xyzApi.podcast.isSubscribed;
            page.detailLoaded = true;
            xyzApi.fetchPodcastEpisodes(page.pid);
        }
        onPodcastEpisodesLoaded: {
            page.episodes = xyzApi.podcastEpisodes;
            page.episodesLoaded = true;
        }
        // Clear the "loading more" spinner on any completion (error/timeout only flips busy).
        onBusyChanged: {
            if (!xyzApi.busy) page.loadingMore = false;
        }
    }

    Rectangle { anchors.fill: parent; color: Theme.bg }

    BelleHeader {
        id: header
        title: qsTr("Podcast")
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        onBackClicked: pageStack.pop()
    }

    Flickable {
        id: scroll
        anchors.top: header.bottom
        anchors.bottom: miniPlayer.visible ? miniPlayer.top : parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        clip: true
        contentWidth: width
        contentHeight: contentCol.height
        flickableDirection: Flickable.VerticalFlick

        Column {
            id: contentCol
            width: scroll.width

            // ---- hero ----
            Item {
                width: contentCol.width
                height: Math.max(heroText.height, 112) + 32

                Column {
                    id: heroText
                    anchors.top: parent.top
                    anchors.topMargin: 14
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.right: cover.left
                    anchors.rightMargin: 16
                    spacing: 0

                    Text {
                        width: parent.width
                        text: page.name
                        font.pixelSize: 27
                        font.weight: Font.Bold
                        color: Theme.text
                        wrapMode: Text.WordWrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                        lineHeight: 1.15
                    }
                    Text {
                        width: parent.width
                        text: page.descText
                        visible: page.descText.length > 0
                        font.pixelSize: 14
                        color: Theme.textDim
                        wrapMode: Text.WordWrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                        lineHeight: 1.45
                        // top gap only when present (no block expressions: use an Item spacer instead)
                    }
                    Item { width: 1; height: page.descText.length > 0 ? 14 : 0 }

                    Row {
                        spacing: 9
                        visible: page.author.length > 0
                        Rectangle {
                            width: 26; height: 26; radius: 13; clip: true
                            color: "#2a2536"
                            anchors.verticalCenter: parent.verticalCenter
                            Image {
                                anchors.fill: parent
                                fillMode: Image.PreserveAspectCrop
                                smooth: true
                                sourceSize.width: 26; sourceSize.height: 26
                                source: page.authorAvatarUrl
                                visible: page.authorAvatarUrl !== ""
                            }
                            Text {
                                visible: page.authorAvatarUrl === "" && page.author.length > 0
                                anchors.centerIn: parent
                                text: page.author.charAt(0)
                                font.pixelSize: 11
                                font.bold: true
                                color: "#ffffff"
                            }
                        }
                        Text {
                            text: page.author
                            font.pixelSize: 14
                            color: Theme.text
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }

                Rectangle {
                    id: cover
                    width: 112; height: 112; radius: 10
                    anchors.top: parent.top
                    anchors.topMargin: 14
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    color: "#1a1a22"
                    clip: true
                    Image {
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        smooth: true
                        sourceSize.width: 112; sourceSize.height: 112
                        source: page.coverUrl
                    }
                }
            }

            // ---- subscriber row + (display-only) subscribe ----
            Item {
                width: contentCol.width
                height: 64
                visible: page.detailLoaded

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    Text {
                        text: page.subscriberText
                        font.pixelSize: 24
                        font.weight: Font.Bold
                        color: Theme.text
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: qsTr("subscribers")
                        font.pixelSize: 13
                        color: Theme.textDim
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 9

                    Rectangle {
                        width: 46; height: 42; radius: 7
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.panel2
                        border.width: 1; border.color: Theme.hairlineStrong
                        Image {
                            source: "gfx/icon-bell.svg"
                            width: 20; height: 20; smooth: true
                            anchors.centerIn: parent
                        }
                    }

                    Rectangle {
                        height: 42; radius: 7
                        width: subLabel.width + 32
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.panel2
                        border.width: 1; border.color: Theme.hairlineStrong
                        Text {
                            id: subLabel
                            anchors.centerIn: parent
                            text: page.isSubscribed ? qsTr("Subscribed") : qsTr("Subscribe")
                            font.pixelSize: 15
                            font.weight: Font.Bold
                            color: Theme.textDim
                        }
                    }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    color: Theme.hairline
                }
            }

            // ---- episode count + filter chips ----
            Item {
                width: contentCol.width
                height: 52
                visible: page.detailLoaded

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.top: parent.top
                    anchors.topMargin: 16
                    text: page.episodeCountText + " " + qsTr("episodes")
                    font.pixelSize: 13
                    color: Theme.textDim
                }

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.bottom: parent.bottom
                    spacing: 8

                    Rectangle {
                        height: 28; radius: 14
                        width: allChip.width + 32
                        color: "#388b6dff"
                        border.width: 1; border.color: Theme.accent
                        Text {
                            id: allChip
                            anchors.centerIn: parent
                            text: qsTr("All")
                            font.pixelSize: 13
                            color: "#ffffff"
                        }
                    }
                    Rectangle {
                        height: 28; radius: 14
                        width: popChip.width + 32
                        color: "#10FFFFFF"
                        Text {
                            id: popChip
                            anchors.centerIn: parent
                            text: qsTr("Popular")
                            font.pixelSize: 13
                            color: Theme.textDim
                        }
                    }
                }
            }

            // ---- episode list ----
            Repeater {
                model: page.episodes

                Item {
                    width: contentCol.width
                    height: bodyArea.height + metaRow.height + 42  // 14 top + 14 gap + 14 bottom

                    MouseArea {
                        anchors.fill: parent
                        onClicked: page.episodeRequested(modelData)
                    }

                    Row {
                        id: bodyArea
                        anchors.top: parent.top
                        anchors.topMargin: 14
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        spacing: 12

                        Rectangle {
                            width: 70; height: 70; radius: 6
                            color: "#1a1a22"
                            clip: true
                            Image {
                                anchors.fill: parent
                                fillMode: Image.PreserveAspectCrop
                                smooth: true
                                sourceSize.width: 70; sourceSize.height: 70
                                source: modelData.coverUrl !== "" ? modelData.coverUrl : page.coverUrl
                            }
                        }

                        Column {
                            width: bodyArea.width - 70 - 12
                            spacing: 7
                            Text {
                                width: parent.width
                                text: modelData.title
                                font.pixelSize: 17
                                font.bold: true
                                color: Theme.text
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                lineHeight: 1.32
                            }
                            Text {
                                width: parent.width
                                text: modelData.desc
                                font.pixelSize: 14
                                color: Theme.textBody
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                lineHeight: 1.4
                            }
                        }
                    }

                    Row {
                        id: metaRow
                        anchors.top: bodyArea.bottom
                        anchors.topMargin: 14
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        spacing: 10

                        Text { text: modelData.durationText; font.pixelSize: 14; color: Theme.textDim; anchors.verticalCenter: parent.verticalCenter }
                        Rectangle { width: 3; height: 3; radius: 2; color: Theme.textFaint; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: modelData.whenText; font.pixelSize: 14; color: Theme.textDim; anchors.verticalCenter: parent.verticalCenter }
                        Rectangle { width: 3; height: 3; radius: 2; color: Theme.textFaint; anchors.verticalCenter: parent.verticalCenter }
                        Row {
                            spacing: 5
                            anchors.verticalCenter: parent.verticalCenter
                            Image { source: "gfx/icon-headphone.svg"; width: 15; height: 15; smooth: true; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: modelData.plays; font.pixelSize: 14; color: Theme.textDim; anchors.verticalCenter: parent.verticalCenter }
                        }
                        Rectangle { width: 3; height: 3; radius: 2; color: Theme.textFaint; anchors.verticalCenter: parent.verticalCenter }
                        Row {
                            spacing: 5
                            anchors.verticalCenter: parent.verticalCenter
                            Image { source: "gfx/icon-comment.svg"; width: 15; height: 15; smooth: true; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: modelData.cmt; font.pixelSize: 14; color: Theme.textDim; anchors.verticalCenter: parent.verticalCenter }
                        }
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 1
                        color: Theme.hairline
                    }
                }
            }

            // ---- load-more footer ----
            Item {
                width: contentCol.width
                visible: page.episodesLoaded && page.episodes.length > 0
                height: visible ? 58 : 0

                // (a) idle → "Load more" + showing-count
                Column {
                    anchors.centerIn: parent
                    spacing: 3
                    visible: xyzApi.hasMorePodcastEpisodes && !page.loadingMore
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: qsTr("Load more")
                        font.pixelSize: 15; font.weight: Font.DemiBold; color: Theme.accentBright
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: qsTr("Showing %1 of %2").arg(page.episodes.length).arg(page.episodeCountText)
                        font.pixelSize: 12; color: Theme.textDim
                    }
                }

                // (b) loading next page → spinner
                Row {
                    anchors.centerIn: parent
                    spacing: 9
                    visible: page.loadingMore
                    BusyIndicator {
                        running: page.loadingMore
                        width: 20; height: 20
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: qsTr("Loading more…"); font.pixelSize: 15; color: Theme.text
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                // (c) end
                Text {
                    anchors.centerIn: parent
                    visible: !xyzApi.hasMorePodcastEpisodes && !page.loadingMore
                    text: qsTr("All episodes loaded")
                    font.pixelSize: 13; color: Theme.textFaint
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: xyzApi.hasMorePodcastEpisodes && !page.loadingMore && !xyzApi.busy
                    onClicked: { page.loadingMore = true; xyzApi.loadMorePodcastEpisodes(); }
                }
            }

            // tail spacer
            Item { width: contentCol.width; height: 16 }
        }
    }

    // ---- loading / error overlays (hero stays visible underneath) ----
    BusyIndicator {
        running: xyzApi.busy && !page.detailLoaded
        visible: running
        width: 40; height: 40
        anchors.horizontalCenter: scroll.horizontalCenter
        anchors.top: scroll.top
        anchors.topMargin: 180
    }
    Text {
        visible: !xyzApi.busy && !page.detailLoaded && xyzApi.errorMessage.length > 0
        anchors.horizontalCenter: scroll.horizontalCenter
        anchors.top: scroll.top
        anchors.topMargin: 180
        width: scroll.width - 48
        text: xyzApi.errorMessage
        color: Theme.errorColor
        font.pixelSize: 13
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
    }

    MiniPlayer {
        id: miniPlayer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        onExpandRequested: page.openPlayerRequested()
    }
}
```

- [ ] **Step 4: Build**

Run: `pwsh scripts/build-simulator.ps1 -Config Debug`
Expected: `[INFO] Build succeeded`. (A typo in the qrc path or QML would surface here or as a runtime "File not found" — caught in Step 5.)

- [ ] **Step 5: Verify the page renders with live data (temporary entry)**

Temporarily make the page reachable for visual check: in `qml/AppWindow.qml`, add a temporary `initialPage` override or push — the simplest is to temporarily change `initialPage:` to a freshly-seeded podcast page. For example, temporarily replace the `initialPage` line with:

```qml
    initialPage: podcastPage
    Component.onCompleted: podcastPage.openWith("<a known pid>", undefined)
```

(You must add the `PodcastPage { id: podcastPage … }` element from Task 4 Step 1 first, or inline a throwaway `PodcastPage { id: podcastPage }`.) Launch the simulator (screenshot-running-simulator practice: `Xyz.exe` with `QtBin` on `PATH` + `QT_PLUGIN_PATH`, capture the `Qt Simulator` window).
Expected: hero (name, description, author chip, cover), subscriber row, "N episodes" + All/Popular chips, and a populated episode list with `dur · when · 🎧plays · 💬cmt` meta; tapping "Load more" appends a page; reaching the end shows "All episodes loaded".
Then **revert** the temporary `initialPage`/`Component.onCompleted` change.

- [ ] **Step 6: Commit**

```bash
git add qml/PodcastPage.qml qml/gfx/icon-bell.svg qml/gfx/icon-headphone.svg qml/qml.qrc
git commit -m "feat(podcast): PodcastPage.qml (hero + episode list) + icons"
```

---

### Task 4: Navigation wiring — both entry points

**Files:**
- Modify: `qml/AppWindow.qml`
- Modify: `qml/SubscriptionsPage.qml`
- Modify: `qml/EpisodePage.qml`

**Interfaces:**
- Consumes: `PodcastPage.openWith(podId, seed)` + `episodeRequested` (Task 3); `episodePage.openWith(item)` (existing); subscription `modelData.pid` + `xyzApi.episode.pid` (Task 1).
- Produces: `SubscriptionsPage` `signal podcastRequested(string pid, variant seed)`; `EpisodePage` `signal podcastRequested(string pid)`; an `AppWindow` `PodcastPage { id: podcastPage }` element routing both.

- [ ] **Step 1: Add the PodcastPage element + route its rows in AppWindow**

In `qml/AppWindow.qml`, add after the `EpisodePage { … }` block (line 180):

```qml
    PodcastPage {
        id: podcastPage
        onEpisodeRequested: {
            episodePage.openWith(item);
            pageStack.push(episodePage);
        }
        onOpenPlayerRequested: window.openNowPlaying()
    }
```

- [ ] **Step 2: Route the Subscriptions tap in AppWindow**

In `qml/AppWindow.qml`, in the existing `SubscriptionsPage { id: subscriptionsPage … }` block (line 171), add a handler:

```qml
        onPodcastRequested: {
            podcastPage.openWith(pid, seed);
            pageStack.push(podcastPage);
        }
```

- [ ] **Step 3: Route the Episode show-link in AppWindow**

In `qml/AppWindow.qml`, in the existing `EpisodePage { id: episodePage … }` block (line 177), add a handler that seeds the hero from the episode's show name + cover for instant paint:

```qml
        onPodcastRequested: {
            podcastPage.openWith(pid, {"name": episodePage.showTitle, "coverUrl": episodePage.coverUrl});
            pageStack.push(podcastPage);
        }
```

- [ ] **Step 4: Make Subscriptions cells tappable**

In `qml/SubscriptionsPage.qml`, add the signal after `signal openPlayerRequested` (line 16):

```qml
    signal podcastRequested(string pid, variant seed)
```

In the **grid** delegate (the outer `Item` at line 72), add a full-cell `MouseArea` as the last child of that `Item` (after the "Often" badge `Rectangle`, before the delegate's closing brace at line 112):

```qml
                MouseArea {
                    anchors.fill: parent
                    onClicked: page.podcastRequested(modelData.pid, modelData)
                }
```

In the **list** `rowDelegate` (the outer `Item` at line 234), add a full-row `MouseArea` as the **first** child of that `Item` (immediately after `height: 72`, before the `Row` at line 238) so it sits behind the content:

```qml
            MouseArea {
                anchors.fill: parent
                onClicked: page.podcastRequested(modelData.pid, modelData)
            }
```

- [ ] **Step 5: Make the Episode show-name tappable**

In `qml/EpisodePage.qml`, add a property after `property string showTitle: ""` (line 35):

```qml
    property string showPid: ""
```

In `openWith`, clear it alongside the other fetched fields (after `page.showTitle = "";`, line 52):

```qml
        page.showPid = "";
```

In the `onEpisodeLoaded` handler, set it alongside `page.showTitle` (after line 105):

```qml
            page.showPid = xyzApi.episode.pid;
```

Replace the show-title `Text` in the hero (lines 195-202) with a tappable Row that shows a chevron affordance when a pid is known:

```qml
                    Row {
                        width: parent.width
                        visible: page.showTitle.length > 0
                        spacing: 3

                        Text {
                            text: page.showTitle
                            font.pixelSize: 14
                            color: Theme.accentBright
                            elide: Text.ElideRight
                            width: page.showPid !== "" ? Math.min(implicitWidth, parent.width - 16) : parent.width
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Image {
                            source: "gfx/icon-chevron.svg"
                            width: 14; height: 14; smooth: true
                            visible: page.showPid !== ""
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: page.showPid !== ""
                            onClicked: page.podcastRequested(page.showPid)
                        }
                    }
```

Add the signal near the top of `EpisodePage.qml`, after `signal openPlayerRequested` (line 15):

```qml
    signal podcastRequested(string pid)
```

- [ ] **Step 6: Build**

Run: `pwsh scripts/build-simulator.ps1 -Config Debug`
Expected: `[INFO] Build succeeded`, no errors.

- [ ] **Step 7: Verify both entry points and the round trip in-sim**

Launch the simulator (logged in). Verify:
1. **Subscriptions → show:** open Subscriptions (订阅 → My subscriptions), tap a cell (grid) and a row (list) → the podcast page opens with that show's hero + episodes.
2. **Episode → show:** open any episode, tap the show name (chevron) in the hero → the podcast page opens for that show.
3. **Load more:** scroll the episode list, tap "Load more" → next page appends; end shows "All episodes loaded".
4. **Row → Episode:** tap an episode row in the podcast page → the Episode page opens and loads (download/play CTA works as before).
5. **Back:** the header back button returns to the previous page each time.

Confirm no empty lists and the MiniPlayer still docks correctly. (No DEVICE_NOTES entry unless an audio/MMF surprise appears — this is networking + UI.)

- [ ] **Step 8: Commit**

```bash
git add qml/AppWindow.qml qml/SubscriptionsPage.qml qml/EpisodePage.qml
git commit -m "feat(podcast): wire entry points (Subscriptions + Episode show-link)"
```

---

## Self-Review

**1. Spec coverage:**
- §3 C++ podcast detail + pid surfacing → Task 1. ✓
- §4 paginated episode list (fetch/loadMore/shape) → Task 2. ✓
- §5 PodcastPage.qml (hero, subscriber row display-only, All/Popular chips, episode list, load-more, states) → Task 3. ✓
- §6 both entry points + route podcast rows → Episode → Task 4. ✓
- §7 assets + qrc → Task 3 Steps 1-2. ✓
- §8 verification (build + replay + in-sim) → present in each task's steps. ✓
- Deferred items (subscribe-write, Popular filter) correctly left as inert/display-only. ✓

**2. Placeholder scan:** No "TBD/TODO/handle edge cases" — every code step has complete code. The icon step names exact source glyphs + color + fallback rule; the replay steps name exact URLs/bodies + the documented header source. The one intentional `<a known pid>` is a runtime input the implementer supplies from their own subscriptions, not missing plan content.

**3. Type consistency:** `fetchPodcast`/`fetchPodcastEpisodes`/`loadMorePodcastEpisodes`, properties `podcast`/`podcastEpisodes`/`hasMorePodcastEpisodes`, signals `podcastLoaded`/`podcastEpisodesLoaded`, members `m_podcast`/`m_podcastEpisodes`/`m_podcastEpisodesPid`/`m_podcastEpisodesKey`/`m_podcastEpisodesTotal` are used identically across Tasks 1-3. Shaped field names (`name, desc, coverUrl, author, authorAvatarUrl, subscriberText, episodeCountText, isSubscribed`; episode `eid, coverUrl, title, desc, durationText, whenText, plays, cmt`) match between C++ shapers (Tasks 1-2) and QML consumption (Task 3). `openWith(podId, seed)` and `podcastRequested` signatures match between producer (Task 3) and callers (Task 4). Episode-row item passed to `episodeRequested` carries the `eid/coverUrl/title/durationText/whenText` that `EpisodePage.openWith` reads. ✓

Note: `PodcastPage` uses property `descText` (not `desc`) to avoid shadowing; the C++ shaped field is `desc` and is read as `xyzApi.podcast.desc` — consistent.

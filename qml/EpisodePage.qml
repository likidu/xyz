import QtQuick 1.1
import com.nokia.symbian 1.1
import "js/Theme.js" as Theme

// Episode detail — hero, Play CTA, show notes, top-comments preview
// (design: screens-detail.jsx + .ep-* / .cmt-* in belle.css).
// Hero is seeded from the tapped Updates card (instant paint); show name, notes,
// comment count and the comment list come from a live fetch by eid. Player deferred
// (the Play CTA is an inert placeholder, like the Updates action row).
Page {
    id: page
    objectName: "EpisodePage"

    property bool hidesToolBar: true
    signal openPlayerRequested
    signal podcastRequested(string pid)

    // ---- seeded from the tapped card ----
    property string eid: ""
    property string coverUrl: ""
    property string epTitle: ""
    property string durationText: ""
    property string whenText: ""

    // ---- seeded from episode detail fetch (not inbox item) ----
    property string audioUrl: ""
    property string audioSizeText: ""

    // ---- download/play CTA state ----
    property bool downloaded: false
    property string downloadedSize: ""
    property string mode: "download"   // set only via refreshDownloaded() (no cross-function binding)
    property bool confirmingDelete: false

    // ---- filled from the fetched detail ----
    property string showTitle: ""
    property string showPid: ""
    property string notes: ""
    property string commentCountText: ""
    property bool detailLoaded: false
    property bool loadingMoreComments: false

    // Seed the hero from the tapped inbox item and fetch fresh detail on activation.
    function openWith(item) {
        page.eid = item.eid;
        page.coverUrl = item.coverUrl;
        page.epTitle = item.title;
        page.durationText = item.durationText;
        page.whenText = item.whenText;
        // clear fetched fields so the previous episode never lingers behind a load
        page.audioUrl = "";
        page.audioSizeText = "";
        page.showTitle = "";
        page.showPid = "";
        page.notes = "";
        page.commentCountText = "";
        commentModel.clear();
        page.detailLoaded = false;
        page.loadingMoreComments = false;
        page.downloaded = false;
        page.downloadedSize = "";
        page.confirmingDelete = false;
        page.refreshDownloaded();   // correct CTA state on first paint (before push)
    }

    function subLine() {
        if (page.whenText.length > 0 && page.durationText.length > 0) {
            return page.durationText + "  ·  " + page.whenText;
        }
        return page.durationText + page.whenText;
    }

    function refreshDownloaded() {
        page.downloaded = (page.eid !== "" && player.isDownloaded(page.eid));
        page.downloadedSize = page.downloaded ? player.downloadedSizeText(page.eid) : "";
        page.mode = page.ctaMode();
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

    onStatusChanged: {
        if (status === PageStatus.Active && page.eid !== "" && !page.detailLoaded) {
            xyzApi.fetchEpisode(page.eid);
        }
        if (status === PageStatus.Active) {
            page.refreshDownloaded();
        }
    }

    // Detail first; comments are fetched after it lands (the client serves one
    // request at a time, so a concurrent call would abort the detail fetch).
    Connections {
        target: xyzApi
        onEpisodeLoaded: {
            page.showTitle = xyzApi.episode.showTitle;
            page.showPid = xyzApi.episode.pid;
            page.notes = xyzApi.episode.notes;
            page.commentCountText = xyzApi.episode.commentCount;
            page.audioUrl = xyzApi.episode.audioUrl;
            page.audioSizeText = xyzApi.episode.audioSizeText;
            page.detailLoaded = true;
            xyzApi.fetchComments(page.eid);
        }
        onCommentsLoaded: {
            // xyzApi.comments is the full accumulated list. Append only the rows
            // we don't have yet so existing delegates — and the Flickable's
            // scroll position — stay put when loading the next page.
            var all = xyzApi.comments;
            for (var i = commentModel.count; i < all.length; ++i) {
                commentModel.append(all[i]);
            }
        }
        // Clear the "loading more" spinner on any request completion — success emits
        // commentsLoaded, but an error/timeout only flips busy back to false.
        onBusyChanged: {
            if (!xyzApi.busy) page.loadingMoreComments = false;
        }
    }

    Connections {
        target: player
        // When a download-only completes, state returns to Idle -> re-check the cache.
        onStateChanged: page.refreshDownloaded();
        // When a (possibly deferred) delete actually removes the file -> re-check.
        onDownloadDeleted: page.refreshDownloaded();
    }

    Rectangle { anchors.fill: parent; color: Theme.bg }

    // Comments accumulate here; "Load more" appends only the newly fetched page
    // (see onCommentsLoaded). Reassigning a whole array model instead would
    // rebuild every delegate, collapse contentHeight mid-teardown and snap the
    // Flickable back to the top — the bug this avoids.
    ListModel { id: commentModel }

    BelleHeader {
        id: header
        title: qsTr("Episode")
        // delete lives in the top banner — shown only when the episode is downloaded
        actionIconSource: page.downloaded ? "gfx/icon-trash-white.svg" : ""
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        onBackClicked: pageStack.pop()
        onActionClicked: page.confirmingDelete = true
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
        // No elastic overshoot — the bounce-back animates extra repaint frames at
        // the list ends, which is wasted work on the weak Belle CPU.
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: contentCol
            width: scroll.width

            // ---- hero ----
            Item {
                width: contentCol.width
                height: Math.max(104, heroInfo.height) + 28

                Rectangle {
                    id: cover
                    width: 104
                    height: 104
                    anchors.top: parent.top
                    anchors.topMargin: 16
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    color: "#1a1a22"
                    clip: true
                    Image {
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        smooth: true
                        sourceSize.width: 104
                        sourceSize.height: 104
                        source: page.coverUrl
                    }
                    // Tap the cover to open the show — same target as the show name.
                    MouseArea {
                        anchors.fill: parent
                        enabled: page.showPid !== ""
                        onClicked: page.podcastRequested(page.showPid)
                    }
                }

                Column {
                    id: heroInfo
                    anchors.top: parent.top
                    anchors.topMargin: 16
                    anchors.left: cover.right
                    anchors.leftMargin: 14
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    spacing: 6

                    Item {
                        width: parent.width
                        height: showTitleText.height
                        visible: page.showTitle.length > 0

                        Text {
                            id: showTitleText
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: page.showTitle
                            font.pixelSize: 14
                            color: Theme.accentBright
                            elide: Text.ElideRight
                            width: page.showPid !== "" ? Math.min(implicitWidth, parent.width - 17) : parent.width
                        }
                        Image {
                            source: "gfx/icon-chevron.svg"
                            width: 14; height: 14; smooth: true
                            visible: page.showPid !== ""
                            anchors.left: showTitleText.right
                            anchors.leftMargin: 3
                            anchors.verticalCenter: showTitleText.verticalCenter
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: page.showPid !== ""
                            onClicked: page.podcastRequested(page.showPid)
                        }
                    }
                    Text {
                        width: parent.width
                        text: page.epTitle
                        font.pixelSize: 19
                        font.bold: true
                        color: Theme.text
                        wrapMode: Text.WordWrap
                        maximumLineCount: 4
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: page.subLine()
                        font.pixelSize: 13
                        color: Theme.textDim
                        elide: Text.ElideRight
                    }
                }
            }

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
                        Text { text: page.audioSizeText !== "" ? qsTr("Download") + "  ·  " + page.audioSizeText : qsTr("Download"); font.pixelSize: 15; font.bold: true; color: Theme.accentBright; anchors.verticalCenter: parent.verticalCenter }
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: page.audioUrl !== ""
                        onClicked: {
                            // Record metadata in the registry before kicking off the fetch,
                            // so the Downloads page can show this episode with its title/show.
                            downloads.note({
                                "eid": page.eid,
                                "title": page.epTitle,
                                "show": page.showTitle,
                                "durationText": page.durationText,
                                "coverUrl": page.coverUrl,
                                "sizeText": page.audioSizeText,
                                "audioUrl": page.audioUrl
                            });
                            player.download(page.audioUrl, page.eid);
                        }
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
                        radius: 6
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
                    Item {
                        id: dlCancel
                        width: 48; height: parent.height
                        anchors.right: parent.right; anchors.top: parent.top
                        Image {
                            source: "gfx/icon-x.svg"; width: 14; height: 14; smooth: true
                            anchors.centerIn: parent
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: { player.cancelDownload(); page.refreshDownloaded(); }
                        }
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
                            else if (page.mode === "ready") player.playEpisode(page.audioUrl, page.eid, page.epTitle, page.coverUrl, page.showTitle);
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
                                    running: page.mode === "playing"
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 14; duration: 320 + index * 70; easing.type: Easing.InOutSine }
                                    NumberAnimation { to: 5;  duration: 320 + index * 70; easing.type: Easing.InOutSine }
                                }
                            }
                        }
                    }
                    MouseArea { anchors.fill: parent; onClicked: player.pause() }
                }

                // saved-locally status (delete moved to the header trash action)
                Row {
                    id: dlStatus
                    visible: page.ctaStatusVisible()
                    anchors.left: parent.left; anchors.leftMargin: 14
                    anchors.top: parent.top; anchors.topMargin: 60
                    spacing: 6
                    Image { source: "gfx/icon-check.svg"; width: 14; height: 14; smooth: true; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: qsTr("Saved to phone memory"); font.pixelSize: 12; color: Theme.accentBright; anchors.verticalCenter: parent.verticalCenter }
                    Text { visible: page.downloadedSize !== ""; text: "\xB7 " + page.downloadedSize; font.pixelSize: 12; color: Theme.textDim; anchors.verticalCenter: parent.verticalCenter }
                }
            }

            // ---- show notes ----
            Item {
                width: contentCol.width
                visible: page.notes.length > 0
                height: visible ? notesText.height + 28 : 0

                Text {
                    id: notesText
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    text: page.notes
                    font.pixelSize: 17
                    lineHeight: 1.62
                    color: Theme.textBody
                    wrapMode: Text.WordWrap
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    color: Theme.hairline
                }
            }

            // ---- comments header ----
            Item {
                width: contentCol.width
                visible: page.detailLoaded
                height: visible ? 42 : 0

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Top Comments")
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                    color: Theme.accentBright
                }
                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: page.commentCountText
                    font.pixelSize: 13
                    color: Theme.textDim
                }
            }

            // ---- comment rows ----
            Repeater {
                model: commentModel

                Item {
                    width: contentCol.width
                    height: Math.max(36, cbody.height) + 20

                    Row {
                        id: crow
                        anchors.top: parent.top
                        anchors.topMargin: 10
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 10

                        Rectangle {
                            width: 36
                            height: 36
                            radius: 18
                            clip: true
                            color: "#2a2536"
                            Image {
                                anchors.fill: parent
                                fillMode: Image.PreserveAspectCrop
                                smooth: true
                                asynchronous: true   // decode off the UI thread so a late avatar can't stall a flick
                                sourceSize.width: 36
                                sourceSize.height: 36
                                source: model.avatarUrl
                                visible: model.avatarUrl !== ""
                            }
                            Text {
                                visible: model.avatarUrl === ""
                                anchors.centerIn: parent
                                text: model.name.charAt(0)
                                font.pixelSize: 16
                                font.bold: true
                                color: "#ffffff"
                            }
                        }

                        Column {
                            id: cbody
                            width: crow.width - 86
                            spacing: 4

                            Text {
                                width: parent.width
                                text: model.loc.length > 0 ? model.name + "  ·  " + model.loc : model.name
                                font.pixelSize: 14
                                color: Theme.textDim
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                text: model.text
                                font.pixelSize: 16
                                lineHeight: 1.55
                                color: Theme.text
                                wrapMode: Text.WordWrap
                            }
                        }

                        Column {
                            width: 30
                            spacing: 3
                            Image {
                                source: "gfx/icon-heart.svg"
                                width: 18
                                height: 18
                                smooth: true
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                            Text {
                                text: model.likes
                                font.pixelSize: 12
                                color: Theme.textFaint
                                anchors.horizontalCenter: parent.horizontalCenter
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
            }

            // ---- load-more comments (design: screens-comments.jsx load states) ----
            Item {
                id: loadMoreWrap
                width: contentCol.width
                visible: page.detailLoaded && commentModel.count > 0
                height: visible ? 58 : 0

                // (a) idle → "Load more" + showing-count
                Column {
                    anchors.centerIn: parent
                    spacing: 3
                    visible: xyzApi.hasMoreComments && !page.loadingMoreComments
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: qsTr("Load more")
                        font.pixelSize: 15; font.weight: Font.DemiBold; color: Theme.accentBright
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: qsTr("Showing %1 of %2").arg(commentModel.count).arg(xyzApi.commentsTotal)
                        font.pixelSize: 12; color: Theme.textDim
                    }
                }

                // (b) loading next page → spinner + "Loading more…"
                Row {
                    anchors.centerIn: parent
                    spacing: 9
                    visible: page.loadingMoreComments
                    BusyIndicator {
                        running: page.loadingMoreComments
                        width: 20; height: 20
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Column {
                        spacing: 3; anchors.verticalCenter: parent.verticalCenter
                        Text { text: qsTr("Loading more…"); font.pixelSize: 15; color: Theme.text }
                        Text {
                            text: qsTr("Showing %1 of %2").arg(commentModel.count).arg(xyzApi.commentsTotal)
                            font.pixelSize: 12; color: Theme.textDim
                        }
                    }
                }

                // (c) end → all loaded
                Text {
                    anchors.centerIn: parent
                    visible: !xyzApi.hasMoreComments && !page.loadingMoreComments
                    text: qsTr("All comments loaded")
                    font.pixelSize: 13; color: Theme.textFaint
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: xyzApi.hasMoreComments && !page.loadingMoreComments && !xyzApi.busy
                    onClicked: { page.loadingMoreComments = true; xyzApi.loadMoreComments(); }
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
        width: 40
        height: 40
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

    // ---- delete-download confirmation (design: .scrim / .dialog / .dlg-btn) ----
    Item {
        id: confirmDelete
        anchors.fill: parent
        visible: page.confirmingDelete
        z: 100

        Rectangle {
            anchors.fill: parent
            color: "#99000000"
            MouseArea { anchors.fill: parent; onClicked: page.confirmingDelete = false }
        }

        Rectangle {
            id: dlg
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 24
            anchors.rightMargin: 24
            anchors.verticalCenter: parent.verticalCenter
            height: dlgCol.height
            radius: 9
            clip: true
            color: Theme.panel2
            border.width: 1
            border.color: Theme.hairlineStrong

            Column {
                id: dlgCol
                width: dlg.width

                // title bar (glossy chrome)
                Item {
                    width: parent.width
                    height: 44
                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Theme.chromeHi }
                            GradientStop { position: 1.0; color: Theme.chromeLo }
                        }
                    }
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("Delete download?")
                        font.pixelSize: 15
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

                // message
                Item {
                    width: parent.width
                    height: msgText.height + 32
                    Text {
                        id: msgText
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("This removes the audio file from phone memory. You can download it again anytime.")
                        font.pixelSize: 13
                        color: Theme.textDim
                        wrapMode: Text.WordWrap
                    }
                }

                // actions: Cancel / Delete
                Item {
                    width: parent.width
                    height: 62

                    Rectangle {
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        anchors.top: parent.top
                        width: (parent.width - 42) / 2
                        height: 46
                        radius: 7
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: "#2c2c33" }
                            GradientStop { position: 1.0; color: "#1a1a1f" }
                        }
                        border.width: 1
                        border.color: Theme.hairlineStrong
                        Text {
                            anchors.centerIn: parent
                            text: qsTr("Cancel")
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                            color: Theme.text
                        }
                        MouseArea { anchors.fill: parent; onClicked: page.confirmingDelete = false }
                    }

                    Rectangle {
                        anchors.right: parent.right
                        anchors.rightMargin: 16
                        anchors.top: parent.top
                        width: (parent.width - 42) / 2
                        height: 46
                        radius: 7
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: "#e0564f" }
                            GradientStop { position: 1.0; color: "#b8362f" }
                        }
                        border.width: 1
                        border.color: "#7c1f1a"
                        Row {
                            anchors.centerIn: parent
                            spacing: 7
                            Image {
                                source: "gfx/icon-trash-white.svg"
                                width: 16
                                height: 16
                                smooth: true
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: qsTr("Delete")
                                font.pixelSize: 15
                                font.weight: Font.DemiBold
                                color: "#ffffff"
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                player.deleteDownload(page.eid);
                                page.confirmingDelete = false;
                            }
                        }
                    }
                }
            }
        }
    }

    MiniPlayer {
        id: miniPlayer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        onExpandRequested: page.openPlayerRequested()
    }
}

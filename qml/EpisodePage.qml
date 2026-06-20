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

    // ---- filled from the fetched detail ----
    property string showTitle: ""
    property string notes: ""
    property string commentCountText: ""
    property variant commentModel: []
    property bool detailLoaded: false

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
        page.notes = "";
        page.commentCountText = "";
        page.commentModel = [];
        page.detailLoaded = false;
        page.downloaded = false;
        page.downloadedSize = "";
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
            page.notes = xyzApi.episode.notes;
            page.commentCountText = xyzApi.episode.commentCount;
            page.audioUrl = xyzApi.episode.audioUrl;
            page.audioSizeText = xyzApi.episode.audioSizeText;
            page.detailLoaded = true;
            xyzApi.fetchComments(page.eid);
        }
        onCommentsLoaded: {
            page.commentModel = xyzApi.comments;
        }
    }

    Connections {
        target: player
        // When a download-only completes, state returns to Idle -> re-check the cache.
        onStateChanged: page.refreshDownloaded();
    }

    Rectangle { anchors.fill: parent; color: Theme.bg }

    BelleHeader {
        id: header
        title: qsTr("Episode")
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        onBackClicked: pageStack.pop()
    }

    Flickable {
        id: scroll
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
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

                    Text {
                        width: parent.width
                        text: page.showTitle
                        visible: page.showTitle.length > 0
                        font.pixelSize: 14
                        color: Theme.accentBright
                        elide: Text.ElideRight
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

                // on-device status + delete (under the button when cached)
                Row {
                    id: dlStatus
                    visible: page.ctaStatusVisible()
                    anchors.left: parent.left; anchors.leftMargin: 14
                    anchors.top: parent.top; anchors.topMargin: 60
                    spacing: 6
                    Image { source: "gfx/icon-check.svg"; width: 14; height: 14; smooth: true; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: qsTr("On device"); font.pixelSize: 12; color: Theme.accentBright; anchors.verticalCenter: parent.verticalCenter }
                    Text { visible: page.downloadedSize !== ""; text: "\xB7 " + page.downloadedSize; font.pixelSize: 12; color: Theme.textDim; anchors.verticalCenter: parent.verticalCenter }
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
                    font.pixelSize: 15
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
                model: page.commentModel

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
                                sourceSize.width: 36
                                sourceSize.height: 36
                                source: modelData.avatarUrl
                                visible: modelData.avatarUrl !== ""
                            }
                            Text {
                                visible: modelData.avatarUrl === ""
                                anchors.centerIn: parent
                                text: modelData.name.charAt(0)
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
                                text: modelData.loc.length > 0 ? modelData.name + "  ·  " + modelData.loc : modelData.name
                                font.pixelSize: 13
                                color: Theme.textDim
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                text: modelData.text
                                font.pixelSize: 15
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
                                text: modelData.likes
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
}

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
        page.showTitle = "";
        page.notes = "";
        page.commentCountText = "";
        page.commentModel = [];
        page.detailLoaded = false;
    }

    function subLine() {
        if (page.whenText.length > 0 && page.durationText.length > 0) {
            return page.durationText + "  ·  " + page.whenText;
        }
        return page.durationText + page.whenText;
    }

    onStatusChanged: {
        if (status === PageStatus.Active && page.eid !== "" && !page.detailLoaded) {
            xyzApi.fetchEpisode(page.eid);
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
            page.detailLoaded = true;
            xyzApi.fetchComments(page.eid);
        }
        onCommentsLoaded: {
            page.commentModel = xyzApi.comments;
        }
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

            // ---- Play CTA (inert — player deferred) ----
            Item {
                width: contentCol.width
                height: 66

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    anchors.top: parent.top
                    anchors.topMargin: 6
                    height: 46
                    radius: 6
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Theme.accentBright }
                        GradientStop { position: 1.0; color: Theme.accentDeep }
                    }

                    Row {
                        anchors.centerIn: parent
                        spacing: 10
                        Image {
                            source: "gfx/icon-play-white.svg"
                            width: 22
                            height: 22
                            smooth: true
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: qsTr("Play")
                            font.pixelSize: 15
                            font.bold: true
                            color: "#ffffff"
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
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

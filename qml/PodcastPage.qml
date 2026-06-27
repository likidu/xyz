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

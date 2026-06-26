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

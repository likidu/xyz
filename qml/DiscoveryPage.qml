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
    signal searchRequested

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
            anchors.right: searchButton.left
            anchors.verticalCenter: parent.verticalCenter
            text: qsTr("Discover")
            font.pixelSize: 24
            font.bold: true
            color: Theme.text
            elide: Text.ElideRight
        }

        // search → push the Search page (design: screens-feed.jsx header action)
        Item {
            id: searchButton
            width: 44
            height: 44
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
                anchors.fill: parent
                radius: 4
                color: Theme.accentDeep
                opacity: searchMouse.pressed ? 0.4 : 0
            }
            Image {
                source: "gfx/tab-search.svg"
                width: 24
                height: 24
                smooth: true
                anchors.centerIn: parent
            }
            MouseArea {
                id: searchMouse
                anchors.fill: parent
                onClicked: page.searchRequested()
            }
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

                        EpisodeCard {
                            width: sectionsColumn.width
                            item: modelData
                            onClicked: page.episodeRequested(modelData)
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

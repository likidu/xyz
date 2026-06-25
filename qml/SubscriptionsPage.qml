import QtQuick 1.1
import com.nokia.symbian 1.1
import "js/Theme.js" as Theme

// Subscriptions — 我的订阅 grid + list (design: screens-subs.jsx).
// Data from /v1/subscription/list via the native xyzApi client.
Page {
    id: page
    objectName: "SubscriptionsPage"

    property bool hidesToolBar: true
    property bool loadedOnce: false
    property string viewMode: "grid"

    signal tabSelected(int index)
    signal openPlayerRequested

    function load() {
        if (page.loadedOnce) {
            return;
        }
        xyzApi.fetchSubscriptions();
    }

    function toggleView() {
        page.viewMode = (page.viewMode === "grid") ? "list" : "grid";
    }

    onStatusChanged: {
        if (status === PageStatus.Active) {
            page.load();
        }
    }

    // Mark loaded only on success, so an aborted/failed fetch retries on the next
    // activation instead of stranding an empty list.
    Connections {
        target: xyzApi
        onSubscriptionsLoaded: page.loadedOnce = true
    }

    Rectangle { anchors.fill: parent; color: Theme.bg }

    BelleHeader {
        id: header
        title: qsTr("Subscriptions")
        actionIconSource: page.viewMode === "grid" ? "gfx/icon-list.svg" : "gfx/icon-grid.svg"
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        onBackClicked: pageStack.pop()
        onActionClicked: page.toggleView()
    }

    Item {
        id: content
        anchors.top: header.bottom
        anchors.bottom: miniPlayer.visible ? miniPlayer.top : tabBar.top
        anchors.left: parent.left
        anchors.right: parent.right
        clip: true

        // ---- GRID ----
        GridView {
            id: grid
            anchors.fill: parent
            visible: page.viewMode === "grid"
            model: xyzApi.subscriptions
            cellWidth: Math.floor(width / 3)
            cellHeight: cellWidth
            clip: true
            delegate: Item {
                width: grid.cellWidth
                height: grid.cellHeight

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    color: "#1a1a22"
                    clip: true

                    Image {
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        smooth: true
                        sourceSize.width: 120
                        sourceSize.height: 120
                        source: modelData.coverUrl
                    }
                }

                Rectangle {
                    visible: modelData.often
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.margins: 6
                    height: 18
                    width: oftenText.width + 12
                    radius: 4
                    color: "#C7080612"
                    border.width: 1
                    border.color: "#808b6dff"
                    Text {
                        id: oftenText
                        anchors.centerIn: parent
                        text: qsTr("Often")
                        font.pixelSize: 10
                        font.bold: true
                        color: Theme.accentBright
                    }
                }
            }
        }

        // ---- LIST ----
        ListView {
            id: subsList
            anchors.fill: parent
            visible: page.viewMode === "list"
            model: xyzApi.subscriptions
            clip: true
            header: listHeader
            delegate: rowDelegate
        }
    }

    // list header: search + starred empty-state + "All Subscriptions" subhead
    Component {
        id: listHeader
        Column {
            width: subsList.width

            Item {
                width: parent.width
                height: 56
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    anchors.top: parent.top
                    anchors.topMargin: 10
                    height: 42
                    radius: 7
                    color: "#161619"
                    border.width: 1
                    border.color: Theme.hairline
                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 13
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 9
                        Image { source: "gfx/tab-search.svg"; width: 17; height: 17; smooth: true; opacity: 0.6; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: qsTr("Search your subscriptions"); font.pixelSize: 15; color: Theme.textFaint; anchors.verticalCenter: parent.verticalCenter }
                    }
                }
            }

            Item {
                width: parent.width
                height: 32
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 8
                    text: qsTr("Starred")
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                    color: Theme.accentBright
                }
            }

            Item {
                width: parent.width
                height: 118
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    anchors.top: parent.top
                    height: 108
                    radius: 9
                    border.width: 1
                    border.color: Theme.hairline
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Theme.panel2 }
                        GradientStop { position: 1.0; color: Theme.panel }
                    }
                    Column {
                        anchors.centerIn: parent
                        spacing: 8
                        Text {
                            width: 220
                            text: qsTr("Star shows you love for a shortcut on the Updates page")
                            font.pixelSize: 14
                            color: Theme.textDim
                            wrapMode: Text.WordWrap
                            horizontalAlignment: Text.AlignHCenter
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                        Text {
                            text: "+ " + qsTr("Add")
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                            color: Theme.accentBright
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }
                }
            }

            Item {
                width: parent.width
                height: 32
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 8
                    text: qsTr("All Subscriptions")
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                    color: Theme.accentBright
                }
            }
        }
    }

    // list row: cover + name + avatar stack + hosts·when + dots
    Component {
        id: rowDelegate
        Item {
            width: subsList.width
            height: 72

            Row {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12

                Rectangle {
                    width: 52
                    height: 52
                    color: "#1a1a22"
                    clip: true
                    anchors.verticalCenter: parent.verticalCenter

                    Image {
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        smooth: true
                        sourceSize.width: 52
                        sourceSize.height: 52
                        source: modelData.coverUrl
                    }
                }

                Column {
                    width: subsList.width - 24 - 52 - 12 - 30
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5

                    Text {
                        width: parent.width
                        text: modelData.name
                        font.pixelSize: 16
                        font.weight: Font.DemiBold
                        color: Theme.text
                        elide: Text.ElideRight
                    }
                    Row {
                        width: parent.width
                        spacing: 7

                        Row {
                            spacing: 3
                            anchors.verticalCenter: parent.verticalCenter
                            Repeater {
                                model: modelData.avatarUrls
                                Rectangle {
                                    width: 19
                                    height: 19
                                    radius: 4
                                    clip: true
                                    color: "#232030"
                                    Image {
                                        anchors.fill: parent
                                        fillMode: Image.PreserveAspectCrop
                                        smooth: true
                                        sourceSize.width: 19
                                        sourceSize.height: 19
                                        source: modelData
                                    }
                                }
                            }
                        }
                        Text {
                            text: modelData.hostsText + "  ·  " + modelData.whenText
                            font.pixelSize: 13
                            color: Theme.textDim
                            elide: Text.ElideRight
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }

                Image {
                    source: "gfx/icon-dots.svg"
                    width: 18
                    height: 18
                    smooth: true
                    opacity: 0.8
                    anchors.verticalCenter: parent.verticalCenter
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

    // ---- states ----
    BusyIndicator {
        running: xyzApi.busy && xyzApi.subscriptions.length === 0
        visible: running
        width: 48
        height: 48
        anchors.centerIn: content
    }
    Text {
        visible: !xyzApi.busy && xyzApi.errorMessage.length > 0 && xyzApi.subscriptions.length === 0
        anchors.centerIn: content
        width: content.width - 48
        text: xyzApi.errorMessage
        color: Theme.errorColor
        font.pixelSize: 13
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
    }
    Text {
        visible: !xyzApi.busy && xyzApi.errorMessage.length === 0 && xyzApi.subscriptions.length === 0 && page.loadedOnce
        anchors.centerIn: content
        text: qsTr("No subscriptions yet")
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
        activeIndex: 1
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        onTabSelected: page.tabSelected(index)
    }
}

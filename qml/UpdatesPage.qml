import QtQuick 1.1
import com.nokia.symbian 1.1
import "js/Theme.js" as Theme

// Updates — subscription tab landing feed (design: screens-updates.jsx).
// Episode cards from /v1/inbox/list via the native xyzApi client.
Page {
    id: page
    objectName: "UpdatesPage"

    property bool hidesToolBar: true
    property bool loadedOnce: false

    signal mySubsRequested
    signal tabSelected(int index)
    signal episodeRequested(variant item)
    signal openPlayerRequested

    function load() {
        if (page.loadedOnce) {
            return;
        }
        xyzApi.fetchInbox();
    }

    onStatusChanged: {
        if (status === PageStatus.Active) {
            page.load();
        }
    }

    // Mark loaded only on success, so an aborted/failed fetch (e.g. the user
    // taps My Subscriptions mid-load, which cancels the in-flight reply) retries
    // on the next activation instead of stranding an empty feed.
    Connections {
        target: xyzApi
        onInboxLoaded: page.loadedOnce = true
    }

    Rectangle { anchors.fill: parent; color: Theme.bg }

    // ---- glossy title bar (design .up-titlebar) ----
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
            text: qsTr("Updates")
            font.pixelSize: 24
            font.bold: true
            color: Theme.text
        }

        Rectangle {
            id: mySubsBtn
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            height: 34
            width: mySubsRow.width + 26
            radius: 8
            color: "#248b6dff"
            border.width: 1
            border.color: "#618b6dff"
            opacity: mySubsMouse.pressed ? 0.7 : 1.0

            Row {
                id: mySubsRow
                anchors.centerIn: parent
                spacing: 7
                Image {
                    source: "gfx/tab-headphones.svg"
                    width: 16
                    height: 16
                    smooth: true
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: qsTr("My Subscriptions")
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    color: Theme.accentBright
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
            MouseArea {
                id: mySubsMouse
                anchors.fill: parent
                onClicked: page.mySubsRequested()
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

    // ---- feed ----
    ListView {
        id: list
        anchors.top: titleBar.bottom
        anchors.bottom: miniPlayer.visible ? miniPlayer.top : tabBar.top
        anchors.left: parent.left
        anchors.right: parent.right
        clip: true
        model: xyzApi.inboxItems
        delegate: updateDelegate
    }

    Component {
        id: updateDelegate
        Item {
            width: list.width
            height: col.height + 28

            // Whole-card tap target → open the Episode page. It sits behind the visual
            // content (none of which grabs the mouse), so a tap anywhere on the row is
            // caught here, while the ListView still receives drags for flicking. The
            // earlier cover+title-only target missed taps on the description / meta /
            // play area, which read as "the item isn't tappable" on the small screen.
            MouseArea {
                id: cardMouse
                anchors.fill: parent
                onClicked: page.episodeRequested(modelData)
            }

            Column {
                id: col
                anchors.top: parent.top
                anchors.topMargin: 14
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 14

                Row {
                    width: parent.width
                    spacing: 12

                    Rectangle {
                        width: 70
                        height: 70
                        radius: 6
                        color: "#1a1a22"
                        clip: true
                        Image {
                            anchors.fill: parent
                            fillMode: Image.PreserveAspectCrop
                            smooth: true
                            sourceSize.width: 70
                            sourceSize.height: 70
                            source: modelData.coverUrl
                        }
                    }

                    Column {
                        width: parent.width - 82
                        spacing: 6

                        Text {
                            width: parent.width
                            text: modelData.title
                            font.pixelSize: 17
                            font.bold: true
                            color: Theme.text
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: modelData.desc
                            font.pixelSize: 15
                            color: Theme.textBody
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                    }
                }

                // meta row (dot separators avoid unicode tofu on Symbian)
                Row {
                    width: parent.width
                    spacing: 10

                    Text { text: modelData.durationText; font.pixelSize: 14; color: Theme.textDim; anchors.verticalCenter: parent.verticalCenter }
                    Rectangle { width: 3; height: 3; radius: 1.5; color: Theme.textFaint; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: modelData.whenText; font.pixelSize: 14; color: Theme.textDim; anchors.verticalCenter: parent.verticalCenter }
                    Rectangle { width: 3; height: 3; radius: 1.5; color: Theme.textFaint; anchors.verticalCenter: parent.verticalCenter }
                    Row {
                        spacing: 4
                        anchors.verticalCenter: parent.verticalCenter
                        Image { source: "gfx/tab-headphones.svg"; width: 14; height: 14; smooth: true; opacity: 0.7; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: modelData.playCount; font.pixelSize: 14; color: Theme.textDim; anchors.verticalCenter: parent.verticalCenter }
                    }
                    Rectangle { width: 3; height: 3; radius: 1.5; color: Theme.textFaint; anchors.verticalCenter: parent.verticalCenter }
                    Row {
                        spacing: 4
                        anchors.verticalCenter: parent.verticalCenter
                        Image { source: "gfx/icon-comment.svg"; width: 14; height: 14; smooth: true; opacity: 0.7; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: modelData.commentCount; font.pixelSize: 14; color: Theme.textDim; anchors.verticalCenter: parent.verticalCenter }
                    }
                }
            }

            // press feedback (native Belle rows highlight on press) — a faint accent
            // wash also makes it obvious on-device that the tap registered.
            Rectangle {
                anchors.fill: parent
                color: Theme.accent
                opacity: cardMouse.pressed ? 0.10 : 0
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
        running: xyzApi.busy && list.count === 0
        visible: running
        width: 48
        height: 48
        anchors.centerIn: list
    }
    Text {
        visible: !xyzApi.busy && xyzApi.errorMessage.length > 0 && list.count === 0
        anchors.centerIn: list
        width: list.width - 48
        text: xyzApi.errorMessage
        color: Theme.errorColor
        font.pixelSize: 13
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
    }
    Text {
        visible: !xyzApi.busy && xyzApi.errorMessage.length === 0 && list.count === 0 && page.loadedOnce
        anchors.centerIn: list
        text: qsTr("No updates yet")
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

import QtQuick 1.1
import com.nokia.symbian 1.1
import "js/Theme.js" as Theme

// Episode search — a search bar at the top, results as episode cards below.
// Pushed from the Discovery header's search button. Hides the system toolbar, so
// it carries its own back button (emits backRequested; the host pops the stack).
Page {
    id: page
    objectName: "SearchPage"

    property bool hidesToolBar: true
    // Becomes true once a query has been submitted, so the idle hint and the
    // "no results" / error states only show after the first search.
    property bool searched: false

    signal episodeRequested(variant item)
    signal backRequested

    function runSearch() {
        if (searchInput.text.length === 0) {
            return;
        }
        page.searched = true;
        xyzApi.search(searchInput.text);
        searchInput.closeSoftwareInputPanel();
    }

    onStatusChanged: {
        if (status === PageStatus.Active) {
            searchInput.forceActiveFocus();
            searchInput.openSoftwareInputPanel();
        }
    }

    Rectangle { anchors.fill: parent; color: Theme.bg }

    // ---- search bar header ----
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

        Item {
            id: backButton
            width: 44
            height: 44
            anchors.left: parent.left
            anchors.leftMargin: 4
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
                anchors.fill: parent
                radius: 4
                color: Theme.accentDeep
                opacity: backMouse.pressed ? 0.4 : 0
            }
            Image {
                source: "gfx/icon-back.svg"
                width: 26
                height: 26
                anchors.centerIn: parent
            }
            MouseArea {
                id: backMouse
                anchors.fill: parent
                onClicked: page.backRequested()
            }
        }

        Rectangle {
            id: field
            anchors.left: backButton.right
            anchors.leftMargin: 4
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            height: 38
            radius: Theme.cornerRadius
            border.color: Theme.hairlineStrong
            border.width: 1
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#0c0c0e" }
                GradientStop { position: 1.0; color: "#161619" }
            }

            Image {
                id: magnifier
                source: "gfx/tab-search.svg"
                width: 18
                height: 18
                smooth: true
                opacity: 0.8
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
            }

            TextInput {
                id: searchInput
                anchors.left: magnifier.right
                anchors.leftMargin: 8
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                font.pixelSize: 16
                color: Theme.text
                cursorDelegate: Rectangle {
                    width: 2
                    height: 20
                    color: Theme.accentBright
                }
                onAccepted: page.runSearch()
            }

            Text {
                anchors.left: magnifier.right
                anchors.leftMargin: 8
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("Search episodes")
                font.pixelSize: 16
                color: Theme.textFaint
                visible: searchInput.text.length === 0
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

    // ---- results ----
    Flickable {
        id: scroller
        anchors.top: titleBar.bottom
        anchors.topMargin: 8
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        clip: true
        contentWidth: width
        contentHeight: resultsColumn.height

        // Top gap comes from the Flickable's topMargin (not a leading spacer); a
        // trailing spacer clears the last card. Mirrors DiscoveryPage's result list.
        Column {
            id: resultsColumn
            width: scroller.width

            Repeater {
                model: xyzApi.searchResults

                EpisodeCard {
                    width: resultsColumn.width
                    item: modelData
                    onClicked: page.episodeRequested(modelData)
                }
            }

            Item { width: parent.width; height: 16 }
        }
    }

    // ---- states ----
    BusyIndicator {
        running: page.searched && xyzApi.busy
        visible: running
        width: 48
        height: 48
        anchors.centerIn: scroller
    }
    Text {
        visible: !page.searched
        anchors.centerIn: scroller
        text: qsTr("Search episodes by keyword")
        color: Theme.textDim
        font.pixelSize: 14
    }
    Text {
        visible: page.searched && !xyzApi.busy && xyzApi.errorMessage.length > 0
        anchors.centerIn: scroller
        width: scroller.width - 48
        text: xyzApi.errorMessage
        color: Theme.errorColor
        font.pixelSize: 13
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
    }
    Text {
        visible: page.searched && !xyzApi.busy && xyzApi.errorMessage.length === 0
                 && xyzApi.searchResults.length === 0
        anchors.centerIn: scroller
        text: qsTr("No episodes found")
        color: Theme.textDim
        font.pixelSize: 14
    }
}

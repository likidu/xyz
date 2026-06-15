import QtQuick 1.1
import "js/Theme.js" as Theme

// Glossy Belle view header (design: belle.css .header) — used on pages that
// hide the system toolbar (pre-login flow).
Rectangle {
    id: header

    property alias title: titleText.text
    property bool showBack: true
    property string actionIconSource: ""
    property bool actionOn: false
    signal backClicked
    signal actionClicked

    height: Theme.headerHeight
    gradient: Gradient {
        GradientStop { position: 0.0; color: Theme.chromeHi }
        GradientStop { position: 0.06; color: "#232328" }
        GradientStop { position: 0.6; color: "#1a1a1e" }
        GradientStop { position: 1.0; color: Theme.chromeLo }
    }

    Item {
        id: backButton
        visible: header.showBack
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
            onClicked: header.backClicked()
        }
    }

    Text {
        id: titleText
        anchors.left: header.showBack ? backButton.right : parent.left
        anchors.leftMargin: header.showBack ? 8 : 16
        anchors.right: actionButton.visible ? actionButton.left : parent.right
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        font.pixelSize: 19
        font.weight: Font.DemiBold
        color: Theme.text
        elide: Text.ElideRight
    }

    Item {
        id: actionButton
        visible: header.actionIconSource !== ""
        width: 44
        height: 44
        anchors.right: parent.right
        anchors.rightMargin: 4
        anchors.verticalCenter: parent.verticalCenter

        Rectangle {
            anchors.fill: parent
            radius: 4
            color: Theme.accentDeep
            opacity: actionMouse.pressed ? 0.4 : 0
        }
        Image {
            source: header.actionIconSource
            width: 24
            height: 24
            smooth: true
            anchors.centerIn: parent
            opacity: header.actionOn ? 1.0 : 0.8
        }
        MouseArea {
            id: actionMouse
            anchors.fill: parent
            onClicked: header.actionClicked()
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

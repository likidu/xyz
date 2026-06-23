import QtQuick 1.1
import com.nokia.symbian 1.1
import "js/Theme.js" as Theme

// Minimal post-login placeholder: proves the login API round-trip by showing
// the stored profile + token state. Real home/discover screens come later.
Page {
    id: page
    objectName: "HomePage"

    property bool hidesToolBar: true
    property string nickname: ""
    property string uid: ""
    property string phoneLabel: ""
    property bool hasToken: false

    signal signedOut
    signal selfTestRequested
    signal tabSelected(int index)
    signal openPlayerRequested

    function reload() {
        nickname = storage.value("auth.nickname", "");
        uid = storage.value("auth.uid", "");
        phoneLabel = storage.value("auth.areaCode", "") + " " + storage.value("auth.phone", "");
        hasToken = storage.value("auth.accessToken", "") !== "";
    }

    function signOut() {
        auth.logout();
        signedOut();
    }

    onStatusChanged: {
        if (status === PageStatus.Activating) {
            reload();
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.bg
    }

    BelleHeader {
        id: header
        title: qsTr("Account")
        showBack: false
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
    }

    Column {
        anchors.top: header.bottom
        anchors.topMargin: 46
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Theme.pagePadding
        anchors.rightMargin: Theme.pagePadding
        spacing: 8

        Image {
            source: "gfx/login-orb.svg"
            width: 76
            height: 76
            anchors.horizontalCenter: parent.horizontalCenter
        }
        Item { width: 1; height: 8 }
        Text {
            text: page.nickname.length > 0 ? page.nickname : qsTr("Signed in")
            font.pixelSize: 21
            font.bold: true
            color: Theme.text
            anchors.horizontalCenter: parent.horizontalCenter
        }
        Text {
            text: page.phoneLabel
            font.pixelSize: 13
            color: Theme.textDim
            anchors.horizontalCenter: parent.horizontalCenter
        }
        Text {
            text: "uid: " + page.uid
            visible: page.uid.length > 0
            font.pixelSize: 12
            color: Theme.textFaint
            anchors.horizontalCenter: parent.horizontalCenter
        }
        Item { width: 1; height: 10 }
        Text {
            text: page.hasToken ? qsTr("API token stored. Login OK.") : qsTr("No API token stored")
            font.pixelSize: 13
            color: page.hasToken ? Theme.accentBright : Theme.errorColor
            anchors.horizontalCenter: parent.horizontalCenter
        }
        Item { width: 1; height: 18 }
        Rectangle {
            width: parent.width
            height: Theme.buttonHeight
            radius: Theme.cornerRadius
            border.width: 1
            border.color: Theme.hairlineStrong
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#2a2a30" }
                GradientStop { position: 1.0; color: "#1d1d22" }
            }
            opacity: signOutMouse.pressed ? 0.8 : 1.0

            Text {
                anchors.centerIn: parent
                text: qsTr("Sign out")
                font.pixelSize: 16
                font.bold: true
                color: Theme.textDim
            }
            MouseArea {
                id: signOutMouse
                anchors.fill: parent
                onClicked: page.signOut()
            }
        }

        Item { width: 1; height: 8 }
        // Dev affordance: jump to the subsystem self-test (incl. the player harness).
        Rectangle {
            width: parent.width
            height: Theme.buttonHeight
            radius: Theme.cornerRadius
            border.width: 1
            border.color: Theme.hairlineStrong
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#2a2a30" }
                GradientStop { position: 1.0; color: "#1d1d22" }
            }
            opacity: selfTestMouse.pressed ? 0.8 : 1.0

            Text {
                anchors.centerIn: parent
                text: qsTr("Self-test")
                font.pixelSize: 16
                font.bold: true
                color: Theme.textDim
            }
            MouseArea {
                id: selfTestMouse
                anchors.fill: parent
                onClicked: page.selfTestRequested()
            }
        }
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
        activeIndex: 3
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        onTabSelected: page.tabSelected(index)
    }
}

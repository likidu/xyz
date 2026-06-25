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
    property string audioResetMsg: ""

    signal signedOut
    signal selfTestRequested
    signal downloadsRequested
    signal tabSelected(int index)
    signal openPlayerRequested

    // Subtitle for the Downloads nav row; reads downloads.count/downloadsText so it
    // re-evaluates whenever the registry changes.
    function downloadsSubtitle() {
        if (downloads.count === 0) {
            return qsTr("No downloads yet");
        }
        var ep = (downloads.count === 1) ? qsTr("1 episode")
                                         : qsTr("%1 episodes").arg(downloads.count);
        if (downloads.downloadsText !== "") {
            return qsTr("%1 · %2 on device").arg(ep).arg(downloads.downloadsText);
        }
        return qsTr("%1 on device").arg(ep);
    }

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

    // Soft "reset audio": recreate the QMediaPlayer to drop our DevSound session, to try
    // to recover a wedged MMF output (the -14/KErrInUse) without a full phone reboot.
    function resetAudio() {
        player.stop();
        audioEngine.releaseFile();
        page.audioResetMsg = qsTr("Audio engine reset");
        resetMsgTimer.restart();
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

    // Account content scrolls — on the small nHD screen the profile + Downloads
    // entry + action buttons overflow under the tab bar (design: .content > .scroll).
    Flickable {
        id: accountScroll
        anchors.top: header.bottom
        anchors.bottom: miniPlayer.visible ? miniPlayer.top : tabBar.top
        anchors.left: parent.left
        anchors.right: parent.right
        clip: true
        contentWidth: width
        contentHeight: acctCol.height + 70
        flickableDirection: Flickable.VerticalFlick

        Column {
        id: acctCol
        anchors.top: parent.top
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

        Item { width: 1; height: 14 }
        // Downloads entry (design: .acct-nav / .nav-row)
        Rectangle {
            width: parent.width
            height: 64
            radius: 9
            border.width: 1
            border.color: Theme.hairline
            gradient: Gradient {
                GradientStop { position: 0.0; color: Theme.panel2 }
                GradientStop { position: 1.0; color: Theme.panel }
            }
            opacity: downloadsMouse.pressed ? 0.85 : 1.0

            Row {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 13

                Rectangle {
                    width: 40
                    height: 40
                    radius: 10
                    anchors.verticalCenter: parent.verticalCenter
                    color: "#248b6dff"
                    border.width: 1
                    border.color: Theme.accent
                    Image {
                        source: "gfx/icon-download.svg"
                        width: 22
                        height: 22
                        smooth: true
                        anchors.centerIn: parent
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 40 - 13 - 20 - 13
                    spacing: 3
                    Text {
                        text: qsTr("Downloads")
                        font.pixelSize: 16
                        font.weight: Font.DemiBold
                        color: Theme.text
                    }
                    Text {
                        width: parent.width
                        text: page.downloadsSubtitle()
                        font.pixelSize: 13
                        color: Theme.textDim
                        elide: Text.ElideRight
                    }
                }

                Image {
                    source: "gfx/icon-chevron.svg"
                    width: 20
                    height: 20
                    smooth: true
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
            MouseArea {
                id: downloadsMouse
                anchors.fill: parent
                onClicked: page.downloadsRequested()
            }
        }

        Item { width: 1; height: 14 }
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

        Item { width: 1; height: 8 }
        // Soft audio reset: recreate the media player to recover a wedged MMF output
        // (-14/KErrInUse) without rebooting the phone.
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
            opacity: resetAudioMouse.pressed ? 0.8 : 1.0

            Text {
                anchors.centerIn: parent
                text: qsTr("Reset audio")
                font.pixelSize: 16
                font.bold: true
                color: Theme.textDim
            }
            MouseArea {
                id: resetAudioMouse
                anchors.fill: parent
                onClicked: page.resetAudio()
            }
        }
        Text {
            text: page.audioResetMsg
            visible: page.audioResetMsg.length > 0
            font.pixelSize: 13
            color: Theme.accentBright
            anchors.horizontalCenter: parent.horizontalCenter
        }
        }
    }

    Timer {
        id: resetMsgTimer
        interval: 2500
        onTriggered: page.audioResetMsg = ""
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
        activeIndex: 2
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        onTabSelected: page.tabSelected(index)
    }
}

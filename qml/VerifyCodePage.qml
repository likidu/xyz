import QtQuick 1.1
import com.nokia.symbian 1.1
import "js/Theme.js" as Theme

// SMS code entry (design: screens-login.jsx LoginCode state). Auth via the
// native `auth` client.
Page {
    id: page
    objectName: "VerifyCodePage"

    property bool hidesToolBar: true
    property string phone: ""
    property string areaCode: "+86"
    property int resendSeconds: 60
    property int codeLength: 4
    property bool codeComplete: codeInput.text.length === codeLength

    signal loggedIn

    function reset() {
        codeInput.text = "";
        resendSeconds = 60;
    }

    function doLogin() {
        if (auth.busy || !codeComplete) {
            return;
        }
        auth.login(phone, areaCode, codeInput.text);
    }

    function resendCode() {
        if (auth.busy || resendSeconds > 0) {
            return;
        }
        auth.sendCode(phone, areaCode);
    }

    Connections {
        target: auth
        onLoginSucceeded: {
            if (page.status === PageStatus.Active) {
                page.loggedIn();
            }
        }
        onSendCodeSucceeded: {
            if (page.status === PageStatus.Active) {
                page.resendSeconds = 60;
            }
        }
    }

    onStatusChanged: {
        if (status === PageStatus.Active) {
            codeInput.forceActiveFocus();
            // codeInput is an invisible 1x1 field that can't be tapped, and
            // forceActiveFocus alone doesn't raise the Symbian VKB — open it explicitly.
            codeInput.openSoftwareInputPanel();
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: page.resendSeconds > 0 && page.status === PageStatus.Active
        onTriggered: page.resendSeconds = page.resendSeconds - 1
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.bg
    }

    BelleHeader {
        id: header
        title: qsTr("Verify")
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        onBackClicked: pageStack.pop()
    }

    Item {
        id: body
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Theme.pagePadding
        anchors.rightMargin: Theme.pagePadding

        Text {
            id: headText
            anchors.top: parent.top
            anchors.topMargin: 30
            anchors.left: parent.left
            text: qsTr("Enter the %1-digit code").arg(page.codeLength)
            font.pixelSize: 16
            font.weight: Font.DemiBold
            color: Theme.text
        }

        Text {
            id: codeSub
            anchors.top: headText.bottom
            anchors.topMargin: 14
            anchors.left: parent.left
            anchors.right: parent.right
            text: qsTr("Code sent to") + " <font color=\"#f3f3f6\"><b>" + page.areaCode + " " + page.phone + "</b></font> " + qsTr("via SMS")
            font.pixelSize: 13
            color: Theme.textDim
            wrapMode: Text.WordWrap
        }

        TextInput {
            id: codeInput
            width: 1
            height: 1
            opacity: 0
            inputMethodHints: Qt.ImhDigitsOnly
            maximumLength: page.codeLength
            validator: RegExpValidator { regExp: /\d*/ }
            onAccepted: page.doLogin()
        }

        Row {
            id: boxes
            anchors.top: codeSub.bottom
            anchors.topMargin: 24
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 9

            Repeater {
                model: page.codeLength
                Rectangle {
                    width: Math.floor((boxes.width - 9 * (page.codeLength - 1)) / page.codeLength)
                    height: 56
                    radius: Theme.cornerRadius
                    border.width: 1
                    border.color: index === codeInput.text.length && !page.codeComplete ? Theme.accent : Theme.hairlineStrong
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#0c0c0e" }
                        GradientStop { position: 1.0; color: "#161619" }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: codeInput.text.charAt(index)
                        font.pixelSize: 24
                        font.bold: true
                        color: Theme.text
                    }
                }
            }
        }

        MouseArea {
            anchors.fill: boxes
            onClicked: {
                codeInput.forceActiveFocus();
                codeInput.openSoftwareInputPanel();
            }
        }

        Text {
            id: resendLine
            anchors.top: boxes.bottom
            anchors.topMargin: 18
            anchors.left: parent.left
            anchors.right: parent.right
            text: qsTr("Didn't get it?") + " <b>" + (page.resendSeconds > 0 ? qsTr("Resend") + " (" + page.resendSeconds + "s)" : "<font color=\"#a98cff\">" + qsTr("Resend") + "</font>") + "</b>"
            font.pixelSize: 13
            color: Theme.textDim

            MouseArea {
                anchors.fill: parent
                onClicked: page.resendCode()
            }
        }

        Rectangle {
            id: signInButton
            anchors.top: resendLine.bottom
            anchors.topMargin: 22
            anchors.left: parent.left
            anchors.right: parent.right
            height: Theme.buttonHeight
            radius: Theme.cornerRadius
            gradient: page.codeComplete && !auth.busy ? enabledGradient : disabledGradient
            opacity: signInMouse.pressed && page.codeComplete && !auth.busy ? 0.8 : 1.0

            Gradient {
                id: enabledGradient
                GradientStop { position: 0.0; color: Theme.accentBright }
                GradientStop { position: 1.0; color: Theme.accentDeep }
            }
            Gradient {
                id: disabledGradient
                GradientStop { position: 0.0; color: "#2a2a30" }
                GradientStop { position: 1.0; color: "#1d1d22" }
            }

            Text {
                anchors.centerIn: parent
                text: auth.busy ? qsTr("Signing in...") : qsTr("Sign in")
                font.pixelSize: 16
                font.bold: true
                color: page.codeComplete && !auth.busy ? "#ffffff" : Theme.textFaint
            }

            MouseArea {
                id: signInMouse
                anchors.fill: parent
                onClicked: page.doLogin()
            }
        }

        Text {
            anchors.top: signInButton.bottom
            anchors.topMargin: 12
            anchors.left: parent.left
            anchors.right: parent.right
            text: auth.errorMessage
            visible: auth.errorMessage.length > 0
            font.pixelSize: 12
            color: Theme.errorColor
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
        }
    }
}

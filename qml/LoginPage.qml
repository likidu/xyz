import QtQuick 1.1
import com.nokia.symbian 1.1
import "js/Theme.js" as Theme
import "js/Api.js" as Api

// SMS login — phone entry + country picker overlay (design: screens-login.jsx
// LoginPhone / LoginCountry states).
Page {
    id: page
    objectName: "LoginPage"

    property bool hidesToolBar: true
    property string areaCode: "+86"
    property string regionAbbrev: "CN"
    property bool busy: false
    property string errorText: ""
    property bool pickerOpen: false
    property bool submitEnabled: !busy && phoneInput.text.length >= 5

    signal codeSent(string phone, string areaCode)
    signal exitRequested

    function requestCode() {
        if (!submitEnabled) {
            return;
        }
        busy = true;
        errorText = "";
        var phone = phoneInput.text;
        var area = areaCode;
        Api.sendCode(phone, area, function (ok, msg) {
            page.busy = false;
            if (ok) {
                page.codeSent(phone, area);
            } else {
                page.errorText = msg;
            }
        });
    }

    function selectRegion(abbrev, code) {
        regionAbbrev = abbrev;
        areaCode = code;
        pickerOpen = false;
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.bg
    }

    BelleHeader {
        id: header
        title: qsTr("Sign in")
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        onBackClicked: page.exitRequested()
    }

    Item {
        id: body
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Theme.pagePadding
        anchors.rightMargin: Theme.pagePadding

        Column {
            id: brand
            anchors.top: parent.top
            anchors.topMargin: 46
            anchors.horizontalCenter: parent.horizontalCenter

            Image {
                source: "gfx/login-orb.svg"
                width: 76
                height: 76
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Item { width: 1; height: 16 }
            Text {
                text: qsTr("Cosmos")
                font.pixelSize: 21
                font.bold: true
                color: Theme.text
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Item { width: 1; height: 4 }
            Text {
                text: qsTr("LITTLE UNIVERSE FM")
                font.pixelSize: 11
                font.letterSpacing: 2
                color: Theme.textFaint
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }

        Text {
            id: headText
            anchors.top: brand.bottom
            anchors.topMargin: 38
            anchors.left: parent.left
            text: qsTr("Sign in with phone")
            font.pixelSize: 16
            font.weight: Font.DemiBold
            color: Theme.text
        }

        Rectangle {
            id: field
            anchors.top: headText.bottom
            anchors.topMargin: 16
            anchors.left: parent.left
            anchors.right: parent.right
            height: Theme.fieldHeight
            radius: Theme.cornerRadius
            border.color: Theme.hairlineStrong
            border.width: 1
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#0c0c0e" }
                GradientStop { position: 1.0; color: "#161619" }
            }

            Item {
                id: ccButton
                width: ccRow.width + 26
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.left: parent.left

                Row {
                    id: ccRow
                    anchors.centerIn: parent
                    spacing: 7

                    Text {
                        text: page.regionAbbrev
                        font.pixelSize: 13
                        font.bold: true
                        color: Theme.text
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: page.areaCode
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                        color: Theme.text
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Image {
                        source: "gfx/icon-chevron-down.svg"
                        width: 16
                        height: 16
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Rectangle {
                    width: 1
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.right: parent.right
                    color: Theme.hairlineStrong
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: page.pickerOpen = true
                }
            }

            TextInput {
                id: phoneInput
                anchors.left: ccButton.right
                anchors.leftMargin: 14
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                font.pixelSize: 17
                color: Theme.text
                inputMethodHints: Qt.ImhDigitsOnly
                validator: RegExpValidator { regExp: /\d{0,15}/ }
                cursorDelegate: Rectangle {
                    width: 2
                    height: 22
                    color: Theme.accentBright
                }
                onAccepted: page.requestCode()
            }

            Text {
                anchors.left: ccButton.right
                anchors.leftMargin: 14
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("Enter phone number")
                font.pixelSize: 16
                color: Theme.textFaint
                visible: phoneInput.text.length === 0 && !phoneInput.activeFocus
            }

            MouseArea {
                anchors.left: ccButton.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                onClicked: phoneInput.forceActiveFocus()
            }
        }

        Text {
            id: hint
            anchors.top: field.bottom
            anchors.topMargin: 12
            anchors.left: parent.left
            anchors.right: parent.right
            text: qsTr("A verification code will be sent to this number via SMS.")
            font.pixelSize: 12
            color: Theme.textDim
            wrapMode: Text.WordWrap
        }

        Rectangle {
            id: getCodeButton
            anchors.top: hint.bottom
            anchors.topMargin: 22
            anchors.left: parent.left
            anchors.right: parent.right
            height: Theme.buttonHeight
            radius: Theme.cornerRadius
            gradient: page.submitEnabled ? enabledGradient : disabledGradient
            opacity: buttonMouse.pressed && page.submitEnabled ? 0.8 : 1.0

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
                text: page.busy ? qsTr("Sending...") : qsTr("Get Code")
                font.pixelSize: 16
                font.bold: true
                color: page.submitEnabled ? "#ffffff" : Theme.textFaint
            }

            MouseArea {
                id: buttonMouse
                anchors.fill: parent
                onClicked: page.requestCode()
            }
        }

        Text {
            id: errorLabel
            anchors.top: getCodeButton.bottom
            anchors.topMargin: 12
            anchors.left: parent.left
            anchors.right: parent.right
            text: page.errorText
            visible: page.errorText.length > 0
            font.pixelSize: 12
            color: Theme.errorColor
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
        }

        Text {
            // Pinned to the bottom; hidden while typing so it never rides up over
            // the form when the software keyboard shrinks the content area.
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 22
            anchors.left: parent.left
            anchors.right: parent.right
            visible: !phoneInput.activeFocus
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: 11
            color: Theme.textFaint
            wrapMode: Text.WordWrap
            text: qsTr("By continuing you agree to our <b><font color=\"#a98cff\">Terms</font></b> and <b><font color=\"#a98cff\">Privacy Policy</font></b>")
        }
    }

    // ---- country picker (Belle selection dialog, design LoginCountry state) ----
    Item {
        id: picker
        anchors.fill: parent
        visible: page.pickerOpen
        z: 100

        Rectangle {
            anchors.fill: parent
            color: "#99000000"
        }
        MouseArea {
            anchors.fill: parent
            onClicked: page.pickerOpen = false
        }

        Rectangle {
            id: dialog
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            height: dialogTitle.height + optionCn.height + optionUs.height
            radius: 9
            border.color: Theme.hairlineStrong
            border.width: 1
            gradient: Gradient {
                GradientStop { position: 0.0; color: Theme.panel2 }
                GradientStop { position: 1.0; color: Theme.panel }
            }

            MouseArea {
                anchors.fill: parent
            }

            Rectangle {
                id: dialogTitle
                height: 48
                radius: 9
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Theme.chromeHi }
                    GradientStop { position: 1.0; color: Theme.chromeLo }
                }

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Region")
                    font.pixelSize: 15
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

            Item {
                id: optionCn
                height: 56
                anchors.top: dialogTitle.bottom
                anchors.left: parent.left
                anchors.right: parent.right

                Text {
                    id: cnFlag
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: "CN"
                    font.pixelSize: 15
                    font.bold: true
                    color: Theme.text
                }
                Text {
                    anchors.left: cnFlag.right
                    anchors.leftMargin: 13
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("China")
                    font.pixelSize: 15
                    color: page.areaCode === "+86" ? Theme.accentBright : Theme.text
                }
                Text {
                    anchors.right: cnRadio.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: "+86"
                    font.pixelSize: 14
                    color: Theme.textDim
                }
                Rectangle {
                    id: cnRadio
                    width: 20
                    height: 20
                    radius: 10
                    color: "transparent"
                    border.width: 2
                    border.color: page.areaCode === "+86" ? Theme.accentBright : Theme.textFaint
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter

                    Rectangle {
                        width: 10
                        height: 10
                        radius: 5
                        color: Theme.accentBright
                        anchors.centerIn: parent
                        visible: page.areaCode === "+86"
                    }
                }
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    color: Theme.hairline
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: page.selectRegion("CN", "+86")
                }
            }

            Item {
                id: optionUs
                height: 56
                anchors.top: optionCn.bottom
                anchors.left: parent.left
                anchors.right: parent.right

                Text {
                    id: usFlag
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: "US"
                    font.pixelSize: 15
                    font.bold: true
                    color: Theme.text
                }
                Text {
                    anchors.left: usFlag.right
                    anchors.leftMargin: 13
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("United States")
                    font.pixelSize: 15
                    color: page.areaCode === "+1" ? Theme.accentBright : Theme.text
                }
                Text {
                    anchors.right: usRadio.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: "+1"
                    font.pixelSize: 14
                    color: Theme.textDim
                }
                Rectangle {
                    id: usRadio
                    width: 20
                    height: 20
                    radius: 10
                    color: "transparent"
                    border.width: 2
                    border.color: page.areaCode === "+1" ? Theme.accentBright : Theme.textFaint
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter

                    Rectangle {
                        width: 10
                        height: 10
                        radius: 5
                        color: Theme.accentBright
                        anchors.centerIn: parent
                        visible: page.areaCode === "+1"
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: page.selectRegion("US", "+1")
                }
            }
        }
    }
}

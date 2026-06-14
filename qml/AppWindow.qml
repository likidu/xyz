import QtQuick 1.1
import com.nokia.symbian 1.1

XyzPageStackWindow {
    id: window
    showStatusBar: true
    showToolBar: pageStack.currentPage ? !pageStack.currentPage.hidesToolBar : false
    platformSoftwareInputPanelEnabled: true

    function handleBack() {
        if (pageStack.depth <= 1) {
            Qt.quit();
        } else {
            pageStack.pop();
        }
    }

    function showAbout() { aboutDialog.visible = true; }
    function hideAbout() { aboutDialog.visible = false; }

    function isLoggedIn() {
        return auth.isLoggedIn();
    }

    function handleTab(index) {
        if (index === 2) {
            while (pageStack.currentPage !== updatesPage && pageStack.depth > 1) {
                pageStack.pop();
            }
        } else if (index === 3) {
            if (!pageStack.busy && pageStack.currentPage !== homePage) {
                pageStack.push(homePage);
            }
        }
        // index 0 (Discover) / 1 (Search) are inert placeholders for now.
    }

    ToolBarLayout {
        id: toolBarLayout
        ToolButton {
            flat: true
            iconSource: "toolbar-back"
            onClicked: window.handleBack()
        }
        ToolButton {
            flat: true
            iconSource: "toolbar-menu"
            onClicked: appMenu.open()
        }
    }

    Menu {
        id: appMenu
        visualParent: window
        MenuLayout {
            MenuItem {
                text: qsTr("Self-test")
                onClicked: { appMenu.close(); pageStack.push(selfTestPage); }
            }
            MenuItem {
                text: qsTr("About")
                onClicked: { appMenu.close(); window.showAbout(); }
            }
        }
    }

    Connections {
        target: xyzApi
        onSessionExpired: {
            auth.logout();
            pageStack.clear();
            pageStack.push(loginPage);
        }
    }

    LoginPage {
        id: loginPage
        onCodeSent: {
            verifyCodePage.phone = phone;
            verifyCodePage.areaCode = areaCode;
            verifyCodePage.reset();
            pageStack.push(verifyCodePage);
        }
        onExitRequested: Qt.quit()
    }

    VerifyCodePage {
        id: verifyCodePage
        onLoggedIn: {
            updatesPage.loadedOnce = false;
            subscriptionsPage.loadedOnce = false;
            pageStack.clear();
            pageStack.push(updatesPage);
        }
    }

    HomePage {
        id: homePage
        tools: toolBarLayout
        onSignedOut: {
            pageStack.clear();
            pageStack.push(loginPage);
        }
    }

    UpdatesPage {
        id: updatesPage
        onMySubsRequested: pageStack.push(subscriptionsPage)
        onTabSelected: window.handleTab(index)
    }

    SubscriptionsPage {
        id: subscriptionsPage
        onTabSelected: window.handleTab(index)
    }

    SelfTestPage {
        id: selfTestPage
        tools: toolBarLayout
    }

    Item {
        id: aboutDialog
        visible: false
        anchors.fill: parent
        z: 1000

        Rectangle { anchors.fill: parent; color: "#99000000" }
        MouseArea { anchors.fill: parent; onClicked: window.hideAbout() }

        Rectangle {
            width: parent.width - 48
            height: 220
            radius: 10
            color: "#2b2b2b"
            border.color: "#4b4b4b"
            border.width: 1
            anchors.centerIn: parent

            MouseArea { anchors.fill: parent }

            Column {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 16
                spacing: 8

                Text {
                    width: parent.width
                    text: qsTr("Xyz")
                    font.pixelSize: 20
                    color: platformStyle.colorNormalLight
                    horizontalAlignment: Text.AlignHCenter
                }
                Text {
                    width: parent.width
                    text: "v" + appVersion
                    font.pixelSize: 16
                    color: "#cdd6ea"
                    horizontalAlignment: Text.AlignHCenter
                }
                Text {
                    width: parent.width
                    text: qsTr("小宇宙 for Symbian Belle.")
                    font.pixelSize: 14
                    color: "#aeb9d4"
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            Button {
                width: parent.width - 32
                text: qsTr("Close")
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 12
                onClicked: window.hideAbout()
            }
        }
    }

    initialPage: isLoggedIn() ? updatesPage : loginPage

    Keys.onReleased: {
        if (event.key === Qt.Key_Escape) {
            window.handleBack();
            event.accepted = true;
        }
    }
}

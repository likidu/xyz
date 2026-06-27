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

    function openNowPlaying() {
        if (!pageStack.busy && pageStack.currentPage !== nowPlayingPage) {
            pageStack.push(nowPlayingPage);
        }
    }

    // Title tap in Now Playing → show the current episode's detail (notes + comments).
    // If that episode's page is already in the stack, unwind back to it (so its loaded
    // detail is reused and the player slides away); otherwise seed and push it.
    function openEpisodeForCurrent() {
        if (pageStack.busy || player.currentEid === "") return;
        var inStack = pageStack.find(function(p) { return p === episodePage; });
        if (inStack) {
            if (episodePage.eid !== player.currentEid) {
                episodePage.openWith({
                    "eid": player.currentEid, "coverUrl": player.currentCoverUrl,
                    "title": player.currentTitle, "durationText": "", "whenText": ""
                });
            }
            pageStack.pop(episodePage);
        } else {
            episodePage.openWith({
                "eid": player.currentEid, "coverUrl": player.currentCoverUrl,
                "title": player.currentTitle, "durationText": "", "whenText": ""
            });
            pageStack.push(episodePage);
        }
    }

    // Open the podcast page for a show. If it's already in the stack (the
    // Podcast<->Episode cycle), re-seed for the new show and unwind back to it
    // rather than pushing a duplicate (a re-push corrupts the Symbian PageStack).
    function openPodcast(pid, seed) {
        if (pageStack.busy || pid === "") return;
        var inStack = pageStack.find(function(p) { return p === podcastPage; });
        if (inStack) {
            if (podcastPage.pid !== pid) podcastPage.openWith(pid, seed);
            pageStack.pop(podcastPage);
        } else {
            podcastPage.openWith(pid, seed);
            pageStack.push(podcastPage);
        }
    }

    // Open the episode page for a tapped item, with the same already-in-stack guard.
    function openEpisodeItem(item) {
        if (pageStack.busy) return;
        var inStack = pageStack.find(function(p) { return p === episodePage; });
        if (inStack) {
            if (episodePage.eid !== item.eid) episodePage.openWith(item);
            pageStack.pop(episodePage);
        } else {
            episodePage.openWith(item);
            pageStack.push(episodePage);
        }
    }

    function handleTab(index) {
        if (index === 0) {
            if (!pageStack.busy && pageStack.currentPage !== discoveryPage) {
                pageStack.push(discoveryPage);
            }
        } else if (index === 1) {
            while (pageStack.currentPage !== updatesPage && pageStack.depth > 1) {
                pageStack.pop();
            }
        } else if (index === 2) {
            if (!pageStack.busy && pageStack.currentPage !== homePage) {
                pageStack.push(homePage);
            }
        }
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
        onSignedOut: {
            pageStack.clear();
            pageStack.push(loginPage);
        }
        onSelfTestRequested: pageStack.push(selfTestPage)
        onDownloadsRequested: pageStack.push(downloadsPage)
        onTabSelected: window.handleTab(index)
        onOpenPlayerRequested: window.openNowPlaying()
    }

    DownloadsPage {
        id: downloadsPage
        onTabSelected: window.handleTab(index)
        onEpisodeRequested: {
            episodePage.openWith(item);
            pageStack.push(episodePage);
        }
    }

    UpdatesPage {
        id: updatesPage
        onMySubsRequested: pageStack.push(subscriptionsPage)
        onTabSelected: window.handleTab(index)
        onEpisodeRequested: {
            episodePage.openWith(item);
            pageStack.push(episodePage);
        }
        onOpenPlayerRequested: window.openNowPlaying()
    }

    DiscoveryPage {
        id: discoveryPage
        onTabSelected: window.handleTab(index)
        onEpisodeRequested: {
            episodePage.openWith(item);
            pageStack.push(episodePage);
        }
        onOpenPlayerRequested: window.openNowPlaying()
        onSearchRequested: {
            if (!pageStack.busy && pageStack.currentPage !== searchPage) {
                pageStack.push(searchPage);
            }
        }
    }

    SearchPage {
        id: searchPage
        onBackRequested: pageStack.pop()
        onEpisodeRequested: {
            episodePage.openWith(item);
            pageStack.push(episodePage);
        }
    }

    SubscriptionsPage {
        id: subscriptionsPage
        onTabSelected: window.handleTab(index)
        onOpenPlayerRequested: window.openNowPlaying()
        onPodcastRequested: window.openPodcast(pid, seed)
    }

    EpisodePage {
        id: episodePage
        onOpenPlayerRequested: window.openNowPlaying()
        onPodcastRequested: window.openPodcast(pid, {"name": episodePage.showTitle, "coverUrl": episodePage.coverUrl})
    }

    PodcastPage {
        id: podcastPage
        onEpisodeRequested: window.openEpisodeItem(item)
        onOpenPlayerRequested: window.openNowPlaying()
    }

    NowPlayingPage {
        id: nowPlayingPage
        onOpenEpisodeRequested: window.openEpisodeForCurrent()
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

import QtQuick 1.1
import com.nokia.symbian 1.1

XyzPageStackWindow {
    id: window
    showStatusBar: true
    showToolBar: pageStack.currentPage ? !pageStack.currentPage.hidesToolBar : false
    platformSoftwareInputPanelEnabled: true

    function handleBack() {
        if (pageStack.currentPage === nowPlayingPage) {
            nowPlayingPage.collapse();   // vertical slide down, then pops
        } else if (pageStack.depth <= 1) {
            Qt.quit();
        } else {
            pageStack.pop();
        }
    }

    function isLoggedIn() {
        return auth.isLoggedIn();
    }

    function openNowPlaying() {
        if (!pageStack.busy && pageStack.currentPage !== nowPlayingPage) {
            // Immediate push suppresses the stack's horizontal slide; the page
            // runs its own vertical animation so it expands up from the mini player.
            pageStack.push(nowPlayingPage, null, true);
            nowPlayingPage.expand();
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

    Connections {
        target: xyzApi
        onSessionExpired: {
            auth.logout();
            pageStack.clear();
            pageStack.push(loginPage);
        }
    }

    // A tap on the Pigler now-playing notification opens the current
    // episode's detail page (Pigler has already foregrounded the app).
    Connections {
        target: notifier
        onOpenCurrentEpisodeRequested: openEpisodeForCurrent()
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

    initialPage: isLoggedIn() ? updatesPage : loginPage

    Keys.onReleased: {
        if (event.key === Qt.Key_Escape) {
            window.handleBack();
            event.accepted = true;
        }
    }
}

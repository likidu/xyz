import QtQuick 1.1
import com.nokia.symbian 1.1
import "js/Theme.js" as Theme

// Now Playing — full-screen player (design: belle.css .player / screens-player.jsx).
// Pushed over the current page; reads everything from the `player` context object.
// Down-chevron header pops back. Speed chip + bottom toolbar are static placeholders.
Page {
    id: page
    objectName: "NowPlayingPage"

    property bool hidesToolBar: true

    // scrubber drag state (don't let position updates fight the finger)
    property bool scrubbing: false
    property real scrubRatio: 0.0

    function fmt(ms) {
        if (ms <= 0) return "0:00";
        var s = Math.floor(ms / 1000);
        var m = Math.floor(s / 60);
        var r = s % 60;
        return m + ":" + (r < 10 ? "0" + r : r);
    }

    function remaining() {
        var d = player.duration;
        if (d <= 0) return "-0:00";
        return "-" + fmt(d - player.position);
    }

    function progressRatio() {
        if (page.scrubbing) return page.scrubRatio;
        if (player.duration <= 0) return 0.0;
        return player.position / player.duration;
    }

    function togglePlay() {
        if (player.state === player.playingState) player.pause();
        else player.resume();
    }

    function skip(deltaMs) {
        var t = player.position + deltaMs;
        if (t < 0) t = 0;
        if (player.duration > 0 && t > player.duration) t = player.duration;
        player.seek(t);
    }

    function clamp01(v) {
        if (v < 0) return 0.0;
        if (v > 1) return 1.0;
        return v;
    }

    Rectangle { anchors.fill: parent; color: Theme.bg }

    BelleHeader {
        id: header
        title: qsTr("Now Playing")
        leadIconSource: "gfx/icon-chevron-down.svg"
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        onBackClicked: pageStack.pop()
    }

    // ---- bottom toolbar (static placeholders) ----
    Rectangle {
        id: toolbar
        height: 56
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#2a2a30" }
            GradientStop { position: 0.08; color: "#1d1d22" }
            GradientStop { position: 1.0; color: "#141417" }
        }
        Rectangle {
            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
            height: 1; color: "#000000"
        }
        Row {
            anchors.centerIn: parent
            spacing: 56
            Image { source: "gfx/icon-list.svg"; width: 24; height: 24; smooth: true; opacity: 0.75 }
            Image { source: "gfx/icon-comment.svg"; width: 24; height: 24; smooth: true; opacity: 0.75 }
            Image { source: "gfx/tab-headphones.svg"; width: 24; height: 24; smooth: true; opacity: 0.75 }
        }
    }

    // ---- player body ----
    Column {
        id: stack
        anchors.top: header.bottom
        anchors.topMargin: 6
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width - 44
        spacing: 0

        Rectangle {
            id: cover
            width: 208; height: 208; radius: 12
            anchors.horizontalCenter: parent.horizontalCenter
            clip: true
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#6a4bd6" }
                GradientStop { position: 0.55; color: "#2a1d54" }
                GradientStop { position: 1.0; color: "#0e0a1f" }
            }
            Text {
                visible: player.currentCoverUrl === ""
                anchors.centerIn: parent
                width: parent.width - 24
                text: player.currentShow
                color: "#ffffff"; font.pixelSize: 22; font.bold: true
                horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
            }
            Image {
                anchors.fill: parent; fillMode: Image.PreserveAspectCrop; smooth: true
                sourceSize.width: 208; sourceSize.height: 208
                source: player.currentCoverUrl
            }
        }

        Item { width: 1; height: 22 }

        Text {
            width: parent.width
            text: player.currentShow
            font.pixelSize: 13; color: Theme.accentBright
            horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
        }

        Item { width: 1; height: 8 }

        Text {
            width: parent.width
            text: player.currentTitle
            font.pixelSize: 19; font.bold: true; color: Theme.text
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
        }

        Item { width: 1; height: 22 }

        // scrubber
        Item {
            width: parent.width; height: 13
            Rectangle {
                id: track
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left; anchors.right: parent.right
                height: 4; radius: 2; color: "#1FFFFFFF"

                Rectangle {
                    anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                    width: parent.width * page.progressRatio(); radius: 2
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Theme.accentDeep }
                        GradientStop { position: 1.0; color: Theme.accentBright }
                    }
                }
                Rectangle {
                    width: 13; height: 13; radius: 6.5; color: "#ffffff"
                    anchors.verticalCenter: parent.verticalCenter
                    x: (parent.width * page.progressRatio()) - 6.5
                }
            }
            MouseArea {
                anchors.fill: parent
                enabled: player.duration > 0
                onPressed: { page.scrubbing = true; page.scrubRatio = page.clamp01(mouse.x / width); }
                onPositionChanged: { if (page.scrubbing) page.scrubRatio = page.clamp01(mouse.x / width); }
                onReleased: {
                    if (player.duration > 0) player.seek(Math.round(page.scrubRatio * player.duration));
                    page.scrubbing = false;
                }
            }
        }

        Item { width: 1; height: 8 }

        Item {
            width: parent.width; height: 16
            Text {
                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                text: page.fmt(player.position); font.pixelSize: 12; color: Theme.textDim
            }
            Text {
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                text: player.duration > 0 ? page.remaining() : "--:--"
                font.pixelSize: 12; color: Theme.textDim
            }
        }

        Item { width: 1; height: 18 }

        // transport
        Item {
            width: parent.width; height: 72
            Row {
                anchors.centerIn: parent
                spacing: 24
                Item {
                    width: 44; height: 44; anchors.verticalCenter: parent.verticalCenter
                    Image { source: "gfx/icon-rewind.svg"; width: 34; height: 34; smooth: true; anchors.centerIn: parent }
                    Text { anchors.centerIn: parent; text: "15"; font.pixelSize: 9; font.bold: true; color: "#d6d6dd" }
                    MouseArea { anchors.fill: parent; onClicked: page.skip(-15000) }
                }
                Rectangle {
                    width: 72; height: 72; radius: 36; anchors.verticalCenter: parent.verticalCenter
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Theme.accentBright }
                        GradientStop { position: 1.0; color: Theme.accentDeep }
                    }
                    Image {
                        anchors.centerIn: parent; width: 30; height: 30; smooth: true
                        source: player.state === player.playingState ? "gfx/icon-pause-white.svg" : "gfx/icon-play-white.svg"
                    }
                    MouseArea { anchors.fill: parent; onClicked: page.togglePlay() }
                }
                Item {
                    width: 44; height: 44; anchors.verticalCenter: parent.verticalCenter
                    Image { source: "gfx/icon-forward.svg"; width: 34; height: 34; smooth: true; anchors.centerIn: parent }
                    Text { anchors.centerIn: parent; text: "30"; font.pixelSize: 9; font.bold: true; color: "#d6d6dd" }
                    MouseArea { anchors.fill: parent; onClicked: page.skip(30000) }
                }
            }
        }

        Item { width: 1; height: 18 }

        // meta chips (On device = real; speed = static placeholder)
        Item {
            width: parent.width; height: 28
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8
                Rectangle {
                    height: 28; radius: 14; color: "#00000000"
                    border.width: 1; border.color: "#668b6dff"
                    width: deviceRow.width + 24
                    Row {
                        id: deviceRow; anchors.centerIn: parent; spacing: 6
                        Image { source: "gfx/icon-check.svg"; width: 14; height: 14; smooth: true; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: qsTr("On device"); font.pixelSize: 12; color: Theme.accentBright; anchors.verticalCenter: parent.verticalCenter }
                    }
                }
                Rectangle {
                    height: 28; radius: 14; color: "#00000000"
                    border.width: 1; border.color: Theme.hairlineStrong
                    width: speedText.width + 24
                    Text { id: speedText; anchors.centerIn: parent; text: "1.0×"; font.pixelSize: 12; color: Theme.textDim }
                }
            }
        }
    }
}

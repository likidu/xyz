import QtQuick 1.1
import "js/Theme.js" as Theme

// Mini floating player docked above the bottom bar (design: belle.css .miniplayer).
// Bound to the `player` context object. Visible whenever a track is loaded/playing.
// Simplified to cover + title/time only; tapping the bar emits expandRequested.
Rectangle {
    id: mini

    signal expandRequested

    height: 56
    visible: player.currentEid !== "" &&
             (player.state === player.preparingState ||
              player.state === player.playingState ||
              player.state === player.pausedState)

    gradient: Gradient {
        GradientStop { position: 0.0; color: "#1a1a1f" }
        GradientStop { position: 1.0; color: "#101013" }
    }

    function fmt(ms) {
        if (ms <= 0) return "0:00";
        var s = Math.floor(ms / 1000);
        var m = Math.floor(s / 60);
        var r = s % 60;
        return m + ":" + (r < 10 ? "0" + r : r);
    }

    // top hairline
    Rectangle {
        anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
        height: 1; color: "#000000"
    }

    // whole-bar tap target → expand to Now Playing
    MouseArea { anchors.fill: parent; onClicked: mini.expandRequested() }

    Rectangle {
        id: cover
        width: 38; height: 38; radius: 5
        anchors.left: parent.left; anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        color: "#1a1a22"; clip: true
        Image {
            anchors.fill: parent; fillMode: Image.PreserveAspectCrop; smooth: true
            sourceSize.width: 38; sourceSize.height: 38
            source: player.currentCoverUrl
        }
    }

    // Expand affordance — mirrors the down-chevron on the Now Playing page.
    Image {
        id: expandChevron
        source: "gfx/icon-chevron-up.svg"
        width: 24; height: 24; smooth: true
        anchors.right: parent.right; anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
    }

    Column {
        anchors.left: cover.right; anchors.leftMargin: 11
        anchors.right: expandChevron.left; anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        Text {
            width: parent.width
            text: player.currentTitle
            font.pixelSize: 14; font.weight: Font.DemiBold; color: Theme.text
            elide: Text.ElideRight
        }
        Text {
            text: mini.fmt(player.position) + " / " + mini.fmt(player.duration)
            font.pixelSize: 12; color: Theme.textDim
        }
    }
}

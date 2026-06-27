import QtQuick 1.1
import "js/Theme.js" as Theme

// Custom Belle bottom tab bar (icon-only, glossy) — design: belle.css .toolbar.
// Placeholder glyphs; active tab marked by full opacity + an accent dot.
Rectangle {
    id: tabBar

    property int activeIndex: 1
    signal tabSelected(int index)

    height: Theme.tabBarHeight
    gradient: Gradient {
        GradientStop { position: 0.0; color: "#2a2a30" }
        GradientStop { position: 0.08; color: "#1d1d22" }
        GradientStop { position: 1.0; color: "#141417" }
    }

    // 1px black top border
    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: "#000000"
    }

    Row {
        anchors.fill: parent

        Repeater {
            model: ["gfx/tab-compass.svg",
                    "gfx/tab-headphones.svg", "gfx/tab-person.svg"]

            Item {
                width: tabBar.width / 3
                height: tabBar.height

                Rectangle {
                    width: 1
                    height: 28
                    color: "#12FFFFFF"
                    visible: index > 0
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                }

                Image {
                    source: modelData
                    width: 30
                    height: 30
                    smooth: true
                    anchors.centerIn: parent
                    opacity: index === tabBar.activeIndex ? 1.0 : 0.65
                }

                Rectangle {
                    width: 5
                    height: 5
                    radius: 2.5
                    color: Theme.accentBright
                    visible: index === tabBar.activeIndex
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 6
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: tabBar.tabSelected(index)
                }
            }
        }
    }
}

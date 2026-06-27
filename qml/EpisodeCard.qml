import QtQuick 1.1
import "js/Theme.js" as Theme

// One episode card (cover + show + title + duration/comments/when foot), shared
// by Discovery and Search. The host sets `width` and `item` (the shaped episode
// map) and handles `clicked`. A single whole-card MouseArea sits on top and the
// content never grabs the mouse, so a tap anywhere on the card registers
// (Symbian list-row tap-target rule).
Item {
    id: root

    property variant item
    signal clicked

    height: card.height + 10

    Rectangle {
        id: card
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        height: cardCol.height
        radius: 8
        border.width: 1
        border.color: Theme.hairline
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.panel2 }
            GradientStop { position: 1.0; color: Theme.panel }
        }

        Column {
            id: cardCol
            anchors.left: parent.left
            anchors.right: parent.right

            // card top: cover + show + title
            Item {
                width: parent.width
                height: cardTop.height + 24
                Row {
                    id: cardTop
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    anchors.top: parent.top
                    anchors.topMargin: 12
                    spacing: 12

                    Rectangle {
                        width: 76
                        height: 76
                        radius: 7
                        color: "#1a1a22"
                        clip: true
                        Image {
                            anchors.fill: parent
                            fillMode: Image.PreserveAspectCrop
                            smooth: true
                            sourceSize.width: 76
                            sourceSize.height: 76
                            source: root.item.coverUrl
                        }
                    }
                    Column {
                        width: parent.width - 88
                        spacing: 5
                        Text {
                            width: parent.width
                            text: root.item.showName
                            font.pixelSize: 13
                            color: Theme.accentBright
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: root.item.title
                            font.pixelSize: 16
                            font.bold: true
                            color: Theme.text
                            wrapMode: Text.WordWrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            // card foot: duration · comments · when
            Rectangle {
                width: parent.width
                height: 1
                color: Theme.hairline
            }
            Item {
                width: parent.width
                height: 40
                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 14
                    Row {
                        spacing: 5
                        anchors.verticalCenter: parent.verticalCenter
                        Image { source: "gfx/tab-headphones.svg"; width: 15; height: 15; smooth: true; opacity: 0.7; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: root.item.durationText; font.pixelSize: 13; color: Theme.textDim; anchors.verticalCenter: parent.verticalCenter }
                    }
                    Row {
                        spacing: 5
                        anchors.verticalCenter: parent.verticalCenter
                        Image { source: "gfx/icon-comment.svg"; width: 15; height: 15; smooth: true; opacity: 0.7; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: root.item.commentCount; font.pixelSize: 13; color: Theme.textDim; anchors.verticalCenter: parent.verticalCenter }
                    }
                }
                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.item.whenText
                    font.pixelSize: 13
                    color: Theme.textFaint
                }
            }
        }
    }

    // press feedback (non-interactive wash) + single whole-card tap target on top.
    Rectangle {
        anchors.fill: card
        radius: 8
        color: Theme.accent
        opacity: cardTap.pressed ? 0.10 : 0
    }
    MouseArea {
        id: cardTap
        anchors.fill: card
        onClicked: root.clicked()
    }
}

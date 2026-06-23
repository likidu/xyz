import QtQuick 1.1
import com.nokia.symbian 1.1
import "js/Theme.js" as Theme

// Downloads Manager — phone-memory meter + in-flight download + on-device list
// (design: screens-download.jsx DownloadsManager + .stor / .dlrow in belle.css).
// Data from the native `downloads` registry; the active row's progress comes live
// off `player`. Tapping an on-device row opens its EpisodePage (play / delete there).
Page {
    id: page
    objectName: "DownloadsPage"

    property bool hidesToolBar: true

    // split out of downloads.items by recompute()
    property variant onDeviceItems: []
    property variant activeItem: ({})
    property bool hasActive: false
    property bool confirmingClear: false

    signal episodeRequested(variant item)
    signal tabSelected(int index)

    // ---- helpers (declared at root per QML 1.1 rules) ----
    function recompute() {
        var all = downloads.items;
        var dev = [];
        var act = null;
        for (var i = 0; i < all.length; ++i) {
            if (all[i].done) {
                dev.push(all[i]);
            } else {
                act = all[i];
            }
        }
        page.onDeviceItems = dev;
        page.activeItem = act ? act : ({});
        page.hasActive = (act !== null);
    }

    function openItem(m) {
        page.episodeRequested({
            "eid": m.eid,
            "coverUrl": m.coverUrl,
            "title": m.title,
            "durationText": m.durationText,
            "whenText": ""
        });
    }

    function metaLine(m) {
        var parts = [];
        if (m.show && m.show.length > 0) parts.push(m.show);
        if (m.durationText && m.durationText.length > 0) parts.push(m.durationText);
        if (m.sizeText && m.sizeText.length > 0) parts.push(m.sizeText);
        return parts.join("  ·  ");
    }

    function meterKnown() { return downloads.diskTotalBytes > 0; }

    function fmtSize(bytes) {
        if (bytes <= 0) return "";
        var gb = bytes / (1024 * 1024 * 1024);
        if (gb >= 1) return gb.toFixed(2) + " GB";
        return Math.round(bytes / (1024 * 1024)) + " MB";
    }

    function meterValueText() {
        if (!page.meterKnown()) return "";
        var used = downloads.diskTotalBytes - downloads.diskFreeBytes;
        return page.fmtSize(used) + " / " + page.fmtSize(downloads.diskTotalBytes);
    }

    function dlFraction() {
        var t = downloads.diskTotalBytes;
        if (t <= 0) return 0;
        return Math.max(0, Math.min(1, downloads.downloadsBytes / t));
    }

    function otherFraction() {
        var t = downloads.diskTotalBytes;
        if (t <= 0) return 0;
        var other = t - downloads.diskFreeBytes - downloads.downloadsBytes;
        if (other < 0) other = 0;
        return Math.max(0, Math.min(1, other / t));
    }

    function progressPctText() {
        return Math.round(player.downloadProgress * 100) + "%";
    }

    onStatusChanged: {
        if (status === PageStatus.Active) {
            downloads.refresh();
            page.recompute();
        }
    }

    Connections {
        target: downloads
        onItemsChanged: page.recompute()
    }

    Rectangle { anchors.fill: parent; color: Theme.bg }

    BelleHeader {
        id: header
        title: qsTr("Downloads")
        actionIconSource: "gfx/icon-trash-white.svg"
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        onBackClicked: pageStack.pop()
        onActionClicked: page.confirmingClear = true
    }

    Item {
        id: content
        anchors.top: header.bottom
        anchors.bottom: tabBar.top
        anchors.left: parent.left
        anchors.right: parent.right
        clip: true

        ListView {
            id: list
            anchors.fill: parent
            model: page.onDeviceItems
            clip: true
            header: listHeader
            delegate: rowDelegate
        }
    }

    // ---- header: storage meter + active download + "On device" subhead ----
    Component {
        id: listHeader
        Column {
            width: list.width

            // storage meter card
            Item {
                width: parent.width
                height: 116

                Rectangle {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    anchors.topMargin: 14
                    anchors.bottomMargin: 6
                    radius: 9
                    border.width: 1
                    border.color: Theme.hairline
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Theme.panel2 }
                        GradientStop { position: 1.0; color: Theme.panel }
                    }

                    Text {
                        id: storLbl
                        anchors.top: parent.top
                        anchors.topMargin: 14
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        text: qsTr("Phone memory")
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        color: Theme.text
                    }
                    Text {
                        anchors.verticalCenter: storLbl.verticalCenter
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        text: page.meterValueText()
                        font.pixelSize: 13
                        color: Theme.textDim
                    }

                    // segmented bar (track with downloads + other segments; rest is free)
                    Rectangle {
                        id: bar
                        anchors.top: storLbl.bottom
                        anchors.topMargin: 12
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        height: 9
                        radius: 5
                        color: "#12FFFFFF"
                        clip: true
                        Row {
                            anchors.fill: parent
                            Rectangle {
                                width: bar.width * page.dlFraction()
                                height: parent.height
                                color: Theme.accentBright
                            }
                            Rectangle {
                                width: bar.width * page.otherFraction()
                                height: parent.height
                                color: "#52FFFFFF"
                            }
                        }
                    }

                    // legend
                    Row {
                        anchors.top: bar.bottom
                        anchors.topMargin: 12
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        spacing: 14

                        Row {
                            spacing: 6
                            Rectangle { width: 9; height: 9; radius: 2; color: Theme.accentBright; anchors.verticalCenter: parent.verticalCenter }
                            Text {
                                text: downloads.downloadsText !== "" ? qsTr("Downloads") + " " + downloads.downloadsText : qsTr("Downloads")
                                font.pixelSize: 12; color: Theme.textDim
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        Row {
                            spacing: 6
                            visible: page.meterKnown()
                            Rectangle { width: 9; height: 9; radius: 2; color: "#52FFFFFF"; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: qsTr("Other"); font.pixelSize: 12; color: Theme.textDim; anchors.verticalCenter: parent.verticalCenter }
                        }
                        Row {
                            spacing: 6
                            visible: page.meterKnown()
                            Rectangle { width: 9; height: 9; radius: 2; color: "#12FFFFFF"; border.width: 1; border.color: Theme.hairlineStrong; anchors.verticalCenter: parent.verticalCenter }
                            Text {
                                text: qsTr("Free") + " " + page.fmtSize(downloads.diskFreeBytes)
                                font.pixelSize: 12; color: Theme.textDim
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }
            }

            // "Downloading" subhead (collapses when nothing in flight)
            Item {
                width: parent.width
                height: page.hasActive ? 34 : 0
                visible: page.hasActive
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 8
                    text: qsTr("Downloading")
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    color: Theme.accentBright
                }
            }

            // active download row
            Item {
                width: parent.width
                height: page.hasActive ? 84 : 0
                visible: page.hasActive

                Rectangle { anchors.fill: parent; color: "#148b6dff" }

                Row {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 12

                    Rectangle {
                        width: 50
                        height: 50
                        radius: 5
                        color: "#1a1a22"
                        clip: true
                        anchors.verticalCenter: parent.verticalCenter
                        Image {
                            anchors.fill: parent
                            fillMode: Image.PreserveAspectCrop
                            smooth: true
                            sourceSize.width: 50
                            sourceSize.height: 50
                            source: page.activeItem.coverUrl ? page.activeItem.coverUrl : ""
                        }
                    }

                    Column {
                        width: list.width - 28 - 50 - 12 - 40 - 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 7
                        Text {
                            width: parent.width
                            text: page.activeItem.title ? page.activeItem.title : ""
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                            color: Theme.text
                            elide: Text.ElideRight
                        }
                        Rectangle {
                            width: parent.width
                            height: 4
                            radius: 2
                            color: "#1AFFFFFF"
                            Rectangle {
                                height: parent.height
                                radius: 2
                                width: parent.width * player.downloadProgress
                                color: Theme.accentBright
                            }
                        }
                        Text {
                            width: parent.width
                            text: qsTr("Downloading") + " " + page.progressPctText()
                                  + (page.activeItem.sizeText ? "  ·  " + page.activeItem.sizeText : "")
                            font.pixelSize: 12
                            color: Theme.accentBright
                            elide: Text.ElideRight
                        }
                    }

                    Item {
                        width: 40
                        height: 50
                        anchors.verticalCenter: parent.verticalCenter
                        Image {
                            source: "gfx/icon-x.svg"
                            width: 16
                            height: 16
                            smooth: true
                            anchors.centerIn: parent
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: player.cancelDownload()
                        }
                    }
                }
            }

            // "On device" subhead
            Item {
                width: parent.width
                height: page.onDeviceItems.length > 0 ? 34 : 0
                visible: page.onDeviceItems.length > 0
                Text {
                    id: onDevText
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 8
                    text: qsTr("On device")
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    color: Theme.accentBright
                }
                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.verticalCenter: onDevText.verticalCenter
                    text: page.onDeviceItems.length
                    font.pixelSize: 13
                    color: Theme.textDim
                }
            }

            // empty state
            Item {
                width: parent.width
                height: (page.onDeviceItems.length === 0 && !page.hasActive) ? 120 : 0
                visible: page.onDeviceItems.length === 0 && !page.hasActive
                Text {
                    anchors.centerIn: parent
                    text: qsTr("No downloads yet")
                    color: Theme.textDim
                    font.pixelSize: 14
                }
            }
        }
    }

    // ---- on-device row ----
    Component {
        id: rowDelegate
        Item {
            width: list.width
            height: Math.max(72, body.height + 22)

            Row {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12

                Rectangle {
                    width: 50
                    height: 50
                    radius: 5
                    color: "#1a1a22"
                    clip: true
                    anchors.verticalCenter: parent.verticalCenter
                    Image {
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        smooth: true
                        sourceSize.width: 50
                        sourceSize.height: 50
                        source: modelData.coverUrl ? modelData.coverUrl : ""
                    }
                }

                Column {
                    id: body
                    width: list.width - 28 - 50 - 12 - 46 - 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5
                    Text {
                        width: parent.width
                        text: modelData.title
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                        color: Theme.text
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: page.metaLine(modelData)
                        font.pixelSize: 13
                        color: Theme.textDim
                        elide: Text.ElideRight
                    }
                }

                Row {
                    width: 46
                    spacing: 8
                    anchors.verticalCenter: parent.verticalCenter
                    Image {
                        source: "gfx/icon-check.svg"
                        width: 18
                        height: 18
                        smooth: true
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Image {
                        source: "gfx/icon-dots.svg"
                        width: 18
                        height: 18
                        smooth: true
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: Theme.hairline
            }

            // full-delegate tap target (behind content) -> open the episode
            MouseArea {
                anchors.fill: parent
                onClicked: page.openItem(modelData)
            }
        }
    }

    // ---- clear-all confirmation (design: .scrim / .dialog / .dlg-btn) ----
    Item {
        id: confirmClear
        anchors.fill: parent
        visible: page.confirmingClear
        z: 100

        Rectangle {
            anchors.fill: parent
            color: "#99000000"
            MouseArea { anchors.fill: parent; onClicked: page.confirmingClear = false }
        }

        Rectangle {
            id: dlg
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 24
            anchors.rightMargin: 24
            anchors.verticalCenter: parent.verticalCenter
            height: dlgCol.height
            radius: 9
            clip: true
            color: Theme.panel2
            border.width: 1
            border.color: Theme.hairlineStrong

            Column {
                id: dlgCol
                width: dlg.width

                Item {
                    width: parent.width
                    height: 44
                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Theme.chromeHi }
                            GradientStop { position: 1.0; color: Theme.chromeLo }
                        }
                    }
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("Delete all downloads?")
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
                    width: parent.width
                    height: clearMsg.height + 32
                    Text {
                        id: clearMsg
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("This removes every downloaded audio file from phone memory. You can download them again anytime.")
                        font.pixelSize: 13
                        color: Theme.textDim
                        wrapMode: Text.WordWrap
                    }
                }

                Item {
                    width: parent.width
                    height: 62

                    Rectangle {
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        anchors.top: parent.top
                        width: (parent.width - 42) / 2
                        height: 46
                        radius: 7
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: "#2c2c33" }
                            GradientStop { position: 1.0; color: "#1a1a1f" }
                        }
                        border.width: 1
                        border.color: Theme.hairlineStrong
                        Text {
                            anchors.centerIn: parent
                            text: qsTr("Cancel")
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                            color: Theme.text
                        }
                        MouseArea { anchors.fill: parent; onClicked: page.confirmingClear = false }
                    }

                    Rectangle {
                        anchors.right: parent.right
                        anchors.rightMargin: 16
                        anchors.top: parent.top
                        width: (parent.width - 42) / 2
                        height: 46
                        radius: 7
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: "#e0564f" }
                            GradientStop { position: 1.0; color: "#b8362f" }
                        }
                        border.width: 1
                        border.color: "#7c1f1a"
                        Row {
                            anchors.centerIn: parent
                            spacing: 7
                            Image {
                                source: "gfx/icon-trash-white.svg"
                                width: 16
                                height: 16
                                smooth: true
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: qsTr("Delete")
                                font.pixelSize: 15
                                font.weight: Font.DemiBold
                                color: "#ffffff"
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                downloads.clearAll();
                                page.confirmingClear = false;
                            }
                        }
                    }
                }
            }
        }
    }

    BelleTabBar {
        id: tabBar
        activeIndex: 3
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        onTabSelected: page.tabSelected(index)
    }
}

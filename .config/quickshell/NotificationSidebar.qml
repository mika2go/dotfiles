pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

Item {
    id: sidebar

    required property var theme
    required property var notificationCenter
    property bool active: false
    property real now: Date.now()
    property int selectedTab: 0
    readonly property string fontFamily: "JetBrainsMono Nerd Font"
    readonly property real stableHeaderWidth: 318
    readonly property bool clearAvailable: selectedTab === 0
        ? notificationCenter.activeCount > 0 : localAiChat.canClear

    signal closeRequested

    focus: active
    Keys.onEscapePressed: event => {
        sidebar.closeRequested()
        event.accepted = true
    }

    function resolveIcon(entry): string {
        const candidates = [entry.appIcon || "", entry.image || ""]
        for (const icon of candidates) {
            if (icon.startsWith("/") || icon.startsWith("file:"))
                return icon
            if (icon.length > 0 && Quickshell.hasThemeIcon(icon))
                return Quickshell.iconPath(icon)
        }
        return ""
    }

    function relativeTime(timestamp): string {
        const seconds = Math.max(0,
            Math.floor((sidebar.now - Number(timestamp)) / 1000))
        if (seconds < 60)
            return "JETZT"
        const minutes = Math.floor(seconds / 60)
        if (minutes < 60)
            return minutes + " MIN"
        const hours = Math.floor(minutes / 60)
        if (hours < 24)
            return hours + " STD"
        return Math.floor(hours / 24) + " T"
    }

    Timer {
        interval: 30000
        running: sidebar.active
        repeat: true
        triggeredOnStart: true
        onTriggered: sidebar.now = Date.now()
    }

    IpcHandler {
        target: "notificationview"

        function meldungen(): void { sidebar.selectedTab = 0 }
        function nova(): void { sidebar.selectedTab = 1 }
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: 16
        }
        spacing: 12

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 52

            Column {
                anchors {
                    verticalCenter: parent.verticalCenter
                }
                x: Math.max(0, parent.width - sidebar.stableHeaderWidth)
                width: 172
                spacing: 1

                Text {
                    width: parent.width
                    text: sidebar.selectedTab === 0 ? "MELDUNGEN" : "NOVA"
                    color: sidebar.theme.textPrimary
                    elide: Text.ElideRight
                    font.family: sidebar.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.Bold
                }

                Text {
                    width: parent.width
                    text: sidebar.selectedTab === 0
                        ? (sidebar.notificationCenter.activeCount > 0
                            ? sidebar.notificationCenter.activeCount
                                + " IM VERLAUF"
                            : "ALLES ERLEDIGT")
                        : "DEIN LOKALER ASSISTENT"
                    color: sidebar.theme.textMuted
                    elide: Text.ElideRight
                    font.family: sidebar.fontFamily
                    font.pixelSize: 8
                }
            }

            Row {
                anchors {
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                spacing: 2

                TabSwitch {
                    activeTab: sidebar.selectedTab === 0
                    label: "󰂚"
                    tooltip: "Benachrichtigungen"
                    onClicked: sidebar.selectedTab = 0
                }

                TabSwitch {
                    activeTab: sidebar.selectedTab === 1
                    label: "󰚩"
                    tooltip: "AI Chat"
                    onClicked: sidebar.selectedTab = 1
                }

                HeaderButton {
                    opacity: sidebar.clearAvailable ? 1 : 0
                    enabled: sidebar.clearAvailable
                    label: "󰃢"
                    tooltip: sidebar.selectedTab === 0
                        ? "Verlauf leeren" : "Chat leeren"
                    onClicked: {
                        if (sidebar.selectedTab === 0)
                            sidebar.notificationCenter.clear()
                        else
                            localAiChat.clearConversation()
                    }

                    Behavior on opacity { NumberAnimation { duration: 140 } }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: sidebar.theme.surfaceHover
        }

        Item {
            id: pageStack

            Layout.fillWidth: true
            Layout.fillHeight: true

            Item {
                id: notificationsPage

                anchors.fill: parent
                visible: sidebar.selectedTab === 0

            GmxMailStatus {
                id: gmxMailStatus

                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                }
                theme: sidebar.theme
                active: sidebar.active && sidebar.selectedTab === 0
            }

            Column {
                anchors.centerIn: parent
                width: parent.width - 30
                spacing: 10
                visible: sidebar.notificationCenter.activeCount === 0
                    && !gmxMailStatus.hasUnread
                opacity: visible ? 1 : 0

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "󰂚"
                    color: sidebar.theme.outlineSubtle
                    font.family: sidebar.fontFamily
                    font.pixelSize: 34
                }

                Text {
                    width: parent.width
                    text: "KEINE BENACHRICHTIGUNGEN"
                    color: sidebar.theme.textMuted
                    horizontalAlignment: Text.AlignHCenter
                    font.family: sidebar.fontFamily
                    font.pixelSize: 9
                    font.weight: Font.Bold
                }

                Text {
                    width: parent.width
                    text: "Neue Meldungen bleiben nach dem Popup hier erhalten."
                    color: sidebar.theme.outlineSubtle
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    font.family: sidebar.fontFamily
                    font.pixelSize: 8
                }

                Behavior on opacity {
                    NumberAnimation { duration: 180 }
                }
            }

            Flickable {
                id: historyView

                anchors {
                    fill: parent
                    topMargin: gmxMailStatus.visible
                        ? gmxMailStatus.implicitHeight + 10 : 0
                }
                visible: sidebar.notificationCenter.activeCount > 0
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.VerticalFlick
                contentWidth: width
                contentHeight: groupColumn.implicitHeight

                Column {
                    id: groupColumn
                    width: historyView.width
                    spacing: 11

                    Repeater {
                        id: groupRepeater

                        model: sidebar.notificationCenter.groups

                        delegate: Item {
                            id: groupItem

                            required property var modelData
                            required property int index
                            property bool expanded: false
                            readonly property var liveEntries:
                                modelData.entries.filter(entry => !entry.closed)
                            readonly property int activeCount: liveEntries.length
                            readonly property var displayEntries: expanded
                                ? liveEntries : liveEntries.slice(0, 2)

                            width: groupColumn.width
                            height: activeCount > 0
                                ? groupSurface.implicitHeight : 0
                            opacity: activeCount > 0 ? 1 : 0
                            clip: true

                            Behavior on height {
                                NumberAnimation {
                                    duration: 220
                                    easing.type: Easing.InOutSine
                                }
                            }

                            Behavior on opacity {
                                NumberAnimation { duration: 180 }
                            }

                            Item {
                                id: groupSurface

                                width: parent.width
                                implicitHeight: groupLayout.implicitHeight

                                ColumnLayout {
                                    id: groupLayout

                                    anchors {
                                        left: parent.left
                                        right: parent.right
                                        top: parent.top
                                    }
                                    spacing: 0

                                    RowLayout {
                                        visible: groupItem.activeCount > 1
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: visible ? 30 : 0
                                        Layout.leftMargin: 49
                                        spacing: 6

                                        Text {
                                            Layout.fillWidth: true
                                            text: groupItem.modelData.appName
                                                .toUpperCase() + "  ·  "
                                                + groupItem.activeCount
                                                + " MELDUNGEN"
                                            color: sidebar.theme.textDisabled
                                            elide: Text.ElideRight
                                            font.family: sidebar.fontFamily
                                            font.pixelSize: 7
                                            font.weight: Font.DemiBold
                                            font.letterSpacing: 0.4
                                        }

                                        Item {
                                            Layout.preferredWidth: 30
                                            Layout.preferredHeight: 30

                                            Text {
                                                anchors.centerIn: parent
                                                text: "󰅀"
                                                rotation: groupItem.expanded ? 180 : 0
                                                color: expandMouse.containsMouse
                                                    ? sidebar.theme.accent
                                                    : sidebar.theme.textMuted
                                                font.family: sidebar.fontFamily
                                                font.pixelSize: 13

                                                Behavior on rotation {
                                                    NumberAnimation {
                                                        duration: 180
                                                        easing.type:
                                                            Easing.OutCubic
                                                    }
                                                }
                                            }

                                            MouseArea {
                                                id: expandMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape:
                                                    Qt.PointingHandCursor
                                                onClicked:
                                                    groupItem.expanded =
                                                        !groupItem.expanded
                                            }
                                        }
                                    }

                                    Rectangle {
                                        visible: groupItem.activeCount > 1
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 1
                                        Layout.leftMargin: 49
                                        color: sidebar.theme.surfaceHover
                                    }

                                    Repeater {
                                        model: groupItem.displayEntries

                                        delegate: Item {
                                            id: notificationRow

                                            required property var modelData
                                            required property int index
                                            property bool bodyExpanded: false
                                            readonly property string icon:
                                                sidebar.resolveIcon(modelData)

                                            Layout.fillWidth: true
                                            implicitHeight:
                                                notificationContent.implicitHeight
                                                    + 20

                                            ColumnLayout {
                                                id: notificationContent

                                                anchors {
                                                    left: parent.left
                                                    right: parent.right
                                                    top: parent.top
                                                    topMargin: 10
                                                    leftMargin: 10
                                                    rightMargin: 4
                                                }
                                                spacing: 4

                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    Layout.preferredHeight: 30
                                                    spacing: 8

                                                    Item {
                                                        Layout.preferredWidth: 30
                                                        Layout.preferredHeight: 30
                                                        clip: true

                                                        IconImage {
                                                            id: appIcon
                                                            anchors.centerIn:
                                                                parent
                                                            width: 26
                                                            height: 26
                                                            visible: source
                                                                .toString()
                                                                .length > 0
                                                            source:
                                                                notificationRow
                                                                    .icon
                                                        }

                                                        Text {
                                                            anchors.centerIn:
                                                                parent
                                                            visible: !appIcon
                                                                .visible
                                                            text:
                                                                notificationRow
                                                                    .modelData
                                                                    .appName
                                                                    .charAt(0)
                                                                    .toUpperCase()
                                                            color: sidebar.theme
                                                                .textPrimary
                                                            font.family:
                                                                sidebar
                                                                    .fontFamily
                                                            font.pixelSize: 13
                                                            font.weight:
                                                                Font.Bold
                                                        }
                                                    }

                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: notificationRow
                                                            .modelData.appName
                                                        color: sidebar.theme
                                                            .textSecondary
                                                        elide: Text.ElideRight
                                                        font.family: sidebar
                                                            .fontFamily
                                                        font.pixelSize: 9
                                                        font.weight:
                                                            Font.DemiBold
                                                    }

                                                    Text {
                                                        text: sidebar
                                                            .relativeTime(
                                                                notificationRow
                                                                    .modelData
                                                                    .createdAt)
                                                        color: sidebar.theme
                                                            .textDisabled
                                                        font.family: sidebar
                                                            .fontFamily
                                                        font.pixelSize: 7
                                                    }

                                                    Item {
                                                        Layout.preferredWidth: 28
                                                        Layout.preferredHeight: 28

                                                        Text {
                                                            anchors.centerIn:
                                                                parent
                                                            text: "󰅖"
                                                            color: dismissMouse
                                                                .containsMouse
                                                                ? sidebar.theme
                                                                    .accent
                                                                : sidebar.theme
                                                                    .textMuted
                                                            opacity: dismissMouse
                                                                .containsMouse
                                                                ? 1 : 0.72
                                                            font.family:
                                                                sidebar
                                                                    .fontFamily
                                                            font.pixelSize: 11

                                                            Behavior on color {
                                                                ColorAnimation {
                                                                    duration: 120
                                                                }
                                                            }
                                                        }

                                                        MouseArea {
                                                            id: dismissMouse
                                                            anchors.fill: parent
                                                            hoverEnabled: true
                                                            cursorShape:
                                                                Qt.PointingHandCursor
                                                            onClicked:
                                                                notificationRow
                                                                    .modelData
                                                                    .dismiss()
                                                        }
                                                        }
                                                    }

                                                Text {
                                                    Layout.fillWidth: true
                                                    Layout.leftMargin: 38
                                                    Layout.rightMargin: 8
                                                    text: notificationRow
                                                        .modelData.summary
                                                    color: sidebar.theme
                                                        .textPrimary
                                                    wrapMode: Text.WordWrap
                                                    maximumLineCount: 2
                                                    elide: Text.ElideRight
                                                    font.family: sidebar
                                                        .fontFamily
                                                    font.pixelSize: 11
                                                    font.weight: Font.Bold
                                                    lineHeight: 1.12
                                                }

                                                Text {
                                                    id: bodyLabel

                                                    Layout.fillWidth: true
                                                    Layout.leftMargin: 38
                                                    Layout.rightMargin: 8
                                                    visible:
                                                        notificationRow
                                                            .modelData.body
                                                            .length > 0
                                                    text:
                                                        notificationRow
                                                            .modelData.body
                                                    color: sidebar.theme.textMuted
                                                    wrapMode: Text.WordWrap
                                                    maximumLineCount:
                                                        notificationRow
                                                            .bodyExpanded
                                                        ? 20 : 2
                                                    elide: Text.ElideRight
                                                    font.family:
                                                        sidebar.fontFamily
                                                    font.pixelSize: 9
                                                    lineHeight: 1.22

                                                    MouseArea {
                                                        id: rowMouse
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape:
                                                            bodyLabel.truncated
                                                                || notificationRow
                                                                    .bodyExpanded
                                                            ? Qt.PointingHandCursor
                                                            : Qt.ArrowCursor
                                                        onClicked: {
                                                            if (bodyLabel.truncated
                                                                    || notificationRow
                                                                        .bodyExpanded) {
                                                                notificationRow
                                                                    .bodyExpanded =
                                                                        !notificationRow
                                                                            .bodyExpanded
                                                            }
                                                        }
                                                    }
                                                }

                                                Flow {
                                                    visible:
                                                        notificationRow
                                                            .modelData.actions
                                                            .length > 0
                                                    Layout.fillWidth: true
                                                    Layout.leftMargin: 38
                                                    Layout.rightMargin: 8
                                                    Layout.preferredHeight:
                                                        implicitHeight
                                                    spacing: 4

                                                    Repeater {
                                                        model:
                                                            notificationRow
                                                                .modelData
                                                                .actions
                                                                .slice(0, 3)

                                                        delegate: Item {
                                                            id: actionButton
                                                            required property
                                                                var modelData
                                                            width: Math.min(
                                                                128,
                                                                actionLabel
                                                                    .implicitWidth
                                                                    + 18)
                                                            height: 28

                                                            Text {
                                                                id: actionLabel
                                                                anchors.centerIn:
                                                                    parent
                                                                text:
                                                                    actionButton
                                                                        .modelData
                                                                        .text
                                                                color:
                                                                    actionMouse
                                                                        .containsMouse
                                                                    ? sidebar.theme.accent
                                                                    : sidebar.theme.textSecondary
                                                                elide:
                                                                    Text.ElideRight
                                                                font.family:
                                                                    sidebar
                                                                        .fontFamily
                                                                font.pixelSize: 8
                                                                font.weight:
                                                                    Font.DemiBold
                                                            }

                                                            Rectangle {
                                                                anchors {
                                                                    bottom: parent.bottom
                                                                    horizontalCenter:
                                                                        parent.horizontalCenter
                                                                }
                                                                width: actionMouse.containsMouse
                                                                    ? parent.width
                                                                    - 10 : 12
                                                                height: 1
                                                                color: sidebar.theme.accentMuted

                                                                Behavior on width {
                                                                    NumberAnimation {
                                                                        duration: 140
                                                                        easing.type:
                                                                            Easing.OutCubic
                                                                    }
                                                                }
                                                            }

                                                            MouseArea {
                                                                id: actionMouse
                                                                anchors.fill:
                                                                    parent
                                                                hoverEnabled:
                                                                    true
                                                                cursorShape:
                                                                    Qt.PointingHandCursor
                                                                onClicked:
                                                                    notificationRow
                                                                        .modelData
                                                                        .invokeAction(
                                                                            actionButton
                                                                                .modelData)
                                                            }
                                                        }
                                                    }
                                                }
                                            }

                                            Rectangle {
                                                visible:
                                                    notificationRow.index
                                                        < groupItem
                                                            .displayEntries
                                                            .length - 1
                                                anchors {
                                                    left: parent.left
                                                    right: parent.right
                                                    bottom: parent.bottom
                                                    leftMargin: 49
                                                    rightMargin: 12
                                                }
                                                height: 1
                                                color: sidebar.theme
                                                    .surfaceHover
                                            }
                                        }
                                    }

                                    Rectangle {
                                        visible: groupItem.index
                                            < groupRepeater.count - 1
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: visible ? 1 : 0
                                        Layout.leftMargin: 49
                                        Layout.rightMargin: 12
                                        color: sidebar.theme.surfaceHover
                                        opacity: 0.82
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

            LocalAiChat {
                id: localAiChat

                anchors.fill: parent
                visible: sidebar.selectedTab === 1
                theme: sidebar.theme
                active: sidebar.active && sidebar.selectedTab === 1
            }
        }
    }

    component TabSwitch: Item {
        id: tab

        required property bool activeTab
        required property string label
        property string tooltip: ""
        signal clicked

        Layout.preferredWidth: 38
        Layout.preferredHeight: 46
        Layout.alignment: Qt.AlignVCenter
        width: 38
        height: 46

        Text {
            anchors {
                horizontalCenter: parent.horizontalCenter
                top: parent.top
                topMargin: 6
            }
            text: tab.label
            color: tab.activeTab || tabMouse.containsMouse
                ? sidebar.theme.textBright : sidebar.theme.textMuted
            font.family: sidebar.fontFamily
            font.pixelSize: 16
            Behavior on color { ColorAnimation { duration: 120 } }
        }

        Rectangle {
            anchors {
                bottom: parent.bottom
                horizontalCenter: parent.horizontalCenter
            }
            width: tab.activeTab ? 18 : tabMouse.containsMouse ? 8 : 3
            height: 2
            radius: 1
            color: tab.activeTab
                ? sidebar.theme.accent : sidebar.theme.outlineSubtle

            Behavior on width {
                NumberAnimation { duration: 170; easing.type: Easing.OutCubic }
            }
            Behavior on color { ColorAnimation { duration: 120 } }
        }

        MouseArea {
            id: tabMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tab.clicked()
        }
    }

    component HeaderButton: Item {
        id: button

        required property string label
        property string tooltip: ""
        signal clicked

        Layout.preferredWidth: 28
        Layout.preferredHeight: 28
        Layout.alignment: Qt.AlignVCenter
        width: 28
        height: 28

        Text {
            id: buttonIcon
            anchors.centerIn: parent
            text: button.label
            width: parent.width
            height: parent.height
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            color: buttonMouse.containsMouse
                ? sidebar.theme.accent : sidebar.theme.textMuted
            font.family: sidebar.fontFamily
            font.pixelSize: 14

            transform: Translate {
                y: buttonMouse.containsMouse ? -1 : 0
                Behavior on y { NumberAnimation { duration: 120 } }
            }
            Behavior on color {
                ColorAnimation { duration: 120 }
            }
        }

        MouseArea {
            id: buttonMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: button.clicked()
        }
    }
}

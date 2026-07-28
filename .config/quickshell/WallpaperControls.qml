pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: root

    required property var theme
    property int wallpaperCount: 0
    property bool loading: false
    property string mediaMode: "static"

    signal refreshRequested()
    signal mediaModeRequested(string mode)

    height: 34

    Row {
        anchors.centerIn: parent
        spacing: 8

        Rectangle {
            id: staticButton

            width: 84
            height: 30
            radius: 15
            color: root.mediaMode === "static"
                ? root.theme.accentMuted
                : (staticMouse.containsMouse
                    ? root.theme.surfaceActive : root.theme.surfaceRaised)
            border.width: 1
            border.color: root.mediaMode === "static"
                ? root.theme.accent : root.theme.outlineSubtle
            scale: staticMouse.pressed ? 0.96 : 1

            Behavior on color { ColorAnimation { duration: 160 } }
            Behavior on scale {
                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
            }

            Text {
                anchors.centerIn: parent
                text: "▧  Static"
                color: root.mediaMode === "static"
                    ? root.theme.onAccent : root.theme.textSecondary
                font.pixelSize: 10
                font.weight: Font.Medium
            }

            MouseArea {
                id: staticMouse

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.mediaModeRequested("static")
            }
        }

        Rectangle {
            id: animatedButton

            width: 104
            height: 30
            radius: 15
            color: root.mediaMode === "animated"
                ? root.theme.accentMuted
                : (animatedMouse.containsMouse
                    ? root.theme.surfaceActive : root.theme.surfaceRaised)
            border.width: 1
            border.color: root.mediaMode === "animated"
                ? root.theme.accent : root.theme.outlineSubtle
            scale: animatedMouse.pressed ? 0.96 : 1

            Behavior on color { ColorAnimation { duration: 160 } }
            Behavior on scale {
                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
            }

            Text {
                anchors.centerIn: parent
                text: "▰  Animated"
                color: root.mediaMode === "animated"
                    ? root.theme.onAccent : root.theme.textSecondary
                font.pixelSize: 10
                font.weight: Font.Medium
            }

            MouseArea {
                id: animatedMouse

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.mediaModeRequested("animated")
            }
        }

        Rectangle {
            id: refreshButton

            width: 88
            height: 30
            radius: 15
            color: refreshMouse.containsMouse
                ? root.theme.surfaceActive : root.theme.surfaceRaised
            border.width: 1
            border.color: root.theme.outlineSubtle
            scale: refreshMouse.pressed ? 0.96 : 1

            Behavior on color { ColorAnimation { duration: 160 } }
            Behavior on scale {
                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
            }

            Text {
                anchors.centerIn: parent
                text: root.loading ? "Processing…" : "↻  Refresh"
                color: root.theme.textSecondary
                font.pixelSize: 10
                font.weight: Font.Medium
            }

            MouseArea {
                id: refreshMouse

                anchors.fill: parent
                enabled: !root.loading
                hoverEnabled: true
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.refreshRequested()
            }
        }
    }
}

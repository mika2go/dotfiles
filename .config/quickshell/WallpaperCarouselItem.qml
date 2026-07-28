pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Widgets

Item {
    id: root

    required property var theme
    required property int index
    required property string filePath
    required property string fileUrl
    required property string fileName
    required property string relativePath
    required property string mediaType
    required property bool isAnimated
    property bool active: false
    property bool viewMoving: false
    property bool revealed: false
    readonly property bool currentItem: PathView.isCurrentItem
    readonly property bool previewReady:
        image.status === Image.Ready || image.status === Image.Error

    signal activated()
    signal focusRequested()

    width: 310
    height: 220
    z: currentItem ? 3 : (PathView.onPath ? 1 : 0)
    scale: (currentItem ? 1 : (PathView.onPath ? 0.8 : 0))
        * (revealed ? 1 : 0.65)
    opacity: PathView.onPath && revealed ? 1 : 0

    Component.onCompleted: revealTimer.start()

    Behavior on scale {
        NumberAnimation { duration: 440; easing.type: Easing.OutBack }
    }

    Behavior on opacity {
        NumberAnimation { duration: 360; easing.type: Easing.OutCubic }
    }

    Timer {
        id: revealTimer
        interval: 34 * Math.min(root.index, 6)
        onTriggered: root.revealed = true
    }

    ClippingRectangle {
        id: imageFrame

        anchors.horizontalCenter: parent.horizontalCenter
        y: 17
        width: 286
        height: Math.round(width / 16 * 9)
        radius: 20
        color: root.theme.surfaceGlass
        border.width: root.active ? 3 : (root.currentItem ? 2 : 1)
        border.color: root.active ? root.theme.accentHover
            : (root.currentItem ? root.theme.textMuted : root.theme.surfaceActive)
        antialiasing: true

        Rectangle {
            anchors.centerIn: parent
            width: 42
            height: 42
            radius: 14
            color: root.theme.surfaceSubtle

            Text {
                anchors.centerIn: parent
                text: "▧"
                color: root.theme.textMuted
                font.pixelSize: 20
            }
        }

        Image {
            id: image

            anchors.fill: parent
            source: root.fileUrl
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            smooth: !root.viewMoving
            mipmap: !root.viewMoving
            sourceSize: Qt.size(
                Math.max(1, Math.ceil(imageFrame.width * 1.5)),
                Math.max(1, Math.ceil(imageFrame.height * 1.5))
            )
            opacity: status === Image.Ready ? 1 : 0
            scale: status === Image.Ready ? 1 : 0.7

            Behavior on opacity {
                NumberAnimation { duration: 560; easing.type: Easing.OutCubic }
            }

            Behavior on scale {
                NumberAnimation { duration: 650; easing.type: Easing.OutBack }
            }
        }

        Rectangle {
            anchors.fill: parent
            color: itemMouse.containsMouse ? root.theme.hoverScrim : "transparent"

            Behavior on color {
                ColorAnimation { duration: 180 }
            }
        }

        Rectangle {
            anchors {
                top: parent.top
                right: parent.right
                margins: 9
            }
            visible: root.isAnimated
            width: mediaLabel.implicitWidth + 16
            height: 24
            radius: 9
            color: root.theme.surface
            border.width: 1
            border.color: root.theme.outlineSubtle

            Text {
                id: mediaLabel

                anchors.centerIn: parent
                text: root.mediaType === "gif" ? "GIF" : "▶ VIDEO"
                color: root.theme.textPrimary
                font.pixelSize: 8
                font.weight: Font.DemiBold
            }
        }
    }

    Text {
        id: label

        anchors {
            top: imageFrame.bottom
            topMargin: 12
            horizontalCenter: parent.horizontalCenter
        }
        width: imageFrame.width - 18
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideMiddle
        text: root.relativePath
        color: root.currentItem ? root.theme.textPrimary : root.theme.textMuted
        font.pixelSize: root.currentItem ? 11 : 10
        font.weight: root.currentItem ? Font.DemiBold : Font.Normal

        Behavior on color {
            ColorAnimation { duration: 220 }
        }
    }

    Rectangle {
        anchors {
            top: label.bottom
            topMargin: 8
            horizontalCenter: parent.horizontalCenter
        }
        visible: root.active
        width: 28
        height: 4
        radius: 2
        color: root.theme.accentHover
    }

    MouseArea {
        id: itemMouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (root.currentItem)
                root.activated()
            else
                root.focusRequested()
        }
    }
}

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications
import Quickshell.Wayland
import Quickshell.Widgets
import Mono.Sdf

// One shared surface is required: only shapes inside the same SdfCanvas can
// smooth-union. These are the four existing shell frame objects represented
// as SDF shapes: left, top, right and bottom monitor frame. The shell bar is
// intentionally separate and keeps its own background.
PanelWindow {
    id: border

    required property var theme
    required property var borderScreen
    required property var notificationCenter
    property bool suppressed: false

    property real sidebarWidth: 54
    property real frameWidth: 14
    property real edgeBleed: 2
    property real mergeSmoothness: 30
    property color borderColor: border.theme.surfaceGlass
    property bool hoverActive: false
    property real hoverOffsetScale: hoverActive ? 0 : 1
    property real hoverCenterY: height / 2
    property real hoverWidth: sidebarWidth
    property real hoverHeight: 236
    readonly property real hoverProgress: 1 - hoverOffsetScale
    property int notificationCount: notificationCenter.popupEntries.length
    property bool notificationClosing: false
    property real notificationOffsetScale: notificationCount > 0
        && !notificationClosing ? 0 : 1
    readonly property real notificationProgress: 1 - notificationOffsetScale
    property real notificationWidth: 320
    property real notificationHeight: 76
    property real notificationRightMargin: 24
    property bool islandExpanded: false
    property bool islandVisible: false
    property real islandProgress: 0
    property real islandWidthProgress: islandProgress
    property real islandHeightProgress: islandProgress
    property real islandTravelProgress: islandProgress
    property real islandWidth: 840
    property real islandHeight: 348
    property real launcherProgress: 0
    property real launcherWidth: 620
    property real launcherHeight: 76
    property alias wallpaperController: wallpaperShelf
    property real powerProgress: 0
    property real powerWidth: 760
    property real powerHeight: 300
    property real mixerProgress: 0
    property real mixerOffsetScale: 1
    property real mixerWidth: 430
    property real mixerHeight: 650
    property real networkProgress: 0
    property real networkOffsetScale: 1
    property real networkWidth: 430
    property real networkHeight: 590
    readonly property real notificationCenterX: width
        - notificationRightMargin - notificationWidth / 2
    readonly property real notificationAnimatedX: notificationCenterX
        + (notificationWidth + 5) * notificationOffsetScale
    readonly property real notificationAnimatedWidth: notificationWidth
    readonly property real notificationAnimatedHeight: notificationHeight
    readonly property real notificationAnimatedTop: 5
    readonly property real notificationSidebarNarrowWidth: 350
    readonly property real notificationSidebarWideWidth: 600
    property real notificationSidebarMorph:
        notificationSidebarUi.selectedTab === 1 ? 1 : 0
    readonly property real notificationSidebarWidth:
        notificationSidebarNarrowWidth
        + (notificationSidebarWideWidth - notificationSidebarNarrowWidth)
            * notificationSidebarMorph
    property real notificationSidebarTop: 5
    property real notificationSidebarBottom: 5
    readonly property real notificationSidebarHeight: Math.max(
        0, height - notificationSidebarTop - notificationSidebarBottom)
    readonly property real notificationSidebarX: width
        - notificationSidebarWidth
        + (notificationSidebarWidth + 5)
            * notificationCenter.offsetScale

    Behavior on notificationOffsetScale {
        NumberAnimation {
            duration: 500
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.38, 1.21, 0.22, 1.0, 1.0, 1.0]
        }
    }

    Behavior on notificationSidebarMorph {
        NumberAnimation {
            duration: 320
            easing.type: Easing.InOutCubic
        }
    }

    Behavior on notificationHeight {
        NumberAnimation { duration: 220; easing.type: Easing.InOutSine }
    }

    onNotificationCountChanged: {
        if (border.notificationCount > 1)
            border.notificationClosing = false
        if (border.notificationCount > 0)
            Qt.callLater(border.syncNotificationHeight)
        else if (border.notificationProgress < 0.001) {
            border.notificationClosing = false
            border.notificationHeight = 76
        }
    }

    onNotificationProgressChanged: {
        if (border.notificationProgress < 0.001
                && border.notificationCount === 0)
            border.notificationHeight = 76
    }

    function syncNotificationHeight() {
        if (border.notificationCount > 0)
            border.notificationHeight = Math.max(
                76, notificationStack.implicitHeight + 24)
    }

    function notificationIcon(notification) {
        if ((notification.image || "").length > 0)
            return notification.image
        const icon = notification.appIcon || ""
        if (icon.startsWith("/") || icon.startsWith("file:"))
            return icon
        if (icon.length > 0 && Quickshell.hasThemeIcon(icon))
            return Quickshell.iconPath(icon)
        return ""
    }

    screen: borderScreen
    visible: borderScreen !== null && !border.suppressed
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Top
    focusable: wallpaperShelf.windowVisible
        || notificationCenter.windowVisible

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    // The frame remains click-through. Only the open wallpaper shelf receives
    // input, so the full-screen border surface never blocks applications.
    mask: Region {
        Region { item: wallpaperInputRegion }
        Region { item: notificationInputRegion }
        Region { item: notificationSidebarInputRegion }
    }

    SdfCanvas {
        id: frame
        anchors.fill: parent
        fillColor: border.borderColor
        smoothness: border.mergeSmoothness

        // The sidebar must live in this same canvas as all four monitor
        // edges. MonoSDF can only create the top-left and bottom-left inner
        // fillets when these shapes participate in one smooth union.
        SdfRoundRect {
            x: (border.sidebarWidth - border.edgeBleed) / 2
            y: frame.height / 2
            halfWidth: (border.sidebarWidth + border.edgeBleed) / 2
            halfHeight: frame.height / 2
            cornerRadius: 0
        }

        // Hover content is another shape in this exact canvas. MonoSDF
        // smooth-unions it with the sidebar instead of drawing a detached
        // popup beside the frame.
        SdfRoundRect {
            enabled: border.hoverProgress > 0.001
            x: border.hoverWidth / 2
                + (-border.hoverWidth - 5) * border.hoverOffsetScale
            y: border.hoverCenterY
            halfWidth: border.hoverWidth / 2
            halfHeight: border.hoverHeight / 2
            cornerRadius: 20
            cornerSmoothing: 0.75
        }

        // The mixer is a full-size left-edge wrapper. Its geometry remains
        // constant and only its position follows the shared Caelestia offset.
        SdfRoundRect {
            enabled: border.mixerProgress > 0.001
            x: border.mixerWidth / 2
                + (-border.mixerWidth - 5) * border.mixerOffsetScale
            y: frame.height / 2
            halfWidth: border.mixerWidth / 2
            halfHeight: border.mixerHeight / 2
            cornerRadius: 28
            cornerSmoothing: 0.78
        }

        // Top frame and Dynamic Island form one MonoSDF surface. The Island
        // keeps its full geometry and follows Caelestia's animated top offset.
        SdfGroup {
            op: SdfGroup.Union
            smoothness: border.islandProgress > 0.001
                    || border.notificationProgress > 0.001
                    || border.powerProgress > 0.001
                ? border.mergeSmoothness
                : 0

            SdfRoundRect {
                x: frame.width / 2
                y: (border.frameWidth - border.edgeBleed) / 2
                halfWidth: frame.width / 2
                halfHeight: (border.frameWidth + border.edgeBleed) / 2
                cornerRadius: 0
            }

            SdfRoundRect {
                enabled: border.islandProgress > 0.001
                origin: SdfShape.Top
                x: frame.width / 2 + border.sidebarWidth / 2
                y: 5 - (border.islandHeight * border.islandHeightProgress + 5)
                    * (1 - border.islandTravelProgress)
                halfWidth: border.islandWidth / 2
                    * border.islandWidthProgress
                halfHeight: border.islandHeight / 2
                    * border.islandHeightProgress
                cornerRadius: 30 * border.islandWidthProgress
                cornerSmoothing: 0.78
            }

            // Notifications use the same zero-to-surface morph as the
            // Dynamic Island. At progress zero the primitive is a point
            // inside the top frame, so closing cannot leave a small tab.
            SdfRoundRect {
                enabled: border.notificationProgress > 0.001
                origin: SdfShape.Top
                x: border.notificationAnimatedX
                y: border.notificationAnimatedTop
                halfWidth: border.notificationAnimatedWidth / 2
                halfHeight: border.notificationAnimatedHeight / 2
                cornerRadius: 18
                cornerSmoothing: 0.76
            }

            // The power surface keeps its full geometry and follows the same
            // top-edge offset as its content window.
            SdfRoundRect {
                enabled: border.powerProgress > 0.001
                origin: SdfShape.Top
                x: frame.width / 2
                y: 5 - (border.powerHeight + 5)
                    * (1 - border.powerProgress)
                halfWidth: border.powerWidth / 2
                halfHeight: border.powerHeight / 2
                cornerRadius: 24
                cornerSmoothing: 0.76
            }
        }

        // The notification center and the persistent right monitor frame
        // share one MonoSDF union. The full-size drawer only translates, so
        // it visibly emerges from the edge and stays fused to it.
        SdfGroup {
            op: SdfGroup.Union
            smoothness: border.notificationCenter.progress > 0.001
                ? border.mergeSmoothness : 0

            SdfRoundRect {
                x: frame.width
                    - (border.frameWidth - border.edgeBleed) / 2
                y: frame.height / 2
                halfWidth: (border.frameWidth + border.edgeBleed) / 2
                halfHeight: frame.height / 2
                cornerRadius: 0
            }

            SdfRoundRect {
                enabled: border.notificationCenter.progress > 0.001
                x: border.notificationSidebarX
                    + border.notificationSidebarWidth / 2
                y: border.notificationSidebarTop
                    + border.notificationSidebarHeight / 2
                halfWidth: border.notificationSidebarWidth / 2
                halfHeight: border.notificationSidebarHeight / 2
                cornerRadius: 22
                cornerSmoothing: 0.76
            }
        }

        // The wallpaper wrapper keeps its full geometry and follows the same
        // bottom offset animation as Caelestia's launcher wrapper.
        SdfGroup {
            op: SdfGroup.Union
            smoothness: wallpaperShelf.morphProgress > 0.001
                    || border.launcherProgress > 0.001
                    || border.networkProgress > 0.001
                ? border.mergeSmoothness : 0

            SdfRoundRect {
                x: frame.width / 2
                y: frame.height - (border.frameWidth - border.edgeBleed) / 2
                halfWidth: frame.width / 2
                halfHeight: (border.frameWidth + border.edgeBleed) / 2
                cornerRadius: 0
            }

            SdfRoundRect {
                enabled: wallpaperShelf.morphProgress > 0.001
                origin: SdfShape.Bottom
                x: wallpaperShelf.x + wallpaperShelf.width / 2
                y: frame.height - border.frameWidth / 2
                    + (wallpaperShelf.height + 5)
                        * (1 - wallpaperShelf.morphProgress)
                halfWidth: wallpaperShelf.width / 2
                halfHeight: wallpaperShelf.height / 2
                cornerRadius: 18
                cornerSmoothing: 0.72
            }

            SdfRoundRect {
                enabled: border.launcherProgress > 0.001
                origin: SdfShape.Bottom
                x: border.sidebarWidth
                    + (frame.width - border.sidebarWidth) / 2
                y: frame.height - border.frameWidth / 2
                    + (border.launcherHeight + 5)
                        * (1 - border.launcherProgress)
                halfWidth: border.launcherWidth / 2
                halfHeight: border.launcherHeight / 2
                cornerRadius: 18
                cornerSmoothing: 0.72
            }

            // The network manager keeps its full geometry and emerges from
            // the lower-right corner on the same offset as its content.
            SdfRoundRect {
                enabled: border.networkProgress > 0.001
                origin: SdfShape.Bottom
                x: frame.width - border.networkWidth / 2
                y: frame.height - border.frameWidth / 2
                    + (border.networkHeight + 5)
                        * border.networkOffsetScale
                halfWidth: border.networkWidth / 2
                halfHeight: border.networkHeight / 2
                cornerRadius: 28
                cornerSmoothing: 0.78
            }
        }
    }

    Item {
        id: wallpaperInputRegion
        x: wallpaperShelf.x - 24
        y: wallpaperShelf.y
        width: wallpaperShelf.windowVisible ? wallpaperShelf.width + 48 : 0
        height: wallpaperShelf.windowVisible ? wallpaperShelf.height : 0
    }

    Item {
        id: notificationInputRegion
        x: border.notificationCenterX - border.notificationWidth / 2
        y: 5
        width: border.notificationProgress > 0.98
            ? border.notificationWidth : 0
        height: border.notificationProgress > 0.98
            ? border.notificationHeight : 0
    }

    Item {
        id: notificationSidebarInputRegion
        x: border.notificationSidebarX
        y: border.notificationSidebarTop
        width: border.notificationCenter.windowVisible
            ? border.notificationSidebarWidth : 0
        height: border.notificationSidebarHeight
    }

    Item {
        id: notificationSidebarContent
        x: border.notificationSidebarX
        y: border.notificationSidebarTop
        width: border.notificationSidebarWidth
        height: border.notificationSidebarHeight
        opacity: 1 - border.notificationCenter.offsetScale
        visible: border.notificationCenter.windowVisible
        clip: true
        z: 3

        NotificationSidebar {
            id: notificationSidebarUi
            theme: border.theme
            anchors.fill: parent
            notificationCenter: border.notificationCenter
            active: border.notificationCenter.shown
            onCloseRequested: border.notificationCenter.close()
        }
    }

    Item {
        id: notificationContent
        x: border.notificationAnimatedX
            - border.notificationAnimatedWidth / 2
        y: border.notificationAnimatedTop
        width: border.notificationAnimatedWidth
        height: border.notificationAnimatedHeight
        opacity: 1 - border.notificationOffsetScale
        visible: border.notificationOffsetScale < 1
        clip: true
        z: 2

        Column {
            id: notificationStack
            x: parent.width - width - 10
            y: 15
            width: border.notificationWidth - 20
            spacing: 3

            onImplicitHeightChanged: border.syncNotificationHeight()

            function resolveIcon(notification) {
                return border.notificationIcon(notification)
            }

            Repeater {
                model: border.notificationCenter.popupEntries

                delegate: Item {
                    id: toast

                    required property var modelData
                    readonly property var palette: border.theme
                    property string resolvedIcon: notificationStack.resolveIcon(modelData)
                    property bool hovered: toastMouse.containsMouse
                    property bool exiting: false
                    property bool closesSurface: false
                    property bool dismissAfterExit: false
                    property real exitProgress: exiting ? 1 : 0

                    width: notificationStack.width
                    height: Math.max(48, notificationRow.implicitHeight + 16)
                    opacity: closesSurface ? 1 : 1 - exitProgress
                    scale: closesSurface ? 1 : 1 - 0.08 * exitProgress

                    Behavior on exitProgress {
                        NumberAnimation { duration: 220; easing.type: Easing.InOutSine }
                    }

                    function beginExit(dismissed) {
                        if (toast.exiting)
                            return
                        toast.dismissAfterExit = dismissed
                        toast.closesSurface = border.notificationCount === 1
                        toast.exiting = true
                        if (toast.closesSurface)
                            border.notificationClosing = true
                        notificationRemoval.interval = toast.closesSurface ? 515 : 220
                        notificationRemoval.restart()
                    }

                    Timer {
                        interval: {
                            if (toast.modelData.urgency === NotificationUrgency.Critical)
                                return 12000
                            const requested = Number(toast.modelData.expireTimeout)
                            return requested > 0 ? Math.max(3500, requested) : 6000
                        }
                        running: border.notificationProgress >= 0.999 && !toast.hovered
                        onTriggered: toast.beginExit(false)
                    }

                    Timer {
                        id: notificationRemoval
                        onTriggered: {
                            if (toast.dismissAfterExit)
                                toast.modelData.dismiss()
                            else
                                toast.modelData.expirePopup()
                        }
                    }

                    RowLayout {
                        id: notificationRow
                        anchors {
                            fill: parent
                            leftMargin: 10
                            rightMargin: 8
                            topMargin: 7
                            bottomMargin: 7
                        }
                        spacing: 9

                        Item {
                            Layout.preferredWidth: 30
                            Layout.preferredHeight: 30
                            Layout.alignment: Qt.AlignTop

                            IconImage {
                                anchors.centerIn: parent
                                width: 18
                                height: 18
                                visible: toast.resolvedIcon.length > 0
                                source: toast.resolvedIcon
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: toast.resolvedIcon.length === 0
                                text: (toast.modelData.appName || "A").charAt(0).toUpperCase()
                                color: border.theme.textPrimary
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 11
                                font.weight: Font.Bold
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 5

                                Text {
                                    Layout.fillWidth: true
                                    text: toast.modelData.summary || "Benachrichtigung"
                                    color: border.theme.textPrimary
                                    elide: Text.ElideRight
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                }

                                Text {
                                    text: "jetzt"
                                    color: border.theme.textMuted
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 8
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: text.length > 0
                                text: toast.modelData.body || toast.modelData.appName || ""
                                color: border.theme.textMuted
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 9
                                lineHeight: 1.05
                            }

                            Row {
                                visible: toast.modelData.actions.length > 0
                                spacing: 5

                                Repeater {
                                    model: toast.modelData.actions.slice(0, 2)

                                    delegate: Rectangle {
                                        id: notificationAction
                                        required property var modelData
                                        width: Math.min(130, notificationActionLabel.implicitWidth + 16)
                                        height: 22
                                        radius: 8
                                        color: notificationActionMouse.containsMouse
                                            ? toast.palette.textPrimary
                                            : toast.palette.surfaceHover

                                        Text {
                                            id: notificationActionLabel
                                            anchors.centerIn: parent
                                            text: notificationAction.modelData.text
                                            color: notificationActionMouse.containsMouse
                                                ? toast.palette.surface
                                                : toast.palette.textPrimary
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 8
                                        }

                                        MouseArea {
                                            id: notificationActionMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: toast.modelData.invokeAction(
                                                notificationAction.modelData)
                                        }
                                    }
                                }
                            }
                        }

                        Text {
                            Layout.preferredWidth: 22
                            Layout.preferredHeight: 30
                            Layout.alignment: Qt.AlignTop
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: "⌄"
                            color: dismissMouse.containsMouse ? border.theme.textBright : border.theme.textMuted
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 13

                            MouseArea {
                                id: dismissMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: toast.beginExit(true)
                            }
                        }
                    }

                    MouseArea {
                        id: toastMouse
                        anchors.fill: parent
                        acceptedButtons: Qt.NoButton
                        hoverEnabled: true
                    }
                }
            }
        }
    }

    WallpaperSwitcher {
        id: wallpaperShelf
        theme: border.theme
        width: Math.min(
            (parent.width - border.sidebarWidth) * 0.78,
            960
        )
        height: Math.min(320, parent.height * 0.37)
        x: border.sidebarWidth
            + (parent.width - border.sidebarWidth - width) / 2
        anchors {
            bottom: parent.bottom
            bottomMargin: border.frameWidth / 2
        }
        suppressed: border.suppressed
        z: 1
    }
}

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: power

    required property var theme
    property var powerScreen
    property var lockController
    property bool shown: false
    property bool windowVisible: false
    property bool suppressed: false
    property string pendingAction: ""
    property int selectedIndex: 0
    property real offsetScale: shown ? 0 : 1

    readonly property real morphProgress: 1 - offsetScale
    readonly property real surfaceWidth: 760
    readonly property real surfaceHeight: 300
    readonly property var actions: [
        {
            action: "lock",
            icon: "󰌾",
            label: "SPERREN",
            detail: "Sitzung schützen",
            dangerous: false
        },
        {
            action: "suspend",
            icon: "󰤄",
            label: "STANDBY",
            detail: "Energie sparen",
            dangerous: false
        },
        {
            action: "logout",
            icon: "󰗽",
            label: "ABMELDEN",
            detail: "Hyprland beenden",
            dangerous: true
        },
        {
            action: "reboot",
            icon: "󰜉",
            label: "NEUSTART",
            detail: "System neu laden",
            dangerous: true
        },
        {
            action: "shutdown",
            icon: "󰐥",
            label: "AUSSCHALTEN",
            detail: "PC herunterfahren",
            dangerous: true
        }
    ]

    Behavior on offsetScale {
        NumberAnimation {
            duration: 500
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.38, 1.21, 0.22, 1.0, 1.0, 1.0]
        }
    }

    function open(): void {
        closeTimer.stop()
        pendingAction = ""
        selectedIndex = 0
        windowVisible = true
        shown = true
        focusTimer.restart()
    }

    function close(): void {
        if (!windowVisible)
            return
        pendingAction = ""
        shown = false
        closeTimer.restart()
    }

    function toggle(): void {
        shown ? close() : open()
    }

    function request(actionName: string): void {
        const entry = actions.find(item => item.action === actionName)
        if (!entry)
            return

        if (entry.dangerous && pendingAction !== actionName) {
            pendingAction = actionName
            confirmTimer.restart()
            return
        }

        pendingAction = ""

        if (actionName === "lock") {
            close()
            if (lockController)
                lockController.activate()
            return
        }

        if (actionName === "suspend") {
            close()
            if (lockController)
                lockController.activate()
            suspendTimer.restart()
            return
        }

        close()
        actionProcess.command = actionName === "logout"
            ? ["hyprctl", "dispatch", "exit"]
            : actionName === "reboot"
                ? ["systemctl", "reboot"]
                : ["systemctl", "poweroff"]
        actionProcess.running = true
    }

    onSuppressedChanged: {
        if (suppressed)
            close()
    }

    IpcHandler {
        target: "power"

        function toggle(): void { power.toggle() }
        function open(): void { power.open() }
        function close(): void { power.close() }
    }

    Process { id: actionProcess }

    Timer {
        id: suspendTimer
        interval: 650
        onTriggered: {
            actionProcess.command = ["systemctl", "suspend"]
            actionProcess.running = true
        }
    }

    Timer {
        id: focusTimer
        interval: 60
        onTriggered: keyFocus.forceActiveFocus()
    }

    Timer {
        id: closeTimer
        interval: 515
        onTriggered: {
            if (!power.shown)
                power.windowVisible = false
        }
    }

    Timer {
        id: confirmTimer
        interval: 3500
        onTriggered: power.pendingAction = ""
    }

    PanelWindow {
        id: powerWindow
        screen: power.powerScreen
        visible: power.powerScreen !== null
            && !power.suppressed
            && power.windowVisible
        color: "transparent"
        implicitHeight: power.surfaceHeight + 5
        exclusiveZone: 0
        focusable: power.shown
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell:power"

        anchors {
            top: true
            left: true
            right: true
        }

        mask: Region { item: powerCard }

        Item {
            id: powerCard
            anchors.horizontalCenter: parent.horizontalCenter
            // The layer-shell work area starts after the 54 px sidebar and
            // ends before the 14 px right frame. Correct its asymmetric
            // center back to the physical monitor center.
            anchors.horizontalCenterOffset: (14 - 54) / 2
            width: Math.min(power.surfaceWidth, parent.width - 90)
            height: power.surfaceHeight
            y: 5 + (-height - 5) * power.offsetScale
            opacity: 1 - power.offsetScale
            visible: power.offsetScale < 1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 24
                spacing: 16

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 13

                    Rectangle {
                        Layout.preferredWidth: 42
                        Layout.preferredHeight: 42
                        radius: 13
                        color: power.theme.textPrimary

                        Text {
                            anchors.centerIn: parent
                            text: "󰐥"
                            color: power.theme.surfaceDeep
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 20
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            text: power.pendingAction === ""
                                ? "POWER SESSION"
                                : "AKTION NOCHMAL BESTÄTIGEN"
                            color: power.theme.textPrimary
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 17
                            font.weight: Font.Bold
                            font.letterSpacing: 0.6
                        }

                        Text {
                            text: power.pendingAction === ""
                                ? "Systemstatus und Sitzungsaktionen"
                                : power.actions.find(item => item.action === power.pendingAction).label
                                    + " wird beim zweiten Klick ausgeführt"
                            color: power.pendingAction === "" ? power.theme.textMuted : power.theme.textSecondary
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 9
                        }
                    }

                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: power.theme.surfaceHover
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 10

                    Repeater {
                        model: power.actions

                        Rectangle {
                            id: powerButton
                            required property var modelData
                            required property int index
                            readonly property bool armed: power.pendingAction === modelData.action
                            readonly property bool selected: power.selectedIndex === index

                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 18
                            color: armed || powerMouse.containsMouse || selected
                                ? power.theme.textPrimary : power.theme.surfaceRaised
                            border.width: 1
                            border.color: armed ? power.theme.textBright : power.theme.surfaceActive

                            Behavior on color { ColorAnimation { duration: 130 } }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 5

                                Item { Layout.fillHeight: true }

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: powerButton.modelData.icon
                                    color: powerButton.armed || powerMouse.containsMouse
                                        || powerButton.selected ? power.theme.surfaceDeep : power.theme.textPrimary
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 27
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: powerButton.armed ? "BESTÄTIGEN" : powerButton.modelData.label
                                    color: powerButton.armed || powerMouse.containsMouse
                                        || powerButton.selected ? power.theme.surfaceDeep : power.theme.textPrimary
                                    horizontalAlignment: Text.AlignHCenter
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 8
                                    font.weight: Font.Bold
                                    font.letterSpacing: 0.5
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: powerButton.modelData.detail
                                    color: powerButton.armed || powerMouse.containsMouse
                                        || powerButton.selected ? power.theme.outlineSubtle : power.theme.textMuted
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 7
                                }

                                Item { Layout.fillHeight: true }
                            }

                            MouseArea {
                                id: powerMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: power.selectedIndex = powerButton.index
                                onClicked: power.request(powerButton.modelData.action)
                            }
                        }
                    }
                }
            }

            Item {
                id: keyFocus
                anchors.fill: parent
                focus: power.shown

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        power.close()
                        event.accepted = true
                    } else if (event.key === Qt.Key_Left) {
                        power.selectedIndex = (power.selectedIndex
                            + power.actions.length - 1) % power.actions.length
                        event.accepted = true
                    } else if (event.key === Qt.Key_Right) {
                        power.selectedIndex = (power.selectedIndex + 1)
                            % power.actions.length
                        event.accepted = true
                    } else if (event.key === Qt.Key_Return
                            || event.key === Qt.Key_Enter) {
                        power.request(power.actions[power.selectedIndex].action)
                        event.accepted = true
                    }
                }
            }
        }
    }
}

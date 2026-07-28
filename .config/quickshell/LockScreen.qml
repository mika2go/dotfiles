pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Wayland
import Quickshell.Widgets

Scope {
    id: controller

    required property var theme
    property int cpuUsage: 0
    property int gpuUsage: 0
    property int memoryUsage: 0
    property bool networkOnline: false
    property int volume: 0
    property bool muted: false
    property var player: null

    readonly property date now: clock.date
    readonly property string userName: Quickshell.env("USER") || "mika"
    readonly property string hostName: Quickshell.env("HOSTNAME") || "MIKAROOT"
    readonly property bool locked: sessionLock.locked
    readonly property bool secure: sessionLock.secure

    property bool authenticating: false
    property bool unlocking: false
    property string pendingPassword: ""
    property string statusText: "PASSWORT EINGEBEN"
    property int failureSerial: 0
    property string pendingPower: ""

    function activate(): void {
        if (sessionLock.locked)
            return
        resetAuth()
        sessionLock.locked = true
    }

    function resetAuth(): void {
        if (passwordPam.active)
            passwordPam.abort()
        authenticating = false
        unlocking = false
        pendingPassword = ""
        statusText = "PASSWORT EINGEBEN"
        pendingPower = ""
        powerConfirmTimer.stop()
    }

    function authenticate(password: string): void {
        if (!sessionLock.secure || authenticating || unlocking)
            return
        if (password.length === 0) {
            statusText = "PASSWORT FEHLT"
            failureSerial++
            return
        }
        pendingPassword = password
        authenticating = true
        statusText = "WIRD GEPRÜFT"
        if (!passwordPam.start()) {
            authenticating = false
            pendingPassword = ""
            statusText = "PAM KONNTE NICHT STARTEN"
            failureSerial++
        }
    }

    function beginUnlock(): void {
        authenticating = false
        pendingPassword = ""
        statusText = "WILLKOMMEN ZURÜCK"
        unlocking = true
        unlockTimer.restart()
    }

    function requestPower(actionName: string): void {
        if (actionName === "suspend") {
            pendingPower = ""
            powerProcess.command = ["systemctl", "suspend"]
            powerProcess.running = true
            return
        }

        if (pendingPower !== actionName) {
            pendingPower = actionName
            powerConfirmTimer.restart()
            return
        }

        pendingPower = ""
        powerProcess.command = actionName === "reboot"
            ? ["systemctl", "reboot"]
            : ["systemctl", "poweroff"]
        powerProcess.running = true
    }

    IpcHandler {
        target: "lock"

        function activate(): void { controller.activate() }
        function status(): string {
            return controller.locked
                ? (controller.secure ? "secure" : "locking")
                : "unlocked"
        }
    }

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    Process { id: powerProcess }

    Timer {
        id: powerConfirmTimer
        interval: 3500
        onTriggered: controller.pendingPower = ""
    }

    Timer {
        id: unlockTimer
        interval: 530
        onTriggered: sessionLock.locked = false
    }

    PamContext {
        id: passwordPam
        config: "passwd"
        configDirectory: Quickshell.shellPath("assets/pam.d")

        onResponseRequiredChanged: {
            if (!responseRequired)
                return
            respond(controller.pendingPassword)
            controller.pendingPassword = ""
        }

        onCompleted: result => {
            if (result === PamResult.Success) {
                controller.beginUnlock()
                return
            }

            controller.authenticating = false
            controller.pendingPassword = ""
            controller.statusText = result === PamResult.MaxTries
                ? "ZU VIELE VERSUCHE"
                : result === PamResult.Error
                    ? "PAM-FEHLER"
                    : "PASSWORT IST NICHT KORREKT"
            controller.failureSerial++
        }

        onError: error => {
            controller.authenticating = false
            controller.pendingPassword = ""
            controller.statusText = "AUTHENTIFIZIERUNG FEHLGESCHLAGEN"
            controller.failureSerial++
        }
    }

    WlSessionLock {
        id: sessionLock

        onLockStateChanged: {
            if (!locked)
                controller.resetAuth()
        }

        LockSurface {
            authController: controller
        }
    }

    // Warm up the screencopy backend before the compositor becomes locked.
    // The real lock surfaces capture only one frame, so they remain cheap.
    Loader {
        asynchronous: true
        active: true
        onLoaded: active = false

        sourceComponent: ScreencopyView {
            captureSource: Quickshell.screens[0]
            live: false
            paintCursor: false
        }
    }

    component LockSurface: WlSessionLockSurface {
        id: surface

        required property var authController
        readonly property bool primary: screen?.name === "DP-1"
        readonly property real panelWidth: Math.min(width - 100, height * 1.50)
        readonly property real panelHeight: Math.min(height - 100, 760)
        property real offsetScale: 1

        color: controller.theme.surfaceDeep

        Component.onCompleted: {
            offsetScale = 0
        }

        Connections {
            target: surface.authController

            function onUnlockingChanged(): void {
                if (surface.authController.unlocking)
                    surface.offsetScale = 1
            }

        }

        Behavior on offsetScale {
            NumberAnimation {
                duration: 500
                easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.38, 1.21, 0.22, 1.0, 1.0, 1.0]
            }
        }

        ScreencopyView {
            id: desktopCapture
            anchors.fill: parent
            captureSource: surface.screen
            paintCursor: false
            live: false

            layer.enabled: true
            layer.effect: MultiEffect {
                autoPaddingEnabled: false
                blurEnabled: true
                blur: 0.85
                blurMax: 48
                blurMultiplier: 0.8
                saturation: -0.75
            }
        }

        Rectangle {
            anchors.fill: parent
            color: controller.theme.surfaceGlass
        }

        Repeater {
            model: 11

            Rectangle {
                required property int index
                x: index * surface.width / 10
                width: 1
                height: surface.height
                color: controller.theme.surfaceSubtle
            }
        }

        Item {
            id: lockWrapper
            width: surface.primary ? surface.panelWidth : Math.min(500, surface.width - 80)
            height: surface.primary ? surface.panelHeight : 260
            x: (surface.width - width) / 2
            readonly property real finalY: (surface.height - height) / 2
            y: finalY + (-height - 5) * surface.offsetScale
            opacity: 1 - surface.offsetScale
            visible: surface.offsetScale < 1

            Rectangle {
                anchors.fill: parent
                radius: 32
                color: controller.theme.surface
                border.width: 1
                border.color: controller.theme.outline
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: 9
                radius: 24
                color: "transparent"
                border.width: 1
                border.color: controller.theme.surfaceHover
            }

            Loader {
                anchors.fill: parent
                anchors.margins: surface.primary ? 24 : 28
                sourceComponent: surface.primary ? primaryContent : secondaryContent
            }
        }

        Component {
            id: secondaryContent

            ColumnLayout {
                spacing: 6

                Item { Layout.fillHeight: true }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: Qt.formatDateTime(surface.authController.now, "HHmm")
                    color: controller.theme.textPrimary
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 68
                    font.weight: Font.Black
                    font.letterSpacing: -6
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "󰌾  SESSION GESPERRT"
                    color: controller.theme.textMuted
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1.4
                }

                Item { Layout.fillHeight: true }
            }
        }

        Component {
            id: primaryContent

            RowLayout {
                id: primaryLayout
                spacing: 16

                Component.onCompleted: passwordFocusTimer.restart()

                Connections {
                    target: surface.authController

                    function onFailureSerialChanged(): void {
                        passwordInput.text = ""
                        passwordFocusTimer.restart()
                    }
                }

                Timer {
                    id: passwordFocusTimer
                    interval: 80
                    onTriggered: {
                        passwordInput.forceActiveFocus()
                        passwordInput.cursorPosition = passwordInput.length
                    }
                }

                ColumnLayout {
                    Layout.preferredWidth: 280
                    Layout.fillHeight: true
                    spacing: 12

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 168
                        radius: 22
                        color: controller.theme.surface
                        border.width: 1
                        border.color: controller.theme.surfaceActive

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 19
                            spacing: 3

                            RowLayout {
                                Layout.fillWidth: true

                                Text {
                                    text: "LOCAL SESSION"
                                    color: controller.theme.textMuted
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 9
                                    font.weight: Font.DemiBold
                                    font.letterSpacing: 1.2
                                }

                                Item { Layout.fillWidth: true }

                                Rectangle {
                                    Layout.preferredWidth: 8
                                    Layout.preferredHeight: 8
                                    radius: 4
                                    color: controller.theme.textPrimary
                                }
                            }

                            Text {
                                text: surface.authController.hostName.toUpperCase()
                                color: controller.theme.textPrimary
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 25
                                font.weight: Font.Bold
                            }

                            Text {
                                text: Qt.formatDateTime(surface.authController.now, "dddd, d. MMMM yyyy")
                                color: controller.theme.textMuted
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 9
                            }

                            Item { Layout.fillHeight: true }

                            Text {
                                text: "HYPRLAND  /  WAYLAND  /  MONO"
                                color: controller.theme.textSecondary
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 8
                                font.weight: Font.DemiBold
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 250
                        radius: 18
                        color: controller.theme.surface
                        border.width: 1
                        border.color: controller.theme.surfaceHover

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 18
                            spacing: 10

                            RowLayout {
                                Layout.fillWidth: true

                                Rectangle {
                                    Layout.preferredWidth: 28
                                    Layout.preferredHeight: 28
                                    radius: 8
                                    color: controller.theme.textPrimary

                                    Text {
                                        anchors.centerIn: parent
                                        text: ">"
                                        color: controller.theme.surfaceDeep
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                    }
                                }

                                Text {
                                    text: "mikafetch.sh"
                                    color: controller.theme.textPrimary
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 10
                                }

                                Item { Layout.fillWidth: true }

                                Text {
                                    text: "󰣇"
                                    color: controller.theme.textPrimary
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 22
                                }
                            }

                            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: controller.theme.surfaceHover }

                            Text {
                                Layout.fillWidth: true
                                text: "USER : " + surface.authController.userName.toUpperCase()
                                    + "\nCPU  : " + surface.authController.cpuUsage + "%"
                                    + "\nGPU  : " + surface.authController.gpuUsage + "%"
                                    + "\nRAM  : " + surface.authController.memoryUsage + "%"
                                    + "\nNET  : " + (surface.authController.networkOnline ? "ONLINE" : "OFFLINE")
                                color: controller.theme.textPrimary
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 10
                                lineHeight: 1.5
                            }

                            Item { Layout.fillHeight: true }

                            Row {
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 10

                                Repeater {
                                    model: [controller.theme.textPrimary, controller.theme.textSecondary, controller.theme.textSecondary, controller.theme.textMuted, controller.theme.outlineSubtle, controller.theme.surfaceHover]

                                    Rectangle {
                                        required property string modelData
                                        width: 18
                                        height: 18
                                        radius: 9
                                        color: modelData
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 22
                        color: controller.theme.surface
                        border.width: 1
                        border.color: controller.theme.surfaceHover

                        ColumnLayout {
                            anchors.centerIn: parent
                            width: parent.width - 34
                            spacing: 5

                            Text {
                                Layout.fillWidth: true
                                text: surface.authController.player
                                    ? (surface.authController.player.trackTitle || "NOTHING PLAYING")
                                    : "NOTHING PLAYING"
                                color: controller.theme.textPrimary
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                            }

                            Text {
                                Layout.fillWidth: true
                                text: surface.authController.player
                                    ? (surface.authController.player.trackArtist || "LOCAL MEDIA")
                                    : "LOCAL MEDIA"
                                color: controller.theme.textMuted
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 8
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.preferredWidth: 430
                    Layout.fillHeight: true
                    spacing: 8

                    Item { Layout.fillHeight: true }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: Qt.formatDateTime(surface.authController.now, "HHmm")
                        color: controller.theme.textPrimary
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 104
                        font.weight: Font.Black
                        font.letterSpacing: -9
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: -17
                        text: Qt.formatDateTime(surface.authController.now, "dddd  •  dd MMM").toUpperCase()
                        color: controller.theme.textPrimary
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        font.letterSpacing: 1
                    }

                    ClippingRectangle {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 24
                        Layout.preferredWidth: 156
                        Layout.preferredHeight: 156
                        radius: 78
                        color: controller.theme.surface
                        border.width: 2
                        border.color: controller.theme.textPrimary

                        ClippingRectangle {
                            anchors.fill: parent
                            anchors.margins: 7
                            radius: width / 2
                            color: "transparent"

                            Image {
                                anchors.fill: parent
                                source: "assets/profile-avatar.jpg"
                                fillMode: Image.PreserveAspectCrop
                                smooth: true
                                mipmap: true
                                asynchronous: true
                                sourceSize: Qt.size(312, 312)
                            }
                        }
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 10
                        text: surface.authController.userName.toUpperCase()
                        color: controller.theme.textPrimary
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        font.letterSpacing: 1.4
                    }

                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 10
                        Layout.preferredWidth: 390
                        Layout.preferredHeight: 56
                        radius: 28
                        color: controller.theme.surface
                        border.width: 1
                        border.color: passwordInput.activeFocus ? controller.theme.textPrimary : controller.theme.surfaceActive

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 19
                            anchors.verticalCenter: parent.verticalCenter
                            text: surface.authController.authenticating ? "󰔟" : "󰌾"
                            color: controller.theme.textMuted
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 16
                        }

                        TextInput {
                            id: passwordInput
                            anchors.left: parent.left
                            anchors.leftMargin: 52
                            anchors.right: submitButton.left
                            anchors.rightMargin: 9
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            enabled: surface.primary
                                && !surface.authController.authenticating
                                && !surface.authController.unlocking
                            color: controller.theme.textPrimary
                            selectionColor: controller.theme.textMuted
                            selectedTextColor: controller.theme.textBright
                            echoMode: TextInput.Password
                            passwordCharacter: "●"
                            verticalAlignment: TextInput.AlignVCenter
                            clip: true
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 12
                            onAccepted: surface.authController.authenticate(text)
                        }

                        Text {
                            anchors.left: passwordInput.left
                            anchors.verticalCenter: parent.verticalCenter
                            visible: passwordInput.text.length === 0
                            text: "Passwort"
                            color: controller.theme.textMuted
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 11
                        }

                        Rectangle {
                            id: submitButton
                            width: 42
                            height: 42
                            radius: 21
                            anchors.right: parent.right
                            anchors.rightMargin: 7
                            anchors.verticalCenter: parent.verticalCenter
                            color: passwordInput.text.length > 0 ? controller.theme.textPrimary : controller.theme.surfaceHover

                            Text {
                                anchors.centerIn: parent
                                text: "󰁔"
                                color: passwordInput.text.length > 0 ? controller.theme.surfaceDeep : controller.theme.textMuted
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 18
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: passwordInput.text.length > 0
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: surface.authController.authenticate(passwordInput.text)
                            }
                        }
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredHeight: 18
                        text: surface.authController.statusText
                        color: surface.authController.statusText === "PASSWORT EINGEBEN"
                            ? controller.theme.textMuted : controller.theme.textPrimary
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 8
                        font.weight: Font.DemiBold
                        font.letterSpacing: 1.2
                    }

                    Item { Layout.fillHeight: true }
                }

                ColumnLayout {
                    Layout.preferredWidth: 280
                    Layout.fillHeight: true
                    spacing: 12

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 126
                        radius: 22
                        color: controller.theme.surface
                        border.width: 1
                        border.color: controller.theme.surfaceActive

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 8

                            Repeater {
                                model: [
                                    { icon: "󰘚", label: surface.authController.cpuUsage + "%", sub: "CPU" },
                                    { icon: "󰍛", label: surface.authController.memoryUsage + "%", sub: "RAM" },
                                    { icon: "󰕾", label: surface.authController.volume + "%", sub: "VOL" }
                                ]

                                Rectangle {
                                    id: metricCell
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: 17
                                    color: controller.theme.surface
                                    border.width: 1
                                    border.color: controller.theme.surfaceActive

                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        spacing: 1

                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: metricCell.modelData.icon
                                            color: controller.theme.textMuted
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 15
                                        }

                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: metricCell.modelData.label
                                            color: controller.theme.textPrimary
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 11
                                            font.weight: Font.Bold
                                        }

                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: metricCell.modelData.sub
                                            color: controller.theme.textMuted
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 7
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 22
                        color: controller.theme.surface
                        border.width: 1
                        border.color: controller.theme.surfaceActive

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 18
                            spacing: 10

                            Text {
                                text: "SECURE SESSION"
                                color: controller.theme.textMuted
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 9
                                font.weight: Font.DemiBold
                                font.letterSpacing: 1.2
                            }

                            Repeater {
                                model: [
                                    ["󰌾", "PASSWORT", "PAM / UNIX"],
                                    ["󰖲", "COMPOSITOR", "HYPRLAND"],
                                    ["󰍹", "SESSION LOCK", "WAYLAND"]
                                ]

                                Rectangle {
                                    id: securityCell
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 62
                                    radius: 14
                                    color: controller.theme.surface
                                    border.width: 1
                                    border.color: controller.theme.surfaceHover

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 12
                                        spacing: 10

                                        Text {
                                            text: securityCell.modelData[0]
                                            color: controller.theme.textPrimary
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 16
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 1

                                            Text {
                                                text: securityCell.modelData[1]
                                                color: controller.theme.textPrimary
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 8
                                                font.weight: Font.DemiBold
                                            }

                                            Text {
                                                text: securityCell.modelData[2]
                                                color: controller.theme.textMuted
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 7
                                            }
                                        }

                                        Text {
                                            text: "●"
                                            color: controller.theme.textPrimary
                                            font.pixelSize: 8
                                        }
                                    }
                                }
                            }

                            Item { Layout.fillHeight: true }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 112
                        radius: 20
                        color: controller.theme.surface
                        border.width: 1
                        border.color: controller.theme.surfaceActive

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 8

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: surface.authController.pendingPower === ""
                                    ? "POWER"
                                    : "NOCHMAL BESTÄTIGEN"
                                color: surface.authController.pendingPower === ""
                                    ? controller.theme.textMuted : controller.theme.textPrimary
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 8
                                font.weight: Font.DemiBold
                                font.letterSpacing: 1
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: 7

                                Repeater {
                                    model: [
                                        { action: "suspend", icon: "󰤄", hint: "Standby" },
                                        { action: "reboot", icon: "󰜉", hint: "Neustart" },
                                        { action: "shutdown", icon: "󰐥", hint: "Aus" }
                                    ]

                                    Rectangle {
                                        id: lockPowerCell
                                        required property var modelData
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        radius: 13
                                        color: lockPowerMouse.containsMouse
                                            || surface.authController.pendingPower === lockPowerCell.modelData.action
                                            ? controller.theme.textPrimary : controller.theme.surfaceRaised

                                        Text {
                                            anchors.centerIn: parent
                                            text: lockPowerCell.modelData.icon
                                            color: lockPowerMouse.containsMouse
                                                || surface.authController.pendingPower === lockPowerCell.modelData.action
                                                ? controller.theme.surfaceDeep : controller.theme.textPrimary
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 16
                                        }

                                        MouseArea {
                                            id: lockPowerMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: surface.authController.requestPower(lockPowerCell.modelData.action)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

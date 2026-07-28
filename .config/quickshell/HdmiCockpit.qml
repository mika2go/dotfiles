pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import Quickshell.Widgets
import Mono.Sdf

Scope {
    id: cockpit

    required property var theme
    property var cockpitScreen
    property bool discordAvailable: false
    property bool discordConnected: false
    property string discordDisplayName: "Discord"
    property string discordUsername: ""
    property string discordAvatarUrl: ""
    property string discordChannelName: ""
    property string discordGuildName: ""
    property int discordParticipantCount: 0
    property bool discordMuted: false
    property bool discordDeafened: false
    property double discordJoinedAt: 0
    property string recordingState: "idle"
    property int recordingElapsedMs: 0
    property bool recordingActionsEnabled: false

    property real surfaceWidth: 720
    property real surfaceHeight: 90
    property real topBleed: 24
    readonly property PwNode microphone: Pipewire.defaultAudioSource
    readonly property bool microphoneMuted: microphone
        && microphone.audio ? microphone.audio.muted : false
    readonly property bool effectiveMicMuted: discordMuted
        || discordDeafened
        || microphoneMuted
    readonly property bool recordingActive: recordingState !== "idle"
        && recordingState !== "error"
    readonly property double voiceElapsedMs: discordConnected
        && discordJoinedAt > 0
        ? Math.max(0, clock.date.getTime() - discordJoinedAt)
        : 0

    function discordCommand(command): void {
        discordAction.command = [
            "/usr/bin/python3",
            "/home/mika/.config/quickshell/scripts/cockpit-discord-command.py",
            command
        ]
        discordAction.running = true
    }

    function formatDuration(milliseconds): string {
        const total = Math.max(0, Math.floor(Number(milliseconds) / 1000))
        const hours = Math.floor(total / 3600)
        const minutes = Math.floor((total % 3600) / 60)
        const seconds = total % 60
        const mm = minutes < 10 ? "0" + minutes : String(minutes)
        const ss = seconds < 10 ? "0" + seconds : String(seconds)
        return hours > 0 ? hours + ":" + mm + ":" + ss : minutes + ":" + ss
    }

    function recordingLabel(): string {
        if (recordingState === "paused")
            return "REC PAUSED"
        if (recordingState === "recording")
            return "RECORDING"
        if (recordingState === "stopping")
            return "REC SAVING"
        if (recordingState === "error")
            return "REC ERROR"
        return "REC IDLE"
    }

    IpcHandler {
        target: "cockpit"

        function refresh(): void {
            if (!statusProcess.running)
                statusProcess.running = true
        }

        function status(): string {
            return JSON.stringify({
                screen: cockpit.cockpitScreen
                    ? cockpit.cockpitScreen.name : "",
                permanent: true,
                bridge: cockpit.discordAvailable,
                connected: cockpit.discordConnected,
                channel: cockpit.discordChannelName,
                muted: cockpit.discordMuted,
                systemMuted: cockpit.microphoneMuted,
                effectiveMuted: cockpit.effectiveMicMuted,
                deafened: cockpit.discordDeafened
            })
        }
    }

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    PwObjectTracker {
        objects: cockpit.microphone ? [cockpit.microphone] : []
    }

    Process {
        id: statusProcess
        command: [
            "/usr/bin/python3",
            "/home/mika/.config/quickshell/scripts/cockpit-status.py"
        ]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const status = JSON.parse(text)
                    const discord = status.discord || {}
                    cockpit.discordAvailable = Boolean(discord.available)
                    cockpit.discordConnected = Boolean(discord.connected)
                    cockpit.discordDisplayName = discord.displayName || "Discord"
                    cockpit.discordUsername = discord.username || ""
                    cockpit.discordAvatarUrl = discord.avatarUrl || ""
                    cockpit.discordChannelName = discord.channelName || ""
                    cockpit.discordGuildName = discord.guildName || ""
                    cockpit.discordParticipantCount = Number(
                        discord.participantCount || 0)
                    cockpit.discordMuted = Boolean(discord.muted)
                    cockpit.discordDeafened = Boolean(discord.deafened)
                    cockpit.discordJoinedAt = Number(discord.joinedAt || 0)
                    cockpit.recordingState = status.recordingState || "idle"
                    cockpit.recordingElapsedMs = Number(
                        status.recordingElapsedMs || 0)
                    cockpit.recordingActionsEnabled = Boolean(
                        status.recordingActionsEnabled)
                } catch (error) {
                    cockpit.discordAvailable = false
                    cockpit.discordConnected = false
                }
            }
        }
    }

    Process {
        id: discordAction
        onRunningChanged: {
            if (!running)
                actionRefresh.restart()
        }
    }

    Process {
        id: utilityAction
    }

    Timer {
        interval: 100
        running: true
        repeat: true
        onTriggered: {
            if (!statusProcess.running)
                statusProcess.running = true
        }
    }

    Timer {
        id: actionRefresh
        interval: 180
        onTriggered: {
            if (!statusProcess.running)
                statusProcess.running = true
        }
    }

    PanelWindow {
        id: cockpitWindow

        screen: cockpit.cockpitScreen
        visible: !!cockpit.cockpitScreen
        color: "transparent"
        implicitHeight: cockpit.surfaceHeight
        exclusiveZone: 0
        focusable: false
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell:hdmi-cockpit"

        anchors {
            top: true
            left: true
            right: true
        }

        mask: Region { item: surfaceRoot }

        Item {
            id: surfaceRoot
            anchors.horizontalCenter: parent.horizontalCenter
            width: cockpit.surfaceWidth
            height: cockpit.surfaceHeight + cockpit.topBleed
            y: -cockpit.topBleed

            SdfCanvas {
                id: cockpitSurface
                anchors.fill: parent
                fillColor: cockpit.theme.surface
                smoothness: 0

                SdfRoundRect {
                    x: cockpitSurface.width / 2
                    y: cockpitSurface.height / 2
                    halfWidth: cockpitSurface.width / 2
                    halfHeight: cockpitSurface.height / 2
                    cornerRadius: 20
                    cornerSmoothing: 0.78
                }
            }

            ClippingRectangle {
                anchors.fill: parent
                color: "transparent"
                radius: 20

                RowLayout {
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        bottom: parent.bottom
                        leftMargin: 26
                        rightMargin: 26
                        topMargin: cockpit.topBleed + 8
                        bottomMargin: 8
                    }
                    spacing: 18

                    Item {
                        Layout.preferredWidth: 48
                        Layout.preferredHeight: 48

                        ClippingRectangle {
                            anchors.fill: parent
                            color: "transparent"
                            radius: width / 2

                            Image {
                                anchors.fill: parent
                                source: cockpit.discordAvatarUrl
                                visible: cockpit.discordAvatarUrl.length > 0
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                smooth: true
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: cockpit.discordAvatarUrl.length === 0
                                text: "󰙯"
                                color: cockpit.theme.textDisabled
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 25
                            }
                        }

                        Rectangle {
                            anchors {
                                right: parent.right
                                bottom: parent.bottom
                            }
                            width: 9
                            height: 9
                            radius: width / 2
                            color: cockpit.discordConnected
                                ? "#43b581"
                                : (cockpit.discordAvailable
                                    ? cockpit.theme.textMuted : "#ef5d62")
                            border.width: 2
                            border.color: cockpit.theme.surface
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                utilityAction.command = [
                                    "hyprctl", "dispatch", "focuswindow",
                                    "class:^(discord)$"
                                ]
                                utilityAction.running = true
                            }
                        }
                    }

                    Item {
                        Layout.preferredWidth: 136
                        Layout.fillHeight: true

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            spacing: 2

                            Text {
                                width: parent.width
                                text: cockpit.discordDisplayName
                                color: cockpit.theme.textPrimary
                                elide: Text.ElideRight
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 13
                                font.weight: Font.Bold
                            }

                            Text {
                                width: parent.width
                                text: cockpit.discordUsername.length > 0
                                    ? "@" + cockpit.discordUsername
                                    : "DISCORD PROFILE"
                                color: cockpit.theme.textMuted
                                elide: Text.ElideRight
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 9
                                font.weight: Font.DemiBold
                            }

                            Text {
                                width: parent.width
                                text: cockpit.discordAvailable
                                    ? (cockpit.discordConnected
                                        ? "VOICE CONNECTED"
                                        : "VOICE IDLE")
                                    : "BRIDGE OFFLINE"
                                color: cockpit.discordConnected
                                    ? "#43b581"
                                    : (cockpit.discordAvailable
                                        ? cockpit.theme.textDisabled : "#ef5d62")
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 8
                                font.weight: Font.Bold
                            }
                        }
                    }

                    Item {
                        Layout.preferredWidth: 220
                        Layout.fillHeight: true

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            spacing: 3
                            visible: cockpit.discordConnected

                            Text {
                                width: parent.width
                                text: cockpit.discordGuildName
                                color: cockpit.theme.textPrimary
                                elide: Text.ElideRight
                                horizontalAlignment: Text.AlignHCenter
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 10
                                font.weight: Font.Bold
                            }

                            Text {
                                width: parent.width
                                text: "󰎤  "
                                    + cockpit.discordChannelName
                                    + "  ·  "
                                    + cockpit.discordParticipantCount
                                    + (cockpit.discordParticipantCount === 1
                                        ? " PERSON" : " PEOPLE")
                                color: cockpit.theme.textMuted
                                elide: Text.ElideRight
                                horizontalAlignment: Text.AlignHCenter
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 9
                                font.weight: Font.DemiBold
                            }

                            Text {
                                width: parent.width
                                text: "VC  "
                                    + cockpit.formatDuration(
                                        cockpit.voiceElapsedMs)
                                color: cockpit.theme.textPrimary
                                horizontalAlignment: Text.AlignHCenter
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 12
                                font.weight: Font.Bold
                            }
                        }
                    }

                    Item {
                        Layout.preferredWidth: 96
                        Layout.fillHeight: true

                        Row {
                            anchors.centerIn: parent
                            spacing: 8

                            Item {
                                width: 40
                                height: 40

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 3

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: cockpit.effectiveMicMuted
                                            ? "󰍭" : "󰍬"
                                        color: cockpit.effectiveMicMuted
                                            ? "#ef5d62"
                                            : (micMouse.containsMouse
                                                ? cockpit.theme.textBright : cockpit.theme.textPrimary)
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 19

                                    }

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: cockpit.effectiveMicMuted
                                            ? "MUTED" : "MIC"
                                        color: cockpit.effectiveMicMuted
                                            ? "#ef5d62" : cockpit.theme.textMuted
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 7
                                        font.weight: Font.Bold
                                    }
                                }

                                MouseArea {
                                    id: micMouse
                                    anchors.fill: parent
                                    enabled: cockpit.discordAvailable
                                    hoverEnabled: true
                                    cursorShape: enabled
                                        ? Qt.PointingHandCursor
                                        : Qt.ArrowCursor
                                    onClicked: {
                                        cockpit.discordMuted = !cockpit.discordMuted
                                        cockpit.discordCommand("toggle-mute")
                                    }
                                }
                            }

                            Item {
                                width: 40
                                height: 40

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 3

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: cockpit.discordDeafened
                                            ? "󰟎" : "󰋋"
                                        color: cockpit.discordDeafened
                                            ? "#ef5d62"
                                            : (deafMouse.containsMouse
                                                ? cockpit.theme.textBright : cockpit.theme.textSecondary)
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 18

                                    }

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: cockpit.discordDeafened
                                            ? "DEAF" : "AUDIO"
                                        color: cockpit.discordDeafened
                                            ? "#ef5d62" : cockpit.theme.textMuted
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 7
                                        font.weight: Font.Bold
                                    }
                                }

                                MouseArea {
                                    id: deafMouse
                                    anchors.fill: parent
                                    enabled: cockpit.discordAvailable
                                    hoverEnabled: true
                                    cursorShape: enabled
                                        ? Qt.PointingHandCursor
                                        : Qt.ArrowCursor
                                    onClicked: {
                                        const nextDeafened =
                                            !cockpit.discordDeafened
                                        cockpit.discordDeafened = nextDeafened
                                        cockpit.discordMuted = nextDeafened
                                        cockpit.discordCommand("toggle-deaf")
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Column {
                            anchors {
                                right: parent.right
                                verticalCenter: parent.verticalCenter
                            }
                            spacing: 4

                            Text {
                                anchors.right: parent.right
                                text: Qt.formatDateTime(clock.date, "HH:mm")
                                color: cockpit.theme.textPrimary
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 16
                                font.weight: Font.Bold
                            }

                            Item {
                                anchors.right: parent.right
                                width: 78
                                height: 18

                                Row {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 7

                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 6
                                        height: 6
                                        radius: 3
                                        color: cockpit.recordingActive
                                            ? "#ef5d62" : cockpit.theme.surfaceActive
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: cockpit.recordingLabel()
                                        color: cockpit.recordingActive
                                            ? "#ef5d62"
                                            : (recordMouse.containsMouse
                                                ? cockpit.theme.textSecondary : cockpit.theme.textDisabled)
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 7
                                        font.weight: Font.Bold
                                    }
                                }

                                MouseArea {
                                    id: recordMouse
                                    anchors.fill: parent
                                    enabled: cockpit.recordingActionsEnabled
                                    hoverEnabled: true
                                    cursorShape: enabled
                                        ? Qt.PointingHandCursor
                                        : Qt.ArrowCursor
                                    onClicked: {
                                        utilityAction.command = [
                                            "/home/mika/.local/bin/boltsnap",
                                            "recording", "show-controls"
                                        ]
                                        utilityAction.running = true
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

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Scope {
    id: osd

    required property var theme
    property var osdScreen
    property int currentVolume: 0
    property bool currentMuted: false
    property bool shown: false
    property bool windowVisible: false
    property bool suppressed: false
    property int level: 0
    property string kind: "volume"
    property bool stateMuted: false
    property bool brightnessAvailable: false

    function run(command) {
        if (action.running)
            action.running = false
        action.command = command
        action.running = true
    }

    function reveal(type, value, muted) {
        osd.kind = type
        osd.level = Math.max(0, Math.min(100, value))
        osd.stateMuted = muted
        osd.windowVisible = true
        osd.shown = true
        closeWindowTimer.stop()
        hideTimer.restart()
    }

    function volumeUp() {
        const next = Math.min(100, osd.currentVolume + 5)
        osd.run(["wpctl", "set-volume", "-l", "1", "@DEFAULT_AUDIO_SINK@", "5%+"])
        osd.reveal("volume", next, false)
    }

    function volumeDown() {
        const next = Math.max(0, osd.currentVolume - 5)
        osd.run(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "5%-"])
        osd.reveal("volume", next, osd.currentMuted)
    }

    function volumeMute() {
        const nextMuted = !osd.currentMuted
        osd.run(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"])
        osd.reveal("volume", osd.currentVolume, nextMuted)
    }

    function micMute() {
        osd.run(["wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", "toggle"])
        osd.reveal("microphone", 100, false)
    }

    function brightnessUp() {
        osd.run(["brightnessctl", "--class=backlight", "-e4", "-n2", "set", "5%+"])
        osd.level = Math.min(100, osd.level + 5)
        osd.reveal("brightness", osd.level, false)
        brightnessReadDelay.restart()
    }

    function brightnessDown() {
        osd.run(["brightnessctl", "--class=backlight", "-e4", "-n2", "set", "5%-"])
        osd.level = Math.max(0, osd.level - 5)
        osd.reveal("brightness", osd.level, false)
        brightnessReadDelay.restart()
    }

    function icon() {
        if (osd.kind === "brightness")
            return "󰃠"
        if (osd.kind === "microphone")
            return "󰍭"
        if (osd.stateMuted || osd.level === 0)
            return "󰖁"
        if (osd.level > 55)
            return "󰕾"
        return "󰖀"
    }

    IpcHandler {
        target: "osd"

        function volumeUp(): void { osd.volumeUp() }
        function volumeDown(): void { osd.volumeDown() }
        function volumeMute(): void { osd.volumeMute() }
        function micMute(): void { osd.micMute() }
        function brightnessUp(): void { osd.brightnessUp() }
        function brightnessDown(): void { osd.brightnessDown() }
    }

    Process {
        id: action
    }

    Process {
        id: brightnessRead
        command: ["brightnessctl", "--class=backlight", "-m"]

        stdout: StdioCollector {
            onStreamFinished: {
                const match = text.match(/,(\\d+)%/)
                osd.brightnessAvailable = match !== null
                if (match)
                    osd.level = Number(match[1])
            }
        }
    }

    Component.onCompleted: brightnessRead.running = true

    Timer {
        id: brightnessReadDelay
        interval: 80
        onTriggered: {
            if (!brightnessRead.running)
                brightnessRead.running = true
        }
    }

    Timer {
        id: hideTimer
        interval: 1450
        onTriggered: {
            osd.shown = false
            closeWindowTimer.restart()
        }
    }

    Timer {
        id: closeWindowTimer
        interval: 220
        onTriggered: {
            if (!osd.shown)
                osd.windowVisible = false
        }
    }

    PanelWindow {
        id: osdWindow

        screen: osd.osdScreen
        visible: osd.osdScreen !== null
            && !osd.suppressed
            && osd.windowVisible
        color: "transparent"
        implicitWidth: 270
        implicitHeight: 68
        exclusiveZone: 0

        anchors {
            bottom: true
        }

        margins {
            bottom: 32
        }

        Rectangle {
            id: card

            anchors.fill: parent
            radius: 19
            color: osd.theme.surfaceGlass
            border.width: 1
            border.color: osd.theme.outlineSubtle
            opacity: osd.shown ? 1 : 0
            scale: osd.shown ? 1 : 0.92

            transform: Translate {
                y: osd.shown ? 0 : 16

                Behavior on y {
                    NumberAnimation {
                        duration: 280
                        easing.type: Easing.OutCubic
                    }
                }
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: osd.shown ? 220 : 170
                    easing.type: Easing.OutCubic
                }
            }

            Behavior on scale {
                NumberAnimation {
                    duration: 260
                    easing.type: Easing.OutBack
                    easing.overshoot: 0.7
                }
            }

            RowLayout {
                anchors {
                    fill: parent
                    leftMargin: 18
                    rightMargin: 18
                }
                spacing: 13

                Text {
                    Layout.preferredWidth: 24
                    text: osd.icon()
                    color: osd.theme.textBright
                    horizontalAlignment: Text.AlignHCenter
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 17
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 7
                    radius: height / 2
                    color: osd.theme.surfaceActive
                    clip: true

                    Rectangle {
                        width: osd.kind === "brightness" && !osd.brightnessAvailable
                            ? 0 : parent.width * osd.level / 100
                        height: parent.height
                        radius: parent.radius
                        color: osd.stateMuted ? osd.theme.textMuted : osd.theme.textBright

                        Behavior on width {
                            NumberAnimation {
                                duration: 160
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                }

                Text {
                    Layout.preferredWidth: 34
                    text: osd.kind === "brightness" && !osd.brightnessAvailable
                        ? "N/A" : (osd.stateMuted ? "OFF" : osd.level + "%")
                    color: osd.theme.textBright
                    horizontalAlignment: Text.AlignRight
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }
            }
        }
    }
}

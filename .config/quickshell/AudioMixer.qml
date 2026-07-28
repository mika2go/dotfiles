pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Wayland

Scope {
    id: mixer

    required property var theme
    property var mixerScreen
    property bool shown: false
    property bool windowVisible: false
    property bool suppressed: false
    property real offsetScale: shown ? 0 : 1
    property var sinks: []
    property var sources: []
    property var streams: []
    property var rememberedStreamVolumes: ({})
    property bool streamVolumeStateLoaded: false

    readonly property real morphProgress: 1 - offsetScale
    // Content stays hidden behind the 54 px sidebar and only reveals during
    // the final travel segment, once its left inset has cleared the icons.
    readonly property real contentReveal: Math.max(0, Math.min(1,
        (morphProgress - 0.94) / 0.06))
    readonly property real surfaceWidth: 430
    readonly property real surfaceHeight: Math.min(650,
        Math.max(520, (mixerScreen?.height ?? 690) - 44))
    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource
    readonly property string fontFamily: "JetBrainsMono Nerd Font"

    Behavior on offsetScale {
        NumberAnimation {
            duration: 500
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.38, 1.21, 0.22, 1.0, 1.0, 1.0]
        }
    }

    function open(): void {
        closeTimer.stop()
        mixer.windowVisible = true
        mixer.shown = true
        focusTimer.restart()
    }

    function close(): void {
        if (!mixer.windowVisible)
            return
        mixer.shown = false
        closeTimer.restart()
    }

    function toggle(): void {
        mixer.shown ? mixer.close() : mixer.open()
    }

    function refreshNodes(): void {
        const nextSinks = []
        const nextSources = []
        const nextStreams = []

        for (const node of Pipewire.nodes.values) {
            if (!node?.audio)
                continue

            if (node.isStream) {
                // Stream properties are only populated after binding. The
                // direction flag is available immediately and reliably keeps
                // recording/capture nodes out of the playback mixer.
                if (node.isSink)
                    nextStreams.push(node)
            } else if (node.isSink) {
                nextSinks.push(node)
            } else if ((node.properties["media.class"] || "") === "Audio/Source") {
                nextSources.push(node)
            }
        }

        const byName = (a, b) => mixer.nodeName(a).localeCompare(mixer.nodeName(b))
        mixer.sinks = nextSinks.sort(byName)
        mixer.sources = nextSources.sort(byName)
        mixer.streams = nextStreams.sort(byName)
    }

    function nodeName(node): string {
        if (!node)
            return "NICHT VERFÜGBAR"
        return node.properties["application.name"]
            || node.description || node.nickname || node.name || "UNBEKANNT"
    }

    function shortName(node): string {
        const name = nodeName(node)
            .replace("Analog Stereo", "ANALOG")
            .replace("Digital Stereo (HDMI)", "HDMI")
        return name.toUpperCase()
    }

    function appIcon(node): string {
        if (!node)
            return ""
        const icon = node.properties["application.icon-name"] || ""
        return icon.length > 0 && Quickshell.hasThemeIcon(icon)
            ? Quickshell.iconPath(icon) : ""
    }

    function streamKey(node): string {
        if (!node)
            return ""
        return String(node.properties["application.id"]
            || node.properties["application.name"]
            || node.name || node.description || "")
            .trim().toLowerCase()
    }

    function rememberStreamVolume(node, value): void {
        const key = streamKey(node)
        if (key.length === 0)
            return
        const next = Object.assign({}, mixer.rememberedStreamVolumes)
        next[key] = Math.max(0, Math.min(1, value))
        mixer.rememberedStreamVolumes = next
        streamVolumeSave.restart()
    }

    function restoreStreamVolume(node): void {
        if (!mixer.streamVolumeStateLoaded || !node?.ready || !node.audio)
            return
        const key = streamKey(node)
        if (key.length === 0)
            return
        const desired = mixer.rememberedStreamVolumes[key]
        if (desired === undefined || desired === null)
            return
        if (Math.abs(node.audio.volume - Number(desired)) > 0.002)
            node.audio.volume = Number(desired)
    }

    function restoreAllStreamVolumes(): void {
        for (const stream of mixer.streams)
            mixer.restoreStreamVolume(stream)
    }

    function setVolume(node, value): void {
        if (!node?.ready || !node.audio)
            return
        const clamped = Math.max(0, Math.min(1, value))
        if (node.isStream)
            mixer.rememberStreamVolume(node, clamped)
        node.audio.volume = clamped
        if (value > 0)
            node.audio.muted = false
    }

    function toggleMuted(node): void {
        if (node?.ready && node.audio)
            node.audio.muted = !node.audio.muted
    }

    function cycleNode(nodes, current, output): void {
        if (nodes.length === 0)
            return
        const currentIndex = nodes.findIndex(node => node === current)
        const next = nodes[(currentIndex + 1) % nodes.length]
        if (output)
            Pipewire.preferredDefaultAudioSink = next
        else
            Pipewire.preferredDefaultAudioSource = next
    }

    IpcHandler {
        target: "mixer"

        function toggle(): void { mixer.toggle() }
        function open(): void { mixer.open() }
        function close(): void { mixer.close() }
    }

    Connections {
        target: Pipewire.nodes
        function onValuesChanged(): void { mixer.refreshNodes() }
    }

    PwObjectTracker {
        objects: [mixer.sink, mixer.source,
            ...mixer.sinks, ...mixer.sources, ...mixer.streams]
            .filter(node => node)
    }

    FileView {
        id: streamVolumeState
        path: "/home/mika/.local/state/quickshell-audio-mixer-volumes.json"
        preload: true
        printErrors: false
        atomicWrites: true

        onLoaded: {
            try {
                const raw = streamVolumeState.text().trim()
                mixer.rememberedStreamVolumes = raw.length > 0
                    ? JSON.parse(raw) : ({})
            } catch (error) {
                mixer.rememberedStreamVolumes = ({})
            }
            mixer.streamVolumeStateLoaded = true
            Qt.callLater(mixer.restoreAllStreamVolumes)
        }

        onLoadFailed: mixer.streamVolumeStateLoaded = true
    }

    Timer {
        id: streamVolumeSave
        interval: 180
        onTriggered: {
            if (mixer.streamVolumeStateLoaded)
                streamVolumeState.setText(JSON.stringify(
                    mixer.rememberedStreamVolumes))
        }
    }

    Component.onCompleted: refreshNodes()

    Timer {
        id: closeTimer
        interval: 515
        onTriggered: {
            if (!mixer.shown)
                mixer.windowVisible = false
        }
    }

    Timer {
        id: focusTimer
        interval: 40
        onTriggered: keyFocus.forceActiveFocus()
    }

    component LevelSlider: Item {
        id: slider

        required property PwNode node
        property bool showPeak: true
        readonly property real value: node?.audio?.volume ?? 0
        readonly property bool muted: node?.audio?.muted ?? false
        readonly property real peak: peakMonitor.peak

        implicitHeight: 28

        PwNodePeakMonitor {
            id: peakMonitor
            node: slider.node
            enabled: slider.showPeak && mixer.shown
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 4
            radius: 2
            color: mixer.theme.surfaceHover

            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, slider.peak))
                height: parent.height
                radius: parent.radius
                color: mixer.theme.surfaceActive

                Behavior on width {
                    NumberAnimation { duration: 70; easing.type: Easing.OutQuad }
                }
            }

            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, slider.value))
                height: parent.height
                radius: parent.radius
                color: slider.muted ? mixer.theme.textDisabled : mixer.theme.textPrimary

                Behavior on width {
                    enabled: !sliderMouse.pressed
                    NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
                }
            }

            Rectangle {
                x: Math.max(0, Math.min(parent.width - width,
                    parent.width * slider.value - width / 2))
                anchors.verticalCenter: parent.verticalCenter
                width: 12
                height: 12
                radius: 6
                color: slider.muted ? mixer.theme.textMuted : mixer.theme.textPrimary
                border.width: 2
                border.color: mixer.theme.surface
            }
        }

        MouseArea {
            id: sliderMouse
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor

            function apply(mouseX): void {
                mixer.setVolume(slider.node,
                    Math.max(0, Math.min(1, mouseX / width)))
            }

            onPressed: mouse => apply(mouse.x)
            onPositionChanged: mouse => {
                if (pressed)
                    apply(mouse.x)
            }
            onWheel: wheel => {
                const delta = wheel.angleDelta.y > 0 ? 0.04 : -0.04
                mixer.setVolume(slider.node, slider.value + delta)
            }
        }
    }

    component IconButton: Rectangle {
        id: button

        property string icon: ""
        property bool active: false
        signal clicked()

        implicitWidth: 34
        implicitHeight: 34
        radius: width / 2
        color: active || buttonMouse.containsMouse ? mixer.theme.textPrimary : mixer.theme.surfaceRaised
        border.width: 0

        Behavior on color { ColorAnimation { duration: 120 } }

        Text {
            anchors.centerIn: parent
            text: button.icon
            color: button.active || buttonMouse.containsMouse ? mixer.theme.surface : mixer.theme.textPrimary
            font.family: mixer.fontFamily
            font.pixelSize: 15
        }

        MouseArea {
            id: buttonMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: button.clicked()
        }
    }

    PanelWindow {
        id: mixerWindow

        screen: mixer.mixerScreen
        visible: mixer.mixerScreen !== null
            && !mixer.suppressed && mixer.windowVisible
        color: "transparent"
        implicitWidth: mixer.surfaceWidth + 5
        exclusiveZone: 0
        focusable: mixer.shown
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell:mono-audio-mixer"

        anchors { top: true; bottom: true; left: true }
        // The layer-shell work area starts after the 54 px sidebar. Pull the
        // wrapper back onto the physical monitor edge so content and MonoSDF
        // surface share exactly the same coordinate space.
        margins { left: -54 }
        mask: Region { item: mixerCard }

        Item {
            id: mixerCard
            width: mixer.surfaceWidth
            height: mixer.surfaceHeight
            anchors.verticalCenter: parent.verticalCenter
            x: (-width - 5) * mixer.offsetScale
            opacity: mixer.contentReveal
            visible: mixer.offsetScale < 1
            clip: true

            ColumnLayout {
                anchors {
                    fill: parent
                    leftMargin: 76
                    rightMargin: 20
                    topMargin: 22
                    bottomMargin: 20
                }
                spacing: 14

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            text: "AUDIO MIXER"
                            color: mixer.theme.textPrimary
                            font.family: mixer.fontFamily
                            font.pixelSize: 17
                            font.weight: Font.Bold
                            font.letterSpacing: 0.8
                        }

                        Text {
                            text: mixer.streams.length + (mixer.streams.length === 1
                                ? " AKTIVER KANAL" : " AKTIVE KANÄLE")
                            color: mixer.theme.textMuted
                            font.family: mixer.fontFamily
                            font.pixelSize: 8
                            font.weight: Font.DemiBold
                            font.letterSpacing: 0.5
                        }
                    }

                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 118
                    color: "transparent"

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 15
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Rectangle {
                                Layout.preferredWidth: 38
                                Layout.preferredHeight: 38
                                radius: width / 2
                                color: mixer.theme.textPrimary

                                Text {
                                    anchors.centerIn: parent
                                    text: mixer.sink?.audio?.muted ? "󰖁" : "󰕾"
                                    color: mixer.theme.surface
                                    font.family: mixer.fontFamily
                                    font.pixelSize: 18
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    text: "MASTER"
                                    color: mixer.theme.textPrimary
                                    font.family: mixer.fontFamily
                                    font.pixelSize: 10
                                    font.weight: Font.Bold
                                    font.letterSpacing: 0.7
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: mixer.shortName(mixer.sink)
                                    color: mixer.theme.textMuted
                                    elide: Text.ElideRight
                                    font.family: mixer.fontFamily
                                    font.pixelSize: 8
                                }
                            }

                            Text {
                                text: mixer.sink?.audio?.muted ? "OFF"
                                    : Math.round((mixer.sink?.audio?.volume ?? 0) * 100) + "%"
                                color: mixer.theme.textPrimary
                                font.family: mixer.fontFamily
                                font.pixelSize: 10
                                font.weight: Font.Bold
                            }

                            IconButton {
                                icon: mixer.sink?.audio?.muted ? "󰖁" : "󰕾"
                                active: mixer.sink?.audio?.muted ?? false
                                onClicked: mixer.toggleMuted(mixer.sink)
                            }
                        }

                        LevelSlider {
                            Layout.fillWidth: true
                            node: mixer.sink
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 24
                            color: "transparent"

                            Rectangle {
                                anchors { left: parent.left; right: parent.right; top: parent.top }
                                height: 1
                                color: outputMouse.containsMouse ? mixer.theme.surfaceActive : mixer.theme.surfaceHover

                                Behavior on color { ColorAnimation { duration: 120 } }
                            }

                            Text {
                                anchors {
                                    left: parent.left
                                    leftMargin: 9
                                    right: outputChevron.left
                                    rightMargin: 8
                                    verticalCenter: parent.verticalCenter
                                }
                                text: "OUTPUT  /  " + mixer.shortName(mixer.sink)
                                color: mixer.theme.textSecondary
                                elide: Text.ElideRight
                                font.family: mixer.fontFamily
                                font.pixelSize: 7
                                font.weight: Font.DemiBold
                            }

                            Text {
                                id: outputChevron
                                anchors { right: parent.right; rightMargin: 9; verticalCenter: parent.verticalCenter }
                                text: "󰁅"
                                color: mixer.theme.textMuted
                                font.family: mixer.fontFamily
                                font.pixelSize: 11
                            }

                            MouseArea {
                                id: outputMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: mixer.cycleNode(mixer.sinks, mixer.sink, true)
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        text: "APPS"
                        color: mixer.theme.textSecondary
                        font.family: mixer.fontFamily
                        font.pixelSize: 9
                        font.weight: Font.Bold
                        font.letterSpacing: 0.8
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: "LIVE"
                        color: mixer.theme.textDisabled
                        font.family: mixer.fontFamily
                        font.pixelSize: 7
                        font.weight: Font.Bold
                    }

                    Rectangle {
                        Layout.preferredWidth: 5
                        Layout.preferredHeight: 5
                        radius: 3
                        color: mixer.streams.length > 0 ? mixer.theme.textPrimary : mixer.theme.outlineSubtle
                    }
                }

                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: width
                    contentHeight: streamColumn.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: streamColumn
                        width: parent.width
                        spacing: 0

                        Text {
                            visible: mixer.streams.length === 0
                            width: parent.width
                            height: 72
                            text: "KEINE APP SPIELT GERADE AUDIO"
                            color: mixer.theme.textDisabled
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            font.family: mixer.fontFamily
                            font.pixelSize: 8
                            font.weight: Font.DemiBold
                        }

                        Repeater {
                            model: mixer.streams

                            Rectangle {
                                id: streamCard
                                required property PwNode modelData
                                width: streamColumn.width
                                height: 72
                                color: "transparent"

                                Rectangle {
                                    anchors {
                                        left: parent.left
                                        right: parent.right
                                        bottom: parent.bottom
                                    }
                                    height: 1
                                    color: streamMouse.hovered ? mixer.theme.surfaceActive : mixer.theme.surfaceHover

                                    Behavior on color { ColorAnimation { duration: 120 } }
                                }

                                RowLayout {
                                    anchors {
                                        fill: parent
                                        leftMargin: 12
                                        rightMargin: 11
                                        topMargin: 10
                                        bottomMargin: 10
                                    }
                                    spacing: 10

                                    Rectangle {
                                        Layout.preferredWidth: 32
                                        Layout.preferredHeight: 32
                                        radius: width / 2
                                        color: mixer.theme.surfaceHover

                                        Image {
                                            anchors.centerIn: parent
                                            width: 18
                                            height: 18
                                            source: mixer.appIcon(streamCard.modelData)
                                            visible: source.toString().length > 0
                                            fillMode: Image.PreserveAspectFit
                                            smooth: true
                                        }

                                        Text {
                                            anchors.centerIn: parent
                                            visible: mixer.appIcon(streamCard.modelData).length === 0
                                            text: "󰎆"
                                            color: mixer.theme.textPrimary
                                            font.family: mixer.fontFamily
                                            font.pixelSize: 15
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1

                                        RowLayout {
                                            Layout.fillWidth: true

                                            Text {
                                                Layout.fillWidth: true
                                                text: mixer.shortName(streamCard.modelData)
                                                color: mixer.theme.textPrimary
                                                elide: Text.ElideRight
                                                font.family: mixer.fontFamily
                                                font.pixelSize: 9
                                                font.weight: Font.Bold
                                            }

                                            Text {
                                                text: streamCard.modelData.audio?.muted ? "OFF"
                                                    : Math.round((streamCard.modelData.audio?.volume ?? 0) * 100) + "%"
                                                color: mixer.theme.textMuted
                                                font.family: mixer.fontFamily
                                                font.pixelSize: 8
                                                font.weight: Font.DemiBold
                                            }
                                        }

                                        LevelSlider {
                                            Layout.fillWidth: true
                                            node: streamCard.modelData
                                        }
                                    }

                                    IconButton {
                                        Layout.preferredWidth: 30
                                        Layout.preferredHeight: 30
                                        icon: streamCard.modelData.audio?.muted ? "󰖁" : "󰕾"
                                        active: streamCard.modelData.audio?.muted ?? false
                                        onClicked: mixer.toggleMuted(streamCard.modelData)
                                    }
                                }

                                HoverHandler { id: streamMouse }

                                Connections {
                                    target: streamCard.modelData

                                    function onReadyChanged(): void {
                                        if (streamCard.modelData.ready)
                                            Qt.callLater(() => mixer.restoreStreamVolume(
                                                streamCard.modelData))
                                    }
                                }

                                Connections {
                                    target: streamCard.modelData.audio

                                    function onVolumesChanged(): void {
                                        Qt.callLater(() => mixer.restoreStreamVolume(
                                            streamCard.modelData))
                                    }
                                }

                                Component.onCompleted: Qt.callLater(
                                    () => mixer.restoreStreamVolume(streamCard.modelData))
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 76
                    color: "transparent"

                    Rectangle {
                        anchors { left: parent.left; right: parent.right; top: parent.top }
                        height: 1
                        color: mixer.theme.surfaceHover
                    }

                    RowLayout {
                        anchors { fill: parent; margins: 11 }
                        spacing: 10

                        IconButton {
                            icon: mixer.source?.audio?.muted ? "󰍭" : "󰍬"
                            active: mixer.source?.audio?.muted ?? false
                            onClicked: mixer.toggleMuted(mixer.source)
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            RowLayout {
                                Layout.fillWidth: true

                                Text {
                                    Layout.fillWidth: true
                                    text: "INPUT  /  " + mixer.shortName(mixer.source)
                                    color: mixer.theme.textSecondary
                                    elide: Text.ElideRight
                                    font.family: mixer.fontFamily
                                    font.pixelSize: 8
                                    font.weight: Font.Bold
                                }

                                Text {
                                    text: mixer.source?.audio?.muted ? "OFF"
                                        : Math.round((mixer.source?.audio?.volume ?? 0) * 100) + "%"
                                    color: mixer.theme.textMuted
                                    font.family: mixer.fontFamily
                                    font.pixelSize: 8
                                }
                            }

                            LevelSlider {
                                Layout.fillWidth: true
                                node: mixer.source
                            }
                        }

                        IconButton {
                            icon: "󰁅"
                            onClicked: mixer.cycleNode(mixer.sources, mixer.source, false)
                        }
                    }
                }
            }

            Item {
                id: keyFocus
                anchors.fill: parent
                focus: mixer.shown
                Keys.onEscapePressed: mixer.close()
            }
        }
    }
}

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Wayland
import Quickshell.Widgets

Scope {
    id: island

    required property var theme
    property var islandScreen
    property real horizontalCenterOffset: 0
    // shell.qml guarantees that this is either Spotify or null.
    property var player: null
    property bool networkOnline: false
    property int volume: 0
    property int microphone: 0
    property bool muted: false
    property int cpuUsage: 0
    property int gpuUsage: 0
    property int memoryUsage: 0
    property int trayCount: 0
    property bool expanded: false
    property bool windowVisible: false
    property bool suppressed: false
    // Caelestia's dashboard wrapper animates one offset from fully visible
    // (0) to one complete panel height above the monitor (1).
    property real offsetScale: expanded ? 0 : 1
    readonly property real morphProgress: 1 - offsetScale
    readonly property real surfaceWidth: 780
    readonly property real compactSurfaceHeight: 330
    readonly property real todoSurfaceHeight: 318
    readonly property real mediaSurfaceHeight: 370
    readonly property real mediaEqualizerSurfaceHeight: 575
    readonly property real surfaceWidthScale: 1
    property real surfaceHeight: activeTab === "dashboard" ? 450
        : activeTab === "todo" ? todoSurfaceHeight
        : activeTab === "media" ? (equalizerExpanded
            ? mediaEqualizerSurfaceHeight : mediaSurfaceHeight)
        : compactSurfaceHeight
    readonly property real surfaceHeightScale: surfaceHeight / compactSurfaceHeight
    readonly property real contentReveal: Math.max(0, Math.min(1,
        1 - offsetScale))
    property string activeTab: "dashboard"
    property bool todoFileLoading: false
    property bool codexLimitAvailable: false
    property int codexRemaining: 0
    property string codexResetText: "wird geladen"
    property real spotifyPosition: 0
    property real visualizerPhase: 0
    property real discRotation: 0
    property var lyricLines: []
    property string lyricRequestKey: ""
    property int requestedLyricIndex: -1
    property int displayedLyricIndex: -1
    property string pendingLyricText: ""
    property string displayedLyricText: ""
    property real lyricOpacity: 1
    readonly property real lyricLeadSeconds: 0.06
    property bool equalizerExpanded: false
    property bool equalizerEnabled: true
    property bool equalizerReady: false
    property bool equalizerStateLoaded: false
    property string equalizerStatus: "WIRD GELADEN"
    property var equalizerGains: [0, 0, 0, 0, 0, 0]
    readonly property var equalizerPresets: [
        { name: "FLAT", gains: [0, 0, 0, 0, 0, 0] },
        { name: "BASS", gains: [6, 4, 2, 0, -1, -2] },
        { name: "VOCAL", gains: [-2, -1, 1, 4, 3, 1] },
        { name: "BRIGHT", gains: [-2, -1, 0, 2.5, 4, 6] },
        { name: "NIGHT", gains: [3, 2, 0, -2, -4, -6] }
    ]
    property int calendarMonth: clock.date.getMonth()
    property int calendarYear: clock.date.getFullYear()
    property bool weatherReady: false
    property int weatherTemperature: 0
    property int weatherCode: 0
    property bool weatherIsDay: true
    property string weatherSummary: "WIRD GELADEN"
    property string weatherLocation: "WEATHER"
    property string uptimeText: "wird geladen"
    readonly property string userName: Quickshell.env("USER") || "mika"
    readonly property string hostName: Quickshell.env("HOSTNAME") || "MIKAROOT"

    signal toggleTrayRequested()

    readonly property var monthNames: [
        "Januar", "Februar", "März", "April", "Mai", "Juni",
        "Juli", "August", "September", "Oktober", "November", "Dezember"
    ]
    readonly property var weekDays: ["MO", "DI", "MI", "DO", "FR", "SA", "SO"]

    Behavior on offsetScale {
        NumberAnimation {
            duration: 500
            easing.type: Easing.BezierSpline
            // Tokens.anim.expressiveDefaultSpatial from Caelestia.
            easing.bezierCurve: [0.38, 1.21, 0.22, 1.0, 1.0, 1.0]
        }
    }

    Behavior on surfaceHeight {
        NumberAnimation {
            duration: 420
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.38, 1.21, 0.22, 1.0, 1.0, 1.0]
        }
    }

    function toggle() {
        island.expanded ? island.close() : island.open()
    }

    function open() {
        closeWindowTimer.stop()
        island.windowVisible = true
        island.expanded = true
        if (!weatherProcess.running)
            weatherProcess.running = true
        if (!uptimeProcess.running)
            uptimeProcess.running = true
    }

    function close() {
        island.expanded = false
        closeWindowTimer.restart()
    }

    function selectTab(tab) {
        if (island.activeTab === tab)
            return
        island.activeTab = tab
        if (tab === "todo" && !codexLimitProcess.running)
            codexLimitProcess.running = true
    }

    function loadTodoTasks(contents) {
        island.todoFileLoading = true
        todoModel.clear()

        const lines = String(contents || "").split(/\r?\n/)
        for (let index = 0; index < lines.length && todoModel.count < 5; ++index) {
            const title = lines[index].trim()
            if (title.length > 0)
                todoModel.append({ "title": title })
        }

        island.todoFileLoading = false
    }

    function addTodoTask() {
        const title = todoInput.text.trim()
        if (title.length === 0 || todoModel.count >= 5)
            return

        todoModel.append({ "title": title })
        todoInput.clear()
        todoSaveTimer.restart()
    }

    function completeTodoTask(index) {
        if (index < 0 || index >= todoModel.count)
            return

        todoModel.remove(index)
        todoSaveTimer.restart()
    }

    function saveTodoTasks() {
        const tasks = []
        for (let index = 0; index < todoModel.count; ++index)
            tasks.push(todoModel.get(index).title)
        todoFile.setText(tasks.join("\n"))
    }

    function codexLimitColor() {
        if (island.codexRemaining >= 60)
            return "#63d17b"
        if (island.codexRemaining >= 20)
            return "#eea64a"
        return "#ef5d62"
    }

    function formatTime(seconds) {
        const safe = Math.max(0, Math.floor(Number(seconds) || 0))
        const minutes = Math.floor(safe / 60)
        const remainder = safe % 60
        return minutes + ":" + (remainder < 10 ? "0" : "") + remainder
    }

    function spotifyAction(command) {
        if (!island.player)
            return
        if (command === "previous" && island.player.canGoPrevious)
            island.player.previous()
        else if (command === "play-pause" && island.player.canTogglePlaying)
            island.player.togglePlaying()
        else if (command === "next" && island.player.canGoNext)
            island.player.next()
        else if (command === "shuffle" && island.player.shuffleSupported)
            island.player.shuffle = !island.player.shuffle
        else if (command === "repeat" && island.player.loopSupported) {
            if (island.player.loopState === MprisLoopState.None)
                island.player.loopState = MprisLoopState.Track
            else if (island.player.loopState === MprisLoopState.Track)
                island.player.loopState = MprisLoopState.Playlist
            else
                island.player.loopState = MprisLoopState.None
        }
    }

    function seekSpotify(ratio) {
        if (!island.player || !island.player.positionSupported
                || !island.player.lengthSupported || island.player.length <= 0)
            return
        island.player.position = Math.max(0, Math.min(1, ratio)) * island.player.length
        island.spotifyPosition = island.player.position
    }

    function currentTrackKey() {
        if (!island.player)
            return ""
        return [
            island.player.trackTitle || "",
            island.player.trackArtist || "",
            island.player.trackAlbum || "",
            Math.round(Number(island.player.length || 0))
        ].join("\u001f")
    }

    function scheduleLyrics() {
        const key = island.currentTrackKey()
        island.lyricRequestKey = key
        island.lyricLines = []
        island.requestedLyricIndex = -1
        island.displayedLyricIndex = -1
        island.pendingLyricText = ""
        island.displayedLyricText = ""
        lyricSwap.stop()
        island.lyricOpacity = 1
        lyricsDebounce.stop()
        if (key.length > 0)
            lyricsDebounce.restart()
    }

    function requestLyrics() {
        if (!island.player || island.lyricRequestKey.length === 0)
            return
        if (lyricsProcess.running)
            lyricsProcess.running = false
        lyricsProcess.command = [
            "/usr/bin/python3",
            "/home/mika/.config/quickshell/scripts/lyrics.py",
            island.lyricRequestKey,
            island.player.trackTitle || "",
            island.player.trackArtist || "",
            island.player.trackAlbum || "",
            String(Number(island.player.length || 0))
        ]
        lyricsProcess.running = true
    }

    function lyricIndexAt(position) {
        let result = -1
        for (let index = 0; index < island.lyricLines.length; ++index) {
            if (Number(island.lyricLines[index].time) > position)
                break
            result = index
        }
        return result
    }

    function updateDisplayedLyric() {
        const index = island.lyricIndexAt(
            island.spotifyPosition + island.lyricLeadSeconds)
        if (index === island.requestedLyricIndex)
            return
        island.requestedLyricIndex = index
        island.pendingLyricText = index >= 0
            ? String(island.lyricLines[index].text || "") : ""
        lyricSwap.stop()
        island.displayedLyricIndex = island.requestedLyricIndex
        island.displayedLyricText = island.pendingLyricText
        island.lyricOpacity = 0.55
        lyricSwap.restart()
    }

    function lyricAtOffset(offset) {
        const center = island.displayedLyricIndex >= 0
            ? island.displayedLyricIndex : 0
        const index = center + offset
        if (index < 0 || index >= island.lyricLines.length)
            return ""
        return String(island.lyricLines[index].text || "")
    }

    function seekLyricAtOffset(offset) {
        if (!island.player || !island.player.positionSupported)
            return
        const center = island.displayedLyricIndex >= 0
            ? island.displayedLyricIndex : 0
        const index = center + offset
        if (index < 0 || index >= island.lyricLines.length)
            return
        island.player.position = Number(island.lyricLines[index].time || 0)
        island.spotifyPosition = island.player.position
    }

    function changeMonth(delta) {
        let month = island.calendarMonth + delta
        let year = island.calendarYear
        if (month < 0) {
            month = 11
            year--
        } else if (month > 11) {
            month = 0
            year++
        }
        island.calendarMonth = month
        island.calendarYear = year
    }

    function calendarCells() {
        const first = new Date(island.calendarYear, island.calendarMonth, 1)
        const start = (first.getDay() + 6) % 7
        const count = new Date(island.calendarYear, island.calendarMonth + 1, 0).getDate()
        const cells = []
        for (let index = 0; index < 42; index++) {
            const day = index - start + 1
            cells.push(day > 0 && day <= count ? day : 0)
        }
        return cells
    }

    function equalizerValue(index) {
        return Math.max(-12, Math.min(12,
            Number(island.equalizerGains[index] || 0)))
    }

    function setEqualizerGain(index, value) {
        const gains = island.equalizerGains.slice()
        gains[index] = Math.round(Math.max(-12, Math.min(12, value)) * 2) / 2
        island.equalizerGains = gains
        island.equalizerStatus = "WIRD ANGEWENDET"
        equalizerApplyTimer.restart()
        equalizerSaveTimer.restart()
    }

    function setEqualizerEnabled(enabled) {
        island.equalizerEnabled = enabled
        island.equalizerStatus = "WIRD ANGEWENDET"
        equalizerApplyTimer.restart()
        equalizerSaveTimer.restart()
    }

    function resetEqualizer() {
        island.equalizerGains = [0, 0, 0, 0, 0, 0]
        island.equalizerStatus = "WIRD ANGEWENDET"
        equalizerApplyTimer.restart()
        equalizerSaveTimer.restart()
    }

    function equalizerPresetMatches(gains) {
        if (!gains || gains.length !== island.equalizerGains.length)
            return false
        for (let index = 0; index < gains.length; ++index) {
            if (Math.abs(Number(gains[index])
                    - island.equalizerValue(index)) > 0.01)
                return false
        }
        return true
    }

    function currentEqualizerPreset() {
        for (let index = 0; index < island.equalizerPresets.length; ++index) {
            const preset = island.equalizerPresets[index]
            if (island.equalizerPresetMatches(preset.gains))
                return preset.name
        }
        return "CUSTOM"
    }

    function applyEqualizerPreset(gains) {
        island.equalizerGains = gains.slice()
        island.equalizerEnabled = true
        island.equalizerStatus = "WIRD ANGEWENDET"
        equalizerApplyTimer.restart()
        equalizerSaveTimer.restart()
    }

    function applyEqualizer() {
        if (!island.equalizerStateLoaded)
            return
        if (equalizerProcess.running) {
            equalizerApplyTimer.restart()
            return
        }
        const gains = island.equalizerGains.map(value => String(
            Math.max(-12, Math.min(12, Number(value) || 0))))
        equalizerProcess.command = [
            "/usr/bin/python3",
            "/home/mika/.config/quickshell/scripts/equalizer-control.py",
            "apply",
            island.equalizerEnabled ? "1" : "0"
        ].concat(gains)
        equalizerProcess.running = true
    }

    IpcHandler {
        target: "island"

        function toggle(): void { island.toggle() }
        function open(): void { island.open() }
        function close(): void { island.close() }
        function dashboard(): void {
            island.selectTab("dashboard")
            island.open()
        }
        function todo(): void {
            island.selectTab("todo")
            island.open()
        }
        function media(): void {
            island.selectTab("media")
            island.open()
        }
        function equalizer(): void {
            island.selectTab("media")
            island.equalizerExpanded = !island.equalizerExpanded
            if (island.equalizerExpanded)
                equalizerApplyTimer.restart()
            island.open()
        }
        function status(): string {
            return JSON.stringify({
                open: island.expanded,
                tab: island.activeTab,
                equalizerExpanded: island.equalizerExpanded,
                equalizerEnabled: island.equalizerEnabled,
                equalizerReady: island.equalizerReady,
                equalizerGains: island.equalizerGains,
                lyricLines: island.lyricLines.length,
                lyricIndex: island.displayedLyricIndex,
                lyric: island.displayedLyricText,
                geometry: {
                    tabCenter: tabRow.x + tabRow.width / 2,
                    contentCenter: contentRoot.width / 2,
                    playCenter: mediaTransportRow.mapToItem(mediaPage,
                        mediaTransportRow.width / 2, 0).x,
                    mediaCenter: mediaPage.width / 2,
                    playEqualizerOffset: mediaTransportRow.mapToItem(mediaPage,
                        mediaTransportRow.width / 2, 0).x - mediaPage.width / 2,
                    equalizerTextCenter: equalizerDisclosureTitle.mapToItem(mediaPage,
                        equalizerDisclosureTitle.width / 2, 0).x,
                    playEqualizerTextOffset: mediaTransportRow.mapToItem(mediaPage,
                        mediaTransportRow.width / 2, 0).x
                        - equalizerDisclosureTitle.mapToItem(mediaPage,
                            equalizerDisclosureTitle.width / 2, 0).x,
                    progressCenter: mediaProgressRow.mapToItem(mediaPage,
                        mediaProgressRow.width / 2, 0).x,
                    progressEqualizerOffset: mediaProgressRow.mapToItem(mediaPage,
                        mediaProgressRow.width / 2, 0).x - mediaPage.width / 2,
                    discCenter: radialCover.mapToItem(mediaPage,
                        radialCover.width / 2, 0).x,
                    playBottom: mediaTransportRow.mapToItem(mediaPage, 0,
                        mediaTransportRow.height).y,
                    equalizerTop: equalizerDisclosure.y,
                    equalizerGap: equalizerDisclosure.y
                        - mediaTransportRow.mapToItem(mediaPage, 0,
                            mediaTransportRow.height).y
                }
            })
        }
    }

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    ListModel {
        id: todoModel
    }

    FileView {
        id: todoFile
        path: Quickshell.env("HOME") + "/.local/share/quickshell/island-todo.txt"
        preload: true
        watchChanges: true
        atomicWrites: true

        onLoaded: {
            island.loadTodoTasks(todoFile.text())
        }

        onFileChanged: {
            if (!todoInput.activeFocus)
                todoFile.reload()
        }
    }

    FileView {
        id: equalizerStateFile
        path: Quickshell.env("HOME")
            + "/.local/state/dynamic-island-equalizer.json"
        preload: true
        atomicWrites: true
        printErrors: false

        onLoaded: {
            try {
                const state = JSON.parse(equalizerStateFile.text())
                island.equalizerEnabled = state.enabled !== false
                if (Array.isArray(state.gains) && state.gains.length === 6)
                    island.equalizerGains = state.gains.map(value =>
                        Math.max(-12, Math.min(12, Number(value) || 0)))
            } catch (error) {
                island.equalizerGains = [0, 0, 0, 0, 0, 0]
            }
            island.equalizerStateLoaded = true
            equalizerApplyTimer.restart()
        }

        onLoadFailed: {
            island.equalizerStateLoaded = true
            equalizerSaveTimer.restart()
            equalizerApplyTimer.restart()
        }
    }

    Process {
        id: weatherProcess
        command: [
            "/usr/bin/python3",
            "/home/mika/.config/quickshell/scripts/weather.py"
        ]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const weather = JSON.parse(text)
                    island.weatherTemperature = weather.temperature
                    island.weatherCode = weather.code
                    island.weatherIsDay = weather.isDay
                    island.weatherSummary = weather.summary
                    island.weatherLocation = weather.location || "WEATHER"
                    island.weatherReady = weather.ok !== false
                } catch (error) {
                    island.weatherSummary = "KEINE VERBINDUNG"
                }
            }
        }
    }

    Process {
        id: uptimeProcess
        command: ["uptime", "-p"]

        stdout: StdioCollector {
            onStreamFinished: {
                const value = text.trim().replace(/^up\\s+/, "")
                island.uptimeText = value.length > 0 ? value : "unbekannt"
            }
        }
    }

    Process {
        id: codexLimitProcess
        command: [
            "/usr/bin/python3",
            "/home/mika/.config/quickshell/scripts/codex-limit.py"
        ]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const status = JSON.parse(text)
                    island.codexLimitAvailable = Boolean(status.available)
                    island.codexRemaining = Number(status.remaining || 0)
                    island.codexResetText = status.resetText || "unbekannt"
                } catch (error) {
                    island.codexLimitAvailable = false
                    island.codexResetText = "keine Daten"
                }
            }
        }
    }

    Process {
        id: lyricsProcess

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text)
                    if (result.key !== island.lyricRequestKey)
                        return
                    island.lyricLines = result.available
                        && Array.isArray(result.lines) ? result.lines : []
                    island.requestedLyricIndex = -2
                    island.updateDisplayedLyric()
                } catch (error) {
                    island.lyricLines = []
                    island.pendingLyricText = ""
                    island.displayedLyricText = ""
                }
            }
        }
    }

    Process {
        id: equalizerProcess

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text)
                    island.equalizerReady = Boolean(result.ok)
                    island.equalizerStatus = result.ok
                        ? (island.equalizerEnabled ? "AKTIV" : "BYPASS")
                        : "NICHT VERFÜGBAR"
                } catch (error) {
                    island.equalizerReady = false
                    island.equalizerStatus = "NICHT VERFÜGBAR"
                }
            }
        }
    }

    Connections {
        target: island.player
        ignoreUnknownSignals: true

        function onTrackTitleChanged() { island.scheduleLyrics() }
        function onTrackArtistChanged() { island.scheduleLyrics() }
        function onTrackAlbumChanged() { island.scheduleLyrics() }
        function onLengthChanged() { island.scheduleLyrics() }
    }

    onPlayerChanged: scheduleLyrics()

    Timer {
        id: todoSaveTimer
        interval: 180
        onTriggered: island.saveTodoTasks()
    }

    Timer {
        id: equalizerApplyTimer
        interval: 120
        onTriggered: island.applyEqualizer()
    }

    Timer {
        id: equalizerSaveTimer
        interval: 240
        onTriggered: {
            if (island.equalizerStateLoaded)
                equalizerStateFile.setText(JSON.stringify({
                    enabled: island.equalizerEnabled,
                    gains: island.equalizerGains
                }))
        }
    }

    Timer {
        interval: 60000
        running: island.expanded && island.activeTab === "todo"
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!codexLimitProcess.running)
            codexLimitProcess.running = true
    }

    Timer {
        interval: 900000
        running: island.expanded
        repeat: true
        onTriggered: if (!weatherProcess.running) weatherProcess.running = true
    }

    Timer {
        interval: 60000
        running: island.expanded
        repeat: true
        onTriggered: if (!uptimeProcess.running) uptimeProcess.running = true
    }

    Timer {
        id: positionTimer
        interval: 100
        running: island.player !== null
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            island.spotifyPosition = island.player
                ? Number(island.player.position || 0) : 0
            island.updateDisplayedLyric()
        }
    }

    Timer {
        id: lyricsDebounce
        interval: 180
        onTriggered: island.requestLyrics()
    }

    NumberAnimation {
        id: lyricSwap
        target: island
        property: "lyricOpacity"
        to: 1
        duration: 120
        easing.type: Easing.OutSine
    }

    Timer {
        interval: 90
        running: island.contentReveal > 0.98 && island.activeTab === "media"
            && island.player && island.player.isPlaying
        repeat: true
        onTriggered: island.visualizerPhase += 0.42
    }

    FrameAnimation {
        running: island.contentReveal > 0.001 && island.activeTab === "media"
            && island.player && island.player.isPlaying
        onTriggered: island.discRotation = (island.discRotation
            + frameTime * 4.0) % 360
    }

    component EqualizerBand: Item {
        id: equalizerBand

        required property int bandIndex
        required property string bandLabel
        readonly property real gain: island.equalizerValue(bandIndex)

        implicitWidth: 82
        implicitHeight: 142

        Text {
            anchors {
                top: parent.top
                horizontalCenter: parent.horizontalCenter
            }
            text: (equalizerBand.gain > 0 ? "+" : "")
                + equalizerBand.gain.toFixed(1) + " dB"
            color: island.equalizerEnabled
                ? island.theme.textSecondary : island.theme.textDisabled
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 8
            font.weight: Font.DemiBold
        }

        Item {
            id: equalizerTrack
            anchors {
                top: parent.top
                topMargin: 22
                bottom: parent.bottom
                bottomMargin: 24
                horizontalCenter: parent.horizontalCenter
            }
            width: 48

            readonly property real handleY: 6
                + ((12 - equalizerBand.gain) / 24) * (height - 12)

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 2
                height: parent.height
                radius: 1
                color: island.theme.surfaceHover
            }

            Repeater {
                model: 5

                Rectangle {
                    required property int index
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: index * (equalizerTrack.height - 1) / 4
                    width: index === 2 ? 10 : 6
                    height: 1
                    color: index === 2
                        ? island.theme.outlineSubtle : island.theme.surfaceHover
                }
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: Math.min(parent.height / 2, equalizerTrack.handleY)
                width: 3
                height: Math.max(2, Math.abs(equalizerTrack.handleY
                    - parent.height / 2))
                radius: 1.5
                color: island.equalizerEnabled
                    ? island.theme.textPrimary : island.theme.textDisabled
            }

            Rectangle {
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    verticalCenter: parent.verticalCenter
                }
                width: 10
                height: 2
                radius: 1
                color: island.theme.outlineSubtle
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: equalizerTrack.handleY - height / 2
                width: 14
                height: 14
                radius: 7
                color: island.equalizerEnabled
                    ? island.theme.textPrimary : island.theme.textMuted
                border.width: 2
                border.color: island.theme.surface

                Behavior on y {
                    enabled: !equalizerMouse.pressed
                    NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
                }
            }

            MouseArea {
                id: equalizerMouse
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor

                function apply(mouseY) {
                    const ratio = Math.max(0, Math.min(1,
                        (mouseY - 6) / Math.max(1, height - 12)))
                    island.setEqualizerGain(equalizerBand.bandIndex,
                        12 - ratio * 24)
                }

                onPressed: mouse => apply(mouse.y)
                onPositionChanged: mouse => {
                    if (pressed)
                        apply(mouse.y)
                }
                onWheel: wheel => island.setEqualizerGain(
                    equalizerBand.bandIndex,
                    equalizerBand.gain + (wheel.angleDelta.y > 0 ? 0.5 : -0.5))
            }
        }

        Text {
            anchors {
                bottom: parent.bottom
                horizontalCenter: parent.horizontalCenter
            }
            text: equalizerBand.bandLabel
            color: island.theme.textMuted
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 8
            font.weight: Font.Bold
            font.letterSpacing: 0.6
        }
    }

    Timer {
        id: closeWindowTimer
        interval: 515
        onTriggered: {
            if (!island.expanded)
                island.windowVisible = false
        }
    }

    PanelWindow {
        id: islandWindow

        screen: island.islandScreen
        visible: island.islandScreen !== null
            && !island.suppressed
        color: "transparent"
        implicitWidth: island.surfaceWidth + 40
            + Math.abs(island.horizontalCenterOffset) * 2
        // Fixed maximum window geometry; only the Island content and its SDF
        // surface morph vertically between dashboard and the expanded media EQ.
        implicitHeight: 650
        exclusiveZone: 0
        focusable: island.contentReveal > 0.2
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell:dynamic-island"

        anchors { top: true }

        mask: Region { item: islandCard }

        Item {
            id: islandCard
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: island.horizontalCenterOffset
            width: island.surfaceWidth
            height: island.surfaceHeight + 34
            y: -34 + (-island.surfaceHeight - 5) * island.offsetScale
            opacity: 1 - island.offsetScale
            visible: island.windowVisible && island.offsetScale < 1

            ClippingRectangle {
                anchors.fill: parent
                color: "transparent"
                radius: 32

                    Item {
                        id: contentRoot
                        anchors {
                            fill: parent
                            topMargin: 36
                            leftMargin: 16
                            rightMargin: 16
                            bottomMargin: 14
                        }

                    Item {
                        anchors.fill: parent
                        focus: island.expanded
                        Keys.onEscapePressed: island.close()
                    }

                    Item {
                        id: tabRow
                        anchors {
                            top: parent.top
                            horizontalCenter: parent.horizontalCenter
                        }
                        width: 390
                        height: 34

                        Repeater {
                            id: tabRepeater
                            model: [
                                { key: "dashboard", icon: "󰕮", label: "Dashboard" },
                                { key: "todo", icon: "󰄬", label: "ToDo" },
                                { key: "media", icon: "󰎈", label: "Media" }
                            ]

                            delegate: Item {
                                id: tabButton
                                required property var modelData
                                required property int index
                                readonly property real indicatorX: x + tabContentRow.x
                                // The row contains both the icon and label. Flooring avoids
                                // rasterising one extra pixel at its fractional right edge.
                                readonly property real indicatorWidth:
                                    Math.floor(tabContentRow.implicitWidth)
                                x: index * 130
                                width: 130
                                height: 34

                                Row {
                                    id: tabContentRow
                                    anchors {
                                        horizontalCenter: parent.horizontalCenter
                                        horizontalCenterOffset: -(tabIcon.implicitWidth
                                            + tabContentRow.spacing) / 2
                                        verticalCenter: parent.verticalCenter
                                        verticalCenterOffset: -3
                                    }
                                    spacing: 7

                                    Text {
                                        id: tabIcon
                                        text: tabButton.modelData.icon
                                        color: island.activeTab === tabButton.modelData.key
                                            ? island.theme.textPrimary : island.theme.textMuted
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 11

                                        Behavior on color {
                                            ColorAnimation { duration: 140 }
                                        }
                                    }

                                    Text {
                                        text: tabButton.modelData.label
                                        color: island.activeTab === tabButton.modelData.key
                                            ? island.theme.textPrimary : island.theme.textMuted
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold

                                        Behavior on color {
                                            ColorAnimation { duration: 140 }
                                        }
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: island.selectTab(tabButton.modelData.key)
                                }
                            }
                        }

                        Rectangle {
                            id: tabIndicator
                            readonly property int activeIndex:
                                island.activeTab === "dashboard" ? 0
                                : island.activeTab === "todo" ? 1 : 2
                            readonly property var activeButton:
                                tabRepeater.itemAt(activeIndex)
                            x: activeButton ? activeButton.indicatorX
                                + (activeIndex === 0 ? 0 : 2) : 0
                            // Font metrics contain invisible space below the glyphs.
                            // Place the indicator against the visible icon/label baseline.
                            y: 21
                            width: activeButton ? activeButton.indicatorWidth : 0
                            height: 2
                            radius: 1
                            color: island.theme.textPrimary

                            Behavior on x {
                                NumberAnimation {
                                    duration: 220
                                    easing.type: Easing.InOutCubic
                                }
                            }

                            Behavior on width {
                                NumberAnimation {
                                    duration: 220
                                    easing.type: Easing.InOutCubic
                                }
                            }
                        }
                    }

                    Rectangle {
                        anchors {
                            top: tabRow.bottom
                            left: parent.left
                            right: parent.right
                        }
                        height: 1
                        color: island.theme.surfaceHover
                    }

                    Item {
                        id: pageArea
                        clip: true
                        anchors {
                            top: tabRow.bottom
                            topMargin: 6
                            left: parent.left
                            leftMargin: 4
                            right: parent.right
                            rightMargin: 4
                            bottom: parent.bottom
                            bottomMargin: 2
                        }

                        Item {
                            id: dashboardPage
                            anchors.fill: parent
                            opacity: island.activeTab === "dashboard" ? 1 : 0
                            visible: opacity > 0.001
                            transform: Translate {
                                id: dashboardShift
                                x: island.activeTab === "dashboard" ? 0 : -18

                                Behavior on x {
                                    NumberAnimation { duration: 170; easing.type: Easing.InOutSine }
                                }
                            }

                            Behavior on opacity {
                                NumberAnimation { duration: 170; easing.type: Easing.InOutSine }
                            }

                            Item {
                                id: caelestiaDash
                                anchors.fill: parent

                                readonly property real gap: 6
                                readonly property real mediaWidth: 260
                                readonly property real leftWidth: width - mediaWidth - gap
                                readonly property real resourceWidth: 118
                                readonly property real topHeight: 92
                                readonly property real bottomY: topHeight + gap
                                readonly property real bottomHeight: height - bottomY

                                Rectangle {
                                    id: dashWeather
                                    x: dashUser.width + caelestiaDash.gap
                                    y: 0
                                    width: caelestiaDash.leftWidth - x
                                    height: caelestiaDash.topHeight
                                    color: "transparent"

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 10
                                        spacing: 9

                                        PixelWeatherIcon {
                                            Layout.preferredWidth: 48
                                            Layout.preferredHeight: 44
                                            code: island.weatherCode
                                            isDay: island.weatherIsDay
                                            color: island.theme.textPrimary
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 0

                                            Text {
                                                text: island.weatherReady
                                                    ? island.weatherTemperature + "°" : "--°"
                                                color: island.theme.textPrimary
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 25
                                                font.weight: Font.Bold
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                text: island.weatherSummary
                                                color: island.theme.textMuted
                                                elide: Text.ElideRight
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 8
                                                font.weight: Font.DemiBold
                                            }

                                            Text {
                                                text: island.weatherLocation
                                                color: island.theme.outlineSubtle
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 7
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    id: dashUser
                                    x: 0
                                    y: 0
                                    width: 244
                                    height: caelestiaDash.topHeight
                                    color: "transparent"

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 10
                                        spacing: 10

                                        ClippingRectangle {
                                            Layout.preferredWidth: 68
                                            Layout.preferredHeight: 68
                                            radius: 20
                                            color: island.theme.surfaceDeep

                                            Image {
                                                anchors.fill: parent
                                                source: "assets/profile-avatar.jpg"
                                                fillMode: Image.PreserveAspectCrop
                                                smooth: true
                                                mipmap: true
                                                asynchronous: true
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 3

                                            Text {
                                                Layout.fillWidth: true
                                                text: island.userName.toUpperCase()
                                                color: island.theme.textPrimary
                                                elide: Text.ElideRight
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 17
                                                font.weight: Font.Bold
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                text: island.hostName + "  /  HYPRLAND"
                                                color: island.theme.textMuted
                                                elide: Text.ElideRight
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 9
                                            }

                                            Item { Layout.preferredHeight: 4 }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 8

                                                Text {
                                                    text: island.networkOnline ? "󰖩 ONLINE" : "󰖪 OFFLINE"
                                                    color: island.theme.textSecondary
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 8
                                                }

                                                Text {
                                                    text: (island.muted ? "󰝟 " : "󰕾 ")
                                                        + island.volume + "%"
                                                    color: island.theme.textSecondary
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 8
                                                }

                                                Text {
                                                    Layout.fillWidth: true
                                                    horizontalAlignment: Text.AlignRight
                                                    text: "󰅐 " + island.uptimeText
                                                    color: island.theme.textDisabled
                                                    elide: Text.ElideRight
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 8
                                                }
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    id: dashTime
                                    x: 0
                                    y: caelestiaDash.bottomY
                                    width: 70
                                    height: caelestiaDash.bottomHeight
                                    color: "transparent"

                                    Column {
                                        anchors.centerIn: parent
                                        spacing: -8

                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: Qt.formatTime(clock.date, "HH")
                                            color: island.theme.textPrimary
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 30
                                            font.weight: Font.Bold
                                        }

                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: "•••"
                                            color: island.theme.textDisabled
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 18
                                        }

                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: Qt.formatTime(clock.date, "mm")
                                            color: island.theme.textPrimary
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 30
                                            font.weight: Font.Bold
                                        }

                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: Qt.formatDate(clock.date, "ddd").toUpperCase()
                                            color: island.theme.textDisabled
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 9
                                        }
                                    }
                                }

                                Rectangle {
                                    id: dashCalendar
                                    x: dashTime.width + caelestiaDash.gap
                                    y: caelestiaDash.bottomY + 6
                                    width: caelestiaDash.leftWidth - x
                                        - caelestiaDash.resourceWidth - caelestiaDash.gap
                                    height: caelestiaDash.bottomHeight - 12
                                    color: "transparent"

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        spacing: 3

                                        RowLayout {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 21

                                            Text {
                                                text: "‹"
                                                color: previousMonthMouse.containsMouse
                                                    ? island.theme.textBright : island.theme.textMuted
                                                font.pixelSize: 18

                                                MouseArea {
                                                    id: previousMonthMouse
                                                    anchors {
                                                        fill: parent
                                                        margins: -5
                                                    }
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: island.changeMonth(-1)
                                                }
                                            }

                                            Item { Layout.fillWidth: true }

                                            Text {
                                                text: island.monthNames[island.calendarMonth].toUpperCase()
                                                    + "  " + island.calendarYear
                                                color: island.theme.textPrimary
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 10
                                                font.weight: Font.Bold
                                            }

                                            Item { Layout.fillWidth: true }

                                            Text {
                                                text: "›"
                                                color: nextMonthMouse.containsMouse
                                                    ? island.theme.textBright : island.theme.textMuted
                                                font.pixelSize: 18

                                                MouseArea {
                                                    id: nextMonthMouse
                                                    anchors {
                                                        fill: parent
                                                        margins: -5
                                                    }
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: island.changeMonth(1)
                                                }
                                            }
                                        }

                                        GridLayout {
                                            Layout.fillWidth: true
                                            columns: 7
                                            columnSpacing: 1
                                            rowSpacing: 0

                                            Repeater {
                                                model: island.weekDays

                                                Text {
                                                    id: dashWeekDay
                                                    required property var modelData
                                                    Layout.fillWidth: true
                                                    horizontalAlignment: Text.AlignHCenter
                                                    text: dashWeekDay.modelData
                                                    color: island.theme.textDisabled
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 7
                                                    font.weight: Font.Bold
                                                }
                                            }
                                        }

                                        GridLayout {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            columns: 7
                                            columnSpacing: 1
                                            rowSpacing: 1

                                            Repeater {
                                                model: island.calendarCells()

                                                Rectangle {
                                                    id: dashDay
                                                    required property var modelData
                                                    readonly property bool today: dashDay.modelData > 0
                                                        && dashDay.modelData === clock.date.getDate()
                                                        && island.calendarMonth === clock.date.getMonth()
                                                        && island.calendarYear === clock.date.getFullYear()
                                                    Layout.fillWidth: true
                                                    Layout.fillHeight: true
                                                    radius: 6
                                                    color: dashDay.today ? island.theme.textPrimary : "transparent"

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: dashDay.modelData > 0
                                                            ? dashDay.modelData : ""
                                                        color: dashDay.today ? island.theme.surface
                                                            : (dashDay.modelData > 0
                                                                ? island.theme.textMuted : "transparent")
                                                        font.family: "JetBrainsMono Nerd Font"
                                                        font.pixelSize: 11
                                                        font.weight: dashDay.today
                                                            ? Font.Bold : Font.DemiBold
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    id: dashResources
                                    x: caelestiaDash.leftWidth - caelestiaDash.resourceWidth
                                    y: caelestiaDash.bottomY
                                    width: caelestiaDash.resourceWidth
                                    height: caelestiaDash.bottomHeight
                                    color: "transparent"

                                    Column {
                                        anchors {
                                            top: parent.top
                                            left: parent.left
                                            right: parent.right
                                            margins: 6
                                        }
                                        spacing: 5

                                        Text {
                                            width: parent.width
                                            horizontalAlignment: Text.AlignHCenter
                                            text: "SYSTEM"
                                            color: island.theme.textDisabled
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 9
                                            font.weight: Font.Bold
                                            font.letterSpacing: 0.7
                                        }

                                        Repeater {
                                            model: [
                                                { icon: "󰍛", label: "CPU", value: island.cpuUsage },
                                                { icon: "󰢮", label: "GPU", value: island.gpuUsage },
                                                { icon: "󰘚", label: "RAM", value: island.memoryUsage }
                                            ]

                                            Rectangle {
                                                id: dashResource
                                                required property var modelData
                                                width: parent.width
                                                height: 44
                                                color: "transparent"

                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.margins: 5
                                                    spacing: 6

                                                    Text {
                                                        text: dashResource.modelData.icon
                                                        color: island.theme.textPrimary
                                                        font.family: "JetBrainsMono Nerd Font"
                                                        font.pixelSize: 18
                                                    }

                                                    ColumnLayout {
                                                        Layout.fillWidth: true
                                                        spacing: 1

                                                        Text {
                                                            text: dashResource.modelData.label
                                                                + " " + dashResource.modelData.value + "%"
                                                            color: island.theme.textSecondary
                                                            font.family: "JetBrainsMono Nerd Font"
                                                            font.pixelSize: 10
                                                            font.weight: Font.Bold
                                                        }

                                                        Rectangle {
                                                            Layout.fillWidth: true
                                                            Layout.preferredHeight: 5
                                                            radius: 2
                                                            color: island.theme.surfaceActive

                                                            Rectangle {
                                                                width: parent.width * Math.max(0,
                                                                    Math.min(100,
                                                                        dashResource.modelData.value)) / 100
                                                                height: parent.height
                                                                radius: parent.radius
                                                                color: island.theme.textPrimary

                                                                Behavior on width {
                                                                    NumberAnimation { duration: 250 }
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    id: dashMedia
                                    x: caelestiaDash.leftWidth + caelestiaDash.gap
                                    y: 0
                                    width: caelestiaDash.mediaWidth
                                    height: parent.height
                                    color: "transparent"

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 10
                                        spacing: 4

                                        Item {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 126

                                            Item {
                                                id: dashRadialCover
                                                width: 118
                                                height: 118
                                                anchors.centerIn: parent

                                                Repeater {
                                                    model: 40

                                                    Item {
                                                        id: dashProgressTick
                                                        required property int index
                                                        anchors.fill: parent
                                                        rotation: dashProgressTick.index * 9

                                                        Rectangle {
                                                            anchors.horizontalCenter: parent.horizontalCenter
                                                            y: 0
                                                            width: 3
                                                            height: dashProgressTick.index / 40
                                                                <= (island.player
                                                                    && island.player.length > 0
                                                                    ? Math.min(1,
                                                                        island.spotifyPosition
                                                                            / island.player.length)
                                                                    : 0)
                                                                ? 9 : 5
                                                            radius: 1
                                                            color: height > 5
                                                                ? island.theme.textPrimary : island.theme.surfaceActive

                                                            Behavior on height {
                                                                NumberAnimation { duration: 180 }
                                                            }
                                                        }
                                                    }
                                                }

                                                ClippingRectangle {
                                                    width: 86
                                                    height: 86
                                                    radius: width / 2
                                                    anchors.centerIn: parent
                                                    color: island.theme.surface

                                                    Image {
                                                        anchors.fill: parent
                                                        visible: island.player
                                                            && (island.player.trackArtUrl
                                                                || "").length > 0
                                                        source: island.player
                                                            ? island.player.trackArtUrl : ""
                                                        fillMode: Image.PreserveAspectCrop
                                                        smooth: true
                                                        mipmap: true
                                                        asynchronous: true
                                                    }

                                                    Image {
                                                        anchors.fill: parent
                                                        visible: !island.player
                                                            || (island.player.trackArtUrl
                                                                || "").length === 0
                                                        source: "assets/album-placeholder.svg"
                                                        fillMode: Image.PreserveAspectCrop
                                                        smooth: true
                                                        mipmap: true
                                                    }
                                                }
                                            }
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            horizontalAlignment: Text.AlignHCenter
                                            text: island.player
                                                ? (island.player.trackTitle || "Unbekannter Titel")
                                                : "KEINE MEDIEN"
                                            color: island.theme.textPrimary
                                            elide: Text.ElideRight
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 12
                                            font.weight: Font.Bold
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            horizontalAlignment: Text.AlignHCenter
                                            text: island.player
                                                ? (island.player.trackArtist
                                                    || island.player.trackAlbum || "Spotify")
                                                : "Spotify nicht geöffnet"
                                            color: island.theme.textDisabled
                                            elide: Text.ElideRight
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 9
                                        }

                                        Item {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            Layout.minimumHeight: 52

                                            Text {
                                                anchors.centerIn: parent
                                                width: Math.max(0, parent.width - 12)
                                                visible: text.length > 0
                                                opacity: island.lyricOpacity
                                                text: island.displayedLyricText
                                                color: island.theme.textSecondary
                                                horizontalAlignment: Text.AlignHCenter
                                                verticalAlignment: Text.AlignVCenter
                                                wrapMode: Text.Wrap
                                                maximumLineCount: 3
                                                elide: Text.ElideRight
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 10
                                                font.weight: Font.Medium
                                                lineHeight: 1.2
                                            }
                                        }

                                        RowLayout {
                                            Layout.alignment: Qt.AlignHCenter
                                            spacing: 12

                                            Repeater {
                                                model: [
                                                    { icon: "󰒮", command: "previous", main: false },
                                                    { icon: island.player && island.player.isPlaying
                                                        ? "󰏤" : "󰐊",
                                                        command: "play-pause", main: true },
                                                    { icon: "󰒭", command: "next", main: false }
                                                ]

                                                Rectangle {
                                                    id: dashMediaButton
                                                    required property var modelData
                                                    Layout.preferredWidth:
                                                        dashMediaButton.modelData.main ? 44 : 34
                                                    Layout.preferredHeight:
                                                        dashMediaButton.modelData.main ? 44 : 34
                                                    radius: width / 2
                                                    color: dashMediaButton.modelData.main
                                                        ? island.theme.textPrimary
                                                        : (dashMediaMouse.containsMouse
                                                            ? island.theme.surfaceHover : "transparent")

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: dashMediaButton.modelData.icon
                                                        color: dashMediaButton.modelData.main
                                                            ? island.theme.surface : island.theme.textPrimary
                                                        font.family: "JetBrainsMono Nerd Font"
                                                        font.pixelSize:
                                                            dashMediaButton.modelData.main ? 17 : 12
                                                    }

                                                    MouseArea {
                                                        id: dashMediaMouse
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: island.spotifyAction(
                                                            dashMediaButton.modelData.command)
                                                    }
                                                }
                                            }
                                        }

                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: " /\\_/\\\n( •.• )"
                                            color: island.theme.textMuted
                                            horizontalAlignment: Text.AlignHCenter
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 10
                                            lineHeight: 0.8
                                        }
                                    }
                                }
                            }
                        }
                        Item {
                            id: todoPage
                            anchors.fill: parent
                            opacity: island.activeTab === "todo" ? 1 : 0
                            visible: opacity > 0.001
                            transform: Translate {
                                x: island.activeTab === "todo" ? 0
                                    : island.activeTab === "dashboard" ? 18 : -18

                                Behavior on x {
                                    NumberAnimation { duration: 170; easing.type: Easing.InOutSine }
                                }
                            }

                            Behavior on opacity {
                                NumberAnimation { duration: 170; easing.type: Easing.InOutSine }
                            }

                            RowLayout {
                                anchors.fill: parent
                                spacing: 18

                                Item {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    Layout.preferredWidth: 1

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 16
                                        spacing: 10

                                        RowLayout {
                                            Layout.fillWidth: true

                                            Text {
                                                text: "󰝖  TODO"
                                                color: island.theme.textPrimary
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 11
                                                font.weight: Font.Bold
                                            }

                                            Item { Layout.fillWidth: true }

                                            Text {
                                                text: todoModel.count + "/5"
                                                color: island.theme.outlineSubtle
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 8
                                                font.weight: Font.DemiBold
                                            }
                                        }

                                        Item {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true

                                            Column {
                                                anchors.fill: parent
                                                spacing: 4

                                                Item {
                                                    width: parent.width
                                                    height: 34

                                                    TextField {
                                                        id: todoInput
                                                        anchors {
                                                            left: parent.left
                                                            right: addTaskHitArea.left
                                                            verticalCenter: parent.verticalCenter
                                                        }
                                                        enabled: todoModel.count < 5
                                                        padding: 0
                                                        leftPadding: 0
                                                        rightPadding: 8
                                                        color: island.theme.textPrimary
                                                        placeholderText: todoModel.count < 5
                                                            ? "Add a task" : "Maximum of 5 tasks"
                                                        placeholderTextColor: island.theme.outlineSubtle
                                                        selectionColor: island.theme.textDisabled
                                                        selectedTextColor: island.theme.textBright
                                                        font.family: "JetBrainsMono Nerd Font"
                                                        font.pixelSize: 10
                                                        maximumLength: 120
                                                        background: null
                                                        onAccepted: island.addTodoTask()
                                                    }

                                                    Text {
                                                        anchors.centerIn: addTaskHitArea
                                                        text: "+"
                                                        color: todoModel.count < 5 && todoInput.text.trim().length > 0
                                                            ? island.theme.textPrimary
                                                            : island.theme.outlineSubtle
                                                        font.family: "JetBrainsMono Nerd Font"
                                                        font.pixelSize: 15

                                                        Behavior on color {
                                                            ColorAnimation { duration: 120 }
                                                        }
                                                    }

                                                    MouseArea {
                                                        id: addTaskHitArea
                                                        anchors {
                                                            right: parent.right
                                                            verticalCenter: parent.verticalCenter
                                                        }
                                                        width: 30
                                                        height: 30
                                                        enabled: todoModel.count < 5
                                                            && todoInput.text.trim().length > 0
                                                        hoverEnabled: true
                                                        cursorShape: enabled
                                                            ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                        onClicked: island.addTodoTask()
                                                    }

                                                    Rectangle {
                                                        anchors {
                                                            left: parent.left
                                                            right: parent.right
                                                            bottom: parent.bottom
                                                        }
                                                        height: 1
                                                        color: todoInput.activeFocus
                                                            ? island.theme.textPrimary
                                                            : island.theme.surfaceHover

                                                        Behavior on color {
                                                            ColorAnimation { duration: 140 }
                                                        }
                                                    }
                                                }

                                                Repeater {
                                                    model: todoModel

                                                    delegate: Item {
                                                        id: taskRow
                                                        required property int index
                                                        required property string title
                                                        width: parent.width
                                                        height: 28

                                                        Text {
                                                            anchors {
                                                                left: parent.left
                                                                right: completeTaskHitArea.left
                                                                rightMargin: 6
                                                                verticalCenter: parent.verticalCenter
                                                            }
                                                            text: taskRow.title
                                                            color: island.theme.textPrimary
                                                            elide: Text.ElideRight
                                                            font.family: "JetBrainsMono Nerd Font"
                                                            font.pixelSize: 10
                                                        }

                                                        Text {
                                                            anchors.centerIn: completeTaskHitArea
                                                            text: "×"
                                                            color: completeTaskHitArea.containsMouse
                                                                ? island.theme.textPrimary
                                                                : island.theme.textMuted
                                                            font.family: "JetBrainsMono Nerd Font"
                                                            font.pixelSize: 15

                                                            Behavior on color {
                                                                ColorAnimation { duration: 120 }
                                                            }
                                                        }

                                                        MouseArea {
                                                            id: completeTaskHitArea
                                                            anchors {
                                                                right: parent.right
                                                                verticalCenter: parent.verticalCenter
                                                            }
                                                            width: 30
                                                            height: 28
                                                            hoverEnabled: true
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: island.completeTodoTask(taskRow.index)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                Item {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    Layout.preferredWidth: 1

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 18
                                        spacing: 12

                                        RowLayout {
                                            Layout.fillWidth: true

                                            Text {
                                                text: "󰚩  CODEX LIMIT"
                                                color: island.theme.textPrimary
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 11
                                                font.weight: Font.Bold
                                            }

                                            Item { Layout.fillWidth: true }

                                            Rectangle {
                                                Layout.preferredWidth: 8
                                                Layout.preferredHeight: 8
                                                radius: 4
                                                color: island.codexLimitAvailable
                                                    ? island.codexLimitColor() : island.theme.outlineSubtle
                                            }
                                        }

                                        Item { Layout.fillHeight: true }

                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: island.codexLimitAvailable
                                                ? island.codexRemaining + "%" : "--%"
                                            color: island.codexLimitAvailable
                                                ? island.codexLimitColor() : island.theme.textDisabled
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 48
                                            font.weight: Font.Bold

                                            Behavior on color {
                                                ColorAnimation { duration: 220 }
                                            }
                                        }

                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: "VERFÜGBAR"
                                            color: island.theme.textDisabled
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 8
                                            font.weight: Font.DemiBold
                                            font.letterSpacing: 1.2
                                        }

                                        Item { Layout.preferredHeight: 5 }

                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 7
                                            radius: 4
                                            color: island.theme.surfaceHover

                                            Rectangle {
                                                width: parent.width * Math.max(0,
                                                    Math.min(100, island.codexRemaining)) / 100
                                                height: parent.height
                                                radius: parent.radius
                                                color: island.codexLimitAvailable
                                                    ? island.codexLimitColor() : island.theme.outlineSubtle

                                                Behavior on width {
                                                    NumberAnimation { duration: 350; easing.type: Easing.OutCubic }
                                                }

                                                Behavior on color {
                                                    ColorAnimation { duration: 220 }
                                                }
                                            }
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true

                                            Text {
                                                text: "0%"
                                                color: island.theme.outlineSubtle
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 7
                                            }

                                            Item { Layout.fillWidth: true }

                                            Text {
                                                text: "100%"
                                                color: island.theme.outlineSubtle
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 7
                                            }
                                        }

                                        Item { Layout.fillHeight: true }

                                        Item {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 54
                                            Layout.bottomMargin: 4

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors {
                                                    leftMargin: -6
                                                    rightMargin: 12
                                                    bottomMargin: 20
                                                }
                                                spacing: 10

                                                Text {
                                                    text: "󰅐"
                                                    color: island.codexLimitAvailable
                                                        ? island.codexLimitColor() : island.theme.outlineSubtle
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 16
                                                }

                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 1

                                                    Text {
                                                        text: "RESET"
                                                        color: island.theme.outlineSubtle
                                                        font.family: "JetBrainsMono Nerd Font"
                                                        font.pixelSize: 7
                                                        font.weight: Font.Bold
                                                    }

                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: island.codexResetText
                                                        color: island.theme.textSecondary
                                                        elide: Text.ElideRight
                                                        font.family: "JetBrainsMono Nerd Font"
                                                        font.pixelSize: 10
                                                        font.weight: Font.DemiBold
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Item {
                            id: mediaPage
                            anchors.fill: parent
                            opacity: island.activeTab === "media" ? 1 : 0
                            visible: opacity > 0.001
                            transform: Translate {
                                id: mediaShift
                                x: island.activeTab === "media" ? 0 : 18

                                Behavior on x {
                                    NumberAnimation { duration: 170; easing.type: Easing.InOutSine }
                                }
                            }

                            Behavior on opacity {
                                NumberAnimation { duration: 170; easing.type: Easing.InOutSine }
                            }

                            Item {
                                id: mediaBackdrop
                                anchors {
                                    top: parent.top
                                    left: parent.left
                                    right: parent.right
                                }
                                height: 344

                                Repeater {
                                    model: [
                                        { px: 0.03, py: 0.15, size: 58, radius: 18, angle: 18, alpha: 0.13, drift: 23 },
                                        { px: 0.18, py: 0.67, size: 34, radius: 17, angle: 0, alpha: 0.10, drift: -17 },
                                        { px: 0.42, py: 0.08, size: 46, radius: 9, angle: 42, alpha: 0.08, drift: 19 },
                                        { px: 0.61, py: 0.73, size: 66, radius: 22, angle: 67, alpha: 0.11, drift: -25 },
                                        { px: 0.82, py: 0.20, size: 40, radius: 20, angle: 0, alpha: 0.10, drift: 16 },
                                        { px: 0.91, py: 0.68, size: 52, radius: 11, angle: 26, alpha: 0.08, drift: -21 }
                                    ]

                                    delegate: Rectangle {
                                        id: driftingShape
                                        required property var modelData
                                        required property int index
                                        readonly property real homeY: modelData.py * mediaBackdrop.height
                                        x: modelData.px * mediaBackdrop.width
                                        y: homeY
                                        width: modelData.size
                                        height: width
                                        radius: modelData.radius
                                        rotation: modelData.angle
                                        color: index % 2 === 0
                                            ? island.theme.accentMuted : island.theme.surfaceActive
                                        opacity: modelData.alpha

                                        SequentialAnimation on y {
                                            running: mediaPage.visible && island.player
                                                && island.player.isPlaying
                                            loops: Animation.Infinite
                                            NumberAnimation {
                                                from: driftingShape.homeY
                                                to: driftingShape.homeY + driftingShape.modelData.drift
                                                duration: 3600 + driftingShape.index * 310
                                                easing.type: Easing.InOutSine
                                            }
                                            NumberAnimation {
                                                from: driftingShape.homeY + driftingShape.modelData.drift
                                                to: driftingShape.homeY
                                                duration: 3600 + driftingShape.index * 310
                                                easing.type: Easing.InOutSine
                                            }
                                        }
                                    }
                                }
                            }

                            RowLayout {
                                id: mediaMainLayout
                                readonly property real coverWidth: 196
                                readonly property real lyricsWidth: 180
                                readonly property real centerWidth: Math.max(250,
                                    width - coverWidth - lyricsWidth - spacing * 2)
                                anchors.fill: mediaBackdrop
                                anchors.margins: 18
                                spacing: 20

                                Item {
                                    id: coverVisualiser
                                    Layout.minimumWidth: mediaMainLayout.coverWidth
                                    Layout.preferredWidth: mediaMainLayout.coverWidth
                                    Layout.maximumWidth: mediaMainLayout.coverWidth
                                    Layout.fillHeight: true

                                    Item {
                                        id: radialCover
                                        anchors.centerIn: parent
                                        anchors.horizontalCenterOffset: -16
                                        width: 178
                                        height: 178

                                        Repeater {
                                            model: 56

                                            Item {
                                                id: visualizerBar
                                                required property int index
                                                anchors.fill: parent
                                                rotation: index * (360 / 56)

                                                Rectangle {
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    y: 0
                                                    width: 3
                                                    height: island.player && island.player.isPlaying
                                                        ? 7 + (Math.sin(visualizerBar.index * 0.73
                                                            + island.visualizerPhase) + 1) * 7
                                                        : 7
                                                    radius: 2
                                                    color: island.theme.textPrimary

                                                    Behavior on height {
                                                        NumberAnimation {
                                                            duration: 90
                                                            easing.type: Easing.InOutSine
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        ClippingRectangle {
                                            width: 120
                                            height: 120
                                            anchors.centerIn: parent
                                            radius: width / 2
                                            color: island.theme.surface
                                            antialiasing: true
                                            smooth: true
                                            layer.enabled: true
                                            layer.samples: 8

                                            Item {
                                                anchors.fill: parent
                                                transform: Rotation {
                                                    origin.x: 60
                                                    origin.y: 60
                                                    angle: island.discRotation
                                                }

                                                Image {
                                                    anchors.fill: parent
                                                    visible: island.player
                                                        && (island.player.trackArtUrl || "").length > 0
                                                    source: island.player
                                                        ? island.player.trackArtUrl : ""
                                                    fillMode: Image.PreserveAspectCrop
                                                    smooth: true
                                                    mipmap: true
                                                    asynchronous: true
                                                }

                                                Image {
                                                    anchors.fill: parent
                                                    visible: !island.player
                                                        || (island.player.trackArtUrl || "").length === 0
                                                    source: "assets/album-placeholder.svg"
                                                    fillMode: Image.PreserveAspectCrop
                                                    smooth: true
                                                    mipmap: true
                                                }
                                            }
                                        }
                                    }
                                }

                                ColumnLayout {
                                    id: mediaDetails
                                    Layout.minimumWidth: mediaMainLayout.centerWidth
                                    Layout.preferredWidth: mediaMainLayout.centerWidth
                                    Layout.maximumWidth: mediaMainLayout.centerWidth
                                    Layout.fillHeight: true
                                    spacing: 3

                                    Text {
                                        Layout.fillWidth: true
                                        text: island.player
                                            ? (island.player.trackTitle || "Unbekannter Titel")
                                            : "Nichts wird abgespielt"
                                        color: island.theme.textPrimary
                                        elide: Text.ElideRight
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 18
                                        font.weight: Font.Bold
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: island.player
                                            ? (island.player.trackArtist || "Unbekannter Künstler")
                                            : "Starte Spotify, um Musik zu steuern"
                                        color: island.theme.textMuted
                                        elide: Text.ElideRight
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: island.player ? (island.player.trackAlbum || "") : ""
                                        color: island.theme.textSecondary
                                        elide: Text.ElideRight
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 10
                                    }

                                    Item { Layout.fillHeight: true }

                                    RowLayout {
                                        id: mediaProgressRow
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 28
                                        Layout.leftMargin: -5
                                        Layout.rightMargin: 5
                                        spacing: 8

                                        Text {
                                            Layout.preferredWidth: 34
                                            text: island.formatTime(island.spotifyPosition)
                                            color: island.theme.textMuted
                                            horizontalAlignment: Text.AlignHCenter
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 8
                                        }

                                        Item {
                                            id: progressSlider
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 28
                                            readonly property real progress: island.player
                                                && island.player.length > 0 ? Math.min(1,
                                                    island.spotifyPosition / island.player.length) : 0

                                            Rectangle {
                                                anchors {
                                                    left: parent.left
                                                    right: parent.right
                                                    verticalCenter: parent.verticalCenter
                                                }
                                                height: 3
                                                radius: height / 2
                                                color: island.theme.surfaceActive

                                                Rectangle {
                                                    anchors {
                                                        top: parent.top
                                                        bottom: parent.bottom
                                                        left: parent.left
                                                    }
                                                    width: parent.width * progressSlider.progress
                                                    radius: height / 2
                                                    color: island.theme.textPrimary
                                                }
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                enabled: island.player && island.player.canSeek
                                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                onPressed: mouse => island.seekSpotify(mouse.x / width)
                                                onPositionChanged: mouse => {
                                                    if (pressed)
                                                        island.seekSpotify(mouse.x / width)
                                                }
                                            }
                                        }

                                        Text {
                                            Layout.preferredWidth: 34
                                            text: island.player
                                                ? island.formatTime(island.player.length) : "0:00"
                                            color: island.theme.textMuted
                                            horizontalAlignment: Text.AlignHCenter
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 8
                                        }
                                    }

                                    Item { Layout.preferredHeight: 11 }

                                    RowLayout {
                                        id: mediaTransportRow
                                        Layout.alignment: Qt.AlignHCenter
                                        Layout.preferredWidth: 240
                                        Layout.maximumWidth: 240
                                        Layout.preferredHeight: 48
                                        Layout.leftMargin: -5
                                        Layout.rightMargin: 5
                                        spacing: 8

                                        Repeater {
                                            model: [
                                                { icon: "󰒟", command: "shuffle", main: false,
                                                    active: island.player && island.player.shuffle },
                                                { icon: "󰒮", command: "previous", main: false, active: false },
                                                { icon: island.player && island.player.isPlaying
                                                    ? "󰏤" : "󰐊", command: "play-pause", main: true, active: false },
                                                { icon: "󰒭", command: "next", main: false, active: false },
                                                { icon: island.player
                                                    && island.player.loopState === MprisLoopState.Track
                                                    ? "󰑘" : "󰑖", command: "repeat", main: false,
                                                    active: island.player
                                                        && island.player.loopState !== MprisLoopState.None }
                                            ]

                                            delegate: Rectangle {
                                                id: caelestiaTransport
                                                required property var modelData
                                                Layout.preferredWidth: modelData.main ? 48 : 40
                                                Layout.preferredHeight: modelData.main ? 48 : 40
                                                radius: height / 2
                                                color: modelData.main
                                                    ? (caelestiaTransportMouse.containsMouse
                                                        ? island.theme.textBright : island.theme.textPrimary)
                                                    : modelData.active ? island.theme.accent
                                                    : (caelestiaTransportMouse.containsMouse
                                                        ? island.theme.surfaceHover : island.theme.surfaceActive)
                                                opacity: island.player ? 1 : 0.42

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: caelestiaTransport.modelData.icon
                                                    color: caelestiaTransport.modelData.main
                                                        || caelestiaTransport.modelData.active
                                                        ? island.theme.surface : island.theme.textSecondary
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: caelestiaTransport.modelData.main ? 17 : 12
                                                }

                                                MouseArea {
                                                    id: caelestiaTransportMouse
                                                    anchors.fill: parent
                                                    enabled: island.player !== null
                                                    hoverEnabled: true
                                                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                    onClicked: island.spotifyAction(
                                                        caelestiaTransport.modelData.command)
                                                }
                                            }
                                        }
                                    }

                                    Item { Layout.fillHeight: true }
                                }

                                ColumnLayout {
                                    id: lyricsColumn
                                    Layout.minimumWidth: mediaMainLayout.lyricsWidth
                                    Layout.preferredWidth: mediaMainLayout.lyricsWidth
                                    Layout.maximumWidth: mediaMainLayout.lyricsWidth
                                    Layout.fillHeight: true
                                    spacing: 8

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 28
                                        spacing: 8

                                        Text {
                                            text: "󰲹"
                                            color: island.theme.textPrimary
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 14
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: "LYRICS"
                                            color: island.theme.textPrimary
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 11
                                            font.weight: Font.Bold
                                            font.letterSpacing: 0.8
                                        }
                                    }

                                    Item {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true

                                        Column {
                                            anchors {
                                                left: parent.left
                                                right: parent.right
                                                verticalCenter: parent.verticalCenter
                                            }
                                            spacing: 10

                                            Repeater {
                                                model: [-2, -1, 0, 1, 2]

                                                delegate: Text {
                                                    id: lyricLine
                                                    required property int modelData
                                                    width: parent.width
                                                    text: island.lyricAtOffset(modelData)
                                                    visible: text.length > 0
                                                    color: modelData === 0
                                                        ? island.theme.textPrimary : island.theme.textMuted
                                                    opacity: modelData === 0 ? island.lyricOpacity
                                                        : Math.max(0.26, 0.62 - Math.abs(modelData) * 0.16)
                                                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: modelData === 0 ? 13 : 9
                                                    font.weight: modelData === 0 ? Font.Bold : Font.Medium

                                                    MouseArea {
                                                        anchors.fill: parent
                                                        enabled: lyricLine.text.length > 0
                                                        hoverEnabled: true
                                                        cursorShape: enabled
                                                            ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                        onClicked: island.seekLyricAtOffset(
                                                            lyricLine.modelData)
                                                    }
                                                }
                                            }
                                        }
                                    }

                                }
                            }

                            Item {
                                id: equalizerDisclosure
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                }
                                y: {
                                    mediaMainLayout.y
                                    mediaDetails.y
                                    mediaTransportRow.y
                                    mediaTransportRow.height
                                    return mediaTransportRow.mapToItem(mediaPage, 0,
                                        mediaTransportRow.height).y + 20
                                }
                                height: 32

                                Rectangle {
                                    anchors {
                                        left: parent.left
                                        right: equalizerDisclosureLabel.left
                                        verticalCenter: parent.verticalCenter
                                        leftMargin: 240
                                        rightMargin: 12
                                    }
                                    height: 1
                                    color: island.theme.surfaceHover
                                }

                                Row {
                                    id: equalizerDisclosureLabel
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: {
                                        // mapToItem itself is not a reactive dependency. Track every
                                        // layout coordinate that can move the transport centre.
                                        mediaMainLayout.x
                                        mediaDetails.x
                                        mediaTransportRow.x
                                        mediaTransportRow.width
                                        equalizerDisclosure.x
                                        return mediaTransportRow.mapToItem(equalizerDisclosure,
                                            mediaTransportRow.width / 2, 0).x
                                            - equalizerDisclosureTitle.width / 2
                                    }
                                    Text {
                                        id: equalizerDisclosureTitle
                                        text: "EQUALIZER"
                                        color: equalizerDisclosureMouse.containsMouse
                                            ? island.theme.textPrimary : island.theme.textMuted
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 8
                                        font.weight: Font.Bold
                                        font.letterSpacing: 1.2
                                    }

                                }

                                Rectangle {
                                    anchors {
                                        left: equalizerDisclosureLabel.right
                                        right: parent.right
                                        verticalCenter: parent.verticalCenter
                                        leftMargin: 12
                                        rightMargin: 240
                                    }
                                    height: 1
                                    color: island.theme.surfaceHover
                                }

                                MouseArea {
                                    id: equalizerDisclosureMouse
                                    anchors.centerIn: parent
                                    width: 150
                                    height: 32
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        island.equalizerExpanded = !island.equalizerExpanded
                                        if (island.equalizerExpanded)
                                            equalizerApplyTimer.restart()
                                    }
                                }
                            }

                            Item {
                                id: equalizerPanel
                                anchors {
                                    top: equalizerDisclosure.bottom
                                    left: parent.left
                                    right: parent.right
                                    bottom: parent.bottom
                                }
                                opacity: island.equalizerExpanded ? 1 : 0
                                visible: opacity > 0.001
                                enabled: island.equalizerExpanded

                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: 180
                                        easing.type: Easing.InOutSine
                                    }
                                }

                                Rectangle {
                                    anchors {
                                        top: parent.top
                                        left: parent.left
                                        right: parent.right
                                        leftMargin: 16
                                        rightMargin: 16
                                    }
                                    height: 1
                                    color: island.theme.surfaceHover
                                }

                                RowLayout {
                                    anchors {
                                        top: parent.top
                                        left: parent.left
                                        right: parent.right
                                        topMargin: 3
                                        leftMargin: 22
                                        rightMargin: 22
                                    }
                                    height: 24
                                    spacing: 7

                                    Text {
                                        text: "6-BAND EQ"
                                        color: island.theme.textSecondary
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 8
                                        font.weight: Font.Bold
                                        font.letterSpacing: 1
                                    }

                                    Text {
                                        text: island.currentEqualizerPreset()
                                        color: island.theme.textSecondary
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 7
                                        font.weight: Font.Bold
                                    }

                                    Text {
                                        text: island.equalizerReady ? "●" : "○"
                                        color: island.equalizerReady
                                            ? island.theme.textPrimary : island.theme.textDisabled
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 7
                                    }

                                    Text {
                                        text: island.equalizerStatus
                                        color: island.theme.textMuted
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 7
                                        font.weight: Font.DemiBold
                                    }

                                    Item { Layout.fillWidth: true }

                                    Item {
                                        Layout.preferredWidth: 58
                                        Layout.preferredHeight: 28

                                        Text {
                                            anchors.centerIn: parent
                                            text: "RESET"
                                            color: resetEqualizerMouse.containsMouse
                                                ? island.theme.textPrimary : island.theme.textMuted
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 8
                                            font.weight: Font.Bold
                                        }

                                        MouseArea {
                                            id: resetEqualizerMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: island.resetEqualizer()
                                        }
                                    }

                                    Item {
                                        Layout.preferredWidth: 82
                                        Layout.preferredHeight: 28

                                        Text {
                                            anchors.centerIn: parent
                                            text: island.equalizerEnabled
                                                ? "󰈐  AKTIV" : "󰈑  BYPASS"
                                            color: bypassEqualizerMouse.containsMouse
                                                ? island.theme.textPrimary
                                                : (island.equalizerEnabled
                                                    ? island.theme.textSecondary
                                                    : island.theme.textDisabled)
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 8
                                            font.weight: Font.Bold
                                        }

                                        MouseArea {
                                            id: bypassEqualizerMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: island.setEqualizerEnabled(
                                                !island.equalizerEnabled)
                                        }
                                    }
                                }

                                RowLayout {
                                    id: equalizerPresetRow
                                    anchors {
                                        top: parent.top
                                        left: parent.left
                                        right: parent.right
                                        topMargin: 27
                                        leftMargin: 154
                                        rightMargin: 154
                                    }
                                    height: 28
                                    spacing: 14

                                    Repeater {
                                        model: island.equalizerPresets

                                        delegate: Item {
                                            id: presetControl
                                            required property var modelData
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 28
                                            readonly property bool active:
                                                island.equalizerPresetMatches(modelData.gains)

                                            Text {
                                                anchors.centerIn: parent
                                                text: presetControl.modelData.name
                                                color: presetControl.active
                                                    || presetMouse.containsMouse
                                                    ? island.theme.textPrimary : island.theme.textMuted
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 7
                                                font.weight: Font.Bold
                                                font.letterSpacing: 0.6
                                            }

                                            Rectangle {
                                                anchors {
                                                    bottom: parent.bottom
                                                    horizontalCenter: parent.horizontalCenter
                                                }
                                                width: presetControl.active ? 26 : 4
                                                height: 1
                                                radius: 1
                                                color: island.theme.textPrimary
                                                opacity: presetControl.active
                                                    || presetMouse.containsMouse ? 1 : 0

                                                Behavior on width {
                                                    NumberAnimation {
                                                        duration: 170
                                                        easing.type: Easing.OutCubic
                                                    }
                                                }

                                                Behavior on opacity {
                                                    NumberAnimation { duration: 120 }
                                                }
                                            }

                                            MouseArea {
                                                id: presetMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: island.applyEqualizerPreset(
                                                    presetControl.modelData.gains)
                                            }
                                        }
                                    }
                                }

                                Canvas {
                                    id: equalizerCurve
                                    anchors {
                                        top: parent.top
                                        topMargin: 58
                                        bottom: parent.bottom
                                        bottomMargin: 2
                                        left: parent.left
                                        leftMargin: 62
                                        right: parent.right
                                        rightMargin: 62
                                    }
                                    property var gains: island.equalizerGains
                                    property real phase: island.visualizerPhase
                                    property color guideColor: island.theme.surfaceHover
                                    property color curveColor: island.equalizerEnabled
                                        ? island.theme.textSecondary : island.theme.textDisabled

                                    onGainsChanged: requestPaint()
                                    onPhaseChanged: requestPaint()
                                    onGuideColorChanged: requestPaint()
                                    onCurveColorChanged: requestPaint()
                                    onWidthChanged: requestPaint()
                                    onHeightChanged: requestPaint()

                                    onPaint: {
                                        const ctx = getContext("2d")
                                        const count = 6
                                        const gap = 14
                                        const bandWidth = (width - gap * (count - 1)) / count
                                        const trackTop = 28
                                        const trackBottom = Math.max(trackTop + 1, height - 24)
                                        const trackHeight = trackBottom - trackTop
                                        const point = index => ({
                                            x: bandWidth / 2 + index * (bandWidth + gap),
                                            y: trackTop + ((12 - Number(gains[index] || 0)) / 24)
                                                * trackHeight
                                        })

                                        ctx.reset()
                                        ctx.lineCap = "round"
                                        ctx.strokeStyle = guideColor
                                        ctx.lineWidth = 1
                                        ctx.globalAlpha = 0.38
                                        for (let guide = 0; guide < 3; ++guide) {
                                            const y = trackTop + guide * trackHeight / 2
                                            ctx.beginPath()
                                            ctx.moveTo(0, y)
                                            ctx.lineTo(width, y)
                                            ctx.stroke()
                                        }

                                        ctx.strokeStyle = curveColor
                                        ctx.lineWidth = 1.5
                                        ctx.globalAlpha = 0.7
                                        ctx.beginPath()
                                        let current = point(0)
                                        ctx.moveTo(current.x, current.y)
                                        for (let index = 1; index < count; ++index) {
                                            current = point(index)
                                            ctx.lineTo(current.x, current.y)
                                        }
                                        ctx.stroke()

                                        ctx.fillStyle = curveColor
                                        for (let index = 0; index < count - 1; ++index) {
                                            const left = point(index)
                                            const right = point(index + 1)
                                            const pulse = (Math.sin(phase + index * 0.9) + 1) / 2
                                            const x = (left.x + right.x) / 2
                                            const y = (left.y + right.y) / 2
                                                + (island.player && island.player.isPlaying
                                                    ? Math.sin(phase * 0.7 + index) * 2 : 0)
                                            ctx.globalAlpha = 0.34 + pulse * 0.42
                                            ctx.beginPath()
                                            ctx.arc(x, y, 1.4 + pulse * 1.1, 0, Math.PI * 2)
                                            ctx.fill()
                                        }
                                        ctx.globalAlpha = 1
                                    }
                                }

                                RowLayout {
                                    anchors {
                                        top: parent.top
                                        topMargin: 58
                                        bottom: parent.bottom
                                        bottomMargin: 2
                                        left: parent.left
                                        right: parent.right
                                        leftMargin: 62
                                        rightMargin: 62
                                    }
                                    spacing: 14

                                    Repeater {
                                        model: [
                                            { label: "60 HZ" },
                                            { label: "150 HZ" },
                                            { label: "400 HZ" },
                                            { label: "1 KHZ" },
                                            { label: "3 KHZ" },
                                            { label: "10 KHZ" }
                                        ]

                                        delegate: EqualizerBand {
                                            required property var modelData
                                            required property int index
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            bandIndex: index
                                            bandLabel: modelData.label
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

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

Scope {
    id: launcher

    required property var theme
    property var launcherScreen
    property bool shown: false
    property bool windowVisible: false
    property bool suppressed: false
    property bool focusGrabReady: false
    property bool wallpaperHandoff: false
    property var wallpaperController
    property int selectedIndex: 0
    property real offsetScale: shown ? 0 : 1
    readonly property real morphProgress: 1 - offsetScale
    readonly property real surfaceWidth: 620
    readonly property real targetHeight: 76 + resultCount * 46
    property real surfaceHeight: targetHeight
    readonly property int resultCount: launcherModel.values.length

    FontLoader {
        id: materialSymbolsFont
        source: Qt.resolvedUrl("assets/MaterialSymbolsRounded.ttf")
    }

    readonly property var actions: [
        {
            name: "Wallpaper",
            icon: "image",
            detail: "Wallpaper-Auswahl öffnen",
            keywords: "bild hintergrund background",
            handoff: "wallpaper",
            command: ["qs", "ipc", "call", "wallpaper", "open"]
        },
        {
            name: "Power-Menü",
            icon: "power_settings_new",
            detail: "Sperren, abmelden oder ausschalten",
            keywords: "shutdown reboot logout suspend",
            command: ["qs", "ipc", "call", "power", "open"]
        },
        {
            name: "Benachrichtigungen",
            icon: "notifications",
            detail: "Benachrichtigungszentrale öffnen",
            keywords: "notifications history",
            command: ["qs", "ipc", "call", "notifications", "open"]
        },
        {
            name: "Dateien",
            icon: "folder",
            detail: "Dateibrowser öffnen",
            keywords: "files explorer home",
            command: ["qs", "ipc", "call", "explorer", "open"]
        },
        {
            name: "Widgets",
            icon: "widgets",
            detail: "Widget-Dashboard öffnen",
            keywords: "dashboard weather system",
            command: ["qs", "ipc", "call", "widgets", "open"]
        },
        {
            name: "Audio",
            icon: "volume_up",
            detail: "Audio-Mixer öffnen",
            keywords: "sound volume mixer",
            command: ["qs", "ipc", "call", "mixer", "open"]
        },
        {
            name: "Tastenkürzel",
            icon: "keyboard",
            detail: "Übersicht der Tastenkürzel öffnen",
            keywords: "keybinds shortcuts hotkeys",
            command: ["qs", "ipc", "call", "keybinds", "open"]
        },
        {
            name: "Bildschirm sperren",
            icon: "lock",
            detail: "Sperrbildschirm aktivieren",
            keywords: "lock session",
            command: ["qs", "ipc", "call", "lock", "activate"]
        }
    ]

    Behavior on offsetScale {
        NumberAnimation {
            duration: 500
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.38, 1.21, 0.22, 1.0, 1.0, 1.0]
        }
    }

    Behavior on surfaceHeight {
        NumberAnimation {
            duration: 220
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.2, 0.0, 0.0, 1.0, 1.0, 1.0]
        }
    }

    function fuzzyScore(text, needle) {
        if (needle.length === 0)
            return 0

        const haystack = (text || "").toLowerCase()
        const exactIndex = haystack.indexOf(needle)
        if (exactIndex !== -1)
            return exactIndex + Math.max(0, haystack.length - needle.length) * 0.02

        let searchIndex = 0
        let firstMatch = -1
        let previousMatch = -1
        let gapPenalty = 0

        for (let index = 0; index < haystack.length
                && searchIndex < needle.length; ++index) {
            if (haystack[index] !== needle[searchIndex])
                continue
            if (firstMatch < 0)
                firstMatch = index
            if (previousMatch >= 0)
                gapPenalty += index - previousMatch - 1
            previousMatch = index
            searchIndex += 1
        }

        if (searchIndex !== needle.length)
            return -1
        return 20 + firstMatch + gapPenalty * 1.5
    }

    function bestFuzzyScore(fields, needle) {
        if (needle.length === 0)
            return 0

        let bestScore = -1
        for (let index = 0; index < fields.length; ++index) {
            const score = launcher.fuzzyScore(fields[index], needle)
            if (score >= 0 && (bestScore < 0 || score < bestScore))
                bestScore = score
        }
        return bestScore
    }

    function applicationSymbol(entry) {
        const categories = (entry.categories || []).join(" ")
        const keywords = (entry.keywords || []).join(" ")
        const identity = ((entry.name || "") + " "
            + (entry.genericName || "") + " "
            + (entry.id || "") + " " + categories + " " + keywords)
            .toLowerCase()

        if (/(terminal|console|shell|kitty|foot|alacritty)/.test(identity))
            return "terminal"
        if (/(browser|firefox|chromium|chrome|zen|web)/.test(identity))
            return "language"
        if (/(development|code|editor|ide|codex)/.test(identity))
            return "code"
        if (/(game|steam|gaming)/.test(identity))
            return "sports_esports"
        if (/(audio|video|music|media|spotify|player)/.test(identity))
            return "play_circle"
        if (/(graphics|image|photo|drawing)/.test(identity))
            return "image"
        if (/(office|document|writer|pdf|spreadsheet)/.test(identity))
            return "description"
        if (/(filemanager|file manager|files|thunar|dolphin)/.test(identity))
            return "folder"
        if (/(chat|discord|mail|message|communication)/.test(identity))
            return "chat"
        if (/(settings|system|configuration|control center)/.test(identity))
            return "settings"
        if (/(network|internet)/.test(identity))
            return "public"
        return "apps"
    }

    function applicationResults(query) {
        const needle = query.trim().toLowerCase().replace(/\s+/g, " ")

        return DesktopEntries.applications.values
            .map(entry => {
                const name = entry.name || ""
                const genericName = entry.genericName || ""
                const keywords = (entry.keywords || []).join(" ")
                const categories = (entry.categories || []).join(" ")
                const score = launcher.bestFuzzyScore([
                    name, genericName, keywords, categories,
                    entry.comment || ""
                ], needle)
                if (score < 0)
                    return null
                return {
                    kind: "application",
                    name: name,
                    icon: launcher.applicationSymbol(entry),
                    detail: entry.comment || genericName || "Anwendung",
                    entry: entry,
                    score: needle.length === 0 ? 0 : score
                }
            })
            .filter(result => result !== null)
            .sort((a, b) => a.score - b.score
                || a.name.localeCompare(b.name))
            .slice(0, 7)
    }

    function actionResults(query) {
        const needle = query.trim().slice(1).trim().toLowerCase()

        return launcher.actions
            .map(action => {
                const score = launcher.bestFuzzyScore([
                    action.name, action.detail, action.keywords
                ], needle)
                if (score < 0)
                    return null
                return {
                    kind: "action",
                    name: action.name,
                    icon: action.icon,
                    detail: action.detail,
                    handoff: action.handoff || "",
                    command: action.command,
                    score: score
                }
            })
            .filter(result => result !== null)
            .sort((a, b) => a.score - b.score
                || a.name.localeCompare(b.name))
            .slice(0, 7)
    }

    function results(query) {
        return query.trim().startsWith(">")
            ? launcher.actionResults(query)
            : launcher.applicationResults(query)
    }

    function open() {
        closeTimer.stop()
        launcher.windowVisible = true
        launcher.shown = true
        launcher.focusGrabReady = false
        launcher.selectedIndex = 0
        focusGrabTimer.restart()
    }

    function close() {
        if (!launcher.windowVisible)
            return
        if (launcher.wallpaperHandoff) {
            launcher.wallpaperHandoff = false
            wallpaperHandoffTimeout.stop()
            if (launcher.wallpaperController)
                launcher.wallpaperController.close()
        }
        focusGrabTimer.stop()
        launcher.focusGrabReady = false
        launcher.shown = false
        closeTimer.restart()
    }

    function toggle() {
        launcher.shown ? launcher.close() : launcher.open()
    }

    function moveSelection(offset) {
        if (launcher.resultCount === 0)
            return
        launcher.selectedIndex = (launcher.selectedIndex + offset
            + launcher.resultCount) % launcher.resultCount
        resultsList.positionViewAtIndex(launcher.selectedIndex, ListView.Contain)
    }

    function launchSelected() {
        if (launcher.resultCount === 0)
            return
        const result = launcherModel.values[launcher.selectedIndex]
        if (result.kind === "action" && result.handoff === "wallpaper") {
            launcher.beginWallpaperHandoff(result)
        } else if (result.kind === "action") {
            launcher.close()
            Quickshell.execDetached(result.command)
        } else {
            launcher.close()
            result.entry.execute()
        }
    }

    function beginWallpaperHandoff(result) {
        if (!launcher.wallpaperController) {
            launcher.close()
            Quickshell.execDetached(result.command)
            return
        }

        launcher.wallpaperHandoff = true
        wallpaperHandoffTimeout.restart()
        launcher.wallpaperController.open()
    }

    onSuppressedChanged: {
        if (launcher.suppressed)
            launcher.close()
    }

    IpcHandler {
        target: "launcher"

        function toggle(): void { launcher.toggle() }
        function open(): void { launcher.open() }
        function close(): void { launcher.close() }
        function query(text: string): void {
            launcher.open()
            searchInput.text = text
            focusGrabTimer.restart()
        }
        function activate(): void { launcher.launchSelected() }
        function status(): string {
            const mode = searchInput.text.trim().startsWith(">")
                ? "actions" : "applications"
            return (launcher.shown ? "open" : "closed") + " "
                + mode + " " + launcher.resultCount
                + " handoff=" + launcher.wallpaperHandoff
                + " progress=" + launcher.morphProgress.toFixed(3)
        }
    }

    ScriptModel {
        id: launcherModel
        values: launcher.results(searchInput.text)
    }

    Timer {
        id: focusGrabTimer
        interval: 80
        onTriggered: {
            if (launcher.shown) {
                launcher.focusGrabReady = true
                searchInput.forceActiveFocus()
                searchInput.cursorPosition = searchInput.length
            }
        }
    }

    Timer {
        id: closeTimer
        interval: 515
        onTriggered: {
            if (!launcher.shown) {
                launcher.windowVisible = false
                searchInput.text = ""
                launcher.selectedIndex = 0
            }
        }
    }

    Timer {
        id: wallpaperHandoffTimeout
        interval: 5000
        onTriggered: {
            if (!launcher.wallpaperHandoff)
                return
            launcher.wallpaperHandoff = false
            launcher.close()
        }
    }

    Connections {
        target: launcher.wallpaperController
        enabled: launcher.wallpaperHandoff

        function onEnteredChanged(): void {
            if (!launcher.wallpaperHandoff
                    || !launcher.wallpaperController.entered)
                return
            wallpaperHandoffTimeout.stop()
            launcher.wallpaperHandoff = false
            launcher.close()
        }
    }

    PanelWindow {
        id: launcherWindow

        screen: launcher.launcherScreen
        visible: launcher.launcherScreen !== null
            && !launcher.suppressed
            && launcher.windowVisible
        color: "transparent"
        implicitHeight: 430
        exclusiveZone: 0
        focusable: launcher.shown
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell:launcher"

        anchors {
            left: true
            right: true
            bottom: true
        }

        mask: Region { item: launcherCard }

        Item {
            id: launcherCard

            anchors {
                horizontalCenter: parent.horizontalCenter
                horizontalCenterOffset: 27
            }
            width: Math.min(launcher.surfaceWidth, parent.width - 90)
            height: launcher.surfaceHeight
            y: parent.height - height + (height + 5) * launcher.offsetScale
            opacity: 1 - launcher.offsetScale
            visible: launcher.offsetScale < 1

            ClippingRectangle {
                anchors.fill: parent
                radius: 18
                color: "transparent"

                Item {
                    id: searchRow
                    anchors {
                        top: parent.top
                        left: parent.left
                        right: parent.right
                    }
                    height: 72

                    Text {
                        anchors {
                            left: parent.left
                            right: parent.right
                            leftMargin: 22
                            rightMargin: 22
                            verticalCenter: parent.verticalCenter
                        }
                        visible: searchInput.text.length === 0
                        text: "Anwendung suchen  ·  > für Aktionen"
                        color: launcher.theme.textMuted
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 14
                    }

                    TextInput {
                        id: searchInput
                        anchors {
                            left: parent.left
                            right: parent.right
                            leftMargin: 22
                            rightMargin: 22
                            verticalCenter: parent.verticalCenter
                        }
                        color: launcher.theme.textPrimary
                        selectionColor: launcher.theme.textPrimary
                        selectedTextColor: launcher.theme.surface
                        clip: true
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 14
                        onTextChanged: launcher.selectedIndex = 0

                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Escape) {
                                launcher.close()
                                event.accepted = true
                            } else if (event.key === Qt.Key_Down
                                    || (event.key === Qt.Key_N
                                        && (event.modifiers & Qt.ControlModifier))) {
                                launcher.moveSelection(1)
                                event.accepted = true
                            } else if (event.key === Qt.Key_Up
                                    || (event.key === Qt.Key_P
                                        && (event.modifiers & Qt.ControlModifier))) {
                                launcher.moveSelection(-1)
                                event.accepted = true
                            } else if (event.key === Qt.Key_Return
                                    || event.key === Qt.Key_Enter) {
                                launcher.launchSelected()
                                event.accepted = true
                            }
                        }
                    }

                    Rectangle {
                        anchors {
                            left: parent.left
                            right: parent.right
                            bottom: parent.bottom
                            leftMargin: 18
                            rightMargin: 18
                        }
                        height: 1
                        color: launcher.theme.surfaceHover
                    }
                }

                ListView {
                    id: resultsList
                    anchors {
                        top: searchRow.bottom
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                        leftMargin: 12
                        rightMargin: 12
                        bottomMargin: 4
                    }
                    model: launcherModel
                    currentIndex: launcher.selectedIndex
                    spacing: 0
                    clip: true
                    interactive: false

                    delegate: Item {
                        id: resultRow
                        required property var modelData
                        required property int index
                        width: resultsList.width
                        height: 46
                        readonly property bool selected:
                            index === launcher.selectedIndex

                        Rectangle {
                            anchors {
                                fill: parent
                                topMargin: 2
                                bottomMargin: 2
                            }
                            radius: 9
                            color: resultRow.selected ? launcher.theme.surfaceSubtle
                                : (resultMouse.containsMouse ? launcher.theme.surfaceSubtle : "transparent")
                        }

                        Item {
                            id: resultIcon
                            anchors {
                                left: parent.left
                                leftMargin: 15
                                verticalCenter: parent.verticalCenter
                            }
                            width: 26
                            height: 26

                            Text {
                                anchors.centerIn: parent
                                text: resultRow.modelData.icon
                                color: launcher.theme.textBright
                                opacity: resultRow.selected ? 1 : 0.72
                                font.family: materialSymbolsFont.name
                                font.pixelSize: 20
                            }
                        }

                        Text {
                            anchors {
                                left: resultIcon.right
                                right: parent.right
                                leftMargin: 12
                                rightMargin: 15
                                verticalCenter: parent.verticalCenter
                            }
                            text: resultRow.modelData.name
                            color: resultRow.selected ? launcher.theme.textPrimary : launcher.theme.textSecondary
                            elide: Text.ElideRight
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 12
                            font.weight: resultRow.selected
                                ? Font.DemiBold : Font.Normal
                        }

                        MouseArea {
                            id: resultMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: launcher.selectedIndex = resultRow.index
                            onClicked: {
                                launcher.selectedIndex = resultRow.index
                                launcher.launchSelected()
                            }
                        }
                    }
                }
            }
        }
    }

    HyprlandFocusGrab {
        active: launcher.shown && launcher.focusGrabReady
        windows: [launcherWindow]
        onCleared: launcher.close()
    }
}

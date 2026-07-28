import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Scope {
    id: explorer

    required property var theme
    property var explorerScreen
    property bool shown: false
    property bool suppressed: false
    property string currentPath: "/home/mika"
    property string parentPath: "/home"
    property var entries: []
    property bool showHidden: false
    property string errorText: ""
    property bool folderDialogOpen: false
    property string pendingMovePath: ""
    property string pendingMoveName: ""
    property string actionMessage: ""
    property bool actionFailed: false

    readonly property var visibleEntries: entries.filter(entry => {
        if (!showHidden && entry.hidden)
            return false
        const needle = searchInput.text.trim().toLowerCase()
        return needle.length === 0 || entry.name.toLowerCase().includes(needle)
    })

    function load(path) {
        if (listing.running)
            listing.running = false
        listing.command = [
            "python3",
            "/home/mika/.config/quickshell/scripts/file-list.py",
            path
        ]
        listing.running = true
    }

    function open() {
        explorer.shown = true
        searchInput.text = ""
        explorer.load(explorer.currentPath)
        focusTimer.restart()
    }

    function close() {
        explorer.shown = false
        searchInput.text = ""
        explorer.folderDialogOpen = false
    }

    function toggle() {
        explorer.shown ? explorer.close() : explorer.open()
    }

    function openEntry(entry) {
        if (entry.directory) {
            searchInput.text = ""
            explorer.load(entry.path)
            return
        }

        opener.command = ["xdg-open", entry.path]
        opener.running = true
        explorer.close()
    }

    function showFolderDialog() {
        explorer.folderDialogOpen = true
        newFolderInput.text = ""
        Qt.callLater(() => newFolderInput.forceActiveFocus())
    }

    function createFolder() {
        const name = newFolderInput.text.trim()
        if (name.length === 0)
            return
        actions.command = [
            "python3",
            "/home/mika/.config/quickshell/scripts/file-actions.py",
            "mkdir",
            explorer.currentPath,
            name
        ]
        actions.running = true
    }

    function prepareMove(entry) {
        explorer.pendingMovePath = entry.path
        explorer.pendingMoveName = entry.name
        explorer.actionMessage = "Zielordner auswählen"
        explorer.actionFailed = false
    }

    function moveHere() {
        if (explorer.pendingMovePath.length === 0)
            return
        actions.command = [
            "python3",
            "/home/mika/.config/quickshell/scripts/file-actions.py",
            "move",
            explorer.pendingMovePath,
            explorer.currentPath
        ]
        actions.running = true
    }

    function cancelMove() {
        explorer.pendingMovePath = ""
        explorer.pendingMoveName = ""
        explorer.actionMessage = ""
        explorer.actionFailed = false
    }

    IpcHandler {
        target: "explorer"

        function toggle(): void {
            explorer.toggle()
        }

        function open(): void {
            explorer.open()
        }

        function close(): void {
            explorer.close()
        }

        function home(): void {
            explorer.shown = true
            explorer.load("/home/mika")
            focusTimer.restart()
        }

        function newFolder(): void {
            explorer.shown = true
            explorer.showFolderDialog()
        }
    }

    Process {
        id: listing

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text)
                    explorer.currentPath = result.path
                    explorer.parentPath = result.parent
                    explorer.entries = result.entries
                    explorer.errorText = result.error || ""
                } catch (error) {
                    explorer.entries = []
                    explorer.errorText = "Ordner konnte nicht gelesen werden"
                }
            }
        }
    }

    Process {
        id: opener
    }

    Process {
        id: actions

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text)
                    explorer.actionMessage = result.message
                    explorer.actionFailed = !result.ok
                    if (result.ok) {
                        if (result.action === "mkdir")
                            explorer.folderDialogOpen = false
                        if (result.action === "move")
                            explorer.cancelMove()
                        explorer.load(explorer.currentPath)
                    }
                } catch (error) {
                    explorer.actionMessage = "Aktion konnte nicht ausgeführt werden"
                    explorer.actionFailed = true
                }
            }
        }
    }

    Process {
        id: terminal
    }

    Timer {
        id: focusTimer
        interval: 40
        onTriggered: {
            searchInput.forceActiveFocus()
            searchInput.cursorPosition = searchInput.length
        }
    }

    PanelWindow {
        id: explorerWindow
        screen: explorer.explorerScreen
        visible: explorer.explorerScreen !== null
            && !explorer.suppressed
            && explorer.shown
        color: "transparent"
        implicitWidth: 760
        implicitHeight: 690
        exclusiveZone: 0
        focusable: true

        anchors {
            top: true
        }

        margins {
            top: 100
        }

        Rectangle {
            anchors.fill: parent
            color: explorer.theme.surfaceGlass
            radius: 22
            border.width: 1
            border.color: explorer.theme.surfaceActive
            clip: true

            ColumnLayout {
                anchors {
                    fill: parent
                    margins: 24
                }
                spacing: 14

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Rectangle {
                        width: 38
                        height: 38
                        radius: 11
                        color: explorer.theme.textPrimary

                        Text {
                            anchors.centerIn: parent
                            text: "󰉋"
                            color: explorer.theme.surface
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 20
                        }
                    }

                    Column {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            text: "Mini Explorer"
                            color: explorer.theme.textPrimary
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 19
                            font.bold: true
                        }

                        Text {
                            width: 480
                            text: explorer.currentPath.replace("/home/mika", "~")
                            color: explorer.theme.textMuted
                            elide: Text.ElideMiddle
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 10
                        }
                    }

                    Rectangle {
                        width: 34
                        height: 34
                        radius: 10
                        color: closeMouse.containsMouse ? explorer.theme.surfaceHover : explorer.theme.surfaceRaised

                        Text {
                            anchors.centerIn: parent
                            text: "×"
                            color: explorer.theme.textPrimary
                            font.pixelSize: 21
                        }

                        MouseArea {
                            id: closeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: explorer.close()
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Repeater {
                        model: [
                            { icon: "󰁍", tip: "Zurück", action: "back" },
                            { icon: "󰋜", tip: "Home", action: "home" }
                        ]

                        delegate: Rectangle {
                            required property var modelData
                            width: 36
                            height: 36
                            radius: 10
                            color: navMouse.containsMouse ? explorer.theme.surfaceHover : explorer.theme.surfaceRaised

                            Text {
                                anchors.centerIn: parent
                                text: modelData.icon
                                color: explorer.theme.textPrimary
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 15
                            }

                            MouseArea {
                                id: navMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (modelData.action === "back")
                                        explorer.load(explorer.parentPath)
                                    else
                                        explorer.load("/home/mika")
                                }
                            }

                            Behavior on color {
                                ColorAnimation { duration: 100 }
                            }
                        }
                    }

                    Rectangle {
                        width: 36
                        height: 36
                        radius: 10
                        color: createMouse.containsMouse ? explorer.theme.textPrimary : explorer.theme.surfaceRaised

                        Text {
                            anchors.centerIn: parent
                            text: "+"
                            color: createMouse.containsMouse ? explorer.theme.surface : explorer.theme.textPrimary
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 19
                            font.bold: true
                        }

                        MouseArea {
                            id: createMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: explorer.showFolderDialog()
                        }

                        Behavior on color {
                            ColorAnimation { duration: 100 }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 36
                        radius: 10
                        color: explorer.theme.surfaceRaised
                        border.width: searchInput.activeFocus ? 1 : 0
                        border.color: explorer.theme.textPrimary

                        Text {
                            anchors {
                                left: parent.left
                                leftMargin: 13
                                verticalCenter: parent.verticalCenter
                            }
                            text: "󰍉"
                            color: explorer.theme.textMuted
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 13
                        }

                        Text {
                            anchors {
                                left: parent.left
                                leftMargin: 40
                                verticalCenter: parent.verticalCenter
                            }
                            visible: searchInput.text.length === 0
                            text: "Im Ordner suchen..."
                            color: explorer.theme.textDisabled
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 11
                        }

                        TextInput {
                            id: searchInput
                            anchors {
                                left: parent.left
                                right: parent.right
                                leftMargin: 40
                                rightMargin: 12
                                verticalCenter: parent.verticalCenter
                            }
                            color: explorer.theme.textPrimary
                            selectionColor: explorer.theme.textPrimary
                            selectedTextColor: explorer.theme.surface
                            clip: true
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 11

                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_Escape) {
                                    explorer.close()
                                    event.accepted = true
                                } else if (event.key === Qt.Key_Backspace
                                        && searchInput.text.length === 0) {
                                    explorer.load(explorer.parentPath)
                                    event.accepted = true
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: 36
                        height: 36
                        radius: 10
                        color: hiddenMouse.containsMouse || explorer.showHidden
                            ? explorer.theme.textPrimary : explorer.theme.surfaceRaised

                        Text {
                            anchors.centerIn: parent
                            text: explorer.showHidden ? "󰈈" : "󰈉"
                            color: explorer.showHidden ? explorer.theme.surface : explorer.theme.textPrimary
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 14
                        }

                        MouseArea {
                            id: hiddenMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: explorer.showHidden = !explorer.showHidden
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 15
                    color: explorer.theme.surface
                    border.width: 1
                    border.color: explorer.theme.surfaceHover
                    clip: true

                    ListView {
                        id: fileList
                        anchors {
                            fill: parent
                            margins: 8
                        }
                        model: explorer.visibleEntries
                        spacing: 3
                        clip: true

                        delegate: Rectangle {
                            required property var modelData
                            width: fileList.width
                            height: 42
                            radius: 9
                            color: entryMouse.containsMouse ? explorer.theme.surfaceHover : "transparent"

                            MouseArea {
                                id: entryMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: explorer.openEntry(modelData)
                            }

                            RowLayout {
                                anchors {
                                    fill: parent
                                    leftMargin: 12
                                    rightMargin: 12
                                }
                                spacing: 12

                                Text {
                                    text: modelData.directory ? "󰉋" : "󰈔"
                                    color: modelData.directory ? explorer.theme.textPrimary : explorer.theme.textMuted
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 17
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.name
                                    color: explorer.theme.textPrimary
                                    elide: Text.ElideRight
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 11
                                    font.bold: modelData.directory
                                }

                                Text {
                                    Layout.preferredWidth: 72
                                    horizontalAlignment: Text.AlignRight
                                    text: modelData.size
                                    color: explorer.theme.textMuted
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 9
                                }

                                Text {
                                    Layout.preferredWidth: 82
                                    horizontalAlignment: Text.AlignRight
                                    text: modelData.modified
                                    color: explorer.theme.textMuted
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 9
                                }

                                Text {
                                    text: modelData.directory ? "›" : ""
                                    color: explorer.theme.textMuted
                                    font.pixelSize: 18
                                }

                                Rectangle {
                                    width: 28
                                    height: 28
                                    radius: 8
                                    color: moveMouse.containsMouse ? explorer.theme.textPrimary : explorer.theme.surfaceRaised
                                    opacity: entryMouse.containsMouse
                                        || moveMouse.containsMouse
                                        || explorer.pendingMovePath === modelData.path ? 1 : 0

                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰆏"
                                        color: moveMouse.containsMouse ? explorer.theme.surface : explorer.theme.textPrimary
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 13
                                    }

                                    MouseArea {
                                        id: moveMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: explorer.prepareMove(modelData)
                                    }

                                    Behavior on opacity {
                                        NumberAnimation { duration: 100 }
                                    }
                                }
                            }

                            Behavior on color {
                                ColorAnimation { duration: 90 }
                            }
                        }

                        ScrollBar.vertical: ScrollBar {
                            policy: ScrollBar.AsNeeded
                        }
                    }

                    Column {
                        anchors.centerIn: parent
                        visible: explorer.visibleEntries.length === 0
                        spacing: 8

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: explorer.errorText.length > 0 ? "󰅙" : "󰅖"
                            color: explorer.theme.textMuted
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 26
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: explorer.errorText.length > 0
                                ? explorer.errorText : "Keine Dateien gefunden"
                            color: explorer.theme.textMuted
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 11
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        Layout.fillWidth: true
                        text: explorer.pendingMovePath.length > 0
                            ? "Verschieben: " + explorer.pendingMoveName
                            : explorer.actionMessage.length > 0
                                ? explorer.actionMessage
                                : explorer.visibleEntries.length + " Elemente"
                        color: explorer.actionFailed ? "#ff8c8c"
                            : explorer.pendingMovePath.length > 0 ? explorer.theme.textPrimary : explorer.theme.textDisabled
                        elide: Text.ElideMiddle
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 10
                    }

                    Rectangle {
                        visible: explorer.pendingMovePath.length > 0
                        width: 34
                        height: 34
                        radius: 10
                        color: cancelMoveMouse.containsMouse ? explorer.theme.surfaceActive : explorer.theme.surfaceHover

                        Text {
                            anchors.centerIn: parent
                            text: "×"
                            color: explorer.theme.textPrimary
                            font.pixelSize: 17
                        }

                        MouseArea {
                            id: cancelMoveMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: explorer.cancelMove()
                        }
                    }

                    Rectangle {
                        visible: explorer.pendingMovePath.length > 0
                        width: 136
                        height: 34
                        radius: 10
                        color: moveHereMouse.containsMouse ? explorer.theme.textPrimary : explorer.theme.textPrimary

                        Text {
                            anchors.centerIn: parent
                            text: "Hierher verschieben"
                            color: explorer.theme.surface
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 9
                            font.bold: true
                        }

                        MouseArea {
                            id: moveHereMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: explorer.moveHere()
                        }
                    }

                    Rectangle {
                        visible: explorer.pendingMovePath.length === 0
                        width: 150
                        height: 34
                        radius: 10
                        color: terminalMouse.containsMouse ? explorer.theme.textPrimary : explorer.theme.surfaceHover

                        Row {
                            anchors.centerIn: parent
                            spacing: 8

                            Text {
                                text: "󰉋"
                                color: terminalMouse.containsMouse ? explorer.theme.surface : explorer.theme.textPrimary
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 13
                            }

                            Text {
                            text: "Im Terminal öffnen"
                                color: terminalMouse.containsMouse ? explorer.theme.surface : explorer.theme.textPrimary
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 10
                            }
                        }

                        MouseArea {
                            id: terminalMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                terminal.command = ["kitty", "--directory", explorer.currentPath]
                                terminal.running = true
                                explorer.close()
                            }
                        }

                        Behavior on color {
                            ColorAnimation { duration: 100 }
                        }
                    }
                }
            }

            Rectangle {
                anchors.fill: parent
                visible: explorer.folderDialogOpen
                color: explorer.theme.surfaceGlass
                z: 20

                MouseArea {
                    anchors.fill: parent
                    onClicked: explorer.folderDialogOpen = false
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: 430
                    height: 170
                    radius: 17
                    color: explorer.theme.surface
                    border.width: 1
                    border.color: explorer.theme.surfaceActive

                    MouseArea {
                        anchors.fill: parent
                    }

                    ColumnLayout {
                        anchors {
                            fill: parent
                            margins: 18
                        }
                        spacing: 12

                        Text {
                            text: "Neuer Ordner"
                            color: explorer.theme.textPrimary
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 15
                            font.bold: true
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 40
                            radius: 10
                            color: explorer.theme.surfaceRaised
                            border.width: newFolderInput.activeFocus ? 1 : 0
                            border.color: explorer.theme.textPrimary

                            TextInput {
                                id: newFolderInput
                                anchors {
                                    fill: parent
                                    leftMargin: 13
                                    rightMargin: 13
                                }
                                verticalAlignment: TextInput.AlignVCenter
                                color: explorer.theme.textPrimary
                                selectionColor: explorer.theme.textPrimary
                                selectedTextColor: explorer.theme.surface
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 11

                                Keys.onPressed: event => {
                                    if (event.key === Qt.Key_Escape) {
                                        explorer.folderDialogOpen = false
                                        event.accepted = true
                                    } else if (event.key === Qt.Key_Return
                                            || event.key === Qt.Key_Enter) {
                                        explorer.createFolder()
                                        event.accepted = true
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.alignment: Qt.AlignRight
                            spacing: 8

                            Rectangle {
                                width: 92
                                height: 32
                                radius: 9
                                color: cancelFolderMouse.containsMouse ? explorer.theme.surfaceHover : explorer.theme.surfaceHover

                                Text {
                                    anchors.centerIn: parent
                                    text: "Abbrechen"
                                    color: explorer.theme.textPrimary
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 9
                                }

                                MouseArea {
                                    id: cancelFolderMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: explorer.folderDialogOpen = false
                                }
                            }

                            Rectangle {
                                width: 92
                                height: 32
                                radius: 9
                                color: createFolderMouse.containsMouse ? explorer.theme.textPrimary : explorer.theme.textPrimary

                                Text {
                                    anchors.centerIn: parent
                                    text: "Erstellen"
                                    color: explorer.theme.surface
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 9
                                    font.bold: true
                                }

                                MouseArea {
                                    id: createFolderMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: explorer.createFolder()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

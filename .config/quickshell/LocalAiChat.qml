pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io

Item {
    id: chat

    required property var theme
    property bool active: false
    property bool ready: false
    property bool busy: false
    property bool preparing: false
    property string aiState: "checking"
    property string statusText: "PRÜFE OLLAMA"
    readonly property bool canClear: messages.count > 0 && !busy
    readonly property string modelName: "qwen3.5:4b"
    readonly property string fontFamily: "JetBrainsMono Nerd Font"
    readonly property string helperPath:
        "/home/mika/.config/quickshell/scripts/local-ai.py"

    function scrollToEnd(): void {
        Qt.callLater(function() {
            conversationView.contentY = Math.max(
                0, conversationView.contentHeight - conversationView.height)
        })
    }

    function conversation(): var {
        const result = []
        for (let index = 0; index < messages.count; ++index) {
            const entry = messages.get(index)
            result.push({ role: entry.role, content: entry.content })
        }
        return result
    }

    function clearConversation(): void {
        if (chat.busy)
            return
        messages.clear()
        if (chat.active && chat.ready)
            inputFocus.restart()
    }

    function updateStatus(raw): void {
        try {
            const result = JSON.parse(raw)
            chat.ready = !!result.ok
            chat.aiState = result.state || "offline"
            chat.statusText = result.message || "NICHT VERFÜGBAR"
        } catch (error) {
            chat.ready = false
            chat.aiState = "offline"
            chat.statusText = "OLLAMA IST OFFLINE"
        }
    }

    function probe(): void {
        if (probeProcess.running || chat.preparing || chat.busy)
            return
        chat.aiState = "checking"
        chat.statusText = "PRÜFE OLLAMA"
        probeProcess.command = [
            "/usr/bin/python3", chat.helperPath, "status", chat.modelName
        ]
        probeProcess.running = true
    }

    function prepare(): void {
        if (prepareProcess.running)
            return
        chat.preparing = true
        chat.ready = false
        chat.aiState = "preparing"
        chat.statusText = "OLLAMA + MODELL WERDEN EINGERICHTET"
        prepareProcess.command = [
            "/usr/bin/python3", chat.helperPath, "prepare", chat.modelName
        ]
        prepareProcess.running = true
    }

    function send(): void {
        const prompt = input.text.trim()
        if (!chat.ready || chat.busy || prompt.length === 0)
            return
        messages.append({ role: "user", content: prompt })
        input.clear()
        chat.busy = true
        chat.statusText = "NOVA DENKT"
        chat.scrollToEnd()
        requestProcess.command = [
            "/usr/bin/python3",
            chat.helperPath,
            "chat",
            chat.modelName,
            JSON.stringify(chat.conversation())
        ]
        requestProcess.running = true
    }

    onActiveChanged: {
        if (active) {
            chat.probe()
            inputFocus.restart()
        }
    }

    ListModel {
        id: messages
    }

    Process {
        id: probeProcess

        stdout: StdioCollector {
            onStreamFinished: chat.updateStatus(text)
        }
    }

    Process {
        id: prepareProcess

        stdout: StdioCollector {
            onStreamFinished: {
                chat.preparing = false
                chat.updateStatus(text)
                if (chat.ready)
                    inputFocus.restart()
            }
        }
    }

    Process {
        id: requestProcess

        stdout: StdioCollector {
            onStreamFinished: {
                chat.busy = false
                try {
                    const result = JSON.parse(text)
                    if (result.ok) {
                        messages.append({
                            role: "assistant",
                            content: result.message
                        })
                        chat.ready = true
                        chat.aiState = "ready"
                        chat.statusText = "BEREIT"
                    } else {
                        chat.ready = result.state !== "missing_model"
                            && result.state !== "offline"
                        chat.aiState = result.state || "request_failed"
                        chat.statusText = "ANTWORT FEHLGESCHLAGEN"
                        messages.append({
                            role: "assistant",
                            content: result.message
                                || "Ich konnte gerade nicht antworten."
                        })
                    }
                } catch (error) {
                    chat.statusText = "ANTWORT FEHLGESCHLAGEN"
                    messages.append({
                        role: "assistant",
                        content: "Ollamas Antwort konnte nicht gelesen werden."
                    })
                }
                chat.scrollToEnd()
                inputFocus.restart()
            }
        }
    }

    Timer {
        interval: 30000
        running: chat.active && !chat.ready && !chat.preparing
        repeat: true
        onTriggered: chat.probe()
    }

    Timer {
        id: inputFocus
        interval: 50
        onTriggered: if (chat.active && chat.ready) input.forceActiveFocus()
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 20
            spacing: 7

            Rectangle {
                Layout.preferredWidth: 5
                Layout.preferredHeight: 5
                radius: 3
                color: chat.ready ? chat.theme.accent
                    : chat.aiState === "checking" || chat.preparing
                        ? chat.theme.textMuted : chat.theme.outlineSubtle

                SequentialAnimation on opacity {
                    running: chat.busy || chat.preparing
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.25; duration: 520 }
                    NumberAnimation { to: 1; duration: 520 }
                }
            }

            Text {
                Layout.fillWidth: true
                text: chat.statusText
                color: chat.ready ? chat.theme.textSecondary
                    : chat.theme.textMuted
                elide: Text.ElideRight
                font.family: chat.fontFamily
                font.pixelSize: 7
                font.weight: Font.DemiBold
            }

            Text {
                text: chat.modelName.toUpperCase()
                color: chat.theme.textDisabled
                font.family: chat.fontFamily
                font.pixelSize: 7
            }

        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Column {
                anchors.centerIn: parent
                width: parent.width - 72
                spacing: 17
                visible: !chat.ready

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "󰚩"
                    color: chat.theme.outlineSubtle
                    font.family: chat.fontFamily
                    font.pixelSize: 52
                }

                Text {
                    width: parent.width
                    text: chat.preparing
                        ? "DEINE LOKALE KI WIRD VORBEREITET"
                        : "LOKALER AI CHAT"
                    color: chat.theme.textSecondary
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    font.family: chat.fontFamily
                    font.pixelSize: 13
                    font.weight: Font.Bold
                }

                Text {
                    width: parent.width
                    text: chat.preparing
                        ? "Der erste Download kann einige Minuten dauern."
                        : chat.aiState === "missing_model"
                            ? "Qwen 3.5 4B fehlt noch. Der Chat bleibt vollständig auf deinem Rechner."
                            : chat.aiState === "missing_runtime"
                                ? "Ollama wird lokal in ~/.local installiert – ohne Cloud und ohne Root."
                                : "Ollama ist gerade nicht erreichbar."
                    color: chat.theme.textMuted
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    font.family: chat.fontFamily
                    font.pixelSize: 11
                    lineHeight: 1.3
                }

                LinkButton {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: !chat.preparing
                    label: chat.aiState === "missing_model"
                        ? "MODELL LADEN" : "LOKAL EINRICHTEN"
                    onClicked: chat.prepare()
                }
            }

            Column {
                anchors.centerIn: parent
                width: parent.width - 72
                spacing: 17
                visible: chat.ready && messages.count === 0

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "󰚩"
                    color: chat.theme.outlineSubtle
                    font.family: chat.fontFamily
                    font.pixelSize: 52
                }

                Text {
                    width: parent.width
                    text: "WAS MÖCHTEST DU WISSEN?"
                    color: chat.theme.textSecondary
                    horizontalAlignment: Text.AlignHCenter
                    font.family: chat.fontFamily
                    font.pixelSize: 13
                    font.weight: Font.Bold
                }

                Text {
                    width: parent.width
                    text: "Ideen, Erklärungen, Texte oder kleine Fragen für jeden Tag."
                    color: chat.theme.textMuted
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    font.family: chat.fontFamily
                    font.pixelSize: 11
                    lineHeight: 1.3
                }
            }

            Flickable {
                id: conversationView

                anchors.fill: parent
                visible: chat.ready && messages.count > 0
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.VerticalFlick
                contentWidth: width
                contentHeight: conversation.implicitHeight

                Column {
                    id: conversation
                    width: conversationView.width
                    spacing: 20

                    Repeater {
                        model: messages

                        delegate: Item {
                            id: message

                            required property string role
                            required property string content
                            readonly property bool fromUser: role === "user"

                            width: conversation.width
                            height: messageLayout.implicitHeight

                            ColumnLayout {
                                id: messageLayout
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    leftMargin: message.fromUser ? 132 : 10
                                    rightMargin: message.fromUser ? 10 : 86
                                }
                                spacing: 7

                                RowLayout {
                                    Layout.fillWidth: true

                                    Text {
                                        Layout.fillWidth: true
                                        text: message.fromUser ? "DU" : "NOVA"
                                        color: message.fromUser
                                            ? chat.theme.textMuted : chat.theme.accent
                                        horizontalAlignment: message.fromUser
                                            ? Text.AlignRight : Text.AlignLeft
                                        font.family: chat.fontFamily
                                        font.pixelSize: 8
                                        font.weight: Font.Bold
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: message.content
                                    color: message.fromUser
                                        ? chat.theme.textSecondary
                                        : chat.theme.textPrimary
                                    horizontalAlignment: message.fromUser
                                        ? Text.AlignRight : Text.AlignLeft
                                    wrapMode: Text.WordWrap
                                    textFormat: Text.PlainText
                                    font.family: chat.fontFamily
                                    font.pixelSize: 11
                                    lineHeight: 1.3
                                }
                            }
                        }
                    }

                    Text {
                        visible: chat.busy
                        text: "NOVA  ·  ·  ·"
                        color: chat.theme.textMuted
                        font.family: chat.fontFamily
                        font.pixelSize: 8

                        SequentialAnimation on opacity {
                            running: chat.busy
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.25; duration: 480 }
                            NumberAnimation { to: 1; duration: 480 }
                        }
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 76
            visible: chat.ready

            Rectangle {
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                }
                height: 1
                color: input.activeFocus
                    ? chat.theme.accentMuted : chat.theme.surfaceHover

                Behavior on color { ColorAnimation { duration: 140 } }
            }

            TextArea {
                id: input

                anchors {
                    left: parent.left
                    right: sendButton.left
                    top: parent.top
                    bottom: parent.bottom
                    topMargin: 9
                    rightMargin: 8
                }
                enabled: chat.ready && !chat.busy
                color: chat.theme.textPrimary
                placeholderText: chat.busy ? "NOVA DENKT ..." : "FRAG ETWAS ..."
                placeholderTextColor: chat.theme.textDisabled
                selectionColor: chat.theme.accentMuted
                selectedTextColor: chat.theme.textBright
                background: null
                wrapMode: TextEdit.Wrap
                font.family: chat.fontFamily
                font.pixelSize: 11
                Keys.onReturnPressed: event => {
                    if (event.modifiers & Qt.ShiftModifier) {
                        event.accepted = false
                    } else {
                        chat.send()
                        event.accepted = true
                    }
                }
            }

            IconButton {
                id: sendButton
                anchors {
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                enabled: chat.ready && !chat.busy && input.text.trim().length > 0
                opacity: enabled ? 1 : 0.35
                label: "󰒊"
                tooltip: "Senden"
                onClicked: chat.send()
            }
        }
    }

    component IconButton: Item {
        id: iconButton

        required property string label
        property string tooltip: ""
        signal clicked

        width: 30
        height: 30
        implicitWidth: 30
        implicitHeight: 30

        Text {
            anchors.centerIn: parent
            text: iconButton.label
            color: iconMouse.containsMouse
                ? chat.theme.accent : chat.theme.textMuted
            font.family: chat.fontFamily
            font.pixelSize: 14

            transform: Translate {
                y: iconMouse.containsMouse ? -1 : 0
                Behavior on y { NumberAnimation { duration: 120 } }
            }
            Behavior on color { ColorAnimation { duration: 120 } }
        }

        MouseArea {
            id: iconMouse
            anchors.fill: parent
            enabled: iconButton.enabled
            hoverEnabled: true
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: iconButton.clicked()
        }
    }

    component LinkButton: Item {
        id: linkButton

        required property string label
        signal clicked

        width: linkLabel.implicitWidth + 12
        height: 34

        Text {
            id: linkLabel
            anchors.centerIn: parent
            text: linkButton.label
            color: linkMouse.containsMouse
                ? chat.theme.accent : chat.theme.textSecondary
            font.family: chat.fontFamily
            font.pixelSize: 10
            font.weight: Font.Bold

            Behavior on color { ColorAnimation { duration: 120 } }
        }

        Rectangle {
            anchors {
                bottom: parent.bottom
                horizontalCenter: parent.horizontalCenter
            }
            width: linkMouse.containsMouse ? parent.width : 18
            height: 1
            color: chat.theme.accentMuted

            Behavior on width {
                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
            }
        }

        MouseArea {
            id: linkMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: linkButton.clicked()
        }
    }
}

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Io

Item {
    id: mail

    required property var theme
    property bool active: false
    property bool configured: false
    property bool ready: false
    property bool checking: false
    property int unread: 0
    property string mailState: "checking"
    property string statusText: "PRÜFE GMX"
    readonly property bool hasUnread: ready && unread > 0
    readonly property string fontFamily: "JetBrainsMono Nerd Font"
    readonly property string helperPath:
        "/home/mika/.config/quickshell/scripts/gmx-mail.py"

    implicitHeight: hasUnread ? 88 : configured ? 34 : 0
    visible: configured || hasUnread

    function refresh(): void {
        if (probe.running)
            return
        mail.checking = true
        probe.command = ["/usr/bin/python3", mail.helperPath]
        probe.running = true
    }

    function applyResult(raw): void {
        mail.checking = false
        try {
            const result = JSON.parse(raw)
            mail.ready = !!result.ok
            mail.configured = !!result.configured
            mail.mailState = result.state || "offline"
            mail.statusText = result.message || "GMX NICHT VERFÜGBAR"
            mail.unread = Number(result.unread || 0)
        } catch (error) {
            mail.ready = false
            mail.mailState = "offline"
            mail.statusText = "GMX NICHT VERFÜGBAR"
        }
    }

    onActiveChanged: if (active) refresh()

    Process {
        id: probe

        stdout: StdioCollector {
            onStreamFinished: mail.applyResult(text)
        }
    }

    Timer {
        interval: 1800000
        running: mail.active
        repeat: true
        triggeredOnStart: true
        onTriggered: mail.refresh()
    }

    RowLayout {
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            topMargin: mail.hasUnread ? 8 : 0
        }
        spacing: 10

        Text {
            Layout.preferredWidth: 30
            Layout.alignment: Qt.AlignTop
            text: "󰇮"
            color: mail.hasUnread ? mail.theme.accent : mail.theme.textMuted
            horizontalAlignment: Text.AlignHCenter
            font.family: mail.fontFamily
            font.pixelSize: 18
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            RowLayout {
                Layout.fillWidth: true
                spacing: 7

                Text {
                    Layout.fillWidth: true
                    text: mail.hasUnread ? "GMX  ·  NEUE E-MAIL"
                        : mail.ready ? "GMX  ·  KEINE NEUEN E-MAILS"
                            : mail.statusText
                    color: mail.hasUnread
                        ? mail.theme.textPrimary : mail.theme.textMuted
                    elide: Text.ElideRight
                    font.family: mail.fontFamily
                    font.pixelSize: mail.hasUnread ? 10 : 8
                    font.weight: Font.Bold
                }

                Text {
                    visible: mail.hasUnread
                    text: "NEU"
                    color: mail.theme.textSecondary
                    font.family: mail.fontFamily
                    font.pixelSize: 9
                    font.weight: Font.Bold
                }
            }

            Row {
                visible: mail.hasUnread
                spacing: 6

                Rectangle {
                    width: 104
                    height: 7
                    radius: 3
                    color: mail.theme.outlineSubtle
                    opacity: 0.42
                }

                Rectangle {
                    width: 58
                    height: 7
                    radius: 3
                    color: mail.theme.outlineSubtle
                    opacity: 0.24
                }
            }

            Row {
                visible: mail.hasUnread
                spacing: 6

                Rectangle {
                    width: 156
                    height: 6
                    radius: 3
                    color: mail.theme.outlineSubtle
                    opacity: 0.22
                }

                Text {
                    text: "PRIVAT"
                    color: mail.theme.textDisabled
                    font.family: mail.fontFamily
                    font.pixelSize: 7
                    font.weight: Font.Bold
                }
            }
        }

        Item {
            Layout.preferredWidth: 30
            Layout.preferredHeight: 30
            Layout.alignment: Qt.AlignTop

            Text {
                anchors.centerIn: parent
                text: "󰑐"
                color: refreshMouse.containsMouse
                    ? mail.theme.accent : mail.theme.textMuted
                font.family: mail.fontFamily
                font.pixelSize: 13
            }

            MouseArea {
                id: refreshMouse
                anchors.fill: parent
                enabled: !mail.checking
                hoverEnabled: true
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: mail.refresh()
            }
        }
    }

    Rectangle {
        visible: mail.hasUnread
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            leftMargin: 40
            rightMargin: 12
        }
        height: 1
        color: mail.theme.surfaceHover
    }
}

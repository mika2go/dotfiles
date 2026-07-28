import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Scope {
    id: overlay

    required property var theme
    property var overlayScreen
    property bool shown: false
    property bool suppressed: false

    readonly property var sections: [
        {
            title: "FENSTER",
            entries: [
                ["Super + Linksklick", "Fenster bewegen"],
                ["Super + Rechtsklick", "Fenster skalieren"],
                ["Super + V", "Floating umschalten"],
                ["Super + Q", "Fenster schließen"],
                ["Super + Shift + C", "Fenster zentrieren"],
                ["Super + P", "Pseudo-Tiling"],
                ["Super + J", "Split wechseln"]
            ]
        },
        {
            title: "NAVIGATION",
            entries: [
                ["Super + ← ↑ ↓ →", "Fokus bewegen"],
                ["Super + 1–7", "Workspace öffnen"],
                ["Super + Mausrad", "Workspace wechseln"],
                ["Super + Shift + 1–7", "Fenster verschieben"],
                ["Super + S", "Scratchpad öffnen"]
            ]
        },
        {
            title: "APPS & TOOLS",
            entries: [
                ["Super + Enter", "Terminal"],
                ["Super + D", "App-Launcher"],
                ["Super + E / F", "Mini-Explorer"],
                ["Super + W", "Dynamic Island"],
                ["Super + B", "Wallpaper wechseln"],
                ["Super + Shift + D", "Wetter & Kalender"],
                ["Super + L", "Bildschirm sperren"],
                ["Super + Shift + S", "Screenshot"],
                ["Alt + Shift + S", "Bildschirmaufnahme"],
                ["Super + I", "Diese Übersicht"],
                ["Super + M", "Power-Menü"]
            ]
        },
        {
            title: "MEDIEN",
            entries: [
                ["Lautstärketasten", "Lauter / leiser / stumm"],
                ["Medientasten", "Zurück / Play / Weiter"],
                ["Helligkeitstasten", "Heller / dunkler"]
            ]
        }
    ]

    function open() {
        overlay.shown = true
        focusTimer.restart()
    }

    function close() {
        overlay.shown = false
    }

    function toggle() {
        overlay.shown ? overlay.close() : overlay.open()
    }

    IpcHandler {
        target: "keybinds"

        function toggle(): void {
            overlay.toggle()
        }

        function open(): void {
            overlay.open()
        }

        function close(): void {
            overlay.close()
        }
    }

    Timer {
        id: focusTimer
        interval: 40
        onTriggered: keyFocus.forceActiveFocus()
    }

    PanelWindow {
        id: overlayWindow
        screen: overlay.overlayScreen
        visible: overlay.overlayScreen !== null
            && !overlay.suppressed
            && overlay.shown
        color: "transparent"
        implicitWidth: 760
        implicitHeight: 700
        exclusiveZone: 0
        focusable: true

        anchors {
            top: true
        }

        margins {
            top: 105
        }

        Rectangle {
            id: card
            anchors.fill: parent
            color: overlay.theme.surfaceGlass
            radius: 22
            border.width: 1
            border.color: overlay.theme.surfaceActive
            clip: true

            transform: Scale {
                origin.x: card.width / 2
                origin.y: 0
                xScale: overlay.shown ? 1 : 0.96
                yScale: overlay.shown ? 1 : 0.96

                Behavior on xScale {
                    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                }
                Behavior on yScale {
                    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                }
            }

            ColumnLayout {
                anchors {
                    fill: parent
                    margins: 22
                }
                spacing: 14

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Rectangle {
                        width: 38
                        height: 38
                        radius: 11
                        color: overlay.theme.textPrimary

                        Text {
                            anchors.centerIn: parent
                            text: "⌘"
                            color: overlay.theme.surface
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 20
                            font.bold: true
                        }
                    }

                    Column {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            text: "Tastenkürzel"
                            color: overlay.theme.textPrimary
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 20
                            font.bold: true
                        }

                        Text {
                            text: "Super + I oder Escape zum Schließen"
                            color: overlay.theme.textMuted
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 11
                        }
                    }

                    Rectangle {
                        width: 34
                        height: 34
                        radius: 10
                        color: closeMouse.containsMouse ? overlay.theme.surfaceHover : overlay.theme.surfaceRaised

                        Text {
                            anchors.centerIn: parent
                            text: "×"
                            color: overlay.theme.textPrimary
                            font.pixelSize: 21
                        }

                        MouseArea {
                            id: closeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: overlay.close()
                        }

                        Behavior on color {
                            ColorAnimation { duration: 100 }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: overlay.theme.surfaceSubtle
                }

                GridLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    columns: 2
                    columnSpacing: 14
                    rowSpacing: 14

                    Repeater {
                        model: overlay.sections

                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.minimumHeight: 40 + modelData.entries.length * 27
                            color: overlay.theme.surfaceSubtle
                            radius: 15
                            border.width: 1
                            border.color: overlay.theme.surfaceHover

                            ColumnLayout {
                                anchors {
                                    fill: parent
                                    margins: 14
                                }
                                spacing: 3

                                Text {
                                    text: modelData.title
                                    color: overlay.theme.textMuted
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 10
                                    font.bold: true
                                    font.letterSpacing: 1.2
                                }

                                Repeater {
                                    model: modelData.entries

                                    delegate: RowLayout {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 24
                                        spacing: 8

                                        Rectangle {
                                            Layout.preferredWidth: 142
                                            Layout.preferredHeight: 24
                                            radius: 7
                                            color: overlay.theme.surfaceHover

                                            Text {
                                                anchors.centerIn: parent
                                                text: modelData[0]
                                                color: overlay.theme.textPrimary
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 10
                                                font.bold: true
                                            }
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData[1]
                                            color: overlay.theme.textSecondary
                                            elide: Text.ElideRight
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 10
                                        }
                                    }
                                }

                            }
                        }
                    }
                }
            }
        }

        Item {
            id: keyFocus
            anchors.fill: parent
            focus: overlay.shown

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    overlay.close()
                    event.accepted = true
                }
            }
        }
    }
}

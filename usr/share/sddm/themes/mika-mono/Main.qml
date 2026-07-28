import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Effects
import QtQuick.Layouts 1.15

Rectangle {
    id: root

    width: 1920
    height: 1080
    color: "#050505"

    readonly property color ink: "#f4f4f4"
    readonly property color muted: "#929292"
    readonly property color panel: "#ed111111"
    readonly property color panelRaised: "#f51a1a1a"
    readonly property color line: "#353535"
    readonly property real uiScale: Math.min(width / 1920, height / 1080)
    readonly property bool showSidePanels: width >= 1180
    property date now: new Date()
    property string statusText: "BEREIT"
    property bool loginPending: false

    function tryLogin() {
        if (username.text.length === 0) {
            statusText = "BENUTZERNAME FEHLT"
            username.forceActiveFocus()
            return
        }

        if (password.text.length === 0) {
            statusText = "PASSWORT EINGEBEN"
            password.forceActiveFocus()
            return
        }

        loginPending = true
        statusText = "ANMELDUNG LÄUFT"
        sddm.login(username.text, password.text, session.currentIndex)
    }

    Image {
        anchors.fill: parent
        source: "wallpaper.png"
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        opacity: 0.55
    }

    Rectangle {
        anchors.fill: parent
        color: "#b8000000"
    }

    Repeater {
        model: 15

        Rectangle {
            required property int index
            x: index * root.width / 14
            width: 1
            height: root.height
            color: "#0dffffff"
        }
    }

    Repeater {
        model: 9

        Rectangle {
            required property int index
            y: index * root.height / 8
            width: root.width
            height: 1
            color: "#0dffffff"
        }
    }

    Rectangle {
        id: shell
        width: Math.min(root.width - 72 * root.uiScale, 1560 * root.uiScale)
        height: Math.min(root.height - 72 * root.uiScale, 850 * root.uiScale)
        anchors.centerIn: parent
        radius: 34 * root.uiScale
        color: "#f2080808"
        border.width: Math.max(1, root.uiScale)
        border.color: "#72ffffff"
        clip: true
        opacity: 0
        scale: 0.975

        Component.onCompleted: {
            opacity = 1
            scale = 1
        }

        Behavior on opacity {
            NumberAnimation { duration: 480; easing.type: Easing.OutCubic }
        }

        Behavior on scale {
            NumberAnimation { duration: 560; easing.type: Easing.OutBack }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 10 * root.uiScale
            radius: shell.radius - 10 * root.uiScale
            color: "transparent"
            border.width: 1
            border.color: "#282828"
        }

        RowLayout {
            id: content
            anchors.fill: parent
            anchors.margins: 24 * root.uiScale
            spacing: 18 * root.uiScale

            ColumnLayout {
                visible: root.showSidePanels
                Layout.preferredWidth: 330 * root.uiScale
                Layout.fillHeight: true
                spacing: 12 * root.uiScale

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 176 * root.uiScale
                    radius: 24 * root.uiScale
                    color: root.panelRaised
                    border.width: 1
                    border.color: root.line

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 22 * root.uiScale
                        spacing: 3 * root.uiScale

                        RowLayout {
                            Layout.fillWidth: true

                            Text {
                                text: "LOCAL SESSION"
                                color: root.muted
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 11 * root.uiScale
                                font.weight: Font.DemiBold
                                font.letterSpacing: 1.4
                            }

                            Item { Layout.fillWidth: true }

                            Rectangle {
                                Layout.preferredWidth: 9 * root.uiScale
                                Layout.preferredHeight: 9 * root.uiScale
                                radius: width / 2
                                color: root.ink
                            }
                        }

                        Item { Layout.preferredHeight: 6 * root.uiScale }

                        Text {
                            text: sddm.hostName ? sddm.hostName.toUpperCase() : "MIKAROOT"
                            color: root.ink
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 29 * root.uiScale
                            font.weight: Font.Bold
                            font.letterSpacing: -1
                        }

                        Text {
                            text: Qt.formatDateTime(root.now, "dddd, d. MMMM yyyy")
                            color: root.muted
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 11 * root.uiScale
                        }

                        Item { Layout.fillHeight: true }

                        Text {
                            text: "SDDM  /  QT6  /  MONO"
                            color: root.ink
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 10 * root.uiScale
                            font.weight: Font.Medium
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 262 * root.uiScale
                    radius: 18 * root.uiScale
                    color: root.panel
                    border.width: 1
                    border.color: root.line

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 20 * root.uiScale
                        spacing: 9 * root.uiScale

                        RowLayout {
                            Layout.fillWidth: true

                            Rectangle {
                                Layout.preferredWidth: 28 * root.uiScale
                                Layout.preferredHeight: 28 * root.uiScale
                                radius: 8 * root.uiScale
                                color: root.ink

                                Text {
                                    anchors.centerIn: parent
                                    text: ">"
                                    color: "#080808"
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 12 * root.uiScale
                                    font.weight: Font.Bold
                                }
                            }

                            Text {
                                text: "mikafetch.sh"
                                color: root.ink
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 11 * root.uiScale
                            }

                            Item { Layout.fillWidth: true }

                            Text {
                                text: "󰣇"
                                color: root.ink
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 25 * root.uiScale
                            }
                        }

                        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: root.line }

                        Item { Layout.preferredHeight: 4 * root.uiScale }

                        Text {
                            Layout.fillWidth: true
                            text: "OS   : ARCH LINUX\nWM   : HYPRLAND\nUSER : " + (username.text || "MIKA").toUpperCase() + "\nDM   : SDDM\nMODE : MONOCHROME"
                            color: "#d7d7d7"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 11 * root.uiScale
                            lineHeight: 1.45
                        }

                        Item { Layout.fillHeight: true }

                        Row {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 10 * root.uiScale

                            Repeater {
                                model: ["#f4f4f4", "#cfcfcf", "#a4a4a4", "#797979", "#555555", "#333333", "#151515"]

                                Rectangle {
                                    required property string modelData
                                    width: 19 * root.uiScale
                                    height: width
                                    radius: width / 2
                                    color: modelData
                                    border.width: modelData === "#151515" ? 1 : 0
                                    border.color: "#4a4a4a"
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 24 * root.uiScale
                    color: root.panelRaised
                    border.width: 1
                    border.color: root.line
                    clip: true

                    Image {
                        anchors.fill: parent
                        source: "wallpaper.png"
                        fillMode: Image.PreserveAspectCrop
                        opacity: 0.28
                    }

                    Rectangle { anchors.fill: parent; color: "#8d000000" }

                    ColumnLayout {
                        anchors.centerIn: parent
                        width: parent.width - 40 * root.uiScale
                        spacing: 7 * root.uiScale

                        Text {
                            Layout.fillWidth: true
                            text: "WELCOME BACK"
                            horizontalAlignment: Text.AlignHCenter
                            color: root.ink
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 14 * root.uiScale
                            font.weight: Font.Bold
                            font.letterSpacing: 2
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "authentication required"
                            horizontalAlignment: Text.AlignHCenter
                            color: root.muted
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 10 * root.uiScale
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.preferredWidth: 610 * root.uiScale
                Layout.maximumWidth: 720 * root.uiScale
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 10 * root.uiScale

                Item { Layout.fillHeight: true }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: Qt.formatDateTime(root.now, "HHmm")
                    color: root.ink
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 128 * root.uiScale
                    font.weight: Font.Black
                    font.letterSpacing: -10 * root.uiScale
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: -22 * root.uiScale
                    text: Qt.formatDateTime(root.now, "dddd  •  dd MMM").toUpperCase()
                    color: root.ink
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 12 * root.uiScale
                    font.weight: Font.Bold
                    font.letterSpacing: 1
                }

                Rectangle {
                    id: avatarFrame
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 26 * root.uiScale
                    Layout.preferredWidth: 168 * root.uiScale
                    Layout.preferredHeight: 168 * root.uiScale
                    radius: width / 2
                    color: root.panelRaised
                    border.width: 2 * root.uiScale
                    border.color: root.ink

                    Item {
                        id: avatarViewport
                        anchors.fill: parent
                        anchors.margins: 7 * root.uiScale

                        Image {
                            id: avatarSource
                            anchors.fill: parent
                            source: "avatar.jpg"
                            fillMode: Image.PreserveAspectCrop
                            smooth: true
                            mipmap: true
                            asynchronous: true
                            cache: true
                            sourceSize.width: 336
                            sourceSize.height: 336
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                maskEnabled: true
                                maskSource: avatarMask
                                maskThresholdMin: 0.5
                                maskSpreadAtMin: 1.0
                            }
                        }

                        Rectangle {
                            id: avatarMask
                            anchors.fill: parent
                            radius: width / 2
                            color: "white"
                            visible: false
                            layer.enabled: true
                            layer.smooth: true
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: "transparent"
                            border.width: 1
                            border.color: "#707070"
                        }
                    }
                }

                TextField {
                    id: username
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 18 * root.uiScale
                    Layout.preferredWidth: Math.min(440 * root.uiScale, parent.width - 24 * root.uiScale)
                    Layout.preferredHeight: 42 * root.uiScale
                    text: userModel.lastUser
                    placeholderText: "Benutzername"
                    color: root.ink
                    placeholderTextColor: root.muted
                    horizontalAlignment: Text.AlignHCenter
                    selectByMouse: true
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11 * root.uiScale
                    font.weight: Font.DemiBold
                    onAccepted: password.forceActiveFocus()

                    background: Rectangle {
                        radius: height / 2
                        color: "#d90d0d0d"
                        border.width: 1
                        border.color: username.activeFocus ? root.ink : root.line

                        Behavior on border.color { ColorAnimation { duration: 140 } }
                    }
                }

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 2 * root.uiScale
                    Layout.preferredWidth: Math.min(500 * root.uiScale, parent.width - 12 * root.uiScale)
                    Layout.preferredHeight: 58 * root.uiScale
                    radius: height / 2
                    color: root.panelRaised
                    border.width: 1
                    border.color: password.activeFocus ? root.ink : root.line

                    Behavior on border.color { ColorAnimation { duration: 140 } }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 21 * root.uiScale
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.loginPending ? "󰔟" : "󰌾"
                        color: root.muted
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 17 * root.uiScale
                    }

                    TextField {
                        id: password
                        anchors.left: parent.left
                        anchors.leftMargin: 56 * root.uiScale
                        anchors.right: loginArrow.left
                        anchors.rightMargin: 9 * root.uiScale
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        placeholderText: "Passwort"
                        echoMode: TextInput.Password
                        passwordCharacter: "●"
                        color: root.ink
                        placeholderTextColor: root.muted
                        selectByMouse: true
                        leftPadding: 0
                        rightPadding: 0
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 12 * root.uiScale
                        onTextEdited: {
                            root.statusText = "BEREIT"
                            root.loginPending = false
                        }
                        onAccepted: root.tryLogin()

                        background: Rectangle { color: "transparent" }
                    }

                    Rectangle {
                        id: loginArrow
                        width: 44 * root.uiScale
                        height: width
                        radius: width / 2
                        anchors.right: parent.right
                        anchors.rightMargin: 7 * root.uiScale
                        anchors.verticalCenter: parent.verticalCenter
                        color: password.text.length > 0 ? root.ink : "#303030"
                        scale: arrowMouse.pressed ? 0.88 : 1

                        Behavior on color { ColorAnimation { duration: 140 } }
                        Behavior on scale { NumberAnimation { duration: 100 } }

                        Text {
                            anchors.centerIn: parent
                            text: "󰁔"
                            color: password.text.length > 0 ? "#080808" : root.muted
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 19 * root.uiScale
                        }

                        MouseArea {
                            id: arrowMouse
                            anchors.fill: parent
                            cursorShape: password.text.length > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: root.tryLogin()
                        }
                    }
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredHeight: 20 * root.uiScale
                    text: root.statusText
                    color: root.statusText === "BEREIT" ? root.muted : root.ink
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 9 * root.uiScale
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1.2
                }

                Item { Layout.fillHeight: true }
            }

            ColumnLayout {
                visible: root.showSidePanels
                Layout.preferredWidth: 330 * root.uiScale
                Layout.fillHeight: true
                spacing: 12 * root.uiScale

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 128 * root.uiScale
                    radius: 24 * root.uiScale
                    color: root.panelRaised
                    border.width: 1
                    border.color: root.line

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 12 * root.uiScale
                        spacing: 8 * root.uiScale

                        Repeater {
                            model: [
                                { icon: "󰣇", label: "ARCH", value: "OS" },
                                { icon: "󰖲", label: "HYPR", value: "WM" },
                                { icon: "󰍹", label: "QT6", value: "UI" }
                            ]

                            Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: 18 * root.uiScale
                                color: "#161616"
                                border.width: 1
                                border.color: "#404040"

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 2 * root.uiScale

                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: modelData.icon
                                        color: root.muted
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 17 * root.uiScale
                                    }

                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: modelData.label
                                        color: root.ink
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 12 * root.uiScale
                                        font.weight: Font.Bold
                                    }

                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: modelData.value
                                        color: root.muted
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 8 * root.uiScale
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 190 * root.uiScale
                    radius: 18 * root.uiScale
                    color: root.panel
                    border.width: 1
                    border.color: root.line

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 18 * root.uiScale
                        spacing: 9 * root.uiScale

                        Text {
                            text: "SESSION"
                            color: root.muted
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 10 * root.uiScale
                            font.weight: Font.DemiBold
                            font.letterSpacing: 1.2
                        }

                        ComboBox {
                            id: session
                            Layout.fillWidth: true
                            Layout.preferredHeight: 50 * root.uiScale
                            model: sessionModel
                            textRole: "name"
                            currentIndex: sessionModel.lastIndex
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 10 * root.uiScale

                            contentItem: Text {
                                leftPadding: 16 * root.uiScale
                                rightPadding: 32 * root.uiScale
                                text: session.displayText
                                color: root.ink
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                                font: session.font
                            }

                            background: Rectangle {
                                radius: 14 * root.uiScale
                                color: "#171717"
                                border.width: 1
                                border.color: session.activeFocus ? root.ink : root.line
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "Die gewählte Sitzung wird nach erfolgreicher Authentifizierung gestartet."
                            color: root.muted
                            wrapMode: Text.WordWrap
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 9 * root.uiScale
                            lineHeight: 1.25
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 24 * root.uiScale
                    color: root.panelRaised
                    border.width: 1
                    border.color: root.line

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 19 * root.uiScale
                        spacing: 12 * root.uiScale

                        RowLayout {
                            Layout.fillWidth: true

                            Text {
                                text: "LOGIN STATUS"
                                color: root.muted
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 10 * root.uiScale
                                font.weight: Font.DemiBold
                                font.letterSpacing: 1.2
                            }

                            Item { Layout.fillWidth: true }

                            Text {
                                text: "03"
                                color: root.muted
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 10 * root.uiScale
                            }
                        }

                        Repeater {
                            model: [
                                { icon: "󰌾", title: "AUTHENTIFIZIERUNG", detail: "PAM / SDDM" },
                                { icon: "󰍹", title: "DISPLAY SERVER", detail: "X11 GREETER" },
                                { icon: "󰖲", title: "DESKTOP SESSION", detail: "HYPRLAND" }
                            ]

                            Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredHeight: 68 * root.uiScale
                                radius: 14 * root.uiScale
                                color: "#121212"
                                border.width: 1
                                border.color: "#2c2c2c"

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 13 * root.uiScale
                                    spacing: 12 * root.uiScale

                                    Text {
                                        text: modelData.icon
                                        color: root.ink
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 18 * root.uiScale
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1

                                        Text {
                                            text: modelData.title
                                            color: root.ink
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 9 * root.uiScale
                                            font.weight: Font.DemiBold
                                        }

                                        Text {
                                            text: modelData.detail
                                            color: root.muted
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 8 * root.uiScale
                                        }
                                    }

                                    Text {
                                        text: "●"
                                        color: root.ink
                                        font.pixelSize: 9 * root.uiScale
                                    }
                                }
                            }
                        }

                        Item { Layout.fillHeight: true }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48 * root.uiScale
                    spacing: 9 * root.uiScale

                    Repeater {
                        model: [
                            { icon: "󰜉", hint: "Neu starten", action: "reboot" },
                            { icon: "󰐥", hint: "Ausschalten", action: "poweroff" }
                        ]

                        Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 14 * root.uiScale
                            color: powerMouse.containsMouse ? root.ink : root.panelRaised
                            border.width: 1
                            border.color: powerMouse.containsMouse ? root.ink : root.line

                            Behavior on color { ColorAnimation { duration: 130 } }

                            Row {
                                anchors.centerIn: parent
                                spacing: 9 * root.uiScale

                                Text {
                                    text: modelData.icon
                                    color: powerMouse.containsMouse ? "#080808" : root.ink
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 14 * root.uiScale
                                }

                                Text {
                                    text: modelData.hint.toUpperCase()
                                    color: powerMouse.containsMouse ? "#080808" : root.muted
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 8 * root.uiScale
                                    font.weight: Font.DemiBold
                                }
                            }

                            MouseArea {
                                id: powerMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (modelData.action === "reboot")
                                        sddm.reboot()
                                    else
                                        sddm.powerOff()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }

    Connections {
        target: sddm

        function onLoginFailed() {
            root.loginPending = false
            root.statusText = "PASSWORT ODER BENUTZERNAME FALSCH"
            password.text = ""
            password.forceActiveFocus()
        }
    }

    Component.onCompleted: {
        if (username.text.length > 0)
            password.forceActiveFocus()
        else
            username.forceActiveFocus()
    }
}

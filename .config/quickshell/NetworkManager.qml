pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: manager

    required property var theme
    property var managerScreen
    property bool shown: false
    property bool windowVisible: false
    property bool suppressed: false
    property bool wifiEnabled: false
    property bool busy: false
    property real offsetScale: shown ? 0 : 1
    property var networks: []
    property var savedConnections: []
    property string activeSsid: ""
    property string activeConnection: ""
    property string statusText: "NETZWERKE WERDEN GELADEN"
    property string passwordSsid: ""

    readonly property real morphProgress: 1 - offsetScale
    readonly property real surfaceWidth: 430
    readonly property real surfaceHeight: Math.min(590,
        Math.max(500, (managerScreen?.height ?? 690) - 70))
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
        manager.windowVisible = true
        manager.shown = true
        manager.refresh()
        focusTimer.restart()
    }

    function close(): void {
        if (!manager.windowVisible)
            return
        manager.shown = false
        manager.passwordSsid = ""
        passwordInput.text = ""
        closeTimer.restart()
    }

    function toggle(): void {
        manager.shown ? manager.close() : manager.open()
    }

    function splitNmcliLine(line): list<string> {
        const fields = []
        let field = ""
        let escaped = false
        for (let i = 0; i < line.length; ++i) {
            const character = line[i]
            if (escaped) {
                field += character
                escaped = false
            } else if (character === "\\") {
                escaped = true
            } else if (character === ":") {
                fields.push(field)
                field = ""
            } else {
                field += character
            }
        }
        if (escaped)
            field += "\\"
        fields.push(field)
        return fields
    }

    function parseProbe(raw): void {
        const lines = raw.split("\n")
        const nextSaved = []
        const strongestBySsid = ({})
        let section = "status"
        let nextWifiEnabled = false
        let nextActiveConnection = ""

        for (let i = 0; i < lines.length; ++i) {
            const line = lines[i].trim()
            if (line === "__SAVED__") {
                section = "saved"
                continue
            }
            if (line === "__APS__") {
                section = "aps"
                continue
            }
            if (line.length === 0)
                continue

            if (section === "status") {
                const values = manager.splitNmcliLine(line)
                nextWifiEnabled = values[0] === "enabled"
                nextActiveConnection = values.length > 1 ? values[1] : ""
            } else if (section === "saved") {
                const values = manager.splitNmcliLine(line)
                if (values.length > 1 && values[1] === "802-11-wireless")
                    nextSaved.push(values[0])
            } else {
                const values = manager.splitNmcliLine(line)
                if (values.length < 4 || values[1].length === 0)
                    continue
                const signal = Math.max(0, Math.min(100, Number(values[2]) || 0))
                const entry = {
                    active: values[0] === "*",
                    ssid: values[1],
                    signal: signal,
                    security: values[3],
                    saved: nextSaved.indexOf(values[1]) >= 0
                }
                const previous = strongestBySsid[entry.ssid]
                if (!previous || entry.active || entry.signal > previous.signal)
                    strongestBySsid[entry.ssid] = entry
            }
        }

        const nextNetworks = Object.keys(strongestBySsid)
            .map(ssid => strongestBySsid[ssid])
            .sort((a, b) => {
                if (a.active !== b.active)
                    return a.active ? -1 : 1
                if (a.saved !== b.saved)
                    return a.saved ? -1 : 1
                return b.signal - a.signal
            })

        manager.wifiEnabled = nextWifiEnabled
        manager.activeConnection = nextActiveConnection
        manager.networks = nextNetworks
        manager.savedConnections = nextSaved
        manager.activeSsid = ""
        for (const network of nextNetworks) {
            if (network.active) {
                manager.activeSsid = network.ssid
                break
            }
        }
        manager.statusText = !nextWifiEnabled
            ? "FUNKNETZ IST DEAKTIVIERT"
            : (manager.activeSsid.length > 0
                ? "VERBUNDEN  /  " + manager.activeSsid
                : nextNetworks.length + " NETZWERKE GEFUNDEN")
        manager.busy = false
    }

    function refresh(): void {
        if (probe.running)
            return
        manager.busy = true
        manager.statusText = "NETZWERKE WERDEN GESCANNT"
        probe.running = true
    }

    function signalIcon(signal): string {
        if (signal >= 75)
            return "󰤨"
        if (signal >= 50)
            return "󰤥"
        if (signal >= 25)
            return "󰤢"
        return "󰤟"
    }

    function isSecured(security): bool {
        return security.length > 0 && security !== "--"
    }

    function runAction(command, pendingSsid, asksForPassword): void {
        if (action.running)
            return
        manager.busy = true
        manager.statusText = "VERBINDUNG WIRD HERGESTELLT"
        action.pendingSsid = pendingSsid
        action.asksForPassword = asksForPassword
        action.command = command
        action.running = true
    }

    function selectNetwork(network): void {
        if (network.active || manager.busy)
            return
        if (manager.isSecured(network.security) && !network.saved) {
            manager.passwordSsid = network.ssid
            passwordInput.text = ""
            Qt.callLater(passwordInput.forceActiveFocus)
            return
        }
        manager.passwordSsid = ""
        manager.runAction(["nmcli", "device", "wifi", "connect", network.ssid],
            network.ssid, manager.isSecured(network.security))
    }

    function connectWithPassword(): void {
        if (manager.passwordSsid.length === 0 || passwordInput.text.length === 0)
            return
        manager.runAction([
            "nmcli", "device", "wifi", "connect", manager.passwordSsid,
            "password", passwordInput.text
        ], manager.passwordSsid, false)
    }

    function toggleWifi(): void {
        if (action.running)
            return
        manager.passwordSsid = ""
        manager.runAction([
            "nmcli", "radio", "wifi", manager.wifiEnabled ? "off" : "on"
        ], "", false)
    }

    IpcHandler {
        target: "network"

        function toggle(): void { manager.toggle() }
        function open(): void { manager.open() }
        function close(): void { manager.close() }
        function refresh(): void { manager.refresh() }
    }

    Process {
        id: probe
        command: ["bash", "-lc",
            "wifi=$(nmcli -t -f WIFI general 2>/dev/null); "
            + "active=$(nmcli -t --escape yes -f NAME,TYPE connection show --active 2>/dev/null "
            + "| awk -F: '$2 == \"802-11-wireless\" {print $1; exit}'); "
            + "printf '%s:%s\\n__SAVED__\\n' \"$wifi\" \"$active\"; "
            + "nmcli -t --escape yes -f NAME,TYPE connection show 2>/dev/null; "
            + "printf '__APS__\\n'; "
            + "nmcli -t --escape yes -f IN-USE,SSID,SIGNAL,SECURITY "
            + "device wifi list --rescan auto 2>/dev/null"]

        stdout: StdioCollector {
            onStreamFinished: manager.parseProbe(text)
        }

        onExited: exitCode => {
            if (exitCode !== 0) {
                manager.busy = false
                manager.statusText = "NETWORKMANAGER NICHT ERREICHBAR"
            }
        }
    }

    Process {
        id: action

        property string pendingSsid: ""
        property bool asksForPassword: false

        onExited: exitCode => {
            manager.busy = false
            if (exitCode === 0) {
                manager.passwordSsid = ""
                passwordInput.text = ""
                manager.statusText = "NETZWERKSTATUS WIRD AKTUALISIERT"
                refreshDelay.restart()
            } else if (action.asksForPassword && action.pendingSsid.length > 0) {
                manager.passwordSsid = action.pendingSsid
                manager.statusText = "PASSWORT ERFORDERLICH"
                Qt.callLater(passwordInput.forceActiveFocus)
            } else {
                manager.statusText = "VERBINDUNG FEHLGESCHLAGEN"
                refreshDelay.restart()
            }
        }
    }

    Timer {
        id: refreshDelay
        interval: 700
        onTriggered: manager.refresh()
    }

    Timer {
        interval: 8000
        running: manager.shown
        repeat: true
        onTriggered: manager.refresh()
    }

    Timer {
        id: closeTimer
        interval: 515
        onTriggered: {
            if (!manager.shown)
                manager.windowVisible = false
        }
    }

    Timer {
        id: focusTimer
        interval: 40
        onTriggered: keyFocus.forceActiveFocus()
    }

    component IconButton: Rectangle {
        id: button

        property string icon: ""
        property bool active: false
        signal clicked()

        implicitWidth: 34
        implicitHeight: 34
        radius: width / 2
        color: active || buttonMouse.containsMouse ? manager.theme.textPrimary : manager.theme.surfaceRaised

        Behavior on color { ColorAnimation { duration: 120 } }

        Text {
            anchors.centerIn: parent
            text: button.icon
            color: button.active || buttonMouse.containsMouse
                ? manager.theme.surface : manager.theme.textPrimary
            font.family: manager.fontFamily
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
        id: managerWindow

        screen: manager.managerScreen
        visible: manager.managerScreen !== null
            && !manager.suppressed && manager.windowVisible
        color: "transparent"
        implicitWidth: manager.surfaceWidth
        implicitHeight: manager.surfaceHeight + 5
        exclusiveZone: 0
        focusable: manager.shown
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell:mono-network-manager"

        anchors { bottom: true; right: true }
        mask: Region { item: managerCard }

        Item {
            id: managerCard
            width: manager.surfaceWidth
            height: manager.surfaceHeight
            anchors {
                right: parent.right
                bottom: parent.bottom
                bottomMargin: (-height - 5) * manager.offsetScale
            }
            opacity: manager.morphProgress
            visible: manager.offsetScale < 1
            clip: true

            ColumnLayout {
                anchors {
                    fill: parent
                    leftMargin: 22
                    rightMargin: 22
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
                            text: "NETWORK MANAGER"
                            color: manager.theme.textPrimary
                            font.family: manager.fontFamily
                            font.pixelSize: 17
                            font.weight: Font.Bold
                            font.letterSpacing: 0.8
                        }

                        Text {
                            Layout.fillWidth: true
                            text: manager.statusText
                            color: manager.theme.textMuted
                            elide: Text.ElideRight
                            font.family: manager.fontFamily
                            font.pixelSize: 8
                            font.weight: Font.DemiBold
                            font.letterSpacing: 0.5
                        }
                    }

                    IconButton {
                        icon: manager.busy ? "󰑐" : "󰑓"
                        active: manager.busy
                        onClicked: manager.refresh()

                        RotationAnimator on rotation {
                            running: manager.busy
                            loops: Animation.Infinite
                            from: 0
                            to: 360
                            duration: 850
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 112
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
                                color: manager.wifiEnabled ? manager.theme.textPrimary : manager.theme.surfaceHover

                                Text {
                                    anchors.centerIn: parent
                                    text: manager.wifiEnabled ? "󰖩" : "󰖪"
                                    color: manager.wifiEnabled ? manager.theme.surface : manager.theme.textMuted
                                    font.family: manager.fontFamily
                                    font.pixelSize: 18
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    text: "WLAN"
                                    color: manager.theme.textPrimary
                                    font.family: manager.fontFamily
                                    font.pixelSize: 10
                                    font.weight: Font.Bold
                                    font.letterSpacing: 0.7
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: manager.activeSsid.length > 0
                                        ? manager.activeSsid.toUpperCase()
                                        : "KEINE AKTIVE VERBINDUNG"
                                    color: manager.theme.textMuted
                                    elide: Text.ElideRight
                                    font.family: manager.fontFamily
                                    font.pixelSize: 8
                                }
                            }

                            Text {
                                text: manager.wifiEnabled ? "AN" : "AUS"
                                color: manager.theme.textPrimary
                                font.family: manager.fontFamily
                                font.pixelSize: 10
                                font.weight: Font.Bold
                            }

                            IconButton {
                                icon: manager.wifiEnabled ? "󰖩" : "󰖪"
                                active: manager.wifiEnabled
                                onClicked: manager.toggleWifi()
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 1
                            color: manager.theme.surfaceHover
                        }

                        Text {
                            Layout.fillWidth: true
                            text: manager.wifiEnabled
                                ? (manager.activeConnection.length > 0
                                    ? "PROFIL  /  " + manager.activeConnection.toUpperCase()
                                    : "BEREIT ZUM VERBINDEN")
                                : "FUNKMODUL DEAKTIVIERT"
                            color: manager.theme.textSecondary
                            elide: Text.ElideRight
                            font.family: manager.fontFamily
                            font.pixelSize: 7
                            font.weight: Font.DemiBold
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        text: "VERFÜGBARE NETZWERKE"
                        color: manager.theme.textSecondary
                        font.family: manager.fontFamily
                        font.pixelSize: 9
                        font.weight: Font.Bold
                        font.letterSpacing: 0.8
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: manager.networks.length.toString().padStart(2, "0")
                        color: manager.theme.textDisabled
                        font.family: manager.fontFamily
                        font.pixelSize: 7
                        font.weight: Font.Bold
                    }
                }

                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: width
                    contentHeight: networkColumn.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: networkColumn
                        width: parent.width
                        spacing: 0

                        Text {
                            visible: manager.networks.length === 0
                            width: parent.width
                            height: 82
                            text: manager.wifiEnabled
                                ? (manager.busy
                                    ? "NETZWERKE WERDEN GESCANNT"
                                    : "KEINE NETZWERKE GEFUNDEN")
                                : "WLAN IST AUSGESCHALTET"
                            color: manager.theme.textDisabled
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            font.family: manager.fontFamily
                            font.pixelSize: 8
                            font.weight: Font.DemiBold
                        }

                        Repeater {
                            model: manager.networks

                            Rectangle {
                                id: networkCard

                                required property var modelData

                                width: networkColumn.width
                                height: 64
                                color: networkMouse.containsMouse
                                    && !networkCard.modelData.active
                                    ? manager.theme.surfaceRaised : "transparent"
                                radius: 10

                                Behavior on color { ColorAnimation { duration: 100 } }

                                RowLayout {
                                    anchors {
                                        fill: parent
                                        leftMargin: 12
                                        rightMargin: 11
                                        topMargin: 8
                                        bottomMargin: 8
                                    }
                                    spacing: 11

                                    Rectangle {
                                        Layout.preferredWidth: 34
                                        Layout.preferredHeight: 34
                                        radius: width / 2
                                        color: networkCard.modelData.active
                                            ? manager.theme.textPrimary : manager.theme.surfaceHover

                                        Text {
                                            anchors.centerIn: parent
                                            text: manager.signalIcon(
                                                networkCard.modelData.signal)
                                            color: networkCard.modelData.active
                                                ? manager.theme.surface : manager.theme.textPrimary
                                            font.family: manager.fontFamily
                                            font.pixelSize: 16
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2

                                        Text {
                                            Layout.fillWidth: true
                                            text: networkCard.modelData.ssid.toUpperCase()
                                            color: manager.theme.textPrimary
                                            elide: Text.ElideRight
                                            font.family: manager.fontFamily
                                            font.pixelSize: 9
                                            font.weight: Font.Bold
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: networkCard.modelData.active
                                                ? "VERBUNDEN"
                                                : (networkCard.modelData.saved
                                                    ? "GESPEICHERT"
                                                    : (manager.isSecured(
                                                        networkCard.modelData.security)
                                                        ? networkCard.modelData.security
                                                        : "OFFEN"))
                                            color: networkCard.modelData.active
                                                ? manager.theme.textSecondary : manager.theme.textDisabled
                                            elide: Text.ElideRight
                                            font.family: manager.fontFamily
                                            font.pixelSize: 7
                                            font.weight: Font.DemiBold
                                        }
                                    }

                                    Text {
                                        text: networkCard.modelData.signal + "%"
                                        color: manager.theme.textMuted
                                        font.family: manager.fontFamily
                                        font.pixelSize: 8
                                        font.weight: Font.DemiBold
                                    }

                                    Text {
                                        text: manager.isSecured(
                                            networkCard.modelData.security)
                                            ? "󰌾" : "󰿆"
                                        color: manager.theme.textMuted
                                        font.family: manager.fontFamily
                                        font.pixelSize: 12
                                    }
                                }

                                MouseArea {
                                    id: networkMouse
                                    anchors.fill: parent
                                    enabled: !networkCard.modelData.active
                                        && !manager.busy
                                    hoverEnabled: true
                                    cursorShape: enabled
                                        ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: manager.selectNetwork(
                                        networkCard.modelData)
                                }

                                Rectangle {
                                    anchors {
                                        left: parent.left
                                        right: parent.right
                                        bottom: parent.bottom
                                        leftMargin: 46
                                        rightMargin: 6
                                    }
                                    height: 1
                                    color: manager.theme.surfaceHover
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: manager.passwordSsid.length > 0 ? 88 : 0
                    visible: height > 0
                    color: "transparent"
                    clip: true

                    Rectangle {
                        anchors { left: parent.left; right: parent.right; top: parent.top }
                        height: 1
                        color: manager.theme.surfaceHover
                    }

                    ColumnLayout {
                        anchors {
                            fill: parent
                            topMargin: 10
                            leftMargin: 4
                            rightMargin: 4
                        }
                        spacing: 6

                        Text {
                            Layout.fillWidth: true
                            text: "PASSWORT  /  " + manager.passwordSsid.toUpperCase()
                            color: manager.theme.textSecondary
                            elide: Text.ElideRight
                            font.family: manager.fontFamily
                            font.pixelSize: 8
                            font.weight: Font.Bold
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 34
                                radius: 10
                                color: manager.theme.surfaceRaised
                                border.width: passwordInput.activeFocus ? 1 : 0
                                border.color: manager.theme.textDisabled

                                TextInput {
                                    id: passwordInput
                                    anchors {
                                        fill: parent
                                        leftMargin: 12
                                        rightMargin: 12
                                    }
                                    verticalAlignment: TextInput.AlignVCenter
                                    color: manager.theme.textPrimary
                                    selectionColor: manager.theme.textDisabled
                                    selectedTextColor: manager.theme.surface
                                    echoMode: TextInput.Password
                                    passwordCharacter: "•"
                                    font.family: manager.fontFamily
                                    font.pixelSize: 10
                                    Keys.onReturnPressed: manager.connectWithPassword()
                                    Keys.onEscapePressed: {
                                        manager.passwordSsid = ""
                                        passwordInput.text = ""
                                        keyFocus.forceActiveFocus()
                                    }
                                }

                                Text {
                                    visible: passwordInput.text.length === 0
                                        && !passwordInput.activeFocus
                                    anchors {
                                        left: parent.left
                                        leftMargin: 12
                                        verticalCenter: parent.verticalCenter
                                    }
                                    text: "NETZWERKSCHLÜSSEL"
                                    color: manager.theme.textDisabled
                                    font.family: manager.fontFamily
                                    font.pixelSize: 8
                                }
                            }

                            IconButton {
                                icon: "󰄬"
                                active: passwordInput.text.length > 0
                                onClicked: manager.connectWithPassword()
                            }
                        }
                    }
                }
            }

            Item {
                id: keyFocus
                anchors.fill: parent
                focus: manager.shown
                Keys.onEscapePressed: manager.close()
            }
        }
    }
}

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Mono.Sdf

Scope {
    id: dashboard

    required property var theme
    property var dashboardScreen
    property bool shown: false
    property bool suppressed: false
    property int targetWorkspace: 1
    property int monthOffset: 0
    property bool weatherReady: false
    property int weatherTemperature: 0
    property int weatherCode: 0
    property bool weatherIsDay: true
    property string weatherSummary: "WIRD GELADEN"
    property string weatherLocation: "WEATHER"
    property var hourlyForecast: []

    readonly property var monthNames: [
        "JANUAR", "FEBRUAR", "MÄRZ", "APRIL", "MAI", "JUNI",
        "JULI", "AUGUST", "SEPTEMBER", "OKTOBER", "NOVEMBER", "DEZEMBER"
    ]
    readonly property var weekDays: ["MO", "DI", "MI", "DO", "FR", "SA", "SO"]
    readonly property var displayedMonth: new Date(
        clock.date.getFullYear(),
        clock.date.getMonth() + dashboard.monthOffset,
        1
    )
    readonly property var calendarDays: {
        const year = dashboard.displayedMonth.getFullYear()
        const month = dashboard.displayedMonth.getMonth()
        const firstDay = (new Date(year, month, 1).getDay() + 6) % 7
        const count = new Date(year, month + 1, 0).getDate()
        const values = []
        for (let index = 0; index < 42; ++index) {
            const day = index - firstDay + 1
            values.push(day >= 1 && day <= count ? day : 0)
        }
        return values
    }

    function weatherIcon(code, isDay) {
        if (code === 0)
            return isDay ? "󰖙" : "󰖔"
        if (code <= 3)
            return "󰖐"
        if (code === 45 || code === 48)
            return "󰖑"
        if (code >= 51 && code <= 67)
            return "󰖗"
        if (code >= 71 && code <= 77)
            return "󰖘"
        if (code >= 80 && code <= 82)
            return "󰖗"
        if (code >= 95)
            return "󰖓"
        return "󰖐"
    }

    function isToday(day) {
        return day > 0
            && dashboard.monthOffset === 0
            && day === clock.date.getDate()
    }

    function open() {
        const monitor = Hyprland.monitorFor(dashboard.dashboardScreen)
        if (monitor && monitor.activeWorkspace)
            dashboard.targetWorkspace = monitor.activeWorkspace.id
        dashboard.monthOffset = 0
        dashboard.shown = true
        placeTimer.restart()
        if (!weatherProcess.running)
            weatherProcess.running = true
    }

    function close() {
        dashboard.shown = false
    }

    function toggle() {
        dashboard.shown ? dashboard.close() : dashboard.open()
    }

    IpcHandler {
        target: "widgets"

        function toggle(): void { dashboard.toggle() }
        function open(): void { dashboard.open() }
        function close(): void { dashboard.close() }
    }

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    Process {
        id: weatherProcess
        command: [
            "/usr/bin/python3",
            "/home/mika/.config/quickshell/scripts/weather.py"
        ]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const weather = JSON.parse(text)
                    dashboard.weatherTemperature = weather.temperature
                    dashboard.weatherCode = weather.code
                    dashboard.weatherIsDay = weather.isDay
                    dashboard.weatherSummary = weather.summary
                    dashboard.weatherLocation = weather.location || "WEATHER"
                    dashboard.hourlyForecast = weather.hourly
                    dashboard.weatherReady = weather.ok !== false
                } catch (error) {
                    dashboard.weatherSummary = "KEINE VERBINDUNG"
                }
            }
        }
    }

    Timer {
        interval: 900000
        running: true
        repeat: true
        onTriggered: if (!weatherProcess.running) weatherProcess.running = true
    }

    Timer {
        id: placeTimer
        interval: 120
        onTriggered: {
            const titles = ["Rice Weather", "Rice Calendar"]
            for (let index = 0; index < titles.length; ++index) {
                Hyprland.dispatch(
                    "hl.dsp.window.move({ workspace = "
                        + dashboard.targetWorkspace
                        + ", follow = false, window = "
                        + "\"title:^(" + titles[index] + ")$\" })"
                )
            }
            lowerTimer.restart()
        }
    }

    Timer {
        id: lowerTimer
        interval: 100
        onTriggered: {
            const titles = ["Rice Weather", "Rice Calendar"]
            for (let index = 0; index < titles.length; ++index) {
                Hyprland.dispatch(
                    "hl.dsp.window.alter_zorder({ mode = \"bottom\", "
                        + "window = \"title:^(" + titles[index] + ")$\" })"
                )
            }
        }
    }

    component Card: Item {
        id: card

        property real cornerRadius: 24
        property real cornerSmoothing: 0.75

        SdfCanvas {
            id: cardBorder
            anchors.fill: parent
            fillColor: dashboard.theme.surfaceGlass
            smoothness: 0
            z: -2

            SdfRoundRect {
                x: cardBorder.width / 2
                y: cardBorder.height / 2
                halfWidth: cardBorder.width / 2
                halfHeight: cardBorder.height / 2
                cornerRadius: card.cornerRadius
                cornerSmoothing: card.cornerSmoothing
            }
        }

        SdfCanvas {
            id: cardSurface
            anchors.fill: parent
            anchors.margins: 1
            fillColor: dashboard.theme.hoverScrim
            smoothness: 0
            z: -1

            SdfRoundRect {
                x: cardSurface.width / 2
                y: cardSurface.height / 2
                halfWidth: cardSurface.width / 2
                halfHeight: cardSurface.height / 2
                cornerRadius: Math.max(0, card.cornerRadius - 1)
                cornerSmoothing: card.cornerSmoothing
            }
        }
    }

    FloatingWindow {
        id: weatherWindow

        screen: dashboard.dashboardScreen
        visible: dashboard.dashboardScreen !== null
            && !dashboard.suppressed
            && dashboard.shown
        title: "Rice Weather"
        color: "transparent"
        implicitWidth: 360
        implicitHeight: 238
        minimumSize: Qt.size(360, 238)
        maximumSize: Qt.size(360, 238)

        Card {
            anchors.fill: parent

            ColumnLayout {
                anchors {
                    fill: parent
                    margins: 18
                }
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 72
                    spacing: 13

                    Text {
                        text: dashboard.weatherIcon(
                            dashboard.weatherCode,
                            dashboard.weatherIsDay
                        )
                        color: dashboard.theme.textPrimary
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 42
                    }

                    Text {
                        text: dashboard.weatherReady
                            ? dashboard.weatherTemperature + "°"
                            : "--°"
                        color: dashboard.theme.textPrimary
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 30
                        font.weight: Font.Medium
                    }

                    Item { Layout.fillWidth: true }

                    Column {
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 4

                        Text {
                            anchors.right: parent.right
                            text: dashboard.weatherLocation
                            color: dashboard.theme.textPrimary
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 11
                            font.bold: true
                        }

                        Text {
                            anchors.right: parent.right
                            text: dashboard.weatherSummary
                            color: dashboard.theme.textMuted
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 8
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: dashboard.theme.surfaceSubtle
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 4

                    Repeater {
                        model: dashboard.hourlyForecast

                        delegate: ColumnLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 4

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: modelData.time
                                color: dashboard.theme.textDisabled
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 7
                                font.bold: true
                            }

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: dashboard.weatherIcon(
                                    modelData.code,
                                    modelData.isDay
                                )
                                color: dashboard.theme.textPrimary
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 22
                            }

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: modelData.temperature + "°"
                                color: dashboard.theme.textMuted
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 8
                            }
                        }
                    }
                }
            }
        }
    }

    FloatingWindow {
        id: calendarWindow

        screen: dashboard.dashboardScreen
        visible: dashboard.dashboardScreen !== null
            && !dashboard.suppressed
            && dashboard.shown
        title: "Rice Calendar"
        color: "transparent"
        implicitWidth: 360
        implicitHeight: 452
        minimumSize: Qt.size(360, 452)
        maximumSize: Qt.size(360, 452)

        Card {
            anchors.fill: parent

            ColumnLayout {
                anchors {
                    fill: parent
                    margins: 18
                }
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 54

                    Text {
                        text: "‹"
                        color: dashboard.theme.textDisabled
                        font.pixelSize: 24

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -10
                            cursorShape: Qt.PointingHandCursor
                            onClicked: dashboard.monthOffset -= 1
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: -2

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: dashboard.monthNames[
                                dashboard.displayedMonth.getMonth()
                            ]
                            color: dashboard.theme.textPrimary
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 18
                            font.bold: true
                            font.letterSpacing: 2.5
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: dashboard.displayedMonth.getFullYear()
                            color: dashboard.theme.textDisabled
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 10
                            font.letterSpacing: 1.5
                        }
                    }

                    Text {
                        text: "›"
                        color: dashboard.theme.textDisabled
                        font.pixelSize: 24

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -10
                            cursorShape: Qt.PointingHandCursor
                            onClicked: dashboard.monthOffset += 1
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: dashboard.theme.surfaceSubtle
                }

                GridLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    columns: 7
                    columnSpacing: 2
                    rowSpacing: 4

                    Repeater {
                        model: dashboard.weekDays

                        delegate: Text {
                            required property string modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: 24
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: modelData
                            color: dashboard.theme.outlineSubtle
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 8
                            font.bold: true
                        }
                    }

                    Repeater {
                        model: dashboard.calendarDays

                        delegate: Rectangle {
                            required property int modelData
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.minimumHeight: 40
                            radius: width / 2
                            property bool today: dashboard.isToday(modelData)
                            color: today ? dashboard.theme.textPrimary : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: modelData === 0 ? "" : modelData
                                color: parent.today ? dashboard.theme.surface : dashboard.theme.textMuted
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 11
                                font.bold: parent.today
                            }
                        }
                    }
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: dashboard.monthOffset === 0
                        ? Qt.formatDateTime(clock.date, "dddd · dd.MM.yyyy")
                        : "KLICK AUF DIE PFEILE ZUM BLÄTTERN"
                    color: dashboard.theme.textDisabled
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 8
                }
            }
        }
    }
}

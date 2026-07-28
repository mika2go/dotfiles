import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
// Mika's Quickshell rice.
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import Quickshell.Wayland
import Mono.Sdf

ShellRoot {
    id: root

    WallpaperTheme {
        id: shellTheme
    }

    // Animated wallpaper renderer. It stays dormant for static wallpapers,
    // leaving awww as the zero-risk fallback.
    WallpaperEngine {}

    property var barScreen: Quickshell.screens.find(screen => screen.name === "DP-1")
    property var cockpitScreen: Quickshell.screens.find(
        screen => screen.name === "HDMI-A-1")
    property int cpuUsage: 0
    property int gpuUsage: 0
    property int memoryUsage: 0
    property bool networkOnline: false
    property bool wifiEnabled: false
    property string activeConnection: "Keine aktive Verbindung"
    property bool bluetoothEnabled: false
    property int volume: 0
    property int microphone: 0
    property bool muted: false
    property bool trayOpen: false
    property bool statsOpen: false
    property real mediaPosition: 0
    property string sidebarHoverKey: ""
    property string sidebarDisplayKey: ""
    property real sidebarPageOpacity: 0
    property bool sidebarHoverWindowVisible: false
    property bool sidebarInteractionActive: false
    property real sidebarHoverY: 0
    property real sidebarHoverHeight: 236
    property real sidebarHoverOffsetScale: sidebarHoverKey.length > 0 ? 0 : 1
    readonly property real sidebarHoverProgress: 1 - sidebarHoverOffsetScale
    readonly property real sidebarContentReveal: Math.max(0, Math.min(
        1, (sidebarHoverProgress - 0.90) / 0.10))
    readonly property real sidebarHoverWidth: 350

    Behavior on sidebarHoverOffsetScale {
        NumberAnimation {
            duration: 500
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.38, 1.21, 0.22, 1.0, 1.0, 1.0]
        }
    }

    Behavior on sidebarHoverY {
        enabled: root.sidebarHoverOffsetScale < 0.999
        NumberAnimation {
            duration: 500
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.38, 1.21, 0.22, 1.0, 1.0, 1.0]
        }
    }

    Behavior on sidebarHoverHeight {
        enabled: root.sidebarHoverOffsetScale < 0.999
        NumberAnimation {
            duration: 500
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.38, 1.21, 0.22, 1.0, 1.0, 1.0]
        }
    }

    onSidebarHoverKeyChanged: {
        sidebarPageSwap.stop()
        if (root.sidebarHoverKey.length === 0) {
            sidebarHoverCleanup.restart()
        } else if (root.sidebarDisplayKey.length === 0) {
            sidebarHoverCleanup.stop()
            root.sidebarHoverWindowVisible = true
            root.sidebarDisplayKey = root.sidebarHoverKey
            root.sidebarPageOpacity = 1
        } else if (root.sidebarDisplayKey !== root.sidebarHoverKey) {
            sidebarHoverCleanup.stop()
            sidebarPageSwap.restart()
        }
    }
    readonly property var shellMonitor: root.barScreen
        ? Hyprland.monitorFor(root.barScreen)
        : null
    readonly property bool fullscreenActive: !!(
        root.shellMonitor
        && root.shellMonitor.activeWorkspace
        && root.shellMonitor.activeWorkspace.hasFullscreen
    )

    function positionSidebarHover() {
        const panelTop = Math.max(0, bottomModules.y - 8)
        root.sidebarHoverHeight = barWindow.height - panelTop
        root.sidebarHoverY = panelTop + root.sidebarHoverHeight / 2
    }

    function sidebarKeyAt(screenY) {
        const localY = screenY - bottomModules.y
        const entries = [
            { key: "network", item: networkModule },
            { key: "bluetooth", item: bluetoothModule },
            { key: "volume", item: volumeModule },
            { key: "tray", item: trayModule },
            { key: "performance", item: performanceModule },
            { key: "power", item: powerModule },
            { key: "clock", item: clockModule }
        ]
        for (let i = 0; i < entries.length; ++i) {
            const entry = entries[i]
            if (localY <= entry.item.y + entry.item.height
                    + bottomModules.spacing / 2)
                return entry.key
        }
        return "clock"
    }

    function updateSidebarHoverFromY(screenY) {
        const key = root.sidebarKeyAt(screenY)
        root.keepSidebarHover()
        if (root.sidebarHoverKey !== key)
            root.showSidebarHover(key, networkModule)
    }

    function showSidebarHover(key, item) {
        sidebarHoverCloseTimer.stop()
        sidebarHoverAutoCloseTimer.stop()
        root.positionSidebarHover()
        root.sidebarHoverWindowVisible = true
        root.sidebarHoverKey = key
    }

    function keepSidebarHover() {
        sidebarHoverCloseTimer.stop()
        sidebarHoverAutoCloseTimer.stop()
    }

    function scheduleSidebarHoverClose() {
        sidebarHoverAutoCloseTimer.stop()
        Qt.callLater(function() {
            if (!root.sidebarPointerInside())
                sidebarHoverCloseTimer.restart()
        })
    }

    function sidebarPointerInside() {
        return root.sidebarInteractionActive
            || sidebarModuleGuardMouse.containsMouse
            || bottomOverviewHover.hovered
            || sidebarPanelHover.hovered
            || sidebarContentHover.hovered
    }

    function holdSidebarInteraction() {
        root.sidebarInteractionActive = true
        root.keepSidebarHover()
        sidebarInteractionRelease.restart()
    }

    function revealSidebarHover(key, y) {
        sidebarHoverCloseTimer.stop()
        root.positionSidebarHover()
        root.sidebarHoverWindowVisible = true
        root.sidebarHoverKey = key
        sidebarHoverAutoCloseTimer.restart()
    }

    function runSidebarAction(command) {
        if (sidebarAction.running)
            sidebarAction.running = false
        sidebarAction.command = command
        sidebarAction.running = true
        sidebarStatusRefresh.restart()
        root.keepSidebarHover()
    }

    function toggleWifi() {
        root.wifiEnabled = !root.wifiEnabled
        root.runSidebarAction([
            "nmcli", "radio", "wifi", root.wifiEnabled ? "on" : "off"
        ])
    }

    function toggleBluetooth() {
        root.bluetoothEnabled = !root.bluetoothEnabled
        root.runSidebarAction([
            "rfkill", root.bluetoothEnabled ? "unblock" : "block", "bluetooth"
        ])
    }

    function formatMediaTime(seconds) {
        const safeSeconds = Math.max(0, Math.floor(Number(seconds) || 0))
        const minutes = Math.floor(safeSeconds / 60)
        const remainder = safeSeconds % 60
        return minutes + ":" + (remainder < 10 ? "0" : "") + remainder
    }

    function cycleWorkspace(step) {
        const monitor = Hyprland.monitorFor(barWindow.screen)
        if (!monitor || !monitor.activeWorkspace)
            return
        const target = monitor.activeWorkspace.id + step
        if (target < 1 || target > 7)
            return
        Hyprland.dispatch("hl.dsp.focus({ workspace = " + target + " })")
    }

    // One server feeds both the transient popup and the persistent history.
    NotificationCenter {
        id: notificationController
        suppressed: root.fullscreenActive
    }

    Launcher {
        id: appLauncher
        theme: shellTheme
        launcherScreen: root.barScreen
        suppressed: root.fullscreenActive
        wallpaperController: borderController.wallpaperController
    }

    Keybinds {
        id: keybindsOverlay
        theme: shellTheme
        overlayScreen: root.barScreen
        suppressed: root.fullscreenActive
    }

    // Compact file browser opened with SUPER + F.
    FileExplorer {
        id: fileExplorer
        theme: shellTheme
        explorerScreen: root.barScreen
        suppressed: root.fullscreenActive
    }

    // Right-side desktop widgets opened with SUPER + W.
    WidgetDashboard {
        id: widgetDashboard
        theme: shellTheme
        dashboardScreen: root.barScreen
        suppressed: root.fullscreenActive
    }

    AudioMixer {
        id: audioMixer
        theme: shellTheme
        mixerScreen: root.barScreen
        suppressed: root.fullscreenActive
    }

    NetworkManager {
        id: networkManager
        theme: shellTheme
        managerScreen: root.barScreen
        suppressed: root.fullscreenActive
    }

    Osd {
        id: osdController
        theme: shellTheme
        osdScreen: root.barScreen
        suppressed: root.fullscreenActive
        currentVolume: root.volume
        currentMuted: root.muted
    }

    LockScreen {
        id: lockScreen
        theme: shellTheme
        cpuUsage: root.cpuUsage
        gpuUsage: root.gpuUsage
        memoryUsage: root.memoryUsage
        networkOnline: root.networkOnline
        volume: root.volume
        muted: root.muted
        player: root.activePlayer
    }

    PowerMenu {
        id: powerMenu
        theme: shellTheme
        powerScreen: root.barScreen
        suppressed: root.fullscreenActive
        lockController: lockScreen
    }

    ScreenBorderCorners {
        id: borderController
        theme: shellTheme
        borderScreen: root.barScreen
        notificationCenter: notificationController
        suppressed: root.fullscreenActive
        islandExpanded: dynamicIsland.expanded
        islandVisible: dynamicIsland.windowVisible
        islandProgress: dynamicIsland.morphProgress
        islandWidthProgress: dynamicIsland.surfaceWidthScale
        islandHeightProgress: dynamicIsland.surfaceHeightScale
        islandTravelProgress: dynamicIsland.morphProgress
        islandWidth: dynamicIsland.surfaceWidth
        islandHeight: dynamicIsland.compactSurfaceHeight
        launcherProgress: appLauncher.morphProgress
        launcherWidth: appLauncher.surfaceWidth
        launcherHeight: appLauncher.surfaceHeight
        powerProgress: powerMenu.morphProgress
        powerWidth: powerMenu.surfaceWidth
        powerHeight: powerMenu.surfaceHeight
        mixerProgress: audioMixer.morphProgress
        mixerOffsetScale: audioMixer.offsetScale
        mixerWidth: audioMixer.surfaceWidth
        mixerHeight: audioMixer.surfaceHeight
        networkProgress: networkManager.morphProgress
        networkOffsetScale: networkManager.offsetScale
        networkWidth: networkManager.surfaceWidth
        networkHeight: networkManager.surfaceHeight
        hoverActive: root.sidebarHoverKey.length > 0
        hoverOffsetScale: root.sidebarHoverOffsetScale
        hoverCenterY: root.sidebarHoverY
        hoverWidth: root.sidebarHoverWidth
        hoverHeight: root.sidebarHoverHeight
    }

    DynamicIsland {
        id: dynamicIsland
        theme: shellTheme
        islandScreen: root.barScreen
        horizontalCenterOffset: 54 / 2
        suppressed: root.fullscreenActive
        player: root.activePlayer
        networkOnline: root.networkOnline
        volume: root.volume
        microphone: root.microphone
        muted: root.muted
        cpuUsage: root.cpuUsage
        gpuUsage: root.gpuUsage
        memoryUsage: root.memoryUsage
        trayCount: SystemTray.items.values.length
        onToggleTrayRequested: root.revealSidebarHover(
            "tray",
            Math.max(60, barWindow.height - 124)
        )
    }

    HdmiCockpit {
        id: hdmiCockpit
        theme: shellTheme
        cockpitScreen: root.cockpitScreen
    }

    property var activePlayer: {
        const spotifyPlayers = Mpris.players.values.filter(player => {
            const identity = ((player.identity || "") + " "
                + (player.desktopEntry || "") + " "
                + (player.dbusName || "")).toLowerCase()
            return identity.includes("spotify")
        })
        return spotifyPlayers.find(player => player.isPlaying)
            || spotifyPlayers.find(player => (player.trackTitle || "").length > 0)
            || spotifyPlayers[0]
            || null
    }

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    Process {
        id: metrics
        command: ["/home/mika/.config/quickshell/scripts/metrics.sh"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const values = text.trim().split("|")
                if (values.length !== 7)
                    return
                root.cpuUsage = Number(values[0])
                root.gpuUsage = Number(values[1])
                root.memoryUsage = Number(values[2])
                root.networkOnline = values[3] === "1"
                root.volume = Number(values[4])
                root.muted = values[5] === "1"
                root.microphone = Number(values[6])
            }
        }
    }

    Process {
        id: sidebarAction
    }

    Process {
        id: sidebarStatusProbe
        command: ["bash", "-lc",
            "wifi=$(nmcli -t -f WIFI general 2>/dev/null); "
            + "conn=$(nmcli -t -f NAME,TYPE connection show --active 2>/dev/null | head -n1 | cut -d: -f1); "
            + "bt=$(rfkill -rn -o TYPE,SOFT 2>/dev/null | awk '$1 == \"bluetooth\" {print $2; exit}'); "
            + "printf '%s|%s|%s\\n' \"$wifi\" \"$conn\" \"$bt\""]

        stdout: StdioCollector {
            onStreamFinished: {
                const values = text.trim().split("|")
                if (values.length < 3)
                    return
                root.wifiEnabled = values[0] === "enabled"
                root.activeConnection = values[1].length > 0
                    ? values[1] : "Keine aktive Verbindung"
                root.bluetoothEnabled = values[2] === "unblocked"
            }
        }
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!sidebarStatusProbe.running)
            sidebarStatusProbe.running = true
    }

    Timer {
        id: sidebarStatusRefresh
        interval: 500
        onTriggered: if (!sidebarStatusProbe.running)
            sidebarStatusProbe.running = true
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: if (!metrics.running) metrics.running = true
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.mediaPosition = root.activePlayer
            ? Number(root.activePlayer.position || 0)
            : 0
    }

    Timer {
        id: statsCloseTimer
        interval: 240
        onTriggered: root.statsOpen = false
    }

    Timer {
        id: sidebarHoverCloseTimer
        interval: 260
        onTriggered: {
            if (!root.sidebarPointerInside())
                root.sidebarHoverKey = ""
        }
    }

    Timer {
        id: sidebarHoverAutoCloseTimer
        interval: 2200
        onTriggered: root.sidebarHoverKey = ""
    }

    Timer {
        id: sidebarHoverCleanup
        interval: 515
        onTriggered: {
            if (root.sidebarHoverKey.length === 0) {
                root.sidebarHoverWindowVisible = false
                root.sidebarDisplayKey = ""
                root.sidebarPageOpacity = 0
            }
        }
    }

    Timer {
        id: sidebarInteractionRelease
        interval: 650
        onTriggered: {
            root.sidebarInteractionActive = false
            if (!root.sidebarPointerInside())
                root.scheduleSidebarHoverClose()
        }
    }

    SequentialAnimation {
        id: sidebarPageSwap

        NumberAnimation {
            target: root
            property: "sidebarPageOpacity"
            to: 0
            duration: 65
            easing.type: Easing.InQuad
        }

        ScriptAction {
            script: root.sidebarDisplayKey = root.sidebarHoverKey
        }

        NumberAnimation {
            target: root
            property: "sidebarPageOpacity"
            to: 1
            duration: 95
            easing.type: Easing.OutQuad
        }
    }

    PanelWindow {
        id: barWindow
        screen: root.barScreen
        visible: root.barScreen !== null && !root.fullscreenActive
        color: "transparent"
        implicitWidth: 380
        exclusiveZone: 54
        WlrLayershell.layer: WlrLayer.Overlay

        mask: Region {
            Region { item: barSurface }
            Region { item: sidebarHoverInputRegion }
        }

        anchors {
            top: true
            bottom: true
            left: true
        }

        margins {
            top: 0
            bottom: 0
            left: 0
        }

        Rectangle {
            id: barSurface
            anchors {
                top: parent.top
                bottom: parent.bottom
                left: parent.left
            }
            width: 54
            color: "transparent"
            radius: 0
            border.width: 0

            Item {
                id: topArea
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                }
                height: 310

                Image {
                    id: archLogo
                    anchors {
                        top: parent.top
                        topMargin: 19
                        horizontalCenter: parent.horizontalCenter
                    }
                    width: 21
                    height: 21
                    source: "assets/arch-mark.svg"
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }

                MouseArea {
                    anchors.fill: archLogo
                    cursorShape: Qt.PointingHandCursor
                    onClicked: appLauncher.toggle()
                }

                Rectangle {
                    id: workspacePill
                    anchors {
                        top: archLogo.bottom
                        topMargin: 16
                        horizontalCenter: parent.horizontalCenter
                    }
                    width: 24
                    height: workspaceColumn.height + 12
                    radius: width / 2
                    color: shellTheme.surfaceRaised

                    Column {
                        id: workspaceColumn
                        anchors.centerIn: parent
                        spacing: 0

                        Repeater {
                            model: 7

                            delegate: Item {
                                required property int index
                                property int workspaceId: index + 1
                                width: 24
                                height: 22

                                Rectangle {
                                    anchors.centerIn: parent
                                    property bool active: {
                                        const monitor = Hyprland.monitorFor(barWindow.screen)
                                        return monitor && monitor.activeWorkspace
                                            && monitor.activeWorkspace.id === parent.workspaceId
                                    }
                                    width: 8
                                    height: active ? 18 : 8
                                    radius: width / 2
                                    color: active ? shellTheme.textPrimary : shellTheme.surfaceActive

                                    Behavior on color {
                                        ColorAnimation { duration: 140 }
                                    }
                                    Behavior on height {
                                        NumberAnimation {
                                            duration: 160
                                            easing.type: Easing.OutCubic
                                        }
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Hyprland.dispatch(
                                        "hl.dsp.focus({ workspace = " + parent.workspaceId + " })"
                                    )
                                    onWheel: wheel => root.cycleWorkspace(
                                        wheel.angleDelta.y > 0 ? -1 : 1
                                    )
                                }
                            }
                        }
                    }
                }
            }

            Item {
                anchors.centerIn: parent
                width: parent.width
                height: 340

                Rectangle {
                    anchors {
                        fill: parent
                        leftMargin: 8
                        rightMargin: 8
                    }
                    radius: 0
                    color: "transparent"
                    border.width: 0

                    Rectangle {
                        id: albumCover
                        anchors {
                            bottom: parent.bottom
                            bottomMargin: 6
                            horizontalCenter: parent.horizontalCenter
                        }
                        width: 28
                        height: 28
                        radius: width / 2
                        rotation: -90
                        color: shellTheme.surfaceRaised
                        clip: true
                        border.width: 1
                        border.color: shellTheme.textBright

                        Image {
                            id: albumImage
                            anchors.fill: parent
                            source: root.activePlayer ? root.activePlayer.trackArtUrl : ""
                            fillMode: Image.PreserveAspectCrop
                            smooth: true
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                maskEnabled: true
                                maskSource: coverMask
                                maskThresholdMin: 0.5
                                maskSpreadAtMin: 1
                            }
                        }

                        Rectangle {
                            id: coverMask
                            anchors.fill: parent
                            radius: width / 2
                            visible: false
                            layer.enabled: true
                        }

                        Image {
                            anchors.fill: parent
                            visible: albumImage.status !== Image.Ready
                            source: "assets/album-placeholder.svg"
                            fillMode: Image.PreserveAspectCrop
                            smooth: true
                        }
                    }

                    Column {
                        anchors.centerIn: parent
                        width: 238
                        rotation: -90
                        spacing: 4

                        Text {
                            width: parent.width
                            height: 16
                            text: root.activePlayer
                                ? (root.activePlayer.trackTitle || root.activePlayer.identity)
                                : "Keine Musik"
                            color: root.activePlayer ? shellTheme.textPrimary : shellTheme.textMuted
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }

                        Rectangle {
                            width: parent.width
                            height: 3
                            radius: height / 2
                            color: shellTheme.surfaceActive
                            clip: true

                            Rectangle {
                                width: root.activePlayer && root.activePlayer.length > 0
                                    ? parent.width * Math.min(
                                        1,
                                        root.mediaPosition / root.activePlayer.length
                                    )
                                    : 0
                                height: parent.height
                                radius: parent.radius
                                color: shellTheme.textPrimary

                                Behavior on width {
                                    NumberAnimation {
                                        duration: 300
                                        easing.type: Easing.OutCubic
                                    }
                                }
                            }
                        }

                        Item {
                            width: parent.width
                            height: 10

                            Text {
                                anchors.left: parent.left
                                text: root.formatMediaTime(root.mediaPosition)
                                color: shellTheme.textMuted
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 7
                            }

                            Text {
                                anchors.right: parent.right
                                text: root.activePlayer
                                    ? root.formatMediaTime(root.activePlayer.length)
                                    : "0:00"
                                color: shellTheme.textMuted
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 7
                            }
                        }
                    }

                    Rectangle {
                        id: playbackButton
                        anchors {
                            top: parent.top
                            topMargin: 6
                            horizontalCenter: parent.horizontalCenter
                        }
                        width: 28
                        height: 28
                        radius: width / 2
                        rotation: -90
                        color: playbackMouse.containsMouse
                            ? shellTheme.textBright
                            : (root.activePlayer && root.activePlayer.isPlaying ? shellTheme.textPrimary : shellTheme.surface)
                        border.width: root.activePlayer && root.activePlayer.isPlaying ? 0 : 1
                        border.color: shellTheme.textBright

                        Behavior on color {
                            ColorAnimation { duration: 120 }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: root.activePlayer && root.activePlayer.isPlaying ? "󰏤" : "󰐊"
                            color: playbackMouse.containsMouse
                                || (root.activePlayer && root.activePlayer.isPlaying)
                                ? shellTheme.surfaceDeep : shellTheme.textBright
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 12
                        }
                    }

                    MouseArea {
                        id: playbackMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (root.activePlayer) root.activePlayer.togglePlaying()
                    }
                }
            }

            Column {
                id: bottomModules
                anchors {
                    bottom: parent.bottom
                    bottomMargin: 14
                    horizontalCenter: parent.horizontalCenter
                }
                spacing: 9

                HoverHandler {
                    id: bottomOverviewHover
                    margin: 10
                    onHoveredChanged: {
                        if (hovered) {
                            root.keepSidebarHover()
                            if (root.sidebarHoverKey.length === 0)
                                root.showSidebarHover("network", networkModule)
                        } else {
                            root.scheduleSidebarHoverClose()
                        }
                    }
                }

                Item {
                    id: networkModule
                    width: 54
                    height: 28
                    Text {
                        anchors.centerIn: parent
                        text: root.networkOnline ? "󰖩" : "󰖪"
                        color: root.networkOnline ? shellTheme.textPrimary : shellTheme.textDisabled
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 14
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.showSidebarHover("network", networkModule)
                        onExited: if (!bottomOverviewHover.hovered)
                            root.scheduleSidebarHoverClose()
                        onClicked: {
                            root.sidebarHoverKey = ""
                            networkManager.toggle()
                        }
                    }
                }

                Item {
                    id: bluetoothModule
                    width: 54
                    height: 28

                    Text {
                        anchors.centerIn: parent
                        text: root.bluetoothEnabled ? "󰂯" : "󰂲"
                        color: root.bluetoothEnabled ? shellTheme.textPrimary : shellTheme.textDisabled
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 14
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.showSidebarHover("bluetooth", bluetoothModule)
                        onExited: if (!bottomOverviewHover.hovered)
                            root.scheduleSidebarHoverClose()
                    }
                }

                Item {
                    id: volumeModule
                    width: 54
                    height: 28
                    Text {
                        anchors.centerIn: parent
                        text: root.muted ? "󰖁" : (root.volume > 55 ? "󰕾" : "󰖀")
                        color: shellTheme.textPrimary
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 14
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.showSidebarHover("volume", volumeModule)
                        onExited: if (!bottomOverviewHover.hovered)
                            root.scheduleSidebarHoverClose()
                        onClicked: {
                            root.sidebarHoverKey = ""
                            audioMixer.toggle()
                        }
                        onWheel: wheel.angleDelta.y > 0
                            ? osdController.volumeUp()
                            : osdController.volumeDown()
                    }
                }

                Item {
                    id: trayModule
                    width: 54
                    height: 28
                    Image {
                        anchors.centerIn: parent
                        width: 16
                        height: 16
                        source: "assets/tray-apps.svg"
                        fillMode: Image.PreserveAspectFit
                        opacity: trayModuleMouse.containsMouse ? 0.55 : 1
                        smooth: true
                    }
                    MouseArea {
                        id: trayModuleMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.showSidebarHover("tray", trayModule)
                        onExited: if (!bottomOverviewHover.hovered)
                            root.scheduleSidebarHoverClose()
                    }
                }

                Item {
                    id: performanceModule
                    width: 54
                    height: 28

                    Image {
                        anchors.centerIn: parent
                        width: 16
                        height: 16
                        source: "assets/performance.svg"
                        fillMode: Image.PreserveAspectFit
                        opacity: performanceMouse.containsMouse ? 0.55 : 1
                        smooth: true
                    }

                    MouseArea {
                        id: performanceMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.showSidebarHover("performance", performanceModule)
                        onExited: if (!bottomOverviewHover.hovered)
                            root.scheduleSidebarHoverClose()
                    }
                }

                Item {
                    id: powerModule
                    width: 54
                    height: 28

                    Text {
                        anchors.centerIn: parent
                        text: "󰐥"
                        color: powerMouse.containsMouse ? shellTheme.textMuted : shellTheme.textPrimary
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 15
                    }

                    MouseArea {
                        id: powerMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.showSidebarHover("power", powerModule)
                        onExited: if (!bottomOverviewHover.hovered)
                            root.scheduleSidebarHoverClose()
                        onClicked: powerMenu.toggle()
                    }
                }

        Item {
            id: clockModule
            width: 54
            height: 38
            Text {
                width: parent.width
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDateTime(clock.date, "HH\nmm")
                color: shellTheme.textBright
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                lineHeight: 0.88
                font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.showSidebarHover("clock", clockModule)
                        onExited: if (!bottomOverviewHover.hovered)
                            root.scheduleSidebarHoverClose()
                        onClicked: dynamicIsland.toggle()
                    }
                }
            }
        }

        Item {
            id: sidebarModuleHoverGuard
            x: 0
            y: Math.max(0, bottomModules.y - 10)
            width: 54
            height: barWindow.height - y
            z: 20

            MouseArea {
                id: sidebarModuleGuardMouse
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                hoverEnabled: true
                onWheel: wheel => wheel.accepted = false

                onEntered: {
                    root.updateSidebarHoverFromY(
                        sidebarModuleHoverGuard.y + mouseY)
                }
                onPositionChanged: mouse => root.updateSidebarHoverFromY(
                    sidebarModuleHoverGuard.y + mouse.y)
                onExited: root.scheduleSidebarHoverClose()
            }
        }

        Item {
            id: sidebarHoverInputRegion
            x: 54
            y: root.sidebarHoverY - height / 2
            width: root.sidebarHoverKey.length > 0
                ? root.sidebarHoverWidth - 54
                : 0
            height: root.sidebarHoverHeight

            HoverHandler {
                id: sidebarPanelHover
                margin: 12
                onHoveredChanged: {
                    if (hovered)
                        root.keepSidebarHover()
                    else
                        root.scheduleSidebarHoverClose()
                }
            }
        }

        Item {
            id: sidebarHoverContent
            x: 70 + (-root.sidebarHoverWidth - 5)
                * root.sidebarHoverOffsetScale
            y: root.sidebarHoverY - height / 2
            width: Math.max(0, root.sidebarHoverWidth - 70)
            height: root.sidebarHoverHeight
            opacity: root.sidebarContentReveal
            visible: root.sidebarHoverWindowVisible
            clip: true

            HoverHandler {
                id: sidebarContentHover
                margin: 8
                onHoveredChanged: {
                    if (hovered)
                        root.keepSidebarHover()
                    else
                        root.scheduleSidebarHoverClose()
                }
            }

            Item {
                id: sidebarControlPage
                property var pageRows: {
                    if (root.sidebarDisplayKey === "network") return [
                        { icon: "󰖩", label: "VERBINDUNG", value: root.activeConnection, action: "none" },
                        { icon: "󰖪", label: "WLAN", value: root.wifiEnabled ? "AN" : "AUS", action: "wifi" },
                        { icon: "󰒓", label: "NETZWERKE", value: "ÖFFNEN  ›", action: "network-settings" }
                    ]
                    if (root.sidebarDisplayKey === "bluetooth") return [
                        { icon: "󰂯", label: "BLUETOOTH", value: root.bluetoothEnabled ? "AN" : "AUS", action: "bluetooth" },
                        { icon: "󰂱", label: "ADAPTER", value: root.bluetoothEnabled ? "BEREIT" : "BLOCKIERT", action: "none" },
                        { icon: "󰑐", label: "STATUS NEU LADEN", value: "AKTUALISIEREN  ›", action: "refresh" }
                    ]
                    if (root.sidebarDisplayKey === "volume") return [
                        { icon: root.muted ? "󰖁" : "󰕾", label: "AUSGABE", value: root.muted ? "STUMM" : root.volume + "%", action: "mute" },
                        { icon: "󰍬", label: "MIKROFON", value: root.microphone + "%", action: "mic" },
                        { icon: "󰒓", label: "AUDIOGERÄTE", value: "ÖFFNEN  ›", action: "audio-settings" }
                    ]
                    if (root.sidebarDisplayKey === "clock") return [
                        { icon: "󰥔", label: "UHRZEIT", value: Qt.formatDateTime(clock.date, "HH:mm:ss"), action: "none" },
                        { icon: "󰃭", label: "DATUM", value: Qt.formatDateTime(clock.date, "dd. MMMM"), action: "none" },
                        { icon: "󰃭", label: "KALENDER", value: "ÖFFNEN  ›", action: "calendar" }
                    ]
                    return [
                        { icon: "󰌾", label: "BILDSCHIRM SPERREN", value: "AUSFÜHREN  ›", action: "lock" },
                        { icon: "󰍃", label: "SITZUNG", value: "AKTIV", action: "none" },
                        { icon: "󰐥", label: "POWER-MENÜ", value: "ÖFFNEN  ›", action: "power" }
                    ]
                }

                opacity: root.sidebarDisplayKey !== "tray"
                    && root.sidebarDisplayKey !== "performance"
                    ? root.sidebarPageOpacity : 0
                visible: opacity > 0
                anchors.fill: parent

                Column {
                    anchors {
                        top: parent.top
                        left: parent.left
                        right: parent.right
                        topMargin: 13
                        leftMargin: 16
                        rightMargin: 16
                    }
                    spacing: 4

                    Text {
                        width: parent.width
                        text: root.sidebarDisplayKey === "network"
                            ? "WLAN"
                            : (root.sidebarDisplayKey === "volume"
                                ? "LAUTSTÄRKE"
                                : (root.sidebarDisplayKey === "bluetooth"
                                    ? "BLUETOOTH"
                                    : (root.sidebarDisplayKey === "clock" ? "UHR & DATUM" : "SYSTEM")))
                        color: shellTheme.textPrimary
                        elide: Text.ElideRight
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 11
                        font.weight: Font.Bold
                    }

                    Text {
                        width: parent.width
                        text: {
                            if (root.sidebarDisplayKey === "network")
                                return root.wifiEnabled ? "Funknetz aktiv" : "Funknetz deaktiviert"
                            if (root.sidebarDisplayKey === "bluetooth")
                                return root.bluetoothEnabled ? "Adapter ist bereit" : "Adapter ist blockiert"
                            if (root.sidebarDisplayKey === "volume")
                                return root.muted ? "Ausgabe stummgeschaltet" : "Ausgabe und Eingabe"
                            if (root.sidebarDisplayKey === "clock")
                                return Qt.formatDateTime(clock.date, "dddd")
                            return "Sitzung und Energie"
                        }
                        color: shellTheme.textMuted
                        elide: Text.ElideRight
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 8
                    }
                }

                Rectangle {
                    anchors {
                        top: parent.top
                        left: parent.left
                        right: parent.right
                        topMargin: 53
                        leftMargin: 16
                        rightMargin: 16
                    }
                    height: 1
                    color: shellTheme.surfaceHover
                }

                Column {
                    anchors {
                        top: parent.top
                        left: parent.left
                        right: parent.right
                        topMargin: 61
                        leftMargin: 12
                        rightMargin: 12
                    }
                    spacing: 0

                    Repeater {
                        model: sidebarControlPage.pageRows

                        delegate: Item {
                            id: sidebarActionRow
                            required property var modelData
                            required property int index
                            width: parent.width
                            height: 39

                            Rectangle {
                                anchors.fill: parent
                                radius: 9
                                color: sidebarActionMouse.containsMouse
                                    && sidebarActionRow.modelData.action !== "none"
                                    ? shellTheme.surfaceHover : "transparent"
                                Behavior on color { ColorAnimation { duration: 100 } }
                            }

                            Text {
                                anchors {
                                    left: parent.left
                                    leftMargin: 6
                                    verticalCenter: parent.verticalCenter
                                }
                                text: sidebarActionRow.modelData.icon
                                color: shellTheme.textPrimary
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 12
                            }

                            Text {
                                anchors {
                                    left: parent.left
                                    leftMargin: 32
                                    verticalCenter: parent.verticalCenter
                                }
                                width: 120
                                text: sidebarActionRow.modelData.label
                                color: shellTheme.textSecondary
                                elide: Text.ElideRight
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 8
                                font.weight: Font.DemiBold
                            }

                            Text {
                                anchors {
                                    right: parent.right
                                    rightMargin: 6
                                    verticalCenter: parent.verticalCenter
                                }
                                width: Math.max(50, parent.width - 158)
                                text: sidebarActionRow.modelData.value
                                color: shellTheme.textMuted
                                horizontalAlignment: Text.AlignRight
                                elide: Text.ElideRight
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 8
                            }

                            MouseArea {
                                id: sidebarActionMouse
                                anchors.fill: parent
                                enabled: sidebarActionRow.modelData.action !== "none"
                                hoverEnabled: true
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onEntered: root.keepSidebarHover()
                                onPressed: root.holdSidebarInteraction()
                                onClicked: {
                                    root.keepSidebarHover()
                                    const action = sidebarActionRow.modelData.action
                                    if (action === "wifi") root.toggleWifi()
                                    else if (action === "bluetooth") root.toggleBluetooth()
                                    else if (action === "network-settings") {
                                        root.sidebarHoverKey = ""
                                        networkManager.open()
                                    }
                                    else if (action === "refresh")
                                        sidebarStatusRefresh.restart()
                                    else if (action === "mute")
                                        osdController.volumeMute()
                                    else if (action === "mic")
                                        osdController.micMute()
                                    else if (action === "audio-settings")
                                        audioMixer.open()
                                    else if (action === "calendar") {
                                        dynamicIsland.selectTab("dashboard")
                                        dynamicIsland.open()
                                    }
                                    else if (action === "lock")
                                        lockScreen.activate()
                                    else if (action === "power")
                                        powerMenu.open()
                                }
                            }

                            Rectangle {
                                visible: index < sidebarControlPage.pageRows.length - 1
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    bottom: parent.bottom
                                    leftMargin: 32
                                    rightMargin: 6
                                }
                                height: 1
                                color: shellTheme.surfaceHover
                            }
                        }
                    }
                }

                Item {
                    visible: root.sidebarDisplayKey === "volume"
                    anchors {
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                        leftMargin: 18
                        rightMargin: 18
                        bottomMargin: 18
                    }
                    height: 18

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 3
                        radius: height / 2
                        color: shellTheme.surfaceHover

                        Rectangle {
                            width: parent.width * Math.min(100, root.volume) / 100
                            height: parent.height
                            radius: parent.radius
                            color: shellTheme.textPrimary
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: root.keepSidebarHover()
                        onWheel: wheel => {
                            root.keepSidebarHover()
                            wheel.angleDelta.y > 0
                                ? osdController.volumeUp()
                                : osdController.volumeDown()
                        }
                    }
                }

                Row {
                    visible: root.sidebarDisplayKey !== "volume"
                    anchors {
                        left: parent.left
                        bottom: parent.bottom
                        leftMargin: 18
                        bottomMargin: 15
                    }
                    spacing: 7

                    Rectangle {
                        width: 5
                        height: 5
                        radius: width / 2
                        color: shellTheme.textMuted
                    }

                    Text {
                        text: "AUSWAHL BLEIBT BEIM KLICK GEÖFFNET"
                        color: shellTheme.textDisabled
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 7
                    }
                }
            }

            Item {
                opacity: root.sidebarDisplayKey === "performance"
                    ? root.sidebarPageOpacity : 0
                visible: opacity > 0
                anchors.fill: parent

                Text {
                    anchors {
                        top: parent.top
                        left: parent.left
                        topMargin: 13
                        leftMargin: 16
                    }
                    text: "SYSTEM STATUS"
                    color: shellTheme.textPrimary
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                    font.weight: Font.Bold
                }

                Text {
                    anchors {
                        top: parent.top
                        left: parent.left
                        topMargin: 31
                        leftMargin: 16
                    }
                    text: "Auslastung in Echtzeit"
                    color: shellTheme.textMuted
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 8
                }

                Column {
                    anchors {
                        top: parent.top
                        left: parent.left
                        right: parent.right
                        topMargin: 58
                        leftMargin: 16
                        rightMargin: 16
                    }
                    spacing: 16

                    Repeater {
                        model: [
                            { label: "CPU", value: root.cpuUsage },
                            { label: "GPU", value: root.gpuUsage },
                            { label: "RAM", value: root.memoryUsage }
                        ]

                        Column {
                            required property var modelData
                            width: parent.width
                            spacing: 6

                            Row {
                                width: parent.width

                                Text {
                                    width: parent.width - 45
                                    text: parent.parent.modelData.label
                                    color: shellTheme.textMuted
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 8
                                    font.weight: Font.Bold
                                }

                                Text {
                                    width: 45
                                    text: parent.parent.modelData.value + "%"
                                    color: shellTheme.textPrimary
                                    horizontalAlignment: Text.AlignRight
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 9
                                }
                            }

                            Rectangle {
                                width: parent.width
                                height: 4
                                radius: height / 2
                                color: shellTheme.surfaceHover
                                clip: true

                                Rectangle {
                                    width: parent.width * Math.min(100, parent.parent.modelData.value) / 100
                                    height: parent.height
                                    radius: parent.radius
                                    color: shellTheme.textPrimary
                                }
                            }
                        }
                    }
                }
            }

            Item {
                opacity: root.sidebarDisplayKey === "tray"
                    ? root.sidebarPageOpacity : 0
                visible: opacity > 0
                anchors.fill: parent

                Text {
                    anchors {
                        top: parent.top
                        left: parent.left
                        topMargin: 13
                        leftMargin: 16
                    }
                    text: "AKTIVE APPS"
                    color: shellTheme.textPrimary
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                    font.weight: Font.Bold
                }

                Text {
                    anchors {
                        top: parent.top
                        left: parent.left
                        topMargin: 31
                        leftMargin: 16
                    }
                    text: "Anklicken zum Öffnen"
                    color: shellTheme.textMuted
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 8
                }

                Column {
                    id: inlineTrayList
                    anchors {
                        top: parent.top
                        left: parent.left
                        right: parent.right
                        topMargin: 53
                        leftMargin: 10
                        rightMargin: 10
                    }
                    spacing: 1

                    Repeater {
                        model: SystemTray.items.values.slice(0, 5)

                        delegate: Item {
                            id: trayAppRow
                            required property var modelData
                            required property int index
                            property string displayName: modelData.title
                                || modelData.tooltipTitle
                                || modelData.id
                                || "Unbekannte App"
                            property bool isBoltSnap: (
                                (modelData.id || "") + " "
                                + (modelData.title || "") + " "
                                + (modelData.tooltipTitle || "")
                            ).toLowerCase().includes("boltsnap")
                            property bool isChatGpt: (modelData.id || "")
                                .toLowerCase().includes("chatgpt")
                            property bool isChrome: (modelData.id || "")
                                .toLowerCase().includes("chrome")
                            width: parent.width
                            height: 38

                            Rectangle {
                                anchors.fill: parent
                                radius: 9
                                color: inlineTrayMouse.containsMouse
                                    ? shellTheme.surfaceHover : "transparent"

                                Behavior on color { ColorAnimation { duration: 110 } }
                            }

                            IconImage {
                                anchors {
                                    left: parent.left
                                    leftMargin: 7
                                    verticalCenter: parent.verticalCenter
                                }
                                width: 23
                                height: 23
                                source: trayAppRow.isBoltSnap
                                    ? "file:///home/mika/System/dotfiles/.config/quickshell/assets/boltsnap.svg"
                                    : (trayAppRow.isChatGpt
                                        ? "file:///usr/share/icons/hicolor/256x256/apps/codex-desktop.png"
                                        : (trayAppRow.isChrome
                                            ? Quickshell.iconPath("google-chrome")
                                            : modelData.icon))
                            }

                            Column {
                                anchors {
                                    left: parent.left
                                    leftMargin: 40
                                    right: parent.right
                                    rightMargin: 55
                                    verticalCenter: parent.verticalCenter
                                }
                                spacing: 1

                                Text {
                                    width: parent.width
                                    text: trayAppRow.displayName
                                    color: shellTheme.textPrimary
                                    elide: Text.ElideRight
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 9
                                    font.weight: Font.DemiBold
                                }

                                Text {
                                    width: parent.width
                                    text: "System-Tray"
                                    color: shellTheme.textDisabled
                                    elide: Text.ElideRight
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 7
                                }
                            }

                            Row {
                                anchors {
                                    right: parent.right
                                    rightMargin: 7
                                    verticalCenter: parent.verticalCenter
                                }
                                spacing: 5

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 5
                                    height: 5
                                    radius: width / 2
                                    color: shellTheme.textSecondary
                                }

                                Text {
                                    text: "AKTIV"
                                    color: shellTheme.textMuted
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 7
                                }
                            }

                            MouseArea {
                                id: inlineTrayMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: root.keepSidebarHover()
                                onPressed: root.holdSidebarInteraction()
                                onClicked: {
                                    root.keepSidebarHover()
                                    modelData.activate()
                                }
                            }

                            Rectangle {
                                visible: trayAppRow.index < Math.min(
                                    5, SystemTray.items.values.length) - 1
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    bottom: parent.bottom
                                    leftMargin: 40
                                    rightMargin: 7
                                }
                                height: 1
                                color: shellTheme.surfaceHover
                            }
                        }
                    }

                    Text {
                        visible: SystemTray.items.values.length === 0
                        width: parent.width
                        height: 70
                        text: "KEINE AKTIVEN APPS"
                        color: shellTheme.textDisabled
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 8
                    }

                    Text {
                        visible: SystemTray.items.values.length > 5
                        width: parent.width
                        height: 24
                        text: "+" + (SystemTray.items.values.length - 5)
                            + " WEITERE APPS"
                        color: shellTheme.textMuted
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 8
                        font.weight: Font.Bold
                    }
                }

                Rectangle {
                    anchors {
                        left: parent.left
                        bottom: parent.bottom
                        leftMargin: 16
                        bottomMargin: 12
                    }
                    width: 118
                    height: 23
                    radius: height / 2
                    color: shellTheme.surfaceHover

                    Text {
                        anchors.centerIn: parent
                        text: SystemTray.items.values.length + " APPS AKTIV"
                        color: shellTheme.textSecondary
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 8
                        font.weight: Font.DemiBold
                    }
                }
            }
        }
    }

    PanelWindow {
        id: topFrame
        screen: root.barScreen
        visible: root.barScreen !== null && !root.fullscreenActive
        color: "transparent"
        implicitHeight: 42
        exclusiveZone: 14

        anchors {
            top: true
            left: true
            right: true
        }

    }

    PanelWindow {
        id: bottomFrame
        screen: root.barScreen
        visible: root.barScreen !== null && !root.fullscreenActive
        color: "transparent"
        implicitHeight: 42
        exclusiveZone: 14

        anchors {
            bottom: true
            left: true
            right: true
        }

    }

    PanelWindow {
        id: rightFrame
        screen: root.barScreen
        visible: root.barScreen !== null && !root.fullscreenActive
        color: "transparent"
        implicitWidth: 14
        exclusiveZone: 14

        anchors {
            top: true
            bottom: true
            right: true
        }

    }

    PanelWindow {
        id: statsWindow
        screen: root.barScreen
        visible: false
        color: "transparent"
        implicitWidth: 190
        implicitHeight: 126
        exclusiveZone: 0

        anchors {
            bottom: true
            left: true
        }

        margins {
            left: 6
            bottom: 56
        }

        Rectangle {
            anchors.fill: parent
            color: shellTheme.surface
            radius: 16
            border.width: 1
            border.color: shellTheme.textBright

            Column {
                anchors {
                    fill: parent
                    margins: 12
                }
                spacing: 9

                Text {
                    text: "SYSTEM"
                    color: shellTheme.textPrimary
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                    font.weight: Font.Bold
                }

                Row {
                    spacing: 8
                    Text {
                        width: 28
                        text: "CPU"
                        color: shellTheme.textSecondary
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 9
                    }
                    Rectangle {
                        width: 84
                        height: 6
                        radius: 3
                        color: shellTheme.surfaceHover
                        anchors.verticalCenter: parent.verticalCenter
                        Rectangle {
                            width: parent.width * Math.min(100, root.cpuUsage) / 100
                            height: parent.height
                            radius: parent.radius
                            color: shellTheme.textPrimary
                        }
                    }
                    Text {
                        width: 34
                        text: root.cpuUsage + "%"
                        color: shellTheme.textPrimary
                        horizontalAlignment: Text.AlignRight
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 9
                    }
                }

                Row {
                    spacing: 8
                    Text {
                        width: 28
                        text: "GPU"
                        color: shellTheme.textSecondary
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 9
                    }
                    Rectangle {
                        width: 84
                        height: 6
                        radius: 3
                        color: shellTheme.surfaceHover
                        anchors.verticalCenter: parent.verticalCenter
                        Rectangle {
                            width: parent.width * Math.min(100, root.gpuUsage) / 100
                            height: parent.height
                            radius: parent.radius
                            color: shellTheme.textPrimary
                        }
                    }
                    Text {
                        width: 34
                        text: root.gpuUsage + "%"
                        color: shellTheme.textPrimary
                        horizontalAlignment: Text.AlignRight
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 9
                    }
                }

                Row {
                    spacing: 8
                    Text {
                        width: 28
                        text: "RAM"
                        color: shellTheme.textSecondary
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 9
                    }
                    Rectangle {
                        width: 84
                        height: 6
                        radius: 3
                        color: shellTheme.surfaceHover
                        anchors.verticalCenter: parent.verticalCenter
                        Rectangle {
                            width: parent.width * Math.min(100, root.memoryUsage) / 100
                            height: parent.height
                            radius: parent.radius
                            color: shellTheme.textPrimary
                        }
                    }
                    Text {
                        width: 34
                        text: root.memoryUsage + "%"
                        color: shellTheme.textPrimary
                        horizontalAlignment: Text.AlignRight
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 9
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onEntered: {
                    statsCloseTimer.stop()
                    root.statsOpen = true
                }
                onExited: statsCloseTimer.restart()
            }
        }
    }

    PanelWindow {
        id: trayWindow
        screen: root.barScreen
        visible: false
        color: "transparent"
        implicitWidth: Math.max(32, trayRow.implicitWidth + 12)
        implicitHeight: 36
        exclusiveZone: 0

        anchors {
            bottom: true
            left: true
        }

        margins {
            left: 4
            bottom: 80
        }

        Rectangle {
            anchors.fill: parent
            color: shellTheme.surface
            radius: 12
            border.width: 1
            border.color: shellTheme.textBright

            Row {
                id: trayRow
                anchors.centerIn: parent
                spacing: 4

                Repeater {
                    model: SystemTray.items

                    delegate: Item {
                        required property var modelData
                        property bool isBoltSnap: (
                            (modelData.id || "") + " "
                            + (modelData.title || "") + " "
                            + (modelData.tooltipTitle || "")
                        ).toLowerCase().includes("boltsnap")
                        width: 22
                        height: 22

                        IconImage {
                            anchors.centerIn: parent
                            width: 14
                            height: 14
                            source: parent.isBoltSnap
                                ? "file:///home/mika/System/dotfiles/.config/quickshell/assets/boltsnap.svg"
                                : Quickshell.iconPath(modelData.icon)
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: modelData.activate()
                        }
                    }
                }

                Text {
                    visible: SystemTray.items.values.length === 0
                    text: "–"
                    color: shellTheme.textMuted
                    font.pixelSize: 16
                }
            }
        }
    }
}

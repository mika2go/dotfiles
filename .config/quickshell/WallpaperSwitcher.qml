pragma ComponentBehavior: Bound

import QtQuick
import Qt.labs.folderlistmodel
import Quickshell.Io

Item {
    id: picker

    required property var theme
    property bool shown: false
    property bool windowVisible: false
    property bool entered: false
    property bool suppressed: false
    property bool refreshPending: false
    property bool openingPending: false
    property bool committing: false
    property real wheelAccumulator: 0
    property int wheelDirectionLock: 0
    property int selectedIndex: -1
    property string selectedPath: ""
    property string selectedFamily: ""
    property string activePath: ""
    property string searchText: ""
    property string mediaMode: "static"
    property string pendingMediaMode: "static"
    property string statusMessage: ""
    property string previewedPath: ""
    property bool videoSupportAvailable: false
    property int visiblePage: 0
    property int realWallpaperCount: 0
    property int realFilteredCount: 0

    readonly property int pageCount: realFilteredCount
    property real offsetScale: picker.entered ? 0 : 1
    readonly property real morphProgress: 1 - offsetScale

    visible: !picker.suppressed && picker.windowVisible

    Behavior on offsetScale {
        NumberAnimation {
            duration: 500
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.38, 1.21, 0.22, 1.0, 1.0, 1.0]
        }
    }

    function wallpaperEntry(source) {
        return {
            filePath: source.filePath,
            fileUrl: source.fileUrl,
            fileName: source.fileName,
            relativePath: source.relativePath || source.fileName,
            family: source.family,
            familyColor: source.familyColor,
            dominantColor: source.dominantColor,
            hue: Number(source.hue || 0),
            mediaType: source.mediaType || "static",
            isAnimated: Boolean(source.isAnimated),
            placeholder: false
        }
    }

    function refreshWallpapers() {
        if (indexer.running) {
            picker.refreshPending = true
            return
        }
        picker.refreshPending = false
        indexer.running = true
    }

    function rebuildFilteredModel() {
        const query = picker.searchText.trim().toLowerCase()
        const matches = []

        for (let index = 0; index < wallpaperModel.count; ++index) {
            const entry = wallpaperModel.get(index)
            const searchable = (
                entry.relativePath + " " + entry.family
            ).toLowerCase()
            const modeMatches = picker.mediaMode === "animated"
                ? entry.isAnimated : !entry.isAnimated
            if (modeMatches && (query.length === 0
                    || searchable.indexOf(query) !== -1))
                matches.push(picker.wallpaperEntry(entry))
        }

        filteredWallpaperModel.clear()
        picker.realFilteredCount = matches.length
        for (let index = 0; index < matches.length; ++index)
            filteredWallpaperModel.append(matches[index])

        let restoredIndex = -1
        const preferredPath = picker.selectedPath.length > 0
            ? picker.selectedPath : picker.activePath
        if (preferredPath.length > 0) {
            for (let index = 0; index < filteredWallpaperModel.count; ++index) {
                if (!filteredWallpaperModel.get(index).placeholder
                        && filteredWallpaperModel.get(index).filePath
                            === preferredPath) {
                    restoredIndex = index
                    break
                }
            }
        }
        if (restoredIndex < 0 && picker.realFilteredCount > 0)
            restoredIndex = 0

        picker.selectedIndex = restoredIndex
        picker.visiblePage = Math.max(0, restoredIndex)
        picker.updateSelected()

        Qt.callLater(function() {
            wallpaperGrid.currentIndex = picker.selectedIndex
            picker.finishOpening()
        })
    }

    function loadWallpaperIndex(rawData) {
        let data
        try {
            data = JSON.parse(rawData)
        } catch (error) {
            console.warn("Wallpaper-Farbindex konnte nicht gelesen werden:", error)
            return
        }

        const previousSelection = picker.selectedPath
        picker.activePath = data.currentPath || picker.activePath
        picker.videoSupportAvailable = Boolean(data.videoSupport)
        picker.selectedPath = picker.openingPending
            || previousSelection.length === 0
            ? picker.activePath : previousSelection

        wallpaperModel.clear()
        picker.realWallpaperCount = data.wallpapers.length
        for (let index = 0; index < data.wallpapers.length; ++index)
            wallpaperModel.append(picker.wallpaperEntry(data.wallpapers[index]))

        if (picker.openingPending && picker.activePath.length > 0) {
            for (let index = 0; index < wallpaperModel.count; ++index) {
                const entry = wallpaperModel.get(index)
                if (entry.filePath === picker.activePath) {
                    picker.mediaMode = entry.isAnimated
                        ? "animated" : "static"
                    break
                }
            }
        }

        picker.rebuildFilteredModel()
    }

    function updateSelected() {
        if (picker.selectedIndex < 0
                || picker.selectedIndex >= filteredWallpaperModel.count) {
            picker.selectedPath = ""
            picker.selectedFamily = ""
            if (picker.shown && picker.entered
                    && picker.previewedPath.length > 0)
                picker.clearPreview()
            return
        }

        const entry = filteredWallpaperModel.get(picker.selectedIndex)
        if (entry.placeholder) {
            picker.selectedPath = ""
            picker.selectedFamily = ""
            return
        }
        picker.selectedPath = entry.filePath
        picker.selectedFamily = entry.family
        picker.schedulePreview()
    }

    function schedulePreview() {
        if (!picker.shown || !picker.entered || picker.committing
                || picker.selectedPath.length === 0
                || picker.selectedPath === picker.previewedPath)
            return
        const entry = filteredWallpaperModel.get(picker.selectedIndex)
        if (entry.mediaType === "video"
                && !picker.videoSupportAvailable)
            return
        previewTimer.restart()
    }

    function clearPreview() {
        previewTimer.stop()
        picker.previewedPath = ""
        if (previewer.running)
            previewer.running = false
        previewer.command = [
            "/home/mika/.config/quickshell/scripts/preview-wallpaper.sh",
            "clear"
        ]
        previewer.running = true
    }

    function finishOpening() {
        if (!picker.openingPending || !picker.shown)
            return

        picker.openingPending = false
        picker.windowVisible = true
        enterTimer.restart()
        focusTimer.restart()
    }

    function open() {
        closeTimer.stop()
        enterTimer.stop()
        focusTimer.stop()
        picker.entered = false
        picker.windowVisible = false
        picker.openingPending = true
        picker.shown = true
        picker.refreshWallpapers()
    }

    function close() {
        picker.shown = false
        picker.openingPending = false
        picker.entered = false
        if (!picker.committing)
            picker.clearPreview()
        closeTimer.restart()
    }

    function toggle() {
        picker.shown ? picker.close() : picker.open()
    }

    function handleQuery(query) {
        picker.searchText = query
        picker.selectedPath = picker.activePath
        picker.rebuildFilteredModel()
    }

    function setMediaMode(mode) {
        if (mode !== "static" && mode !== "animated")
            return
        if (mode === picker.mediaMode)
            return
        if (picker.shown && picker.entered) {
            picker.pendingMediaMode = mode
            modeSwitchAnimation.restart()
            return
        }
        picker.applyMediaMode(mode)
    }

    function applyMediaMode(mode) {
        picker.mediaMode = mode
        picker.selectedPath = picker.activePath
        picker.rebuildFilteredModel()
    }

    function handleWheel(wheel) {
        const angleX = Number(wheel.angleDelta.x || 0)
        const angleY = Number(wheel.angleDelta.y || 0)
        const pixelX = Number(wheel.pixelDelta.x || 0)
        const pixelY = Number(wheel.pixelDelta.y || 0)
        const angleDelta = Math.abs(angleX) > Math.abs(angleY)
            ? angleX : angleY
        const pixelDelta = Math.abs(pixelX) > Math.abs(pixelY)
            ? pixelX : pixelY
        const usesAngleDelta = angleDelta !== 0
        const delta = usesAngleDelta ? angleDelta : pixelDelta
        if (delta === 0)
            return

        wheel.accepted = true
        wheelAccumulatorReset.restart()
        if (picker.wheelAccumulator !== 0
                && Math.sign(delta) !== Math.sign(picker.wheelAccumulator))
            picker.wheelAccumulator = 0

        picker.wheelAccumulator += delta
        const threshold = usesAngleDelta ? 120 : 36
        if (Math.abs(picker.wheelAccumulator) < threshold)
            return

        const requestedDirection =
            picker.wheelAccumulator > 0 ? -1 : 1
        picker.wheelAccumulator = 0
        if (picker.wheelDirectionLock === 0)
            picker.wheelDirectionLock = requestedDirection
        if (picker.wheelDirectionLock > 0)
            wallpaperGrid.incrementCurrentIndex()
        else
            wallpaperGrid.decrementCurrentIndex()
    }

    function showPage(page) {
        if (picker.pageCount === 0)
            return

        const target = ((page % picker.pageCount)
            + picker.pageCount) % picker.pageCount
        const current = wallpaperGrid.currentIndex
        if (target === (current + 1) % picker.pageCount)
            wallpaperGrid.incrementCurrentIndex()
        else if (target === (current - 1 + picker.pageCount)
                % picker.pageCount)
            wallpaperGrid.decrementCurrentIndex()
        else
            wallpaperGrid.currentIndex = target
    }

    function moveHorizontal(direction) {
        picker.showPage(picker.selectedIndex + direction)
    }

    function moveVertical(direction) {
        picker.moveHorizontal(direction)
    }

    function selectForKeyboard(index) {
        picker.showPage(index)
    }

    function applySelected(index) {
        if (index < 0 || index >= filteredWallpaperModel.count)
            return
        const entry = filteredWallpaperModel.get(index)
        if (entry.placeholder)
            return
        if (entry.mediaType === "video"
                && !picker.videoSupportAvailable) {
            picker.statusMessage =
                "Video-Unterstützung fehlt: qt6-multimedia installieren"
            statusMessageTimer.restart()
            return
        }

        picker.selectedIndex = index
        picker.selectedPath = entry.filePath
        picker.activePath = entry.filePath
        picker.committing = true
        previewTimer.stop()
        if (previewer.running)
            previewer.running = false
        setter.command = [
            "/home/mika/.config/quickshell/scripts/set-wallpaper.sh",
            entry.filePath
        ]
        setter.running = true
        picker.close()
    }

    IpcHandler {
        target: "wallpaper"

        function toggle(): void { picker.toggle() }
        function open(): void { picker.open() }
        function close(): void { picker.close() }
        function nextPage(): void { picker.showPage(picker.visiblePage + 1) }
        function previousPage(): void { picker.showPage(picker.visiblePage - 1) }
        function query(text: string): void {
            picker.handleQuery(text)
        }
        function mode(mode: string): void { picker.setMediaMode(mode) }
        function status(): string {
            return JSON.stringify({
                shown: picker.shown,
                entered: picker.entered,
                progress: Number(picker.morphProgress.toFixed(3)),
                page: picker.visiblePage,
                pages: picker.pageCount,
                selected: picker.selectedIndex,
                filtered: picker.realFilteredCount,
                total: picker.realWallpaperCount,
                carouselOffset: wallpaperGrid.offset,
                visibleItems: wallpaperGrid.pathItemCount,
                viewportWidth: wallpaperGrid.width,
                videoSupport: picker.videoSupportAvailable
            })
        }
    }

    ListModel {
        id: wallpaperModel
    }

    ListModel {
        id: filteredWallpaperModel
    }

    FolderListModel {
        id: wallpaperWatcher

        folder: "file:///home/mika/System/dotfiles/.config/hypr/wallpapers"
        nameFilters: [
            "*.png", "*.jpg", "*.jpeg", "*.webp",
            "*.gif", "*.mp4", "*.webm", "*.mkv", "*.mov"
        ]
        showDirs: true
        onCountChanged: watcherRefresh.restart()
        onStatusChanged: {
            if (status === FolderListModel.Ready)
                watcherRefresh.restart()
        }
    }

    Connections {
        target: wallpaperWatcher

        function onDataChanged() { watcherRefresh.restart() }
        function onRowsInserted() { watcherRefresh.restart() }
        function onRowsRemoved() { watcherRefresh.restart() }
    }

    Process {
        id: indexer

        command: [
            "/home/mika/.config/quickshell/scripts/wallpaper-index.py",
            "/home/mika/System/dotfiles/.config/hypr/wallpapers"
        ]
        stdout: StdioCollector {
            onStreamFinished: picker.loadWallpaperIndex(text)
        }
        onRunningChanged: {
            if (!running && picker.refreshPending)
                watcherRefresh.restart()
        }
    }

    Process {
        id: setter

        onExited: exitCode => {
            picker.committing = false
            picker.previewedPath = ""
            if (exitCode !== 0) {
                picker.statusMessage =
                    "Wallpaper konnte nicht aktiviert werden"
                statusMessageTimer.restart()
                picker.clearPreview()
                picker.refreshWallpapers()
            }
        }
    }

    Process {
        id: previewer
    }

    Component.onCompleted: picker.refreshWallpapers()

    Timer {
        id: enterTimer
        interval: 16
        onTriggered: {
            picker.entered = true
            picker.schedulePreview()
        }
    }

    Timer {
        id: previewTimer
        interval: 110
        onTriggered: {
            if (!picker.shown || picker.committing
                    || picker.selectedPath.length === 0)
                return
            picker.previewedPath = picker.selectedPath
            if (previewer.running)
                previewer.running = false
            previewer.command = [
                "/home/mika/.config/quickshell/scripts/preview-wallpaper.sh",
                "preview",
                picker.selectedPath
            ]
            previewer.running = true
        }
    }

    Timer {
        id: watcherRefresh
        interval: 300
        onTriggered: picker.refreshWallpapers()
    }

    Timer {
        id: closeTimer
        interval: 515
        onTriggered: {
            if (!picker.shown)
                picker.windowVisible = false
        }
    }

    Timer {
        id: focusTimer
        interval: 40
        onTriggered: wallpaperGrid.forceActiveFocus()
    }

    Timer {
        id: wheelAccumulatorReset
        interval: 180
        onTriggered: {
            picker.wheelAccumulator = 0
            picker.wheelDirectionLock = 0
        }
    }

    Timer {
        id: statusMessageTimer
        interval: 4000
        onTriggered: picker.statusMessage = ""
    }

    SequentialAnimation {
        id: modeSwitchAnimation

        NumberAnimation {
            target: wallpaperGrid
            property: "opacity"
            to: 0
            duration: 120
            easing.type: Easing.OutCubic
        }
        ScriptAction {
            script: picker.applyMediaMode(picker.pendingMediaMode)
        }
        NumberAnimation {
            target: wallpaperGrid
            property: "opacity"
            to: 1
            duration: 280
            easing.type: Easing.OutCubic
        }
    }

    Item {
        id: shelfContent

        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
            bottomMargin: (-height - 5) * picker.offsetScale
        }
        width: parent.width
        height: parent.height
        opacity: 1 - picker.offsetScale
        visible: picker.windowVisible && picker.offsetScale < 1

        WallpaperControls {
            id: toolbar

            theme: picker.theme
            anchors {
                top: parent.top
                topMargin: 12
                left: parent.left
                leftMargin: 12
                right: parent.right
                rightMargin: 12
            }
            wallpaperCount: picker.realFilteredCount
            loading: indexer.running
            mediaMode: picker.mediaMode
            onRefreshRequested: picker.refreshWallpapers()
            onMediaModeRequested: mode => picker.setMediaMode(mode)
        }

        PathView {
            id: wallpaperGrid

            anchors {
                top: toolbar.bottom
                topMargin: 5
                left: parent.left
                leftMargin: 9
                right: parent.right
                rightMargin: 9
                bottom: parent.bottom
                bottomMargin: 0
            }
            model: filteredWallpaperModel
            pathItemCount: {
                const visible = Math.min(5, count)
                if (visible === 2)
                    return 1
                if (visible > 1 && visible % 2 === 0)
                    return visible - 1
                return visible
            }
            cacheItemCount: 4
            clip: true
            interactive: count > 1
            snapMode: PathView.SnapToItem
            preferredHighlightBegin: 0.5
            preferredHighlightEnd: 0.5
            highlightRangeMode: PathView.StrictlyEnforceRange
            highlightMoveDuration: 360
            flickDeceleration: 3400

            Keys.onEscapePressed: picker.close()
            Keys.onLeftPressed: picker.moveHorizontal(-1)
            Keys.onRightPressed: picker.moveHorizontal(1)
            Keys.onUpPressed: picker.moveHorizontal(-1)
            Keys.onDownPressed: picker.moveHorizontal(1)
            Keys.onReturnPressed: picker.applySelected(picker.selectedIndex)
            Keys.onEnterPressed: picker.applySelected(picker.selectedIndex)
            Keys.onPressed: event => {
                if ((event.modifiers & Qt.ControlModifier)
                        && event.key === Qt.Key_Tab) {
                    picker.setMediaMode(picker.mediaMode === "static"
                        ? "animated" : "static")
                    event.accepted = true
                    return
                }
            }

            onCurrentIndexChanged: {
                if (currentIndex < 0
                        || currentIndex >= filteredWallpaperModel.count)
                    return
                picker.selectedIndex = currentIndex
                picker.visiblePage = currentIndex
                picker.updateSelected()
            }

            MouseArea {
                anchors.fill: parent
                z: 2
                acceptedButtons: Qt.NoButton
                onWheel: wheel => picker.handleWheel(wheel)
            }

            path: Path {
                startX: -115
                startY: wallpaperGrid.height / 2

                PathLine {
                    x: wallpaperGrid.width / 2
                    y: wallpaperGrid.height / 2
                }
                PathLine {
                    x: wallpaperGrid.width + 115
                    y: wallpaperGrid.height / 2
                }
            }

            delegate: WallpaperCarouselItem {
                id: wallpaperTile

                theme: picker.theme
                active: filePath === picker.activePath
                viewMoving: wallpaperGrid.moving
                onFocusRequested: wallpaperGrid.currentIndex = index
                onActivated: picker.applySelected(index)
                onPreviewReadyChanged: {
                    if (previewReady && index === picker.selectedIndex)
                        Qt.callLater(picker.finishOpening)
                }
            }
        }

        Text {
            anchors.centerIn: wallpaperGrid
            visible: picker.realFilteredCount === 0
                || picker.statusMessage.length > 0
            text: picker.statusMessage.length > 0
                ? picker.statusMessage
                : (picker.searchText.length > 0
                    ? "Keine passenden Wallpaper"
                    : (picker.mediaMode === "animated"
                        ? "Keine animierten Wallpaper gefunden"
                        : "Keine Wallpaper gefunden"))
            color: picker.theme.textMuted
            font.pixelSize: 11
            z: 6
        }

    }
}

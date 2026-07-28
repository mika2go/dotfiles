pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.UPower
import Quickshell.Wayland

Scope {
    id: engine

    property string currentPath: ""
    property string fallbackPath: ""
    property string previewPath: ""
    property string previewFallbackPath: ""
    property bool manualPaused: false
    property bool pauseOnBattery: true
    property bool pauseWhenCovered: true
    property int pauseRevision: 0

    readonly property bool previewActive: previewPath.length > 0
    readonly property string effectivePath:
        previewActive ? previewPath : currentPath
    readonly property string effectiveFallbackPath:
        previewActive ? previewFallbackPath : fallbackPath
    readonly property string extension: {
        const clean = effectivePath.toLowerCase()
        const index = clean.lastIndexOf(".")
        return index >= 0 ? clean.slice(index + 1) : ""
    }
    readonly property bool isVideo:
        ["mp4", "webm", "mkv", "mov"].includes(extension)
    readonly property bool isGif: extension === "gif"
    readonly property bool animatedActive: isVideo || isGif
    readonly property url currentUrl: effectivePath.length > 0
        ? "file://" + effectivePath : ""
    readonly property url fallbackUrl: effectiveFallbackPath.length > 0
        ? "file://" + effectiveFallbackPath : ""

    function loadState() {
        const lines = stateFile.text().split("\n")
        engine.currentPath = (lines[0] || "").trim()
        engine.fallbackPath = (lines[1] || lines[0] || "").trim()
    }

    function loadPreview() {
        const lines = previewFile.text().split("\n")
        engine.previewPath = (lines[0] || "").trim()
        engine.previewFallbackPath = (lines[1] || lines[0] || "").trim()
    }

    function clearPreview() {
        engine.previewPath = ""
        engine.previewFallbackPath = ""
    }

    function coveredFor(screen) {
        engine.pauseRevision
        if (!engine.pauseWhenCovered)
            return false

        const monitor = Hyprland.monitorFor(screen)
        const workspace = monitor && monitor.activeWorkspace
            ? monitor.activeWorkspace : null
        if (!workspace)
            return false
        if (workspace.hasFullscreen)
            return true

        const toplevels = workspace.toplevels
            ? workspace.toplevels.values : []
        if (toplevels.length >= 2)
            return true
        if (toplevels.length === 0 || !monitor)
            return false

        const size = toplevels[0].lastIpcObject
            ? toplevels[0].lastIpcObject.size : null
        const screenArea = screen.width * screen.height
        return !!size && size.length >= 2 && screenArea > 0
            && size[0] * size[1] >= screenArea * 0.7
    }

    FileView {
        id: stateFile

        path: "/home/mika/.cache/quickshell/wallpaper-engine-current"
        preload: true
        watchChanges: true
        printErrors: false
        onLoaded: engine.loadState()
        onFileChanged: reload()
    }

    FileView {
        id: previewFile

        path: "/home/mika/.cache/quickshell/wallpaper-engine-preview"
        preload: true
        watchChanges: true
        printErrors: false
        onLoaded: engine.loadPreview()
        onFileChanged: reload()
        onLoadFailed: engine.clearPreview()
    }

    Timer {
        interval: 500
        repeat: true
        running: engine.animatedActive
        onTriggered: engine.pauseRevision++
    }

    IpcHandler {
        target: "wallpaper-engine"

        function pause(): void { engine.manualPaused = true }
        function play(): void { engine.manualPaused = false }
        function status(): string {
            return JSON.stringify({
                path: engine.currentPath,
                effectivePath: engine.effectivePath,
                preview: engine.previewActive,
                animated: engine.animatedActive,
                video: engine.isVideo,
                gif: engine.isGif,
                manuallyPaused: engine.manualPaused,
                onBattery: UPower.onBattery
            })
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: backgroundWindow

            required property var modelData
            readonly property bool paused:
                engine.manualPaused
                || (engine.pauseOnBattery && UPower.onBattery)
                || engine.coveredFor(backgroundWindow.modelData)

            screen: modelData
            visible: engine.animatedActive
            color: "black"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.namespace: "quickshell:wallpaper-engine"

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            mask: Region {}

            Image {
                anchors.fill: parent
                source: engine.fallbackUrl
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                visible: engine.animatedActive && (
                    engine.isGif
                        ? animatedGif.status !== Image.Ready
                        : (!videoLoader.item || !videoLoader.item.frameReady)
                )
            }

            AnimatedImage {
                id: animatedGif

                anchors.fill: parent
                source: engine.isGif ? engine.currentUrl : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                playing: engine.isGif && !backgroundWindow.paused
                visible: engine.isGif && status === Image.Ready
            }

            Loader {
                id: videoLoader

                anchors.fill: parent
                active: engine.isVideo
                source: "VideoWallpaper.qml"

                onLoaded: backgroundWindow.syncVideo()
            }

            function syncVideo() {
                if (!videoLoader.item)
                    return
                videoLoader.item.videoSource = engine.currentUrl
                videoLoader.item.autoStart = !backgroundWindow.paused
            }

            Connections {
                target: engine

                function onEffectivePathChanged() {
                    Qt.callLater(backgroundWindow.syncVideo)
                }
            }

            onPausedChanged: {
                if (!videoLoader.item)
                    return
                videoLoader.item.autoStart = !paused
                if (paused)
                    videoLoader.item.pause()
                else
                    videoLoader.item.play()
            }
        }
    }
}

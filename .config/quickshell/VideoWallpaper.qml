pragma ComponentBehavior: Bound

import QtQuick
import QtMultimedia

Item {
    id: root

    property url videoSource
    property bool autoStart: true
    property bool frameReady: false
    property bool usePlayerA: true
    property bool swapping: false
    property bool pendingSwapToA: true

    readonly property int playbackState: usePlayerA
        ? playerA.playbackState : playerB.playbackState
    readonly property int mediaStatus: usePlayerA
        ? playerA.mediaStatus : playerB.mediaStatus
    readonly property int error: usePlayerA ? playerA.error : playerB.error
    readonly property string errorString: usePlayerA
        ? playerA.errorString : playerB.errorString

    function activePlayer() {
        if (root.swapping)
            return root.pendingSwapToA ? playerA : playerB
        return root.usePlayerA ? playerA : playerB
    }

    function play() {
        if (root.videoSource.toString().length > 0)
            root.activePlayer().play()
    }

    function pause() {
        root.activePlayer().pause()
    }

    function clear() {
        deferredSwap.stop()
        playerA.stop()
        playerB.stop()
        playerA.source = ""
        playerB.source = ""
        root.frameReady = false
        root.swapping = false
    }

    function scheduleSwap(toA) {
        root.swapping = true
        root.pendingSwapToA = toA
        const outgoing = toA ? playerB : playerA
        outgoing.pause()
        deferredSwap.restart()
    }

    function completeSwap() {
        const toA = root.pendingSwapToA
        const incoming = toA ? playerA : playerB
        const outgoing = toA ? playerB : playerA

        if (root.autoStart)
            incoming.play()
        else
            incoming.pause()

        root.usePlayerA = toA
        Qt.callLater(function() {
            outgoing.stop()
            outgoing.source = ""
            root.swapping = false
        })
    }

    onVideoSourceChanged: {
        root.frameReady = false
        if (videoSource.toString().length === 0) {
            root.clear()
            return
        }

        if (playerA.source.toString().length === 0
                && playerB.source.toString().length === 0) {
            root.usePlayerA = true
            playerA.source = videoSource
            return
        }

        const incoming = root.usePlayerA ? playerB : playerA
        incoming.source = videoSource
    }

    onAutoStartChanged: {
        if (autoStart)
            root.play()
        else
            root.pause()
    }

    Timer {
        id: deferredSwap
        interval: 100
        onTriggered: root.completeSwap()
    }

    VideoOutput {
        id: outputA
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectCrop
        visible: root.usePlayerA
    }

    AudioOutput {
        id: mutedOutputA
        muted: true
        volume: 0
    }

    MediaPlayer {
        id: playerA

        videoOutput: outputA
        audioOutput: mutedOutputA
        loops: MediaPlayer.Infinite
        autoPlay: false

        onPositionChanged: {
            if (root.usePlayerA && position > 0)
                root.frameReady = true
        }
        onMediaStatusChanged: {
            if (!root.usePlayerA && !root.swapping
                    && mediaStatus === MediaPlayer.LoadedMedia)
                root.scheduleSwap(true)
            else if (root.usePlayerA
                    && playerB.source.toString().length === 0
                    && mediaStatus === MediaPlayer.LoadedMedia) {
                if (root.autoStart)
                    playerA.play()
            }
        }
        onErrorOccurred: (error, message) => {
            if (error !== MediaPlayer.NoError)
                console.warn("Wallpaper video A:", message)
        }
    }

    VideoOutput {
        id: outputB
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectCrop
        visible: !root.usePlayerA
    }

    AudioOutput {
        id: mutedOutputB
        muted: true
        volume: 0
    }

    MediaPlayer {
        id: playerB

        videoOutput: outputB
        audioOutput: mutedOutputB
        loops: MediaPlayer.Infinite
        autoPlay: false

        onPositionChanged: {
            if (!root.usePlayerA && position > 0)
                root.frameReady = true
        }
        onMediaStatusChanged: {
            if (root.usePlayerA && !root.swapping
                    && mediaStatus === MediaPlayer.LoadedMedia)
                root.scheduleSwap(false)
        }
        onErrorOccurred: (error, message) => {
            if (error !== MediaPlayer.NoError)
                console.warn("Wallpaper video B:", message)
        }
    }

    Component.onDestruction: root.clear()
}

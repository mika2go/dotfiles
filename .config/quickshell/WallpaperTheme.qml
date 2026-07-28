import QtQuick
import Quickshell
import Quickshell.Io

// One palette for the complete shell. The wallpaper index already contains
// the dominant colour for static and animated wallpapers, so the shell only
// has to watch the selected path and turn that colour into contrast-safe
// semantic roles.
Scope {
    id: theme

    property string committedPath: ""
    property string previewPath: ""
    property var colorCache: ({})

    readonly property string effectivePath: previewPath.length > 0
        ? previewPath : committedPath
    readonly property color fallbackSource: "#405079"
    readonly property color sourceColor: {
        const cached = theme.colorCache[theme.effectivePath]
        const dominant = cached && cached.colors
            ? cached.colors.dominantColor : ""
        return dominant && dominant.length > 0
            ? dominant : theme.fallbackSource
    }

    // Dark, clearly wallpaper-tinted surfaces preserve the light-on-dark
    // contrast while carrying enough saturation to visually match the image.
    readonly property color surfaceDeep:
        theme.tone(theme.sourceColor, 0.045, 1.10, 0.97)
    readonly property color surface:
        theme.tone(theme.sourceColor, 0.085, 1.15, 0.94)
    readonly property color surfaceGlass:
        theme.tone(theme.sourceColor, 0.10, 1.22, 0.76)
    readonly property color surfaceRaised:
        theme.tone(theme.sourceColor, 0.13, 1.18, 0.95)
    readonly property color surfaceHover:
        theme.tone(theme.sourceColor, 0.19, 1.22, 0.97)
    readonly property color surfaceActive:
        theme.tone(theme.sourceColor, 0.26, 1.25, 0.98)
    readonly property color surfaceSubtle:
        theme.tone(theme.sourceColor, 0.15, 1.08, 0.34)
    readonly property color scrim:
        theme.tone(theme.sourceColor, 0.025, 0.95, 0.74)
    readonly property color hoverScrim:
        theme.tone(theme.sourceColor, 0.035, 0.90, 0.20)

    readonly property color outline:
        theme.tone(theme.sourceColor, 0.38, 1.10, 0.86)
    readonly property color outlineSubtle:
        theme.tone(theme.sourceColor, 0.29, 1.00, 0.68)
    readonly property color track:
        theme.tone(theme.sourceColor, 0.24, 1.16, 0.96)

    readonly property color textDisabled:
        theme.tone(theme.sourceColor, 0.44, 0.40, 1.0)
    readonly property color textMuted:
        theme.tone(theme.sourceColor, 0.60, 0.34, 1.0)
    readonly property color textSecondary:
        theme.tone(theme.sourceColor, 0.78, 0.28, 1.0)
    readonly property color textPrimary:
        theme.tone(theme.sourceColor, 0.93, 0.24, 1.0)
    readonly property color textBright:
        theme.tone(theme.sourceColor, 0.985, 0.12, 1.0)

    readonly property color accent:
        theme.tone(theme.sourceColor, 0.72, 1.70, 1.0)
    readonly property color accentHover:
        theme.tone(theme.sourceColor, 0.84, 1.45, 1.0)
    readonly property color accentMuted:
        theme.tone(theme.sourceColor, 0.52, 1.55, 1.0)
    readonly property color onAccent:
        theme.tone(theme.sourceColor, 0.045, 0.85, 1.0)

    function tone(base, lightness, saturationScale, alpha) {
        const hue = base.hslHue >= 0 ? base.hslHue : 0.62
        const sourceSaturation = Math.max(0.16, base.hslSaturation)
        const saturation = Math.max(
            0.08,
            Math.min(0.82, sourceSaturation * saturationScale)
        )
        return Qt.hsla(hue, saturation, lightness, alpha)
    }

    function loadPath(file, preview) {
        const path = (file.text().split("\n")[0] || "").trim()
        if (preview)
            theme.previewPath = path
        else
            theme.committedPath = path
    }

    function loadCache() {
        try {
            const parsed = JSON.parse(cacheFile.text())
            theme.colorCache = parsed && parsed.files
                ? parsed.files : ({})
        } catch (error) {
            console.warn("Wallpaper-Theme konnte den Farbcache nicht lesen:",
                error)
            theme.colorCache = ({})
        }
    }

    IpcHandler {
        target: "theme"

        function status(): string {
            return JSON.stringify({
                path: theme.effectivePath,
                preview: theme.previewPath.length > 0,
                source: String(theme.sourceColor),
                surface: String(theme.surface),
                accent: String(theme.accent),
                text: String(theme.textPrimary)
            })
        }
    }

    FileView {
        id: stateFile

        path: "/home/mika/.cache/quickshell/wallpaper-engine-current"
        preload: true
        watchChanges: true
        printErrors: false
        onLoaded: theme.loadPath(stateFile, false)
        onFileChanged: reload()
    }

    FileView {
        id: previewFile

        path: "/home/mika/.cache/quickshell/wallpaper-engine-preview"
        preload: true
        watchChanges: true
        printErrors: false
        onLoaded: theme.loadPath(previewFile, true)
        onFileChanged: reload()
        onLoadFailed: theme.previewPath = ""
    }

    FileView {
        id: cacheFile

        path: "/home/mika/.cache/quickshell/wallpaper-colors.json"
        preload: true
        watchChanges: true
        printErrors: false
        onLoaded: theme.loadCache()
        onFileChanged: reload()
        onLoadFailed: theme.colorCache = ({})
    }
}

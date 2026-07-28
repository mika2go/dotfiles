pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

Scope {
    id: center

    property bool suppressed: false
    property bool shown: false
    property bool windowVisible: false
    property real offsetScale: shown ? 0 : 1
    readonly property real progress: 1 - offsetScale
    property var entries: []
    property int revision: 0
    property bool stateLoaded: false
    readonly property int activeCount: {
        center.revision
        return center.entries.filter(entry => !entry.closed).length
    }
    readonly property var popupEntries: {
        center.revision
        return center.entries.filter(entry => entry.popup && !entry.closed)
    }
    readonly property var groups: {
        center.revision
        const grouped = new Map()
        for (const entry of center.entries) {
            const key = entry.appName || "Anwendung"
            if (!grouped.has(key))
                grouped.set(key, [])
            grouped.get(key).push(entry)
        }
        return Array.from(grouped, pair => ({
            appName: pair[0],
            entries: pair[1]
        }))
    }

    Behavior on offsetScale {
        NumberAnimation {
            duration: 500
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.38, 1.21, 0.22, 1.0, 1.0, 1.0]
        }
    }

    function entryChanged(): void {
        center.revision++
        if (center.stateLoaded)
            saveTimer.restart()
    }

    function addNotification(notification): void {
        notification.tracked = true
        const currentId = String(notification.id)
        const existing = center.entries.find(entry =>
            entry.notificationId === currentId)
        if (existing) {
            existing.notification = notification
            existing.persisted = false
            existing.popup = !center.shown && !center.suppressed
            existing.syncFromNotification()
            center.entryChanged()
            return
        }

        const entry = entryComponent.createObject(center, {
            owner: center,
            notification: notification,
            popup: !center.shown && !center.suppressed
        })
        if (!entry)
            return

        center.entries = [entry, ...center.entries]
        center.trimHistory()
        center.entryChanged()
    }

    function restoreEntry(properties): void {
        const duplicate = center.entries.find(entry =>
            entry.notificationId === (properties.notificationId || "")
                && entry.appName === (properties.appName || "Anwendung")
                && entry.summary === (properties.summary
                    || "Benachrichtigung")
                && entry.body === (properties.body || ""))
        if (duplicate) {
            duplicate.createdAt = Number(properties.createdAt)
                || duplicate.createdAt
            return
        }

        const entry = entryComponent.createObject(center, {
            owner: center
        })
        if (!entry)
            return
        entry["restore"](properties)
        center.entries.push(entry)
    }

    function trimHistory(): void {
        while (center.entries.length > 100) {
            const oldest = center.entries.pop()
            if (oldest.notification)
                oldest.notification.expire()
            oldest.destroy()
        }
    }

    function hideAllPopups(): void {
        for (const entry of center.entries)
            entry.popup = false
        center.entryChanged()
    }

    function open(): void {
        if (center.suppressed)
            return
        closeTimer.stop()
        center.windowVisible = true
        center.hideAllPopups()
        center.shown = true
    }

    function close(): void {
        if (!center.windowVisible)
            return
        center.shown = false
        closeTimer.restart()
    }

    function toggle(): void {
        center.shown ? center.close() : center.open()
    }

    function clear(): void {
        for (const entry of center.entries.slice())
            entry.dismiss()
    }

    function finalizeRemoval(entry): void {
        if (!entry.closed || !center.entries.includes(entry))
            return
        center.entries = center.entries.filter(candidate => candidate !== entry)
        center.entryChanged()
        entry.destroy()
    }

    function serializableEntries(): var {
        return center.entries
            .filter(entry => !entry.closed)
            .slice(0, 100)
            .map(entry => ({
                createdAt: entry.createdAt,
                notificationId: entry.notificationId,
                appName: entry.appName,
                appIcon: entry.appIcon,
                summary: entry.summary,
                body: entry.body,
                image: entry.image,
                urgency: entry.urgency,
                expireTimeout: entry.expireTimeout,
                resident: entry.resident
            }))
    }

    onSuppressedChanged: {
        if (center.suppressed)
            center.close()
    }

    NotificationServer {
        id: notificationServer

        keepOnReload: true
        persistenceSupported: true
        bodySupported: true
        bodyMarkupSupported: false
        bodyHyperlinksSupported: false
        bodyImagesSupported: true
        actionsSupported: true
        actionIconsSupported: false
        imageSupported: true
        inlineReplySupported: false

        onNotification: notification => center.addNotification(notification)
    }

    FileView {
        id: historyFile

        path: Quickshell.env("HOME")
            + "/.local/state/quickshell-notifications.json"
        preload: true
        printErrors: false
        atomicWrites: true

        onLoaded: {
            try {
                const raw = historyFile.text().trim()
                const restored = raw.length > 0 ? JSON.parse(raw) : []
                if (Array.isArray(restored)) {
                    for (const properties of restored.slice(0, 100))
                        center.restoreEntry(properties)
                }
            } catch (error) {
                console.warn("Notification-Verlauf konnte nicht geladen werden:",
                    error)
            }
            center.entries.sort((a, b) => b.createdAt - a.createdAt)
            center.stateLoaded = true
            center.entryChanged()
        }

        onLoadFailed: {
            center.stateLoaded = true
        }
    }

    Timer {
        id: saveTimer
        interval: 250
        onTriggered: historyFile.setText(JSON.stringify(
            center.serializableEntries()))
    }

    Timer {
        id: closeTimer
        interval: 515
        onTriggered: {
            if (!center.shown)
                center.windowVisible = false
        }
    }

    IpcHandler {
        target: "notifications"

        function toggle(): void { center.toggle() }
        function open(): void { center.open() }
        function close(): void { center.close() }
        function clear(): void { center.clear() }
        function status(): string {
            return JSON.stringify({
                shown: center.shown,
                windowVisible: center.windowVisible,
                suppressed: center.suppressed,
                offsetScale: center.offsetScale,
                activeCount: center.activeCount,
                popupCount: center.popupEntries.length
            })
        }
    }

    Component {
        id: entryComponent

        NotificationEntry {}
    }
}

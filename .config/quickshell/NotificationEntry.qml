import QtQuick

QtObject {
    id: entry

    required property var owner
    property var notification: null
    property bool popup: false
    property bool closed: false
    property bool persisted: false
    property real createdAt: Date.now()
    property string notificationId: ""
    property string appName: ""
    property string appIcon: ""
    property string summary: ""
    property string body: ""
    property string image: ""
    property int urgency: 1
    property real expireTimeout: 6000
    property bool resident: false
    property var actions: []

    function syncFromNotification(): void {
        if (!entry.notification)
            return

        entry.notificationId = String(entry.notification.id)
        entry.appName = entry.notification.appName || "Anwendung"
        entry.appIcon = entry.notification.appIcon || ""
        entry.summary = entry.notification.summary || "Benachrichtigung"
        entry.body = entry.notification.body || ""
        entry.image = entry.notification.image || ""
        entry.urgency = Number(entry.notification.urgency)
        entry.expireTimeout = Number(entry.notification.expireTimeout)
        entry.resident = !!entry.notification.resident
        entry.actions = entry.notification.actions || []
        entry.owner.entryChanged()
    }

    function expirePopup(): void {
        if (!entry.popup)
            return
        entry.popup = false
        entry.owner.entryChanged()
    }

    function invokeAction(action): void {
        if (action && action.invoke)
            action.invoke()
        entry.expirePopup()
    }

    function dismiss(): void {
        if (entry.closed)
            return

        entry.popup = false
        entry.closed = true
        if (entry.notification)
            entry.notification.dismiss()
        entry.owner.entryChanged()
        removalTimer.restart()
    }

    function restore(properties): void {
        entry.persisted = true
        entry.popup = false
        entry.createdAt = Number(properties.createdAt) || Date.now()
        entry.notificationId = properties.notificationId || ""
        entry.appName = properties.appName || "Anwendung"
        entry.appIcon = properties.appIcon || ""
        entry.summary = properties.summary || "Benachrichtigung"
        entry.body = properties.body || ""
        entry.image = properties.image || ""
        const restoredUrgency = Number(properties.urgency)
        entry.urgency = Number.isFinite(restoredUrgency)
            ? restoredUrgency : 1
        entry.expireTimeout = Number(properties.expireTimeout) || 6000
        entry.resident = !!properties.resident
        entry.actions = []
    }

    readonly property Connections notificationConnections: Connections {
        target: entry.notification
        ignoreUnknownSignals: true

        function onSummaryChanged(): void { entry.syncFromNotification() }
        function onBodyChanged(): void { entry.syncFromNotification() }
        function onAppIconChanged(): void { entry.syncFromNotification() }
        function onAppNameChanged(): void { entry.syncFromNotification() }
        function onImageChanged(): void { entry.syncFromNotification() }
        function onExpireTimeoutChanged(): void { entry.syncFromNotification() }
        function onUrgencyChanged(): void { entry.syncFromNotification() }
        function onResidentChanged(): void { entry.syncFromNotification() }
        function onActionsChanged(): void { entry.syncFromNotification() }

        function onClosed(reason): void {
            entry.notification = null
            entry.actions = []
            entry.popup = false
            entry.owner.entryChanged()
        }
    }

    readonly property Timer removalTimer: Timer {
        interval: 515
        onTriggered: entry.owner.finalizeRemoval(entry)
    }

    Component.onCompleted: {
        if (entry.notification)
            entry.syncFromNotification()
    }
}

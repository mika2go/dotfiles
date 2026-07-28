# Upstream design reference

This SDDM theme is an original monochrome adaptation of the Caelestia lock-screen layout.
It does not bundle Caelestia or require Quickshell at login time.

- Project: https://github.com/caelestia-dots/shell
- Inspected commit: `fbb3d1be076b34b7e83e4470f4ef3b76a10ec496`
- Reference modules: `modules/lock/Content.qml`, `Center.qml`, `Fetch.qml`,
  `Resources.qml`, `Media.qml`, `NotifDock.qml`, and `center/PasswordInput.qml`
- Upstream license: GPL-3.0

Adapted for SDDM/Qt 6 on 2026-07-27. Runtime-only Quickshell features such as
weather, notifications, media control, and resource services were replaced with
SDDM-native session, user, authentication, host, and power controls.

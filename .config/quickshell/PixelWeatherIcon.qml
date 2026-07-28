import QtQuick

Item {
    id: root

    property int code: 0
    property bool isDay: true
    property color color: "white"

    implicitWidth: 48
    implicitHeight: 44

    readonly property int columns: 12
    readonly property var pattern: pixelPattern(code, isDay)
    readonly property int rows: pattern.length
    readonly property int pixelSize: Math.max(1, Math.floor(Math.min(
        width / columns, height / rows)))
    readonly property int drawingWidth: columns * pixelSize
    readonly property int drawingHeight: rows * pixelSize

    function pixelPattern(weatherCode, day) {
        if (weatherCode <= 1) {
            return day ? [
                "     ##     ",
                "  .  ##  .  ",
                "   ######   ",
                "  ########  ",
                ".### ## ###.",
                "####    ####",
                "#### ## ####",
                " ########## ",
                "   ######   ",
                "  .  ##  .  ",
                "     ##     "
            ] : [
                "       ###  ",
                "     ###### ",
                "    ####    ",
                "   ####     ",
                "   ###   .  ",
                "   ###      ",
                "   ####  .  ",
                "    ######  ",
                "     #####  ",
                "       ###  ",
                "            "
            ]
        }

        if (weatherCode >= 95) {
            return [
                "     ...    ",
                "    #####   ",
                "  ########  ",
                " ## # #  ## ",
                "##       ###",
                " ########## ",
                "     ##     ",
                "    ###     ",
                "     ##     ",
                "    ##      ",
                "            "
            ]
        }

        if ((weatherCode >= 51 && weatherCode <= 67)
                || (weatherCode >= 80 && weatherCode <= 82)) {
            return [
                "     ...    ",
                "    #####   ",
                "  ########  ",
                " ## # #  ## ",
                "##       ###",
                " ########## ",
                "            ",
                "  ##  ##    ",
                "  ##  ## ## ",
                "      ## ## ",
                "            "
            ]
        }

        if (weatherCode >= 71 && weatherCode <= 77) {
            return [
                "     ...    ",
                "    #####   ",
                "  ########  ",
                " ## # #  ## ",
                "##       ###",
                " ########## ",
                "            ",
                " .#.  .#.   ",
                "  #  .###.  ",
                " .#.   #    ",
                "            "
            ]
        }

        if (weatherCode === 45 || weatherCode === 48) {
            return [
                "            ",
                "    #####   ",
                "  ########  ",
                " ## # #  ## ",
                "##       ###",
                " ########## ",
                "            ",
                "............",
                "  ........  ",
                "............",
                "            "
            ]
        }

        return [
            "       ##   ",
            "    .  ## . ",
            "     ####   ",
            "    ####    ",
            "  ########  ",
            " ## # #  ## ",
            "##       ###",
            " ########## ",
            "            ",
            "            ",
            "            "
        ]
    }

    Repeater {
        model: root.rows * root.columns

        Rectangle {
            required property int index
            readonly property int row: Math.floor(index / root.columns)
            readonly property int column: index % root.columns
            readonly property string pixel: root.pattern[row].charAt(column)

            x: Math.floor((root.width - root.drawingWidth) / 2)
                + column * root.pixelSize
            y: Math.floor((root.height - root.drawingHeight) / 2)
                + row * root.pixelSize
            width: root.pixelSize
            height: root.pixelSize
            visible: pixel !== " "
            color: root.color
            opacity: pixel === "." ? 0.45 : 1
            antialiasing: false
        }
    }
}

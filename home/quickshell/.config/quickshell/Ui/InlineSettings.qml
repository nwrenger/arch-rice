import QtQuick
import qs.Commons

Item {
    id: root

    default property alias content: contentColumn.data
    property color accent: Theme.mauve
    property alias spacing: contentColumn.spacing
    readonly property real contentWidth: contentColumn.width

    implicitHeight: contentColumn.implicitHeight + 8

    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.topMargin: 4
        anchors.bottomMargin: 4
        width: 2
        radius: 1
        color: root.accent
        opacity: 0.65
    }

    Column {
        id: contentColumn

        x: 14
        width: parent.width - x
        spacing: 4
    }
}

import QtQuick
import qs.Commons

Item {
    property real verticalPadding: 0

    width: parent ? parent.width : 100
    implicitWidth: 100
    implicitHeight: line.height + verticalPadding * 2
    height: implicitHeight

    Rectangle {
        id: line

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: 1
        color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.12)
    }
}

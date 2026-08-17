import QtQuick
import qs.Commons

Rectangle {
    id: root

    property string text: ""
    property string popupName: ""
    property color foreground: Theme.text
    property bool active: false

    signal clicked(int button)
    signal wheel(int delta)

    implicitWidth: Math.max(32, label.implicitWidth + 24)
    implicitHeight: Theme.barHeight
    color: mouse.containsMouse || root.active ? Theme.surface0 : Qt.rgba(Theme.surface0.r, Theme.surface0.g, Theme.surface0.b, 0)

    Text {
        id: label
        anchors.centerIn: parent
        text: root.text
        color: root.foreground
        font.family: Theme.fontFamily
        font.pixelSize: 13
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onPressed: Util.callAncestor(root.parent, "barInteraction", {
            "popupName": root.popupName,
            "trayItem": null
        })
        onClicked: function(event) { root.clicked(event.button) }
        onWheel: function(event) { root.wheel(event.angleDelta.y) }
    }

    Behavior on color { ColorAnimation { duration: 100 } }
}

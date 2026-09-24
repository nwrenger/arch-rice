import QtQuick
import qs.Commons

Rectangle {
    id: root

    property bool checked: false
    property color accent: Theme.mauve
    property bool keyboardFocusVisible: false
    property bool mouseHighlightEnabled: true
    readonly property bool keyboardNavigable: true

    signal toggled()

    implicitWidth: 34
    implicitHeight: 18
    radius: height / 2
    color: checked ? accent : Theme.surface1
    border.width: keyboardFocusVisible ? 1 : 0
    border.color: Theme.text

    function keyboardActivate() {
        root.toggled();
    }

    function syncHoverNavigation() {
        Util.callAncestor(root.parent, "hoverNavigationItem", root);
    }

    Rectangle {
        width: 14
        height: 14
        radius: 7
        x: root.checked ? root.width - width - 2 : 2
        anchors.verticalCenter: parent.verticalCenter
        color: root.checked ? Theme.base : Theme.subtext0

        Behavior on x {
            NumberAnimation {
                duration: 120
                easing.type: Easing.OutCubic
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: root.syncHoverNavigation()
        onPositionChanged: root.syncHoverNavigation()
        onClicked: {
            root.syncHoverNavigation();
            root.toggled();
        }
    }
}

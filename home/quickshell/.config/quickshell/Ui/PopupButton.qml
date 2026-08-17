import QtQuick
import qs.Commons

Rectangle {
    id: root

    property string text: ""
    property string icon: ""
    property color accent: Theme.mauve
    property bool highlighted: false
    property bool keyboardFocusVisible: false
    property bool mouseHighlightEnabled: true
    readonly property bool keyboardNavigable: true
    readonly property bool navigationFocusVisible: keyboardFocusVisible

    signal clicked()

    implicitWidth: label.implicitWidth + 28
    implicitHeight: 34
    activeFocusOnTab: false
    radius: Theme.radius
    color: (mouse.containsMouse && mouseHighlightEnabled) || navigationFocusVisible ? Theme.surface1 : Theme.surface0
    border.width: navigationFocusVisible ? 1 : 0
    border.color: accent

    Keys.onReturnPressed: root.clicked()
    Keys.onEnterPressed: root.clicked()
    Keys.onSpacePressed: root.clicked()

    function keyboardActivate() {
        root.clicked();
    }

    function syncHoverNavigation() {
        Util.callAncestor(root.parent, "hoverNavigationItem", root);
    }

    Text {
        id: label

        anchors.centerIn: parent
        text: (root.icon ? root.icon + "  " : "") + root.text
        color: root.highlighted ? root.accent : Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: 12
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: root.syncHoverNavigation()
        onPositionChanged: root.syncHoverNavigation()
        onClicked: {
            root.syncHoverNavigation();
            root.forceActiveFocus(Qt.MouseFocusReason);
            root.clicked();
        }
    }

}

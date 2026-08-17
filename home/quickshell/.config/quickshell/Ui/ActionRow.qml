import QtQuick
import qs.Commons

Rectangle {
    id: root

    property string icon: ""
    property url iconSource: ""
    property string label: ""
    property string detail: ""
    property bool reserveIconSpace: true
    property bool selected: false
    property bool accented: false
    property bool current: false
    property bool focusOnClick: true
    property color accent: Theme.mauve
    property bool keyboardFocusVisible: false
    property bool mouseHighlightEnabled: true
    readonly property bool keyboardNavigable: true
    readonly property bool navigationFocusVisible: keyboardFocusVisible

    signal activated()
    signal secondaryActivated()
    signal scrollRequested(real delta)
    signal pointerInteraction()

    implicitHeight: detail ? 58 : 46
    activeFocusOnTab: false
    radius: Theme.radius
    color: current || (mouse.containsMouse && mouseHighlightEnabled) || navigationFocusVisible ? Theme.surface0 : "transparent"
    border.width: navigationFocusVisible ? 1 : 0
    border.color: accent

    Keys.onReturnPressed: root.activated()
    Keys.onEnterPressed: root.activated()
    Keys.onSpacePressed: root.activated()
    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Menu) {
            root.secondaryActivated();
            event.accepted = true;
        }
    }

    function keyboardActivate() {
        root.activated();
    }

    function keyboardSecondaryActivate() {
        root.secondaryActivated();
    }

    function syncHoverNavigation() {
        Util.callAncestor(root.parent, "hoverNavigationItem", root);
    }

    Row {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        spacing: root.reserveIconSpace ? 12 : 0

        Item {
            width: root.reserveIconSpace ? 26 : 0
            height: parent.height
            visible: root.reserveIconSpace

            Image {
                anchors.centerIn: parent
                width: 26
                height: 26
                visible: root.iconSource.toString() !== ""
                source: root.iconSource
                sourceSize.width: 52
                sourceSize.height: 52
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
            }

            Text {
                anchors.fill: parent
                visible: root.iconSource.toString() === ""
                text: root.icon
                color: root.selected || root.accented ? root.accent : Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 19
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

        }

        Column {
            width: parent.width - (root.reserveIconSpace ? 38 : 0)
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
                width: parent.width
                text: root.label
                color: root.selected || root.accented ? root.accent : Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 15
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                visible: root.detail !== ""
                text: root.detail
                color: Theme.subtext0
                font.family: Theme.fontFamily
                font.pixelSize: 11
                elide: Text.ElideRight
            }

        }

    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onEntered: {
            root.syncHoverNavigation();
            root.pointerInteraction();
        }
        onPositionChanged: {
            root.syncHoverNavigation();
            root.pointerInteraction();
        }
        onClicked: function (event) {
            root.syncHoverNavigation();
            root.pointerInteraction();
            if (root.focusOnClick)
                root.forceActiveFocus(Qt.MouseFocusReason);
            if (event.button === Qt.RightButton)
                root.secondaryActivated();
            else
                root.activated();
        }
        onWheel: function(event) {
            root.scrollRequested(Util.wheelDistance(event));
            event.accepted = true;
        }
    }

}

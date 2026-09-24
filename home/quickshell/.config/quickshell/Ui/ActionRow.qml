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
    property real singleLineHeight: 38
    property real detailedHeight: 50
    property real horizontalPadding: 10
    property real contentSpacing: 10
    property real iconSlotWidth: 26
    property real iconImageSize: 22
    property real iconSourceSize: 44
    property real iconFontSize: 16
    property real labelFontSize: 12
    property real detailFontSize: 10
    readonly property bool keyboardNavigable: true
    readonly property bool navigationFocusVisible: keyboardFocusVisible

    signal activated()
    signal secondaryActivated()
    signal scrollRequested(real delta)
    signal pointerInteraction()

    implicitHeight: detail ? detailedHeight : singleLineHeight
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
        anchors.leftMargin: root.horizontalPadding
        anchors.rightMargin: root.horizontalPadding
        spacing: root.reserveIconSpace ? root.contentSpacing : 0

        Item {
            id: iconSlot

            width: root.reserveIconSpace ? root.iconSlotWidth : 0
            height: parent.height
            visible: root.reserveIconSpace

            Image {
                anchors.centerIn: parent
                width: root.iconImageSize
                height: root.iconImageSize
                visible: root.iconSource.toString() !== ""
                source: root.iconSource
                sourceSize.width: root.iconSourceSize
                sourceSize.height: root.iconSourceSize
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
                font.pixelSize: root.iconFontSize
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

        }

        Column {
            width: parent.width - iconSlot.width - parent.spacing
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
                width: parent.width
                text: root.label
                color: root.selected || root.accented ? root.accent : Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: root.labelFontSize
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                visible: root.detail !== ""
                text: root.detail
                color: Theme.subtext0
                font.family: Theme.fontFamily
                font.pixelSize: root.detailFontSize
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

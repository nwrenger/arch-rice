import QtQuick
import QtQuick.Controls
import qs.Commons

Item {
    id: root

    property string icon: ""
    property string label: ""
    property real value: 0
    property color accent: Theme.mauve
    property bool keyboardFocusVisible: false
    property bool mouseHighlightEnabled: true
    readonly property bool keyboardNavigable: true
    readonly property bool navigationFocusVisible: keyboardFocusVisible

    signal iconClicked()
    signal moved(real value)

    implicitHeight: 52
    activeFocusOnTab: false

    function keyboardActivate() {
        root.iconClicked();
    }

    function keyboardAdjust(direction) {
        if (direction > 0)
            slider.increase();
        else
            slider.decrease();
        root.moved(slider.value);
    }

    function syncHoverNavigation() {
        Util.callAncestor(root.parent, "hoverNavigationItem", root);
    }

    Keys.onLeftPressed: {
        slider.decrease();
        root.moved(slider.value);
    }
    Keys.onRightPressed: {
        slider.increase();
        root.moved(slider.value);
    }
    Keys.onSpacePressed: root.iconClicked()

    HoverHandler {
        onHoveredChanged: {
            if (hovered)
                root.syncHoverNavigation();
        }
        onPointChanged: {
            if (hovered)
                root.syncHoverNavigation();
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: -3
        radius: Theme.radius
        color: "transparent"
        border.width: root.navigationFocusVisible ? 1 : 0
        border.color: root.accent
    }

    Text {
        id: iconLabel

        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 27
        text: root.icon
        color: root.accent
        font.family: Theme.fontFamily
        font.pixelSize: 18
        horizontalAlignment: Text.AlignHCenter
    }

    MouseArea {
        anchors.fill: iconLabel
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            root.forceActiveFocus(Qt.MouseFocusReason);
            root.iconClicked();
        }
    }

    Text {
        anchors.left: iconLabel.right
        anchors.top: parent.top
        anchors.topMargin: 2
        text: root.label
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: 11
    }

    Text {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: 2
        text: Math.round(root.value * 100) + "%"
        color: Theme.subtext0
        font.family: Theme.fontFamily
        font.pixelSize: 11
    }

    Slider {
        id: slider

        anchors.left: iconLabel.right
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 4
        height: 24
        from: 0
        to: 1
        value: root.value
        activeFocusOnTab: false
        onMoved: root.moved(value)

        background: Rectangle {
            x: slider.leftPadding
            y: slider.topPadding + slider.availableHeight / 2 - height / 2
            width: slider.availableWidth
            height: 6
            radius: 3
            color: Theme.surface1

            Rectangle {
                width: slider.visualPosition * parent.width
                height: parent.height
                radius: parent.radius
                color: root.accent
            }

        }

        handle: Rectangle {
            x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
            y: slider.topPadding + slider.availableHeight / 2 - height / 2
            width: 14
            height: 14
            radius: 7
            color: slider.pressed ? Theme.text : root.accent
        }

    }

}

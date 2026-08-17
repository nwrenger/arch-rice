import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarPopup {
    id: root

    required property var trayItem
    property var submenuStack: []
    readonly property var currentChildren: submenuStack.length > 0 ? submenuStack[submenuStack.length - 1].opener.children : menuOpener.children
    readonly property string currentTitle: submenuStack.length > 0 ? submenuStack[submenuStack.length - 1].title : ""

    function syncNavigationAfterMenuChange() {
        Qt.callLater(function () {
            if (!root.opened)
                return;
            if (root.keyboardNavigationActive)
                root.focusNavigation(1);
            else {
                root.keyboardNavigationItem = null;
                root.updateNavigationVisuals(null);
            }
        });
    }

    function resetMenu() {
        menuScroll.contentY = 0;
        var openers = submenuStack;
        submenuStack = [];
        for (var i = openers.length - 1; i >= 0; i--)
            openers[i].opener.destroy();
    }

    function enterSubmenu(entry, title) {
        var opener = submenuOpenerComponent.createObject(root, {
            "menu": entry
        });
        if (!opener)
            return;

        menuScroll.contentY = 0;
        var stack = submenuStack.slice();
        stack.push({
            "opener": opener,
            "title": title
        });
        submenuStack = stack;
        syncNavigationAfterMenuChange();
    }

    function leaveSubmenu() {
        if (submenuStack.length === 0)
            return;

        menuScroll.contentY = 0;
        var stack = submenuStack.slice();
        var current = stack.pop();
        submenuStack = stack;
        current.opener.destroy();
        syncNavigationAfterMenuChange();
    }

    popupWidth: 290
    popupHeight: Math.min(430, Math.max(58, menuHeader.height + menuColumn.implicitHeight + 32))
    onOpenedChanged: {
        if (!opened)
            resetMenu();
    }
    onTrayItemChanged: resetMenu()

    Component {
        id: submenuOpenerComponent

        QsMenuOpener {
        }
    }

    QsMenuOpener {
        id: menuOpener

        menu: root.trayItem ? root.trayItem.menu : null
    }

    Column {
        anchors.fill: parent
        spacing: 0

        Item {
            id: menuHeader

            readonly property bool keyboardNavigable: root.submenuStack.length > 0
            property bool keyboardFocusVisible: false
            property bool mouseHighlightEnabled: true

            function keyboardActivate() {
                root.leaveSubmenu();
            }

            width: parent.width
            height: root.submenuStack.length > 0 ? 38 : 0
            visible: height > 0
            activeFocusOnTab: false

            Keys.onReturnPressed: root.leaveSubmenu()
            Keys.onEnterPressed: root.leaveSubmenu()
            Keys.onSpacePressed: root.leaveSubmenu()

            Rectangle {
                anchors.fill: parent
                radius: Theme.radius
                color: menuHeader.keyboardFocusVisible ? Theme.surface0 : "transparent"
                border.width: menuHeader.keyboardFocusVisible ? 1 : 0
                border.color: Theme.mauve
            }

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 26
                text: "‹"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 22
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 32
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.currentTitle
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.bold: true
                elide: Text.ElideRight
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.hoverNavigationItem(menuHeader)
                onPositionChanged: root.hoverNavigationItem(menuHeader)
                onPressed: root.hoverNavigationItem(menuHeader)
                onClicked: {
                    menuHeader.forceActiveFocus(Qt.MouseFocusReason);
                    root.leaveSubmenu();
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: Theme.surface1
            }
        }

        WheelScrollView {
            id: menuScroll

            width: parent.width
            height: parent.height - menuHeader.height
            contentWidth: width
            contentHeight: menuColumn.implicitHeight

            Column {
                id: menuColumn

                width: parent.width
                spacing: 0

                Repeater {
                    model: root.currentChildren

                    Item {
                        id: menuRow

                        required property var modelData
                        readonly property bool keyboardNavigable: !modelData.isSeparator && modelData.enabled
                        property bool keyboardFocusVisible: false
                        property bool mouseHighlightEnabled: true

                        width: menuColumn.width
                        height: modelData.isSeparator ? 11 : 36
                        enabled: !modelData.isSeparator && modelData.enabled
                        activeFocusOnTab: false
                        opacity: modelData.enabled ? 1 : 0.45

                        function activate() {
                            if (modelData.hasChildren)
                                root.enterSubmenu(modelData, modelData.text || "Menu");
                            else {
                                modelData.triggered();
                                root.closeRequested();
                            }
                        }

                        function keyboardActivate() {
                            activate();
                        }

                        function keyboardAdjust(direction) {
                            if (direction > 0 && modelData.hasChildren)
                                activate();
                            else if (direction < 0)
                                root.leaveSubmenu();
                        }

                        Keys.onReturnPressed: menuRow.activate()
                        Keys.onEnterPressed: menuRow.activate()
                        Keys.onSpacePressed: menuRow.activate()
                        Keys.onRightPressed: {
                            if (menuRow.modelData.hasChildren)
                                menuRow.activate();
                        }
                        Keys.onLeftPressed: root.leaveSubmenu()

                        Rectangle {
                            visible: menuRow.modelData.isSeparator
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            height: 1
                            color: Theme.surface1
                        }

                        Rectangle {
                            visible: !menuRow.modelData.isSeparator
                            anchors.fill: parent
                            radius: Theme.radius
                            color: ((rowMouse.containsMouse && menuRow.mouseHighlightEnabled) || menuRow.keyboardFocusVisible) && menuRow.modelData.enabled ? Theme.surface0 : "transparent"
                            border.width: menuRow.keyboardFocusVisible ? 1 : 0
                            border.color: Theme.mauve
                        }

                        Text {
                            visible: !menuRow.modelData.isSeparator && menuRow.modelData.buttonType !== QsMenuButtonType.None
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: 26
                            text: menuRow.modelData.checkState === Qt.Checked ? "✓" : ""
                            color: Theme.mauve
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            horizontalAlignment: Text.AlignHCenter
                        }

                        Image {
                            id: menuIcon

                            visible: !menuRow.modelData.isSeparator && String(menuRow.modelData.icon || "") !== ""
                            anchors.left: parent.left
                            anchors.leftMargin: 28
                            anchors.verticalCenter: parent.verticalCenter
                            width: 18
                            height: 18
                            source: menuRow.modelData.icon
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                        }

                        Text {
                            visible: !menuRow.modelData.isSeparator
                            anchors.left: parent.left
                            anchors.leftMargin: menuIcon.visible ? 54 : 30
                            anchors.right: submenuArrow.left
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: menuRow.modelData.text || ""
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            elide: Text.ElideRight
                        }

                        Text {
                            id: submenuArrow

                            visible: !menuRow.modelData.isSeparator && menuRow.modelData.hasChildren
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            width: 14
                            text: "›"
                            color: Theme.subtext0
                            font.family: Theme.fontFamily
                            font.pixelSize: 20
                            horizontalAlignment: Text.AlignHCenter
                        }

                        MouseArea {
                            id: rowMouse

                            anchors.fill: parent
                            enabled: !menuRow.modelData.isSeparator && menuRow.modelData.enabled
                            hoverEnabled: true
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onEntered: root.hoverNavigationItem(menuRow)
                            onPositionChanged: root.hoverNavigationItem(menuRow)
                            onPressed: root.hoverNavigationItem(menuRow)
                            onClicked: {
                                menuRow.forceActiveFocus(Qt.MouseFocusReason);
                                menuRow.activate();
                            }
                        }
                    }
                }
            }
        }
    }
}

import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Commons

PopupWindow {
    id: root

    required property Item anchorItem
    property bool opened: false
    property int popupWidth: 360
    property int popupHeight: 320
    property int popupMargin: Theme.gap
    property bool focusGrabEnabled: true
    property bool keyboardNavigationActive: false
    property var keyboardNavigationItem: null
    property var customKeyHandler: null
    property bool focusGrabReady: false
    default property alias content: contentHolder.data

    signal closeRequested()

    function collectNavigationItems(item, result, visited) {
        if (!item || visited.indexOf(item) >= 0)
            return;
        visited.push(item);

        var children = item.children || [];
        for (var i = 0; i < children.length; i++) {
            var child = children[i];
            if (!child.visible || !child.enabled)
                continue;
            if (child.keyboardNavigable === true && result.indexOf(child) < 0)
                result.push(child);
            collectNavigationItems(child, result, visited);
        }

        if (item.contentItem && item.contentItem !== item)
            collectNavigationItems(item.contentItem, result, visited);
    }

    function navigationItems() {
        var result = [];
        collectNavigationItems(contentHolder, result, []);
        return result;
    }

    function revealNavigationItem(item) {
        var ancestor = item;
        while (ancestor) {
            if (ancestor.keyboardScrollView === true) {
                ancestor.ensureItemVisible(item);
                return;
            }
            ancestor = ancestor.parent;
        }
    }

    function focusNavigation(step) {
        var items = navigationItems();
        if (items.length === 0) {
            keyboardNavigationItem = null;
            return;
        }

        var index = items.indexOf(keyboardNavigationItem);

        if (index < 0)
            index = step > 0 ? 0 : items.length - 1;
        else
            index = (index + step + items.length) % items.length;

        keyboardNavigationItem = items[index];
        updateNavigationVisuals(items[index]);
        if (items[index].keyboardNeedsFocus === true)
            items[index].forceActiveFocus(Qt.TabFocusReason);
        revealNavigationItem(items[index]);
    }

    function applyNavigationVisuals(items, activeItem, keyboardActive) {
        for (var i = 0; i < items.length; i++) {
            var current = items[i] === activeItem;
            if (items[i].keyboardFocusVisible !== undefined)
                items[i].keyboardFocusVisible = keyboardActive && current;
            if (items[i].mouseHighlightEnabled !== undefined)
                items[i].mouseHighlightEnabled = !keyboardActive || current;
        }
    }

    function updateNavigationVisuals(activeItem) {
        applyNavigationVisuals(navigationItems(), activeItem, keyboardNavigationActive);
    }

    function hoverNavigationItem(item) {
        var items = navigationItems();
        if (!item || items.indexOf(item) < 0)
            return;

        keyboardNavigationItem = item;
        updateNavigationVisuals(item);
    }

    function beginKeyboardNavigation(step) {
        if (!keyboardNavigationActive && keyboardNavigationItem) {
            keyboardNavigationActive = true;
            hoverNavigationItem(keyboardNavigationItem);
            revealNavigationItem(keyboardNavigationItem);
            return;
        }
        keyboardNavigationActive = true;
        focusNavigation(step);
    }

    function resetKeyboardNavigation() {
        var items = navigationItems();
        applyNavigationVisuals(items, null, false);
        keyboardNavigationActive = false;
        keyboardNavigationItem = null;
    }

    function handleKey(event) {
        if (!opened)
            return;

        if (customKeyHandler && customKeyHandler(event)) {
            event.accepted = true;
            return;
        }

        if (event.key === Qt.Key_Escape) {
            closeRequested();
            event.accepted = true;
            return;
        }

        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            var backwards = event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier);
            beginKeyboardNavigation(backwards ? -1 : 1);
            event.accepted = true;
            return;
        }

        if (!keyboardNavigationActive)
            return;

        if (event.key === Qt.Key_Down) {
            focusNavigation(1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Up) {
            focusNavigation(-1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            if (keyboardNavigationItem && typeof keyboardNavigationItem.keyboardActivate === "function")
                keyboardNavigationItem.keyboardActivate();
            event.accepted = true;
        } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
            if (keyboardNavigationItem && typeof keyboardNavigationItem.keyboardAdjust === "function") {
                keyboardNavigationItem.keyboardAdjust(event.key === Qt.Key_Right ? 1 : -1);
                event.accepted = true;
            }
        } else if (event.key === Qt.Key_Menu) {
            if (keyboardNavigationItem && typeof keyboardNavigationItem.keyboardSecondaryActivate === "function") {
                keyboardNavigationItem.keyboardSecondaryActivate();
                event.accepted = true;
            }
        }
    }

    function captureKeyboardFocus() {
        if (!opened)
            return;

        contentHolder.forceActiveFocus(Qt.OtherFocusReason);
    }

    visible: opened
    color: "transparent"
    implicitWidth: popupWidth
    implicitHeight: popupHeight

    Connections {
        target: root

        function onOpenedChanged() {
            root.resetKeyboardNavigation();
            root.focusGrabReady = false;
            focusGrabDelay.stop();
            if (root.opened) {
                Qt.callLater(root.captureKeyboardFocus);
                focusGrabDelay.restart();
            }
        }
    }

    Timer {
        id: focusGrabDelay

        interval: 120
        onTriggered: {
            if (root.opened)
                root.focusGrabReady = true;
        }
    }

    HyprlandFocusGrab {
        id: focusGrab

        active: root.opened && root.focusGrabEnabled && root.focusGrabReady
        windows: {
            return root.anchorItem && root.anchorItem.QsWindow.window ? [root, root.anchorItem.QsWindow.window] : [root];
        }
        onActiveChanged: {
            if (active)
                Qt.callLater(root.captureKeyboardFocus);
        }
        onCleared: {
            if (root.opened && root.focusGrabReady)
                root.closeRequested();
        }
    }

    anchor {
        id: popupAnchor

        window: root.anchorItem ? root.anchorItem.QsWindow.window : null
        adjustment: PopupAdjustment.Slide
        edges: Edges.Top | Edges.Left
        gravity: Edges.Bottom | Edges.Right
        rect.width: 1
        rect.height: 1
        onAnchoring: {
            if (!root.anchorItem || !popupAnchor.window)
                return;

            var point = popupAnchor.window.contentItem.mapFromItem(root.anchorItem, root.anchorItem.width / 2 - root.implicitWidth / 2, root.anchorItem.height + root.popupMargin);
            point.x = Util.clamp(point.x, root.popupMargin, popupAnchor.window.width - root.implicitWidth - root.popupMargin);
            popupAnchor.rect.x = Math.round(point.x);
            popupAnchor.rect.y = Math.round(point.y);
        }
    }

    Card {
        anchors.fill: parent
        color: Qt.rgba(0.118, 0.118, 0.18, 0.98)

        Item {
            id: contentHolder

            anchors.fill: parent
            anchors.margins: 16
            focus: true
            Keys.onPressed: function(event) { root.handleKey(event); }
        }

    }

}

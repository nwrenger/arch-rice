import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Notifications
import Quickshell.Wayland
import qs.Commons

Item {
    id: root

    property var entries: []
    property int nextSerial: 1

    function remove(serial, dismiss) {
        var next = [];
        for (var i = 0; i < entries.length; i++) {
            var entry = entries[i];
            if (entry.serial === serial) {
                if (dismiss) {
                    try {
                        entry.notification.dismiss();
                    } catch (e) {}
                } else {
                    try {
                        entry.notification.expire();
                    } catch (e2) {}
                }
                continue;
            }
            next.push(entry);
        }
        entries = next;
    }

    function invoke(serial) {
        for (var i = 0; i < entries.length; i++) {
            var entry = entries[i];
            if (entry.serial !== serial)
                continue;
            var actions = entry.notification.actions || [];
            for (var j = 0; j < actions.length; j++) {
                if (actions[j] && actions[j].identifier === "default") {
                    actions[j].invoke();
                    break;
                }
            }
            remove(serial, true);
            return;
        }
    }

    NotificationServer {
        id: server
        keepOnReload: false
        imageSupported: true
        actionsSupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true

        onNotification: function (notification) {
            notification.tracked = true;
            var serial = root.nextSerial++;
            var screenName = Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name || "") : "";
            root.entries = [
                {
                    notification: notification,
                    serial: serial,
                    screen: screenName
                }
            ].concat(root.entries).slice(0, 6);
            notification.closed.connect(function () {
                var next = [];
                for (var i = 0; i < root.entries.length; i++) {
                    if (root.entries[i].serial !== serial)
                        next.push(root.entries[i]);
                }
                root.entries = next;
            });
        }
    }

    Variants {
        model: Quickshell.screens

        delegate: Component {
            PanelWindow {
                id: popupWindow
                required property var modelData

                screen: modelData
                visible: root.entries.length > 0
                anchors {
                    top: true
                    bottom: true
                    left: true
                    right: true
                }
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.namespace: "arch-rice-notifications"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                mask: Region {
                    item: popupColumn
                }

                ColumnLayout {
                    id: popupColumn
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.topMargin: Theme.barHeight + Theme.gap
                    anchors.rightMargin: Theme.gap
                    spacing: 8

                    Repeater {
                        model: root.entries

                        Item {
                            required property var modelData
                            readonly property bool belongsHere: modelData.screen === "" || modelData.screen === popupWindow.modelData.name

                            visible: belongsHere
                            Layout.preferredWidth: belongsHere ? card.implicitWidth : 0
                            Layout.preferredHeight: belongsHere ? card.implicitHeight : 0

                            Timer {
                                interval: modelData.notification.urgency === NotificationUrgency.Critical ? 2147483647 : Math.max(3000, modelData.notification.expireTimeout || 5000)
                                running: parent.belongsHere
                                onTriggered: root.remove(modelData.serial, false)
                            }

                            NotificationCard {
                                id: card
                                notification: modelData.notification
                                onDismissRequested: root.remove(modelData.serial, true)
                                onActionRequested: root.invoke(modelData.serial)
                            }
                        }
                    }
                }
            }
        }
    }
}

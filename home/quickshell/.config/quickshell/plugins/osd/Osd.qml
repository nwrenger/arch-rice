import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
    id: root

    property bool opened: false
    property string icon: ""
    property string message: ""
    property real progress: -1
    property string targetScreenName: ""

    function show(iconName, text, value) {
        icon = String(iconName || "");
        message = String(text || "");
        progress = Number(value);
        targetScreenName = Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name || "") : "";
        opened = true;
        closeTimer.restart();
    }

    function close() {
        closeTimer.stop();
        opened = false;
    }

    Timer {
        id: closeTimer
        interval: 1800
        onTriggered: root.opened = false
    }

    Variants {
        model: Quickshell.screens

        delegate: Component {
            PanelWindow {
                id: panel
                required property var modelData

                screen: modelData
                visible: root.opened && (root.targetScreenName === "" || modelData.name === root.targetScreenName)
                anchors {
                    top: true
                    bottom: true
                    left: true
                    right: true
                }
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.namespace: "arch-rice-osd"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                mask: Region {}

                Card {
                    width: Math.max(210, content.implicitWidth + 32)
                    height: 66
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 68
                    color: Qt.rgba(0.118, 0.118, 0.18, 0.96)

                    Row {
                        id: content
                        anchors.centerIn: parent
                        spacing: 14

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.icon
                            color: Theme.mauve
                            font.family: Theme.fontFamily
                            font.pixelSize: 25
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 7

                            Text {
                                text: root.message
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: 14
                            }

                            Rectangle {
                                visible: root.progress >= 0
                                width: 130
                                height: 7
                                radius: height / 2
                                color: Theme.surface1

                                Rectangle {
                                    width: parent.width * Util.clamp(root.progress, 0, 1)
                                    height: parent.height
                                    radius: height / 2
                                    color: Theme.mauve
                                    Behavior on width {
                                        NumberAnimation {
                                            duration: 120
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

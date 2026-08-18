import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import Quickshell.Wayland
import Quickshell.Widgets
import "popups"
import qs.Commons
import qs.Ui

Item {
    id: root

    required property var shell
    required property var audio
    required property var media
    required property var status
    property date now: new Date()
    property string activePopup: ""
    property string activePopupScreen: ""
    readonly property var bluetoothAdapter: Bluetooth.defaultAdapter
    readonly property int bluetoothConnections: {
        var count = 0;
        var values = Bluetooth.devices ? Bluetooth.devices.values : [];
        for (var i = 0; i < values.length; i++)
            if (values[i] && values[i].connected) {
                count++;
            }
        return count;
    }

    function workspace(id) {
        var values = Hyprland.workspaces.values;
        for (var i = 0; i < values.length; i++)
            if (values[i].id === id) {
                return values[i];
            }
        return null;
    }

    function focusWorkspace(id) {
        closeActivePopup();
        Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.focus({ workspace = \"" + id + "\" })"]);
    }

    function toggleBluetooth() {
        if (!bluetoothAdapter)
            return;

        Quickshell.execDetached(["bluetoothctl", "power", bluetoothAdapter.enabled ? "off" : "on"]);
    }

    function networkText() {
        if (status.lanConnected)
            return "󰈀";
        if (status.wifiConnected)
            return "󰤨 " + status.wifiSignal + "%";
        if (status.wifiAvailable)
            return "󰤭";
        if (status.lanAvailable)
            return "󰈂";
        return "󰤮";
    }

    function togglePopup(name, screenName) {
        if (activePopup === name && activePopupScreen === screenName) {
            activePopup = "";
            activePopupScreen = "";
        } else {
            activePopup = name;
            activePopupScreen = screenName;
        }
    }

    function popupOpened(name, screenName) {
        return activePopup === name && activePopupScreen === screenName;
    }

    function closeActivePopup() {
        activePopup = "";
        activePopupScreen = "";
    }

    function closePopup(name, screenName) {
        if (activePopup !== name || (screenName && activePopupScreen !== screenName))
            return;

        activePopup = "";
        activePopupScreen = "";
    }

    function displayTrayMenu(item, anchorItem) {
        if (!item || !item.hasMenu || !anchorItem || !anchorItem.QsWindow.window)
            return;

        activePopup = "";
        activePopupScreen = "";
        var window = anchorItem.QsWindow.window;
        var point = window.contentItem.mapFromItem(anchorItem, anchorItem.width / 2, anchorItem.height / 2);
        item.display(window, Math.round(point.x), Math.round(point.y));
    }

    function prepareBarInteraction(screenName, interaction) {
        var requestedPopup = interaction && interaction.popupName ? String(interaction.popupName) : "";

        if (activePopup !== "" && (activePopupScreen !== screenName || activePopup !== requestedPopup)) {
            activePopup = "";
            activePopupScreen = "";
        }
    }

    function togglePopupForFocusedScreen(name) {
        var screenName = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : (Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "");
        if (screenName)
            togglePopup(name, screenName);
    }

    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: root.now = new Date()
    }

    Variants {
        model: Quickshell.screens

        delegate: Component {
            PanelWindow {
                id: barWindow

                required property var modelData
                readonly property bool popupAcceptsKeyboard: root.activePopup !== "" && root.activePopupScreen === modelData.name

                function activePopupObject() {
                    if (root.activePopupScreen !== modelData.name)
                        return null;
                    if (root.activePopup === "calendar")
                        return calendarPopup;
                    if (root.activePopup === "media")
                        return mediaPopup;
                    if (root.activePopup === "audio")
                        return audioPopup;
                    if (root.activePopup === "vpn")
                        return vpnPopup;
                    if (root.activePopup === "network")
                        return networkPopup;
                    if (root.activePopup === "bluetooth")
                        return bluetoothPopup;
                    return null;
                }

                function barInteraction(interaction) {
                    root.prepareBarInteraction(modelData.name, interaction);
                }

                screen: modelData
                implicitHeight: Theme.barHeight
                color: Theme.base
                exclusionMode: ExclusionMode.Auto
                WlrLayershell.namespace: "arch-rice-bar"
                WlrLayershell.layer: WlrLayer.Top
                WlrLayershell.keyboardFocus: popupAcceptsKeyboard ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

                anchors {
                    top: true
                    left: true
                    right: true
                }

                MouseArea {
                    anchors.fill: parent
                    onPressed: barWindow.barInteraction(null)
                }

                onPopupAcceptsKeyboardChanged: {
                    if (popupAcceptsKeyboard)
                        Qt.callLater(function () {
                            keyboardRouter.forceActiveFocus(Qt.OtherFocusReason);
                        });
                }

                Item {
                    id: keyboardRouter

                    anchors.fill: parent
                    focus: barWindow.popupAcceptsKeyboard
                    Keys.priority: Keys.BeforeItem
                    Keys.onPressed: function (event) {
                        var popup = barWindow.activePopupObject();
                        if (popup)
                            popup.handleKey(event);
                    }
                }

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter

                    BarButton {
                        text: "󰗀"
                        foreground: Theme.text
                        onClicked: root.shell.toggleLauncher("root")
                    }

                    Repeater {
                        model: [1, 2, 3, 4]

                        BarButton {
                            required property int modelData
                            readonly property var ws: root.workspace(modelData)
                            readonly property bool focused: Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id === modelData

                            implicitWidth: 32
                            text: focused ? "󱓻" : String(modelData)
                            foreground: Theme.text
                            opacity: ws || focused ? 1 : 0.55
                            onClicked: root.focusWorkspace(modelData)
                        }
                    }
                }

                BarButton {
                    id: clockButton

                    popupName: "calendar"
                    anchors.centerIn: parent
                    text: Qt.formatDateTime(root.now, "dddd HH:mm")
                    foreground: Theme.blue
                    active: root.popupOpened("calendar", barWindow.modelData.name)
                    onClicked: root.togglePopup("calendar", barWindow.modelData.name)
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter

                    Repeater {
                        model: SystemTray.items.values

                        Item {
                            id: trayItem

                            required property var modelData

                            width: 42
                            height: Theme.barHeight

                            IconImage {
                                anchors.centerIn: parent
                                width: 16
                                height: 16
                                source: modelData.icon
                            }

                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                cursorShape: Qt.PointingHandCursor
                                onPressed: barWindow.barInteraction({
                                    "popupName": ""
                                })
                                onClicked: function (event) {
                                    if (event.button === Qt.RightButton) {
                                        root.displayTrayMenu(modelData, trayItem);
                                        event.accepted = true;
                                    } else if (modelData.onlyMenu) {
                                        root.displayTrayMenu(modelData, trayItem);
                                    } else {
                                        modelData.activate();
                                    }
                                }
                            }
                        }
                    }

                    BarButton {
                        id: mediaButton

                        popupName: "media"
                        visible: root.media.players.length > 0
                        text: root.media.activePlayer && root.media.activePlayer.isPlaying ? "󰐊" : "󰏤"
                        foreground: Theme.green
                        active: root.popupOpened("media", barWindow.modelData.name)
                        onClicked: root.togglePopup("media", barWindow.modelData.name)
                    }

                    BarButton {
                        id: audioButton

                        popupName: "audio"
                        text: root.audio.outputMuted ? "󰝟" : (root.audio.outputVolume < 0.34 ? "󰕿" : root.audio.outputVolume < 0.67 ? "󰖀" : "󰕾")
                        foreground: root.audio.outputMuted ? Theme.overlay0 : Theme.red
                        active: root.popupOpened("audio", barWindow.modelData.name)
                        onClicked: function (button) {
                            if (button === Qt.RightButton)
                                root.audio.toggleOutput();
                            else
                                root.togglePopup("audio", barWindow.modelData.name);
                        }
                        onWheel: root.audio.adjustOutput(delta > 0 ? 0.05 : -0.05)
                    }

                    BarButton {
                        popupName: "audio"
                        text: root.audio.inputMuted ? "󰍭" : "󰍬"
                        foreground: root.audio.inputMuted ? Theme.overlay0 : Theme.yellow
                        active: root.popupOpened("audio", barWindow.modelData.name)
                        onClicked: function (button) {
                            if (button === Qt.RightButton)
                                root.audio.toggleInput();
                            else
                                root.togglePopup("audio", barWindow.modelData.name);
                        }
                        onWheel: root.audio.adjustInput(delta > 0 ? 0.05 : -0.05)
                    }

                    BarButton {
                        id: vpnButton

                        popupName: "vpn"
                        text: root.status.vpnConnected ? "󰒃" : "󰌙"
                        foreground: root.status.vpnConnected ? Theme.mauve : Theme.overlay0
                        active: root.popupOpened("vpn", barWindow.modelData.name)
                        onClicked: root.togglePopup("vpn", barWindow.modelData.name)
                    }

                    BarButton {
                        text: root.status.uxplayRunning ? "󱟲" : "󰀸"
                        foreground: root.status.uxplayRunning ? Theme.lavender : Theme.overlay0
                        onClicked: root.status.toggleUxPlay()
                    }

                    BarButton {
                        id: networkButton

                        popupName: "network"
                        text: root.networkText()
                        foreground: root.status.lanConnected || root.status.wifiConnected ? Theme.sky : Theme.overlay0
                        active: root.popupOpened("network", barWindow.modelData.name)
                        onClicked: root.togglePopup("network", barWindow.modelData.name)
                    }

                    BarButton {
                        id: bluetoothButton

                        popupName: "bluetooth"
                        text: root.bluetoothAdapter && root.bluetoothAdapter.enabled ? (root.bluetoothConnections > 0 ? "󰂱 " + root.bluetoothConnections : "󰂯") : "󰂲"
                        foreground: root.bluetoothAdapter && root.bluetoothAdapter.enabled ? Theme.sky : Theme.overlay0
                        active: root.popupOpened("bluetooth", barWindow.modelData.name)
                        onClicked: function (button) {
                            if (button === Qt.RightButton)
                                root.toggleBluetooth();
                            else
                                root.togglePopup("bluetooth", barWindow.modelData.name);
                        }
                    }

                    BarButton {
                        text: " " + root.status.cpuUsage + "%"
                        foreground: Theme.green
                        onClicked: {
                            root.closeActivePopup();
                            Quickshell.execDetached(["alacritty", "--title", "btop", "-e", "btop"]);
                        }
                    }
                }

                CalendarPopup {
                    id: calendarPopup

                    anchorItem: clockButton
                    opened: root.popupOpened("calendar", barWindow.modelData.name)
                    onCloseRequested: root.closePopup("calendar", barWindow.modelData.name)
                }

                MediaPopup {
                    id: mediaPopup

                    anchorItem: mediaButton
                    media: root.media
                    opened: root.popupOpened("media", barWindow.modelData.name)
                    onCloseRequested: root.closePopup("media", barWindow.modelData.name)
                }

                AudioPopup {
                    id: audioPopup

                    anchorItem: audioButton
                    audio: root.audio
                    opened: root.popupOpened("audio", barWindow.modelData.name)
                    onCloseRequested: root.closePopup("audio", barWindow.modelData.name)
                }

                VpnPopup {
                    id: vpnPopup

                    anchorItem: vpnButton
                    status: root.status
                    opened: root.popupOpened("vpn", barWindow.modelData.name)
                    onCloseRequested: root.closePopup("vpn", barWindow.modelData.name)
                }

                NetworkPopup {
                    id: networkPopup

                    anchorItem: networkButton
                    status: root.status
                    opened: root.popupOpened("network", barWindow.modelData.name)
                    onCloseRequested: root.closePopup("network", barWindow.modelData.name)
                }

                BluetoothPopup {
                    id: bluetoothPopup

                    anchorItem: bluetoothButton
                    opened: root.popupOpened("bluetooth", barWindow.modelData.name)
                    onCloseRequested: root.closePopup("bluetooth", barWindow.modelData.name)
                }
            }
        }
    }
}

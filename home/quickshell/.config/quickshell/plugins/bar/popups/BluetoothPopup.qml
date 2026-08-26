import QtQuick
import Quickshell
import Quickshell.Bluetooth
import qs.Commons
import qs.Ui

BarPopup {
    id: root

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var devices: sortedDevices()
    property string configuredDeviceAddress: ""

    function sortedDevices() {
        var values = Bluetooth.devices ? Bluetooth.devices.values.slice() : [];
        values.sort(function(a, b) {
            var rankA = a.connected ? 0 : (a.paired ? 1 : 2);
            var rankB = b.connected ? 0 : (b.paired ? 1 : 2);
            if (rankA !== rankB)
                return rankA - rankB;

            return deviceLabel(a).localeCompare(deviceLabel(b));
        });
        return values;
    }

    function deviceLabel(device) {
        return String(device.name || device.deviceName || device.address || "Unknown device");
    }

    function deviceDetail(device) {
        if (device.connected)
            return device.batteryAvailable ? "Connected · " + Math.round(device.battery * 100) + "% battery" : "Connected";

        if (device.pairing)
            return "Pairing…";

        if (device.paired)
            return "Paired";

        return "Available";
    }

    function activateDevice(device) {
        if (device.connected)
            device.disconnect();
        else if (device.paired)
            device.connect();
        else
            device.pair();
    }

    function deviceAddress(device) {
        return String(device && device.address || "");
    }

    function toggleDeviceConfiguration(device) {
        if (!device || !device.paired)
            return;

        var address = deviceAddress(device);
        if (!address)
            return;

        configuredDeviceAddress = configuredDeviceAddress === address ? "" : address;
    }

    function closeDeviceConfiguration() {
        configuredDeviceAddress = "";
    }

    function forgetDevice(device) {
        if (!device)
            return;

        closeDeviceConfiguration();
        device.forget();
    }

    popupWidth: 390
    popupHeight: 500
    customKeyHandler: function(event) {
        if (event.key === Qt.Key_Escape && root.configuredDeviceAddress !== "") {
            root.closeDeviceConfiguration();
            return true;
        }

        if (event.key !== Qt.Key_C)
            return false;

        var item = root.keyboardNavigationItem;
        if (!item || typeof item.keyboardConfigure !== "function")
            return false;

        item.keyboardConfigure();
        return true;
    }
    onOpenedChanged: {
        if (adapter && adapter.enabled)
            adapter.discovering = opened;
        if (!opened)
            closeDeviceConfiguration();
    }

    Column {
        anchors.fill: parent
        spacing: 10

        PopupHeader {
            width: parent.width
            icon: !root.adapter || !root.adapter.enabled ? "󰂲" : (root.adapter.discovering ? "󰂰" : "󰂯")
            title: "Bluetooth"
            subtitle: !root.adapter ? "No adapter found" : (!root.adapter.enabled ? "Powered off" : (root.adapter.discovering ? "Scanning for devices…" : "Ready"))
            accent: Theme.sky
        }

        Row {
            width: parent.width
            height: 34
            spacing: 8

            PopupButton {
                text: root.adapter && root.adapter.enabled ? "Turn off" : "Turn on"
                icon: "󰂯"
                onClicked: {
                    if (root.adapter)
                        Quickshell.execDetached(["bluetoothctl", "power", root.adapter.enabled ? "off" : "on"]);

                }
            }

            PopupButton {
                visible: root.adapter && root.adapter.enabled
                text: root.adapter && root.adapter.discovering ? "Scanning" : "Scan"
                icon: "󰑓"
                highlighted: root.adapter && root.adapter.discovering
                accent: Theme.sky
                onClicked: {
                    if (root.adapter)
                        root.adapter.discovering = !root.adapter.discovering;

                }
            }

        }

        PopupSection {
            width: parent.width
            height: 22
            text: "DEVICES"
            verticalAlignment: Text.AlignVCenter
        }

        WheelScrollView {
            width: parent.width
            height: parent.height - y
            contentWidth: width
            contentHeight: deviceList.implicitHeight

            Column {
                id: deviceList

                width: parent.width
                spacing: 3

                Text {
                    width: parent.width
                    height: 50
                    visible: root.devices.length === 0
                    text: root.adapter && root.adapter.enabled ? "No devices found" : "Turn Bluetooth on to see devices"
                    color: Theme.overlay0
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                Repeater {
                    model: root.devices

                    Item {
                        id: deviceEntry

                        required property var modelData
                        readonly property string entryAddress: root.deviceAddress(modelData)
                        readonly property bool configurationExpanded: modelData.paired && root.configuredDeviceAddress === entryAddress

                        width: deviceList.width
                        implicitHeight: deviceColumn.implicitHeight

                        Column {
                            id: deviceColumn

                            width: parent.width
                            spacing: 4

                            ActionRow {
                                id: row

                                width: parent.width
                                icon: deviceEntry.modelData.connected ? "󰂱" : (deviceEntry.modelData.paired ? "󰂯" : "󰂰")
                                label: root.deviceLabel(deviceEntry.modelData)
                                detail: root.deviceDetail(deviceEntry.modelData) + (deviceEntry.configurationExpanded ? " · Settings open" : "")
                                selected: deviceEntry.modelData.connected
                                accent: Theme.sky

                                function keyboardConfigure() {
                                    root.toggleDeviceConfiguration(deviceEntry.modelData);
                                }

                                onActivated: {
                                    if (root.configuredDeviceAddress !== "" && !deviceEntry.configurationExpanded)
                                        root.closeDeviceConfiguration();
                                    root.activateDevice(deviceEntry.modelData);
                                }
                                onSecondaryActivated: root.toggleDeviceConfiguration(deviceEntry.modelData)
                            }

                            Loader {
                                id: deviceConfigurationLoader

                                x: 24
                                width: parent.width - x
                                active: deviceEntry.configurationExpanded
                                visible: active
                                height: active && item ? item.implicitHeight : 0

                                sourceComponent: InlineSettings {
                                    width: deviceConfigurationLoader.width
                                    accent: Theme.sky

                                    PopupSection {
                                        width: parent.width
                                        height: 24
                                        text: "DEVICE SETTINGS"
                                        verticalAlignment: Text.AlignVCenter
                                    }

                                    ActionRow {
                                        width: parent.width
                                        icon: "󰆴"
                                        label: "Forget device"
                                        detail: "Remove the paired device"
                                        accented: true
                                        accent: Theme.red
                                        onActivated: root.forgetDevice(deviceEntry.modelData)
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

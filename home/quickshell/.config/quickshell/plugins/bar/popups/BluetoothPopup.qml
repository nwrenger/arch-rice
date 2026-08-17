import QtQuick
import Quickshell
import Quickshell.Bluetooth
import qs.Commons
import qs.Ui

BarPopup {
    id: root

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var devices: sortedDevices()

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

    popupWidth: 390
    popupHeight: 500
    onOpenedChanged: {
        if (adapter && adapter.enabled)
            adapter.discovering = opened;

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
                        required property var modelData

                        width: deviceList.width
                        height: row.implicitHeight

                        ActionRow {
                            id: row

                            width: parent.width - (modelData.paired ? 38 : 0)
                            icon: modelData.connected ? "󰂱" : (modelData.paired ? "󰂯" : "󰂰")
                            label: root.deviceLabel(modelData)
                            detail: root.deviceDetail(modelData)
                            selected: modelData.connected
                            accent: Theme.sky
                            onActivated: root.activateDevice(modelData)
                        }

                        PopupButton {
                            visible: modelData.paired
                            width: 34
                            height: 34
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: "󰆴"
                            onClicked: modelData.forget()
                        }

                    }

                }

            }

        }

    }

}

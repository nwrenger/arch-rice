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
    property int phraseIndex: 0
    readonly property var activePhrases: [
        "Untangling wires",
        "Streaming vikings",
        "Pairing mysteries",
        "Herding headsets",
        "Taming radios",
        "Summoning speakers",
        "Wrangling codecs",
        "Polishing packets"
    ]
    readonly property string heroStatusText: {
        if (!adapter)
            return "No adapter";
        if (!adapter.enabled)
            return "Turned off";
        return activePhrases[phraseIndex % activePhrases.length];
    }

    function sortedDevices() {
        var values = Bluetooth.devices ? Bluetooth.devices.values.slice() : [];
        values = values.filter(function (device) {
            return humanDeviceName(device) !== "";
        });
        values.sort(function (a, b) {
            var rankA = a.connected ? 0 : (a.paired ? 1 : 2);
            var rankB = b.connected ? 0 : (b.paired ? 1 : 2);
            if (rankA !== rankB)
                return rankA - rankB;

            return deviceLabel(a).localeCompare(deviceLabel(b));
        });
        return values;
    }

    function humanDeviceName(device) {
        var address = String(device && device.address || "").trim().toLowerCase();
        var candidates = [device && device.name, device && device.deviceName];
        for (var i = 0; i < candidates.length; i++) {
            var name = String(candidates[i] || "").trim();
            var normalized = name.toLowerCase();
            if (!name || normalized === address)
                continue;
            if (/^(?:[0-9a-f]{2}[:-]){5}[0-9a-f]{2}$/i.test(name))
                continue;
            if (/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(name))
                continue;
            if (/^[0-9a-f]{32}$/i.test(name) || /^0x[0-9a-f]{4,32}$/i.test(name))
                continue;
            return name;
        }
        return "";
    }

    function deviceLabel(device) {
        return humanDeviceName(device) || "Unknown device";
    }

    function deviceDetail(device) {
        if (device.connected && device.batteryAvailable)
            return Math.round(device.battery * 100) + "%";
        return "";
    }

    function deviceTransitioning(device) {
        return !!device && (device.pairing || device.state === BluetoothDeviceState.Connecting || device.state === BluetoothDeviceState.Disconnecting);
    }

    function deviceSection(device) {
        if (device && device.connected)
            return "connected";
        if (device && device.paired)
            return "paired";
        return "available";
    }

    function sectionTitle(index) {
        if (index < 0 || index >= devices.length)
            return "";
        var section = deviceSection(devices[index]);
        if (index > 0 && deviceSection(devices[index - 1]) === section)
            return "";
        if (section === "connected")
            return "CONNECTED";
        if (section === "paired")
            return "PAIRED";
        return "AVAILABLE";
    }

    function activateDevice(device) {
        if (deviceTransitioning(device))
            return;
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
    customKeyHandler: function (event) {
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
        if (!opened) {
            closeDeviceConfiguration();
            phraseIndex = 0;
        }
    }

    Timer {
        interval: 2800
        repeat: true
        running: root.opened && root.adapter && root.adapter.enabled
        onTriggered: root.phraseIndex = (root.phraseIndex + 1) % root.activePhrases.length
    }

    Column {
        anchors.fill: parent
        spacing: Theme.popupSpacing

        PopupHeader {
            width: parent.width
            icon: !root.adapter || !root.adapter.enabled ? "󰂲" : (root.adapter.discovering ? "󰂰" : "󰂯")
            title: "Bluetooth"
            subtitle: root.heroStatusText
            accent: Theme.sky
            trailingControl: Component {
                PopupToggle {
                    checked: !!root.adapter && root.adapter.enabled
                    accent: Theme.sky
                    onToggled: {
                        if (root.adapter)
                            Quickshell.execDetached(["bluetoothctl", "power", root.adapter.enabled ? "off" : "on"]);
                    }
                }
            }
        }

        WheelScrollView {
            width: parent.width
            height: parent.height - y
            contentWidth: width
            contentHeight: deviceList.implicitHeight

            Column {
                id: deviceList

                width: parent.width
                spacing: 4

                Text {
                    width: parent.width
                    height: 50
                    visible: root.devices.length === 0
                    text: !root.adapter ? "No Bluetooth adapter" : (!root.adapter.enabled ? "Turn Bluetooth on to scan" : "Scanning for devices…")
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
                        required property int index
                        readonly property string entryAddress: root.deviceAddress(modelData)
                        readonly property bool configurationExpanded: modelData.paired && root.configuredDeviceAddress === entryAddress

                        width: deviceList.width
                        implicitHeight: deviceColumn.implicitHeight

                        Column {
                            id: deviceColumn

                            width: parent.width
                            spacing: 4

                            Column {
                                width: parent.width
                                spacing: 10

                                PopupSection {
                                    width: parent.width
                                    height: visible ? 22 : 0
                                    visible: root.sectionTitle(deviceEntry.index) !== ""
                                    text: root.sectionTitle(deviceEntry.index)
                                    verticalAlignment: Text.AlignVCenter
                                }

                                ActionRow {
                                    id: row

                                    width: parent.width
                                    icon: deviceEntry.modelData.connected ? "󰂱" : (deviceEntry.modelData.paired ? "󰂯" : "󰂰")
                                    label: root.deviceLabel(deviceEntry.modelData)
                                    detail: root.deviceDetail(deviceEntry.modelData)
                                    selected: deviceEntry.modelData.connected
                                    accent: Theme.sky
                                    enabled: !root.deviceTransitioning(deviceEntry.modelData)
                                    opacity: enabled ? 1 : 0.55

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

                                    ActionRow {
                                        width: parent.width
                                        icon: "󰆴"
                                        label: "Forget device"
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

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarPopup {
    id: root

    required property var status
    property string interfaceName: ""
    property string stationProcessInterface: ""
    property string networkProcessInterface: ""
    property string stationState: status.wifiState
    property string currentSsid: status.wifiSsid
    property var networks: []
    property var pendingNetwork: null
    property bool passwordRequested: false
    property string errorMessage: ""

    function stripAnsi(value) {
        return String(value || "").replace(/\x1b\[[0-9;]*m/g, "");
    }

    function signalPercent(value) {
        var rssi = Number(value);
        if (isNaN(rssi))
            return 0;

        // `iwctl get-networks rssi-dbms` reports hundredths of a dBm (for
        // example -5800 means -58 dBm), while `station show` uses plain dBm.
        if (Math.abs(rssi) > 1000)
            rssi /= 100;

        return Util.clamp(Math.round(2 * (rssi + 100)), 0, 100);
    }

    function signalIcon(percent) {
        if (percent >= 75)
            return "󰤨";

        if (percent >= 50)
            return "󰤥";

        if (percent >= 25)
            return "󰤢";

        return "󰤟";
    }

    function headerIcon() {
        if (status.lanConnected)
            return "󰈀";
        return stationState === "connected" ? "󰤨" : "󰤭";
    }

    function headerTitle() {
        if (status.lanConnected)
            return "Network - Wired Connection";
        if (stationState === "connected")
            return "Network - " + (currentSsid || "Wi-Fi");
        return "Network";
    }

    function headerSubtitle() {
        if (status.lanConnected || stationState === "connected")
            return "Connected";
        if (status.lanAvailable || interfaceName)
            return "Disconnected";
        return "Unavailable";
    }

    function lanDetail() {
        if (!status.lanAvailable)
            return "No physical Ethernet adapter found";
        if (!status.lanConnected)
            return status.lanInterface + " · Cable disconnected";

        var parts = [status.lanInterface];
        if (status.lanAddress)
            parts.push(status.lanAddress);
        if (status.lanSpeedMbps > 0)
            parts.push(status.lanSpeedMbps >= 1000 ? (status.lanSpeedMbps / 1000) + " Gbit/s" : status.lanSpeedMbps + " Mbit/s");
        return parts.join(" · ");
    }

    function parseInterface(output) {
        var lines = stripAnsi(output).split("\n");
        for (var i = 0; i < lines.length; i++) {
            var match = lines[i].match(/^\s*(\S+)\s+(connected|disconnected|connecting)\b/i);
            if (match)
                return match[1];
        }
        return "";
    }

    function parseStation(output) {
        var nextState = "disconnected";
        var nextSsid = "";
        var lines = stripAnsi(output).split("\n");
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim();
            var stateMatch = line.match(/^State\s+(.+)$/i);
            if (stateMatch)
                nextState = stateMatch[1].trim();

            var networkMatch = line.match(/^Connected network\s+(.+)$/i);
            if (networkMatch)
                nextSsid = networkMatch[1].trim();
        }
        stationState = nextState;
        currentSsid = nextState === "connected" ? nextSsid : "";
    }

    function parseNetworks(output) {
        var result = [];
        var lines = stripAnsi(output).split("\n");
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i];
            var connected = /^\s*>/.test(line);
            line = line.replace(/^\s*>?\s*/, "").trim();
            var parts = line.split(/\s{2,}/);
            if (parts.length < 3)
                continue;

            var security = parts[parts.length - 2].trim().toLowerCase();
            var rssi = Number(parts[parts.length - 1].trim());
            if (isNaN(rssi) || ["open", "psk", "8021x", "sae", "owe"].indexOf(security) < 0)
                continue;

            var name = parts.slice(0, parts.length - 2).join("  ").trim();
            if (!name)
                continue;

            result.push({
                "name": name,
                "security": security,
                "signal": signalPercent(rssi),
                "connected": connected || name === currentSsid
            });
        }
        result.sort(function (a, b) {
            if (a.connected !== b.connected)
                return a.connected ? -1 : 1;

            return b.signal - a.signal;
        });
        networks = result;
    }

    function refresh() {
        errorMessage = "";
        if (!interfaceProcess.running)
            interfaceProcess.running = true;
    }

    function scan() {
        if (!interfaceName)
            return;

        Quickshell.execDetached(["iwctl", "station", interfaceName, "scan"]);
        scanTimer.restart();
    }

    function connectNetwork(network) {
        if (!network || !interfaceName || connectProcess.running)
            return;

        passwordRequested = false;
        errorMessage = "";
        if (network.connected) {
            pendingNetwork = null;
            Quickshell.execDetached(["iwctl", "station", interfaceName, "disconnect"]);
            refreshTimer.restart();
            return;
        }
        pendingNetwork = network;
        connectProcess.command = ["iwctl", "--dont-ask", "station", interfaceName, "connect", network.name];
        connectProcess.running = true;
    }

    function connectWithPassword() {
        if (!pendingNetwork || !interfaceName || passwordInput.text === "" || connectProcess.running)
            return;

        connectProcess.command = ["iwctl", "--passphrase", passwordInput.text, "--dont-ask", "station", interfaceName, "connect", pendingNetwork.name];
        passwordInput.text = "";
        passwordRequested = false;
        connectProcess.running = true;
    }

    function closePasswordPrompt() {
        passwordRequested = false;
        passwordInput.text = "";
        pendingNetwork = null;
        errorMessage = "";
    }

    popupWidth: 410
    popupHeight: 530
    onOpenedChanged: {
        if (opened) {
            refresh();
        } else {
            passwordRequested = false;
            passwordInput.text = "";
            pendingNetwork = null;
            errorMessage = "";
        }
    }

    Process {
        id: interfaceProcess

        command: ["iwctl", "station", "list"]

        stdout: StdioCollector {
            onStreamFinished: {
                root.interfaceName = root.parseInterface(text);
                if (!root.interfaceName) {
                    root.stationState = "unavailable";
                    root.currentSsid = "";
                    root.errorMessage = "No Wi-Fi station found";
                    root.networks = [];
                    return;
                }
                if (stationProcess.running)
                    return;

                root.stationProcessInterface = root.interfaceName;
                stationProcess.command = ["iwctl", "station", root.interfaceName, "show"];
                stationProcess.running = true;
            }
        }
    }

    Process {
        id: stationProcess

        stdout: StdioCollector {
            onStreamFinished: {
                if (root.stationProcessInterface !== root.interfaceName) {
                    root.refresh();
                    return;
                }

                root.parseStation(text);
                root.scan();
            }
        }
    }

    Process {
        id: networkProcess

        stdout: StdioCollector {
            onStreamFinished: {
                if (root.networkProcessInterface === root.interfaceName)
                    root.parseNetworks(text);
                else
                    root.scan();
            }
        }
    }

    Process {
        id: connectProcess

        onExited: function (exitCode) {
            if (!root.opened || !root.pendingNetwork) {
                root.passwordRequested = false;
                return;
            }

            if (exitCode !== 0 && root.pendingNetwork && root.pendingNetwork.security !== "open") {
                root.passwordRequested = true;
                Qt.callLater(function () {
                    passwordInput.forceActiveFocus(Qt.OtherFocusReason);
                });
            } else if (exitCode !== 0) {
                root.errorMessage = "Could not connect to the network";
                root.pendingNetwork = null;
            } else {
                root.pendingNetwork = null;
            }
            refreshTimer.restart();
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (root.opened && root.pendingNetwork && String(text || "").trim())
                    root.errorMessage = String(text).trim();
            }
        }
    }

    Timer {
        id: scanTimer

        interval: 900
        onTriggered: {
            if (!root.interfaceName)
                return;
            if (networkProcess.running) {
                scanTimer.restart();
                return;
            }

            root.networkProcessInterface = root.interfaceName;
            networkProcess.command = ["iwctl", "station", root.interfaceName, "get-networks", "rssi-dbms"];
            networkProcess.running = true;
        }
    }

    Timer {
        id: refreshTimer

        interval: 900
        onTriggered: root.refresh()
    }

    Column {
        anchors.fill: parent
        spacing: 10

        PopupHeader {
            width: parent.width
            icon: root.headerIcon()
            title: root.headerTitle()
            subtitle: root.headerSubtitle()
            accent: Theme.sky
        }

        PopupButton {
            text: "Refresh"
            icon: "󰑓"
            onClicked: {
                root.status.refresh();
                root.refresh();
            }
        }

        PopupSection {
            width: parent.width
            height: 22
            text: "WIRED"
            verticalAlignment: Text.AlignVCenter
        }

        Rectangle {
            width: parent.width
            height: 58
            radius: Theme.radius
            color: "transparent"

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                width: 26
                text: root.status.lanConnected ? "󰈀" : (root.status.lanAvailable ? "󰈂" : "󰌙")
                color: root.status.lanConnected ? Theme.sky : Theme.overlay0
                font.family: Theme.fontFamily
                font.pixelSize: 19
                horizontalAlignment: Text.AlignHCenter
            }

            Column {
                anchors.left: parent.left
                anchors.leftMargin: 52
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Text {
                    width: parent.width
                    text: root.status.lanConnected ? "LAN connected" : (root.status.lanAvailable ? "LAN disconnected" : "LAN unavailable")
                    color: root.status.lanConnected ? Theme.sky : Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 14
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    text: root.lanDetail()
                    color: Theme.subtext0
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }
        }

        PopupSection {
            width: parent.width
            height: 22
            text: "AVAILABLE NETWORKS"
            verticalAlignment: Text.AlignVCenter
        }

        Rectangle {
            width: parent.width
            height: root.passwordRequested ? 52 : 0
            visible: height > 0
            radius: Theme.radius
            color: Theme.mantle
            border.width: passwordInput.activeFocus || passwordInput.keyboardFocusVisible ? 1 : 0
            border.color: Theme.sky

            TextInput {
                id: passwordInput

                readonly property bool keyboardNavigable: true
                readonly property bool keyboardNeedsFocus: true
                property bool keyboardFocusVisible: false
                property bool mouseHighlightEnabled: true

                function keyboardActivate() {
                    root.connectWithPassword();
                }

                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 42
                verticalAlignment: TextInput.AlignVCenter
                echoMode: TextInput.Password
                color: Theme.text
                selectionColor: Theme.sky
                font.family: Theme.fontFamily
                font.pixelSize: 13
                activeFocusOnTab: false
                Keys.onEscapePressed: root.closePasswordPrompt()
                Keys.onReturnPressed: root.connectWithPassword()

                HoverHandler {
                    onHoveredChanged: {
                        if (hovered)
                            root.hoverNavigationItem(passwordInput);
                    }
                    onPointChanged: {
                        if (hovered)
                            root.hoverNavigationItem(passwordInput);
                    }
                }
            }

            Text {
                anchors.fill: passwordInput
                visible: passwordInput.text === ""
                text: root.pendingNetwork ? "Password for " + root.pendingNetwork.name : "Password"
                color: Theme.overlay0
                font: passwordInput.font
                verticalAlignment: Text.AlignVCenter
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                text: "󰌾"
                color: Theme.sky
                font.family: Theme.fontFamily
                font.pixelSize: 17
            }
        }

        Text {
            width: parent.width
            visible: root.errorMessage !== "" && !root.passwordRequested
            text: root.errorMessage
            color: Theme.red
            font.family: Theme.fontFamily
            font.pixelSize: 10
            elide: Text.ElideRight
        }

        WheelScrollView {
            width: parent.width
            height: parent.height - y
            contentWidth: width
            contentHeight: networkList.implicitHeight

            Column {
                id: networkList

                width: parent.width
                spacing: 3

                Text {
                    width: parent.width
                    height: 52
                    visible: root.networks.length === 0 && root.errorMessage === ""
                    text: "Scanning for Wi-Fi networks…"
                    color: Theme.overlay0
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                Repeater {
                    model: root.networks

                    ActionRow {
                        required property var modelData

                        width: networkList.width
                        icon: root.signalIcon(modelData.signal)
                        label: modelData.name
                        detail: (modelData.security === "open" ? "Open" : "Secured") + " · " + modelData.signal + "%" + (modelData.connected ? " · Connected" : "")
                        selected: modelData.connected
                        accent: Theme.sky
                        enabled: !connectProcess.running
                        opacity: enabled ? 1 : 0.55
                        onActivated: root.connectNetwork(modelData)
                    }
                }
            }
        }
    }
}

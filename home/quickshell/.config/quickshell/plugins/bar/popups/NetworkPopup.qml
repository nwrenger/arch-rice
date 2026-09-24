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
    property var knownNetworks: []
    property int knownDetailsIndex: -1
    property string knownDetailsName: ""
    property string configuredKnownNetwork: ""
    property string knownActionName: ""
    property string knownActionKind: ""
    property string knownActionError: ""
    property string knownActionProcessError: ""
    property string transitionNetworkName: ""
    property string networkTransitionState: ""
    property int transitionPollAttempts: 0
    property var pendingNetwork: null
    property bool passwordRequested: false
    property string errorMessage: ""
    property string throughputInterface: ""
    property real previousRxBytes: 0
    property real previousTxBytes: 0
    property real previousSampleTime: 0
    property real downloadRate: 0
    property real uploadRate: 0
    property bool throughputReady: false
    property int connectionPhraseIndex: 0
    readonly property var connectionPhrases: ["Wiring bits", "Handling packets", "Sorting frames", "Hauling bytes", "Routing crumbs", "Counting collisions", "Bending light"]

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

    function networkSectionTitle(index) {
        if (index < 0 || index >= networks.length)
            return "";
        var known = knownNetwork(networks[index].name) !== null;
        if (index > 0 && (knownNetwork(networks[index - 1].name) !== null) === known)
            return "";
        return known ? "KNOWN NETWORKS" : "OTHER NETWORKS";
    }

    function beginNetworkTransition(network, state) {
        transitionNetworkName = network.name;
        networkTransitionState = state;
        transitionPollAttempts = 0;
    }

    function clearNetworkTransition() {
        transitionNetworkName = "";
        networkTransitionState = "";
        transitionPollAttempts = 0;
    }

    function updateNetworkTransition() {
        if (networkTransitionState === "")
            return;

        var completedConnection = networkTransitionState === "connecting" && stationState === "connected" && currentSsid === transitionNetworkName;
        var finished = completedConnection || (networkTransitionState === "disconnecting" && (stationState === "disconnected" || stationState === "unavailable" || (stationState === "connected" && currentSsid !== transitionNetworkName)));
        if (finished) {
            clearNetworkTransition();
            if (completedConnection)
                knownRefreshTimer.restart();
        }
    }

    function headerIcon() {
        if (status.lanConnected)
            return "󰈀";
        return stationState === "connected" ? "󰤨" : "󰤭";
    }

    function headerTitle() {
        if (status.lanConnected) {
            var detail = "";
            if (status.lanSpeedMbps >= 1000)
                detail = (status.lanSpeedMbps / 1000).toFixed(status.lanSpeedMbps % 1000 === 0 ? 0 : 1) + "gbit";
            else if (status.lanSpeedMbps > 0)
                detail = status.lanSpeedMbps + "mbit";
            return detail ? "Ethernet (" + detail + ")" : "Ethernet";
        }
        if (stationState === "connected")
            return currentSsid || "Wi-Fi";
        return interfaceName || "No connection";
    }

    function headerSubtitle() {
        if (status.lanConnected || stationState === "connected")
            return connectionPhrases[connectionPhraseIndex % connectionPhrases.length];
        if (status.lanAvailable || interfaceName)
            return "Not connected";
        return "No connection";
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

    function resetThroughput() {
        throughputInterface = "";
        previousRxBytes = 0;
        previousTxBytes = 0;
        previousSampleTime = 0;
        downloadRate = 0;
        uploadRate = 0;
        throughputReady = false;
    }

    function parseThroughput(output) {
        var fields = String(output || "").trim().split("\t");
        if (fields.length < 3 || !fields[0]) {
            resetThroughput();
            return;
        }

        var iface = fields[0];
        var rxBytes = Number(fields[1]);
        var txBytes = Number(fields[2]);
        if (!isFinite(rxBytes) || !isFinite(txBytes)) {
            resetThroughput();
            return;
        }

        var now = Date.now() / 1000;
        if (iface !== throughputInterface || previousSampleTime === 0 || rxBytes < previousRxBytes || txBytes < previousTxBytes) {
            throughputInterface = iface;
            previousRxBytes = rxBytes;
            previousTxBytes = txBytes;
            previousSampleTime = now;
            downloadRate = 0;
            uploadRate = 0;
            throughputReady = false;
            return;
        }

        var elapsed = now - previousSampleTime;
        if (elapsed > 0) {
            downloadRate = Math.max(0, (rxBytes - previousRxBytes) / elapsed);
            uploadRate = Math.max(0, (txBytes - previousTxBytes) / elapsed);
            throughputReady = true;
        }
        previousRxBytes = rxBytes;
        previousTxBytes = txBytes;
        previousSampleTime = now;
    }

    function formatRate(bytesPerSecond) {
        var value = Math.max(0, Number(bytesPerSecond) || 0);
        if (value < 1024)
            return Math.round(value) + " B/s";
        if (value < 1024 * 1024)
            return (value / 1024).toFixed(1) + " KB/s";
        if (value < 1024 * 1024 * 1024)
            return (value / (1024 * 1024)).toFixed(1) + " MB/s";
        return (value / (1024 * 1024 * 1024)).toFixed(2) + " GB/s";
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
        updateNetworkTransition();
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
        networks = result;
        sortNetworks();
    }

    function sortNetworks() {
        var result = networks.slice();
        result.sort(function (a, b) {
            var aKnown = knownNetwork(a.name) !== null;
            var bKnown = knownNetwork(b.name) !== null;
            if (aKnown !== bKnown)
                return aKnown ? -1 : 1;
            if (a.connected !== b.connected)
                return a.connected ? -1 : 1;

            return b.signal - a.signal;
        });
        networks = result;

        if (configuredKnownNetwork !== "") {
            var stillAvailable = false;
            for (var i = 0; i < result.length; i++) {
                if (result[i].name === configuredKnownNetwork) {
                    stillAvailable = true;
                    break;
                }
            }
            if (!stillAvailable)
                closeKnownConfiguration();
        }
    }

    function knownNetwork(name) {
        for (var i = 0; i < knownNetworks.length; i++) {
            if (knownNetworks[i].name === name)
                return knownNetworks[i];
        }
        return null;
    }

    function parseKnownNetworks(output) {
        var result = [];
        var lines = stripAnsi(output).split("\n");
        for (var i = 0; i < lines.length; i++) {
            var match = lines[i].match(/^\s{2}(.+?)\s{2,}(open|psk|8021x|sae|owe)(?:\s|$)/i);
            if (!match)
                continue;

            var name = match[1].trim();
            var existing = knownNetwork(name);
            result.push({
                "name": name,
                "security": match[2].toLowerCase(),
                "autoConnect": existing ? existing.autoConnect : false,
                "autoConnectKnown": existing ? existing.autoConnectKnown : false
            });
        }
        result.sort(function (a, b) {
            return a.name.localeCompare(b.name);
        });
        knownNetworks = result;
        if (configuredKnownNetwork !== "" && !knownNetwork(configuredKnownNetwork))
            closeKnownConfiguration();
        sortNetworks();
        knownDetailsIndex = -1;
        loadNextKnownNetworkDetails();
    }

    function updateKnownNetwork(name, autoConnect, autoConnectKnown) {
        var result = [];
        for (var i = 0; i < knownNetworks.length; i++) {
            var network = knownNetworks[i];
            result.push(network.name === name ? {
                "name": network.name,
                "security": network.security,
                "autoConnect": autoConnect,
                "autoConnectKnown": autoConnectKnown
            } : network);
        }
        knownNetworks = result;
    }

    function removeKnownNetwork(name) {
        var result = [];
        for (var i = 0; i < knownNetworks.length; i++) {
            if (knownNetworks[i].name !== name)
                result.push(knownNetworks[i]);
        }
        knownNetworks = result;
        sortNetworks();
    }

    function loadNextKnownNetworkDetails() {
        if (knownDetailsProcess.running)
            return;

        knownDetailsIndex++;
        if (knownDetailsIndex >= knownNetworks.length) {
            knownDetailsName = "";
            return;
        }

        knownDetailsName = knownNetworks[knownDetailsIndex].name;
        knownDetailsProcess.command = ["iwctl", "--dont-ask", "known-networks", knownDetailsName, "show"];
        knownDetailsProcess.running = true;
    }

    function refreshKnownNetworks() {
        if (knownListProcess.running || knownDetailsProcess.running || knownActionProcess.running)
            return;

        knownListProcess.running = true;
    }

    function toggleKnownConfiguration(network) {
        if (!network)
            return;
        knownActionError = "";
        configuredKnownNetwork = configuredKnownNetwork === network.name ? "" : network.name;
    }

    function closeKnownConfiguration() {
        configuredKnownNetwork = "";
    }

    function setKnownAutoConnect(network) {
        if (!network || !network.autoConnectKnown || knownListProcess.running || knownDetailsProcess.running || knownActionProcess.running)
            return;

        knownActionName = network.name;
        knownActionKind = "autoconnect";
        knownActionError = "";
        knownActionProcessError = "";
        knownActionProcess.command = ["iwctl", "--dont-ask", "known-networks", network.name, "set-property", "AutoConnect", network.autoConnect ? "no" : "yes"];
        knownActionProcess.running = true;
    }

    function forgetKnownNetwork(network) {
        if (!network || knownListProcess.running || knownDetailsProcess.running || knownActionProcess.running)
            return;

        knownActionName = network.name;
        knownActionKind = "forget";
        knownActionError = "";
        knownActionProcessError = "";
        knownActionProcess.command = ["iwctl", "--dont-ask", "known-networks", network.name, "forget"];
        knownActionProcess.running = true;
    }

    function refresh() {
        errorMessage = "";
        if (!interfaceProcess.running)
            interfaceProcess.running = true;
        refreshKnownNetworks();
    }

    function scan() {
        if (!interfaceName)
            return;

        Quickshell.execDetached(["iwctl", "station", interfaceName, "scan"]);
        scanTimer.restart();
    }

    function connectNetwork(network) {
        if (!network || !interfaceName || connectProcess.running || disconnectProcess.running || networkTransitionState !== "")
            return;

        closeKnownConfiguration();
        passwordRequested = false;
        errorMessage = "";
        if (network.connected) {
            pendingNetwork = null;
            beginNetworkTransition(network, "disconnecting");
            disconnectProcess.command = ["iwctl", "--dont-ask", "station", interfaceName, "disconnect"];
            disconnectProcess.running = true;
            return;
        }
        pendingNetwork = network;
        beginNetworkTransition(network, "connecting");
        connectProcess.command = ["iwctl", "--dont-ask", "station", interfaceName, "connect", network.name];
        connectProcess.running = true;
    }

    function connectWithPassword() {
        if (!pendingNetwork || !interfaceName || passwordInput.text === "" || connectProcess.running || disconnectProcess.running || networkTransitionState !== "")
            return;

        errorMessage = "";
        connectProcess.command = ["iwctl", "--passphrase", passwordInput.text, "--dont-ask", "station", interfaceName, "connect", pendingNetwork.name];
        beginNetworkTransition(pendingNetwork, "connecting");
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
    customKeyHandler: function (event) {
        if (event.key === Qt.Key_Escape && root.configuredKnownNetwork !== "") {
            root.closeKnownConfiguration();
            return true;
        }

        if (event.key === Qt.Key_R) {
            root.status.refresh();
            root.refresh();
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
        if (opened) {
            resetThroughput();
            connectionPhraseIndex = 0;
            refresh();
        } else {
            resetThroughput();
            passwordRequested = false;
            passwordInput.text = "";
            pendingNetwork = null;
            errorMessage = "";
            knownActionError = "";
            knownActionProcessError = "";
            closeKnownConfiguration();
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
        id: throughputProcess

        command: ["bash", "-lc", "iface=$(ip -4 route show default 2>/dev/null | awk 'NR == 1 { for (i = 1; i <= NF; i++) if ($i == \"dev\") { print $(i + 1); exit } }'); " + "[ -n \"$iface\" ] || iface=$(ip -6 route show default 2>/dev/null | awk 'NR == 1 { for (i = 1; i <= NF; i++) if ($i == \"dev\") { print $(i + 1); exit } }'); " + "[ -n \"$iface\" ] || exit 0; " + "rx=$(cat \"/sys/class/net/$iface/statistics/rx_bytes\" 2>/dev/null) || exit 0; " + "tx=$(cat \"/sys/class/net/$iface/statistics/tx_bytes\" 2>/dev/null) || exit 0; " + "printf '%s\\t%s\\t%s\\n' \"$iface\" \"$rx\" \"$tx\""]

        stdout: StdioCollector {
            onStreamFinished: root.parseThroughput(text)
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
            if (exitCode === 0) {
                root.pendingNetwork = null;
                refreshTimer.restart();
                knownRefreshTimer.restart();
                return;
            }

            root.clearNetworkTransition();
            if (!root.opened || !root.pendingNetwork) {
                root.passwordRequested = false;
                root.pendingNetwork = null;
            } else if (root.pendingNetwork.security !== "open") {
                root.passwordRequested = true;
                Qt.callLater(function () {
                    passwordInput.forceActiveFocus(Qt.OtherFocusReason);
                });
            } else {
                root.errorMessage = "Could not connect to the network";
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

    Process {
        id: disconnectProcess

        onExited: function (exitCode) {
            if (exitCode === 0)
                return;

            root.clearNetworkTransition();
            if (root.errorMessage === "")
                root.errorMessage = "Could not disconnect from the network";
            refreshTimer.restart();
        }

        stderr: StdioCollector {
            onStreamFinished: {
                var message = root.stripAnsi(text).trim();
                if (root.opened && message)
                    root.errorMessage = message;
            }
        }
    }

    Process {
        id: knownListProcess

        command: ["iwctl", "--dont-ask", "known-networks", "list"]

        stdout: StdioCollector {
            onStreamFinished: root.parseKnownNetworks(text)
        }
    }

    Process {
        id: knownDetailsProcess

        onExited: function (exitCode) {
            if (exitCode !== 0 && root.knownDetailsName !== "")
                root.updateKnownNetwork(root.knownDetailsName, false, false);
            Qt.callLater(root.loadNextKnownNetworkDetails);
        }

        stdout: StdioCollector {
            onStreamFinished: {
                var match = root.stripAnsi(text).match(/AutoConnect\s+(yes|no)\b/i);
                if (root.knownDetailsName !== "" && match)
                    root.updateKnownNetwork(root.knownDetailsName, match[1].toLowerCase() === "yes", true);
            }
        }
    }

    Process {
        id: knownActionProcess

        onExited: function (exitCode) {
            if (exitCode === 0) {
                root.knownActionError = "";
                if (root.knownActionKind === "forget") {
                    root.removeKnownNetwork(root.knownActionName);
                    root.closeKnownConfiguration();
                    refreshTimer.restart();
                } else if (root.knownActionKind === "autoconnect") {
                    var network = root.knownNetwork(root.knownActionName);
                    if (network)
                        root.updateKnownNetwork(network.name, !network.autoConnect, true);
                }
            } else {
                root.knownActionError = root.knownActionProcessError || (root.knownActionKind === "forget" ? "Could not forget network" : "Could not change auto-connect");
            }

            root.knownActionName = "";
            root.knownActionKind = "";
            root.knownActionProcessError = "";
            knownRefreshTimer.restart();
        }

        stderr: StdioCollector {
            onStreamFinished: {
                var message = root.stripAnsi(text).trim();
                if (message)
                    root.knownActionProcessError = message;
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
        interval: 1000
        repeat: true
        running: root.opened
        triggeredOnStart: true
        onTriggered: {
            if (!throughputProcess.running)
                throughputProcess.running = true;
        }
    }

    Timer {
        interval: 2800
        repeat: true
        running: root.opened && (root.status.lanConnected || root.stationState === "connected")
        onTriggered: root.connectionPhraseIndex = (root.connectionPhraseIndex + 1) % root.connectionPhrases.length
    }

    Timer {
        id: refreshTimer

        interval: 900
        onTriggered: root.refresh()
    }

    Timer {
        interval: 500
        repeat: true
        running: root.networkTransitionState !== ""

        onTriggered: {
            if (!connectProcess.running && !disconnectProcess.running) {
                root.transitionPollAttempts++;
                if (root.transitionPollAttempts >= 60) {
                    root.errorMessage = root.networkTransitionState === "connecting" ? "Connection timed out" : "Disconnection timed out";
                    root.clearNetworkTransition();
                    root.refresh();
                    return;
                }
            }

            if (!interfaceProcess.running)
                interfaceProcess.running = true;
        }
    }

    Timer {
        id: knownRefreshTimer

        interval: 300
        onTriggered: {
            if (knownListProcess.running || knownDetailsProcess.running || knownActionProcess.running)
                restart();
            else
                root.refreshKnownNetworks();
        }
    }

    Column {
        anchors.fill: parent
        spacing: Theme.popupSpacing

        PopupHeader {
            width: parent.width
            icon: root.headerIcon()
            title: root.headerTitle()
            subtitle: root.headerSubtitle()
            accent: Theme.sky
            separatorVisible: false
        }

        Grid {
            width: parent.width
            height: 18
            columns: 4

            Text {
                width: parent.width * 0.20
                height: parent.height
                text: "Receiving"
                color: Theme.subtext0
                font.family: Theme.fontFamily
                font.pixelSize: 10
                verticalAlignment: Text.AlignVCenter
            }

            Text {
                width: parent.width * 0.30
                height: parent.height
                text: root.throughputReady ? root.formatRate(root.downloadRate) : "--"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 11
                font.bold: true
                verticalAlignment: Text.AlignVCenter
            }

            Text {
                width: parent.width * 0.18
                height: parent.height
                text: "Sending"
                color: Theme.subtext0
                font.family: Theme.fontFamily
                font.pixelSize: 10
                verticalAlignment: Text.AlignVCenter
            }

            Text {
                width: parent.width * 0.32
                height: parent.height
                text: root.throughputReady ? root.formatRate(root.uploadRate) : "--"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 11
                font.bold: true
                horizontalAlignment: Text.AlignRight
                verticalAlignment: Text.AlignVCenter
            }
        }

        PopupSeparator {
            width: parent.width
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
                text: "Passphrase"
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
                spacing: 4

                PopupSection {
                    width: parent.width
                    height: visible ? 22 : 0
                    visible: root.networks.length === 0 && root.errorMessage === ""
                    text: "SCANNING WI-FI…"
                    verticalAlignment: Text.AlignVCenter
                }

                Repeater {
                    model: root.networks

                    Item {
                        id: availableEntry

                        required property var modelData
                        required property int index
                        readonly property var savedNetwork: root.knownNetwork(modelData.name)
                        readonly property bool configurationExpanded: !!savedNetwork && root.configuredKnownNetwork === modelData.name
                        readonly property string transition: root.transitionNetworkName === modelData.name ? root.networkTransitionState : ""

                        width: networkList.width
                        implicitHeight: availableColumn.implicitHeight

                        Column {
                            id: availableColumn

                            width: parent.width
                            spacing: 4

                            Column {
                                width: parent.width
                                spacing: 10

                                PopupSection {
                                    width: parent.width
                                    height: visible ? 22 : 0
                                    visible: root.networkSectionTitle(availableEntry.index) !== ""
                                    text: root.networkSectionTitle(availableEntry.index)
                                    verticalAlignment: Text.AlignVCenter
                                }

                                ActionRow {
                                    id: availableRow

                                    width: parent.width
                                    icon: root.signalIcon(availableEntry.modelData.signal)
                                    label: availableEntry.modelData.name
                                    selected: availableEntry.modelData.connected
                                    accent: Theme.sky
                                    enabled: root.networkTransitionState === "" && !connectProcess.running && !disconnectProcess.running && !knownActionProcess.running
                                    opacity: availableEntry.transition !== "" || knownActionProcess.running ? 0.55 : 1

                                    function keyboardConfigure() {
                                        if (availableEntry.savedNetwork)
                                            root.toggleKnownConfiguration(availableEntry.savedNetwork);
                                    }

                                    onActivated: root.connectNetwork(availableEntry.modelData)
                                    onSecondaryActivated: {
                                        if (availableEntry.savedNetwork)
                                            root.toggleKnownConfiguration(availableEntry.savedNetwork);
                                    }
                                }
                            }

                            Loader {
                                id: networkConfigurationLoader

                                x: 24
                                width: parent.width - x
                                active: availableEntry.configurationExpanded
                                visible: active
                                height: active && item ? item.implicitHeight : 0

                                sourceComponent: InlineSettings {
                                    width: networkConfigurationLoader.width
                                    accent: Theme.sky

                                    ActionRow {
                                        width: parent.width
                                        icon: availableEntry.savedNetwork && availableEntry.savedNetwork.autoConnect ? "󰄬" : "󰝦"
                                        label: "Auto-connect"
                                        selected: !!availableEntry.savedNetwork && availableEntry.savedNetwork.autoConnectKnown && availableEntry.savedNetwork.autoConnect
                                        accent: Theme.sky
                                        enabled: !!availableEntry.savedNetwork && availableEntry.savedNetwork.autoConnectKnown && !knownListProcess.running && !knownDetailsProcess.running && !knownActionProcess.running
                                        opacity: enabled ? 1 : 0.55
                                        onActivated: root.setKnownAutoConnect(availableEntry.savedNetwork)
                                    }

                                    ActionRow {
                                        width: parent.width
                                        icon: "󰆴"
                                        label: "Forget network"
                                        accented: true
                                        accent: Theme.red
                                        enabled: !!availableEntry.savedNetwork && !knownListProcess.running && !knownDetailsProcess.running && !knownActionProcess.running
                                        opacity: enabled ? 1 : 0.55
                                        onActivated: root.forgetKnownNetwork(availableEntry.savedNetwork)
                                    }

                                    Text {
                                        width: parent.width
                                        height: visible ? implicitHeight + 8 : 0
                                        visible: availableEntry.configurationExpanded && root.knownActionError !== ""
                                        text: root.knownActionError
                                        color: Theme.red
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                        wrapMode: Text.Wrap
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

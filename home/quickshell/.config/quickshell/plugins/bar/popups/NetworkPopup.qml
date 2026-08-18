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

    function networkDetail(network, known, transition, settingsOpen) {
        var parts = [known ? "Known" : (network.security === "open" ? "Open" : "Secured"), network.signal + "%"];
        if (transition === "connecting")
            parts.push("Connecting…");
        else if (transition === "disconnecting")
            parts.push("Disconnecting…");
        else if (network.connected)
            parts.push("Connected");
        if (settingsOpen)
            parts.push("Settings open");
        return parts.join(" · ");
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

        var finished = networkTransitionState === "connecting"
            ? stationState === "connected" && currentSsid === transitionNetworkName
            : stationState === "disconnected" || stationState === "unavailable" || (stationState === "connected" && currentSsid !== transitionNetworkName);
        if (finished)
            clearNetworkTransition();
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
            refresh();
        } else {
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

                    Item {
                        id: availableEntry

                        required property var modelData
                        readonly property var savedNetwork: root.knownNetwork(modelData.name)
                        readonly property bool configurationExpanded: !!savedNetwork && root.configuredKnownNetwork === modelData.name
                        readonly property string transition: root.transitionNetworkName === modelData.name ? root.networkTransitionState : ""

                        width: networkList.width
                        implicitHeight: availableColumn.implicitHeight

                        Column {
                            id: availableColumn

                            width: parent.width
                            spacing: 4

                            ActionRow {
                                id: availableRow

                                width: parent.width
                                icon: root.signalIcon(availableEntry.modelData.signal)
                                label: availableEntry.modelData.name
                                detail: root.networkDetail(availableEntry.modelData, !!availableEntry.savedNetwork, availableEntry.transition, availableEntry.configurationExpanded)
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

                                    PopupSection {
                                        width: parent.width
                                        height: 24
                                        text: "NETWORK SETTINGS"
                                        verticalAlignment: Text.AlignVCenter
                                    }

                                    ActionRow {
                                        width: parent.width
                                        icon: availableEntry.savedNetwork && availableEntry.savedNetwork.autoConnect ? "󰄬" : "󰝦"
                                        label: "Auto-connect"
                                        detail: availableEntry.savedNetwork && availableEntry.savedNetwork.autoConnectKnown ? (availableEntry.savedNetwork.autoConnect ? "Enabled" : "Disabled") : "Loading…"
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
                                        detail: "Remove the saved network"
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

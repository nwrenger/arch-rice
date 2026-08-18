import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

Item {
    id: root

    property int deviceId: -1
    property int profileDevice: -1
    property bool output: true
    property var deviceProfiles: []
    property var deviceRoutes: []
    property var activeRoutes: []
    property int activeProfile: -1
    property bool loading: false
    property bool applying: false
    property string errorMessage: ""
    property string pendingKind: ""
    property int pendingIndex: -1
    property int syncAttempts: 0

    function activeProfileDevices() {
        var mediaClass = output ? "Audio/Sink" : "Audio/Source";
        for (var i = 0; i < deviceProfiles.length; i++) {
            var profile = deviceProfiles[i];
            if (Number(profile.index) !== activeProfile)
                continue;

            var classes = profile.classes || [];
            for (var j = 0; j < classes.length; j++) {
                var entry = classes[j];
                if (Array.isArray(entry) && entry[0] === mediaClass)
                    return entry[3] || [];
            }
        }
        return profileDevice >= 0 ? [profileDevice] : [];
    }

    function routesForNode() {
        var result = [];
        var direction = output ? "output" : "input";
        var profileDevices = activeProfileDevices();
        for (var i = 0; i < deviceRoutes.length; i++) {
            var route = deviceRoutes[i];
            var devices = route.devices || [];
            if (String(route.direction || "").toLowerCase() !== direction)
                continue;

            if (profileDevices.length === 0) {
                result.push(route);
                continue;
            }

            for (var j = 0; j < profileDevices.length; j++) {
                if (devices.indexOf(profileDevices[j]) >= 0) {
                    result.push(route);
                    break;
                }
            }
        }
        return result;
    }

    function profilesForDirection() {
        var result = [];
        var seen = {};
        for (var i = 0; i < deviceProfiles.length; i++) {
            var profile = deviceProfiles[i];
            if (String(profile.name || "").toLowerCase() === "off")
                continue;

            var key = String(profile.index);
            if (seen[key])
                continue;
            seen[key] = true;
            result.push(profile);
        }
        return result;
    }

    function loadConfiguration() {
        if (deviceId < 0) {
            loading = false;
            errorMessage = "No configurable PipeWire device found";
            return;
        }

        if (configProcess.running)
            return;

        var query = ".[] | select(.id == $id) | {profiles: [(.info.params.EnumProfile // [])[] | select(.available != \"no\") | {index, name, description, available, classes}], activeProfile: ((.info.params.Profile // [])[0].index // -1), routes: [(.info.params.EnumRoute // [])[] | select(.available != \"no\") | {index, description, direction, devices}], activeRoutes: [(.info.params.Route // [])[] | .index]}";
        loading = deviceProfiles.length === 0;
        if (!applying)
            errorMessage = "";
        configProcess.command = ["bash", "-lc", "pw-dump | jq -c --argjson id " + deviceId + " '" + query + "'"];
        configProcess.running = true;
    }

    function selectProfile(profile) {
        if (!profile || deviceId < 0 || loading || applying || applyProcess.running || Number(profile.index) === activeProfile)
            return;

        activeProfile = Number(profile.index);
        runChange(["wpctl", "set-profile", String(deviceId), String(profile.index)], "profile", Number(profile.index));
    }

    function selectRoute(route) {
        if (!route || deviceId < 0 || loading || applying || applyProcess.running || activeRoutes.indexOf(Number(route.index)) >= 0)
            return;

        var direction = output ? "output" : "input";
        var updated = [];
        for (var i = 0; i < activeRoutes.length; i++) {
            var activeIndex = Number(activeRoutes[i]);
            var sameDirection = false;
            for (var j = 0; j < deviceRoutes.length; j++) {
                if (Number(deviceRoutes[j].index) === activeIndex && String(deviceRoutes[j].direction || "").toLowerCase() === direction) {
                    sameDirection = true;
                    break;
                }
            }
            if (!sameDirection)
                updated.push(activeIndex);
        }
        updated.push(Number(route.index));
        activeRoutes = updated;
        runChange(["wpctl", "set-route", String(deviceId), String(route.index)], "route", Number(route.index));
    }

    function runChange(command, kind, index) {
        applying = true;
        errorMessage = "";
        pendingKind = kind;
        pendingIndex = index;
        syncAttempts = 0;
        applyTimeout.restart();
        applyProcess.command = command;
        applyProcess.running = true;
    }

    function finishChange(error) {
        applyTimeout.stop();
        syncReload.stop();
        applying = false;
        pendingKind = "";
        pendingIndex = -1;
        syncAttempts = 0;
        if (error)
            errorMessage = error;
    }

    function changeIsSynchronized() {
        if (pendingKind === "profile")
            return activeProfile === pendingIndex;
        if (pendingKind === "route")
            return activeRoutes.indexOf(pendingIndex) >= 0;
        return true;
    }

    function retrySynchronization() {
        if (!applying)
            return;
        if (syncAttempts < 12) {
            syncAttempts++;
            syncReload.restart();
        } else {
            finishChange("PipeWire did not activate the requested setting");
        }
    }

    implicitHeight: configuration.implicitHeight

    Component.onCompleted: loadConfiguration()
    onDeviceIdChanged: {
        deviceProfiles = [];
        deviceRoutes = [];
        activeRoutes = [];
        activeProfile = -1;
        finishChange("");
        if (deviceId >= 0)
            loadConfiguration();
    }

    Timer {
        id: syncReload

        interval: 250
        onTriggered: root.loadConfiguration()
    }

    Timer {
        id: applyTimeout

        interval: 4000
        onTriggered: {
            root.finishChange("Audio device change timed out");
        }
    }

    Process {
        id: applyProcess

        onExited: function(exitCode) {
            if (exitCode !== 0) {
                root.finishChange("Could not apply audio device change");
                return;
            }

            syncReload.restart();
        }
    }

    Process {
        id: configProcess

        onExited: function(exitCode) {
            root.loading = false;
            if (exitCode !== 0) {
                if (root.applying)
                    root.finishChange("Could not synchronize audio device change");
                else if (root.deviceProfiles.length === 0)
                    root.errorMessage = "Could not read PipeWire configuration";
            }
        }

        stdout: StdioCollector {
            onStreamFinished: {
                var outputText = String(text || "").trim();
                if (!outputText) {
                    if (root.applying)
                        root.retrySynchronization();
                    else
                        root.errorMessage = "Could not read PipeWire configuration";
                    return;
                }

                try {
                    var data = JSON.parse(outputText);
                    root.deviceProfiles = data.profiles || [];
                    root.deviceRoutes = data.routes || [];
                    root.activeRoutes = data.activeRoutes || [];
                    root.activeProfile = Number(data.activeProfile);
                    if (root.applying) {
                        if (root.changeIsSynchronized()) {
                            root.finishChange("");
                        } else {
                            root.retrySynchronization();
                        }
                    }
                } catch (error) {
                    if (root.applying)
                        root.finishChange("Could not synchronize audio device change");
                    else
                        root.errorMessage = "Could not parse PipeWire configuration";
                }
            }
        }
    }

    InlineSettings {
        id: configuration

        width: parent.width
        accent: root.output ? Theme.red : Theme.yellow
        spacing: 4

        PopupSection {
            width: parent.width
            height: 24
            text: "DEVICE SETTINGS"
            verticalAlignment: Text.AlignVCenter
        }

        Text {
            width: parent.width
            height: visible ? 44 : 0
            visible: root.loading || root.applying || root.errorMessage !== ""
            text: root.applying ? "Applying device change…" : (root.loading ? "Loading device configuration…" : root.errorMessage)
            color: root.errorMessage ? Theme.red : Theme.overlay0
            font.family: Theme.fontFamily
            font.pixelSize: 11
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        PopupSection {
            width: parent.width
            height: 24
            visible: !root.loading && root.profilesForDirection().length > 0
            text: "PROFILE"
            verticalAlignment: Text.AlignVCenter
        }

        Repeater {
            model: !root.loading ? root.profilesForDirection() : []

            ActionRow {
                required property var modelData

                width: configuration.contentWidth
                icon: Number(modelData.index) === root.activeProfile ? "󰄬" : "󰝦"
                label: modelData.description || "Profile " + modelData.index
                selected: Number(modelData.index) === root.activeProfile
                accent: root.output ? Theme.red : Theme.yellow
                enabled: !root.loading && !root.applying
                opacity: enabled ? 1 : 0.55
                onActivated: root.selectProfile(modelData)
            }
        }

        PopupSection {
            width: parent.width
            height: 24
            visible: !root.loading && root.routesForNode().length > 0
            text: root.output ? "OUTPUT PORT" : "INPUT PORT"
            verticalAlignment: Text.AlignVCenter
        }

        Repeater {
            model: !root.loading ? root.routesForNode() : []

            ActionRow {
                required property var modelData

                width: configuration.contentWidth
                icon: root.activeRoutes.indexOf(Number(modelData.index)) >= 0 ? "󰄬" : "󰝦"
                label: modelData.description || "Port " + modelData.index
                selected: root.activeRoutes.indexOf(Number(modelData.index)) >= 0
                accent: root.output ? Theme.red : Theme.yellow
                enabled: !root.loading && !root.applying
                opacity: enabled ? 1 : 0.55
                onActivated: root.selectRoute(modelData)
            }
        }

        Text {
            width: parent.width
            height: visible ? 44 : 0
            visible: !root.loading && root.errorMessage === "" && root.profilesForDirection().length === 0 && root.routesForNode().length === 0
            text: "No configurable profiles or ports"
            color: Theme.overlay0
            font.family: Theme.fontFamily
            font.pixelSize: 11
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }
}

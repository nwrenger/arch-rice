import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarPopup {
    id: root

    required property var status
    property var locations: []
    property var expandedCountries: []
    property string selectedCountryCode: ""
    property string selectedCityCode: ""
    property string errorMessage: ""
    property int phraseIndex: 0
    readonly property var activePhrases: ["Encrypting connections", "Sending secrets", "Guarding wires", "Braiding packets", "Polishing tunnels", "Hiding routes", "Sealing ports", "Shuffling keys"]

    function heroTitle() {
        if (!status.vpnConnected || !status.vpnCountry)
            return "Mullvad VPN";
        return (status.vpnCity ? status.vpnCity + ", " : "") + status.vpnCountry;
    }

    function heroStatus() {
        if (status.vpnState === "Connecting")
            return "Connecting";
        if (status.vpnConnected)
            return activePhrases[phraseIndex % activePhrases.length];
        return "Disconnected";
    }

    function parseLocations(output) {
        var countries = [];
        var currentCountry = null;
        var lines = String(output || "").split("\n");
        for (var i = 0; i < lines.length; i++) {
            var countryMatch = lines[i].match(/^([^\s].*?) \(([a-z]{2})\)\s*$/i);
            if (countryMatch) {
                currentCountry = {
                    "label": countryMatch[1],
                    "code": countryMatch[2].toLowerCase(),
                    "cities": []
                };
                countries.push(currentCountry);
                continue;
            }

            var cityMatch = lines[i].match(/^\s+(.+?) \(([a-z0-9-]+)\)\s+@/i);
            if (currentCountry && cityMatch)
                currentCountry.cities.push({
                    "label": cityMatch[1],
                    "code": cityMatch[2].toLowerCase()
                });
        }
        countries.sort(function (a, b) {
            return a.label.localeCompare(b.label);
        });
        for (var j = 0; j < countries.length; j++)
            countries[j].cities.sort(function (a, b) {
                return a.label.localeCompare(b.label);
            });

        locations = countries;
        syncSelection();
        if (countries.length === 0)
            errorMessage = "No Mullvad locations found";
    }

    function countryExpanded(code) {
        return expandedCountries.indexOf(code) >= 0;
    }

    function toggleCountry(code) {
        expandedCountries = countryExpanded(code) ? [] : [code];
    }

    function syncSelection() {
        var currentCountryCode = String(status.vpnCountryCode || "").toLowerCase();
        var currentCityCode = String(status.vpnCityCode || "").toLowerCase();
        var currentCity = String(status.vpnCity || "").toLowerCase();
        if (currentCountryCode === "")
            return;

        for (var i = 0; i < locations.length; i++) {
            var country = locations[i];
            if (country.code !== currentCountryCode)
                continue;

            if (currentCityCode === "") {
                selectedCountryCode = country.code;
                selectedCityCode = "";
                expandedCountries = [country.code];
                Qt.callLater(root.scrollToSelection);
                return;
            }

            for (var j = 0; j < country.cities.length; j++) {
                var city = country.cities[j];
                var codeMatch = city.code === currentCityCode;
                var labelMatch = currentCity !== "" && String(city.label).toLowerCase() === currentCity;
                if (!codeMatch && !labelMatch)
                    continue;

                selectedCountryCode = country.code;
                selectedCityCode = city.code;
                expandedCountries = [country.code];
                Qt.callLater(root.scrollToSelection);
                return;
            }
        }
    }

    function scrollToSelection() {
        for (var i = 0; i < countryRepeater.count; i++) {
            var country = countryRepeater.itemAt(i);
            if (!country || country.modelData.code !== selectedCountryCode)
                continue;

            var target = country.headerItem();
            for (var j = 0; j < country.cityCount(); j++) {
                var city = country.cityAt(j);
                if (city && city.modelData.code === selectedCityCode) {
                    target = city;
                    break;
                }
            }
            menuScroll.ensureItemVisible(target);
            return;
        }
    }

    function syncSelectionWhenReady() {
        if (opened && locations.length > 0)
            syncSelection();
    }

    function refreshLocations() {
        errorMessage = "";
        if (!relayProcess.running)
            relayProcess.running = true;
    }

    function selectLocation(country, city) {
        if (!country || !city)
            return;

        selectedCountryCode = country.code;
        selectedCityCode = city.code;
        Quickshell.execDetached(["mullvad", "relay", "set", "location", country.code, city.code]);
        statusRefresh.restart();
    }

    popupWidth: 390
    popupHeight: 530
    onOpenedChanged: {
        if (opened) {
            phraseIndex = 0;
            status.refresh();
            if (locations.length === 0)
                refreshLocations();
            else
                syncSelection();
        }
    }

    Timer {
        id: statusRefresh

        interval: 900
        onTriggered: root.status.refresh()
    }

    Timer {
        interval: 2800
        repeat: true
        running: root.opened && root.status.vpnState === "Connected"
        onTriggered: root.phraseIndex = (root.phraseIndex + 1) % root.activePhrases.length
    }

    Connections {
        target: root.status

        function onVpnCityCodeChanged() {
            root.syncSelectionWhenReady();
        }

        function onVpnCountryCodeChanged() {
            root.syncSelectionWhenReady();
        }
    }

    Process {
        id: relayProcess

        command: ["mullvad", "relay", "list"]

        onExited: function (exitCode) {
            if (exitCode !== 0 && root.locations.length === 0)
                root.errorMessage = "Could not load Mullvad locations";
        }

        stdout: StdioCollector {
            onStreamFinished: root.parseLocations(text)
        }
    }

    Column {
        anchors.fill: parent
        spacing: Theme.popupSpacing

        PopupHeader {
            width: parent.width
            icon: root.status.vpnConnected ? "󰒃" : "󰌙"
            title: root.heroTitle()
            subtitle: root.heroStatus()
            accent: Theme.mauve
            trailingControl: Component {
                PopupToggle {
                    checked: root.status.vpnConnected
                    accent: Theme.mauve
                    onToggled: root.status.toggleVpn()
                }
            }
        }

        PopupSection {
            width: parent.width
            height: 22
            text: "LOCATIONS"
            verticalAlignment: Text.AlignVCenter
        }

        WheelScrollView {
            id: menuScroll

            width: parent.width
            height: parent.height - y
            contentWidth: width
            contentHeight: locationList.implicitHeight

            Column {
                id: locationList

                width: parent.width
                spacing: 4

                Text {
                    width: parent.width
                    height: 52
                    visible: root.locations.length === 0
                    text: relayProcess.running ? "Loading Mullvad locations…" : root.errorMessage
                    color: root.errorMessage ? Theme.red : Theme.overlay0
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                Repeater {
                    id: countryRepeater

                    model: root.locations

                    Column {
                        id: countryGroup

                        required property var modelData

                        function cityCount() {
                            return cityRepeater.count;
                        }

                        function cityAt(index) {
                            return cityRepeater.itemAt(index);
                        }

                        function headerItem() {
                            return countryRow;
                        }

                        width: locationList.width
                        spacing: root.countryExpanded(modelData.code) ? 4 : 0

                        ActionRow {
                            id: countryRow

                            width: countryGroup.width
                            icon: root.countryExpanded(countryGroup.modelData.code) ? "󰅀" : "󰅂"
                            label: countryGroup.modelData.label
                            detail: countryGroup.modelData.cities.length + (countryGroup.modelData.cities.length === 1 ? " location" : " locations")
                            selected: countryGroup.modelData.code === root.selectedCountryCode
                            accent: Theme.mauve
                            onActivated: root.toggleCountry(countryGroup.modelData.code)
                        }

                        InlineSettings {
                            id: citySettings

                            x: 24
                            width: countryGroup.width - x
                            height: root.countryExpanded(countryGroup.modelData.code) ? implicitHeight : 0
                            visible: height > 0
                            accent: Theme.mauve
                            spacing: 4

                            Repeater {
                                id: cityRepeater

                                model: root.countryExpanded(countryGroup.modelData.code) ? countryGroup.modelData.cities : []

                                ActionRow {
                                    required property var modelData

                                    width: citySettings.contentWidth
                                    label: modelData.label
                                    reserveIconSpace: false
                                    selected: countryGroup.modelData.code === root.selectedCountryCode && modelData.code === root.selectedCityCode
                                    accent: Theme.mauve
                                    onActivated: root.selectLocation(countryGroup.modelData, modelData)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

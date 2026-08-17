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

    Connections {
        target: root.status

        function onVpnCityCodeChanged() { root.syncSelectionWhenReady(); }

        function onVpnCountryCodeChanged() { root.syncSelectionWhenReady(); }
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
        spacing: 12

        PopupHeader {
            width: parent.width
            icon: root.status.vpnConnected ? "󰒃" : "󰌙"
            title: "Mullvad VPN"
            subtitle: root.status.vpnCountry ? root.status.vpnState + " · " + root.status.vpnCountry + (root.status.vpnCity ? ", " + root.status.vpnCity : "") : root.status.vpnState
            accent: Theme.mauve
        }

        Rectangle {
            width: parent.width
            height: 56
            radius: Theme.radius
            color: Theme.surface0

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                text: root.status.vpnConnected ? "Your traffic is protected" : "VPN is disconnected"
                color: root.status.vpnConnected ? Theme.green : Theme.subtext0
                font.family: Theme.fontFamily
                font.pixelSize: 12
            }

            Rectangle {
                width: 10
                height: 10
                radius: 5
                anchors.right: parent.right
                anchors.rightMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                color: root.status.vpnConnected ? Theme.green : Theme.overlay0
            }
        }

        Row {
            width: parent.width
            height: 36
            spacing: 8

            PopupButton {
                text: root.status.vpnConnected ? "Disconnect" : "Connect"
                icon: root.status.vpnConnected ? "󰌙" : "󰒃"
                highlighted: true
                accent: Theme.mauve
                onClicked: root.status.toggleVpn()
            }

            PopupButton {
                text: "Refresh locations"
                icon: "󰑓"
                onClicked: root.refreshLocations()
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
                spacing: 3

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
                        spacing: root.countryExpanded(modelData.code) ? 3 : 0

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

                        Item {
                            x: 24
                            width: countryGroup.width - x
                            height: root.countryExpanded(countryGroup.modelData.code) ? cityColumn.implicitHeight + 8 : 0
                            visible: height > 0

                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                anchors.topMargin: 4
                                anchors.bottomMargin: 4
                                width: 2
                                radius: 1
                                color: Theme.mauve
                                opacity: 0.65
                            }

                            Column {
                                id: cityColumn

                                x: 14
                                width: parent.width - x
                                spacing: 3

                                Repeater {
                                    id: cityRepeater

                                    model: root.countryExpanded(countryGroup.modelData.code) ? countryGroup.modelData.cities : []

                                    ActionRow {
                                        required property var modelData

                                        width: cityColumn.width
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
}

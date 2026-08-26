import "AppSearch.js" as AppSearch
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
    id: root

    required property var session
    property bool opened: false
    property string mode: "apps"
    property string query: ""
    property int selectedIndex: 0
    property bool keyboardSelectionActive: false
    property var dataRows: []
    property var modeHistory: []
    property var selectedPackages: []
    property string calcResult: ""
    property string targetScreenName: ""
    property string dataProcessMode: ""
    property string queuedDataMode: ""
    readonly property bool packageMode: mode.indexOf("package-") === 0
    readonly property string title: {
        var titles = {
            "apps": "Applications",
            "root": "System",
            "install": "Install package",
            "remove-choice": "Remove package",
            "package-official": "Official",
            "package-aur": "AUR",
            "package-flatpak": "Flatpak",
            "package-remove": "Remove system package",
            "package-flatpak-remove": "Remove Flatpak",
            "power": "Power"
        };
        var value = titles[mode] || "Launcher";
        if (packageMode && selectedPackages.length > 0)
            value += " · " + selectedPackages.length + " selected";
        return value;
    }
    readonly property var visibleRows: buildRows()
    readonly property bool compactStaticMenu: mode === "root" || mode === "install" || mode === "remove-choice" || mode === "power"
    readonly property int initialRowsHeight: rowsHeight(staticRows())
    readonly property int visibleRowsHeight: rowsHeight(visibleRows)
    readonly property int minimumCardHeight: compactStaticMenu ? 100 + initialRowsHeight : 440

    signal calculationFinished(string expression, string result)

    function rowsHeight(rows) {
        if (rows.length === 0)
            return 52;

        var height = (rows.length - 1) * 4;
        for (var i = 0; i < rows.length; i++)
            height += rows[i].detail ? 58 : 46;
        return height;
    }

    function open(requestedMode) {
        modeHistory = [];
        mode = String(requestedMode || "apps");
        query = "";
        selectedIndex = 0;
        keyboardSelectionActive = false;
        selectedPackages = [];
        targetScreenName = Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name || "") : "";
        opened = true;
        loadModeData();
    }

    function close() {
        opened = false;
        query = "";
        modeHistory = [];
        selectedPackages = [];
    }

    function toggle(requestedMode) {
        var next = String(requestedMode || "apps");
        if (opened && mode === next)
            close();
        else
            open(next);
    }

    function setMode(next) {
        var nextMode = String(next);
        if (nextMode === mode)
            return;

        modeHistory = modeHistory.concat([mode]);
        showMode(nextMode);
    }

    function showMode(next) {
        mode = next;
        query = "";
        selectedIndex = 0;
        keyboardSelectionActive = false;
        dataRows = [];
        selectedPackages = [];
        loadModeData();
    }

    function goBack() {
        if (modeHistory.length === 0) {
            close();
            return;
        }
        var history = modeHistory.slice();
        var previousMode = history.pop();
        modeHistory = history;
        showMode(previousMode);
    }

    function staticRows() {
        if (mode === "root")
            return [
                {
                    "icon": "󰋼",
                    "label": "About",
                    "action": "about"
                },
                {
                    "icon": "󰏗",
                    "label": "Install",
                    "target": "install"
                },
                {
                    "icon": "󰚰",
                    "label": "Update",
                    "action": "update"
                },
                {
                    "icon": "󰆴",
                    "label": "Remove",
                    "target": "remove-choice"
                },
                {
                    "icon": "󰐥",
                    "label": "Power",
                    "target": "power"
                }
            ];

        if (mode === "install")
            return [
                {
                    "icon": "󰣇",
                    "label": "Official",
                    "target": "package-official"
                },
                {
                    "icon": "󰣇",
                    "label": "AUR",
                    "target": "package-aur"
                },
                {
                    "icon": "",
                    "label": "Flatpak",
                    "target": "package-flatpak"
                }
            ];

        if (mode === "remove-choice")
            return [
                {
                    "icon": "󰣇",
                    "label": "System",
                    "action": "remove-system"
                },
                {
                    "icon": "",
                    "label": "Flatpak",
                    "target": "package-flatpak-remove"
                }
            ];

        if (mode === "power")
            return [
                {
                    "icon": "󰐥",
                    "label": "Shutdown",
                    "action": "poweroff"
                },
                {
                    "icon": "󰜉",
                    "label": "Reboot",
                    "action": "reboot"
                },
                {
                    "icon": "󰍃",
                    "label": "Logout",
                    "action": "logout"
                },
                {
                    "icon": "󰤄",
                    "label": "Suspend",
                    "action": "suspend"
                }
            ];

        return [];
    }

    function packageMatchRank(label, needle) {
        if (label === needle)
            return 0;

        if (label.indexOf(needle) === 0)
            return 1;

        var separators = "-_.+@";
        var index = label.indexOf(needle, 1);
        while (index >= 0) {
            if (separators.indexOf(label.charAt(index - 1)) >= 0)
                return 2;

            index = label.indexOf(needle, index + 1);
        }
        return label.indexOf(needle) >= 0 ? 3 : -1;
    }

    function moveSelection(step) {
        if (visibleRows.length === 0) {
            selectedIndex = 0;
            return;
        }
        selectedIndex = Util.clamp(selectedIndex + step, 0, visibleRows.length - 1);
    }

    function searchPackages(needle) {
        if (!needle)
            return dataRows;

        var matches = [];
        for (var i = 0; i < dataRows.length; i++) {
            var row = dataRows[i];
            var rank = packageMatchRank(String(row.label || "").toLowerCase(), needle);
            if (rank < 0 && String(row.detail || "").toLowerCase().indexOf(needle) >= 0)
                rank = 4;
            if (rank < 0 && String(row.searchText || "").toLowerCase().indexOf(needle) >= 0)
                rank = 4;
            if (rank >= 0)
                matches.push({
                    "row": row,
                    "rank": rank
                });
        }
        matches.sort(function (a, b) {
            if (a.rank !== b.rank)
                return a.rank - b.rank;

            return String(a.row.label || "").localeCompare(String(b.row.label || ""));
        });
        var rows = [];
        for (var j = 0; j < matches.length; j++)
            rows.push(matches[j].row);
        return rows;
    }

    function calc(expr) {
        expr = String(expr || "").trim();
        if (!expr)
            return;

        if (qalcProcess.running) {
            calcTimer.restart();
            return;
        }

        qalcProcess.expression = expr;
        qalcProcess.command = ["qalc", "-t", expr];
        qalcProcess.running = true;
    }

    function buildRows() {
        if (mode === "apps") {
            var values = DesktopEntries.applications ? DesktopEntries.applications.values : [];
            var matches = AppSearch.search(values, query);

            // If there are no matches go into math mode
            if (!matches || matches.length === 0) {
                return [
                    {
                        "icon": "",
                        "label": calcResult,
                        "detail": "Select to copy the result",
                        "copyText": calcResult
                    }
                ];
            } else {
                var apps = [];
                for (var i = 0; i < matches.length; i++) {
                    var entry = matches[i].entry;
                    apps.push({
                        "icon": "󰀻",
                        "iconSource": Quickshell.iconPath(entry.icon || "", true),
                        "label": entry.name || entry.id,
                        "detail": entry.genericName || entry.comment || "",
                        "desktopId": entry.id
                    });
                }
                return apps;
            }
        }
        if (mode.indexOf("package-") === 0)
            return searchPackages(query.trim().toLowerCase());

        var rows = staticRows();
        var needle = query.trim().toLowerCase();
        if (!needle)
            return rows;

        var filtered = [];
        for (var k = 0; k < rows.length; k++) {
            var row = rows[k];
            if ((row.label + " " + (row.detail || "")).toLowerCase().indexOf(needle) >= 0)
                filtered.push(row);
        }
        return filtered;
    }

    function packageCommand(modeName) {
        var catalog = Quickshell.shellDir + "/scripts/package-catalog";
        if (modeName === "package-official")
            return ["bash", catalog, "official"];
        if (modeName === "package-aur")
            return ["bash", catalog, "aur"];
        if (modeName === "package-flatpak")
            return ["bash", catalog, "flatpak"];
        if (modeName === "package-remove")
            return ["bash", catalog, "system-remove"];
        if (modeName === "package-flatpak-remove")
            return ["bash", catalog, "flatpak-remove"];
        return null;
    }

    function loadModeData() {
        var command = packageCommand(mode);
        if (!command) {
            queuedDataMode = "";
            return;
        }

        if (dataProcess.running) {
            queuedDataMode = dataProcessMode === mode ? "" : mode;
            return;
        }

        dataProcessMode = mode;
        queuedDataMode = "";
        dataProcess.command = command;
        dataProcess.running = true;
    }

    function launchTerminal(command, titleText) {
        Quickshell.execDetached(["alacritty", "--title", titleText || "arch-rice", "-e", "fish", "-c", command + "; show_done"]);
        close();
    }

    function packageSelected(packageName) {
        return selectedPackages.indexOf(String(packageName || "")) >= 0;
    }

    function togglePackageSelection(row) {
        if (!row || !row.packageName)
            return;

        var packageName = String(row.packageName);
        var selected = selectedPackages.slice();
        var index = selected.indexOf(packageName);
        if (index >= 0)
            selected.splice(index, 1);
        else
            selected.push(packageName);
        selectedPackages = selected;
    }

    function activatePackages(packages) {
        if (!packages || packages.length === 0)
            return;

        var quoted = [];
        for (var i = 0; i < packages.length; i++)
            quoted.push(Util.shellQuote(packages[i]));
        var arguments = quoted.join(" ");
        if (mode === "package-official")
            launchTerminal("sudo pacman -S -- " + arguments, "package install");
        else if (mode === "package-aur")
            launchTerminal("paru -S -- " + arguments, "AUR install");
        else if (mode === "package-flatpak")
            launchTerminal("flatpak install --app " + arguments, "Flatpak install");
        else if (mode === "package-flatpak-remove")
            launchTerminal("flatpak uninstall --app " + arguments, "Flatpak removal");
        else
            launchTerminal("sudo pacman -Rns -- " + arguments, "package removal");
    }

    function launchApplication(desktopId) {
        var id = desktopId.trim();
        if (!id)
            return;

        // Enpass won't launch over the normal way. Therefore, this launches
        // the binary in its own graphical service.
        if (id === "enpass") {
            Quickshell.execDetached(["systemd-run", "--user", "--collect", "--quiet", "--slice=app-graphical.slice", "/opt/enpass/Enpass"]);
            close();
            return;
        }

        // gtk-launch resolves the desktop entry while
        // uwsm-app places the application in the graphical application slice.
        Quickshell.execDetached(["uwsm-app", "--", "gtk-launch", id]);
        close();
    }

    function activate(row) {
        if (!row)
            return;

        if (row.target) {
            setMode(row.target);
            return;
        }
        if (row.copyText) {
            Quickshell.clipboardText = row.copyText;
            close();
            return;
        }
        if (row.desktopId) {
            launchApplication(row.desktopId);
            return;
        }
        if (row.packageName) {
            activatePackages([row.packageName]);
            return;
        }
        switch (row.action) {
        case "about":
            Quickshell.execDetached(["alacritty", "--title", "fastfetch", "-e", "fish", "-c", "fastfetch; show_done"]);
            close();
            break;
        case "update":
            launchTerminal("update", "system update");
            break;
        case "remove-system":
            setMode("package-remove");
            break;
        case "poweroff":
        case "reboot":
        case "logout":
        case "suspend":
            close();
            session.request(row.action);
            break;
        }
    }

    function activateSelected() {
        if (packageMode && selectedPackages.length > 0) {
            activatePackages(selectedPackages);
            return;
        }
        if (visibleRows.length > 0)
            activate(visibleRows[selectedIndex]);
    }

    onQueryChanged: {
        selectedIndex = 0;
        calcTimer.restart();
    }
    onCalculationFinished: function (expression, result) {
        if (mode === "apps" && query === expression)
            calcResult = result;
    }
    onVisibleRowsChanged: {
        if (selectedIndex >= visibleRows.length)
            selectedIndex = Math.max(0, visibleRows.length - 1);
    }

    Process {
        id: dataProcess

        stdout: StdioCollector {
            onStreamFinished: {
                var lines = String(text || "").split("\n");
                var rows = [];
                var flatpakMode = root.dataProcessMode === "package-flatpak" || root.dataProcessMode === "package-flatpak-remove";
                var seenPackages = {};
                for (var i = 0; i < lines.length; i++) {
                    var line = lines[i].trim();
                    if (!line)
                        continue;

                    var columns = line.split("\t");
                    var packageName = String(columns[0] || "").trim();
                    if (!packageName || seenPackages[packageName])
                        continue;
                    seenPackages[packageName] = true;
                    rows.push({
                        "icon": flatpakMode ? "" : (root.dataProcessMode === "package-remove" ? "󰆴" : "󰏗"),
                        "label": String(columns[1] || packageName).trim() || packageName,
                        "detail": String(columns[2] || "").trim() || "No description available",
                        "searchText": packageName + " " + String(columns[3] || ""),
                        "packageName": packageName
                    });
                }
                if (flatpakMode) {
                    rows.sort(function (a, b) {
                        var titleOrder = String(a.label).localeCompare(String(b.label));
                        return titleOrder !== 0 ? titleOrder : String(a.packageName).localeCompare(String(b.packageName));
                    });
                }
                if (root.mode === root.dataProcessMode)
                    root.dataRows = rows;
            }
        }

        onExited: {
            var nextMode = root.queuedDataMode;
            root.queuedDataMode = "";
            if (nextMode && root.mode === nextMode)
                root.loadModeData();
        }
    }

    Process {
        id: qalcProcess
        property string expression: ""

        stdout: StdioCollector {
            onStreamFinished: root.calculationFinished(qalcProcess.expression, text.trim())
        }
    }

    Timer {
        id: calcTimer

        interval: 100
        onTriggered: {
            if (root.mode !== "apps" || !root.query.trim())
                return;

            var values = DesktopEntries.applications ? DesktopEntries.applications.values : [];
            if (AppSearch.search(values, root.query).length === 0)
                root.calc(root.query);
        }
    }

    Variants {
        model: Quickshell.screens

        delegate: Component {
            PanelWindow {
                id: panel

                required property var modelData
                readonly property bool targetPanel: root.targetScreenName !== "" ? root.targetScreenName === modelData.name : modelData === Quickshell.screens[0]

                screen: modelData
                visible: root.opened
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.namespace: "arch-rice-launcher"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: visible && targetPanel ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
                mask: Region {
                    item: dismissArea
                }
                onVisibleChanged: {
                    if (visible && targetPanel)
                        Qt.callLater(function () {
                            input.forceActiveFocus();
                        });
                }

                anchors {
                    top: true
                    bottom: true
                    left: true
                    right: true
                }

                MouseArea {
                    id: dismissArea

                    anchors.fill: parent
                    onPressed: root.close()
                }

                Card {
                    visible: panel.targetPanel
                    width: root.compactStaticMenu ? 270 : 470
                    height: Math.min(panel.height - 48, Math.max(root.minimumCardHeight, Math.min(620, 100 + root.visibleRowsHeight)))
                    anchors.centerIn: parent

                    MouseArea {
                        anchors.fill: parent
                        onClicked: function (event) {
                            event.accepted = true;
                        }
                    }

                    Column {
                        anchors.fill: parent
                        anchors.margins: 18
                        spacing: 12

                        Rectangle {
                            id: header

                            width: parent.width
                            height: 52
                            radius: Theme.radius
                            color: Theme.mantle

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 14
                                anchors.verticalCenter: parent.verticalCenter
                                width: 20
                                text: ""
                                color: input.activeFocus ? Theme.mauve : Theme.overlay0
                                font.family: Theme.fontFamily
                                font.pixelSize: 17
                                horizontalAlignment: Text.AlignHCenter
                            }

                            TextInput {
                                id: input

                                anchors.fill: parent
                                anchors.leftMargin: 46
                                anchors.rightMargin: 14
                                verticalAlignment: TextInput.AlignVCenter
                                text: root.query
                                color: Theme.text
                                selectionColor: Theme.mauve
                                selectedTextColor: Theme.base
                                font.family: Theme.fontFamily
                                font.pixelSize: 17
                                cursorDelegate: Rectangle {
                                    width: 2
                                    radius: 1
                                    color: Theme.mauve
                                    opacity: 0.8
                                    visible: input.activeFocus && input.selectionStart === input.selectionEnd
                                }
                                focus: panel.visible && panel.targetPanel
                                onTextEdited: root.query = text
                                onActiveFocusChanged: {
                                    if (activeFocus && text !== root.query)
                                        text = root.query;
                                }
                                Keys.onPressed: function (event) {
                                    if (event.key === Qt.Key_Escape) {
                                        root.goBack();
                                        event.accepted = true;
                                    } else if (event.key === Qt.Key_Down) {
                                        root.keyboardSelectionActive = true;
                                        root.moveSelection(1);
                                        event.accepted = true;
                                    } else if (event.key === Qt.Key_Up) {
                                        root.keyboardSelectionActive = true;
                                        root.moveSelection(-1);
                                        event.accepted = true;
                                    } else if (event.key === Qt.Key_Tab && root.packageMode && root.visibleRows.length > 0) {
                                        root.keyboardSelectionActive = true;
                                        root.togglePackageSelection(root.visibleRows[root.selectedIndex]);
                                        root.moveSelection(1);
                                        event.accepted = true;
                                    } else if (event.key === Qt.Key_Backtab && root.packageMode && root.visibleRows.length > 0) {
                                        root.keyboardSelectionActive = true;
                                        root.togglePackageSelection(root.visibleRows[root.selectedIndex]);
                                        root.moveSelection(-1);
                                        event.accepted = true;
                                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                        root.activateSelected();
                                        event.accepted = true;
                                    } else if (event.key === Qt.Key_Backspace && root.query === "" && root.modeHistory.length > 0) {
                                        root.goBack();
                                        event.accepted = true;
                                    }
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: input.text === ""
                                    text: root.title
                                    color: Theme.overlay0
                                    font: input.font
                                }
                            }
                        }

                        Item {
                            width: parent.width
                            height: parent.height - header.height - parent.spacing

                            ListView {
                                id: rowsList

                                function scrollBy(distance) {
                                    var minimumY = originY;
                                    var maximumY = Math.max(minimumY, originY + contentHeight - height);
                                    contentY = Util.clamp(contentY + distance, minimumY, maximumY);
                                }

                                anchors.fill: parent
                                model: root.visibleRows
                                clip: true
                                spacing: 4
                                boundsBehavior: Flickable.StopAtBounds
                                reuseItems: true
                                currentIndex: root.selectedIndex
                                onCurrentIndexChanged: {
                                    if (currentIndex >= 0)
                                        positionViewAtIndex(currentIndex, ListView.Contain);
                                }

                                Connections {
                                    function onModeChanged() {
                                        rowsList.positionViewAtBeginning();
                                    }

                                    function onQueryChanged() {
                                        rowsList.positionViewAtBeginning();
                                    }

                                    target: root
                                }

                                delegate: ActionRow {
                                    required property var modelData
                                    required property int index
                                    readonly property bool packageMarked: !!modelData.packageName && root.packageSelected(modelData.packageName)

                                    width: ListView.view.width
                                    icon: packageMarked ? "󰄬" : (modelData.icon || "")
                                    iconSource: modelData.iconSource || ""
                                    label: modelData.label || ""
                                    detail: modelData.detail || ""
                                    current: index === root.selectedIndex
                                    selected: !root.packageMode && index === root.selectedIndex
                                    accented: packageMarked
                                    focusOnClick: false
                                    mouseHighlightEnabled: !root.keyboardSelectionActive || index === root.selectedIndex
                                    onPointerInteraction: {
                                        root.keyboardSelectionActive = false;
                                        root.selectedIndex = index;
                                    }
                                    onActivated: root.activate(modelData)
                                    onSecondaryActivated: {
                                        if (root.packageMode)
                                            root.togglePackageSelection(modelData);
                                    }
                                    onScrollRequested: function (delta) {
                                        rowsList.scrollBy(delta);
                                    }
                                }
                            }

                            Text {
                                visible: root.visibleRows.length === 0
                                anchors.fill: parent
                                text: dataProcess.running ? "Loading…" : "No results"
                                color: Theme.overlay0
                                font.family: Theme.fontFamily
                                font.pixelSize: 14
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }
                }
            }
        }
    }
}

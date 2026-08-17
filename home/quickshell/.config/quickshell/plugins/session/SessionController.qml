import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
    id: root

    property bool active: false
    property bool committed: false
    property string action: ""
    property string targetScreenName: ""
    property string errorMessage: ""

    readonly property string icon: errorMessage !== "" ? "󰅙" : action === "poweroff" ? "󰐥" : action === "reboot" ? "󰜉" : action === "logout" ? "󰍃" : "󰤄"
    readonly property string message: errorMessage !== "" ? errorMessage : action === "poweroff" ? "Shutting down…" : action === "reboot" ? "Restarting…" : action === "logout" ? "Logging out…" : "Suspending…"

    function request(nextAction) {
        if (["poweroff", "reboot", "logout", "suspend"].indexOf(nextAction) < 0)
            return;
        action = nextAction;
        targetScreenName = Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name || "") : "";
        committed = false;
        errorMessage = "";
        active = true;
        commitTimer.restart();
    }

    function cancel() {
        if (committed)
            return;
        commitTimer.stop();
        reset();
    }

    function reset() {
        actionTimeoutTimer.stop();
        active = false;
        committed = false;
        action = "";
        errorMessage = "";
    }

    function failCommit(message, details) {
        var detailText = String(details || "").trim();
        console.warn("Session action failed: " + message + (detailText ? ": " + detailText : ""));
        actionTimeoutTimer.stop();
        committed = false;
        errorMessage = message;
    }

    function actionName() {
        return action === "poweroff" ? "shutdown" : action === "reboot" ? "restart" : action === "logout" ? "logout" : "suspend";
    }

    function commit() {
        if (!active)
            return;
        committed = true;

        if (action === "suspend") {
            suspendProcess.command = ["bash", "-lc", "sleep 0.4; systemctl suspend"];
            suspendProcess.running = true;
            return;
        }

        var command = action === "poweroff" ? ["systemctl", "poweroff", "--no-wall"] : action === "reboot" ? ["systemctl", "reboot", "--no-wall"] : ["uwsm", "stop"];

        var args = ["systemd-run", "--user", "--collect", "--quiet", "--on-active=2s", "--timer-property=AccuracySec=100ms"];
        for (var i = 0; i < command.length; i++)
            args.push(command[i]);
        scheduleProcess.command = args;
        scheduleProcess.running = true;
    }

    Timer {
        id: commitTimer
        interval: 900
        onTriggered: root.commit()
    }

    Timer {
        id: actionTimeoutTimer
        interval: 12000
        onTriggered: {
            if (root.active && root.committed)
                root.failCommit("The " + root.actionName() + " action did not complete", "timed out after scheduling");
        }
    }

    Process {
        id: scheduleProcess

        stderr: StdioCollector {
            id: scheduleStderr
            waitForEnd: true
        }

        onExited: function (exitCode, exitStatus) {
            if (exitCode !== 0 || exitStatus !== 0) {
                root.failCommit("Could not schedule " + root.actionName(), scheduleStderr.text);
                return;
            }

            closeWindowsProcess.command = ["bash", "-lc", "hyprctl clients -j | jq -r '.[].address' | while read -r address; do hyprctl dispatch closewindow address:$address >/dev/null 2>&1 || true; done"];
            closeWindowsProcess.running = true;
            actionTimeoutTimer.restart();
        }
    }

    Process {
        id: closeWindowsProcess

        onExited: function (exitCode, exitStatus) {
            if (exitCode !== 0 || exitStatus !== 0)
                console.warn("Failed to close one or more application windows before " + root.actionName());
        }
    }

    Process {
        id: suspendProcess

        stderr: StdioCollector {
            id: suspendStderr
            waitForEnd: true
        }

        onExited: function (exitCode, exitStatus) {
            if (exitCode !== 0 || exitStatus !== 0) {
                root.failCommit("Could not suspend", suspendStderr.text);
                return;
            }
            root.reset();
        }
    }

    Variants {
        model: Quickshell.screens

        delegate: Component {
            PanelWindow {
                id: panel
                required property var modelData

                readonly property bool acceptsFocus: root.targetScreenName === "" ? modelData === Quickshell.screens[0] : modelData.name === root.targetScreenName

                screen: modelData
                visible: root.active
                anchors {
                    top: true
                    bottom: true
                    left: true
                    right: true
                }
                color: Qt.rgba(0.06, 0.055, 0.09, 0.94)
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.namespace: "arch-rice-session"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: visible && acceptsFocus ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

                Column {
                    anchors.centerIn: parent
                    spacing: 20

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.icon
                        color: root.errorMessage !== "" ? Theme.red : Theme.mauve
                        font.family: Theme.fontFamily
                        font.pixelSize: 72
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.message
                        color: root.errorMessage !== "" ? Theme.red : Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: 25
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: !root.committed
                        text: root.errorMessage !== "" ? "Esc to close" : "Esc to cancel"
                        color: Theme.overlay0
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                    }
                }

                Item {
                    id: keyHandler
                    anchors.fill: parent
                    focus: panel.visible && panel.acceptsFocus
                    Keys.onEscapePressed: root.cancel()
                }

                onVisibleChanged: if (visible && acceptsFocus)
                    Qt.callLater(function () {
                        keyHandler.forceActiveFocus();
                    })

                onAcceptsFocusChanged: if (visible && acceptsFocus)
                    Qt.callLater(function () {
                        keyHandler.forceActiveFocus();
                    })
            }
        }
    }
}

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Polkit
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
    id: root

    property string message: "Authentication is required"
    property string prompt: "Password"
    property bool failed: false
    property bool submitted: false
    property string targetScreenName: ""

    readonly property bool dialogVisible: agent.isActive

    function syncFlow() {
        var flow = agent.flow;
        if (!flow)
            return;
        message = String(flow.message || "Authentication is required");
        prompt = String(flow.inputPrompt || "Password").replace(/:\s*$/, "");
        failed = !!flow.failed;
        if (flow.isResponseRequired)
            submitted = false;
    }

    function submit(password) {
        var flow = agent.flow;
        if (!flow || !flow.isResponseRequired)
            return;
        submitted = true;
        failed = false;
        flow.submit(password);
    }

    function cancel() {
        if (agent.flow)
            agent.flow.cancelAuthenticationRequest();
    }

    PolkitAgent {
        id: agent
        path: "/org/archrice/PolkitAgent"

        onAuthenticationRequestStarted: {
            root.targetScreenName = Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name || "") : "";
            root.submitted = false;
            root.failed = false;
            root.syncFlow();
        }
        onIsActiveChanged: if (isActive)
            root.syncFlow()
        onIsRegisteredChanged: {
            if (isRegistered)
                console.log("arch-rice Polkit agent registered");
            else
                console.warn("arch-rice Polkit agent is not registered; another agent may be active");
        }
    }

    Connections {
        target: agent.flow
        function onInputPromptChanged() {
            root.syncFlow();
        }
        function onIsResponseRequiredChanged() {
            root.syncFlow();
        }
        function onSupplementaryMessageChanged() {
            root.syncFlow();
        }
        function onFailedChanged() {
            root.syncFlow();
        }
        function onAuthenticationFailed() {
            root.failed = true;
            root.submitted = false;
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
                visible: root.dialogVisible
                anchors {
                    top: true
                    bottom: true
                    left: true
                    right: true
                }
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.namespace: "arch-rice-polkit"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: acceptsFocus ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

                Card {
                    width: 390
                    height: 190
                    anchors.centerIn: parent
                    border.color: root.failed ? Theme.red : Theme.mauve

                    Column {
                        anchors.fill: parent
                        anchors.margins: 24
                        spacing: 16

                        Text {
                            width: parent.width
                            text: "  " + root.message
                            color: root.failed ? Theme.red : Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                            wrapMode: Text.Wrap
                            horizontalAlignment: Text.AlignHCenter
                        }

                        Rectangle {
                            width: parent.width
                            height: 48
                            radius: Theme.radius
                            color: Theme.mantle
                            border.width: 1
                            border.color: root.failed ? Theme.red : Theme.surface1

                            TextInput {
                                id: passwordInput
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                verticalAlignment: TextInput.AlignVCenter
                                echoMode: TextInput.Password
                                enabled: !root.submitted
                                color: Theme.text
                                selectionColor: Theme.mauve
                                font.family: Theme.fontFamily
                                font.pixelSize: 16
                                focus: panel.visible && panel.acceptsFocus

                                Keys.onEscapePressed: root.cancel()
                                Keys.onReturnPressed: {
                                    var password = text;
                                    text = "";
                                    root.submit(password);
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.leftMargin: 14
                                visible: passwordInput.text === ""
                                text: root.submitted ? "Authenticating…" : root.prompt
                                color: Theme.overlay0
                                font: passwordInput.font
                            }
                        }

                        Text {
                            width: parent.width
                            text: root.failed ? "Authentication failed — try again" : "Enter to authenticate · Esc to cancel"
                            color: root.failed ? Theme.red : Theme.overlay0
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }

                onVisibleChanged: {
                    passwordInput.text = "";
                    if (visible && acceptsFocus)
                        Qt.callLater(function () {
                            passwordInput.forceActiveFocus();
                        });
                }
            }
        }
    }
}

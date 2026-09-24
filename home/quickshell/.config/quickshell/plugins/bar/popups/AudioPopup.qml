import QtQuick
import qs.Commons
import qs.Ui

BarPopup {
    id: root

    required property var audio
    property int configuredDeviceId: -1
    property int configuredProfileDevice: -1
    property bool configuredOutput: true

    function propertyNumber(node, name) {
        if (!node || !node.properties)
            return -1;

        var value = Number(node.properties[name]);
        return isNaN(value) ? -1 : value;
    }

    function toggleDeviceConfiguration(node, output) {
        if (!node)
            return;

        var nextDeviceId = propertyNumber(node, "device.id");
        if (nextDeviceId < 0)
            return;

        if (configuredDeviceId === nextDeviceId && configuredOutput === output) {
            closeDeviceConfiguration();
            return;
        }

        configuredDeviceId = nextDeviceId;
        configuredProfileDevice = propertyNumber(node, "card.profile.device");
        configuredOutput = output;
    }

    function closeDeviceConfiguration() {
        configuredDeviceId = -1;
        configuredProfileDevice = -1;
    }

    function outputVolumeName() {
        if (audio.outputMuted)
            return "Muted";

        var percent = Math.round(audio.outputVolume * 100);
        if (percent === 0)
            return "Silenced";
        if (percent >= 100)
            return "Concert hall";
        if (percent >= 85)
            return "Party mode";
        if (percent >= 70)
            return "Cranked up";
        if (percent >= 50)
            return "Steady groove";
        if (percent >= 30)
            return "Easy listening";
        if (percent >= 15)
            return "Murmur";
        return "Whisper";
    }

    popupWidth: 390
    popupHeight: 540
    customKeyHandler: function (event) {
        if (event.key === Qt.Key_Escape && root.configuredDeviceId >= 0) {
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
        if (!opened)
            closeDeviceConfiguration();
    }

    component AudioDeviceEntry: Item {
        id: entryRoot

        required property var node
        property bool output: true
        readonly property int entryDeviceId: root.propertyNumber(node, "device.id")
        readonly property bool configurationExpanded: root.configuredDeviceId === entryDeviceId && root.configuredOutput === output

        implicitHeight: entryColumn.implicitHeight

        Column {
            id: entryColumn

            width: parent.width
            spacing: 4

            ActionRow {
                id: deviceRow

                width: parent.width
                icon: node === (output ? root.audio.sink : root.audio.source) ? (output ? "󰓃" : "󰍬") : (output ? "󰋋" : "󰍮")
                label: root.audio.labelFor(node)
                selected: node === (output ? root.audio.sink : root.audio.source)
                accent: output ? Theme.red : Theme.yellow

                function keyboardConfigure() {
                    root.toggleDeviceConfiguration(node, output);
                }

                onActivated: {
                    if (root.configuredDeviceId >= 0 && !configurationExpanded)
                        root.closeDeviceConfiguration();
                    if (output)
                        root.audio.selectSink(node);
                    else
                        root.audio.selectSource(node);
                }
                onSecondaryActivated: root.toggleDeviceConfiguration(node, output)
            }

            Loader {
                id: configurationLoader

                x: 24
                width: parent.width - x
                active: configurationExpanded
                visible: active
                height: active && item ? item.implicitHeight : 0

                sourceComponent: AudioDeviceConfiguration {
                    width: configurationLoader.width
                    deviceId: entryDeviceId
                    profileDevice: root.configuredProfileDevice
                    output: entryRoot.output
                }
            }
        }
    }

    Column {
        anchors.fill: parent
        spacing: Theme.popupSpacing

        PopupHeader {
            width: parent.width
            icon: root.audio.outputMuted ? "󰝟" : "󰕾"
            title: "Audio"
            subtitle: root.outputVolumeName()
            accent: Theme.red
            trailingControl: Component {
                PopupToggle {
                    checked: !root.audio.outputMuted
                    accent: Theme.red
                    onToggled: root.audio.toggleOutput()
                }
            }
        }

        WheelScrollView {
            width: parent.width
            height: parent.height - y
            contentWidth: width
            contentHeight: audioLists.implicitHeight

            Column {
                id: audioLists

                width: parent.width
                spacing: 4

                PopupSection {
                    width: parent.width
                    height: 22
                    text: "OUTPUT"
                    verticalAlignment: Text.AlignVCenter
                }

                PopupSlider {
                    width: parent.width
                    icon: root.audio.outputMuted ? "󰝟" : "󰕾"
                    value: root.audio.outputMuted ? 0 : root.audio.outputVolume
                    accent: Theme.red
                    onMoved: function (value) {
                        root.audio.setNodeVolume(root.audio.sink, value);
                    }
                    onIconClicked: root.audio.toggleOutput()
                }

                Repeater {
                    model: root.audio.sinks

                    AudioDeviceEntry {
                        required property var modelData

                        width: audioLists.width
                        node: modelData
                        output: true
                    }
                }

                PopupSeparator {
                    width: parent.width
                    visible: root.audio.sources.length > 0
                    verticalPadding: 4
                }

                PopupSection {
                    width: parent.width
                    height: visible ? 22 : 0
                    visible: root.audio.sources.length > 0
                    text: "INPUT"
                    verticalAlignment: Text.AlignVCenter
                }

                PopupSlider {
                    width: parent.width
                    visible: !!root.audio.source
                    icon: root.audio.inputMuted ? "󰍭" : "󰍬"
                    value: root.audio.inputMuted ? 0 : root.audio.inputVolume
                    accent: Theme.yellow
                    onMoved: function (value) {
                        root.audio.setNodeVolume(root.audio.source, value);
                    }
                    onIconClicked: root.audio.toggleInput()
                }

                Repeater {
                    model: root.audio.sources

                    AudioDeviceEntry {
                        required property var modelData

                        width: audioLists.width
                        node: modelData
                        output: false
                    }
                }

                PopupSeparator {
                    width: parent.width
                    visible: root.audio.streams.length > 0
                    verticalPadding: 4
                }

                PopupSection {
                    width: parent.width
                    height: visible ? 22 : 0
                    visible: root.audio.streams.length > 0
                    text: "SOURCES"
                    verticalAlignment: Text.AlignVCenter
                }

                Repeater {
                    model: root.audio.streams

                    PopupSlider {
                        required property var modelData

                        x: 3
                        width: audioLists.width - 6
                        icon: modelData.audio && modelData.audio.muted ? "󰝟" : "󰎈"
                        label: root.audio.labelFor(modelData)
                        value: modelData.audio && !modelData.audio.muted ? modelData.audio.volume : 0
                        accent: Theme.mauve
                        onMoved: function (value) {
                            root.audio.setNodeVolume(modelData, value);
                        }
                        onIconClicked: root.audio.toggleNode(modelData)
                    }
                }

                Item {
                    width: 1
                    height: root.audio.streams.length > 0 ? 3 : 0
                }
            }
        }
    }
}

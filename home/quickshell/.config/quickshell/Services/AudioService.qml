import QtQuick
import Quickshell.Services.Pipewire
import qs.Commons

Item {
    id: root

    property var osd: null
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property var nodes: Pipewire.nodes ? Pipewire.nodes.values : []
    readonly property var sinks: filterNodes(true, false)
    readonly property var sources: filterNodes(false, false)
    readonly property var streams: filterNodes(true, true)
    readonly property real outputVolume: sink && sink.audio ? sink.audio.volume : 0
    readonly property bool outputMuted: sink && sink.audio ? sink.audio.muted : true
    readonly property real inputVolume: source && source.audio ? source.audio.volume : 0
    readonly property bool inputMuted: source && source.audio ? source.audio.muted : true

    function filterNodes(wantsSink, wantsStream) {
        var result = [];
        for (var i = 0; i < nodes.length; i++) {
            var node = nodes[i];
            if (!node || node.isSink !== wantsSink || node.isStream !== wantsStream)
                continue;

            if (node.audio)
                result.push(node);
        }
        return result;
    }

    function labelFor(node) {
        if (!node)
            return "Unknown";

        return String(node.nickname || node.description || node.name || "Unknown");
    }

    function selectSink(node) {
        if (node)
            Pipewire.preferredDefaultAudioSink = node;
    }

    function selectSource(node) {
        if (node)
            Pipewire.preferredDefaultAudioSource = node;
    }

    function setNodeVolume(node, value) {
        if (!node || !node.audio)
            return;

        node.audio.muted = false;
        node.audio.volume = Util.clamp(value, 0, 1);
    }

    function toggleNode(node) {
        if (node && node.audio)
            node.audio.muted = !node.audio.muted;
    }

    function showOutput() {
        if (!osd)
            return;

        osd.show(outputMuted ? "󰝟" : "󰕾", outputMuted ? "Muted" : Math.round(outputVolume * 100) + "%", outputMuted ? 0 : outputVolume);
    }

    function showInput() {
        if (!osd)
            return;

        osd.show(inputMuted ? "󰍭" : "󰍬", inputMuted ? "Microphone muted" : "Microphone " + Math.round(inputVolume * 100) + "%", inputMuted ? 0 : inputVolume);
    }

    function adjustOutput(delta) {
        if (!sink || !sink.audio)
            return;

        sink.audio.muted = false;
        sink.audio.volume = Util.clamp(outputVolume + delta, 0, 1);
        showOutput();
    }

    function toggleOutput() {
        if (!sink || !sink.audio)
            return;

        sink.audio.muted = !sink.audio.muted;
        showOutput();
    }

    function adjustInput(delta) {
        if (!source || !source.audio)
            return;

        source.audio.volume = Util.clamp(inputVolume + delta, 0, 1);
        showInput();
    }

    function toggleInput() {
        if (!source || !source.audio)
            return;

        source.audio.muted = !source.audio.muted;
        showInput();
    }

    PwObjectTracker {
        objects: root.sink ? [root.sink] : []
    }

    PwObjectTracker {
        objects: root.source ? [root.source] : []
    }

    PwObjectTracker {
        objects: root.nodes
    }
}

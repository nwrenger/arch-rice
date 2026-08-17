pragma Singleton
import QtQuick
import Quickshell

QtObject {
    function clamp(value, minimum, maximum) {
        return Math.max(minimum, Math.min(maximum, value));
    }

    function wheelDistance(event) {
        var pixelDistance = event.pixelDelta.y;
        return pixelDistance !== 0 ? -pixelDistance * 1.5 : -event.angleDelta.y * 0.75;
    }

    function shellQuote(value) {
        return "'" + String(value).replace(/'/g, "'\\''") + "'";
    }

    function fileUrl(path) {
        var value = String(path || "");
        if (!value)
            return "";

        return value.indexOf("file://") === 0 ? value : "file://" + value;
    }

    function callAncestor(item, functionName, argument) {
        var ancestor = item;
        while (ancestor) {
            var callback = ancestor[functionName];
            if (typeof callback === "function") {
                callback(argument);
                return true;
            }
            ancestor = ancestor.parent;
        }
        return false;
    }

    function run(command) {
        if (Array.isArray(command))
            Quickshell.execDetached(command);
        else
            Quickshell.execDetached(["bash", "-lc", String(command)]);
    }
}

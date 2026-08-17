import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Item {
    id: root

    property var osd: null
    property int cpuUsage: 0
    property string vpnState: "Unknown"
    property string vpnCountry: ""
    property string vpnCity: ""
    property string vpnCountryCode: ""
    property string vpnCityCode: ""
    property bool uxplayRunning: false
    property string wifiState: "unavailable"
    property int wifiSignal: 0
    property string wifiSsid: ""
    property string lanState: "unavailable"
    property string lanInterface: ""
    property string lanAddress: ""
    property int lanSpeedMbps: 0
    readonly property bool vpnConnected: vpnState === "Connected" || vpnState === "Connecting"
    readonly property bool wifiAvailable: wifiState !== "unavailable"
    readonly property bool wifiConnected: wifiState === "connected"
    readonly property bool lanAvailable: lanState !== "unavailable"
    readonly property bool lanConnected: lanState === "connected"

    function startIfIdle(process) {
        if (!process.running)
            process.running = true;
    }

    function refresh() {
        var processes = [cpuProcess, vpnProcess, vpnRelayProcess, uxplayProcess, wifiProcess, lanProcess];
        for (var i = 0; i < processes.length; i++)
            startIfIdle(processes[i]);
    }

    function parseVpnStatus(text) {
        var output = String(text || "");
        var lines = output.split("\n");
        vpnState = String(lines[0] || "Unknown").trim();
        var locationMatch = output.match(/Visible location:\s*([^,\n]+),\s*([^.\n]+)\./);
        var locationIsVpn = vpnState === "Connected" && locationMatch;
        vpnCountry = locationIsVpn ? locationMatch[1].trim() : "";
        vpnCity = locationIsVpn ? locationMatch[2].trim() : "";
    }

    function parseVpnRelay(text) {
        var output = String(text || "");
        var cityMatch = output.match(/^\s*Location:\s*city\s+([a-z0-9-]+),\s*([a-z]{2})\s*$/im);
        var countryMatch = output.match(/^\s*Location:\s*country\s+([a-z]{2})\s*$/im);
        var hostnameMatch = output.match(/^\s*Location:\s*hostname\s+([a-z]{2})-([a-z0-9]+)-\S+\s*$/im);

        if (cityMatch) {
            vpnCountryCode = cityMatch[2].toLowerCase();
            vpnCityCode = cityMatch[1].toLowerCase();
        } else if (hostnameMatch) {
            vpnCountryCode = hostnameMatch[1].toLowerCase();
            vpnCityCode = hostnameMatch[2].toLowerCase();
        } else if (countryMatch) {
            vpnCountryCode = countryMatch[1].toLowerCase();
            vpnCityCode = "";
        } else if (/^\s*Location:\s*any\s*$/im.test(output)) {
            vpnCountryCode = "";
            vpnCityCode = "";
        }
    }

    function parseWifiStatus(text) {
        var fields = String(text || "unavailable\t0").trim().split("\t");
        wifiState = fields[0] || "unavailable";
        wifiSignal = Util.clamp(Number(fields[1] || "0") || 0, 0, 100);
        wifiSsid = fields[2] || "";
    }

    function parseLanStatus(text) {
        var fields = String(text || "unavailable\t\t\t0").trim().split("\t");
        lanState = fields[0] || "unavailable";
        lanInterface = fields[1] || "";
        lanAddress = fields[2] || "";
        lanSpeedMbps = Math.max(0, Number(fields[3] || "0") || 0);
    }

    function toggleVpn() {
        Quickshell.execDetached(["mullvad", vpnConnected ? "disconnect" : "connect"]);
        if (osd)
            osd.show("󰒃", vpnConnected ? "VPN disconnecting…" : "VPN connecting…", -1);

        delayedRefresh.restart();
    }

    function toggleUxPlay() {
        if (uxplayRunning)
            Quickshell.execDetached(["pkill", "-x", "uxplay"]);
        else
            Quickshell.execDetached(["uxplay", "-n", "nils", "-hls"]);
        if (osd)
            osd.show(uxplayRunning ? "󰀸" : "󱟲", uxplayRunning ? "AirPlay off" : "AirPlay active", -1);

        delayedRefresh.restart();
    }

    Timer {
        interval: 2000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Timer {
        id: delayedRefresh

        interval: 700
        onTriggered: root.refresh()
    }

    Process {
        id: cpuProcess

        command: ["bash", "-lc", "LC_ALL=C top -bn1 | awk '/Cpu\\(s\\)/ { printf \"%d\\n\", 100-$8; exit }'"]

        stdout: StdioCollector {
            onStreamFinished: root.cpuUsage = Util.clamp(Number(String(text || "0").trim()) || 0, 0, 100)
        }

    }

    Process {
        id: vpnProcess

        command: ["mullvad", "status"]

        stdout: StdioCollector {
            onStreamFinished: root.parseVpnStatus(text)
        }

    }

    Process {
        id: vpnRelayProcess

        command: ["mullvad", "relay", "get"]

        stdout: StdioCollector {
            onStreamFinished: root.parseVpnRelay(text)
        }
    }

    Process {
        id: uxplayProcess

        command: ["bash", "-lc", "pgrep -x uxplay >/dev/null && echo yes || echo no"]

        stdout: StdioCollector {
            onStreamFinished: root.uxplayRunning = String(text || "").trim() === "yes"
        }

    }

    Process {
        id: wifiProcess

        command: ["bash", "-lc", "iface=$(iwctl station list 2>/dev/null | sed $'s/\\033\\\\[[0-9;]*m//g' | awk '$2 ~ /^(connected|disconnected|connecting)$/ { print $1; exit }'); " + "if [ -z \"$iface\" ]; then printf 'unavailable\\t0\\n'; exit; fi; " + "details=$(iwctl station \"$iface\" show 2>/dev/null | sed $'s/\\033\\\\[[0-9;]*m//g'); " + "state=$(printf '%s\\n' \"$details\" | awk '$1 == \"State\" { print $2; exit }'); " + "rssi=$(printf '%s\\n' \"$details\" | awk '$1 == \"RSSI\" { print $2; exit }'); " + "signal=$((2 * (${rssi:--100} + 100))); " + "[ \"$signal\" -lt 0 ] && signal=0; [ \"$signal\" -gt 100 ] && signal=100; " + "ssid=$(printf '%s\\n' \"$details\" | awk '$1 == \"Connected\" && $2 == \"network\" { $1=\"\"; $2=\"\"; sub(/^ +/, \"\"); print; exit }'); " + "printf '%s\\t%d\\t%s\\n' \"${state:-disconnected}\" \"$signal\" \"$ssid\""]

        stdout: StdioCollector {
            onStreamFinished: root.parseWifiStatus(text)
        }

    }

    Process {
        id: lanProcess

        command: ["bash", "-lc", "iface=''; fallback=''; " +
            "for iface_path in /sys/class/net/*; do " +
            "[ -e \"$iface_path/device\" ] || continue; " +
            "[ -d \"$iface_path/wireless\" ] && continue; " +
            "iface_name=${iface_path##*/}; " +
            "[ -z \"$fallback\" ] && fallback=$iface_name; " +
            "if [ \"$(cat \"$iface_path/carrier\" 2>/dev/null)\" = 1 ]; then iface=$iface_name; break; fi; " +
            "done; " +
            "[ -n \"$iface\" ] || iface=$fallback; " +
            "if [ -z \"$iface\" ]; then printf 'unavailable\\t\\t\\t0\\n'; exit; fi; " +
            "carrier=$(cat \"/sys/class/net/$iface/carrier\" 2>/dev/null); " +
            "state=disconnected; [ \"$carrier\" = 1 ] && state=connected; " +
            "address=$(ip -4 -o address show dev \"$iface\" scope global 2>/dev/null | awk 'NR == 1 { split($4, value, \"/\"); print value[1] }'); " +
            "speed=$(cat \"/sys/class/net/$iface/speed\" 2>/dev/null); " +
            "case $speed in ''|*[!0-9]*) speed=0;; esac; " +
            "printf '%s\\t%s\\t%s\\t%d\\n' \"$state\" \"$iface\" \"$address\" \"$speed\""]

        stdout: StdioCollector {
            onStreamFinished: root.parseLanStatus(text)
        }
    }

}

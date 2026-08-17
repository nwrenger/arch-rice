import QtQuick
import Quickshell
import Quickshell.Io
import "Services"
import "plugins/background"
import "plugins/bar"
import "plugins/launcher"
import "plugins/notifications"
import "plugins/osd"
import "plugins/polkit"
import "plugins/session"

ShellRoot {
    id: shell

    function toggleLauncher(mode) {
        launcherOverlay.toggle(mode);
    }

    Osd {
        id: osd
    }

    AudioService {
        id: audio

        osd: osd
    }

    MediaService {
        id: mediaService

        osd: osd
    }

    StatusService {
        id: status

        osd: osd
    }

    Background {
        id: background
    }

    Notifications {
        id: notifications
    }

    PolkitAgent {
        id: polkit
    }

    SessionController {
        id: sessionController
    }

    Launcher {
        id: launcherOverlay

        session: sessionController
    }

    Bar {
        id: bar

        shell: shell
        audio: audio
        media: mediaService
        status: status
    }

    IpcHandler {
        function ping() : string {
            return "ok";
        }

        function launcher(mode: string) : string {
            launcherOverlay.toggle(mode);
            return "ok";
        }

        function volume(action: string) : string {
            if (action === "up")
                audio.adjustOutput(0.05);
            else if (action === "down")
                audio.adjustOutput(-0.05);
            else if (action === "mute")
                audio.toggleOutput();
            else
                return "unknown";
            return "ok";
        }

        function mic(action: string) : string {
            if (action === "mute")
                audio.toggleInput();
            else if (action === "up")
                audio.adjustInput(0.05);
            else if (action === "down")
                audio.adjustInput(-0.05);
            else
                return "unknown";
            return "ok";
        }

        function media(action: string) : string {
            if (action === "next")
                mediaService.next();
            else if (action === "previous")
                mediaService.previous();
            else if (action === "toggle")
                mediaService.playPause();
            else
                return "unknown";
            return "ok";
        }

        function uxplay(action: string) : string {
            if (action !== "toggle")
                return "unknown";

            status.toggleUxPlay();
            return "ok";
        }

        function wallpaper(action: string) : string {
            if (action !== "random")
                return "unknown";

            background.randomWallpaper();
            return "ok";
        }

        function setWallpaper(path: string) : string {
            background.setWallpaper(path, false);
            return "ok";
        }

        function session(action: string) : string {
            if (["poweroff", "reboot", "logout", "suspend"].indexOf(action) < 0)
                return "unknown";

            sessionController.request(action);
            return "ok";
        }

        function showOsd(icon: string, message: string) : string {
            osd.show(icon, message, -1);
            return "ok";
        }

        function popup(name: string) : string {
            if (["calendar", "audio", "network", "bluetooth", "media", "vpn"].indexOf(name) < 0)
                return "unknown";

            bar.togglePopupForFocusedScreen(name);
            return bar.activePopup + "@" + bar.activePopupScreen;
        }

        function popupState() : string {
            return bar.activePopup + "@" + bar.activePopupScreen;
        }

        function popupClose() : string {
            bar.closePopup(bar.activePopup, bar.activePopupScreen);
            bar.closeTrayMenu();
            return "ok";
        }

        target: "shell"
    }

}

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

Item {
    id: root

    readonly property string home: Quickshell.env("HOME")
    property string wallpaperDir: home + "/Pictures/wallpaper"
    readonly property string stateDir: home + "/.local/state"
    readonly property string statePath: stateDir + "/wallpaper"

    property string displayedWallpaper: ""
    property string incomingWallpaper: ""
    property real transitionProgress: 1

    function setWallpaper(path, instant) {
        var value = String(path || "").trim();
        if (!value || value === displayedWallpaper)
            return;
        stateFile.setText(value + "\n");

        transition.stop();
        if (instant || !displayedWallpaper) {
            displayedWallpaper = value;
            incomingWallpaper = "";
            transitionProgress = 1;
            return;
        }

        incomingWallpaper = value;
        transitionProgress = 0;
        transition.restart();
    }

    function randomWallpaper() {
        if (!randomProcess.running)
            randomProcess.running = true;
    }

    Process {
        id: ensureStateDir
        running: true
        command: ["mkdir", "-p", root.stateDir]
        onExited: stateFile.reload()
    }

    FileView {
        id: stateFile
        path: root.statePath
        watchChanges: true
        atomicWrites: true
        printErrors: false
        onLoaded: {
            var value = String(text() || "").trim();
            if (value)
                root.setWallpaper(value, root.displayedWallpaper === "");
            else
                root.randomWallpaper();
        }
        onLoadFailed: root.randomWallpaper()
        onFileChanged: reload()
    }

    Process {
        id: randomProcess
        command: ["bash", "-lc", "find " + Util.shellQuote(root.wallpaperDir) + " -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.gif' \\) -print0 | shuf -z -n1 | tr -d '\\0'"]
        stdout: StdioCollector {
            onStreamFinished: root.setWallpaper(String(text || "").trim(), false)
        }
    }

    NumberAnimation {
        id: transition
        target: root
        property: "transitionProgress"
        from: 0
        to: 1
        duration: 650
        easing.type: Easing.InOutCubic
        onFinished: {
            root.displayedWallpaper = root.incomingWallpaper;
            root.incomingWallpaper = "";
            root.transitionProgress = 1;
        }
    }

    Variants {
        model: Quickshell.screens

        delegate: Component {
            PanelWindow {
                id: panel
                required property var modelData

                screen: modelData
                anchors {
                    top: true
                    bottom: true
                    left: true
                    right: true
                }
                color: Theme.base
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.namespace: "arch-rice-background"
                WlrLayershell.layer: WlrLayer.Background
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

                WallpaperFrame {
                    anchors.fill: parent
                    path: root.displayedWallpaper
                    opacity: root.incomingWallpaper ? 1 - root.transitionProgress : 1
                }

                WallpaperFrame {
                    anchors.fill: parent
                    path: root.incomingWallpaper
                    visible: root.incomingWallpaper !== ""
                    opacity: root.transitionProgress
                }
            }
        }
    }

    component WallpaperFrame: Item {
        id: frame
        property string path: ""

        Loader {
            anchors.fill: parent
            active: frame.path !== ""
            sourceComponent: /\.gif$/i.test(frame.path) ? animatedFrame : staticFrame
        }

        Component {
            id: staticFrame
            Image {
                source: Util.fileUrl(frame.path)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                smooth: true
            }
        }

        Component {
            id: animatedFrame
            AnimatedImage {
                source: Util.fileUrl(frame.path)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                playing: true
                smooth: true
            }
        }
    }
}

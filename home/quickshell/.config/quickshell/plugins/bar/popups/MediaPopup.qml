import QtQuick
import qs.Commons
import qs.Ui

BarPopup {
    id: root

    required property var media
    readonly property var player: media.activePlayer

    function playerLabel(player) {
        return String(player.identity || player.dbusName || "Media player");
    }

    popupWidth: 390
    popupHeight: Math.min(410, 220 + media.players.length * 58)

    Column {
        anchors.fill: parent
        spacing: 10

        PopupHeader {
            width: parent.width
            icon: root.player && root.player.isPlaying ? "󰐊" : "󰏤"
            title: root.player && root.player.trackTitle ? root.player.trackTitle : "Nothing playing"
            subtitle: root.player && root.player.trackArtist ? root.player.trackArtist : (root.player ? root.playerLabel(root.player) : "Open a media player to begin")
            accent: Theme.green
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            height: 40
            spacing: 10

            PopupButton {
                text: "󰒮"
                enabled: !!root.player
                opacity: enabled ? 1 : 0.45
                onClicked: root.media.previous()
            }

            PopupButton {
                text: root.player && root.player.isPlaying ? "󰏤" : "󰐊"
                highlighted: true
                accent: Theme.green
                enabled: !!root.player
                opacity: enabled ? 1 : 0.45
                onClicked: root.media.playPause()
            }

            PopupButton {
                text: "󰒭"
                enabled: !!root.player
                opacity: enabled ? 1 : 0.45
                onClicked: root.media.next()
            }

        }

        PopupSection {
            width: parent.width
            height: 22
            visible: root.media.players.length > 0
            text: "PLAYERS"
            verticalAlignment: Text.AlignVCenter
        }

        WheelScrollView {
            width: parent.width
            height: parent.height - y
            contentWidth: width
            contentHeight: playerList.implicitHeight

            Column {
                id: playerList

                width: parent.width
                spacing: 3

                Repeater {
                    model: root.media.players

                    ActionRow {
                        required property var modelData

                        width: playerList.width
                        icon: modelData.isPlaying ? "󰐊" : "󰏤"
                        label: root.playerLabel(modelData)
                        detail: modelData.trackTitle || "No track information"
                        selected: modelData === root.player
                        accent: Theme.green
                        onActivated: root.media.activatePlayer(modelData)
                    }

                }

            }

        }

    }

}

import QtQuick
import Quickshell.Services.Mpris

Item {
    id: root

    property var osd: null
    readonly property var players: Mpris.players ? Mpris.players.values : []
    readonly property var activePlayer: {
        for (var i = 0; i < players.length; i++) {
            if (players[i] && players[i].isPlaying)
                return players[i];
        }
        return players.length > 0 ? players[0] : null;
    }

    function feedback(icon, action) {
        if (!osd)
            return;

        var player = activePlayer;
        var title = player && player.trackTitle ? player.trackTitle : action;
        var artist = player && player.trackArtist ? " — " + player.trackArtist : "";
        osd.show(icon, title + artist, -1);
    }

    function playPause() {
        var player = activePlayer;
        if (!player)
            return;

        if (player.isPlaying && player.canPause)
            player.pause();
        else if (!player.isPlaying && player.canPlay)
            player.play();
        else if (player.canTogglePlaying)
            player.togglePlaying();
        feedback(player.isPlaying ? "󰏤" : "󰐊", "Play/Pause");
    }

    function next() {
        var player = activePlayer;
        if (player && player.canGoNext)
            player.next();

        feedback("󰒭", "Next");
    }

    function previous() {
        var player = activePlayer;
        if (player && player.canGoPrevious)
            player.previous();

        feedback("󰒮", "Previous");
    }

    function activatePlayer(player) {
        if (!player)
            return;

        if (player === activePlayer) {
            playPause();
            return;
        }
        if (player.canPlay)
            player.play();
        else if (player.canTogglePlaying)
            player.togglePlaying();
    }
}

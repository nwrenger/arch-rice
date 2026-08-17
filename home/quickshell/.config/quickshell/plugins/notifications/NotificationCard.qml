import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.Commons
import qs.Ui

Card {
    id: root

    required property var notification
    signal dismissRequested
    signal actionRequested

    implicitWidth: 340
    implicitHeight: Math.max(88, content.implicitHeight + 24)
    border.color: notification.urgency === 2 ? Theme.red : Theme.mauve

    Row {
        id: content
        anchors.fill: parent
        anchors.margins: 12
        spacing: 12

        IconImage {
            width: 48
            height: 48
            anchors.verticalCenter: parent.verticalCenter
            source: notification.image || Quickshell.iconPath(notification.appIcon || "dialog-information", true)
        }

        Column {
            width: parent.width - 72
            anchors.verticalCenter: parent.verticalCenter
            spacing: 5

            Text {
                width: parent.width
                text: notification.summary || notification.appName || "Notification"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 14
                font.bold: true
                wrapMode: Text.Wrap
            }

            Text {
                width: parent.width
                visible: text !== ""
                text: notification.body || ""
                color: Theme.subtext0
                font.family: Theme.fontFamily
                font.pixelSize: 12
                textFormat: Text.RichText
                wrapMode: Text.Wrap
                maximumLineCount: 4
                elide: Text.ElideRight
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: function (event) {
            if (event.button === Qt.RightButton)
                root.dismissRequested();
            else
                root.actionRequested();
        }
    }
}

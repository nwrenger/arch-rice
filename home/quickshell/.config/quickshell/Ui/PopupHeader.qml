import QtQuick
import qs.Commons

Item {
    id: root

    property string icon: ""
    property string title: ""
    property string subtitle: ""
    property color accent: Theme.mauve

    implicitHeight: subtitle ? 54 : 38

    Row {
        anchors.fill: parent
        spacing: 12

        Text {
            width: 32
            anchors.verticalCenter: parent.verticalCenter
            text: root.icon
            color: root.accent
            font.family: Theme.fontFamily
            font.pixelSize: 24
            horizontalAlignment: Text.AlignHCenter
        }

        Column {
            width: parent.width - 44
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
                width: parent.width
                text: root.title
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 17
                font.bold: true
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                visible: root.subtitle !== ""
                text: root.subtitle
                color: Theme.subtext0
                font.family: Theme.fontFamily
                font.pixelSize: 11
                elide: Text.ElideRight
            }

        }

    }

}

import QtQuick
import qs.Commons

Item {
    id: root

    property string icon: ""
    property string title: ""
    property string subtitle: ""
    property color accent: Theme.mauve
    property bool separatorVisible: true
    property Component trailingControl: null

    property bool clickable: false

    signal clicked()

    implicitHeight: subtitle ? 48 : 38

    MouseArea {
        anchors.fill: parent
        enabled: root.clickable
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.clicked()
    }

    Row {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: parent.height - (root.separatorVisible ? 9 : 0)
        spacing: 14

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
            width: parent.width - 46 - (trailingLoader.visible ? trailingLoader.width + 14 : 0)
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
                width: parent.width
                text: root.title
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 14
                font.bold: true
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                visible: root.subtitle !== ""
                text: root.subtitle.toUpperCase()
                color: Theme.subtext0
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.bold: true
                font.letterSpacing: 1.2
                elide: Text.ElideRight
            }

        }

        Loader {
            id: trailingLoader

            width: item ? item.implicitWidth : 0
            height: item ? item.implicitHeight : 0
            anchors.verticalCenter: parent.verticalCenter
            visible: root.trailingControl !== null
            sourceComponent: root.trailingControl
        }

    }

    PopupSeparator {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: root.separatorVisible
    }

}

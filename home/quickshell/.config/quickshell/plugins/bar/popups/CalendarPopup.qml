import QtQuick
import qs.Commons
import qs.Ui

BarPopup {
    id: root

    property date now: new Date()
    property date viewedMonth: new Date(now.getFullYear(), now.getMonth(), 1)

    function changeMonth(delta) {
        viewedMonth = new Date(viewedMonth.getFullYear(), viewedMonth.getMonth() + delta, 1);
    }

    function resetToday() {
        now = new Date();
        viewedMonth = new Date(now.getFullYear(), now.getMonth(), 1);
    }

    function dayForCell(index) {
        var first = new Date(viewedMonth.getFullYear(), viewedMonth.getMonth(), 1).getDay();
        var mondayFirst = (first + 6) % 7;
        return index - mondayFirst + 1;
    }

    function daysInMonth() {
        return new Date(viewedMonth.getFullYear(), viewedMonth.getMonth() + 1, 0).getDate();
    }

    function isToday(day) {
        return day > 0 && day === now.getDate() && viewedMonth.getMonth() === now.getMonth() && viewedMonth.getFullYear() === now.getFullYear();
    }

    popupWidth: 360
    popupHeight: 392
    onOpenedChanged: {
        if (opened) {
            resetToday();
        }
    }

    Timer {
        interval: 60000
        repeat: true
        running: root.opened
        onTriggered: root.now = new Date()
    }

    Column {
        anchors.fill: parent
        spacing: 12

        PopupHeader {
            width: parent.width
            icon: "󰃭"
            title: Qt.formatDate(root.now, "dddd, d MMMM")
            subtitle: Qt.formatDate(root.now, "d.MM.yyyy")
            accent: Theme.blue
        }

        Row {
            width: parent.width
            height: 34

            PopupButton {
                width: 38
                text: "‹"
                onClicked: root.changeMonth(-1)
            }

            Text {
                width: parent.width - 76
                height: parent.height
                text: Qt.formatDate(root.viewedMonth, "MMMM yyyy")
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 14
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            PopupButton {
                width: 38
                text: "›"
                onClicked: root.changeMonth(1)
            }
        }

        Row {
            width: parent.width
            height: 22

            Repeater {
                model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

                Text {
                    required property string modelData

                    width: parent.width / 7
                    height: parent.height
                    text: modelData
                    color: Theme.overlay0
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }

        Grid {
            width: parent.width
            columns: 7
            rowSpacing: 4

            Repeater {
                model: 42

                Rectangle {
                    required property int index
                    readonly property int day: root.dayForCell(index)
                    readonly property bool validDay: day > 0 && day <= root.daysInMonth()

                    width: parent.width / 7
                    height: 34
                    radius: Theme.radius
                    color: root.isToday(day) ? Theme.blue : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: parent.validDay ? parent.day : ""
                        color: root.isToday(parent.day) ? Theme.base : (index % 7 >= 5 ? Theme.subtext0 : Theme.text)
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.bold: root.isToday(parent.day)
                    }
                }
            }
        }

        PopupButton {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Today"
            icon: "󰃭"
            highlighted: root.viewedMonth.getMonth() !== root.now.getMonth() || root.viewedMonth.getFullYear() !== root.now.getFullYear()
            accent: Theme.blue
            onClicked: root.resetToday()
        }
    }
}

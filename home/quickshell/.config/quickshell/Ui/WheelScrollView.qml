import QtQuick
import qs.Commons

Item {
    id: root

    default property alias content: contentRoot.data
    property alias contentWidth: view.contentWidth
    property alias contentHeight: view.contentHeight
    property alias contentY: view.contentY
    property alias moving: view.moving
    readonly property bool keyboardScrollView: true

    function scrollBy(distance) {
        var minimumY = view.originY;
        var maximumY = Math.max(minimumY, view.originY + view.contentHeight - view.height);
        view.contentY = Util.clamp(view.contentY + distance, minimumY, maximumY);
    }

    function ensureItemVisible(item) {
        if (!item)
            return;

        var position = contentRoot.mapFromItem(item, 0, 0);
        var top = position.y;
        var bottom = top + item.height;
        if (top < view.contentY)
            view.contentY = Math.max(view.originY, top);
        else if (bottom > view.contentY + view.height)
            view.contentY = Math.min(Math.max(view.originY, view.originY + view.contentHeight - view.height), bottom - view.height);
    }

    Flickable {
        id: view

        anchors.fill: parent
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        pixelAligned: true

        Item {
            id: contentRoot

            width: view.contentWidth
            height: view.contentHeight
        }

    }

    MouseArea {
        anchors.fill: parent
        z: 1000
        acceptedButtons: Qt.NoButton
        onWheel: function(event) {
            root.scrollBy(Util.wheelDistance(event));
            event.accepted = true;
        }
    }

}

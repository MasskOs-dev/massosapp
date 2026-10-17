import QtQuick
import FeatherIcons 1.0
Item {
    id: r
    property string d
    property color color: Theme.text
    property int size: 20
    property real sw: 2
    width: size; height: size
    Behavior on color { ColorAnimation { duration: 200 } }
    FeatherIcon { anchors.fill: parent; icon: r.d; color: r.color; iconSize: r.size; strokeWidth: r.sw }
}

pragma Singleton
import QtQuick
QtObject {
    property bool dark: true
    property color bg1:         dark ? "#1d272b" : "#eaf1fa"
    property color bg2:         dark ? "#12191c" : "#d3e0f0"
    property color glass:       dark ? "#8a2a373c" : "#a6ffffff"
    property color glassStrong: dark ? "#b3303e44" : "#d9ffffff"
    property color glassBorder: dark ? "#2effffff" : "#e6ffffff"
    property color hover:       dark ? "#33ffffff" : "#80ffffff"
    property color pill:        dark ? "#cc12191c" : "#f2ffffff"
    property color page:        dark ? "#171e21" : "#ffffff"
    property color text:        dark ? "#dfeceb" : "#1c2535"
    property color sub:         dark ? "#8a9ca0" : "#6d7a8d"
    property color accent:      dark ? "#62d6ca" : "#3f8cf0"
    property color blob1:       dark ? "#2f6f73" : "#7fb4ff"
    property color blob2:       dark ? "#2a4a63" : "#c9b8ff"
    property color blob3:       dark ? "#3a5a52" : "#9fe3d8"
    Behavior on bg1 { ColorAnimation { duration: 400 } }
    Behavior on bg2 { ColorAnimation { duration: 400 } }
    Behavior on glass { ColorAnimation { duration: 400 } }
    Behavior on glassStrong { ColorAnimation { duration: 400 } }
    Behavior on glassBorder { ColorAnimation { duration: 400 } }
    Behavior on hover { ColorAnimation { duration: 250 } }
    Behavior on pill { ColorAnimation { duration: 400 } }
    Behavior on page { ColorAnimation { duration: 400 } }
    Behavior on text { ColorAnimation { duration: 400 } }
    Behavior on sub { ColorAnimation { duration: 400 } }
    Behavior on accent { ColorAnimation { duration: 400 } }
    Behavior on blob1 { ColorAnimation { duration: 600 } }
    Behavior on blob2 { ColorAnimation { duration: 600 } }
    Behavior on blob3 { ColorAnimation { duration: 600 } }
}

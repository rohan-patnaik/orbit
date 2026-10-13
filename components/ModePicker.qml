import QtQuick
import qs.Commons

Row {
  id: root

  property string currentMode: "grid"
  property var features: ({
      grid: true,
      flip: true,
      icons: true
    })

  signal modeRequested(string mode)

  spacing: Style.space(6)

  Repeater {
    model: ["icons", "flip", "grid"].filter(mode => root.features[mode] !== false)

    Rectangle {
      id: pill

      required property int index
      required property var modelData

      readonly property bool selected: root.currentMode === modelData

      width: Style.space(82)
      height: Style.space(28)
      radius: height / 2
      color: selected ? Color.menu.selectedBackground : (hoverHandler.hovered ? Qt.alpha(Color.menu.text, 0.08) : "transparent")
      border.width: selected ? 1 : 0
      border.color: Color.accent

      Text {
        anchors.centerIn: parent
        text: (["icons", "flip", "grid"].indexOf(pill.modelData) + 1) + "  " + String(pill.modelData).charAt(0).toUpperCase() + String(pill.modelData).slice(1)
        color: pill.selected ? Color.menu.selectedText : Color.menu.text
        opacity: pill.selected || hoverHandler.hovered ? 1 : 0.68
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.caption
      }

      HoverHandler {
        id: hoverHandler
      }

      TapHandler {
        onTapped: root.modeRequested(String(pill.modelData))
      }
    }
  }
}

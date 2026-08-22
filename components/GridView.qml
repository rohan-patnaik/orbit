import QtQuick
import qs.Commons
import "../SwitcherLogic.js" as Logic

Item {
  id: root

  property var windows: []
  property int selectedIndex: 0
  property bool hoverArmed: false
  property real maximumWidth: Style.space(1240)
  property real maximumHeight: Style.space(720)

  signal selectRequested(int index)
  signal activateRequested(int index)

  readonly property int pageSize: 12
  readonly property int firstIndex: Logic.pageStart(root.selectedIndex, root.pageSize)
  readonly property var pageWindows: root.windows.slice(firstIndex, firstIndex + pageSize)
  readonly property int columnCount: Logic.gridColumns(pageWindows.length, maximumWidth)
  readonly property int rowCount: Math.ceil(pageWindows.length / Math.max(1, columnCount))
  readonly property real spacing: Style.space(12)
  readonly property real cardWidth: Math.min(Style.space(292), (maximumWidth - spacing * (columnCount - 1)) / Math.max(1, columnCount))
  readonly property real cardHeight: Math.min(Style.space(196), (maximumHeight - spacing * (rowCount - 1)) / Math.max(1, rowCount))

  implicitWidth: columnCount * cardWidth + Math.max(0, columnCount - 1) * spacing
  implicitHeight: rowCount * cardHeight + Math.max(0, rowCount - 1) * spacing

  Grid {
    anchors.fill: parent
    columns: root.columnCount
    spacing: root.spacing

    Repeater {
      model: root.pageWindows

      WindowCard {
        required property int index
        required property var modelData

        width: root.cardWidth
        height: root.cardHeight
        windowData: modelData
        windowIndex: root.firstIndex + index
        selected: windowIndex === root.selectedIndex
        hoverArmed: root.hoverArmed
        previewEnabled: true
        onSelectRequested: requestedIndex => root.selectRequested(requestedIndex)
        onActivateRequested: requestedIndex => root.activateRequested(requestedIndex)
      }
    }
  }

  Text {
    visible: root.windows.length > root.pageSize
    anchors.top: parent.bottom
    anchors.topMargin: Style.space(6)
    anchors.horizontalCenter: parent.horizontalCenter
    text: (Math.floor(root.selectedIndex / root.pageSize) + 1) + " / " + Math.ceil(root.windows.length / root.pageSize)
    color: Color.menu.text
    opacity: 0.6
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.caption
  }
}

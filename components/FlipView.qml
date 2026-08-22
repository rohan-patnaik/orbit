import QtQuick
import qs.Commons
import "../SwitcherLogic.js" as Logic

Item {
  id: root

  property var windows: []
  property int selectedIndex: 0
  property bool hoverArmed: false
  property real maximumWidth: Style.space(1160)
  property real maximumHeight: Style.space(620)

  signal selectRequested(int index)
  signal activateRequested(int index)

  readonly property real cardWidth: Math.min(Style.space(430), maximumWidth * 0.5)
  readonly property real cardHeight: Math.min(Style.space(282), maximumHeight * 0.68)
  readonly property real horizontalStep: Math.min(Style.space(126), cardWidth * 0.3)
  readonly property var visibleEntries: Logic.flipEntries(windows, selectedIndex, 7)

  implicitWidth: Math.min(maximumWidth, cardWidth + horizontalStep * Math.max(0, visibleEntries.length - 1))
  implicitHeight: Math.min(maximumHeight, cardHeight + Style.space(92))

  Repeater {
    model: root.visibleEntries

    WindowCard {
      id: card

      required property var modelData

      readonly property int distance: Math.abs(modelData.offset)

      width: root.cardWidth
      height: root.cardHeight
      x: (root.width - width) / 2 + modelData.offset * root.horizontalStep
      y: (root.height - height) / 2 + distance * Style.space(14)
      z: 100 - distance * 10
      scale: 1 - distance * 0.075
      opacity: 1 - distance * 0.16
      windowData: modelData.windowData
      windowIndex: modelData.windowIndex
      selected: modelData.offset === 0
      hoverArmed: root.hoverArmed
      previewEnabled: true
      transform: Rotation {
        origin.x: card.width / 2
        origin.y: card.height / 2
        axis.x: 0
        axis.y: 1
        axis.z: 0
        angle: -card.modelData.offset * 13

        Behavior on angle {
          NumberAnimation {
            duration: 120
          }
        }
      }

      Behavior on x {
        NumberAnimation {
          duration: 120
        }
      }
      Behavior on y {
        NumberAnimation {
          duration: 120
        }
      }
      Behavior on scale {
        NumberAnimation {
          duration: 120
        }
      }
      Behavior on opacity {
        NumberAnimation {
          duration: 120
        }
      }

      onSelectRequested: requestedIndex => root.selectRequested(requestedIndex)
      onActivateRequested: requestedIndex => root.activateRequested(requestedIndex)
    }
  }
}

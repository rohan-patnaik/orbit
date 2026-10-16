import QtQuick
import qs.Commons
import qs.Commons as OrbitTheme

Column {
  id: root

  property var features: ({})
  signal featureRequested(string key)
  spacing: Style.space(8)

  Text {
    text: "Desktop features"
    color: OrbitTheme.Color.menu.text
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.body
    font.bold: true
  }

  Grid {
    columns: 2
    spacing: Style.space(8)
    width: parent.width

    Repeater {
      model: [
        {
          key: "dock",
          label: "Application dock"
        },
        {
          key: "grid",
          label: "Grid"
        },
        {
          key: "flip",
          label: "Flip"
        },
        {
          key: "icons",
          label: "Icons"
        },
        {
          key: "taskManager",
          label: "Task Manager"
        }
      ]

      Rectangle {
        id: tile

        required property var modelData
        activeFocusOnTab: true
        Accessible.role: Accessible.CheckBox
        Accessible.name: modelData.label
        Accessible.checkable: true
        Accessible.checked: checked
        Accessible.onPressAction: root.featureRequested(String(modelData.key))
        Keys.onSpacePressed: root.featureRequested(String(modelData.key))
        readonly property bool checked: root.features[modelData.key] !== false
        width: (root.width - Style.space(8)) / 2
        height: Style.space(42)
        radius: Style.cornerRadius
        color: checked ? Qt.alpha(OrbitTheme.Color.menu.text, 0.06) : "transparent"
        border.width: 1
        border.color: OrbitTheme.Color.menu.border

        Rectangle {
          id: check

          anchors.left: parent.left
          anchors.leftMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(20)
          height: width
          radius: Style.space(4)
          color: tile.checked ? OrbitTheme.Color.accent : "transparent"
          border.width: 1
          border.color: tile.checked ? OrbitTheme.Color.accent : OrbitTheme.Color.menu.border

          Text {
            anchors.centerIn: parent
            visible: tile.checked
            text: "✓"
            color: OrbitTheme.Color.background
            font.pixelSize: Style.font.caption
          }
        }

        Text {
          anchors.left: check.right
          anchors.leftMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          text: tile.modelData.label
          color: OrbitTheme.Color.menu.text
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.body
        }

        TapHandler {
          gesturePolicy: TapHandler.ReleaseWithinBounds
          onTapped: root.featureRequested(String(tile.modelData.key))
        }
      }
    }
  }

  Text {
    width: parent.width
    text: "Task Manager: Ctrl+Shift+Esc; off uses btop. All features start on. Turn all three views off for direct Alt+Tab switching."
    color: OrbitTheme.Color.menu.text
    opacity: 0.65
    wrapMode: Text.WordWrap
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.caption
  }
}

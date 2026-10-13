import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

PopupCard {
  id: root
  required property var taskbar
  property var task: null
  property int page: 0
  readonly property var windows: task ? task.windows.slice().sort(function (a, b) {
    return taskbar.safeAddress(a.address).localeCompare(taskbar.safeAddress(b.address))
  }) : []
  readonly property int pageSize: Math.max(1, Math.min(3, Math.floor((popupScreen ? popupScreen.width - 48 : 800) / 250)))
  readonly property int pageCount: Math.max(1, Math.ceil(windows.length / pageSize))
  readonly property var pageWindows: windows.slice(Math.min(page, pageCount - 1) * pageSize, (Math.min(page, pageCount - 1) + 1) * pageSize)
  readonly property real cardWidth: Math.min(250, (popupScreen ? popupScreen.width : 800) - 64)
  triggerMode: "hover"
  owner: taskbar.popoutOwner
  contentWidth: fittedContentWidth(pageWindows.length * cardWidth + Math.max(0, pageWindows.length - 1) * 8 + padding * 2 + Border.left(borderSpec) + Border.right(borderSpec))
  contentHeight: fittedContentHeight(previewColumn.implicitHeight)

  function selectWindow(window) {
    taskbar.hidePreviews()
    taskbar.focusWindow(window)
  }

  Column {
    id: previewColumn
    width: parent.width
    spacing: 8

    Row {
      id: previewRow
      spacing: 8
      Repeater {
        id: previewCards
        model: root.pageWindows.length
        Rectangle {
          id: card
          required property int index
          readonly property var window: root.pageWindows[index]
          readonly property var client: window ? window.lastIpcObject : ({})
          readonly property bool minimized: !!root.taskbar.minimizedState(window)
          readonly property var snapshot: root.taskbar.savedPreview(window)
          readonly property bool useSnapshot: snapshot !== null && !root.taskbar.taskIsActive({
            windows: [window]
          })
          width: root.cardWidth
          height: 182
          radius: 8
          color: Qt.alpha(Color.popups.text, cardMouse.containsMouse ? 0.12 : 0.045)
          border.width: 1
          border.color: Qt.alpha(Color.popups.text, cardMouse.containsMouse ? 0.28 : 0.09)

          MouseArea {
            id: cardMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.selectWindow(card.window)
          }

          Row {
            x: 10
            y: 9
            spacing: 7
            Image {
              width: 18
              height: 18
              source: root.taskbar.iconSource(root.task ? root.task.icon : "")
              layer.enabled: root.taskbar.symbolicIcon(root.task ? root.task.icon : "")
              layer.effect: ColorOverlay {
                color: root.taskbar.foreground
              }
              fillMode: Image.PreserveAspectFit
            }
            Text {
              width: card.width - 77
              text: card.client.title || (root.task ? root.task.name : "Window")
              textFormat: Text.PlainText
              color: Color.popups.text
              font.pixelSize: 12
              elide: Text.ElideRight
            }
          }
          Rectangle {
            x: parent.width - 31
            y: 5
            width: 26
            height: 26
            radius: 5
            color: closeMouse.containsMouse ? "#c42b1c" : "transparent"
            Text {
              anchors.centerIn: parent
              text: "×"
              font.pixelSize: 21
              color: Color.popups.text
            }
            MouseArea {
              id: closeMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.taskbar.closeTaskWindows({
                windows: [card.window]
              })
            }
          }

          Item {
            x: 8
            y: 39
            width: parent.width - 16
            height: 134
            clip: true
            ScreencopyView {
              id: thumbnail
              anchors.fill: parent
              captureSource: root.open && card.window && !card.useSnapshot ? card.window.wayland : null
              paintCursor: false
              live: root.open && !card.useSnapshot
              constraintSize: Qt.size(Math.max(1, width), Math.max(1, height))
              opacity: hasContent ? 1 : 0
            }
            Image {
              anchors.fill: parent
              visible: card.useSnapshot
              source: card.useSnapshot ? card.snapshot.capture.url : ""
              fillMode: Image.PreserveAspectFit
              smooth: true
            }
            Column {
              anchors.centerIn: parent
              spacing: 8
              visible: !thumbnail.hasContent && !card.useSnapshot
              Image {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 48
                height: 48
                source: root.taskbar.iconSource(root.task ? root.task.icon : "")
                layer.enabled: root.taskbar.symbolicIcon(root.task ? root.task.icon : "")
                layer.effect: ColorOverlay {
                  color: root.taskbar.foreground
                }
                fillMode: Image.PreserveAspectFit
              }
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: card.minimized ? "Minimized" : "Preview unavailable"
                color: Qt.alpha(Color.popups.text, 0.7)
                font.pixelSize: 11
              }
            }
          }
        }
      }
    }

    Row {
      visible: root.pageCount > 1
      height: visible ? 28 : 0
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 12
      Button {
        text: "‹"
        width: 32
        height: 28
        enabled: root.page > 0
        opacity: enabled ? 1 : 0.4
        onClicked: root.page = Math.max(0, root.page - 1)
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: (Math.min(root.page, root.pageCount - 1) * root.pageSize + 1) + "–" + Math.min((Math.min(root.page, root.pageCount - 1) + 1) * root.pageSize, root.windows.length) + " of " + root.windows.length + " windows"
        color: Color.popups.text
        font.pixelSize: 12
      }
      Button {
        text: "›"
        width: 32
        height: 28
        enabled: root.page < root.pageCount - 1
        opacity: enabled ? 1 : 0.4
        onClicked: root.page = Math.min(root.pageCount - 1, root.page + 1)
      }
    }
  }
}

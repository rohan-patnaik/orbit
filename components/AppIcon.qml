import QtQuick
import Quickshell

Item {
  id: root

  property string iconSource: ""
  property string fallbackText: "?"
  property bool showBackplate: false

  readonly property bool hasIcon: root.iconSource.length > 0
  readonly property bool canSampleIcon: root.iconSource.startsWith("file:") || root.iconSource.startsWith("/")
  readonly property color sampledColor: quantizer.colors.length > 0 ? quantizer.colors[0] : "#808080"
  readonly property real sampledLuminance: root.sampledColor.r * 0.2126 + root.sampledColor.g * 0.7152 + root.sampledColor.b * 0.0722
  readonly property color contrastBackplate: root.sampledLuminance < 0.5 ? "#f5f5f5" : "#171717"

  ColorQuantizer {
    id: quantizer

    source: root.showBackplate && root.hasIcon && root.canSampleIcon ? root.iconSource : ""
    depth: 0
    rescaleSize: 32
  }

  Rectangle {
    anchors.fill: parent
    visible: root.showBackplate || !root.hasIcon
    radius: Math.max(3, width * 0.22)
    color: root.hasIcon ? root.contrastBackplate : "#202020"
    border.width: root.showBackplate ? 1 : 0
    border.color: root.hasIcon && root.sampledLuminance < 0.5 ? "#d5d5d5" : "#303030"
  }

  Image {
    anchors.centerIn: parent
    width: root.showBackplate ? parent.width * 0.76 : parent.width
    height: root.showBackplate ? parent.height * 0.76 : parent.height
    visible: root.hasIcon
    source: root.iconSource
    fillMode: Image.PreserveAspectFit
    asynchronous: true
    smooth: true
    mipmap: true
    sourceSize.width: Math.max(1, width)
    sourceSize.height: Math.max(1, height)
  }

  Text {
    anchors.centerIn: parent
    visible: !root.hasIcon
    text: root.fallbackText || "?"
    color: "#f5f5f5"
    font.bold: true
    font.pixelSize: Math.max(9, Math.min(parent.width, parent.height) * 0.38)
  }
}

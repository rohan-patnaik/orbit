import QtQuick

Image {
  id: root

  property string iconSource: ""

  source: root.iconSource
  fillMode: Image.PreserveAspectFit
  asynchronous: true
  smooth: true
  mipmap: true
  sourceSize.width: Math.max(1, width)
  sourceSize.height: Math.max(1, height)
}

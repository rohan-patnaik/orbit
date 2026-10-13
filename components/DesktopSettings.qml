import QtQuick
import qs.Commons
import qs.Commons as OrbitTheme

Flickable {
  id: root

  property var modes: ({})
  property var features: ({})
  property string errorMessage: ""
  signal featureRequested(string key)
  signal toggleRequested(string mode)
  signal defaultRequested(string mode)
  signal applyRequested
  signal cancelRequested
  contentWidth: width
  contentHeight: content.implicitHeight
  boundsBehavior: Flickable.StopAtBounds
  clip: true

  Column {
    id: content

    width: root.width
    spacing: Style.space(16)

    FeatureSettings {
      width: parent.width
      features: root.features
      onFeatureRequested: key => root.featureRequested(key)
    }

    Text {
      width: parent.width
      visible: root.errorMessage !== ""
      text: root.errorMessage
      wrapMode: Text.WordWrap
      color: OrbitTheme.Color.menu.text
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.caption
    }

    WindowModeSettings {
      width: parent.width
      modes: root.modes
      onToggleRequested: mode => root.toggleRequested(mode)
      onDefaultRequested: mode => root.defaultRequested(mode)
      onApplyRequested: root.applyRequested()
      onCancelRequested: root.cancelRequested()
    }
  }
}

import QtQuick
import Quickshell
import Quickshell.Io
import "SwitcherLogic.js" as Logic
import "dock"

// A custom bar module, so existing taskbar pin/order settings keep their ID.
Item {
  id: root

  property QtObject bar: null
  property string moduleName: "taskbar"
  property var settings: ({})
  property var pluginPreferences: ({})
  readonly property bool dockEnabled: pluginPreferences.enabled !== false && Logic.normalizedFeatures(pluginPreferences.features).dock
  readonly property var openPanelIndicatorPopup: dockLoader.item ? dockLoader.item.openPanelIndicatorPopup : null
  implicitWidth: dockLoader.item ? dockLoader.item.implicitWidth : 0
  implicitHeight: dockLoader.item ? dockLoader.item.implicitHeight : 0
  visible: dockEnabled && dockLoader.status === Loader.Ready

  function close() {
    if (dockLoader.item)
      dockLoader.item.close()
  }

  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      try {
        const config = JSON.parse(text())
        const plugins = Array.isArray(config.plugins) ? config.plugins : []
        root.pluginPreferences = plugins.find(entry => entry && entry.id === "io.github.rohan-patnaik.window-switcher") || {}
      } catch (error) {
        console.warn("Orbit dock: unable to read preferences: " + error)
      }
    }
  }

  Loader {
    id: dockLoader
    active: root.dockEnabled
    anchors.fill: parent
    sourceComponent: Taskbar {
      popoutOwner: root
      bar: root.bar
      moduleName: root.moduleName
      settings: root.settings
    }
  }
}

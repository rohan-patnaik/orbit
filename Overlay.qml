import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import "components"
import "SwitcherLogic.js" as Logic

Item {
  id: root

  readonly property string pluginId: "io.github.rohan-patnaik.window-switcher"

  property var shell: null
  property var manifest: null
  property bool opened: false
  property bool releaseToActivate: false
  property bool sawKeyEvent: false
  property bool hoverArmed: false
  property point initialPointerPosition: Qt.point(-1, -1)
  property var windows: []
  property int selectedIndex: 0
  property string mode: "grid"
  property int snapshotWorkspaceId: -1
  property string snapshotMonitorName: ""
  property int snapshotMonitorId: -1
  property var targetScreen: null
  property var pendingWindow: null

  function applicationInfo(applicationClass, title) {
    const originalClass = String(applicationClass || "").trim()
    const lowerClass = originalClass.toLowerCase()
    const variants = [originalClass, lowerClass, lowerClass.replace(/-/g, ""), lowerClass.split(".")[0], lowerClass.split(".").pop()]

    for (const variant of variants) {
      if (!variant)
        continue
      const entry = DesktopEntries.byId(variant)
      if (entry)
        return desktopEntryInfo(entry, originalClass)
    }

    const applications = DesktopEntries.applications.values || []
    for (const entry of applications) {
      if (entry.startupClass && String(entry.startupClass).toLowerCase() === lowerClass) {
        return desktopEntryInfo(entry, originalClass)
      }
    }

    const lowerTitle = String(title || "").toLowerCase()
    if (lowerTitle) {
      for (const entry of applications) {
        const name = String(entry.name || "").trim()
        if (name && lowerTitle.includes(name.toLowerCase())) {
          return desktopEntryInfo(entry, originalClass)
        }
      }
    }

    for (const variant of variants) {
      if (!variant)
        continue
      const icon = Quickshell.iconPath(variant, true)
      if (icon) {
        return {
          name: Logic.friendlyAppName(originalClass),
          icon: icon
        }
      }
    }

    return {
      name: Logic.friendlyAppName(originalClass),
      icon: Quickshell.iconPath("application-x-executable", true)
    }
  }

  function desktopEntryInfo(entry, fallbackName) {
    return {
      name: String(entry.name || Logic.friendlyAppName(fallbackName)),
      icon: entry.icon ? Quickshell.iconPath(entry.icon, "application-x-executable") : Quickshell.iconPath("application-x-executable", true)
    }
  }

  function focusedScreen() {
    const screens = Quickshell.screens || []
    for (const screen of screens) {
      if (String(screen.name || "") === root.snapshotMonitorName)
        return screen
    }
    return screens.length > 0 ? screens[0] : null
  }

  function snapshotCurrentWindows() {
    const workspace = Hyprland.focusedWorkspace
    const monitor = Hyprland.focusedMonitor
    if (!workspace || !monitor || Number(workspace.id) <= 0)
      return []

    root.snapshotWorkspaceId = Number(workspace.id)
    root.snapshotMonitorName = String(monitor.name || "")
    root.snapshotMonitorId = Number(monitor.id)
    root.targetScreen = root.focusedScreen()

    const rows = []
    const toplevels = Hyprland.toplevels.values || []
    for (const toplevel of toplevels) {
      const ipc = toplevel.lastIpcObject || {}
      const address = Logic.safeAddress(toplevel.address || ipc.address)
      if (!address || ipc.mapped === false)
        continue
      const workspaceId = toplevel.workspace ? Number(toplevel.workspace.id) : Number(ipc.workspace ? ipc.workspace.id : -1)
      const monitorName = toplevel.monitor ? String(toplevel.monitor.name || "") : ""
      const monitorId = toplevel.monitor ? Number(toplevel.monitor.id) : Number(ipc.monitor)

      if (!Logic.isEligibleWindow(ipc, workspaceId, monitorName, monitorId, root.snapshotWorkspaceId, root.snapshotMonitorName, root.snapshotMonitorId)) {
        continue
      }

      const applicationClass = String(ipc.class || ipc.initialClass || (toplevel.wayland ? toplevel.wayland.appId : "") || "Application")
      const title = String(toplevel.title || ipc.title || applicationClass)
      const application = root.applicationInfo(applicationClass, title)
      rows.push({
        address: address,
        applicationClass: applicationClass,
        appName: application.name,
        iconSource: application.icon,
        title: title,
        focusHistoryId: Logic.focusHistoryId(ipc.focusHistoryID),
        groupIndex: Logic.groupIndex(ipc.grouped, address),
        pinned: ipc.pinned === true,
        xwayland: ipc.xwayland === true,
        toplevel: toplevel,
        wayland: toplevel.wayland || null
      })
    }

    return Logic.decorateDuplicateLabels(Logic.sortByRecency(rows))
  }

  function startSwitcher(activateOnRelease) {
    Hyprland.refreshToplevels()
    const nextWindows = root.snapshotCurrentWindows()
    if (nextWindows.length < 2)
      return
    root.windows = nextWindows
    root.selectedIndex = Logic.initialSelection(nextWindows)
    root.releaseToActivate = activateOnRelease
    root.sawKeyEvent = false
    root.hoverArmed = false
    root.initialPointerPosition = Qt.point(-1, -1)
    root.opened = true
    watchdog.restart()
  }

  function open(payloadJson) {
    let payload = {}
    if (payloadJson) {
      try {
        payload = JSON.parse(payloadJson)
      } catch (error) {
        console.warn("window-switcher: invalid invocation payload:", error)
      }
    }
    root.startSwitcher(payload.action === "next")
  }

  function close() {
    root.cancel()
  }

  function setMode(value) {
    root.mode = Logic.normalizeMode(value)
    return root.mode
  }

  function debugState(_argument) {
    const raw = []
    const toplevels = Hyprland.toplevels.values || []
    for (const toplevel of toplevels) {
      const ipc = toplevel.lastIpcObject || {}
      raw.push({
        address: String(toplevel.address || ""),
        title: String(toplevel.title || ""),
        workspaceId: toplevel.workspace ? Number(toplevel.workspace.id) : -1,
        monitorName: toplevel.monitor ? String(toplevel.monitor.name || "") : "",
        mapped: ipc.mapped,
        pinned: ipc.pinned,
        applicationClass: ipc.class,
        hasWaylandHandle: !!toplevel.wayland
      })
    }
    return JSON.stringify({
      focusedWorkspaceId: Hyprland.focusedWorkspace ? Number(Hyprland.focusedWorkspace.id) : -1,
      focusedMonitorName: Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name || "") : "",
      raw: raw,
      snapshot: root.snapshotCurrentWindows().map(window => ({
            address: window.address,
            label: window.label,
            title: window.title
          })),
      opened: root.opened
    })
  }

  function cycle(step) {
    root.selectedIndex = Logic.wrapIndex(root.selectedIndex + step, root.windows.length)
    watchdog.restart()
  }

  function select(index) {
    if (index < 0 || index >= root.windows.length)
      return
    root.selectedIndex = index
    watchdog.restart()
  }

  function navigate(direction) {
    if (root.mode !== "grid") {
      root.cycle(direction === "left" || direction === "up" ? -1 : 1)
      return
    }
    const firstIndex = Logic.pageStart(root.selectedIndex, 12)
    const pageCount = Math.min(12, root.windows.length - firstIndex)
    const availableWidth = root.targetScreen ? Number(root.targetScreen.width) - Style.space(96) : Style.space(1200)
    const columns = Logic.gridColumns(pageCount, availableWidth)
    root.select(Logic.gridMove(root.selectedIndex, direction, root.windows.length, columns))
  }

  function finish(activate) {
    if (!root.opened)
      return
    const selected = activate && root.selectedIndex >= 0 ? root.windows[root.selectedIndex] : null
    watchdog.stop()
    root.releaseToActivate = false
    root.opened = false
    if (!selected)
      return
    root.pendingWindow = selected
    activateTimer.restart()
  }

  function accept() {
    root.finish(true)
  }

  function cancel() {
    root.finish(false)
  }

  function pointerMoved(x, y) {
    if (root.hoverArmed)
      return
    if (root.initialPointerPosition.x < 0) {
      root.initialPointerPosition = Qt.point(x, y)
      return
    }
    const distance = Math.abs(x - root.initialPointerPosition.x) + Math.abs(y - root.initialPointerPosition.y)
    if (distance > 3)
      root.hoverArmed = true
  }

  function pruneClosedWindows() {
    if (!root.opened)
      return
    const liveAddresses = ({})
    const toplevels = Hyprland.toplevels.values || []
    for (const toplevel of toplevels) {
      const address = Logic.safeAddress(toplevel.address)
      if (address)
        liveAddresses[address] = true
    }
    const remaining = root.windows.filter(window => liveAddresses[window.address] === true)
    if (remaining.length === root.windows.length)
      return
    if (remaining.length < 2) {
      root.cancel()
      return
    }
    root.windows = Logic.decorateDuplicateLabels(remaining)
    root.selectedIndex = Math.min(root.selectedIndex, remaining.length - 1)
  }

  GlobalShortcut {
    appid: "omarchy-window-switcher"
    name: "next"
    description: "Cycle through current-workspace windows"

    onPressed: {
      if (root.opened)
        root.cycle(1)
      else
        root.startSwitcher(true)
    }
  }

  Connections {
    target: Hyprland.toplevels

    function onValuesChanged() {
      root.pruneClosedWindows()
    }
  }

  Timer {
    id: watchdog
    interval: 10000
    onTriggered: root.cancel()
  }

  Timer {
    id: activateTimer
    interval: 80
    onTriggered: {
      const selected = root.pendingWindow
      if (!selected)
        return
      if (selected.wayland)
        selected.wayland.activate()
      focusFallbackTimer.restart()
    }
  }

  Timer {
    id: focusFallbackTimer
    interval: 160
    onTriggered: {
      const selected = root.pendingWindow
      root.pendingWindow = null
      if (!selected)
        return
      const active = Hyprland.activeToplevel
      if (active && String(active.address) === selected.address)
        return
      if (selected.groupIndex > 0) {
        Hyprland.dispatch('hl.dsp.group.active({ window = "address:' + selected.address + '", index = ' + selected.groupIndex + ' })')
      }
      Hyprland.dispatch('hl.dsp.focus({ window = "address:' + selected.address + '" })')
    }
  }

  LazyLoader {
    active: root.opened

    PanelWindow {
      id: panel

      screen: root.targetScreen
      anchors {
        top: true
        bottom: true
        left: true
        right: true
      }
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "omarchy-window-switcher"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

      Timer {
        id: modifierPollTimer
        interval: 150
        repeat: true
        running: root.opened && root.releaseToActivate && !root.sawKeyEvent
        onTriggered: {
          if (!modifierCheck.running)
            modifierCheck.running = true
        }
      }

      Process {
        id: modifierCheck
        command: ["hyprctl", "eval", 'error(tostring(hl.is_key_down("Super_L") or hl.is_key_down("Super_R")))']
        stdout: StdioCollector {
          onStreamFinished: {
            if (!root.opened || !root.releaseToActivate || root.sawKeyEvent)
              return
            if (!text.trim().endsWith("true"))
              root.accept()
          }
        }
      }

      Rectangle {
        anchors.fill: parent
        color: Color.menu.scrim

        TapHandler {
          onTapped: root.cancel()
        }
      }

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        hoverEnabled: true
        onPositionChanged: mouse => root.pointerMoved(mouse.x, mouse.y)
      }

      Rectangle {
        id: switcherCard

        anchors.centerIn: parent
        width: Math.min(panel.width - Style.gapsOut * 2, Math.max(Style.space(360), viewLoader.width + Style.space(40)))
        height: Math.min(panel.height - Style.gapsOut * 2, viewLoader.height + Style.space(104))
        radius: Style.cornerRadius * 2
        color: Color.menu.background
        border.width: 1
        border.color: Color.menu.border
        focus: true

        Keys.onPressed: event => {
          root.sawKeyEvent = true
          if (event.key === Qt.Key_Escape) {
            root.cancel()
          } else if (event.key === Qt.Key_Q) {
            root.cycle(event.modifiers & Qt.ShiftModifier ? -1 : 1)
          } else if (event.key === Qt.Key_Tab) {
            root.navigate(event.modifiers & Qt.ShiftModifier ? "left" : "right")
          } else if (event.key === Qt.Key_Backtab) {
            root.cycle(-1)
          } else if (event.key === Qt.Key_Right) {
            root.navigate("right")
          } else if (event.key === Qt.Key_Left) {
            root.navigate("left")
          } else if (event.key === Qt.Key_Down) {
            root.navigate("down")
          } else if (event.key === Qt.Key_Up) {
            root.navigate("up")
          } else if (event.key === Qt.Key_1) {
            root.setMode("icons")
          } else if (event.key === Qt.Key_2) {
            root.setMode("flip")
          } else if (event.key === Qt.Key_3) {
            root.setMode("grid")
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            root.accept()
          } else {
            return
          }
          event.accepted = true
        }

        Keys.onReleased: event => {
          root.sawKeyEvent = true
          const superReleased = event.key === Qt.Key_Meta || event.key === Qt.Key_Super_L || event.key === Qt.Key_Super_R
          if (root.releaseToActivate && superReleased)
            root.accept()
          event.accepted = true
        }

        Text {
          id: heading
          anchors.top: parent.top
          anchors.topMargin: Style.space(18)
          anchors.horizontalCenter: parent.horizontalCenter
          text: "Windows · " + (root.mode === "grid" ? "Grid" : root.mode === "flip" ? "Flip" : "Icons")
          color: Color.menu.text
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }

        Loader {
          id: viewLoader

          anchors.centerIn: parent
          width: item ? item.implicitWidth : 0
          height: item ? item.implicitHeight : 0
          sourceComponent: root.mode === "grid" ? gridViewComponent : root.mode === "flip" ? flipViewComponent : iconsViewComponent
        }

        Component {
          id: iconsViewComponent

          IconsView {
            maximumWidth: panel.width - Style.space(96)
            windows: root.windows
            selectedIndex: root.selectedIndex
            hoverArmed: root.hoverArmed
            onSelectRequested: index => root.select(index)
            onActivateRequested: index => {
              root.select(index)
              root.accept()
            }
          }
        }

        Component {
          id: gridViewComponent

          GridView {
            maximumWidth: panel.width - Style.space(96)
            maximumHeight: panel.height - Style.space(190)
            windows: root.windows
            selectedIndex: root.selectedIndex
            hoverArmed: root.hoverArmed
            onSelectRequested: index => root.select(index)
            onActivateRequested: index => {
              root.select(index)
              root.accept()
            }
          }
        }

        Component {
          id: flipViewComponent

          FlipView {
            maximumWidth: panel.width - Style.space(96)
            maximumHeight: panel.height - Style.space(190)
            windows: root.windows
            selectedIndex: root.selectedIndex
            hoverArmed: root.hoverArmed
            onSelectRequested: index => root.select(index)
            onActivateRequested: index => {
              root.select(index)
              root.accept()
            }
          }
        }

        Text {
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(16)
          anchors.horizontalCenter: parent.horizontalCenter
          width: Math.min(parent.width - Style.space(48), Style.space(620))
          text: root.windows.length > 0 ? root.windows[root.selectedIndex].title : ""
          color: Color.menu.text
          opacity: 0.72
          elide: Text.ElideRight
          horizontalAlignment: Text.AlignHCenter
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}

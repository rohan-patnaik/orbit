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
  property string releaseModifier: ""
  property bool sawKeyEvent: false
  property bool hoverArmed: false
  property point initialPointerPosition: Qt.point(-1, -1)
  property var windows: []
  property int selectedIndex: 0
  property string mode: "grid"
  readonly property var entries: root.mode === "icons" ? Logic.applicationEntries(root.windows) : root.windows
  property int snapshotWorkspaceId: -1
  property string snapshotMonitorName: ""
  property int snapshotMonitorId: -1
  property var targetScreen: null
  property var pendingWindow: null
  property bool snapshotPending: false
  property bool snapshotCancelled: false
  property bool pendingActivateOnRelease: false
  property string pendingModifier: ""
  property int pendingDirection: 1
  property int queuedSteps: 0

  function applicationInfo(applicationClass, initialClass, appId) {
    const originalClass = String(applicationClass || "").trim()
    const rawVariants = [appId, applicationClass, initialClass]
    const variants = []
    for (const rawVariant of rawVariants) {
      const value = String(rawVariant || "").trim().replace(/\.desktop$/i, "")
      const lower = value.toLowerCase()
      const candidates = [value, lower, lower.replace(/-/g, ""), lower.split(".")[0], lower.split(".").pop()]
      for (const candidate of candidates) {
        if (candidate && !variants.includes(candidate))
          variants.push(candidate)
      }
    }

    for (const variant of variants) {
      const entry = DesktopEntries.byId(variant)
      if (entry)
        return desktopEntryInfo(entry, originalClass)
    }

    const applications = DesktopEntries.applications.values || []
    for (const entry of applications) {
      const startupClass = String(entry.startupClass || "").toLowerCase()
      if (startupClass && variants.includes(startupClass))
        return desktopEntryInfo(entry, originalClass)
    }

    for (const variant of variants) {
      const entry = DesktopEntries.heuristicLookup(variant)
      if (entry)
        return desktopEntryInfo(entry, originalClass)
    }

    for (const variant of variants) {
      const icon = Quickshell.iconPath(variant, true)
      if (icon) {
        return {
          id: Logic.normalizeApplicationKey(variant),
          name: Logic.friendlyAppName(originalClass),
          icon: icon,
          fallbackText: Logic.appMonogram(originalClass)
        }
      }
    }

    return {
      id: Logic.normalizeApplicationKey(appId || initialClass || originalClass),
      name: Logic.friendlyAppName(originalClass),
      icon: "",
      fallbackText: Logic.appMonogram(originalClass)
    }
  }

  function desktopEntryInfo(entry, fallbackName) {
    const name = String(entry.name || Logic.friendlyAppName(fallbackName))
    return {
      id: Logic.normalizeApplicationKey(entry.id || fallbackName),
      name: name,
      icon: entry.icon ? Quickshell.iconPath(entry.icon, true) : "",
      fallbackText: Logic.appMonogram(name)
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

  function captureFocusContext() {
    const workspace = Hyprland.focusedWorkspace
    const monitor = Hyprland.focusedMonitor
    if (!workspace || !monitor || Number(workspace.id) <= 0)
      return false

    root.snapshotWorkspaceId = Number(workspace.id)
    root.snapshotMonitorName = String(monitor.name || "")
    root.snapshotMonitorId = Number(monitor.id)
    root.targetScreen = root.focusedScreen()
    return true
  }

  function snapshotCurrentWindows(clients) {
    if (!Array.isArray(clients))
      return []

    const rows = []
    const toplevels = Hyprland.toplevels.values || []
    const toplevelByAddress = ({})
    for (const toplevel of toplevels) {
      const address = Logic.safeAddress(toplevel.address)
      if (address)
        toplevelByAddress[address] = toplevel
    }

    for (const ipc of clients) {
      const address = Logic.safeAddress(ipc.address)
      if (!address || ipc.mapped === false)
        continue
      const toplevel = toplevelByAddress[address] || null
      const workspaceId = Number(ipc.workspace ? ipc.workspace.id : -1)
      const monitorName = toplevel && toplevel.monitor ? String(toplevel.monitor.name || "") : ""
      const monitorId = Number(ipc.monitor)

      if (!Logic.isEligibleWindow(ipc, workspaceId, monitorName, monitorId, root.snapshotWorkspaceId, root.snapshotMonitorName, root.snapshotMonitorId)) {
        continue
      }

      const wayland = toplevel ? toplevel.wayland || null : null
      const appId = String(wayland ? wayland.appId || "" : "")
      const initialClass = String(ipc.initialClass || "")
      const applicationClass = String(ipc.class || initialClass || appId || "Application")
      const title = String(ipc.title || (toplevel ? toplevel.title || "" : "") || applicationClass)
      const application = root.applicationInfo(applicationClass, initialClass, appId)
      const size = Array.isArray(ipc.size) ? ipc.size : []
      rows.push({
        address: address,
        appKey: application.id,
        applicationClass: applicationClass,
        appName: application.name,
        iconSource: application.icon,
        fallbackText: application.fallbackText,
        title: title,
        focusHistoryId: Logic.focusHistoryId(ipc.focusHistoryID),
        groupIndex: Logic.groupIndex(ipc.grouped, address),
        pinned: ipc.pinned === true,
        xwayland: ipc.xwayland === true,
        previewWidth: Number(size[0]) || 16,
        previewHeight: Number(size[1]) || 9,
        toplevel: toplevel,
        wayland: wayland
      })
    }

    return Logic.decorateDuplicateLabels(Logic.sortByRecency(rows))
  }

  function completeWindowQuery(text) {
    if (!root.snapshotPending)
      return
    root.snapshotPending = false
    if (root.snapshotCancelled)
      return
    let clients = []
    try {
      clients = JSON.parse(text)
    } catch (error) {
      console.warn("window-switcher: unable to read current window order:", error)
      return
    }

    const nextWindows = root.snapshotCurrentWindows(clients)
    root.windows = nextWindows
    const nextEntries = root.mode === "icons" ? Logic.applicationEntries(nextWindows) : nextWindows
    if (nextEntries.length < 2)
      return
    const initialIndex = Logic.initialSelection(nextEntries, root.pendingDirection)
    root.selectedIndex = Logic.wrapIndex(initialIndex + root.queuedSteps, nextEntries.length)
    root.releaseToActivate = root.pendingActivateOnRelease
    root.releaseModifier = root.pendingActivateOnRelease ? root.pendingModifier : ""
    root.sawKeyEvent = false
    root.hoverArmed = false
    root.initialPointerPosition = Qt.point(-1, -1)
    root.opened = true
    watchdog.restart()
  }

  function startSwitcher(activateOnRelease, modifier, direction) {
    root.mode = root.configuredMode()
    if (!root.captureFocusContext())
      return
    root.snapshotPending = true
    root.snapshotCancelled = false
    root.pendingActivateOnRelease = activateOnRelease
    root.pendingModifier = String(modifier || "")
    root.pendingDirection = direction
    root.queuedSteps = 0
    windowQuery.running = true
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
    const action = String(payload.action || "show")
    root.startSwitcher(action === "next" || action === "previous", String(payload.modifier || ""), action === "previous" ? -1 : 1)
  }

  function close() {
    root.cancel()
  }

  function setMode(value) {
    const selected = root.entries[root.selectedIndex]
    const selectedAddress = selected ? selected.address : ""
    const nextMode = Logic.normalizeMode(value)
    root.mode = nextMode
    const nextEntries = root.mode === "icons" ? Logic.applicationEntries(root.windows) : root.windows
    const matchingIndex = Logic.entryIndexForAddress(nextEntries, selectedAddress)
    root.selectedIndex = matchingIndex >= 0 ? matchingIndex : Math.min(root.selectedIndex, Math.max(0, nextEntries.length - 1))
    if (root.shell && typeof root.shell.updateEntryInline === "function") {
      root.shell.updateEntryInline(root.pluginId, {
        id: root.pluginId,
        mode: nextMode
      })
    }
    return root.mode
  }

  function configuredMode() {
    const config = root.shell ? root.shell.shellConfig : null
    return Logic.modeFromPluginEntries(config ? config.plugins : null, root.pluginId)
  }

  onShellChanged: {
    if (root.shell && !root.opened)
      root.mode = root.configuredMode()
  }

  function cycle(step) {
    root.selectedIndex = Logic.wrapIndex(root.selectedIndex + step, root.entries.length)
    watchdog.restart()
  }

  function invokeShortcut(step) {
    if (root.opened)
      root.cycle(step)
    else if (root.snapshotPending)
      root.queuedSteps += step
    else
      root.startSwitcher(true, "alt", step)
  }

  function releaseModifierExpression() {
    if (root.releaseModifier === "alt")
      return 'error(tostring(hl.is_key_down("Alt_L") or hl.is_key_down("Alt_R")))'
    if (root.releaseModifier === "super")
      return 'error(tostring(hl.is_key_down("Super_L") or hl.is_key_down("Super_R")))'
    return "error(false)"
  }

  function select(index) {
    if (index < 0 || index >= root.entries.length)
      return
    root.selectedIndex = index
    watchdog.restart()
  }

  function navigate(direction) {
    if (root.mode !== "grid") {
      root.cycle(direction === "left" || direction === "up" ? -1 : 1)
      return
    }
    if (viewLoader.item && typeof viewLoader.item.navigationTarget === "function")
      root.select(viewLoader.item.navigationTarget(root.selectedIndex, direction))
  }

  function finish(activate) {
    if (!root.opened)
      return
    const selected = activate && root.selectedIndex >= 0 ? root.entries[root.selectedIndex] : null
    watchdog.stop()
    root.releaseToActivate = false
    root.releaseModifier = ""
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
    if (root.snapshotPending) {
      root.snapshotCancelled = true
      root.snapshotPending = false
    }
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
    const selected = root.entries[root.selectedIndex]
    const selectedAddress = selected ? selected.address : ""
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
    root.windows = Logic.decorateDuplicateLabels(remaining)
    const remainingEntries = root.mode === "icons" ? Logic.applicationEntries(root.windows) : root.windows
    if (remainingEntries.length < 2) {
      root.cancel()
      return
    }
    const matchingIndex = Logic.entryIndexForAddress(remainingEntries, selectedAddress)
    root.selectedIndex = matchingIndex >= 0 ? matchingIndex : Math.min(root.selectedIndex, remainingEntries.length - 1)
  }

  Process {
    id: windowQuery
    command: ["hyprctl", "-j", "clients"]
    stdout: StdioCollector {
      onStreamFinished: root.completeWindowQuery(text)
    }
  }

  GlobalShortcut {
    appid: "omarchy-window-switcher"
    name: "next"
    description: "Cycle forward through current-workspace windows"

    onPressed: root.invokeShortcut(1)
  }

  GlobalShortcut {
    appid: "omarchy-window-switcher"
    name: "previous"
    description: "Cycle backward through current-workspace windows"

    onPressed: root.invokeShortcut(-1)
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
        command: ["hyprctl", "eval", root.releaseModifierExpression()]
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
        height: Math.min(panel.height - Style.gapsOut * 2, viewLoader.height + Style.space(144))
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
          const altReleased = event.key === Qt.Key_Alt
          const modifierReleased = root.releaseModifier === "alt" ? altReleased : root.releaseModifier === "super" && superReleased
          if (root.releaseToActivate && modifierReleased)
            root.accept()
          event.accepted = true
        }

        Text {
          id: heading
          anchors.top: parent.top
          anchors.topMargin: Style.space(18)
          anchors.horizontalCenter: parent.horizontalCenter
          text: "Orbit · " + (root.mode === "grid" ? "Grid" : root.mode === "flip" ? "Flip" : "Icons")
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
            windows: root.entries
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
            windows: root.entries
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
            windows: root.entries
            selectedIndex: root.selectedIndex
            hoverArmed: root.hoverArmed
            onSelectRequested: index => root.select(index)
            onActivateRequested: index => {
              root.select(index)
              root.accept()
            }
          }
        }

        ModePicker {
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(39)
          anchors.horizontalCenter: parent.horizontalCenter
          currentMode: root.mode
          onModeRequested: mode => root.setMode(mode)
        }

        Text {
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(16)
          anchors.horizontalCenter: parent.horizontalCenter
          width: Math.min(parent.width - Style.space(48), Style.space(620))
          text: root.entries.length > 0 ? root.entries[root.selectedIndex].title : ""
          textFormat: Text.PlainText
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

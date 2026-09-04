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
  property string windowScope: "visible"
  readonly property var entries: root.mode === "icons" ? Logic.applicationEntries(root.windows) : root.windows
  property int snapshotWorkspaceId: -1
  property string snapshotMonitorName: ""
  property int snapshotMonitorId: -1
  property var snapshotVisibleWorkspaceIds: []
  property var snapshotVisibleMonitorNames: []
  property var snapshotVisibleMonitorIds: []
  property var targetScreen: null
  property var pendingWindow: null
  property var pendingFullscreenRelease: null
  property var pendingFullscreenRestore: null
  property var rememberedFullscreenStates: ({})
  property var handoffAnimationAddresses: []
  property bool handoffRestoresTargetFirst: false
  property bool handoffNeedsCover: false
  property bool activationCommitInProgress: false
  property bool activationCommitSettling: false
  property bool activationCommitFinalizing: false
  property bool activationTargetSurfaceReady: false
  property int activationCommitAttempts: 0
  readonly property int activationCommitAttemptLimit: 50
  property bool snapshotPending: false
  property bool snapshotCancelled: false
  property bool pendingActivateOnRelease: false
  property string pendingModifier: ""
  property int pendingDirection: 1
  property int queuedSteps: 0
  property string managerMode: ""
  property var windowModes: Logic.defaultWindowModes()
  property var settingsDraft: Logic.defaultWindowModes()
  property var snapLayouts: Logic.snapLayouts()
  property int snapSelectedLayout: 0
  property int snapSelectedSlot: 0
  property var snapTargetWindow: null
  property var snapTargetMonitor: null
  property var snapClientRows: []
  property var snapAssistCandidates: []
  property var snapRemainingSlots: []
  property int snapAssistSelected: 0
  property bool snapActiveReady: false
  property bool snapMonitorReady: false
  property bool snapClientsReady: false
  property var snapRestoreStates: ({})
  property var snapGroups: []
  property var pendingSnapGroup: null
  property var snapAnimationAddresses: []
  property string snapPendingFocusAddress: ""

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

  function screenForMonitorName(monitorName) {
    const screens = Quickshell.screens || []
    for (const screen of screens) {
      if (String(screen.name || "") === String(monitorName || ""))
        return screen
    }
    return null
  }

  function focusedScreen() {
    const screens = Quickshell.screens || []
    const focused = root.screenForMonitorName(root.snapshotMonitorName)
    if (focused)
      return focused
    return screens.length > 0 ? screens[0] : null
  }

  function switcherScreen() {
    const config = root.shell ? root.shell.shellConfig : null
    const monitors = []
    for (const monitor of Hyprland.monitors.values || [])
      monitors.push(monitor)
    const monitorName = Logic.overlayMonitorName(config ? config.plugins : null, root.pluginId, monitors, root.snapshotMonitorName)
    return root.screenForMonitorName(monitorName) || root.focusedScreen()
  }

  function captureFocusContext() {
    const workspace = Hyprland.focusedWorkspace
    const monitor = Hyprland.focusedMonitor
    if (!workspace || !monitor || Number(workspace.id) <= 0)
      return false

    root.snapshotWorkspaceId = Number(workspace.id)
    root.snapshotMonitorName = String(monitor.name || "")
    root.snapshotMonitorId = Number(monitor.id)
    const visibleWorkspaceIds = []
    const visibleMonitorNames = []
    const visibleMonitorIds = []
    const monitors = Hyprland.monitors.values || []
    for (const candidateMonitor of monitors) {
      if (root.windowScope === "monitor" && Number(candidateMonitor.id) !== root.snapshotMonitorId)
        continue
      const monitorName = String(candidateMonitor.name || "")
      const monitorId = Number(candidateMonitor.id)
      const activeWorkspace = candidateMonitor.activeWorkspace
      if (monitorName && !visibleMonitorNames.includes(monitorName))
        visibleMonitorNames.push(monitorName)
      if (Number.isFinite(monitorId) && !visibleMonitorIds.includes(monitorId))
        visibleMonitorIds.push(monitorId)
      if (activeWorkspace && Number(activeWorkspace.id) !== 0 && !visibleWorkspaceIds.includes(Number(activeWorkspace.id)))
        visibleWorkspaceIds.push(Number(activeWorkspace.id))
    }
    root.snapshotVisibleWorkspaceIds = visibleWorkspaceIds
    root.snapshotVisibleMonitorNames = visibleMonitorNames
    root.snapshotVisibleMonitorIds = visibleMonitorIds
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

      if (!Logic.isEligibleWindow(ipc, workspaceId, monitorName, monitorId, root.windowScope, root.snapshotVisibleWorkspaceIds, root.snapshotVisibleMonitorNames, root.snapshotVisibleMonitorIds, root.snapshotWorkspaceId, root.snapshotMonitorName, root.snapshotMonitorId)) {
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
        workspaceId: workspaceId,
        monitorName: monitorName,
        monitorId: monitorId,
        appKey: application.id,
        applicationClass: applicationClass,
        appName: application.name,
        iconSource: application.icon,
        fallbackText: application.fallbackText,
        title: title,
        focusHistoryId: Logic.focusHistoryId(ipc.focusHistoryID),
        fullscreenState: Logic.fullscreenState(ipc.fullscreen),
        clientFullscreenState: Logic.fullscreenState(ipc.fullscreenClient),
        groupIndex: Logic.groupIndex(ipc.grouped, address),
        pinned: ipc.pinned === true,
        xwayland: ipc.xwayland === true,
        previewWidth: Number(size[0]) || 16,
        previewHeight: Number(size[1]) || 9,
        positionX: Array.isArray(ipc.at) ? Number(ipc.at[0]) || 0 : 0,
        positionY: Array.isArray(ipc.at) ? Number(ipc.at[1]) || 0 : 0,
        floating: ipc.floating === true,
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
    root.windowScope = root.configuredScope()
    if (!root.captureFocusContext())
      return
    root.targetScreen = root.switcherScreen()
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
    root.persistPluginSettings({
      mode: nextMode
    })
    return root.mode
  }

  function currentPluginSettings() {
    const config = root.shell ? root.shell.shellConfig : null
    const plugins = config && Array.isArray(config.plugins) ? config.plugins : []
    for (const plugin of plugins) {
      if (plugin && String(plugin.id || "") === root.pluginId)
        return JSON.parse(JSON.stringify(plugin))
    }
    return {
      id: root.pluginId
    }
  }

  function persistPluginSettings(changes) {
    if (!root.shell || typeof root.shell.updateEntryInline !== "function")
      return
    const next = root.currentPluginSettings()
    for (const key in changes)
      next[key] = changes[key]
    next.id = root.pluginId
    root.shell.updateEntryInline(root.pluginId, next)
  }

  function configuredMode() {
    const config = root.shell ? root.shell.shellConfig : null
    return Logic.modeFromPluginEntries(config ? config.plugins : null, root.pluginId)
  }

  function configuredScope() {
    const config = root.shell ? root.shell.shellConfig : null
    return Logic.scopeFromPluginEntries(config ? config.plugins : null, root.pluginId)
  }

  function configuredWindowModes() {
    const config = root.shell ? root.shell.shellConfig : null
    return Logic.windowModesFromPluginEntries(config ? config.plugins : null, root.pluginId)
  }

  onShellChanged: {
    if (root.shell && !root.opened) {
      root.mode = root.configuredMode()
      root.windowScope = root.configuredScope()
      root.windowModes = root.configuredWindowModes()
    }
  }

  function openSettings() {
    if (root.managerMode !== "") {
      root.closeManager()
      return
    }
    root.cancel()
    root.windowScope = root.configuredScope()
    if (!root.captureFocusContext())
      return
    root.windowModes = root.configuredWindowModes()
    root.settingsDraft = Logic.normalizedWindowModes(root.windowModes)
    root.managerMode = "settings"
  }

  function toggleSettingsMode(mode) {
    root.settingsDraft = Logic.toggleWindowMode(root.settingsDraft, mode)
  }

  function setSettingsDefault(mode) {
    const next = Logic.normalizedWindowModes(root.settingsDraft)
    if (next[mode] !== true)
      return
    next.defaultMode = mode
    root.settingsDraft = Logic.normalizedWindowModes(next)
  }

  function applyWindowModeSettings() {
    root.windowModes = Logic.normalizedWindowModes(root.settingsDraft)
    root.persistPluginSettings({
      windowModes: root.windowModes
    })
    root.managerMode = ""
    settingsReload.running = true
  }

  function closeManager() {
    root.managerMode = ""
    root.snapTargetWindow = null
    root.snapTargetMonitor = null
    root.snapClientRows = []
    root.snapAssistCandidates = []
    root.snapRemainingSlots = []
    root.pendingSnapGroup = null
  }

  function openSnapManager() {
    if (root.managerMode !== "") {
      root.closeManager()
      return
    }
    root.cancel()
    root.windowScope = root.configuredScope()
    if (!root.captureFocusContext())
      return
    root.snapSelectedLayout = 0
    root.snapSelectedSlot = 0
    root.snapTargetWindow = null
    root.snapTargetMonitor = null
    root.snapClientRows = []
    root.snapAssistCandidates = []
    root.snapRemainingSlots = []
    root.snapActiveReady = false
    root.snapMonitorReady = false
    root.snapClientsReady = false
    snapActiveQuery.running = true
    snapMonitorQuery.running = true
    snapClientsQuery.running = true
  }

  function completeSnapActive(text) {
    try {
      const active = JSON.parse(text)
      const address = Logic.safeAddress(active.address)
      if (address) {
        root.snapTargetWindow = {
          address: address,
          workspaceId: Number(active.workspace ? active.workspace.id : -1),
          monitorId: Number(active.monitor),
          positionX: Array.isArray(active.at) ? Number(active.at[0]) || 0 : 0,
          positionY: Array.isArray(active.at) ? Number(active.at[1]) || 0 : 0,
          previewWidth: Array.isArray(active.size) ? Number(active.size[0]) || 1 : 1,
          previewHeight: Array.isArray(active.size) ? Number(active.size[1]) || 1 : 1,
          fullscreenState: Logic.fullscreenState(active.fullscreen),
          clientFullscreenState: Logic.fullscreenState(active.fullscreenClient),
          floating: active.floating === true
        }
      }
    } catch (error) {
      console.warn("window-switcher: unable to read active window for snap:", error)
    }
    root.snapActiveReady = true
    root.maybeOpenSnapManager()
  }

  function completeSnapMonitors(text) {
    try {
      const monitors = JSON.parse(text)
      const monitorId = root.snapTargetWindow ? root.snapTargetWindow.monitorId : root.snapshotMonitorId
      for (const monitor of monitors) {
        if (Number(monitor.id) === Number(monitorId)) {
          root.snapTargetMonitor = monitor
          root.snapshotMonitorName = String(monitor.name || root.snapshotMonitorName)
          root.targetScreen = root.focusedScreen()
          break
        }
      }
    } catch (error) {
      console.warn("window-switcher: unable to read monitors for snap:", error)
    }
    root.snapMonitorReady = true
    root.maybeOpenSnapManager()
  }

  function completeSnapClients(text) {
    try {
      root.snapClientRows = root.snapshotCurrentWindows(JSON.parse(text))
    } catch (error) {
      console.warn("window-switcher: unable to read clients for snap:", error)
      root.snapClientRows = []
    }
    root.snapClientsReady = true
    root.maybeOpenSnapManager()
  }

  function maybeOpenSnapManager() {
    if (!root.snapActiveReady || !root.snapMonitorReady || !root.snapClientsReady)
      return
    if (!root.snapTargetWindow || !root.snapTargetMonitor) {
      console.warn("window-switcher: snap layouts need an active window and monitor")
      return
    }
    root.managerMode = "snap"
  }

  function snapGeometry(layoutIndex, slotIndex) {
    const layout = root.snapLayouts[layoutIndex]
    if (!layout || !layout.slots[slotIndex])
      return null
    const compositorGap = Style.gapsOut * 2
    return Logic.snapGeometry(layout.slots[slotIndex], root.snapTargetMonitor, compositorGap, compositorGap)
  }

  function rememberSnapState(window) {
    if (!window || !window.address || root.snapRestoreStates[window.address])
      return
    const saved = Object.assign({}, root.snapRestoreStates)
    saved[window.address] = {
      x: window.positionX,
      y: window.positionY,
      width: window.previewWidth,
      height: window.previewHeight,
      floating: window.floating,
      fullscreen: window.fullscreenState,
      clientFullscreen: window.clientFullscreenState
    }
    root.snapRestoreStates = saved
  }

  function snapWindow(window, layoutIndex, slotIndex) {
    const geometry = root.snapGeometry(layoutIndex, slotIndex)
    const address = window ? Logic.safeAddress(window.address) : ""
    if (!geometry || !address)
      return false
    root.rememberSnapState(window)
    Hyprland.dispatch('hl.dsp.window.set_prop({ prop = "no_anim", value = "true", window = "address:' + address + '" })')
    Hyprland.dispatch('hl.dsp.window.fullscreen_state({ internal = 0, client = 0, action = "set", window = "address:' + address + '" })')
    Hyprland.dispatch('hl.dsp.window.float({ action = "set", window = "address:' + address + '" })')
    Hyprland.dispatch('hl.dsp.window.move({ x = ' + geometry.x + ', y = ' + geometry.y + ', relative = false, window = "address:' + address + '" })')
    Hyprland.dispatch('hl.dsp.window.resize({ x = ' + geometry.width + ', y = ' + geometry.height + ', relative = false, window = "address:' + address + '" })')
    const animationAddresses = root.snapAnimationAddresses.slice()
    if (!animationAddresses.includes(address))
      animationAddresses.push(address)
    root.snapAnimationAddresses = animationAddresses
    snapAnimationRelease.restart()
    root.snapPendingFocusAddress = address
    return true
  }

  function chooseSnapSlot(layoutIndex, slotIndex) {
    if (!root.snapWindow(root.snapTargetWindow, layoutIndex, slotIndex))
      return
    const layout = root.snapLayouts[layoutIndex]
    const remaining = []
    for (let index = 0; index < layout.slots.length; index++) {
      if (index !== slotIndex)
        remaining.push(index)
    }
    root.snapRemainingSlots = remaining
    root.pendingSnapGroup = {
      layoutId: String(layout.id || "layout"),
      workspaceId: root.snapTargetWindow.workspaceId,
      monitorId: root.snapTargetWindow.monitorId,
      addresses: [root.snapTargetWindow.address]
    }
    root.snapAssistCandidates = root.snapClientRows.filter(window => window.address !== root.snapTargetWindow.address && window.workspaceId === root.snapTargetWindow.workspaceId)
    root.snapAssistSelected = 0
    if (remaining.length > 0 && root.snapAssistCandidates.length > 0)
      root.managerMode = "assist"
    else {
      root.managerMode = ""
      snapFocusTimer.restart()
    }
  }

  function chooseSnapAssist(index) {
    if (index < 0 || index >= root.snapAssistCandidates.length || root.snapRemainingSlots.length === 0)
      return
    const candidate = root.snapAssistCandidates[index]
    const slotIndex = root.snapRemainingSlots[0]
    if (!root.snapWindow(candidate, root.snapSelectedLayout, slotIndex))
      return
    const pendingGroup = root.pendingSnapGroup ? Object.assign({}, root.pendingSnapGroup) : null
    if (pendingGroup) {
      pendingGroup.addresses = pendingGroup.addresses.slice()
      pendingGroup.addresses.push(candidate.address)
      root.pendingSnapGroup = pendingGroup
      root.rememberSnapGroup(pendingGroup)
    }
    root.snapRemainingSlots = root.snapRemainingSlots.slice(1)
    root.snapAssistCandidates = root.snapAssistCandidates.filter(window => window.address !== candidate.address)
    root.snapAssistSelected = Math.min(root.snapAssistSelected, Math.max(0, root.snapAssistCandidates.length - 1))
    if (root.snapRemainingSlots.length === 0 || root.snapAssistCandidates.length === 0) {
      root.managerMode = ""
      snapFocusTimer.restart()
    }
  }

  function cycleSnapSlot(step) {
    const layout = root.snapLayouts[root.snapSelectedLayout]
    root.snapSelectedSlot = Logic.wrapIndex(root.snapSelectedSlot + step, layout.slots.length)
  }

  function cycleSnapLayout(step) {
    root.snapSelectedLayout = Logic.wrapIndex(root.snapSelectedLayout + step, root.snapLayouts.length)
    const layout = root.snapLayouts[root.snapSelectedLayout]
    root.snapSelectedSlot = Math.min(root.snapSelectedSlot, layout.slots.length - 1)
  }

  function rememberSnapGroup(group) {
    if (!group || !Array.isArray(group.addresses) || group.addresses.length < 2)
      return
    const addresses = group.addresses.filter(address => Logic.safeAddress(address) !== "")
    if (addresses.length < 2)
      return
    const next = root.snapGroups.filter(existing => !existing.addresses.some(address => addresses.includes(address)))
    next.push({
      layoutId: group.layoutId,
      workspaceId: group.workspaceId,
      monitorId: group.monitorId,
      addresses: addresses
    })
    root.snapGroups = next
  }

  function raiseSnapGroup(address) {
    const safeAddress = Logic.safeAddress(address)
    if (!safeAddress)
      return
    for (const group of root.snapGroups) {
      if (!group.addresses.includes(safeAddress))
        continue
      for (const memberAddress of group.addresses) {
        if (memberAddress === safeAddress)
          continue
        Hyprland.dispatch('hl.dsp.window.alter_zorder({ top = true, window = "address:' + memberAddress + '" })')
      }
      Hyprland.dispatch('hl.dsp.window.alter_zorder({ top = true, window = "address:' + safeAddress + '" })')
      return
    }
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

  function fullscreenSnapshot(window) {
    if (!window)
      return null
    const internalState = Logic.fullscreenState(window.fullscreenState)
    const clientState = Logic.fullscreenState(window.clientFullscreenState)
    if (internalState === 0 && clientState === 0)
      return null
    return {
      address: Logic.safeAddress(window.address),
      internal: internalState,
      client: clientState
    }
  }

  function rememberSourceFullscreen(source) {
    if (!source)
      return
    const address = Logic.safeAddress(source.address)
    if (!address)
      return
    const remembered = Object.assign({}, root.rememberedFullscreenStates)
    const snapshot = root.fullscreenSnapshot(source)
    if (snapshot)
      remembered[address] = snapshot
    else
      delete remembered[address]
    root.rememberedFullscreenStates = remembered
  }

  function prepareFullscreenHandoff(source, selected) {
    root.pendingFullscreenRelease = null
    root.pendingFullscreenRestore = null
    root.handoffRestoresTargetFirst = false
    root.handoffNeedsCover = false
    if (!source || !selected)
      return
    const sourceAddress = Logic.safeAddress(source.address)
    const selectedAddress = Logic.safeAddress(selected.address)
    if (!sourceAddress || !selectedAddress || sourceAddress === selectedAddress)
      return
    root.rememberSourceFullscreen(source)
    if (!Logic.sameWorkspace(source, selected))
      return
    const selectedSnapshot = root.rememberedFullscreenStates[selectedAddress] || root.fullscreenSnapshot(selected)
    const desiredInternalState = selectedSnapshot ? Logic.resumableFullscreenState(selectedSnapshot.internal, selectedSnapshot.client) : 0
    if (selectedSnapshot) {
      root.pendingFullscreenRestore = {
        address: selectedAddress,
        internal: desiredInternalState
      }
    }

    const handoff = Logic.fullscreenHandoffPlan(source.fullscreenState, selected.fullscreenState, desiredInternalState)
    root.handoffRestoresTargetFirst = handoff.restoreTargetBeforeFocus
    const targetAlreadyMatchesSourceSize = handoff.restoreTargetBeforeFocus && !Logic.dimensionsDiffer(source.previewWidth, source.previewHeight, selected.previewWidth, selected.previewHeight, 2)
    root.handoffNeedsCover = handoff.targetResizes && !targetAlreadyMatchesSourceSize
    const suppressAnimations = handoff.releaseSource || handoff.targetResizes
    if (suppressAnimations)
      root.suppressHandoffAnimations([sourceAddress, selectedAddress])

    if (handoff.releaseSource) {
      root.pendingFullscreenRelease = {
        address: sourceAddress
      }
    }
  }

  function suppressHandoffAnimations(addresses) {
    const uniqueAddresses = []
    for (const value of addresses) {
      const address = Logic.safeAddress(value)
      if (!address || uniqueAddresses.includes(address))
        continue
      uniqueAddresses.push(address)
      Hyprland.dispatch('hl.dsp.window.set_prop({ prop = "no_anim", value = "true", window = "address:' + address + '" })')
    }
    root.handoffAnimationAddresses = uniqueAddresses
  }

  function releaseHandoffAnimations() {
    for (const address of root.handoffAnimationAddresses) {
      Hyprland.dispatch('hl.dsp.window.set_prop({ prop = "no_anim", value = "unset", window = "address:' + address + '" })')
    }
    root.handoffAnimationAddresses = []
  }

  function restoreSelectedFullscreen() {
    const restore = root.pendingFullscreenRestore
    if (!restore || restore.internal <= 0)
      return
    Hyprland.dispatch('hl.dsp.window.fullscreen_state({ internal = ' + restore.internal + ', client = -1, action = "set", window = "address:' + restore.address + '" })')
  }

  function requestPendingActivation() {
    const selected = root.pendingWindow
    if (!selected)
      return
    if (root.handoffRestoresTargetFirst)
      root.restoreSelectedFullscreen()
    const release = root.pendingFullscreenRelease
    if (release) {
      Hyprland.dispatch('hl.dsp.window.fullscreen_state({ internal = 0, client = -1, action = "set", window = "address:' + release.address + '" })')
    }
    root.raisePendingWindow()
    if (!root.handoffRestoresTargetFirst)
      root.restoreSelectedFullscreen()
  }

  function raisePendingWindow() {
    const selected = root.pendingWindow
    if (!selected)
      return
    root.raiseSnapGroup(selected.address)
    if (selected.groupIndex > 0) {
      Hyprland.dispatch('hl.dsp.group.active({ window = "address:' + selected.address + '", index = ' + selected.groupIndex + ' })')
    }
    if (selected.wayland)
      selected.wayland.activate()
    Hyprland.dispatch('hl.dsp.focus({ window = "address:' + selected.address + '" })')
    Hyprland.dispatch('hl.dsp.window.bring_to_top()')
  }

  function abortActivationCommit() {
    activationCommitTimer.stop()
    activationSettleTimer.stop()
    activationRevealTimer.stop()
    activationFinalizeTimer.stop()
    root.releaseHandoffAnimations()
    console.warn("window-switcher: selected window did not accept focus; keeping Orbit open")
    root.pendingWindow = null
    root.pendingFullscreenRelease = null
    root.pendingFullscreenRestore = null
    root.handoffRestoresTargetFirst = false
    root.handoffNeedsCover = false
    root.activationCommitInProgress = false
    root.activationCommitSettling = false
    root.activationCommitFinalizing = false
    root.activationTargetSurfaceReady = false
    root.activationCommitAttempts = 0
    root.releaseToActivate = false
    root.releaseModifier = ""
    watchdog.restart()
  }

  function finishActivationCommit() {
    if (root.activationCommitFinalizing)
      return
    activationCommitTimer.stop()
    activationSettleTimer.stop()
    activationRevealTimer.stop()
    root.activationCommitFinalizing = true
    root.opened = false
    activationFinalizeTimer.restart()
  }

  function finalizeActivationCommit() {
    activationFinalizeTimer.stop()
    root.releaseHandoffAnimations()
    root.raisePendingWindow()
    root.pendingWindow = null
    root.pendingFullscreenRelease = null
    root.pendingFullscreenRestore = null
    root.handoffRestoresTargetFirst = false
    root.handoffNeedsCover = false
    root.activationCommitInProgress = false
    root.activationCommitSettling = false
    root.activationCommitFinalizing = false
    root.activationTargetSurfaceReady = false
    root.activationCommitAttempts = 0
  }

  function advanceActivationCommit() {
    if (!root.activationCommitInProgress)
      return
    const selected = root.pendingWindow
    if (!selected) {
      root.finishActivationCommit()
      return
    }

    root.activationCommitAttempts++
    if (root.activationCommitAttempts === 1) {
      root.requestPendingActivation()
      return
    }

    const active = Hyprland.activeToplevel
    const selectedIsActive = active && Logic.safeAddress(active.address) === Logic.safeAddress(selected.address)
    if (!selectedIsActive) {
      root.requestPendingActivation()
      if (root.activationCommitAttempts < root.activationCommitAttemptLimit)
        return
      root.abortActivationCommit()
      return
    }

    if (root.handoffNeedsCover && !root.activationCommitSettling) {
      activationCommitTimer.stop()
      root.activationCommitSettling = true
      if (root.activationTargetSurfaceReady)
        activationRevealTimer.restart()
      else
        activationSettleTimer.restart()
      return
    }

    root.finishActivationCommit()
  }

  function observeActivationTargetSurface(width, height) {
    if (!root.activationCommitInProgress || !root.handoffNeedsCover || !root.pendingWindow)
      return
    if (root.activationTargetSurfaceReady)
      return
    if (!Logic.dimensionsDiffer(width, height, root.pendingWindow.previewWidth, root.pendingWindow.previewHeight, 2))
      return
    root.activationTargetSurfaceReady = true
    if (root.activationCommitSettling) {
      activationSettleTimer.stop()
      activationRevealTimer.restart()
    }
  }

  function finish(activate) {
    if (!root.opened || root.activationCommitInProgress)
      return
    const selected = activate && root.selectedIndex >= 0 ? root.entries[root.selectedIndex] : null
    watchdog.stop()
    root.releaseToActivate = false
    root.releaseModifier = ""
    if (!selected) {
      root.opened = false
      return
    }
    root.prepareFullscreenHandoff(root.windows.length > 0 ? root.windows[0] : null, selected)
    root.pendingWindow = selected
    root.activationCommitInProgress = true
    root.activationCommitSettling = false
    root.activationCommitFinalizing = false
    root.activationTargetSurfaceReady = false
    root.activationCommitAttempts = 0
    activationCommitTimer.restart()
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
    const nextGroups = []
    for (const group of root.snapGroups) {
      const addresses = group.addresses.filter(address => liveAddresses[address] === true)
      if (addresses.length > 1)
        nextGroups.push(Object.assign({}, group, {
          addresses: addresses
        }))
    }
    root.snapGroups = nextGroups
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

  Process {
    id: snapActiveQuery
    command: ["hyprctl", "-j", "activewindow"]
    stdout: StdioCollector {
      onStreamFinished: root.completeSnapActive(text)
    }
  }

  Process {
    id: snapMonitorQuery
    command: ["hyprctl", "-j", "monitors"]
    stdout: StdioCollector {
      onStreamFinished: root.completeSnapMonitors(text)
    }
  }

  Process {
    id: snapClientsQuery
    command: ["hyprctl", "-j", "clients"]
    stdout: StdioCollector {
      onStreamFinished: root.completeSnapClients(text)
    }
  }

  Process {
    id: settingsReload
    command: ["hyprctl", "reload"]
  }

  GlobalShortcut {
    appid: "omarchy-window-switcher"
    name: "next"
    description: "Cycle forward through windows on visible monitors"

    onPressed: root.invokeShortcut(1)
  }

  GlobalShortcut {
    appid: "omarchy-window-switcher"
    name: "previous"
    description: "Cycle backward through windows on visible monitors"

    onPressed: root.invokeShortcut(-1)
  }

  GlobalShortcut {
    appid: "omarchy-window-switcher"
    name: "snap"
    description: "Choose a Windows-style snap layout for the active window"

    onPressed: root.openSnapManager()
  }

  GlobalShortcut {
    appid: "omarchy-window-switcher"
    name: "settings"
    description: "Configure Orbit window modes"

    onPressed: root.openSettings()
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
    id: activationCommitTimer
    interval: 40
    repeat: true
    onTriggered: root.advanceActivationCommit()
  }

  Timer {
    id: activationSettleTimer
    interval: 1600
    onTriggered: root.finishActivationCommit()
  }

  Timer {
    id: activationRevealTimer
    interval: 80
    onTriggered: root.finishActivationCommit()
  }

  Timer {
    id: activationFinalizeTimer
    interval: 32
    onTriggered: root.finalizeActivationCommit()
  }

  Timer {
    id: snapAnimationRelease
    interval: 120
    onTriggered: {
      for (const address of root.snapAnimationAddresses)
        Hyprland.dispatch('hl.dsp.window.set_prop({ prop = "no_anim", value = "unset", window = "address:' + address + '" })')
      root.snapAnimationAddresses = []
    }
  }

  Timer {
    id: snapFocusTimer
    interval: 32
    onTriggered: {
      const address = Logic.safeAddress(root.snapPendingFocusAddress)
      root.snapPendingFocusAddress = ""
      if (!address)
        return
      Hyprland.dispatch('hl.dsp.focus({ window = "address:' + address + '" })')
      Hyprland.dispatch("hl.dsp.window.bring_to_top()")
    }
  }

  LazyLoader {
    active: root.managerMode !== ""

    PanelWindow {
      id: managerPanel

      screen: root.targetScreen
      anchors {
        top: true
        bottom: true
        left: true
        right: true
      }
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "omarchy-orbit-window-manager"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

      Rectangle {
        anchors.fill: parent
        color: Color.menu.scrim

        TapHandler {
          onTapped: root.closeManager()
        }
      }

      Rectangle {
        id: managerCard

        anchors.centerIn: parent
        width: root.managerMode === "settings" ? Style.space(560) : Math.min(managerPanel.width - Style.gapsOut * 2, Style.space(560))
        height: root.managerMode === "settings" ? Style.space(430) : root.managerMode === "assist" ? Math.min(managerPanel.height - Style.gapsOut * 2, Style.space(570)) : Style.space(330)
        radius: Style.cornerRadius * 2
        color: Color.menu.background
        border.width: 1
        border.color: Color.menu.border
        focus: true

        Keys.onPressed: event => {
          if (event.key === Qt.Key_Escape) {
            root.closeManager()
          } else if (root.managerMode === "snap") {
            if (event.key === Qt.Key_Left || event.key === Qt.Key_Backtab)
              root.cycleSnapSlot(-1)
            else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab)
              root.cycleSnapSlot(1)
            else if (event.key === Qt.Key_Up)
              root.cycleSnapLayout(-1)
            else if (event.key === Qt.Key_Down)
              root.cycleSnapLayout(1)
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)
              root.chooseSnapSlot(root.snapSelectedLayout, root.snapSelectedSlot)
            else
              return
          } else if (root.managerMode === "assist") {
            if (event.key === Qt.Key_Left || event.key === Qt.Key_Up || event.key === Qt.Key_Backtab)
              root.snapAssistSelected = Logic.wrapIndex(root.snapAssistSelected - 1, root.snapAssistCandidates.length)
            else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down || event.key === Qt.Key_Tab)
              root.snapAssistSelected = Logic.wrapIndex(root.snapAssistSelected + 1, root.snapAssistCandidates.length)
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)
              root.chooseSnapAssist(root.snapAssistSelected)
            else
              return
          } else {
            return
          }
          event.accepted = true
        }

        Text {
          id: managerHeading

          anchors {
            top: parent.top
            topMargin: Style.space(18)
            horizontalCenter: parent.horizontalCenter
          }
          text: root.managerMode === "settings" ? "Orbit · Window modes" : root.managerMode === "assist" ? "Orbit · Snap Assist" : "Orbit · Snap layouts"
          color: Color.menu.text
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }

        Loader {
          anchors {
            top: managerHeading.bottom
            topMargin: Style.space(16)
            bottom: parent.bottom
            bottomMargin: Style.space(18)
            left: parent.left
            leftMargin: Style.space(20)
            right: parent.right
            rightMargin: Style.space(20)
          }
          sourceComponent: root.managerMode === "settings" ? settingsComponent : root.managerMode === "assist" ? snapAssistComponent : snapPickerComponent
        }

        Component {
          id: snapPickerComponent

          Column {
            spacing: Style.space(14)

            SnapLayoutPicker {
              anchors.horizontalCenter: parent.horizontalCenter
              layouts: root.snapLayouts
              selectedLayout: root.snapSelectedLayout
              selectedSlot: root.snapSelectedSlot
              onSlotHovered: (layoutIndex, slotIndex) => {
                root.snapSelectedLayout = layoutIndex
                root.snapSelectedSlot = slotIndex
              }
              onSlotRequested: (layoutIndex, slotIndex) => {
                root.snapSelectedLayout = layoutIndex
                root.snapSelectedSlot = slotIndex
                root.chooseSnapSlot(layoutIndex, slotIndex)
              }
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "Arrows choose · Enter snaps · Esc cancels"
              color: Color.menu.text
              opacity: 0.55
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        Component {
          id: settingsComponent

          WindowModeSettings {
            width: parent ? parent.width : 0
            modes: root.settingsDraft
            onToggleRequested: mode => root.toggleSettingsMode(mode)
            onDefaultRequested: mode => root.setSettingsDefault(mode)
            onApplyRequested: root.applyWindowModeSettings()
            onCancelRequested: root.closeManager()
          }
        }

        Component {
          id: snapAssistComponent

          Column {
            spacing: Style.space(12)

            Text {
              width: parent.width
              text: "Pick a window for the next open zone. Continue until the layout is filled, or press Esc."
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              horizontalAlignment: Text.AlignHCenter
              color: Color.menu.text
              opacity: 0.65
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.caption
            }

            GridView {
              anchors.horizontalCenter: parent.horizontalCenter
              maximumWidth: managerCard.width - Style.space(56)
              maximumHeight: managerCard.height - Style.space(130)
              windows: root.snapAssistCandidates
              selectedIndex: root.snapAssistSelected
              hoverArmed: true
              onSelectRequested: index => root.snapAssistSelected = index
              onActivateRequested: index => {
                root.snapAssistSelected = index
                root.chooseSnapAssist(index)
              }
            }
          }
        }
      }
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
      WlrLayershell.keyboardFocus: root.activationCommitInProgress ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive

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
        id: switcherScrim

        anchors.fill: parent
        color: root.activationCommitInProgress && root.handoffNeedsCover ? Color.menu.background : Color.menu.scrim

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

      Rectangle {
        id: handoffCover

        anchors.fill: parent
        z: root.activationCommitInProgress && root.handoffNeedsCover ? 1000 : -1000
        color: Color.menu.background
        clip: true

        ScreencopyView {
          id: outgoingCapture

          readonly property var captureWindow: root.windows.length > 0 ? root.windows[0] : null
          readonly property real coverScale: sourceSize.width > 0 && sourceSize.height > 0 ? Math.max(handoffCover.width / sourceSize.width, handoffCover.height / sourceSize.height) : 1

          anchors.centerIn: parent
          width: sourceSize.width > 0 ? sourceSize.width * coverScale : handoffCover.width
          height: sourceSize.height > 0 ? sourceSize.height * coverScale : handoffCover.height
          captureSource: captureWindow ? captureWindow.wayland : null
          constraintSize: Qt.size(Math.max(1, handoffCover.width), Math.max(1, handoffCover.height))
          paintCursor: false
          live: false
        }

        ShaderEffectSource {
          anchors.centerIn: parent
          width: outgoingCapture.width
          height: outgoingCapture.height
          sourceItem: outgoingCapture
          hideSource: true
          live: !root.activationCommitInProgress
        }

        ScreencopyView {
          id: targetReadyProbe

          anchors.fill: parent
          captureSource: root.pendingWindow ? root.pendingWindow.wayland : null
          constraintSize: Qt.size(Math.max(1, handoffCover.width), Math.max(1, handoffCover.height))
          paintCursor: false
          live: true
          opacity: 0
          onHasContentChanged: root.observeActivationTargetSurface(sourceSize.width, sourceSize.height)
          onSourceSizeChanged: root.observeActivationTargetSurface(sourceSize.width, sourceSize.height)
        }

        Timer {
          interval: 32
          repeat: true
          running: root.activationCommitInProgress && root.handoffNeedsCover
          onTriggered: root.observeActivationTargetSurface(targetReadyProbe.sourceSize.width, targetReadyProbe.sourceSize.height)
        }
      }
    }
  }
}

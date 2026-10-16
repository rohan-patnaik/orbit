import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Commons as OrbitTheme
import qs.Ui

// Windows-style taskbar for the Omarchy bar.
//
// Pinned applications are read from this module's shell.json entry. Running
// windows from normal Hyprland workspaces are grouped by desktop application
// and ordered with the pins using the saved drag order. Minimized windows remain
// available to restore.
// Other special-workspace utility windows are omitted,
// matching the usual taskbar treatment of background helpers and scratchpads.
Item {
  id: taskbar

  property var popoutOwner: taskbar
  property QtObject bar: null
  property string moduleName: ""
  property var settings: ({})

  property var taskEntries: []
  property var clientWindows: []
  property var previewSnapshots: ({})

  function previewIdentity(window) {
    var client = window ? window.lastIpcObject : ({})
    return String(client.stableId || client.pid || "") + ":" + String(client.class || "")
  }

  function rememberPreview(window, capture, width, height) {
    if (!window || !capture || !capture.url)
      return
    var address = safeAddress(window.address)
    if (!clientWindows.some(function (w) {
      return safeAddress(w.address) === address && previewIdentity(w) === previewIdentity(window)
    }))
      return
    var next = Object.assign({}, previewSnapshots)
    next[address] = {
      identity: previewIdentity(window),
      capture: capture,
      width: width,
      height: height,
      time: Date.now()
    }
    var keys = Object.keys(next).sort(function (a, b) {
      return next[b].time - next[a].time
    })
    for (var key of keys.slice(24))
      delete next[key]
    previewSnapshots = next
  }

  function savedPreview(window) {
    var saved = window ? previewSnapshots[safeAddress(window.address)] : null
    return saved && saved.identity === previewIdentity(window) ? saved : null
  }

  TaskbarTransition {
    id: transition
    taskbar: taskbar
  }

  property string pendingLaunchId: ""
  property double pendingLaunchDeadline: 0
  Timer {
    interval: 16
    running: taskbar.pendingLaunchId !== ""
    repeat: true
    onTriggered: {
      if (Date.now() > taskbar.pendingLaunchDeadline) {
        taskbar.pendingLaunchId = ""
        return
      }
      var task = taskbar.taskEntries.find(function (t) {
        return taskbar.stripDesktopSuffix(t.desktopId) === taskbar.pendingLaunchId && t.windows.length > 0
      })
      if (task) {
        taskbar.pendingLaunchId = ""
        taskbar.focusWindow(task.windows[0])
      }
    }
  }
  // Keep feedback on the module: task delegates rebuild when window state
  // changes, but the clicked app's pulse must finish without restarting.
  property string pulsingTaskKey: ""
  property real clickScale: 1.0

  function pulseTask(task) {
    if (!task)
      return
    clickPulse.stop()
    clickScale = 1.0
    pulsingTaskKey = task.key
    clickPulse.start()
  }

  SequentialAnimation {
    id: clickPulse
    NumberAnimation {
      target: taskbar
      property: "clickScale"
      to: 1.18
      duration: 90
      easing.type: Easing.OutQuad
    }
    NumberAnimation {
      target: taskbar
      property: "clickScale"
      to: 1.0
      duration: 210
      easing.type: Easing.InOutQuad
    }
    onFinished: taskbar.pulsingTaskKey = ""
  }
  property string hoverTaskKey: ""
  property string previewTaskKey: ""
  property bool previewOpen: false
  readonly property var openPanelIndicatorPopup: previews.open ? previews : (contextMenu.open ? contextMenu : null)
  readonly property var previewTask: taskEntries.find(function (t) {
    return t.key === previewTaskKey
  }) || null

  function hoverTask(task, entered) {
    if (entered && task && task.windows.length && !contextOpen && !dragKey) {
      hoverTaskKey = task.key
      previewClose.stop()
      if (previewTaskKey !== task.key || !previewOpen)
        previewShow.restart()
    } else if (task && hoverTaskKey === task.key) {
      hoverTaskKey = ""
      previewShow.stop()
      previewClose.restart()
    }
  }

  function hidePreviews() {
    previewShow.stop()
    previewOpen = false
  }

  Timer {
    id: previewShow
    interval: 240
    onTriggered: {
      if (!taskbar.hoverTaskKey || taskbar.contextOpen)
        return
      taskbar.previewTaskKey = taskbar.hoverTaskKey
      previews.page = 0
      taskbar.previewOpen = true
    }
  }
  Timer {
    id: previewClose
    interval: 280
    onTriggered: if (!previews.containsMouse && !taskbar.hoverTaskKey)
      taskbar.hidePreviews()
  }

  // A persistent anchor and count-based delegates survive compositor polling.
  Item {
    id: previewAnchor
    x: Math.max(0, taskbar.taskEntries.findIndex(function (t) {
      return t.key === taskbar.previewTaskKey
    })) * taskbar.barSize
    width: taskbar.barSize
    height: taskbar.barSize
  }
  TaskbarPreviews {
    id: previews
    taskbar: taskbar
    anchorItem: previewAnchor
    bar: taskbar.bar
    task: taskbar.previewTask
    open: taskbar.previewOpen && task !== null && task.windows.length > 0
    onContainsMouseChanged: {
      if (containsMouse)
        previewClose.stop()
      else
        previewClose.restart()
    }
  }

  property var contextTask: null
  property var contextAnchor: null
  property bool contextOpen: false
  property int windowRevision: 0

  readonly property int barSize: bar ? bar.barSize : Style.bar.sizeHorizontal
  readonly property int iconExtent: Math.round(barSize * 0.55)
  readonly property color foreground: bar ? bar.barForeground : OrbitTheme.Color.foreground

  implicitWidth: taskRow.implicitWidth
  implicitHeight: barSize
  visible: taskEntries.length > 0

  function close() {
    contextOpen = false
    hidePreviews()
  }

  function stripDesktopSuffix(value) {
    return String(value || "").trim().replace(/\.desktop$/i, "")
  }

  function normalizeId(value) {
    return stripDesktopSuffix(value).toLowerCase()
  }

  function safeAddress(value) {
    var address = String(value || "").trim()
    var match = /^(?:0x)?([0-9a-fA-F]+)$/.exec(address)
    return match ? "0x" + match[1].toLowerCase() : ""
  }

  function appendUnique(values, value) {
    var text = stripDesktopSuffix(value)
    if (!text)
      return
    var normalized = normalizeId(text)
    for (var i = 0; i < values.length; i++) {
      if (normalizeId(values[i]) === normalized)
        return
    }
    values.push(text)
  }

  function mergeAliases(target, source) {
    var merged = target instanceof Array ? target.slice() : []
    var values = source instanceof Array ? source : []
    for (var i = 0; i < values.length; i++)
      appendUnique(merged, values[i])
    return merged
  }

  function friendlyName(value) {
    var text = stripDesktopSuffix(value)
    var dot = text.lastIndexOf(".")
    if (dot >= 0 && dot < text.length - 1)
      text = text.substring(dot + 1)
    text = text.replace(/[._-]+/g, " ").trim()
    if (!text)
      return "Application"
    return text.split(/\s+/).map(function (word) {
      return word.charAt(0).toUpperCase() + word.slice(1)
    }).join(" ")
  }

  function monogram(value) {
    var words = String(value || "App").trim().split(/\s+/)
    if (words.length <= 1)
      return words[0].slice(0, 2).toUpperCase()
    return (words[0].charAt(0) + words[words.length - 1].charAt(0)).toUpperCase()
  }

  function windowAliases(toplevel) {
    var aliases = []
    if (!toplevel)
      return aliases

    var client = toplevel.lastIpcObject || ({})
    var wayland = toplevel.wayland || null
    appendUnique(aliases, wayland ? wayland.appId : "")
    appendUnique(aliases, client.class)
    appendUnique(aliases, client.initialClass)
    return aliases
  }

  function desktopEntryFor(aliases) {
    var values = aliases instanceof Array ? aliases : []

    // Exact IDs are both the cheapest and the most reliable lookup.
    for (var i = 0; i < values.length; i++) {
      var original = stripDesktopSuffix(values[i])
      var normalized = normalizeId(original)
      var exact = original ? DesktopEntries.byId(original) : null
      if (exact)
        return exact
      if (normalized && normalized !== original) {
        exact = DesktopEntries.byId(normalized)
        if (exact)
          return exact
      }
    }

    // StartupWMClass is the authoritative bridge for apps whose window class
    // and desktop filename differ.
    var applications = DesktopEntries.applications.values || []
    for (var j = 0; j < applications.length; j++) {
      var entry = applications[j]
      if (!entry)
        continue
      var entryId = normalizeId(entry.id)
      var startupClass = normalizeId(entry.startupClass)
      for (var k = 0; k < values.length; k++) {
        var candidate = normalizeId(values[k])
        if (candidate && (candidate === entryId || candidate === startupClass))
          return entry
      }
    }

    // Browser --app windows use the URL, not the launcher's filename. Match
    // the URL host/path encoded in Exec so web apps never become Chrome tabs.
    for (var a = 0; a < applications.length; a++) {
      var app = applications[a]
      var command = String(app ? app.execString : "")
      if (!/(?:omarchy-launch-webapp|--app=)/.test(command))
        continue
      var urls = command.match(/https?:\/\/[^\s"']+/g) || []
      for (var u = 0; u < urls.length; u++) {
        // Chromium's app name is host + "_" + path (default path is /).
        var url = /^https?:\/\/([^/:?#]+)(?::[0-9]+)?([^?#]*)/.exec(urls[u])
        if (!url)
          continue
        var encoded = (url[1] + "_" + (url[2] || "/")).replace(/[^a-zA-Z0-9.]/g, "_").toLowerCase()
        for (var v = 0; v < values.length; v++) {
          var browserClass = normalizeId(values[v])
          if (/^(chrome|chromium|brave|msedge|vivaldi|opera|helium)-/.test(browserClass) && browserClass.substring(browserClass.indexOf("-") + 1).indexOf(encoded + "-") === 0)
            return app
        }
      }
    }
    // An unmatched browser app must not inherit its browser's icon/group.
    if (values.some(function (v) {
      return /^(chrome|chromium|brave|msedge|vivaldi|opera|helium)-/.test(normalizeId(v))
    }))
      return null

    // Quickshell's heuristic handles the remaining common reverse-domain and
    // AppImage naming differences.
    for (var n = 0; n < values.length; n++) {
      var heuristic = DesktopEntries.heuristicLookup(stripDesktopSuffix(values[n]))
      if (heuristic)
        return heuristic
    }
    return null
  }

  function applicationInfo(toplevel) {
    var aliases = windowAliases(toplevel)
    var entry = desktopEntryFor(aliases)
    if (entry) {
      appendUnique(aliases, entry.id)
      appendUnique(aliases, entry.startupClass)
      var desktopId = stripDesktopSuffix(entry.id)
      var name = String(entry.name || friendlyName(desktopId))
      return {
        key: normalizeId(desktopId),
        desktopId: desktopId,
        name: name,
        icon: String(entry.icon || desktopId || "application-x-executable"),
        aliases: aliases,
        fallbackText: monogram(name)
      }
    }

    var fallbackId = aliases.length > 0 ? aliases[0] : "application"
    var fallbackName = friendlyName(fallbackId)
    return {
      key: normalizeId(fallbackId),
      desktopId: "",
      name: fallbackName,
      icon: fallbackId || "application-x-executable",
      aliases: aliases,
      fallbackText: monogram(fallbackName)
    }
  }

  function sanitizedPin(pin) {
    if (!pin || typeof pin !== "object")
      return null
    var desktopId = stripDesktopSuffix(pin.desktopId || pin.id || "")
    var key = normalizeId(pin.key || desktopId)
    if (!key)
      return null

    var aliases = []
    appendUnique(aliases, key)
    appendUnique(aliases, desktopId)
    var configuredAliases = pin.aliases instanceof Array ? pin.aliases : []
    for (var i = 0; i < configuredAliases.length; i++)
      appendUnique(aliases, configuredAliases[i])

    var entry = desktopEntryFor(aliases)
    var icon = String(pin.icon || "")
    if (entry && entry.icon && (!icon || normalizeId(icon) === normalizeId(desktopId) || icon === "application-x-executable"))
      icon = String(entry.icon)
    var name = String(pin.name || friendlyName(desktopId || key))
    return {
      key: key,
      desktopId: desktopId,
      name: name,
      icon: icon || desktopId || key,
      aliases: aliases,
      fallbackText: monogram(name)
    }
  }

  function configuredPins() {
    var rawPins = settings && settings.pins instanceof Array ? settings.pins : []
    var pins = []
    for (var i = 0; i < rawPins.length; i++) {
      var pin = sanitizedPin(rawPins[i])
      if (!pin)
        continue
      var duplicate = false
      for (var j = 0; j < pins.length; j++) {
        if (pins[j].key === pin.key) {
          duplicate = true
          break
        }
      }
      if (!duplicate)
        pins.push(pin)
    }
    return pins
  }

  function identitiesOverlap(left, right) {
    var a = left instanceof Array ? left : []
    var b = right instanceof Array ? right : []
    for (var i = 0; i < a.length; i++) {
      var normalized = normalizeId(a[i])
      if (!normalized)
        continue
      for (var j = 0; j < b.length; j++) {
        if (normalized === normalizeId(b[j]))
          return true
      }
    }
    return false
  }

  function pinIndexForInfo(info, pins) {
    var infoAliases = info.aliases instanceof Array ? info.aliases.slice() : []
    appendUnique(infoAliases, info.key)
    appendUnique(infoAliases, info.desktopId)
    for (var i = 0; i < pins.length; i++) {
      var pinAliases = pins[i].aliases instanceof Array ? pins[i].aliases.slice() : []
      appendUnique(pinAliases, pins[i].key)
      appendUnique(pinAliases, pins[i].desktopId)
      if (identitiesOverlap(infoAliases, pinAliases))
        return i
    }
    return -1
  }

  // Store recovery data in the compositor workspace name, so minimizing is
  // reversible even after a shell reload, on either monitor's taskbar.
  function normalWorkspace(workspace) {
    return !!workspace && Number.isFinite(Number(workspace.id)) && (Number(workspace.id) > 0 || (!!workspace.name && !String(workspace.name).startsWith("special:")))
  }

  function minimizedState(toplevel) {
    var client = toplevel ? (toplevel.lastIpcObject || ({})) : ({})
    var name = String(client.workspace ? client.workspace.name : "")
    var match = /^special:taskbar-minimized-(-?\d+)-([0-3])-([0-3])-([01])-[0-9a-f]+(?:-([0-9a-f]+)-([0-9a-f]+))?$/.exec(name)
    return match ? {
      workspace: match[1],
      workspaceHex: match[5] || "",
      monitorHex: match[6] || "",
      internal: Number(match[2]),
      client: Number(match[3]),
      pinned: match[4] === "1"
    } : null
  }

  function minimizedRestoreScript(state) {
    if (!state)
      return ""
    return 'local function unhex(s) return (s:gsub("..",function(c) return string.char(tonumber(c,16)) end)) end; ' + 'local destination=' + (Number(state.workspace) > 0 ? '"' + state.workspace + '"' : '"name:"..unhex("' + state.workspaceHex + '")') + '; ' + 'local existed=hl.get_workspace(destination); ' + 'hl.dispatch(hl.dsp.window.move({workspace=destination,follow=false,window=t})); ' + 'if not existed then for _,m in ipairs(hl.get_monitors()) do if m.name==unhex("' + state.monitorHex + '") then ' + 'hl.dispatch(hl.dsp.workspace.move({workspace=destination,monitor=m.name})); break end end end; '
  }

  function utf8Hex(value) {
    return Array.from(unescape(encodeURIComponent(String(value || "")))).map(function (c) {
      return ("0" + c.charCodeAt(0).toString(16)).slice(-2)
    }).join("")
  }

  function moveWindow(toplevel, workspace) {
    var address = safeAddress(toplevel.address)
    if (!address)
      return
    if (Hyprland.usingLua)
      Hyprland.dispatch('hl.dsp.window.move({ workspace = "' + workspace + '", follow = false, window = "address:' + address + '" })')
    else
      Hyprland.dispatch("movetoworkspacesilent " + workspace + ",address:" + address)
  }

  function minimizeWindow(toplevel) {
    minimizeWindows([toplevel])
  }

  function minimizeWindows(toplevels) {
    // Capture MRU before hiding any siblings: each move changes focus history.
    // Release, hide and promote the survivor in one compositor transaction.
    var windows = (toplevels || []).filter(function (w) {
      return w && !minimizedState(w) && normalWorkspace(w.workspace) && safeAddress(w.address)
    })
    if (!windows.length)
      return
    var workspace = Number(windows[0].workspace.id)
    var addresses = windows.map(function (w) {
      return safeAddress(w.address)
    })
    var candidates = clientWindows.filter(function (w) {
      return eligibleWindow(w) && !minimizedState(w) && w.workspace && Number(w.workspace.id) === workspace && addresses.indexOf(safeAddress(w.address)) < 0
    }).sort(function (a, b) {
      return focusHistory(a) - focusHistory(b)
    })
    if (!Hyprland.usingLua) {
      windows.forEach(function (w) {
        taskbar.minimizeWindowLegacy(w)
      })
      if (candidates.length)
        focusWindow(candidates[0])
      return
    }
    var script = 'local function hex(s) return (s:gsub(".",function(c) return string.format("%02x",string.byte(c)) end)) end; local ws=' + workspace + '; local targets={}; local candidates={}; '
    addresses.forEach(function (address) {
      script += 'do local w=hl.get_window("address:' + address + '"); ' + 'if w and w.mapped and w.workspace and w.workspace.id==ws then table.insert(targets,w) end end; '
    })
    candidates.forEach(function (w) {
      script += 'do local w=hl.get_window("address:' + safeAddress(w.address) + '"); ' + 'if w and w.mapped and w.workspace and w.workspace.id==ws then table.insert(candidates,w) end end; '
    })
    script += 'table.sort(candidates,function(a,b) return a.focus_history_id<b.focus_history_id end); '
    script += 'for _,w in ipairs(targets) do ' + 'local destination="special:taskbar-minimized-"..ws.."-"..w.fullscreen.."-"..w.fullscreen_client.."-"..(w.pinned and "1" or "0").."-"..w.address:gsub("^0x","").."-"..hex(w.workspace.name).."-"..hex(w.monitor.name); ' + 'if w.pinned then hl.dispatch(hl.dsp.window.pin({action="off",window=w})) end; ' + 'hl.dispatch(hl.dsp.window.fullscreen_state({internal=0,client=0,action="set",window=w})); ' + 'hl.dispatch(hl.dsp.window.move({workspace=destination,follow=false,window=w})); end; ' + 'local nextWindow=candidates[1]; '
    script += 'if nextWindow then ' + 'if nextWindow.workspace.tiled_layout=="monocle" and not nextWindow.floating then hl.dispatch(hl.dsp.focus({window=nextWindow})) end; ' + 'hl.dispatch(hl.dsp.window.fullscreen_state({internal=1,client=1,action="set",window=nextWindow})); ' + 'hl.dispatch(hl.dsp.window.set_prop({prop="sync_fullscreen",value="true",window=nextWindow})); ' + 'hl.dispatch(hl.dsp.focus({window=nextWindow})); ' + 'hl.dispatch(hl.dsp.window.alter_zorder({mode="top",window=nextWindow})) end'
    transition.run(script, candidates.length ? safeAddress(candidates[0].address) : "", addresses.concat(candidates.length ? [safeAddress(candidates[0].address)] : []))
  }

  function minimizeWindowLegacy(toplevel) {
    if (!toplevel || minimizedState(toplevel))
      return
    var client = toplevel.lastIpcObject || ({})
    var workspace = client.workspace ? Number(client.workspace.id) : 0
    var address = safeAddress(toplevel.address)
    if (!normalWorkspace(client.workspace) || !address)
      return
    var destination = "special:taskbar-minimized-" + workspace + "-" + Number(client.fullscreen || 0) + "-" + Number(client.fullscreenClient || 0) + "-" + (client.pinned ? "1" : "0") + "-" + address.slice(2) + "-" + utf8Hex(client.workspace.name) + "-" + utf8Hex(((Hyprland.monitors.values || []).find(function (m) {
        return Number(m.id) === Number(client.monitor)
      }) || {}).name)
    if (client.pinned) {
      if (Hyprland.usingLua)
        Hyprland.dispatch('hl.dsp.window.pin({ action = "off", window = "address:' + address + '" })')
      else
        Hyprland.dispatch("pin address:" + address)
    }
    moveWindow(toplevel, destination)
  }

  function restoreWindow(toplevel) {
    var state = minimizedState(toplevel)
    if (!state)
      return
    var address = safeAddress(toplevel.address)
    if (Hyprland.usingLua) {
      Hyprland.dispatch('local t=hl.get_window("address:' + address + '"); if t then ' + minimizedRestoreScript(state) + 'end')
      Hyprland.dispatch('hl.dsp.window.fullscreen_state({ internal = ' + state.internal + ', client = ' + state.client + ', window = "address:' + address + '" })')
      if (state.pinned)
        Hyprland.dispatch('hl.dsp.window.pin({ action = "on", window = "address:' + address + '" })')
    } else {
      moveWindow(toplevel, Number(state.workspace) > 0 ? state.workspace : "name:" + decodeURIComponent(state.workspaceHex.replace(/../g, "%$&")))
      Hyprland.dispatch("fullscreenstate " + state.internal + " " + state.client + " address:" + address)
      if (state.pinned)
        Hyprland.dispatch("pin address:" + address)
    }
  }

  function eligibleWindow(toplevel) {
    if (!toplevel)
      return false
    var client = toplevel.lastIpcObject || ({})
    if (client.mapped === false)
      return false
    if (String(client.class || "").toLowerCase() === "wispr-flow")
      return false

    if (!normalWorkspace(client.workspace || toplevel.workspace) && !minimizedState(toplevel))
      return false

    var tags = client.tags instanceof Array ? client.tags : []
    if (tags.indexOf("skip-taskbar") !== -1)
      return false
    return windowAliases(toplevel).length > 0
  }

  function focusHistory(toplevel) {
    var client = toplevel ? (toplevel.lastIpcObject || ({})) : ({})
    var value = Number(client.focusHistoryID)
    return Number.isFinite(value) && value >= 0 ? value : 2147483647
  }

  function refreshTasks() {
    if (dragKey)
      return
    var pins = configuredPins()
    var entries = []
    var groups = ({})

    for (var i = 0; i < pins.length; i++) {
      var pin = pins[i]
      var pinTask = {
        key: pin.key,
        pinKey: pin.key,
        desktopId: pin.desktopId,
        name: pin.name,
        icon: pin.icon,
        aliases: pin.aliases,
        fallbackText: pin.fallbackText,
        windows: [],
        pinned: true
      }
      entries.push(pinTask)
      groups["pin:" + i] = pinTask
    }

    // Use fresh compositor data for both normal and minimized windows. The
    // Wayland model can retain stale IPC objects after a workspace move.
    var windows = clientWindows
    for (var j = 0; j < windows.length; j++) {
      var toplevel = windows[j]
      if (!eligibleWindow(toplevel))
        continue
      var info = applicationInfo(toplevel)
      var pinIndex = pinIndexForInfo(info, pins)
      var groupId = pinIndex >= 0 ? "pin:" + pinIndex : "app:" + info.key
      var task = groups[groupId]
      if (!task) {
        task = {
          key: info.key,
          pinKey: "",
          desktopId: info.desktopId,
          name: info.name,
          icon: info.icon,
          aliases: info.aliases,
          fallbackText: info.fallbackText,
          windows: [],
          pinned: false
        }
        entries.push(task)
        groups[groupId] = task
      } else {
        task.aliases = mergeAliases(task.aliases, info.aliases)
        // A live desktop entry can fill in metadata for an older/minimal pin.
        if (!task.desktopId && info.desktopId)
          task.desktopId = info.desktopId
        if (!task.icon && info.icon)
          task.icon = info.icon
      }
      task.windows.push(toplevel)
    }

    for (var n = 0; n < entries.length; n++) {
      entries[n].windows.sort(function (left, right) {
        var delta = focusHistory(left) - focusHistory(right)
        if (delta !== 0)
          return delta
        return safeAddress(left.address).localeCompare(safeAddress(right.address))
      })
    }

    taskEntries = orderedTasks(entries, settings.taskOrder)
    windowRevision++
  }

  function taskIsActive(task) {
    var revision = windowRevision
    var active = Hyprland.activeToplevel
    var address = active ? safeAddress(active.address) : ""
    var windows = task && task.windows instanceof Array ? task.windows : []
    for (var i = 0; i < windows.length; i++) {
      if (address && safeAddress(windows[i].address) === address && !minimizedState(windows[i]))
        return true
    }
    return false
  }

  function taskIsUrgent(task) {
    var revision = windowRevision
    var windows = task && task.windows instanceof Array ? task.windows : []
    for (var i = 0; i < windows.length; i++) {
      if (windows[i] && windows[i].urgent === true)
        return true
    }
    return false
  }

  function tooltipFor(task) {
    var count = task && task.windows instanceof Array ? task.windows.length : 0
    var status = count === 0 ? "Pinned" : (count === 1 ? "1 window" : count + " windows")
    return String(task ? task.name : "Application") + " — " + status + "\nDrag to reorder · Left-click to switch, minimize or restore · Middle-click for a new window · Right-click for options"
  }

  function symbolicIcon(iconName) {
    return /-symbolic(?:\.[a-z]+)?$/.test(String(iconName || ""))
  }

  function iconSource(iconName) {
    var value = String(iconName || "")
    var library = bar && bar.shell ? bar.shell.appLibrary : null
    if (library && typeof library.iconSource === "function") {
      var resolved = library.iconSource(value)
      // Missing metadata gets a distinctive monogram, not the same gear for
      // every unknown app. Keep real icons named application-x-executable.
      if (value !== "application-x-executable" && String(resolved) === String(Quickshell.iconPath("application-x-executable", true)))
        return ""
      return resolved
    }
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0)
      return value
    if (value.charAt(0) === "/")
      return Util.fileUrl(value)
    var themed = Quickshell.iconPath(value, true)
    return themed || ""
  }

  function launchTask(task) {
    if (!task)
      return
    var desktopId = stripDesktopSuffix(task.desktopId)
    if (!desktopId)
      return
    pendingLaunchId = desktopId
    pendingLaunchDeadline = Date.now() + 20000
    var library = bar && bar.shell ? bar.shell.appLibrary : null
    if (Hyprland.usingLua) {
      if (library && typeof library.beginLaunchFeedback === "function")
        library.beginLaunchFeedback(task.name)
      var command = "uwsm-app -- gtk-launch " + Util.shellQuote(desktopId + ".desktop")
      var source = Hyprland.activeToplevel ? safeAddress(Hyprland.activeToplevel.address) : ""
      transition.run('hl.dispatch(hl.dsp.exec_cmd(' + JSON.stringify(command) + ', {maximize=true, no_anim=true}))', "", source ? [source] : [], true)
      return
    }
    if (library && typeof library.launch === "function") {
      library.launch(desktopId, task.name)
      return
    }
    Quickshell.execDetached(["uwsm-app", "--", "gtk-launch", desktopId + ".desktop"])
  }

  function focusWindow(toplevel) {
    if (!toplevel)
      return
    var address = safeAddress(toplevel.address)
    if (address) {
      if (Hyprland.usingLua) {
        // One compositor transaction releases the outgoing maximized window,
        // then promotes the selected app to work-area maximized (mode 1).
        // This also covers floating apps such as T3 Code and ChatGPT.
        var restore = minimizedState(toplevel)
        var script = 'local t=hl.get_window("address:' + address + '"); if not t or not t.mapped then return end; '
        if (restore) {
          script += minimizedRestoreScript(restore)
          if (restore.pinned)
            script += 'hl.dispatch(hl.dsp.window.pin({action="on",window=t})); '
        }
        script += 'local monocle=t.workspace and t.workspace.tiled_layout=="monocle" and not t.floating; ' + 'if monocle and t.fullscreen>0 then hl.dispatch(hl.dsp.window.fullscreen_state({internal=0,client=t.fullscreen_client,action="set",window=t})) end; ' + 'for _,s in ipairs(hl.get_windows()) do if s.address~=t.address and s.workspace and t.workspace and s.workspace.id==t.workspace.id and s.fullscreen>0 then ' + 'hl.dispatch(hl.dsp.window.set_prop({prop="no_anim",value="true",window=s})); ' + 'hl.dispatch(hl.dsp.window.fullscreen_state({internal=0,client=s.fullscreen_client==2 and 2 or 0,action="set",window=s})); ' + 'if s.fullscreen_client~=2 then hl.dispatch(hl.dsp.window.set_prop({prop="sync_fullscreen",value="true",window=s})) end end end; ' + 'if monocle then hl.dispatch(hl.dsp.focus({window=t})) end; ' + 'hl.dispatch(hl.dsp.window.fullscreen_state({internal=1,client=1,action="set",window=t})); ' + 'hl.dispatch(hl.dsp.window.set_prop({prop="sync_fullscreen",value="true",window=t})); ' + 'hl.dispatch(hl.dsp.focus({window=t})); ' + 'hl.dispatch(hl.dsp.window.alter_zorder({mode="top",window=t}))'
        var source = Hyprland.activeToplevel ? safeAddress(Hyprland.activeToplevel.address) : ""
        var workspace = restore ? Number(restore.workspace) : Number(toplevel.workspace.id)
        var affected = clientWindows.filter(function (w) {
          return w.workspace && Number(w.workspace.id) === workspace
        }).map(function (w) {
          return safeAddress(w.address)
        })
        transition.run(script, address, affected.concat([source, address]))
      } else {
        restoreWindow(toplevel)
        Hyprland.dispatch("focuswindow address:" + address)
        Hyprland.dispatch("fullscreenstate 1 1 address:" + address)
      }
      return
    }
    if (toplevel.wayland && typeof toplevel.wayland.activate === "function")
      toplevel.wayland.activate()
  }

  function activateTask(task) {
    if (!task)
      return
    var windows = task.windows instanceof Array ? task.windows : []
    if (windows.length === 0) {
      launchTask(task)
      return
    }

    // A focused application toggles out of view. Minimize its sibling windows
    // on this workspace too, so a grouped app does not leave another window
    // covering the desktop. Windows on other workspaces stay where they are.
    if (taskIsActive(task)) {
      var active = Hyprland.activeToplevel
      var activeAddress = active ? safeAddress(active.address) : ""
      var focusedWindow = windows.find(function (w) {
        return safeAddress(w.address) === activeAddress
      })
      var focusedClient = focusedWindow ? (focusedWindow.lastIpcObject || ({})) : ({})
      if (focusedWindow && Number(focusedClient.fullscreen) !== 1) {
        focusWindow(focusedWindow)
        return
      }
      var workspace = focusedWindow && focusedWindow.workspace ? focusedWindow.workspace.id : 0
      minimizeWindows(windows.filter(function (w) {
        var client = w.lastIpcObject || ({})
        return client.workspace && client.workspace.id === workspace
      }))
      return
    }

    // Prefer an existing normal window over a minimized sibling. With all
    // windows minimized, restore the most recently used one.
    var target = windows[0]
    for (var j = 0; j < windows.length; j++) {
      if (!minimizedState(windows[j])) {
        target = windows[j]
        break
      }
    }
    var restoreState = minimizedState(target)
    if (restoreState) {
      for (var k = 0; k < windows.length; k++) {
        var siblingState = minimizedState(windows[k])
        if (windows[k] !== target && siblingState && siblingState.workspace === restoreState.workspace)
          restoreWindow(windows[k])
      }
    }
    focusWindow(target)
  }

  function closeTaskWindows(task) {
    contextOpen = false
    var windows = task && task.windows instanceof Array ? task.windows.slice() : []
    for (var i = 0; i < windows.length; i++) {
      var toplevel = windows[i]
      if (toplevel && toplevel.wayland && typeof toplevel.wayland.close === "function") {
        toplevel.wayland.close()
      } else {
        var address = toplevel ? safeAddress(toplevel.address) : ""
        if (address) {
          if (Hyprland.usingLua)
            Hyprland.dispatch('hl.dsp.window.close({ window = "address:' + address + '" })')
          else
            Hyprland.dispatch("closewindow address:" + address)
        }
      }
    }
  }

  function taskPinIndex(task, pins) {
    if (!task)
      return -1
    var info = {
      key: task.pinKey || task.key,
      desktopId: task.desktopId,
      aliases: task.aliases
    }
    return pinIndexForInfo(info, pins)
  }

  function persistSettings(next) {
    if (JSON.stringify(next) === JSON.stringify(settings))
      return true
    if (!bar || !bar.shell || typeof bar.shell.updateEntryInline !== "function" || bar.shell.updateEntryInline(moduleName || "taskbar", next) !== true) {
      console.warn("Taskbar: settings write failed")
      Quickshell.execDetached(["notify-send", "Taskbar", "Could not save taskbar order or pins."])
      return false
    }
    settings = next
    refreshTasks()
    return true
  }

  function persistPins(pins) {
    var next = Object.assign({}, settings)
    next.type = "qml"
    next.pins = pins
    return persistSettings(next)
  }

  function orderedTasks(entries, order) {
    var keys = order instanceof Array ? order : []
    var next = entries.slice()
    // Stable sort leaves new apps/pins in their existing relative order.
    next.sort(function (a, b) {
      var ai = keys.indexOf(a.key), bi = keys.indexOf(b.key)
      var delta = (ai < 0 ? keys.length : ai) - (bi < 0 ? keys.length : bi)
      return delta || entries.indexOf(a) - entries.indexOf(b)
    })
    return next
  }

  function reorderSettings(keys) {
    var next = Object.assign({}, settings)
    var order = keys.slice()
    // Retain positions for apps that are currently closed.
    var old = settings.taskOrder instanceof Array ? settings.taskOrder : []
    for (var i = 0; i < old.length; i++)
      if (order.indexOf(old[i]) < 0)
        order.push(old[i])
    next.taskOrder = order
    var rawPins = settings.pins instanceof Array ? settings.pins : []
    next.pins = orderedTasks(configuredPins(), order).map(function (pin) {
      return rawPins.find(function (raw) {
        var clean = sanitizedPin(raw)
        return clean && clean.key === pin.key
      }) || pin
    })
    return next
  }

  property string dragKey: ""
  property bool iconDragging: false
  property real dragStartX: 0
  property real dragStartY: 0
  property real dragPointerX: 0
  property int dragDropIndex: -1
  property var dragOriginal: []

  function beginIconGesture(key, point) {
    dragKey = key
    iconDragging = false
    dragStartX = point.x
    dragStartY = point.y
    dragPointerX = point.x
    dragOriginal = taskEntries.slice()
    hidePreviews()
    contextOpen = false
  }

  function updateIconGesture(point) {
    if (!dragKey)
      return
    if (!iconDragging && Math.abs(point.x - dragStartX) + Math.abs(point.y - dragStartY) < 6)
      return
    iconDragging = true
    hoverTaskKey = ""
    dragPointerX = point.x
    // Leaving the row vertically cancels the drop, without moving an app.
    dragDropIndex = point.y < -barSize || point.y > barSize * 2 ? -1 : Math.max(0, Math.min(dragOriginal.length - 1, Math.floor(point.x / barSize)))
    var next = dragOriginal.slice()
    var from = next.findIndex(function (t) {
      return t.key === dragKey
    })
    if (from < 0 || dragDropIndex < 0)
      return
    var moved = next.splice(from, 1)[0]
    next.splice(dragDropIndex, 0, moved)
    taskEntries = next
  }

  function endIconGesture(cancelled) {
    var consumed = iconDragging
    var keys = taskEntries.map(function (t) {
      return t.key
    })
    var changed = JSON.stringify(keys) !== JSON.stringify(dragOriginal.map(function (t) {
      return t.key
    }))
    var save = consumed && !cancelled && dragDropIndex >= 0 && changed
    dragKey = ""
    iconDragging = false
    dragDropIndex = -1
    if (save)
      persistSettings(reorderSettings(keys))
    refreshTasks()
    return consumed
  }

  function togglePin(task) {
    if (!task)
      return
    var pins = configuredPins()
    var index = taskPinIndex(task, pins)
    contextOpen = false

    if (index >= 0) {
      pins.splice(index, 1)
      persistPins(pins)
      return
    }

    var desktopId = stripDesktopSuffix(task.desktopId)
    if (!desktopId)
      return
    pins.push({
      key: normalizeId(task.key || desktopId),
      desktopId: desktopId,
      name: String(task.name || friendlyName(desktopId)),
      icon: String(task.icon || desktopId),
      aliases: mergeAliases(task.aliases, [task.key, desktopId])
    })
    persistPins(pins)
  }

  function openContextMenu(task, anchor) {
    if (!task || !anchor)
      return
    hidePreviews()
    contextTask = task
    contextAnchor = anchor
    contextOpen = true
    if (bar)
      bar.hideTooltip(anchor)
  }

  onSettingsChanged: {
    if (dragKey)
      endIconGesture(true)
    refreshDebounce.restart()
  }

  Connections {
    target: Hyprland.toplevels
    function onValuesChanged() {
      refreshDebounce.restart()
    }
  }

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() {
      refreshDebounce.restart()
    }
  }

  Connections {
    target: Hyprland
    function onActiveToplevelChanged() {
      taskbar.windowRevision++
      refreshDebounce.restart()
    }
    function onRawEvent(event) {
      var name = String(event ? event.name : "")
      if (/^(openwindow|closewindow|activewindow|windowtitle|movewindow|urgent)/.test(name))
        refreshDebounce.restart()
    }
  }

  Timer {
    id: refreshDebounce
    interval: 40
    onTriggered: {
      taskbar.refreshTasks()
      if (!clientQuery.running)
        clientQuery.running = true
    }
  }

  Process {
    id: clientQuery
    command: ["hyprctl", "-j", "clients"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var clients = JSON.parse(text)
          taskbar.clientWindows = clients.map(function (client) {
            var live = (Hyprland.toplevels.values || []).find(function (w) {
              return taskbar.safeAddress(w.address) === taskbar.safeAddress(client.address)
            })
            return {
              address: client.address,
              workspace: client.workspace,
              lastIpcObject: client,
              wayland: live ? live.wayland : null,
              urgent: live ? live.urgent : false
            }
          })
          taskbar.refreshTasks()
        } catch (error) {
          console.warn("Taskbar: cannot refresh windows:", error)
        }
      }
    }
  }

  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: if (!clientQuery.running)
      clientQuery.running = true
  }

  Component.onCompleted: {
    refreshTasks()
    clientQuery.running = true
  }

  Row {
    id: taskRow
    anchors.centerIn: parent
    spacing: 0

    Repeater {
      id: taskButtons
      model: taskbar.taskEntries.length

      WidgetButton {
        id: taskButton
        required property int index

        function beginIconGesture(x, y) {
          taskbar.beginIconGesture(task.key, mapToItem(taskRow, x, y))
        }
        function updateIconGesture(x, y) {
          taskbar.updateIconGesture(mapToItem(taskRow, x, y))
        }
        function endIconGesture(cancelled) {
          return taskbar.endIconGesture(cancelled)
        }
        readonly property var task: taskbar.taskEntries[index]
        readonly property bool running: task && task.windows instanceof Array && task.windows.length > 0
        readonly property int rearCards: running ? Math.min(2, task.windows.length - 1) : 0
        readonly property bool focused: taskbar.taskIsActive(task)
        readonly property bool urgent: taskbar.taskIsUrgent(task)
        readonly property color tileColor: {
          if (urgent)
            return Qt.alpha(taskbar.bar ? taskbar.bar.urgent : OrbitTheme.Color.urgent, 0.24)
          if (tooltipHovered)
            return Qt.alpha(taskbar.foreground, focused ? 0.24 : (running ? 0.18 : 0.12))
          if (focused)
            return Qt.alpha(taskbar.foreground, 0.18)
          if (running)
            return Qt.alpha(taskbar.foreground, 0.09)
          return "transparent"
        }

        bar: taskbar.bar
        keepSpace: true
        hasVisualContent: true
        labelVisible: false
        fixedWidth: taskbar.barSize
        fixedHeight: taskbar.barSize
        tooltipText: running ? "" : taskbar.tooltipFor(task)
        onTooltipHoveredChanged: taskbar.hoverTask(task, tooltipHovered)
        onTaskChanged: if (tooltipHovered)
          taskbar.hoverTask(task, true)
        Component.onDestruction: taskbar.hoverTask(task, false)

        // At most three cards: two narrow exposed edges behind the front.
        Repeater {
          model: taskButton.rearCards
          Rectangle {
            required property int index
            x: 4 + (taskButton.rearCards - index) * 2.5
            y: 4 - (taskButton.rearCards - index) * 2.5
            width: taskbar.barSize - 11
            height: taskbar.barSize - 11
            radius: 7
            color: Qt.alpha(taskbar.foreground, 0.16 + index * 0.04)
            border.width: 1
            border.color: Qt.alpha(taskbar.foreground, 0.23)
          }
        }
        Rectangle {
          anchors.fill: parent
          anchors.margins: 4
          radius: 8
          // Opaque front card keeps the two rear cards visible only at edges.
          color: taskButton.rearCards > 0 ? Qt.tint(OrbitTheme.Color.background, taskButton.tileColor) : taskButton.tileColor

          Behavior on color {
            ColorAnimation {
              duration: 100
            }
          }
        }

        Item {
          id: iconVisual
          anchors.centerIn: parent
          // A transform leaves the button's layout and hit area unchanged.
          opacity: task && task.key === taskbar.dragKey && taskbar.iconDragging ? 0.3 : 1.0
          scale: task && task.key === taskbar.pulsingTaskKey ? taskbar.clickScale : 1.0
          transformOrigin: Item.Center
          width: taskbar.iconExtent
          height: taskbar.iconExtent

          Image {
            id: appIcon
            anchors.fill: parent
            sourceSize.width: width * Screen.devicePixelRatio
            sourceSize.height: height * Screen.devicePixelRatio
            source: taskbar.iconSource(task ? task.icon : "")
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
            mipmap: true
            layer.enabled: task && taskbar.symbolicIcon(task.icon)
            layer.effect: ColorOverlay {
              color: taskbar.foreground
            }
          }

          Text {
            anchors.centerIn: parent
            visible: appIcon.status === Image.Error || String(appIcon.source) === ""
            text: task ? task.fallbackText : "A"
            textFormat: Text.PlainText
            color: taskbar.foreground
            font.family: taskbar.bar ? taskbar.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }
        }

        onPressed: function (button) {
          taskbar.hidePreviews()
          taskbar.pulseTask(task)
          if (button === Qt.LeftButton)
            taskbar.activateTask(task)
          else if (button === Qt.MiddleButton)
            taskbar.launchTask(task)
          else if (button === Qt.RightButton)
            taskbar.openContextMenu(task, taskButton)
        }
      }
    }
  }

  Item {
    visible: taskbar.iconDragging
    x: taskRow.x + taskbar.dragPointerX - taskbar.barSize / 2
    y: taskRow.y
    width: taskbar.barSize
    height: taskbar.barSize
    z: 20
    readonly property var draggedTask: taskbar.dragOriginal.find(function (t) {
      return t.key === taskbar.dragKey
    }) || null
    Rectangle {
      anchors.fill: parent
      anchors.margins: 3
      radius: 8
      color: Qt.alpha(taskbar.foreground, 0.22)
    }
    Image {
      anchors.centerIn: parent
      width: taskbar.iconExtent
      height: width
      source: taskbar.iconSource(parent.draggedTask ? parent.draggedTask.icon : "")
      fillMode: Image.PreserveAspectFit
      layer.enabled: parent.draggedTask && taskbar.symbolicIcon(parent.draggedTask.icon)
      layer.effect: ColorOverlay {
        color: taskbar.foreground
      }
    }
  }

  PopupCard {
    id: contextMenu
    anchorItem: taskbar.contextAnchor || taskbar
    bar: taskbar.bar
    owner: taskbar.popoutOwner
    open: taskbar.contextOpen && taskbar.contextTask !== null
    contentWidth: contextMenu.fittedContentWidth(Style.space(260))
    contentHeight: contextMenu.fittedContentHeight(contextColumn.implicitHeight)

    Column {
      id: contextColumn
      anchors.fill: parent
      spacing: Style.space(4)

      Row {
        width: parent.width
        height: Math.max(contextIcon.height, contextTitleColumn.implicitHeight)
        spacing: Style.space(10)

        Image {
          id: contextIcon
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(24)
          height: Style.space(24)
          sourceSize.width: width * Screen.devicePixelRatio
          sourceSize.height: height * Screen.devicePixelRatio
          source: taskbar.iconSource(taskbar.contextTask ? taskbar.contextTask.icon : "")
          layer.enabled: taskbar.symbolicIcon(taskbar.contextTask ? taskbar.contextTask.icon : "")
          layer.effect: ColorOverlay {
            color: taskbar.foreground
          }
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          smooth: true
        }

        Column {
          id: contextTitleColumn
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - contextIcon.width - parent.spacing
          spacing: Style.space(1)

          Text {
            width: parent.width
            text: taskbar.contextTask ? taskbar.contextTask.name : "Application"
            textFormat: Text.PlainText
            color: OrbitTheme.Color.popups.text
            font.family: taskbar.bar ? taskbar.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            readonly property int windowCount: taskbar.contextTask && taskbar.contextTask.windows instanceof Array ? taskbar.contextTask.windows.length : 0
            text: windowCount === 0 ? "Not running" : (windowCount === 1 ? "1 window" : windowCount + " windows")
            color: Qt.alpha(OrbitTheme.Color.popups.text, 0.68)
            font.family: taskbar.bar ? taskbar.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
      }

      PanelSeparator {
        foreground: OrbitTheme.Color.popups.text
      }

      Button {
        visible: taskbar.contextTask && stripDesktopSuffix(taskbar.contextTask.desktopId) !== ""
        width: parent.width
        leftAlign: true
        iconText: "\uf067"
        text: "Open new window"
        foreground: OrbitTheme.Color.popups.text
        fontSize: Style.font.bodySmall
        iconSize: Style.font.bodySmall
        onClicked: {
          taskbar.contextOpen = false
          taskbar.launchTask(taskbar.contextTask)
        }
      }

      Button {
        width: parent.width
        leftAlign: true
        enabled: taskbar.contextTask && (taskbar.taskPinIndex(taskbar.contextTask, taskbar.configuredPins()) >= 0 || stripDesktopSuffix(taskbar.contextTask.desktopId) !== "")
        opacity: enabled ? 1.0 : 0.45
        iconText: "\uf08d"
        text: taskbar.contextTask && taskbar.taskPinIndex(taskbar.contextTask, taskbar.configuredPins()) >= 0 ? "Unpin from taskbar" : "Pin to taskbar"
        foreground: OrbitTheme.Color.popups.text
        fontSize: Style.font.bodySmall
        iconSize: Style.font.bodySmall
        onClicked: if (enabled)
          taskbar.togglePin(taskbar.contextTask)
      }

      PanelSeparator {
        visible: taskbar.contextTask && taskbar.contextTask.windows instanceof Array && taskbar.contextTask.windows.length > 0
        foreground: OrbitTheme.Color.popups.text
      }

      Button {
        visible: taskbar.contextTask && taskbar.contextTask.windows instanceof Array && taskbar.contextTask.windows.length > 0
        width: parent.width
        leftAlign: true
        iconText: "\uf2ed"
        text: taskbar.contextTask && taskbar.contextTask.windows.length > 1 ? "Close all windows" : "Close window"
        foreground: OrbitTheme.Color.popups.text
        fontSize: Style.font.bodySmall
        iconSize: Style.font.bodySmall
        onClicked: taskbar.closeTaskWindows(taskbar.contextTask)
      }
    }
  }
}

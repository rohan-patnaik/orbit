import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

// A short, input-transparent cover hides client resize negotiation. There is
// no polling or capture outside a taskbar action; Orbit supplies commit proof.
Item {
  id: root
  required property var taskbar
  property bool busy: false
  property bool dispatched: false
  property bool coverReady: false
  property bool needsResize: true
  property var job: null
  property var queued: []
  property var sourceWindow: null
  property var sourceScreen: null
  property var coverImage: null
  property double startedAt: 0
  property double dispatchedAt: 0
  property double readySince: 0
  property int generation: 0
  property var lastResult: ({})

  function run(script, address, addresses, launching) {
    var next = {
      script: script,
      target: address,
      addresses: addresses || [],
      launching: launching || false
    }
    if (busy && job.launching && !action.running) {
      launchDeadline.stop()
      next.addresses = next.addresses.concat(job.addresses)
      job = next
      dispatched = false
      readySince = 0
      dispatch()
      return
    }
    if (busy) {
      queued.push(next)
      return
    }
    job = next
    var activeWindow = taskbar.clientWindows.find(function (w) {
      return Hyprland.activeToplevel && taskbar.safeAddress(w.address) === taskbar.safeAddress(Hyprland.activeToplevel.address)
    }) || null
    var targetWindow = taskbar.clientWindows.find(function (w) {
      return taskbar.safeAddress(w.address) === address
    }) || activeWindow
    var targetMonitor = targetWindow ? targetWindow.lastIpcObject.monitor : -1
    if (launching && taskbar.QsWindow.window) {
      var launchMonitor = (Hyprland.monitors.values || []).find(function (m) {
        return m.name === taskbar.QsWindow.window.screen.name
      })
      if (launchMonitor)
        targetMonitor = launchMonitor.id
    }
    sourceWindow = activeWindow && Number(activeWindow.lastIpcObject.monitor) === Number(targetMonitor) ? activeWindow : taskbar.clientWindows.filter(function (w) {
      return Number(w.lastIpcObject.monitor) === Number(targetMonitor) && !taskbar.minimizedState(w) && w.lastIpcObject.visible !== false
    }).sort(function (a, b) {
      return taskbar.focusHistory(a) - taskbar.focusHistory(b)
    })[0] || activeWindow
    var ipc = sourceWindow ? sourceWindow.lastIpcObject : null
    var targetIpc = targetWindow ? targetWindow.lastIpcObject : null
    // A full-size inactive monocle window already has the required buffer.
    // New launches must leave the desktop live while the process starts:
    // a monitor snapshot can bake in the hover cursor/tooltip for two seconds.
    // Keep covers only for existing-window resizes and restores.
    needsResize = !launching && (!address || !ipc || !targetIpc || !!taskbar.minimizedState(targetWindow) || ipc.floating || targetIpc.floating || Number(ipc.fullscreen) !== 1 || Number(targetIpc.fullscreen) === 2 || !ipc.workspace || !targetIpc.workspace || ipc.workspace.id !== targetIpc.workspace.id || ipc.monitor !== targetIpc.monitor || !Array.isArray(ipc.size) || !Array.isArray(targetIpc.size) || !Array.isArray(ipc.at) || !Array.isArray(targetIpc.at) || ipc.size[0] <= 0 || ipc.size[1] <= 0 || ipc.size[0] !== targetIpc.size[0] || ipc.size[1] !== targetIpc.size[1] || ipc.at[0] !== targetIpc.at[0] || ipc.at[1] !== targetIpc.at[1])
    var monitor = (Hyprland.monitors.values || []).find(function (m) {
      return ipc && Number(m.id) === Number(ipc.monitor)
    })
    sourceScreen = (Quickshell.screens || []).find(function (s) {
      return monitor && s.name === monitor.name
    }) || (taskbar.QsWindow.window ? taskbar.QsWindow.window.screen : null)
    generation++
    startedAt = Date.now()
    coverReady = false
    coverImage = null
    readySince = 0
    dispatched = false
    busy = true
    if (needsResize)
      captureDeadline.restart()
    else
      dispatch()
  }

  function dispatch() {
    if (!busy || dispatched || action.running)
      return
    captureDeadline.stop()
    coverPaint.stop()
    dispatched = true
    dispatchedAt = Date.now()
    var script = ""
    for (var address of job.addresses) {
      var safe = taskbar.safeAddress(address)
      if (safe)
        script += 'do local w=hl.get_window("address:' + safe + '"); if w then hl.dispatch(hl.dsp.window.set_prop({prop="no_anim",value="true",window=w})); hl.dispatch(hl.dsp.window.set_prop({prop="render_unfocused",value="true",window=w})) end end; '
    }
    action.command = ["hyprctl", "eval", script + job.script]
    action.running = true
  }

  function finish(reason) {
    if (!busy || action.running)
      return
    readinessTimer.stop()
    launchDeadline.stop()
    coverPaint.stop()
    captureDeadline.stop()
    lastResult = {
      target: job.target,
      reason: reason,
      elapsedMs: Date.now() - startedAt,
      resizeMs: Date.now() - dispatchedAt,
      cover: coverReady
    }
    var script = ""
    for (var address of job.addresses) {
      var safe = taskbar.safeAddress(address)
      if (safe)
        script += 'do local w=hl.get_window("address:' + safe + '"); if w then hl.dispatch(hl.dsp.window.set_prop({prop="no_anim",value="unset",window=w})); hl.dispatch(hl.dsp.window.set_prop({prop="render_unfocused",value="unset",window=w})) end end; '
    }
    if (script)
      Quickshell.execDetached(["hyprctl", "eval", script])
    busy = false
    job = null
    sourceWindow = null
    coverImage = null
    if (queued.length) {
      var next = queued.shift()
      Qt.callLater(function () {
        root.run(next.script, next.target, next.addresses, next.launching)
      })
    }
  }

  Timer {
    id: captureDeadline
    interval: 150
    onTriggered: root.dispatch()
  }
  // Let the captured image reach the compositor before changing window sizes.
  // This runs once per switch, independently of client rendering latency.
  Timer {
    id: coverPaint
    interval: 34
    onTriggered: root.dispatch()
  }
  Timer {
    id: launchDeadline
    interval: 2000
    onTriggered: root.finish("launch-wait-timeout")
  }
  Process {
    id: action
    onExited: function (code) {
      if (code === 0 && root.job.launching) {
        if (root.queued.length) {
          var next = root.queued.shift()
          root.run(next.script, next.target, next.addresses, next.launching)
        } else
          launchDeadline.start()
      } else if (code !== 0 || !root.job.target)
        root.finish(code !== 0 ? "dispatch-error" : "no-target")
      else
        readinessTimer.start()
    }
  }
  Timer {
    id: readinessTimer
    interval: 16
    repeat: true
    onTriggered: {
      if (Date.now() - root.dispatchedAt > 1200) {
        root.finish("timeout")
        return
      }
      if (!readiness.running) {
        readiness.generation = root.generation
        readiness.command = ["hyprctl", "orbit-window-ready", root.job.target]
        readiness.running = true
      }
    }
  }
  Process {
    id: readiness
    property int generation: 0
    stdout: StdioCollector {
      onStreamFinished: {
        if (!root.busy || readiness.generation !== root.generation)
          return
        try {
          var state = JSON.parse(text)
          if (state.ready && state.active && state.internal === 1) {
            // A toplevel configure can precede its browser/GTK child surface.
            // Retain the cover through those subsequent rendering frames.
            if (!root.readySince)
              root.readySince = Date.now()
            var target = root.taskbar.clientWindows.find(function (w) {
              return root.taskbar.safeAddress(w.address) === root.job.target
            })
            var settleMs = root.needsResize ? (target && /firefox|zen/i.test(String(target.lastIpcObject.class)) ? 320 : 80) : 0
            if (Date.now() - root.readySince >= settleMs)
              root.finish("committed")
          } else if (!state.supported && Date.now() - root.dispatchedAt > 80)
            root.finish("unsupported-client")
          else
            root.readySince = 0
        } catch (error) {
          if (Date.now() - root.dispatchedAt > 80)
            root.finish("readiness-unavailable")
        }
      }
    }
  }

  LazyLoader {
    active: root.busy && root.needsResize && root.sourceScreen !== null
    PanelWindow {
      screen: root.sourceScreen
      anchors {
        top: true
        bottom: true
        left: true
        right: true
      }
      exclusionMode: ExclusionMode.Ignore
      color: "transparent"
      mask: Region {}
      WlrLayershell.namespace: "omarchy-taskbar-transition"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      ScreencopyView {
        id: screenCapture
        anchors.fill: parent
        captureSource: root.sourceScreen
        live: false
        paintCursor: false
        opacity: 0
        onHasContentChanged: {
          if (!hasContent)
            return
          var generation = root.generation
          grabToImage(function (result) {
            if (root.busy && root.generation === generation && !root.dispatched)
              root.coverImage = result
          })
        }
      }
      Image {
        id: frozenScreen
        anchors.fill: parent
        source: root.coverImage ? root.coverImage.url : ""
        fillMode: Image.Stretch
        onStatusChanged: {
          if (status !== Image.Ready || root.dispatched)
            return
          root.coverReady = true
          coverPaint.start()
        }
      }
      ScreencopyView {
        id: windowCapture
        width: sourceSize.width > 0 ? sourceSize.width : 468
        height: sourceSize.height > 0 ? sourceSize.height : 268
        opacity: 0
        captureSource: root.sourceWindow ? root.sourceWindow.wayland : null
        live: false
        paintCursor: false
        onHasContentChanged: {
          if (!hasContent || !root.sourceWindow)
            return
          var window = root.sourceWindow
          var w = sourceSize.width
          var h = sourceSize.height
          var scale = Math.min(1, 468 / Math.max(1, w), 268 / Math.max(1, h))
          grabToImage(function (result) {
            root.taskbar.rememberPreview(window, result, w, h)
          }, Qt.size(Math.max(1, Math.round(w * scale)), Math.max(1, Math.round(h * scale))))
        }
      }
    }
  }
}

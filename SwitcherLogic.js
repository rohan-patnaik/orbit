.pragma library

function safeAddress(value) {
  var address = String(value || "").trim()
  var match = /^(?:0x)?([0-9a-fA-F]+)$/.exec(address)
  return match ? "0x" + match[1].toLowerCase() : ""
}

function focusHistoryId(value) {
  var number = Number(value)
  return Number.isFinite(number) && number >= 0 ? number : 2147483647
}

function fullscreenState(value) {
  var number = Number(value)
  return Number.isInteger(number) && number >= 0 && number <= 3 ? number : 0
}

function resumableFullscreenState(internalState, clientState) {
  var internal = fullscreenState(internalState)
  return internal > 0 ? internal : fullscreenState(clientState)
}

function fullscreenHandoffPlan(sourceInternalState, targetInternalState, targetDesiredState) {
  var source = fullscreenState(sourceInternalState)
  var currentTarget = fullscreenState(targetInternalState)
  var desiredTarget = fullscreenState(targetDesiredState)
  var restoreTargetBeforeFocus = source > 0 && source === desiredTarget
  return {
    restoreTargetBeforeFocus: restoreTargetBeforeFocus,
    releaseSource: source > 0 && !restoreTargetBeforeFocus,
    targetResizes: currentTarget !== desiredTarget
  }
}

function dimensionsDiffer(firstWidth, firstHeight, secondWidth, secondHeight, tolerance) {
  var limit = Math.max(0, Number(tolerance) || 0)
  return Math.abs((Number(firstWidth) || 0) - (Number(secondWidth) || 0)) > limit
    || Math.abs((Number(firstHeight) || 0) - (Number(secondHeight) || 0)) > limit
}

function listIncludesNumber(values, value) {
  if (!Array.isArray(values)) return false
  var target = Number(value)
  for (var i = 0; i < values.length; i++) {
    if (Number(values[i]) === target) return true
  }
  return false
}

function listIncludesString(values, value) {
  if (!Array.isArray(values)) return false
  var target = String(value || "")
  if (!target) return false
  for (var i = 0; i < values.length; i++) {
    if (String(values[i] || "") === target) return true
  }
  return false
}

function isEligibleWindow(ipc, workspaceId, monitorName, monitorId, scope,
    visibleWorkspaceIds, visibleMonitorNames, visibleMonitorIds,
    activeWorkspaceId, activeMonitorName, activeMonitorId) {
  if (!ipc || ipc.mapped === false) return false
  var normalizedScope = normalizeScope(scope)
  var workspace = Number(workspaceId)
  if (normalizedScope === "all") return workspace > 0

  if (normalizedScope === "monitor") {
    if (workspace === Number(activeWorkspaceId)) return true
    if (ipc.pinned !== true) return false
    if (monitorName && activeMonitorName) return monitorName === activeMonitorName
    return Number(monitorId) === Number(activeMonitorId)
  }

  if (listIncludesNumber(visibleWorkspaceIds, workspace)) return true
  if (ipc.pinned !== true) return false
  if (listIncludesString(visibleMonitorNames, monitorName)) return true
  return listIncludesNumber(visibleMonitorIds, monitorId)
}

function sameWorkspace(first, second) {
  if (!first || !second) return true
  var firstId = Number(first.workspaceId)
  var secondId = Number(second.workspaceId)
  if (Number.isFinite(firstId) && Number.isFinite(secondId))
    return firstId === secondId
  return true
}

function sortByRecency(rows) {
  return rows.slice().sort(function(a, b) {
    var historyDifference = focusHistoryId(a.focusHistoryId)
      - focusHistoryId(b.focusHistoryId)
    if (historyDifference !== 0) return historyDifference
    return String(a.address).localeCompare(String(b.address))
  })
}

function friendlyAppName(value) {
  var text = String(value || "Application")
    .replace(/\.desktop$/i, "")
    .replace(/[._-]+/g, " ")
    .trim()
  if (!text) return "Application"
  return text.split(/\s+/).map(function(word) {
    return word.charAt(0).toUpperCase() + word.slice(1)
  }).join(" ")
}

function decorateDuplicateLabels(rows) {
  var counts = {}
  for (var i = 0; i < rows.length; i++) {
    var key = String(rows[i].appName || rows[i].applicationClass || "Application")
      .toLowerCase()
    counts[key] = (counts[key] || 0) + 1
  }

  var ordinals = {}
  return rows.map(function(row) {
    var copy = {}
    for (var property in row) copy[property] = row[property]
    var name = String(row.appName || friendlyAppName(row.applicationClass))
    var key = name.toLowerCase()
    ordinals[key] = (ordinals[key] || 0) + 1
    copy.label = counts[key] > 1 ? name + " " + ordinals[key] : name
    return copy
  })
}

function normalizeApplicationKey(value) {
  return String(value || "application")
    .replace(/\.desktop$/i, "")
    .trim()
    .toLowerCase()
}

function applicationEntries(rows) {
  if (!Array.isArray(rows)) return []
  var grouped = []
  var byKey = {}

  for (var i = 0; i < rows.length; i++) {
    var row = rows[i]
    var key = normalizeApplicationKey(row.appKey || row.applicationClass)
    var entry = byKey[key]
    if (!entry) {
      entry = {}
      for (var property in row) entry[property] = row[property]
      entry.appKey = key
      entry.label = String(row.appName || friendlyAppName(row.applicationClass))
      entry.memberAddresses = []
      entry.windowCount = 0
      byKey[key] = entry
      grouped.push(entry)
    }
    entry.memberAddresses.push(safeAddress(row.address))
    entry.windowCount++
  }

  return grouped
}

function entryIndexForAddress(rows, address) {
  if (!Array.isArray(rows)) return -1
  var normalized = safeAddress(address)
  for (var i = 0; i < rows.length; i++) {
    if (safeAddress(rows[i].address) === normalized) return i
    var members = rows[i].memberAddresses
    if (Array.isArray(members)) {
      for (var j = 0; j < members.length; j++) {
        if (safeAddress(members[j]) === normalized) return i
      }
    }
  }
  return -1
}

function appMonogram(value) {
  var words = String(value || "App").trim().split(/\s+/)
  if (words.length <= 1) return words[0].slice(0, 2).toUpperCase()
  return (words[0].charAt(0) + words[words.length - 1].charAt(0)).toUpperCase()
}

function initialSelection(rows, direction) {
  if (rows.length <= 1) return 0
  return Number(direction) < 0 ? rows.length - 1 : 1
}

function wrapIndex(index, length) {
  if (length <= 0) return -1
  return ((index % length) + length) % length
}

function groupIndex(grouped, address) {
  if (!Array.isArray(grouped)) return 0
  var normalized = safeAddress(address)
  for (var i = 0; i < grouped.length; i++) {
    if (safeAddress(grouped[i]) === normalized) return i + 1
  }
  return 0
}

function normalizeMode(value) {
  var mode = String(value || "").toLowerCase()
  return mode === "icons" || mode === "flip" || mode === "grid" ? mode : "grid"
}

function normalizeScope(value) {
  var scope = String(value || "").toLowerCase()
  return scope === "monitor" || scope === "all" || scope === "visible" ? scope : "visible"
}

function modeFromPluginEntries(entries, pluginId) {
  if (!Array.isArray(entries)) return "grid"
  var id = String(pluginId || "")
  for (var i = 0; i < entries.length; i++) {
    if (entries[i] && String(entries[i].id || "") === id)
      return normalizeMode(entries[i].mode)
  }
  return "grid"
}

function scopeFromPluginEntries(entries, pluginId) {
  if (!Array.isArray(entries)) return "visible"
  for (var i = 0; i < entries.length; i++) {
    if (String(entries[i].id || "") === String(pluginId || ""))
      return normalizeScope(entries[i].scope)
  }
  return "visible"
}

function snapLayouts() {
  return [
    { id: "halves", label: "Halves", slots: [
      { x: 0, y: 0, width: 0.5, height: 1 },
      { x: 0.5, y: 0, width: 0.5, height: 1 }
    ] },
    { id: "wide-left", label: "Two thirds", slots: [
      { x: 0, y: 0, width: 2 / 3, height: 1 },
      { x: 2 / 3, y: 0, width: 1 / 3, height: 1 }
    ] },
    { id: "main-left", label: "Main and stack", slots: [
      { x: 0, y: 0, width: 0.5, height: 1 },
      { x: 0.5, y: 0, width: 0.5, height: 0.5 },
      { x: 0.5, y: 0.5, width: 0.5, height: 0.5 }
    ] },
    { id: "thirds", label: "Thirds", slots: [
      { x: 0, y: 0, width: 1 / 3, height: 1 },
      { x: 1 / 3, y: 0, width: 1 / 3, height: 1 },
      { x: 2 / 3, y: 0, width: 1 / 3, height: 1 }
    ] },
    { id: "wide-center", label: "Wide center", slots: [
      { x: 0, y: 0, width: 0.25, height: 1 },
      { x: 0.25, y: 0, width: 0.5, height: 1 },
      { x: 0.75, y: 0, width: 0.25, height: 1 }
    ] },
    { id: "quarters", label: "Quarters", slots: [
      { x: 0, y: 0, width: 0.5, height: 0.5 },
      { x: 0.5, y: 0, width: 0.5, height: 0.5 },
      { x: 0, y: 0.5, width: 0.5, height: 0.5 },
      { x: 0.5, y: 0.5, width: 0.5, height: 0.5 }
    ] }
  ]
}

function snapGeometry(slot, monitor, outerGap, innerGap) {
  var safeSlot = slot || { x: 0, y: 0, width: 1, height: 1 }
  var safeMonitor = monitor || {}
  var scale = Number(safeMonitor.scale)
  if (!Number.isFinite(scale) || scale <= 0) scale = 1
  var reserved = Array.isArray(safeMonitor.reserved) ? safeMonitor.reserved : []
  var leftReserved = Number(reserved[0]) || 0
  var topReserved = Number(reserved[1]) || 0
  var rightReserved = Number(reserved[2]) || 0
  var bottomReserved = Number(reserved[3]) || 0
  var outer = Math.max(0, Number(outerGap) || 0)
  var inner = Math.max(0, Number(innerGap) || 0)
  var areaX = (Number(safeMonitor.x) || 0) + leftReserved + outer
  var areaY = (Number(safeMonitor.y) || 0) + topReserved + outer
  var areaWidth = Math.max(1, (Number(safeMonitor.width) || 1) / scale - leftReserved - rightReserved - outer * 2)
  var areaHeight = Math.max(1, (Number(safeMonitor.height) || 1) / scale - topReserved - bottomReserved - outer * 2)
  var startX = areaX + Number(safeSlot.x || 0) * areaWidth
  var startY = areaY + Number(safeSlot.y || 0) * areaHeight
  var endX = areaX + (Number(safeSlot.x || 0) + Number(safeSlot.width || 1)) * areaWidth
  var endY = areaY + (Number(safeSlot.y || 0) + Number(safeSlot.height || 1)) * areaHeight
  if (Number(safeSlot.x || 0) > 0) startX += inner / 2
  if (Number(safeSlot.y || 0) > 0) startY += inner / 2
  if (Number(safeSlot.x || 0) + Number(safeSlot.width || 1) < 0.9999) endX -= inner / 2
  if (Number(safeSlot.y || 0) + Number(safeSlot.height || 1) < 0.9999) endY -= inner / 2
  return {
    x: Math.round(startX),
    y: Math.round(startY),
    width: Math.max(1, Math.round(endX - startX)),
    height: Math.max(1, Math.round(endY - startY))
  }
}

function defaultWindowModes() {
  return {
    defaultMode: "maximized",
    tiled: true,
    floating: true,
    maximized: true,
    fullscreen: true,
    tiledFullscreen: true
  }
}

function normalizedWindowModes(value) {
  var defaults = defaultWindowModes()
  var source = value && typeof value === "object" ? value : {}
  var result = {
    defaultMode: String(source.defaultMode || defaults.defaultMode),
    tiled: source.tiled === undefined ? defaults.tiled : source.tiled === true,
    floating: source.floating === undefined ? defaults.floating : source.floating === true,
    maximized: source.maximized === undefined ? defaults.maximized : source.maximized === true,
    fullscreen: source.fullscreen === undefined ? defaults.fullscreen : source.fullscreen === true,
    tiledFullscreen: source.tiledFullscreen === undefined ? defaults.tiledFullscreen : source.tiledFullscreen === true
  }
  if (!result.tiled && !result.floating && !result.maximized)
    result.maximized = true
  if ((result.defaultMode !== "tiled" && result.defaultMode !== "floating" && result.defaultMode !== "maximized") || !result[result.defaultMode]) {
    result.defaultMode = result.maximized ? "maximized" : result.tiled ? "tiled" : "floating"
  }
  return result
}

function windowModesFromPluginEntries(entries, pluginId) {
  if (!Array.isArray(entries)) return defaultWindowModes()
  for (var i = 0; i < entries.length; i++) {
    if (String(entries[i].id || "") === String(pluginId || ""))
      return normalizedWindowModes(entries[i].windowModes)
  }
  return defaultWindowModes()
}

function toggleWindowMode(value, mode) {
  var current = normalizedWindowModes(value)
  if (!(mode in current) || mode === "defaultMode") return current
  var next = {}
  for (var key in current) next[key] = current[key]
  next[mode] = !next[mode]
  return normalizedWindowModes(next)
}

function previewAspect(width, height) {
  var w = Number(width)
  var h = Number(height)
  if (!Number.isFinite(w) || !Number.isFinite(h) || w <= 0 || h <= 0)
    return 16 / 9
  return Math.max(0.25, Math.min(5, w / h))
}

function rowPartitions(length, rowCount) {
  var results = []
  if (length <= 0 || rowCount <= 0 || rowCount > length) return results

  function visit(start, rowsLeft, breaks) {
    if (rowsLeft === 1) {
      results.push(breaks.concat([length]))
      return
    }
    var maximumEnd = length - rowsLeft + 1
    for (var end = start + 1; end <= maximumEnd; end++)
      visit(end, rowsLeft - 1, breaks.concat([end]))
  }

  visit(0, rowCount, [])
  return results
}

function aspectGridLayout(rows, availableWidth, availableHeight, spacing,
    horizontalPadding, fixedCardHeight, maximumPreviewHeight) {
  var source = Array.isArray(rows) ? rows : []
  if (source.length === 0) {
    return { items: [], width: 0, height: 0, rowCount: 0, previewHeight: 0 }
  }

  var maxWidth = Math.max(1, Number(availableWidth) || 1)
  var maxHeight = Math.max(1, Number(availableHeight) || 1)
  var gap = Math.max(0, Number(spacing) || 0)
  var padding = Math.max(0, Number(horizontalPadding) || 0)
  var fixedHeight = Math.max(0, Number(fixedCardHeight) || 0)
  var previewCap = Math.max(1, Number(maximumPreviewHeight) || 1)
  var aspects = source.map(function(row) {
    return previewAspect(row.previewWidth, row.previewHeight)
  })

  var best = null
  var maximumRows = Math.min(source.length, 4)
  for (var rowCount = 1; rowCount <= maximumRows; rowCount++) {
    var partitions = rowPartitions(source.length, rowCount)
    for (var p = 0; p < partitions.length; p++) {
      var ends = partitions[p]
      var start = 0
      var widthLimitedHeight = Number.POSITIVE_INFINITY
      var sums = []
      var counts = []

      for (var r = 0; r < ends.length; r++) {
        var end = ends[r]
        var aspectSum = 0
        for (var i = start; i < end; i++) aspectSum += aspects[i]
        var count = end - start
        var widthForPreviews = maxWidth - gap * Math.max(0, count - 1)
          - padding * 2 * count
        widthLimitedHeight = Math.min(widthLimitedHeight,
          widthForPreviews / Math.max(0.01, aspectSum))
        sums.push(aspectSum)
        counts.push(count)
        start = end
      }

      var heightLimitedHeight = (maxHeight - gap * Math.max(0, rowCount - 1)
        - fixedHeight * rowCount) / rowCount
      var previewHeight = Math.floor(Math.min(previewCap, widthLimitedHeight,
        heightLimitedHeight))
      if (previewHeight < 1) continue

      var rowWidths = sums.map(function(sum, index) {
        return sum * previewHeight + padding * 2 * counts[index]
          + gap * Math.max(0, counts[index] - 1)
      })
      var widest = Math.max.apply(Math, rowWidths)
      var narrowest = Math.min.apply(Math, rowWidths)
      var imbalance = widest - narrowest
      var candidate = {
        ends: ends,
        previewHeight: previewHeight,
        rowWidths: rowWidths,
        rowCount: rowCount,
        imbalance: imbalance
      }

      if (!best || candidate.previewHeight > best.previewHeight
          || (candidate.previewHeight === best.previewHeight
            && candidate.rowCount < best.rowCount)
          || (candidate.previewHeight === best.previewHeight
            && candidate.rowCount === best.rowCount
            && candidate.imbalance < best.imbalance)) {
        best = candidate
      }
    }
  }

  if (!best) {
    best = {
      ends: [source.length],
      previewHeight: 1,
      rowWidths: [maxWidth],
      rowCount: 1
    }
  }

  var layoutWidth = Math.min(maxWidth, Math.max.apply(Math, best.rowWidths))
  var cardHeight = best.previewHeight + fixedHeight
  var layoutHeight = best.rowCount * cardHeight
    + Math.max(0, best.rowCount - 1) * gap
  var items = []
  var itemStart = 0
  for (var rowIndex = 0; rowIndex < best.ends.length; rowIndex++) {
    var itemEnd = best.ends[rowIndex]
    var x = (layoutWidth - best.rowWidths[rowIndex]) / 2
    for (var itemIndex = itemStart; itemIndex < itemEnd; itemIndex++) {
      var cardWidth = aspects[itemIndex] * best.previewHeight + padding * 2
      items.push({
        index: itemIndex,
        row: rowIndex,
        x: x,
        y: rowIndex * (cardHeight + gap),
        width: cardWidth,
        height: cardHeight,
        centerX: x + cardWidth / 2
      })
      x += cardWidth + gap
    }
    itemStart = itemEnd
  }

  return {
    items: items,
    width: layoutWidth,
    height: layoutHeight,
    rowCount: best.rowCount,
    previewHeight: best.previewHeight
  }
}

function gridMoveByLayout(index, direction, items) {
  if (!Array.isArray(items) || items.length === 0) return -1
  var current = items[index]
  if (!current) return 0
  if (direction === "left") return wrapIndex(index - 1, items.length)
  if (direction === "right") return wrapIndex(index + 1, items.length)

  var rowCount = 0
  for (var i = 0; i < items.length; i++)
    rowCount = Math.max(rowCount, Number(items[i].row) + 1)
  var targetRow = direction === "up"
    ? wrapIndex(Number(current.row) - 1, rowCount)
    : wrapIndex(Number(current.row) + 1, rowCount)
  var bestIndex = index
  var bestDistance = Number.POSITIVE_INFINITY
  for (var j = 0; j < items.length; j++) {
    if (Number(items[j].row) !== targetRow) continue
    var distance = Math.abs(Number(items[j].centerX) - Number(current.centerX))
    if (distance < bestDistance) {
      bestDistance = distance
      bestIndex = j
    }
  }
  return bestIndex
}

function pageStart(index, pageSize) {
  if (index < 0 || pageSize <= 0) return 0
  return Math.floor(index / pageSize) * pageSize
}

function flipEntries(rows, selectedIndex, maximumVisible) {
  if (!rows || rows.length === 0 || maximumVisible <= 0) return []
  var count = Math.min(rows.length, maximumVisible)
  var before = Math.floor((count - 1) / 2)
  var after = count - before - 1
  var entries = []
  for (var offset = -before; offset <= after; offset++) {
    var index = wrapIndex(selectedIndex + offset, rows.length)
    entries.push({
      windowData: rows[index],
      windowIndex: index,
      offset: offset
    })
  }
  return entries
}

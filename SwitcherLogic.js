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

function isEligibleWindow(ipc, workspaceId, monitorName, monitorId,
    activeWorkspaceId, activeMonitorName, activeMonitorId) {
  if (!ipc || ipc.mapped === false) return false
  if (Number(workspaceId) === Number(activeWorkspaceId)) return true
  if (ipc.pinned !== true) return false
  if (monitorName && activeMonitorName) return monitorName === activeMonitorName
  return Number(monitorId) === Number(activeMonitorId)
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

function initialSelection(rows) {
  return rows.length > 1 ? 1 : 0
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

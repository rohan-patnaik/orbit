const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const source = fs.readFileSync(path.join(__dirname, "..", "SwitcherLogic.js"), "utf8")
  .replace(/^\.pragma library\s*$/m, "");
const logic = {};
vm.createContext(logic);
vm.runInContext(source, logic);

test("safeAddress accepts only Hyprland hexadecimal addresses", () => {
  assert.equal(logic.safeAddress("0xABC123"), "0xabc123");
  assert.equal(logic.safeAddress("ABC123"), "0xabc123");
  assert.equal(logic.safeAddress('0x12" })'), "");
  assert.equal(logic.safeAddress("address:0x12"), "");
});

test("fullscreen state normalization preserves valid Hyprland states", () => {
  assert.equal(logic.fullscreenState(0), 0);
  assert.equal(logic.fullscreenState(3), 3);
  assert.equal(logic.fullscreenState(-1), 0);
  assert.equal(logic.fullscreenState(4), 0);
  assert.equal(logic.fullscreenState("2"), 2);
  assert.equal(logic.resumableFullscreenState(2, 1), 2);
  assert.equal(logic.resumableFullscreenState(0, 2), 2);
  assert.equal(logic.resumableFullscreenState(0, 0), 0);
});

test("fullscreen handoff restores matching target state before focus transfer", () => {
  assert.deepEqual(
    JSON.parse(JSON.stringify(logic.fullscreenHandoffPlan(1, 1, 1))),
    { restoreTargetBeforeFocus: true, releaseSource: false, targetResizes: false }
  );
  assert.deepEqual(
    JSON.parse(JSON.stringify(logic.fullscreenHandoffPlan(2, 0, 2))),
    { restoreTargetBeforeFocus: true, releaseSource: false, targetResizes: true }
  );
  assert.deepEqual(
    JSON.parse(JSON.stringify(logic.fullscreenHandoffPlan(2, 1, 1))),
    { restoreTargetBeforeFocus: false, releaseSource: true, targetResizes: false }
  );
  assert.deepEqual(
    JSON.parse(JSON.stringify(logic.fullscreenHandoffPlan(1, 0, 0))),
    { restoreTargetBeforeFocus: false, releaseSource: true, targetResizes: false }
  );
  assert.equal(logic.dimensionsDiffer(1896, 1030, 1896, 1030, 2), false);
  assert.equal(logic.dimensionsDiffer(1896, 1030, 941, 508, 2), true);
});

test("visible scope includes every monitor's active workspace", () => {
  const visibleWorkspaces = [1, 2];
  const visibleMonitorNames = ["eDP-1", "HDMI-A-1"];
  const visibleMonitorIds = [0, 1];
  assert.equal(logic.isEligibleWindow({ mapped: true }, 1, "HDMI-A-1", 1, "visible", visibleWorkspaces, visibleMonitorNames, visibleMonitorIds, 1, "HDMI-A-1", 1), true);
  assert.equal(logic.isEligibleWindow({ mapped: true }, 2, "eDP-1", 0, "visible", visibleWorkspaces, visibleMonitorNames, visibleMonitorIds, 1, "HDMI-A-1", 1), true);
  assert.equal(logic.isEligibleWindow({ mapped: true }, 3, "eDP-1", 0, "visible", visibleWorkspaces, visibleMonitorNames, visibleMonitorIds, 1, "HDMI-A-1", 1), false);
  assert.equal(logic.isEligibleWindow({ mapped: true, pinned: true }, 3, "eDP-1", 0, "visible", visibleWorkspaces, visibleMonitorNames, visibleMonitorIds, 1, "HDMI-A-1", 1), true);
  assert.equal(logic.isEligibleWindow({ mapped: false }, 2, "eDP-1", 0, "visible", visibleWorkspaces, visibleMonitorNames, visibleMonitorIds, 1, "HDMI-A-1", 1), false);
});

test("monitor and all-workspace scopes preserve their intended boundaries", () => {
  assert.equal(logic.isEligibleWindow({ mapped: true }, 1, "HDMI-A-1", 1, "monitor", [1, 2], ["eDP-1", "HDMI-A-1"], [0, 1], 1, "HDMI-A-1", 1), true);
  assert.equal(logic.isEligibleWindow({ mapped: true }, 2, "eDP-1", 0, "monitor", [1, 2], ["eDP-1", "HDMI-A-1"], [0, 1], 1, "HDMI-A-1", 1), false);
  assert.equal(logic.isEligibleWindow({ mapped: true }, 8, "eDP-1", 0, "all", [], [], [], 1, "HDMI-A-1", 1), true);
  assert.equal(logic.isEligibleWindow({ mapped: true }, -99, "eDP-1", 0, "all", [], [], [], 1, "HDMI-A-1", 1), false);
  assert.equal(logic.normalizeScope("unexpected"), "visible");
});

test("fullscreen handoffs only couple windows on the same workspace", () => {
  assert.equal(logic.sameWorkspace({ workspaceId: 1 }, { workspaceId: 1 }), true);
  assert.equal(logic.sameWorkspace({ workspaceId: 1 }, { workspaceId: 2 }), false);
  assert.equal(logic.sameWorkspace({}, {}), true);
});

test("windows are sorted by focus history", () => {
  const rows = logic.sortByRecency([
    { address: "0x3", focusHistoryId: 2 },
    { address: "0x1", focusHistoryId: 0 },
    { address: "0x2", focusHistoryId: 1 }
  ]);
  assert.deepEqual(Array.from(rows, row => row.address), ["0x1", "0x2", "0x3"]);
  assert.equal(logic.initialSelection(rows, 1), 1);
  assert.equal(logic.initialSelection(rows, -1), 2);
});

test("duplicate application labels receive stable ordinals", () => {
  const rows = logic.decorateDuplicateLabels([
    { appName: "Firefox", address: "0x1" },
    { appName: "Firefox", address: "0x2" },
    { appName: "Terminal", address: "0x3" }
  ]);
  assert.deepEqual(Array.from(rows, row => row.label), ["Firefox 1", "Firefox 2", "Terminal"]);
});

test("icon mode groups windows by application and preserves MRU representatives", () => {
  const entries = logic.applicationEntries([
    { appKey: "firefox", appName: "Firefox", address: "0x1", title: "Recent" },
    { appKey: "terminal", appName: "Terminal", address: "0x2", title: "Shell" },
    { appKey: "firefox", appName: "Firefox", address: "0x3", title: "Older" }
  ]);
  assert.equal(entries.length, 2);
  assert.equal(entries[0].address, "0x1");
  assert.deepEqual(Array.from(entries[0].memberAddresses), ["0x1", "0x3"]);
  assert.equal(entries[0].windowCount, 2);
  assert.equal(logic.entryIndexForAddress(entries, "0x3"), 0);
  assert.equal(logic.appMonogram("Visual Studio Code"), "VC");
});

test("selection wraps in both directions", () => {
  assert.equal(logic.wrapIndex(3, 3), 0);
  assert.equal(logic.wrapIndex(-1, 3), 2);
  assert.equal(logic.wrapIndex(0, 0), -1);
});

test("groupIndex returns a one-based group position", () => {
  assert.equal(logic.groupIndex(["0x1", "0x2"], "0x2"), 2);
  assert.equal(logic.groupIndex([], "0x2"), 0);
});

test("modes normalize to the grid default", () => {
  assert.equal(logic.normalizeMode("icons"), "icons");
  assert.equal(logic.normalizeMode("flip"), "flip");
  assert.equal(logic.normalizeMode("GRID"), "grid");
  assert.equal(logic.normalizeMode("unknown"), "grid");
});

test("persisted mode comes from the matching plugin entry", () => {
  const entries = [
    { id: "another.plugin", mode: "icons" },
    { id: "io.github.rohan-patnaik.window-switcher", mode: "flip" }
  ];
  assert.equal(logic.modeFromPluginEntries(entries, "io.github.rohan-patnaik.window-switcher"), "flip");
  assert.equal(logic.modeFromPluginEntries([{ id: "io.github.rohan-patnaik.window-switcher", mode: "invalid" }], "io.github.rohan-patnaik.window-switcher"), "grid");
  assert.equal(logic.modeFromPluginEntries([], "io.github.rohan-patnaik.window-switcher"), "grid");
});

test("persisted scope comes from the matching plugin entry", () => {
  const entries = [
    { id: "another.plugin", scope: "monitor" },
    { id: "io.github.rohan-patnaik.window-switcher", scope: "all" }
  ];
  assert.equal(logic.scopeFromPluginEntries(entries, "io.github.rohan-patnaik.window-switcher"), "all");
  assert.equal(logic.scopeFromPluginEntries([{ id: "io.github.rohan-patnaik.window-switcher", scope: "bad" }], "io.github.rohan-patnaik.window-switcher"), "visible");
  assert.equal(logic.scopeFromPluginEntries([], "io.github.rohan-patnaik.window-switcher"), "visible");
});

test("Alt+Tab targets the primary display independently of the focused display", () => {
  const monitors = [
    { id: 0, name: "eDP-1", x: -1280, y: 0, width: 1920, height: 1080, scale: 1.5 },
    { id: 1, name: "HDMI-A-1", x: 0, y: 0, width: 1920, height: 1080, scale: 1 }
  ];
  const id = "io.github.rohan-patnaik.window-switcher";
  assert.equal(logic.primaryMonitorName(monitors), "HDMI-A-1");
  assert.equal(logic.overlayMonitorName([], id, monitors, "eDP-1"), "HDMI-A-1");
  assert.equal(logic.overlayMonitorName([{ id, overlayMonitor: "focused" }], id, monitors, "eDP-1"), "eDP-1");
  assert.equal(logic.overlayMonitorName([{ id, overlayMonitor: "HDMI-A-1" }], id, monitors, "eDP-1"), "HDMI-A-1");
  assert.equal(logic.overlayMonitorName([{ id, overlayMonitor: "missing" }], id, monitors, "eDP-1"), "HDMI-A-1");
});

test("Windows snap layouts expose six scale-aware arrangements", () => {
  const layouts = logic.snapLayouts();
  assert.equal(layouts.length, 6);
  assert.equal(layouts[0].slots.length, 2);
  assert.equal(layouts[5].slots.length, 4);
  const left = logic.snapGeometry(layouts[0].slots[0], {
    x: -1280, y: 0, width: 1920, height: 1080, scale: 1.5,
    reserved: [0, 0, 0, 26]
  }, 10, 10);
  const right = logic.snapGeometry(layouts[0].slots[1], {
    x: -1280, y: 0, width: 1920, height: 1080, scale: 1.5,
    reserved: [0, 0, 0, 26]
  }, 10, 10);
  assert.deepEqual(JSON.parse(JSON.stringify(left)), { x: -1270, y: 10, width: 625, height: 674 });
  assert.deepEqual(JSON.parse(JSON.stringify(right)), { x: -635, y: 10, width: 625, height: 674 });
});

test("window mode policy always retains a valid normal launch mode", () => {
  const modes = logic.normalizedWindowModes({
    defaultMode: "tiled", tiled: false, floating: false, maximized: false,
    fullscreen: false, tiledFullscreen: false
  });
  assert.equal(modes.maximized, true);
  assert.equal(modes.defaultMode, "maximized");
  const toggled = logic.toggleWindowMode(logic.defaultWindowModes(), "maximized");
  assert.equal(toggled.maximized, false);
  assert.equal(toggled.defaultMode, "tiled");
  const entries = [{ id: "io.github.rohan-patnaik.window-switcher", windowModes: {
    defaultMode: "floating", tiled: false, floating: true, maximized: false
  } }];
  assert.equal(logic.windowModesFromPluginEntries(entries, "io.github.rohan-patnaik.window-switcher").defaultMode, "floating");
});

test("grid geometry preserves source aspect ratios and navigation wraps", () => {
  const rows = [
    { previewWidth: 1600, previewHeight: 900 },
    { previewWidth: 900, previewHeight: 900 },
    { previewWidth: 500, previewHeight: 900 },
    { previewWidth: 1200, previewHeight: 900 }
  ];
  const layout = logic.aspectGridLayout(rows, 900, 500, 12, 8, 52, 220);
  assert.equal(layout.items.length, rows.length);
  assert.ok(layout.width <= 900);
  assert.ok(layout.height <= 500);
  for (const item of layout.items) {
    const expectedAspect = rows[item.index].previewWidth / rows[item.index].previewHeight;
    assert.ok(Math.abs((item.width - 16) / layout.previewHeight - expectedAspect) < 0.001);
  }
  assert.equal(logic.gridMoveByLayout(0, "left", layout.items), 3);
  assert.equal(logic.gridMoveByLayout(3, "right", layout.items), 0);
  const down = logic.gridMoveByLayout(0, "down", layout.items);
  assert.notEqual(layout.items[down].row, layout.items[0].row);
  assert.equal(logic.pageStart(13, 12), 12);
});

test("flip mode instantiates at most seven unique neighboring windows", () => {
  const rows = Array.from({ length: 10 }, (_, index) => ({ address: `0x${index + 1}` }));
  const entries = logic.flipEntries(rows, 0, 7);
  assert.equal(entries.length, 7);
  assert.deepEqual(Array.from(entries, entry => entry.offset), [-3, -2, -1, 0, 1, 2, 3]);
  assert.equal(new Set(Array.from(entries, entry => entry.windowIndex)).size, 7);
  assert.equal(entries.find(entry => entry.offset === 0).windowIndex, 0);
});

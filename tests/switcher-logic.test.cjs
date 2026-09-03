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

test("eligibility is limited to the current workspace or visible pinned windows", () => {
  assert.equal(logic.isEligibleWindow({ mapped: true }, 2, "DP-1", 1, 2, "DP-1", 1), true);
  assert.equal(logic.isEligibleWindow({ mapped: true }, 3, "DP-1", 1, 2, "DP-1", 1), false);
  assert.equal(logic.isEligibleWindow({ mapped: true, pinned: true }, 3, "DP-1", 1, 2, "DP-1", 1), true);
  assert.equal(logic.isEligibleWindow({ mapped: false }, 2, "DP-1", 1, 2, "DP-1", 1), false);
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

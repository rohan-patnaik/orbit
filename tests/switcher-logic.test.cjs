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

test("grid geometry is bounded and navigation wraps", () => {
  assert.equal(logic.gridColumns(3, 1200), 2);
  assert.equal(logic.gridColumns(8, 1200), 4);
  assert.equal(logic.gridColumns(8, 600), 2);
  assert.equal(logic.gridMove(1, "down", 6, 3), 4);
  assert.equal(logic.gridMove(0, "up", 6, 3), 3);
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

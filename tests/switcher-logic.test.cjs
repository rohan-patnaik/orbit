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
  assert.equal(logic.initialSelection(rows), 1);
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

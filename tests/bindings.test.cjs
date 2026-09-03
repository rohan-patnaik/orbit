const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const root = path.resolve(__dirname, "..");
const bindings = fs.readFileSync(path.join(root, "bindings.lua"), "utf8");
const overlay = fs.readFileSync(path.join(root, "Overlay.qml"), "utf8");

test("Orbit owns Alt+Tab and preserves stock cycling on Super+Q", () => {
  assert.match(bindings, /hl\.unbind\("ALT \+ TAB"\)/);
  assert.match(bindings, /hl\.unbind\("ALT \+ SHIFT \+ TAB"\)/);
  assert.match(bindings, /"ALT \+ TAB"[\s\S]*omarchy-window-switcher:next/);
  assert.match(bindings, /"ALT \+ SHIFT \+ TAB"[\s\S]*omarchy-window-switcher:previous/);
  assert.match(bindings, /"SUPER \+ Q"[\s\S]*hl\.dsp\.window\.cycle_next\(\)/);
  assert.match(bindings, /"SUPER \+ SHIFT \+ Q"[\s\S]*cycle_next\(\{ next = false \}\)/);
});

test("the overlay cycles backward and activates when Alt is released", () => {
  assert.match(overlay, /name: "previous"[\s\S]*root\.invokeShortcut\(-1\)/);
  assert.match(overlay, /hl\.is_key_down\("Alt_L"\)[\s\S]*hl\.is_key_down\("Alt_R"\)/);
  assert.match(overlay, /event\.key === Qt\.Key_Alt/);
  assert.match(overlay, /root\.releaseModifier === "alt" \? altReleased/);
});

test("the overlay snapshots the compositor MRU order before opening", () => {
  assert.match(overlay, /command: \["hyprctl", "-j", "clients"\]/);
  assert.match(overlay, /JSON\.parse\(text\)/);
  assert.match(overlay, /focusHistoryID/);
  assert.match(overlay, /queuedSteps/);
  assert.doesNotMatch(overlay, /lastIpcObject/);
});

test("window activation preserves each app's compositor and client fullscreen state", () => {
  assert.match(overlay, /fullscreenState: Logic\.fullscreenState\(ipc\.fullscreen\)/);
  assert.match(overlay, /clientFullscreenState: Logic\.fullscreenState\(ipc\.fullscreenClient\)/);
  assert.match(overlay, /fullscreen_state\(\{ internal = 0, client = -1/);
  assert.match(overlay, /root\.prepareFullscreenHandoff/);
  assert.match(overlay, /root\.restoreSelectedFullscreen\(\)/);
});

test("fullscreen handoff stays covered and disables transient layout animation", () => {
  assert.match(overlay, /root\.activationCommitInProgress = true/);
  assert.match(overlay, /id: activationCommitTimer[\s\S]*root\.advanceActivationCommit\(\)/);
  assert.match(overlay, /root\.activationCommitInProgress \? WlrKeyboardFocus\.None : WlrKeyboardFocus\.Exclusive/);
  assert.match(overlay, /function requestPendingActivation\(\)[\s\S]*internal = 0, client = -1[\s\S]*hl\.dsp\.focus[\s\S]*root\.restoreSelectedFullscreen\(\)/);
  assert.match(overlay, /set_prop\(\{ prop = "no_anim", value = "true"/);
  assert.match(overlay, /set_prop\(\{ prop = "no_anim", value = "unset"/);
  assert.match(overlay, /root\.finishActivationCommit\(\)[\s\S]*root\.opened = false/);
  assert.doesNotMatch(overlay, /id: fullscreenRestoreTimer/);
});

test("icon mode uses desktop metadata and groups application windows", () => {
  assert.match(overlay, /DesktopEntries\.heuristicLookup/);
  assert.match(overlay, /Logic\.applicationEntries/);
  assert.doesNotMatch(overlay, /application-x-executable/);
});

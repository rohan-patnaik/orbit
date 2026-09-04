const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const root = path.resolve(__dirname, "..");
const bindings = fs.readFileSync(path.join(root, "bindings.lua"), "utf8");
const overlay = fs.readFileSync(path.join(root, "Overlay.qml"), "utf8");
const windowCard = fs.readFileSync(path.join(root, "components", "WindowCard.qml"), "utf8");

test("Orbit owns Alt+Tab and preserves stock cycling on Super+Q", () => {
  assert.match(bindings, /hl\.unbind\("ALT \+ TAB"\)/);
  assert.match(bindings, /hl\.unbind\("ALT \+ SHIFT \+ TAB"\)/);
  assert.match(bindings, /"ALT \+ TAB"[\s\S]*omarchy-window-switcher:next/);
  assert.match(bindings, /"ALT \+ SHIFT \+ TAB"[\s\S]*omarchy-window-switcher:previous/);
  assert.match(bindings, /"SUPER \+ Q"[\s\S]*hl\.dsp\.window\.cycle_next\(\)/);
  assert.match(bindings, /"SUPER \+ SHIFT \+ Q"[\s\S]*cycle_next\(\{ next = false \}\)/);
});

test("Orbit exposes Windows-style snap layouts and a window-mode policy", () => {
  assert.match(bindings, /orbit_window_modes/);
  assert.match(bindings, /o\.window\("\.\*", \{ maximize = true \}\)/);
  assert.match(bindings, /hl\.unbind\("SUPER \+ T"\)/);
  assert.match(bindings, /hl\.unbind\("SUPER \+ F"\)/);
  assert.match(bindings, /hl\.unbind\("SUPER \+ CTRL \+ F"\)/);
  assert.match(bindings, /hl\.unbind\("SUPER \+ ALT \+ F"\)/);
  assert.match(bindings, /"SUPER \+ Z"[\s\S]*omarchy-window-switcher:snap/);
  assert.match(bindings, /"SUPER \+ SHIFT \+ Z"[\s\S]*omarchy-window-switcher:settings/);
});

test("snap placement uses exact-address compositor operations and Snap Assist", () => {
  assert.match(overlay, /name: "snap"[\s\S]*root\.openSnapManager\(\)/);
  assert.match(overlay, /fullscreen_state\(\{ internal = 0, client = 0/);
  assert.match(overlay, /window\.float\(\{ action = "set"/);
  assert.match(overlay, /window\.move\(\{ x = '[^\n]*relative = false/);
  assert.match(overlay, /window\.resize\(\{ x = '[^\n]*relative = false/);
  assert.match(overlay, /root\.managerMode = "assist"/);
  assert.match(overlay, /root\.snapAssistCandidates\.filter/);
});

test("plugin settings are merged so mode, scope, and window policy survive each save", () => {
  assert.match(overlay, /function currentPluginSettings\(\)/);
  assert.match(overlay, /function persistPluginSettings\(changes\)/);
  assert.match(overlay, /root\.persistPluginSettings\(\{\s*mode: nextMode\s*\}\)/);
  assert.match(overlay, /root\.persistPluginSettings\(\{\s*windowModes: root\.windowModes\s*\}\)/);
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

test("exact-address activation raises the focused window and waits for confirmation", () => {
  assert.match(
    overlay,
    /hl\.dsp\.focus\(\{ window = "address:' \+ selected\.address[\s\S]*hl\.dsp\.window\.bring_to_top\(\)/
  );
  assert.match(overlay, /activationCommitAttempts < root\.activationCommitAttemptLimit/);
  assert.match(overlay, /root\.abortActivationCommit\(\)[\s\S]*return/);
  assert.match(overlay, /selected window did not accept focus; keeping Orbit open/);
});

test("the selected window is raised again after the keyboard-grabbing layer unmaps", () => {
  assert.match(
    overlay,
    /function finishActivationCommit\(\)[\s\S]*root\.opened = false[\s\S]*activationFinalizeTimer\.restart\(\)/
  );
  assert.match(
    overlay,
    /function finalizeActivationCommit\(\)[\s\S]*root\.releaseHandoffAnimations\(\)[\s\S]*root\.raisePendingWindow\(\)/
  );
  assert.match(overlay, /id: activationFinalizeTimer[\s\S]*interval: 32/);
});

test("fullscreen handoff stays covered and disables transient layout animation", () => {
  assert.match(overlay, /root\.activationCommitInProgress = true/);
  assert.match(overlay, /id: activationCommitTimer[\s\S]*root\.advanceActivationCommit\(\)/);
  assert.match(overlay, /root\.activationCommitInProgress \? WlrKeyboardFocus\.None : WlrKeyboardFocus\.Exclusive/);
  assert.match(overlay, /function requestPendingActivation\(\)[\s\S]*internal = 0, client = -1[\s\S]*root\.raisePendingWindow\(\)[\s\S]*root\.restoreSelectedFullscreen\(\)/);
  assert.match(overlay, /function raisePendingWindow\(\)[\s\S]*hl\.dsp\.focus/);
  assert.match(overlay, /set_prop\(\{ prop = "no_anim", value = "true"/);
  assert.match(overlay, /set_prop\(\{ prop = "no_anim", value = "unset"/);
  assert.match(overlay, /root\.finishActivationCommit\(\)[\s\S]*root\.opened = false/);
  assert.doesNotMatch(overlay, /id: fullscreenRestoreTimer/);
});

test("resize-sensitive clients remain covered until their restored surface settles", () => {
  assert.match(overlay, /root\.handoffRestoresTargetFirst = handoff\.restoreTargetBeforeFocus/);
  assert.match(overlay, /root\.handoffNeedsCover = handoff\.targetResizes && !targetAlreadyMatchesSourceSize/);
  assert.match(overlay, /id: activationSettleTimer[\s\S]*interval: 1600/);
  assert.match(overlay, /id: activationRevealTimer[\s\S]*interval: 80/);
  assert.match(overlay, /readonly property var captureWindow: root\.windows\.length > 0 \? root\.windows\[0\] : null/);
  assert.match(overlay, /id: outgoingCapture[\s\S]*captureSource: captureWindow \? captureWindow\.wayland : null/);
  assert.match(overlay, /sourceItem: outgoingCapture[\s\S]*hideSource: true[\s\S]*live: !root\.activationCommitInProgress/);
  assert.match(overlay, /id: targetReadyProbe[\s\S]*live: true[\s\S]*onSourceSizeChanged: root\.observeActivationTargetSurface/);
  assert.match(overlay, /if \(root\.activationTargetSurfaceReady\)[\s\S]*return[\s\S]*activationRevealTimer\.restart\(\)/);
});

test("window previews do not disable their own screencopy source", () => {
  assert.match(windowCard, /opacity: hasContent \? 1 : 0/);
  assert.doesNotMatch(windowCard, /visible: hasContent/);
});

test("icon mode uses desktop metadata and groups application windows", () => {
  assert.match(overlay, /DesktopEntries\.heuristicLookup/);
  assert.match(overlay, /Logic\.applicationEntries/);
  assert.doesNotMatch(overlay, /application-x-executable/);
});

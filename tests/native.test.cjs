const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const root = path.resolve(__dirname, "..");
const source = fs.readFileSync(path.join(root, "native", "orbit_drag.cpp"), "utf8");
const bindings = fs.readFileSync(path.join(root, "bindings.lua"), "utf8");
const hyprpm = fs.readFileSync(path.join(root, "hyprpm.toml"), "utf8");

test("native drag bridge is ABI-guarded and uses typed compositor drag events", () => {
  assert.match(source, /__hyprland_api_get_hash\(\)/);
  assert.match(source, /__hyprland_api_get_client_hash\(\)/);
  assert.match(source, /dragController\(\)/);
  assert.match(source, /controller->mode\(\) != MBIND_MOVE/);
  assert.match(source, /controller->dragThresholdReached\(\)/);
  assert.match(source, /m_events\.input\.mouse\.move\.listen/);
  assert.match(source, /WL_POINTER_BUTTON_STATE_RELEASED/);
  assert.match(source, /sendGlobalShortcutEvent\("omarchy-window-switcher", "snap"/);
});

test("the shell bindings remain independent from the optional in-process bridge", () => {
  assert.doesNotMatch(bindings, /hl\.plugin\.load/);
  assert.match(bindings, /omarchy-window-switcher:snap/);
});

test("repository exposes the native bridge to hyprpm", () => {
  assert.match(hyprpm, /\[repository\]/);
  assert.match(hyprpm, /\[orbit-drag\]/);
  assert.match(hyprpm, /output = "native\/orbit-drag\.so"/);
  assert.match(hyprpm, /make -C native clean all/);
});

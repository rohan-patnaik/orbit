const test = require('node:test');
const assert = require('node:assert/strict');
const { overlay, logic } = require('./overlay-harness.cjs');
const id = 'io.github.rohan-patnaik.window-switcher';
const json = value => JSON.stringify(value);
const app = { address: '0xa', class: 'firefox', monitor: 1, workspace: { id: 1 }, mapped: true, size: [800, 600], focusHistoryID: 0 };

test('existing and fresh installations enable the dock and all three views', () => {
  assert.deepEqual(JSON.parse(json(logic.featuresFromPluginEntries([], id))), { dock: true, grid: true, flip: true, icons: true, taskManager: true });
  assert.deepEqual(Array.from(logic.enabledViews({ dock: false })), ['grid', 'flip', 'icons']);
  assert.deepEqual(JSON.parse(json(logic.normalizedFeatures({ grid: 'false', flip: false, icons: null, unknown: false }))), { dock: true, grid: true, flip: false, icons: true, taskManager: true });
});

test('disabled saved view falls back to an enabled view; toggles are independent', () => {
  const entries = [{ id, mode: 'grid', features: { grid: false, icons: false } }];
  assert.equal(logic.modeFromPluginEntries(entries, id), 'flip');
  const next = logic.toggledFeature(logic.featuresFromPluginEntries(entries, id), 'dock');
  assert.equal(next.dock, false);
  assert.equal(next.grid, false);
  assert.equal(next.flip, true);
  assert.equal(next.icons, false);
  assert.deepEqual(Array.from(logic.enabledViews(logic.toggledFeature(next, 'invalid'))), ['flip']);
});

test('numeric/API selection cannot enter a disabled view or disturb window selection', () => {
  const { root } = overlay({ mode: 'flip', selectedIndex: 1, windows: [{ address: '0xa' }, { address: '0xb' }], shell: { shellConfig: { plugins: [{ id, features: { grid: false, icons: false } }] } } });
  assert.equal(root.setMode('grid'), 'flip');
  assert.equal(root.setMode('icons'), 'flip');
  assert.equal(root.entries[root.selectedIndex].address, '0xb');
});

test('all views off performs the actual MRU activation without mapping a picker', () => {
  const { root } = overlay({ shell: { shellConfig: { plugins: [{ id, features: { grid: false, flip: false, icons: false } }] } } });
  root.startSwitcher(true, 'alt', 1, 'native');
  assert.equal(root.pendingGestureReleased, true);
  root.completeWindowQuery(json([app, { ...app, address: '0xb', focusHistoryID: 1 }]));
  assert.equal(root.pendingWindow.address, '0xb');
  assert.equal(root.activationCommitInProgress, true);
  assert.equal(root.pickerPresented, false);
  root.presentPicker();
  assert.equal(root.pickerPresented, false);
});

test('Apply preserves unrelated plugin preferences and saves features atomically', () => {
  const saved = [];
  const entry = { id, mode: 'grid', scope: 'all', overlayMonitor: 'focused', futurePreference: { keep: true }, features: { grid: true, flip: true, icons: true, dock: true } };
  const { root, env } = overlay({ mode: 'grid', managerMode: 'settings', featuresDraft: { dock: false, grid: false, flip: true, icons: false }, settingsDraft: logic.defaultWindowModes(), shell: { shellConfig: { plugins: [entry] }, updateEntryInline: (key, value) => { saved.push({ key, value: JSON.parse(json(value)) }); return true; } } });
  assert.equal(root.applyWindowModeSettings(), true);
  assert.equal(saved.length, 1);
  assert.equal(saved[0].value.scope, 'all');
  assert.equal(saved[0].value.overlayMonitor, 'focused');
  assert.equal(saved[0].value.futurePreference.keep, true);
  assert.equal(saved[0].value.mode, 'flip');
  assert.equal(saved[0].value.features.dock, false);
  assert.equal(root.managerMode, '');
  assert.notEqual(env.settingsReload.running, true, 'view/dock-only changes do not reload compositor bindings');
});

test('failed save retains the editable dialog and active policy', () => {
  const { root } = overlay({ mode: 'grid', managerMode: 'settings', featuresDraft: { dock: false }, settingsDraft: logic.defaultWindowModes(), shell: { shellConfig: { plugins: [{ id, scope: 'all' }] }, updateEntryInline: () => false } });
  assert.equal(root.applyWindowModeSettings(), false);
  assert.equal(root.managerMode, 'settings');
  assert.equal(root.mode, 'grid');
  assert.match(root.settingsError, /Could not save/);
});

test('watched scoped-facade preferences remain authoritative without shellConfig', () => {
  const { root } = overlay({ settingsLoaded: true, savedPluginEntries: [{ id, mode: 'icons', features: { icons: false, grid: false }, scope: 'all', keep: 9 }], shell: {} });
  assert.equal(root.configuredMode(), 'flip');
  assert.equal(root.configuredScope(), 'all');
  assert.equal(root.currentPluginSettings().keep, 9);
});


test('Task Manager defaults on, toggles independently and persists without reload', () => {
  const flags = logic.featuresFromPluginEntries([{ id, features: { dock: false } }], id);
  assert.equal(flags.taskManager, true);
  const next = logic.toggledFeature(flags, 'taskManager');
  assert.equal(next.taskManager, false);
  assert.equal(next.dock, false);
  assert.deepEqual(JSON.parse(json(logic.enabledViews(next))), ['grid', 'flip', 'icons']);
  const saved = [];
  const { root, env } = overlay({ mode: 'grid', managerMode: 'settings', featuresDraft: next,
    settingsDraft: logic.defaultWindowModes(), shell: { shellConfig: { plugins: [{ id }] },
      updateEntryInline: (key, value) => { saved.push(value); return true; } } });
  assert.equal(root.applyWindowModeSettings(), true);
  assert.equal(saved[0].features.taskManager, false);
  assert.notEqual(env.settingsReload.running, true);
});

const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const test = require('node:test');
const { overlay, logic } = require('./overlay-harness.cjs');

const pluginId = 'io.github.rohan-patnaik.window-switcher';
const normalModes = ['tiled', 'floating', 'maximized'];
const flags = [...normalModes, 'fullscreen', 'tiledFullscreen', 'maximizeOnSwitch'];

test('every mode combination retains an enabled normal default and respects disabled snap modes', () => {
  for (let mask = 0; mask < 1 << flags.length; mask++) {
    for (const defaultMode of [...normalModes, 'fullscreen', 'invalid']) {
      const input = { defaultMode };
      flags.forEach((flag, index) => { input[flag] = Boolean(mask & (1 << index)); });
      const policy = logic.normalizedWindowModes(input);
      assert.ok(normalModes.includes(policy.defaultMode));
      assert.equal(policy[policy.defaultMode], true);
      assert.ok(normalModes.some(mode => policy[mode]));
      if (!policy.maximized) assert.equal(policy.maximizeOnSwitch, false);
      for (const layout of logic.availableSnapLayouts(policy))
        assert.equal(policy[layout.action || 'floating'], true);
      for (const flag of flags) {
        const changed = logic.toggleWindowMode(policy, flag);
        assert.equal(changed[changed.defaultMode], true);
        assert.ok(normalModes.some(mode => changed[mode]));
      }
    }
  }
});

test('media fullscreen outranks every normal-mode policy and utility windows are not auto-maximized', () => {
  for (let mask = 0; mask < 1 << flags.length; mask++) {
    const input = {};
    flags.forEach((flag, index) => { input[flag] = Boolean(mask & (1 << index)); });
    const policy = logic.normalizedWindowModes(input);
    for (const fullscreen of [{ fullscreenState: 2 }, { clientFullscreenState: 2 }])
      assert.equal(logic.desiredWindowState(fullscreen, null, policy), 2);
    for (const utility of [{ floating: true }, { pinned: true }])
      assert.equal(logic.desiredWindowState(utility, null, policy), 0);
  }
});

test('each new switcher session follows primary, disconnected fallback and reconnected primary', () => {
  const { root, env } = overlay({ shell: { shellConfig: { plugins: [{ id: pluginId, overlayMonitor: 'HDMI-A-1' }] } } });
  const both = Array.from(env.Hyprland.monitors.values);
  const screens = Array.from(env.Quickshell.screens);
  for (const connected of [true, false, true]) {
    env.Hyprland.monitors.values = connected ? both : [both[0]];
    env.Quickshell.screens = connected ? screens : [screens[1]];
    root.startSwitcher(true, 'alt', 1, 'native');
    assert.equal(root.targetScreen.name, connected ? 'HDMI-A-1' : 'eDP-1');
    assert.deepEqual(Array.from(root.snapshotVisibleWorkspaceIds), connected ? [2, 1] : [2]);
    root.cancel();
    env.windowQuery.running = false;
  }
});

test('closing the selected window before acceptance chooses a live entry without changing MRU order', () => {
  const windows = ['0xa', '0xb', '0xc'].map(address => ({ address, appName: address, appKey: address }));
  const { root, env } = overlay({ opened: true, windows, selectedIndex: 1 });
  env.Hyprland.toplevels.values = [windows[0], windows[2]];
  root.pruneClosedWindows();
  assert.equal(root.opened, true);
  assert.deepEqual(Array.from(root.windows, window => window.address), ['0xa', '0xc']);
  assert.equal(root.entries[root.selectedIndex].address, '0xc');
  env.Hyprland.toplevels.values = [windows[0]];
  root.pruneClosedWindows();
  assert.equal(root.opened, false);
  assert.notEqual(env.activationDispatch.running, true);
});

test('activation transaction is a no-op when its exact target has closed or is unmapped', () => {
  const script = logic.activationScript('0xa', '0xb', 2, true, 0, []);
  for (const target of ['nil', '{address="0xb",mapped=false}']) {
    execFileSync('lua', ['-'], { input: `
      local target=${target}; local calls=0;
      hl={get_window=function() return target end, dispatch=function() calls=calls+1 end};
      local function activate() ${script} end;
      activate(); assert(calls==0)
    ` });
  }
});

test('unsupported or unavailable surface evidence cannot masquerade as committed readiness', () => {
  const { root } = overlay({ activationCommitInProgress: true, handoffNeedsCover: true,
    pendingWindow: { address: '0xa' }, pendingFullscreenRestore: { internal: 1 }, activationGeneration: 9 });
  root.observeActivationTargetCommit('invalid JSON', 9);
  assert.equal(root.activationReadiness, 'fallback-unavailable');
  root.observeActivationTargetCommit(JSON.stringify({ protocol: 1, address: '0xa', supported: false, ready: true }), 9);
  assert.equal(root.activationReadiness, 'fallback-unsupported');
  assert.notEqual(root.activationTargetSurfaceReady, true);
  root.observeActivationTargetCommit(JSON.stringify({ protocol: 1, address: '0xa', supported: true, ready: true, internal: 1 }), 8);
  assert.notEqual(root.activationTargetSurfaceReady, true);
});

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { overlay, logic } = require('./overlay-harness.cjs');
const json = JSON.stringify;
const rows = [0, 1, 2].map(i => ({ address: `0x${i + 1}`, mapped: true, class: 'app',
  workspace: { id: 1 }, monitor: 1, size: [800, 600], focusHistoryID: i, fullscreen: 0, fullscreenClient: 0 }));

test('a released native gesture commits without a picker or tiled handoff capture', () => {
  const { root } = overlay();
  root.observeSwitcherStep('{"protocol":1,"step":1}');
  root.observeSwitcherRelease('{"protocol":1}');
  root.completeWindowQuery(json(rows));
  assert.equal(root.pendingWindow.address, '0x2');
  assert.equal(root.activationCommitInProgress, true);
  assert.equal(root.pickerPresented, false);
  assert.equal(root.coverCaptureNeeded, false);
});

test('held native Alt has no polling; unloading re-enables polling and watchdog', () => {
  const { root, env } = overlay();
  root.observeSwitcherStep('{"protocol":1,"step":1}');
  root.completeWindowQuery(json(rows));
  assert.equal(root.pickerPresented, false);
  root.presentPicker();
  assert.equal(root.pickerPresented, true);
  assert.equal(root.modifierPollingNeeded, false);
  let restarted = 0;
  env.watchdog.restart = () => restarted++;
  root.observeSwitcherFallback('{"protocol":1}');
  assert.equal(root.modifierPollingNeeded, true);
  assert.equal(restarted, 1);
  root.observeModifierState('error: false');
  assert.equal(root.pendingWindow.address, '0x2');
});

test('quick native release after the query activates before the delayed picker can flash', () => {
  const { root, env } = overlay();
  let scheduled = 0, stopped = 0;
  env.pickerPresentationTimer.restart = () => scheduled++;
  env.pickerPresentationTimer.stop = () => stopped++;
  root.observeSwitcherStep('{"protocol":1,"step":1}');
  root.completeWindowQuery(json(rows));
  assert.equal(scheduled, 1);
  assert.equal(root.pickerPresented, false);
  root.observeSwitcherRelease('{"protocol":1}');
  assert.equal(root.pendingWindow.address, '0x2');
  assert.equal(root.activationCommitInProgress, true);
  assert.equal(stopped, 1);
  root.presentPicker();
  assert.equal(root.pickerPresented, false, 'a stale timer cannot reopen the picker during activation');
});

test('a native hold cancelled before presentation cannot flash a late picker', () => {
  const { root } = overlay();
  root.observeSwitcherStep('{"protocol":1,"step":1}');
  root.completeWindowQuery(json(rows));
  root.cancel(); root.presentPicker();
  assert.equal(root.opened, false);
  assert.equal(root.pickerPresented, false);
});

test('a target closing during activation dismisses the picker and restores surviving source fullscreen', () => {
  const { root, env, calls } = overlay();
  root.observeSwitcherStep('{"protocol":1,"step":1}');
  root.completeWindowQuery(json(rows.slice(0, 2).map((w, i) => ({ ...w, fullscreen: i === 0 ? 2 : 0, fullscreenClient: 2 }))));
  root.observeSwitcherRelease('{"protocol":1}');
  env.activationDispatch.running = true;
  env.activationReadinessQuery.running = true;
  env.Hyprland.toplevels.values = [{ address: '0x1' }];
  root.pruneClosedWindows();
  assert.equal(root.opened, false);
  assert.equal(root.pickerPresented, false);
  assert.equal(root.activationCommitInProgress, false);
  assert.equal(root.pendingWindow, null);
  assert.equal(env.activationDispatch.running, false);
  assert.equal(env.activationReadinessQuery.running, false);
  assert.ok(calls.some(s => s.includes('internal=2,client=-1') && s.includes('address:0x1')));
});

test('the real watchdog callback permits a long native hold and still cancels broken fallback input', () => {
  const source = fs.readFileSync(path.join(__dirname, '../Overlay.qml'), 'utf8');
  const block = source.match(/id: watchdog\n[\s\S]*?onTriggered: \{([\s\S]*?)\n    \}/)[1];
  for (const native of [true, false]) {
    const { root, env } = overlay({ opened: true, releaseToActivate: true, switcherInputSource: native ? 'native' : 'global' });
    vm.runInContext(`(function() {${block}})()`, env);
    assert.equal(root.opened, native);
  }
});

test('snapshot resolves duplicate application metadata only once, refreshes next time', () => {
  const { root, env } = overlay();
  root.startSwitcher(true, 'alt', 1);
  let lookups = 0;
  root.applicationInfo = () => ({ id: 'app', name: `App ${++lookups}`, icon: '', fallbackText: 'A' });
  root.completeWindowQuery(json(rows));
  assert.equal(lookups, 1);
  env.windowQuery.running = false;
  root.cancel(); root.startSwitcher(true, 'alt', 1); root.completeWindowQuery(json(rows));
  assert.equal(lookups, 2, 'no stale application/theme cache across snapshots');
});

test('cover allocation follows same-workspace resize policy across all fullscreen modes', () => {
  for (const sourceMode of [0, 1, 2]) for (const targetMode of [0, 1, 2]) {
    for (const clientMode of [0, 1, 2]) for (const maximize of [false, true]) {
      const source = { address: '0xa', workspaceId: 1, fullscreenState: sourceMode };
      const target = { address: '0xb', workspaceId: 1, fullscreenState: targetMode, clientFullscreenState: clientMode };
      const modes = { ...logic.defaultWindowModes(), maximizeOnSwitch: maximize };
      const { root } = overlay({ windowModes: modes });
      root.prepareFullscreenHandoff(source, target);
      assert.equal(logic.needsHandoffCover(source, target, null, modes), root.handoffNeedsCover);
      assert.equal(logic.needsHandoffCover(source, { ...target, workspaceId: 2 }, null, modes), false);
      assert.equal(logic.needsHandoffCover(source, source, null, modes), false);
    }
  }
});

test('quick fullscreen restore retains its capture even without presenting a picker', () => {
  const { root } = overlay();
  root.startSwitcher(true, 'alt', 1, 'native'); root.observeSwitcherRelease('{"protocol":1}');
  root.completeWindowQuery(json(rows.map((w, i) => ({ ...w, fullscreen: i === 0 ? 2 : 0, fullscreenClient: 2 }))));
  assert.equal(root.pickerPresented, false);
  assert.equal(root.coverCaptureNeeded, true);
  assert.equal(root.handoffNeedsCover, true);
});

test('focus readiness is requested after dispatch, never ahead of the activation transaction', () => {
  const { root, env } = overlay({ activationCommitInProgress: true, pendingWindow: { address: '0xb' }, activationGeneration: 7 });
  root.requestActivationReadiness();
  assert.notEqual(env.activationReadinessQuery.running, true);
  root.activationCommitAttempts = 1; env.activationDispatch.running = true;
  root.requestActivationReadiness();
  assert.notEqual(env.activationReadinessQuery.running, true);
  env.activationDispatch.running = false;
  root.requestActivationReadiness();
  assert.equal(env.activationReadinessQuery.running, true);
  assert.equal(env.activationReadinessQuery.generation, 7);
  assert.deepEqual(Array.from(env.activationReadinessQuery.command), ['hyprctl', 'orbit-window-ready', '0xb']);
});

test('confirmed tiled focus advances immediately, without another retry timer tick', () => {
  const { root } = overlay({ activationCommitInProgress: true, activationCommitAttempts: 1,
    pendingWindow: { address: '0xb' }, activationGeneration: 7, handoffNeedsCover: false });
  root.observeActivationTargetCommit(json({ protocol: 1, address: '0xb', active: true }), 7);
  assert.equal(root.activationCommitFinalizing, true);
  const attempts = root.activationCommitAttempts;
  root.advanceActivationCommit();
  assert.equal(root.activationCommitAttempts, attempts, 'already-finalizing work cannot run twice');
});

test('fast focus confirmation cannot bypass a fullscreen surface commit and render guard', () => {
  const { root, env } = overlay({ activationCommitInProgress: true, activationCommitAttempts: 1,
    pendingWindow: { address: '0xb' }, pendingFullscreenRestore: { internal: 2 }, activationGeneration: 7, handoffNeedsCover: true });
  let reveal = 0; env.activationRevealTimer.restart = () => reveal++;
  const state = { protocol: 1, address: '0xb', active: true, supported: true, internal: 2 };
  root.observeActivationTargetCommit(json({ ...state, ready: false }), 7);
  assert.notEqual(root.activationCommitFinalizing, true);
  assert.equal(reveal, 0);
  root.advanceActivationCommit();
  assert.equal(root.activationCommitSettling, true);
  root.observeActivationTargetCommit(json({ ...state, ready: true }), 7);
  assert.equal(reveal, 1);
  assert.notEqual(root.activationCommitFinalizing, true, 'reveal timer still owns the render guard');
});

test('a ready buffer with refused focus keeps checking until the exact window becomes active', () => {
  const { root, env } = overlay({ activationCommitInProgress: true, activationCommitAttempts: 1,
    pendingWindow: { address: '0xb' }, pendingFullscreenRestore: { internal: 2 }, activationGeneration: 7, handoffNeedsCover: true });
  const state = { protocol: 1, address: '0xb', active: false, supported: true, ready: true, internal: 2 };
  root.observeActivationTargetCommit(json(state), 7);
  assert.equal(root.activationTargetSurfaceReady, true);
  assert.equal(root.activationFocusConfirmed, false);
  assert.notEqual(root.activationCommitSettling, true);
  root.requestActivationReadiness();
  assert.equal(env.activationReadinessQuery.running, true);
  root.observeActivationTargetCommit(json({ ...state, active: true }), 7);
  assert.equal(root.activationCommitSettling, true);
});

test('in-flight focus requests are not multiplied; a stuck process still has a bounded abort', () => {
  const { root, env } = overlay({ activationCommitInProgress: true, activationCommitAttempts: 1,
    pendingWindow: { address: '0xb' }, activationGeneration: 7 });
  env.activationReadinessQuery.running = true;
  root.advanceActivationCommit();
  assert.notEqual(env.activationDispatch.running, true);
  let aborted = 0;
  root.abortActivationCommit = () => aborted++;
  root.activationCommitAttempts = root.activationCommitAttemptLimit - 1;
  root.advanceActivationCommit();
  assert.equal(aborted, 1);
});

test('known unsupported readiness stops subprocess polling during the bounded cover fallback', () => {
  const { root, env } = overlay({ activationCommitInProgress: true, activationCommitAttempts: 2,
    activationCommitSettling: true, activationReadiness: 'fallback-unsupported', pendingWindow: { address: '0xb' } });
  root.requestActivationReadiness();
  assert.notEqual(env.activationReadinessQuery.running, true);
});

test('Escape cancels queued input during the picker-unmapped finalization interval', () => {
  const { root } = overlay({ opened: false, activationCommitInProgress: true, activationCommitFinalizing: true });
  root.invokeShortcut(1, 'native');
  root.observeSwitcherCancel('{"protocol":1}');
  root.observeSwitcherRelease('{"protocol":1}');
  root.finalizeActivationCommit();
  assert.equal(root.deferredSwitchGestures.length, 0);
  assert.equal(root.snapshotPending, false);
});

test('stable Flip slots match existing forward/reverse/wrap ordering and stay bounded', () => {
  for (let length = 1; length <= 40; length++) for (let selected = 0; selected < length; selected++) {
    const windows = Array.from({ length }, (_, index) => ({ address: `0x${index.toString(16)}` }));
    const expected = Array.from(logic.flipEntries(windows, selected, 7), e => [e.windowIndex, e.offset + 0]);
    const actual = windows.map((_, i) => [i, logic.flipOffset(i, selected, length, 7)])
      .filter(e => e[1] !== null).sort((a, b) => a[1] - b[1]);
    assert.deepEqual(actual, expected);
    assert.ok(actual.length <= 7);
  }
});

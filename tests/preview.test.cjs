const test = require('node:test');
const assert = require('node:assert/strict');
const { overlay, logic } = require('./overlay-harness.cjs');

const full = { address: '0xa', previewIdentity: 'stable-firefox', workspaceId: 1, monitorId: 1,
  previewWidth: 1896, previewHeight: 1019, fullscreenState: 1, clientFullscreenState: 1 };
const image = { url: 'image://test/full-firefox' };
const plain = value => JSON.parse(JSON.stringify(value));

test('a demoted maximized window retains the full image and its aspect, not its hidden tile', () => {
  const cache = logic.rememberPreview({}, full, image, 1896, 1019, 24);
  const hidden = { ...full, fullscreenState: 0, previewWidth: 466 };
  hidden.previewSnapshot = logic.restoredPreview(hidden, cache['0xa']);
  assert.deepEqual(plain(hidden.previewSnapshot), { url: image.url, width: 1896, height: 1019 });
  const layout = logic.aspectGridLayout([full, hidden, hidden], 1200, 700, 12, 8, 52, 220);
  assert.ok(layout.items.every(item => Math.abs((item.width - 16) / layout.previewHeight - 1896 / 1019) < 1e-8));
  assert.equal(hidden.previewWidth, 466, 'snap and activation logic must retain actual compositor geometry');
});

test('fresh visible windows, mode changes, moves and reused addresses cannot show an old snapshot', () => {
  const saved = logic.rememberPreview({}, full, image, 1896, 1019, 24)['0xa'];
  const hidden = { ...full, fullscreenState: 0 };
  for (const change of [{ fullscreenState: 1 }, { clientFullscreenState: 0 }, { clientFullscreenState: 2 },
    { floating: true }, { pinned: true }, { monitorId: 0 }, { workspaceId: 2 }, { previewIdentity: 'new-firefox' },
    { previewMonitorKey: 'changed-resolution-or-scale' }]) {
    assert.equal(logic.restoredPreview({ ...hidden, ...change }, saved), null, JSON.stringify(change));
  }
  const fullscreen = { ...full, fullscreenState: 2, clientFullscreenState: 2, previewWidth: 1920, previewHeight: 1080 };
  const media = logic.rememberPreview({}, fullscreen, image, 1920, 1080, 24)['0xa'];
  assert.equal(logic.restoredPreview({ ...fullscreen, fullscreenState: 0 }, media).width, 1920);
});

test('late narrow captures and ineligible windows cannot overwrite a good full preview', () => {
  const cache = logic.rememberPreview({}, full, image, 1896, 1019, 24);
  for (const [window, width, height] of [[full, 466, 1019], [full, 0, 1019],
    [{ ...full, fullscreenState: 0 }, 1896, 1019], [{ ...full, floating: true, fullscreenState: 0 }, 1896, 1019]]) {
    assert.equal(logic.rememberPreview(cache, window, image, width, height, 24), cache);
  }
  assert.equal(logic.rememberPreview(cache, full, null, 1896, 1019, 24), cache);
  const scaled = logic.rememberPreview({}, full, image, 2844, 1529, 24);
  assert.ok(scaled['0xa'], 'monitor scaling may round one physical pixel');
});

test('explicit fullscreen on a floating window retains its own image until the client leaves that mode', () => {
  const floating = { ...full, floating: true, fullscreenState: 2, clientFullscreenState: 2 };
  const saved = logic.rememberPreview({}, floating, image, 1896, 1019, 24)['0xa'];
  assert.ok(logic.restoredPreview({ ...floating, fullscreenState: 0 }, saved));
  assert.equal(logic.restoredPreview({ ...floating, fullscreenState: 0, clientFullscreenState: 0 }, saved), null);
});

test('retained previews have a fixed count and pixel budget and refresh their eviction order', () => {
  let cache = {};
  for (let i = 0; i < 80; i++) {
    cache = logic.rememberPreview(cache, { ...full, address: '0x' + i.toString(16) }, image, 1896, 1019, 24);
    assert.ok(Object.keys(cache).length <= 24);
  }
  assert.equal(Object.keys(cache)[0], '0x38');
  cache = logic.rememberPreview(cache, { ...full, address: '0x38' }, image, 1896, 1019, 24);
  cache = logic.rememberPreview(cache, { ...full, address: '0x50' }, image, 1896, 1019, 24);
  assert.ok(cache['0x38']);
  assert.equal(cache['0x39'], undefined);
  for (const [w, h] of [[1896, 1019], [3840, 2160], [1080, 3840], [7680, 1080], [1000, 700], [200, 120]]) {
    const size = logic.previewCaptureSize(w, h);
    assert.ok(size.width <= 640 && size.height <= 400);
    assert.ok(Math.abs(size.width / size.height / (w / h) - 1) < 0.006);
  }
});

test('ten-to-seven, portrait, and ultrawide windows preserve their individual grid proportions', () => {
  const rows = [[1000, 700], [900, 900], [200, 1000], [7000, 1000]].map(([previewWidth, previewHeight]) => ({ previewWidth, previewHeight }));
  const layout = logic.aspectGridLayout(rows, 1300, 800, 12, 8, 52, 220);
  for (const card of layout.items) {
    assert.ok(Math.abs((card.width - 16) / layout.previewHeight - rows[card.index].previewWidth / rows[card.index].previewHeight) < 1e-8);
    assert.ok(card.x >= 0 && card.x + card.width <= 1300 + 1e-8);
  }
});

test('the real overlay pairs images with restored dimensions and prunes closed-window pixels', () => {
  const { root, env } = overlay({ windowScope: 'all' });
  const toplevel = { address: '0xa', monitor: { name: 'HDMI-A-1' } };
  env.Hyprland.toplevels.values = [toplevel];
  const ipc = { address: '0xa', class: 'firefox', stableId: 'firefox-1', monitor: 1,
    workspace: { id: 1 }, size: [1896, 1019], fullscreen: 1, fullscreenClient: 1 };
  const window = root.snapshotCurrentWindows([ipc])[0];
  root.windows = [window];
  root.rememberWindowPreview(window, image, 1896, 1019);
  const [hidden] = root.snapshotCurrentWindows([{ ...ipc, size: [466, 1019], fullscreen: 0 }]);
  assert.equal(hidden.previewSnapshot.width, 1896);
  assert.equal(hidden.previewWidth, 466);
  env.Hyprland.toplevels.values = [];
  root.pruneClosedWindows();
  assert.equal(Object.keys(root.previewSnapshots).length, 0);
  env.Hyprland.toplevels.values = [{ ...toplevel }];
  root.rememberWindowPreview(window, image, 1896, 1019);
  assert.equal(Object.keys(root.previewSnapshots).length, 0, 'a late callback must not resurrect a closed window');
});

test('a quick switch from maximized to a floating window still captures the outgoing preview', () => {
  const { root } = overlay();
  root.observeSwitcherStep('{"protocol":1,"step":1}');
  root.observeSwitcherRelease('{"protocol":1}');
  root.completeWindowQuery(JSON.stringify([
    { address: '0xa', class: 'app', workspace: { id: 1 }, monitor: 1, size: [1896, 1019], fullscreen: 1, fullscreenClient: 1, focusHistoryID: 0 },
    { address: '0xb', class: 'utility', workspace: { id: 1 }, monitor: 1, size: [600, 400], floating: true, focusHistoryID: 1 }
  ]));
  assert.equal(root.pickerPresented, false);
  assert.equal(root.coverCaptureNeeded, false, 'the floating target needs no resize cover');
  assert.equal(root.sourcePreviewCaptureNeeded, true, 'the source will lose its maximized geometry');
  root.windows = [{ ...full, fullscreenState: 0 }];
  assert.equal(root.sourcePreviewCaptureNeeded, false, 'ordinary tiled quick taps keep their allocation-free path');
});

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const logic = {};
vm.createContext(logic);
vm.runInContext(fs.readFileSync(path.join(__dirname, '../SwitcherLogic.js'), 'utf8').replace(/^\.pragma library\s*$/m, ''), logic);
const window = {
  address: '0xa', fullscreenState: 1, clientFullscreenState: 1,
  previewWidth: 1920, previewHeight: 1080, previewIdentity: 'pid:app',
  previewMonitorKey: '1920:1080:1:12', workspaceId: 1, monitorId: 1,
  floating: false, pinned: false,
};
const capture = { url: 'memory:preview' };
const remember = (w = window, cache = {}, c = capture, width = 1920, height = 1080) =>
  logic.rememberPreview(cache, w, c, width, height, 24);

test('temporary demotion retains the full-size image and dimensions', () => {
  const cache = remember();
  const preview = logic.restoredPreview({ ...window, fullscreenState: 0, previewWidth: 500 }, cache['0xa']);
  assert.equal(preview.url, capture.url);
  assert.equal(preview.width, 1920);
  assert.equal(preview.height, 1080);
  assert.equal(logic.restoredPreview(window, cache['0xa']), null, 'visible full-size windows use fresh captures');
});

test('real mode, identity, workspace and monitor changes invalidate retained pixels', () => {
  const cache = remember();
  for (const change of [
    { floating: true }, { pinned: true }, { clientFullscreenState: 2 },
    { previewIdentity: 'other:app' }, { previewMonitorKey: '2560:1440:1:12' },
    { workspaceId: 2 }, { monitorId: 2 },
  ]) {
    assert.equal(logic.restoredPreview({ ...window, fullscreenState: 0, ...change }, cache['0xa']), null, JSON.stringify(change));
  }
});

test('stale resized captures and invalid captures cannot replace good pixels', () => {
  const cache = remember();
  assert.equal(remember(window, cache, capture, 500, 1080), cache);
  assert.equal(remember({ ...window, fullscreenState: 0 }, cache), cache);
  assert.equal(remember(window, cache, {}), cache);
});

test('capture cache evicts the oldest entry and stays bounded', () => {
  let cache = {};
  for (let i = 0; i < 30; i++) cache = remember({ ...window, address: '0x' + i.toString(16) }, cache);
  assert.equal(Object.keys(cache).length, 24);
  assert.equal(cache['0x0'], undefined);
  assert.ok(cache['0x1d']);
});

test('portrait and ultrawide capture geometry remains proportional and bounded', () => {
  for (const [width, height] of [[100, 1000], [10000, 100], [1920, 1080]]) {
    assert.equal(logic.previewAspect(width, height), width / height);
    const size = logic.previewCaptureSize(width, height);
    assert.ok(size.width <= 640 && size.height <= 400);
    assert.ok(Math.abs(size.width / size.height / (width / height) - 1) < 0.1);
  }
});

test('Wispr internal windows stay excluded even when otherwise eligible', () => {
  for (const key of ['class', 'initialClass']) {
    assert.equal(logic.isEligibleWindow({ mapped: true, [key]: 'wispr-flow' }, 1, 'main', 1,
      'all', [1], ['main'], [1], 1, 'main', 1), false);
  }
});

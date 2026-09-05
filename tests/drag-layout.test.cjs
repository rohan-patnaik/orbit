const assert = require('node:assert/strict');
const test = require('node:test');
const { logic } = require('./overlay-harness.cjs');
const monitor = { id: 0, name: 'eDP-1', x: -1280, y: 0, width: 1920, height: 1080, scale: 1.5 };
const event = (x, y) => ({ protocol: 1, session: 1, phase: 'move', monitor, window: { address: '0xabc' }, x, y });

test('top and all four corners use logical output coordinates, including negative origins', () => {
  for (const [x, y, edge] of [
    [-1270, 10, 'top-left'], [-10, 10, 'top-right'], [-640, 10, 'top'],
    [-1270, 710, 'bottom-left'], [-10, 710, 'bottom-right'],
    [-640, 200, ''], [-640, 710, ''], [-1400, 10, ''], [20, 10, '']
  ]) assert.equal(logic.dragEdge(event(x, y)), edge);
});

test('picker opens while moving, remains available inside its card, hides when dragged away', () => {
  let state = logic.dragPresentation(null, event(-640, 10), null);
  assert.equal(state.visible, true);
  const rect = logic.dragPickerGeometry(monitor, state.anchor, 640, 318);
  state = logic.dragPresentation(state, event(-640, 160), rect);
  assert.equal(state.visible, true);
  assert.equal(logic.dragPresentation(state, event(-640, 500), rect).visible, false);
  assert.equal(logic.dragPresentation(state, { ...event(-640, 160), phase: 'end' }, rect).visible, false);
  assert.equal(logic.dragPresentation(state, { ...event(-640, 160), session: 2 }, rect).visible, false);
});

test('rotated monitors and native logical monitor events agree on snap geometry', () => {
  const rotated = { x: -720, y: 0, width: 1920, height: 1080, transform: 1, scale: 1.5, reserved: [0, 0, 0, 37] };
  const native = { ...rotated, logicalWidth: 720, logicalHeight: 1280 };
  const slot = logic.snapLayouts()[0].slots[0];
  const first = logic.snapGeometry(slot, rotated, 12, 12);
  const second = logic.snapGeometry(slot, native, 12, 12);
  assert.deepEqual(JSON.parse(JSON.stringify(first)), JSON.parse(JSON.stringify(second)));
  assert.equal(first.x, -708);
  assert.equal(first.height, 1219);
});

test('disabled modes cannot reappear via snap picker or maximize-on-switch', () => {
  const policy = logic.normalizedWindowModes({ floating: false, maximized: false, fullscreen: true, maximizeOnSwitch: true });
  assert.equal(policy.maximizeOnSwitch, false);
  assert.deepEqual(Array.from(logic.availableSnapLayouts(policy), layout => layout.id), ['fullscreen']);
  const ids = Array.from(logic.snapLayouts(), layout => layout.id);
  assert.equal(ids.includes('main-stack'), false);
  assert.ok(ids.includes('maximized') && ids.includes('fullscreen'));
});

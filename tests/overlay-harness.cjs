const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const base = path.join(__dirname, '..');
const source = fs.readFileSync(path.join(base, 'Overlay.qml'), 'utf8');
const logic = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(base, 'SwitcherLogic.js'), 'utf8').replace(/^\.pragma library\s*$/m, ''), logic);

function overlay(overrides = {}) {
  const calls = [];
  const timer = () => ({ restart() {}, stop() {} });
  const root = Object.assign({
    pluginId: 'io.github.rohan-patnaik.window-switcher', opened: false, snapshotPending: false,
    activationCommitInProgress: false, managerMode: '', windows: [], mode: 'grid',
    snapshotRestartPending: false, deferredSwitchGestures: [], pendingGestureReleased: false,
    switcherInputSource: 'global', inputTraceEnabled: false, inputTrace: [],
    activationGeneration: 0,
    selectedIndex: 0, snapQueryPending: false, snapGroups: [], snapRestoreStates: {},
    snapMonitorRows: [], snapClientRows: [], snapAnimationAddresses: [],
    rememberedFullscreenStates: {}, handoffAnimationAddresses: [],
    windowModes: logic.defaultWindowModes(), shell: { shellConfig: { plugins: [] } },
    dragState: { visible: false, session: 0 }, dragShownCount: 0, dragDropCount: 0,
    snapActiveReady: false, snapMonitorReady: false, snapClientsReady: false,
  }, overrides);
  Object.defineProperty(root, 'entries', { get: () => root.mode === 'icons' ? logic.applicationEntries(root.windows) : root.windows });
  Object.defineProperty(root, 'snapLayouts', { get: () => logic.availableSnapLayouts(root.windowModes) });
  const env = vm.createContext({
    root, Logic: logic, console, Style: { gapsOut: 6 },
    Qt: { point: (x, y) => ({ x, y }) },
    Quickshell: { screens: [{ name: 'HDMI-A-1' }, { name: 'eDP-1' }], iconPath: () => '' },
    DesktopEntries: { byId: () => null, applications: { values: [] }, heuristicLookup: () => null },
    Hyprland: { monitors: { values: [
      { id: 0, name: 'eDP-1', x: -1280, y: 0, activeWorkspace: { id: 2 } },
      { id: 1, name: 'HDMI-A-1', x: 0, y: 0, activeWorkspace: { id: 1 } }
    ] }, focusedWorkspace: { id: 2 }, focusedMonitor: { id: 0, name: 'eDP-1' },
      toplevels: { values: [] }, dispatch: command => calls.push(command) },
    windowQuery: {}, snapActiveQuery: {}, snapMonitorQuery: {}, snapClientsQuery: {}, settingsReload: {}, mediaExitRestore: {}, activationDispatch: {},
    watchdog: timer(), dragWatchdog: timer(), snapAnimationRelease: timer(), snapFocusTimer: timer(),
    activationCommitTimer: timer(), activationSettleTimer: timer(), activationRevealTimer: timer(), activationFinalizeTimer: timer(),
    dragLayer: { item: null }, switcherLayer: { item: null },
  });
  // Execute the actual QML method bodies. Unlike source-string assertions this
  // checks observable state/dispatch order with competing asynchronous callbacks.
  const methods = source.matchAll(/^  function (\w+)\(([^)]*)\) \{\n([\s\S]*?)^  \}/gm);
  for (const [, name, args, body] of methods)
    root[name] = vm.runInContext(`(function(${args}) {${body}\n})`, env);
  return { root, env, calls };
}
module.exports = { overlay, logic };

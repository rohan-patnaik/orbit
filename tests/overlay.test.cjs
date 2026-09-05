const test = require('node:test');
const assert = require('node:assert/strict');
const { overlay, logic } = require('./overlay-harness.cjs');
const json = value => JSON.stringify(value);
const main = { id: 1, name: 'HDMI-A-1', x: 0, y: 0, width: 1920, height: 1080, scale: 1 };
const laptop = { id: 0, name: 'eDP-1', x: -1280, y: 0, width: 1920, height: 1080, scale: 1.5 };
const app = { address: '0xa', monitor: 1, workspace: { id: 1 }, at: [10, 10], size: [800, 600], fullscreen: 0 };

test('switcher requested on laptop targets main while admitting both visible workspaces', () => {
  const { root } = overlay();
  root.startSwitcher(true, 'alt', 1);
  assert.equal(root.targetScreen.name, 'HDMI-A-1');
  root.completeWindowQuery(json([
    { ...app, class: 'one', focusHistoryID: 1 },
    { ...app, address: '0xb', class: 'two', monitor: 0, workspace: { id: 2 }, focusHistoryID: 0 },
    { ...app, address: '0xc', class: 'hidden', workspace: { id: 3 }, focusHistoryID: 2 }
  ]));
  assert.equal(root.opened, true);
  assert.deepEqual(Array.from(root.entries, w => w.address), ['0xb', '0xa']);
  assert.equal(root.entries[root.selectedIndex].address, '0xa');
});

test('rapid forward and reverse requests are counted while MRU query is pending', () => {
  const { root } = overlay();
  root.startSwitcher(true, 'alt', 1);
  root.invokeShortcut(1); root.invokeShortcut(1); root.invokeShortcut(-1);
  root.completeWindowQuery(json([0, 1, 2].map(i => ({ ...app, address: `0x${i+1}`, focusHistoryID: i }))));
  assert.equal(root.selectedIndex, 2);
  root.cancel();
  assert.equal(root.opened, false);
});

test('cancelled query cannot resurrect the switcher', () => {
  const { root } = overlay();
  root.startSwitcher(true, 'alt', 1); root.cancel();
  root.completeWindowQuery(json([app, { ...app, address: '0xb' }]));
  assert.equal(root.opened, false);
});

test('snap queries may finish in any order without snapping on the focused laptop', () => {
  const { root } = overlay();
  root.openSnapManager();
  root.completeSnapMonitors(json([laptop, main]));
  root.completeSnapClients('[]');
  assert.equal(root.managerMode, '');
  root.completeSnapActive(json(app));
  assert.equal(root.managerMode, 'snap');
  assert.equal(root.snapTargetMonitor.name, 'HDMI-A-1');
  assert.equal(root.targetScreen.name, 'HDMI-A-1');
});

test('cancelled snap query and stale drag client callback cannot open a modal picker', () => {
  const { root } = overlay();
  root.openSnapManager(); root.closeManager();
  root.completeSnapActive(json(app)); root.completeSnapMonitors(json([main])); root.completeSnapClients('[]');
  assert.equal(root.managerMode, '');
  assert.equal(root.snapTargetWindow, null);
});

test('drag is visible before release; exact dragged target survives focus changes', () => {
  const { root, env, calls } = overlay();
  const move = { protocol: 1, session: 7, phase: 'move', x: 600, y: 10, monitor: main,
    window: { address: '0xa', monitorId: 1, workspaceId: 1, floating: true } };
  root.handleDragEvent(json(move));
  assert.equal(root.dragState.visible, true);
  assert.equal(root.managerMode, '');
  assert.equal(calls.length, 0, 'showing a preview must not change any real window');
  env.dragLayer.item = { cardGeometry: { x: 600, y: 12, width: 640, height: 318 }, hitTest: () => ({ layout: 5, slot: 0 }) };
  root.handleDragEvent(json({ ...move, phase: 'end', x: 650, y: 250 }));
  assert.equal(root.dragState.visible, false);
  assert.equal(root.dragDropCount, 1);
  assert.ok(calls.some(c => c.includes('internal = 1') && c.includes('address:0xa')));
});

test('release outside, Escape, wrong epoch, and end-without-preview never snap', () => {
  for (const phase of ['end', 'cancel']) {
    const { root, calls } = overlay();
    const event = { protocol: 1, session: 1, phase: 'move', x: 600, y: 10, monitor: main, window: { address: '0xa' } };
    root.handleDragEvent(json(event));
    root.handleDragEvent(json({ ...event, phase, session: 0 }));
    assert.equal(root.dragState.visible, true);
    root.handleDragEvent(json({ ...event, phase }));
    assert.equal(root.dragState.visible, false);
    assert.equal(calls.length, 0);
  }
});

test('live media fullscreen wins; intentional floating/PiP windows are not auto-maximized', () => {
  const policy = { ...logic.defaultWindowModes(), maximizeOnSwitch: true };
  assert.equal(logic.desiredWindowState({ fullscreenState: 0, clientFullscreenState: 2 }, null, policy), 2);
  assert.equal(logic.desiredWindowState({ fullscreenState: 0, clientFullscreenState: 0 }, null, policy), 1);
  assert.equal(logic.desiredWindowState({ floating: true }, null, policy), 0);
  assert.equal(logic.desiredWindowState({ pinned: true }, null, policy), 0);
});

test('release on another monitor cannot drop onto a stale picker', () => {
  const { root, env, calls } = overlay();
  const event = { protocol: 1, session: 1, phase: 'move', x: 600, y: 10, monitor: main, window: { address: '0xa' } };
  root.handleDragEvent(json(event));
  env.dragLayer.item = { hitTest: () => ({ layout: 5, slot: 0 }) };
  root.handleDragEvent(json({ ...event, phase: 'end', monitor: laptop }));
  assert.equal(root.dragDropCount, 0);
  assert.equal(calls.length, 0);
});

test('new Alt-Tab during activation waits for a fresh MRU snapshot', () => {
  const { root } = overlay({ activationCommitInProgress: true });
  root.invokeShortcut(1); root.invokeShortcut(1); root.invokeShortcut(-1);
  assert.deepEqual(JSON.parse(json(root.deferredSwitchGestures)), [{steps:[1,1,-1],released:false,source:'global'}]);
  root.finalizeActivationCommit();
  assert.equal(root.snapshotPending, true);
  assert.equal(root.queuedSteps, 0);
  root.completeWindowQuery(json([
    { ...app, address: '0xb', focusHistoryID: 0 },
    { ...app, address: '0xa', focusHistoryID: 1 }
  ]));
  assert.equal(root.entries[root.selectedIndex].address, '0xa');
});

test('rapid independent Alt gestures stay separate and each receives fresh MRU state', () => {
  const {root}=overlay({activationCommitInProgress:true});
  root.invokeShortcut(1); root.observeSwitcherRelease('{"protocol":1}');
  root.invokeShortcut(1); root.observeSwitcherRelease('{"protocol":1}');
  assert.equal(root.deferredSwitchGestures.length,2);
  root.finalizeActivationCommit();
  assert.equal(root.pendingGestureReleased,true);
  root.invokeShortcut(-1); root.observeSwitcherRelease('{"protocol":1}');
  assert.equal(root.deferredSwitchGestures.length,2,'new input cannot merge into a released pending query');
  root.completeWindowQuery(json([{...app,address:'0xb',focusHistoryID:0},{...app,address:'0xa',focusHistoryID:1}]));
  assert.equal(root.activationCommitInProgress,true,'a completed gesture commits without waiting for a later Alt release');
  assert.equal(root.pendingWindow.address,'0xa');
});

test('held Alt refreshes the watchdog; failed modifier queries never accept a window', () => {
  const {root,env}=overlay({opened:true,releaseToActivate:true});
  let accepted=0,refreshed=0;root.accept=()=>accepted++;env.watchdog.restart=()=>refreshed++;
  root.observeModifierState('error: true'); assert.equal(refreshed,1);
  root.observeModifierState(''); root.observeModifierState('error: connection failed'); assert.equal(accepted,0);
  root.observeModifierState('error: false'); assert.equal(accepted,1);
});

test('native presses and releases remain ordered while delayed modifier polls cannot commit a later gesture', () => {
  const {root}=overlay();
  root.observeSwitcherStep('{"protocol":1,"step":1}');
  assert.equal(root.switcherInputSource,'native');
  root.observeSwitcherRelease('{"protocol":1}');
  root.observeSwitcherStep('{"protocol":1,"step":1}');
  assert.equal(root.deferredSwitchGestures.length,1);
  assert.equal(root.deferredSwitchGestures[0].source,'native');
  assert.equal(root.deferredSwitchGestures[0].released,false);
  root.opened=true;root.releaseToActivate=true;
  let accepted=0;root.accept=()=>accepted++;
  root.observeModifierState('error: false');
  assert.equal(accepted,0,'a poll from an earlier gesture must not accept a native session');
  root.observeSwitcherFallback('{"protocol":1}');
  root.observeModifierState('error: false');
  assert.equal(accepted,1,'unloading the bridge restores modifier-query handling');
  assert.equal(root.deferredSwitchGestures[0].source,'global');
});

test('Escape precedes an immediate Alt release even when Wayland key delivery lags', () => {
  const {root}=overlay({opened:true,releaseToActivate:true,releaseModifier:'alt',windows:[app,{...app,address:'0xb'}],selectedIndex:1});
  root.observeSwitcherCancel('{"protocol":1}');root.observeSwitcherRelease('{"protocol":1}');
  assert.equal(root.opened,false);assert.equal(root.activationCommitInProgress,false);
});

test('cancel-and-reopen drains the old query instead of accepting stale stdout', () => {
  const { root, env } = overlay();
  root.startSwitcher(true, 'alt', 1); root.cancel();
  env.windowQuery.running = true;
  root.startSwitcher(true, 'alt', 1);
  root.completeWindowQuery(json([app, { ...app, address: '0xb' }]));
  assert.equal(root.opened, false);
  assert.equal(root.snapshotRestartPending, true);
  root.snapshotRestartPending = false;
  root.completeWindowQuery(json([app, { ...app, address: '0xc' }]));
  assert.equal(root.entries[root.selectedIndex].address, '0xc');
});

test('closed windows are pruned from fullscreen memory and groups even with picker closed', () => {
  const { root } = overlay({ rememberedFullscreenStates: { '0xa': { internal: 2 } },
    snapRestoreStates: { '0xa': {} }, snapGroups: [{ addresses: ['0xa', '0xb'] }] });
  root.pruneClosedWindows();
  assert.equal(Object.keys(root.rememberedFullscreenStates).length, 0);
  assert.equal(Object.keys(root.snapRestoreStates).length, 0);
  assert.equal(root.snapGroups.length, 0);
});

test('named normal workspaces are eligible, hidden special workspaces are not', () => {
  assert.equal(logic.isEligibleWindow({ workspace: { name: 'codex-background' } }, -1337, '', 0, 'all'), true);
  assert.equal(logic.isEligibleWindow({ workspace: { name: 'special:secret' } }, -99, '', 0, 'all'), false);
});

test('icon contrast samples opaque artwork, not transparent padding', () => {
  assert.equal(logic.iconLuminance([0, 0, 0, 255, 255, 255, 255, 0]), 0);
  assert.ok(logic.iconLuminance([255, 255, 255, 255, 0, 0, 0, 0]) > 0.99);
  assert.equal(logic.iconLuminance([]), 0.5);
});

test('grid arrow navigation reaches the view inside its loader', () => {
  const { root, env } = overlay({ windows: [app, { ...app, address: '0xb' }] });
  env.switcherLayer.item = { loadedView: { navigationTarget: () => 1 } };
  root.navigate('right');
  assert.equal(root.selectedIndex, 1);
});

test('surface readiness requires a committed buffer for the exact address, state, and generation', () => {
  const { root } = overlay({ activationCommitInProgress: true, handoffNeedsCover: true,
    pendingWindow: {address: '0xa'}, pendingFullscreenRestore: {internal:1}, activationGeneration:4 });
  const ready = {protocol:1,address:'0xa',supported:true,ready:true,internal:1};
  for(const [value,generation] of [[{...ready,address:'0xb'},4],[ready,3],[{...ready,ready:false},4],[{...ready,internal:0},4]]) {
    root.observeActivationTargetCommit(json(value),generation);
    assert.notEqual(root.activationTargetSurfaceReady,true);
  }
  root.observeActivationTargetCommit(json(ready),4);
  assert.equal(root.activationTargetSurfaceReady,true);
  assert.equal(root.activationReadiness,'committed');
});

test('direct compositor focus confirmation outranks delayed Quickshell focus cache', () => {
  const {root,env}=overlay({activationCommitInProgress:true,pendingWindow:{address:'0xb'},activationGeneration:4,activationCommitAttempts:1});
  env.Hyprland.activeToplevel={address:'0xa'};
  root.observeActivationTargetCommit(json({protocol:1,address:'0xb',active:true,supported:true,ready:true}),4);
  root.advanceActivationCommit();
  assert.equal(root.activationCommitFinalizing,true);
});

test('two-fullscreen handoff uses one guarded compositor transaction', () => {
  const { root, env } = overlay();
  const source = {address:'0xa',workspaceId:1,fullscreenState:2,clientFullscreenState:2};
  const target = {address:'0xb',workspaceId:1,fullscreenState:0,clientFullscreenState:2};
  root.prepareFullscreenHandoff(source,target);
  root.pendingWindow=target;
  root.requestPendingActivation();
  const command=env.activationDispatch.command[2];
  assert.ok(command.indexOf('state(s,0)')<command.indexOf('state(t,2)'));
  assert.equal(root.handoffNeedsCover,true);
  root.requestPendingActivation();
  assert.equal(env.activationDispatch.command[2],command,'in-flight command is never replaced');
});

test('activation Lua is idempotent and preserves source client state on every retry', () => {
  const {execFileSync}=require('node:child_process');
  for(const cross of [false,true]) {
    const script=logic.activationScript('0xa','0xb',2,!cross,0,[]);
    const lua=`local s={address="0xa",mapped=true,workspace={id=1},fullscreen=2,fullscreen_client=2};
      local t={address="0xb",mapped=true,workspace={id=${cross?2:1}},fullscreen=0,fullscreen_client=2}; local changes=0;local active=s;
      hl={get_window=function(a) return a=="address:0xa" and s or t end,dispatch=function(f) f() end,dsp={window={}}};
      hl.dsp.window.fullscreen_state=function(v)return function()assert(v.client==2);v.window.fullscreen=v.internal;v.window.fullscreen_client=v.client;changes=changes+1 end end;
      hl.dsp.focus=function(v)return function()active=v.window end end;
      hl.dsp.window.alter_zorder=function(v)return function()assert(v.mode=="top")end end;
      ${script}; assert(s.fullscreen==${cross?2:0} and s.fullscreen_client==2 and t.fullscreen==2 and active==t);
      local before=changes; ${script}; assert(changes==before)`;
    execFileSync('lua',['-'],{input:lua});
  }
});

test('wrapping to the original window cannot reuse an earlier handoff mode', () => {
  const {root}=overlay({lastHandoff:{desired:1}});
  const window={address:'0xa',fullscreenState:2,clientFullscreenState:2};
  root.prepareFullscreenHandoff(window,window);
  assert.equal(root.lastHandoff.desired,undefined);
});

test('restoring a normal maximized app synchronizes future client fullscreen requests', () => {
  const {root,env}=overlay({windowModes:{...logic.defaultWindowModes(),maximizeOnSwitch:true}});
  const source={address:'0xa',workspaceId:1,fullscreenState:1,clientFullscreenState:1};
  const target={address:'0xb',workspaceId:1,fullscreenState:0,clientFullscreenState:0};
  root.prepareFullscreenHandoff(source,target); root.pendingWindow=target; root.requestPendingActivation();
  assert.ok(env.activationDispatch.command[2].includes('mode == 1 and client == 0 then client = 1'));
  root.prepareFullscreenHandoff(source,{...target,fullscreenState:1});
  assert.equal(root.pendingFullscreenRestore,null,'already restored state must not be toggled');
});

test('only real media exit follows personal default; manual/snap/floating changes remain available', () => {
  const {root,env}=overlay({shell:{shellConfig:{plugins:[{id:'io.github.rohan-patnaik.window-switcher',windowModes:{defaultMode:'maximized'}}]}}});
  const event={protocol:1,address:'0xa',requested:false,internal:0,client:0,floating:false,pinned:false};
  for (const change of [{requested:true},{internal:1},{client:2},{floating:true},{pinned:true},{protocol:0}]) {
    root.handleClientFullscreen(json({...event,...change}));
    assert.notEqual(env.mediaExitRestore.running,true);
  }
  root.handleClientFullscreen(json(event));
  assert.equal(env.mediaExitRestore.running,true);
  assert.equal(env.mediaExitRestore.command[2],logic.mediaExitRestoreScript('0xa'));
  assert.equal(logic.desiredWindowState({fullscreenState:0,clientFullscreenState:0},{internal:2,client:2},logic.defaultWindowModes()),0);
});

test('media exit Lua transaction rejects stale focus, window state, and utility windows', () => {
  const {execFileSync}=require('node:child_process');
  const script=logic.mediaExitRestoreScript('0xa');
  for (const patch of ['', 'w=nil', 'a.address="0xb"', 'w.fullscreen=2', 'w.fullscreen_client=2', 'w.floating=true', 'w.pinned=true', 'w.mapped=false']) {
    const input=`local calls=0; local w={address="0xa",mapped=true,fullscreen=0,fullscreen_client=0}; local a={address="0xa"}; ${patch};
      hl={get_window=function()return w end,get_active_window=function()return a end,
      dispatch=function()calls=calls+1 end,dsp={window={fullscreen_state=function(v)assert(v.internal==1 and v.client==1 and v.window==w);return v end}}};
      ${script}; assert(calls==${patch?0:1})`;
    execFileSync('lua',['-'],{input});
  }
});

test('activation does not race compositor handoff with a foreign-toplevel request', () => {
  const {root,calls}=overlay();
  root.pendingWindow={address:'0xa',wayland:{activate(){assert.fail('unordered Wayland activation');}}};
  root.raisePendingWindow();
  assert.ok(calls[0].includes('hl.dsp.focus'));
});

test('snap group raises companions first and the chosen member last using valid Lua mode', () => {
  const {root,calls}=overlay({snapGroups:[{addresses:['0xa','0xb','0xc']}]});
  root.raiseSnapGroup('0xb');
  assert.equal(calls.length,3);
  assert.ok(calls.every(c=>c.includes('mode = "top"')));
  assert.ok(calls[2].includes('address:0xb'));
});

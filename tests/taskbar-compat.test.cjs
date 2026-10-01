const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { overlay, logic } = require('./overlay-harness.cjs');

const whatsapp = {id:'WhatsApp',name:'WhatsApp',icon:'whatsapp',execString:'omarchy-launch-webapp "https://web.whatsapp.com/"'};
const other = {id:'Other',name:'Other',icon:'other',execString:'chromium --app=https://web.whatsapp.com/other'};
const entries=[other,whatsapp];

test('browser apps match canonical launcher host/path, not their browser', () => {
  for (const browser of ['chrome','chromium','brave','msedge','vivaldi','opera','helium']) {
    assert.equal(logic.webAppDesktopEntry([`${browser}-web.whatsapp.com__-Default`],entries),whatsapp);
    assert.equal(logic.webAppDesktopEntry([`${browser}-web.whatsapp.com__-Profile_2`],entries),whatsapp);
  }
  assert.equal(logic.webAppDesktopEntry(['chrome-web.whatsapp.com__other-Default'],entries),other);
  assert.equal(logic.webAppDesktopEntry(['chrome-unknown.example__-Default'],entries),null);
  assert.equal(logic.webAppDesktopEntry(['google-chrome'],entries),null);
  assert.equal(logic.webAppDesktopEntry(['chrome-web.whatsapp.com__-Default'],{0:whatsapp,length:1}),whatsapp,'Qt list-like models work');
  assert.equal(logic.webAppDesktopEntry(['chrome-web.whatsapp.com__-Default'],[{...whatsapp,execString:'firefox https://web.whatsapp.com/'}]),null);
});

test('actual QML lookup keeps WhatsApp separate, preserves native aliases and icon paths', () => {
  const {root,env}=overlay();
  env.desktopEntryInfo=root.desktopEntryInfo;
  env.DesktopEntries.applications.values=entries;
  env.DesktopEntries.heuristicLookup=()=>({id:'google-chrome',name:'Chrome',icon:'chrome'});
  env.Quickshell.iconPath=value=>value ? `image://icon/${value}` : '';
  env.Util={fileUrl:value=>'file://'+value.split('/').map(encodeURIComponent).join('/')};
  let info=root.applicationInfo('chrome-web.whatsapp.com__-Default','','');
  assert.equal(info.id,'whatsapp');assert.equal(info.name,'WhatsApp');assert.equal(info.icon,'image://icon/whatsapp');
  // Missing web-app metadata must not fall through to the generic browser.
  env.Quickshell.iconPath=()=>'';
  info=root.applicationInfo('chrome-unknown.example__-Default','','');
  assert.notEqual(info.id,'google-chrome');assert.equal(info.icon,'');assert.ok(info.fallbackText);
  const zen={id:'io.github.rohan-patnaik.zenpdf',name:'ZenPDF',startupClass:'zenpdf',icon:'/icons/zen mark#1.png'};
  env.DesktopEntries.applications.values=[zen];
  info=root.applicationInfo('zenpdf','','');
  assert.equal(info.id,zen.id);assert.equal(info.icon,'file:///icons/zen%20mark%231.png');
  env.Quickshell.iconPath=value=>value==='zenpdf' ? 'image://icon/zenpdf' : '';
  assert.equal(root.desktopEntryInfo({...zen,icon:''},'zenpdf').icon,'image://icon/zenpdf');
  for (const icon of ['file:///icons/zen.png','image://icon/zenpdf']) {
    assert.equal(root.desktopEntryInfo({...zen,icon},'zenpdf').icon,icon);
  }
});

const hex=value=>Buffer.from(value).toString('hex');
const record=`special:taskbar-minimized--1337-1-1-0-abc-${hex('named laptop')}-${hex('DP-2')}`;
test('extended named-workspace records retain all/visible/monitor scope and reject malformed names', () => {
  const ipc={mapped:true,workspace:{id:-99,name:record}};
  assert.equal(logic.taskbarMinimizedState(ipc).workspaceId,-1337);
  for (const scope of ['all','visible','monitor']) {
    assert(logic.isEligibleWindow(ipc,-99,'DP-2',1,scope,[-1337],['DP-2'],[1],-1337,'DP-2',1));
  }
  assert(!logic.isEligibleWindow(ipc,-99,'DP-2',1,'visible',[1],['DP-1'],[0],1,'DP-1',0));
  for (const name of ['special:background','special:taskbar-minimized--1337-1-1-0-abc',record.slice(0,-1),record.replace('--1337','-0')]) {
    assert.equal(logic.taskbarMinimizedState({workspace:{name}}),null);
  }
  assert.equal(logic.taskbarMinimizedState({workspace:{name:'special:taskbar-minimized-1-2-1-1-abc'}}).pinned,true);
});

test('production Lua restores named workspaces in place, handles unplugged displays and retries', () => {
  const script=logic.activationScript('','0xabc',0,false,0,[]);
  for (const existed of [true,false]) {
    for (const connected of [true,false]) {
      const lua=`
local moves=0;local monitorMoves=0;local restored=false
local t={mapped=true,address='0xabc',fullscreen=1,fullscreen_client=1,floating=true,workspace={id=-99,name=${JSON.stringify(record)}}}
hl={get_window=function() return t end,get_workspace=function(dest) assert(dest=='name:named laptop');return ${existed?'{}':'nil'} end,
 get_monitors=function() return ${connected?'{{name="DP-2"}}':'{{name="DP-1"}}'} end,
 dispatch=function(v) end,
 dsp={window={move=function(v) assert(v.window==t and v.follow==false and v.workspace=='name:named laptop');moves=moves+1;t.workspace={id=-1337,name='named laptop'};return '' end,
 fullscreen_state=function(v) assert(v.internal==1 and v.client==1);restored=true;return '' end,
 alter_zorder=function()return '' end,pin=function()error('not pinned') end},
 workspace={move=function(v) assert(v.workspace=='name:named laptop' and v.monitor=='DP-2');monitorMoves=monitorMoves+1;return '' end},focus=function()return '' end}}
${script}
${script}
assert(moves==1 and restored);assert(monitorMoves==${!existed&&connected?1:0})
`;
      const run=spawnSync('lua',['-'],{input:lua,encoding:'utf8'});
      assert.equal(run.status,0,run.stderr);
    }
  }
});

test('symbolic artwork keeps contrast in Icons, Grid and Flip without extra image processing', () => {
  const source=fs.readFileSync(path.join(__dirname,'../components/AppIcon.qml'),'utf8');
  assert.match(source,/readonly property bool contrastRequired: root.showBackplate \|\|/);
  assert.match(source,/visible: root.contrastRequired && root.hasIcon/);
  assert.match(source,/visible: root.contrastRequired \|\| !root.hasIcon/);
});

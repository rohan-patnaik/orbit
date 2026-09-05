const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const { spawnSync } = require('node:child_process');

test('real offscreen QML keeps bounded previews alive while cycling and releases them on close', t => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'orbit-qml-lifetime-'));
  try {
    fs.mkdirSync(path.join(dir, 'Commons'));
    fs.writeFileSync(path.join(dir, 'Commons/qmldir'), 'module qs.Commons\nsingleton Style 1.0 Style.qml\nsingleton Color 1.0 Color.qml\n');
    fs.writeFileSync(path.join(dir, 'Commons/Style.qml'), `pragma Singleton
import QtQuick
QtObject {
  property real cornerRadius: 8
  property real gapsOut: 6
  property var font: ({menuFamily: "sans-serif", body: 14, caption: 12})
  function space(n) { return n }
}`);
    fs.writeFileSync(path.join(dir, 'Commons/Color.qml'), `pragma Singleton
import QtQuick
QtObject {
  property color accent: "#729cfa"
  property color background: "#202020"
  property var menu: ({background: "#202020", text: "#eeeeee", border: "#444444",
    selectedBackground: "#304060", selectedText: "#ffffff", scrim: "#66000000"})
}`);
    const base = process.env.ORBIT_QML_SOURCE_DIR || path.resolve(__dirname, '..');
    fs.writeFileSync(path.join(dir, 'shell.qml'), `import QtQuick
import Quickshell
import "${pathToFileURL(base + '/components').href}" as OrbitViews
ShellRoot {
  id: test
  property int stage: 0
  property var previous: ({})
  property var result: ({checks: 0, peakFlip: 0, peakGrid: 0, retainedFlip: 0})
  function check(ok, message) {
    if (!ok) { console.error("ORBIT_QML_FAILURE " + message); Qt.exit(1) }
    result.checks++
  }
  function windows(count) {
    return Array.from({length: count}, (_, i) => ({address: "0x" + (i+1).toString(16),
      title: "Fixture " + i, label: "Fixture " + i, wayland: null, iconSource: "", fallbackText: "F",
      previewWidth: 800 + i * 20, previewHeight: 600}))
  }
  function cards(item, result) {
    result = result || ({})
    if (!item) return result
    if (item.windowIndex !== undefined) result[item.windowIndex] = item
    for (const child of item.children || []) cards(child, result)
    return result
  }
  FloatingWindow {
    visible: true
    implicitWidth: 1200; implicitHeight: 800
    Loader {
      id: views
      active: true
      sourceComponent: Item {
        property alias flip: flip
        property alias grid: grid
        OrbitViews.FlipView { id: flip; windows: test.windows(6); width: implicitWidth; height: implicitHeight }
        OrbitViews.GridView { id: grid; windows: test.windows(25); width: implicitWidth; height: implicitHeight }
      }
    }
  }
  Timer {
    interval: 16; running: true; repeat: true
    onTriggered: {
      if (test.stage === 0) {
        test.previous = test.cards(views.item.flip)
        test.check(Object.keys(test.previous).length === 6, "initial six Flip previews")
        views.item.flip.selectedIndex = 1
      } else if (test.stage === 1) {
        const current = test.cards(views.item.flip)
        for (const key of Object.keys(current)) test.check(current[key] === test.previous[key], "Flip preview recreated on selection " + key)
        test.check(current[1].parent.z > current[0].parent.z, "selected Flip slot on top")
        views.item.flip.windows = test.windows(40)
      } else if (test.stage === 2) {
        test.previous = test.cards(views.item.flip)
        test.check(Object.keys(test.previous).length === 7, "seven previews for forty windows")
        views.item.flip.selectedIndex = 2
      } else if (test.stage === 3) {
        const current = test.cards(views.item.flip)
        let retained = 0
        for (const key of Object.keys(current)) if (current[key] === test.previous[key]) retained++
        test.result.retainedFlip = retained
        test.check(retained === 6, "only the entering Flip preview is created")
        const grid = views.item.grid
        test.check(grid.navigationTarget(11, "right") === 12, "right enters next grid page")
        test.check(grid.navigationTarget(0, "left") === 24, "left wraps across full window list")
        test.previous = test.cards(grid)
        grid.selectedIndex = 1
      } else if (test.stage === 4) {
        const current = test.cards(views.item.grid)
        for (const key of Object.keys(current)) test.check(current[key] === test.previous[key], "grid recreates same-page preview")
      } else if (test.stage < 30) {
        views.item.flip.selectedIndex = (test.stage * 7) % 40
        views.item.grid.selectedIndex = test.stage % 25
      } else if (test.stage === 30) {
        views.active = false
      } else {
        test.check(views.item === null, "closing releases view tree")
        console.log("ORBIT_QML_RESULT " + JSON.stringify(test.result))
        Qt.quit()
      }
      if (views.item) {
        const flipCount = Object.keys(test.cards(views.item.flip)).length
        const gridCount = Object.keys(test.cards(views.item.grid)).length
        test.result.peakFlip = Math.max(test.result.peakFlip, flipCount)
        test.result.peakGrid = Math.max(test.result.peakGrid, gridCount)
        test.check(flipCount <= 7 && gridCount <= 12, "preview bounds while cycling")
      }
      test.stage++
    }
  }
}`);
    const run = spawnSync('quickshell', ['--no-color', '-p', path.join(dir, 'shell.qml')], {
      encoding: 'utf8', timeout: 10000,
      env: { ...process.env, QT_QPA_PLATFORM: 'offscreen', QT_QUICK_BACKEND: 'software',
        QT_QPA_PLATFORMTHEME: '', QT_QUICK_CONTROLS_STYLE: 'Basic', DISPLAY: '',
        WAYLAND_DISPLAY: 'orbit-test-no-display', HYPRLAND_INSTANCE_SIGNATURE: 'orbit-test-no-compositor',
        QS_CONFIG_PATH: dir, QML_DISABLE_DISK_CACHE: '1' }
    });
    const output = run.stdout + run.stderr;
    assert.equal(run.status, 0, output + (run.error || ''));
    assert.doesNotMatch(output, /ORBIT_QML_FAILURE|ReferenceError|TypeError|Binding loop|Unable to load|Failed to load/);
    const match = /ORBIT_QML_RESULT (\{[^\n]+\})/.exec(output);
    assert.ok(match, output);
    const result = JSON.parse(match[1]);
    assert.ok(result.checks >= 50, output);
    assert.equal(result.peakFlip, 7);
    assert.equal(result.peakGrid, 12);
    assert.equal(result.retainedFlip, 6);
    t.diagnostic(JSON.stringify(result));
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

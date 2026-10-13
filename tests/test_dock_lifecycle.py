"""Exercise the real Dock.qml Loader and visibility bindings in QtQuick."""
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(importlib.util.find_spec("PySide6"), "Native Qt test requires PySide6")
class DockLifecycleTests(unittest.TestCase):
    def test_initial_visibility_disable_and_reenable_destroy_the_dock(self):
        source = (ROOT / "Dock.qml").read_text()
        # Substitute only the external file watcher and taskbar implementation.
        # Preserve the actual parent/Loader visibility and sizing bindings.
        start = source.index("  FileView {")
        cursor = source.index("{", start)
        depth = 1
        end = cursor + 1
        while depth:
            depth += (source[end] == "{") - (source[end] == "}")
            end += 1
        source = source[:start] + source[end:]
        source = source.replace("import Quickshell\n", "").replace("import Quickshell.Io\n", "")
        with tempfile.TemporaryDirectory(prefix="orbit-dock-qt-") as temporary:
            folder = Path(temporary)
            (folder / "dock").mkdir()
            (folder / "Dock.qml").write_text(source)
            (folder / "SwitcherLogic.js").write_bytes((ROOT / "SwitcherLogic.js").read_bytes())
            (folder / "dock/Taskbar.qml").write_text('''import QtQuick
Item {
 objectName: "dock-taskbar"
 property var popoutOwner: null
 property QtObject bar: null
 property string moduleName: ""
 property var settings: ({})
 property var openPanelIndicatorPopup: QtObject {}
 implicitWidth: 333
 implicitHeight: 37
 function close() {}
}''')
            runner = '''import sys
from PySide6.QtCore import QObject, QUrl, QCoreApplication, QEvent
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlComponent, QQmlEngine
from PySide6.QtQuick import QQuickWindow
app=QGuiApplication([]);engine=QQmlEngine();c=QQmlComponent(engine,QUrl.fromLocalFile(sys.argv[1]))
root=c.create();assert root is not None,str(c.errors())
window=QQuickWindow();window.resize(800,100);root.setParentItem(window.contentItem());window.show()
app.processEvents()
assert root.property('visible') is True,'dock must be visible on initial load'
assert root.property('implicitWidth')==333
old=root.findChild(QObject,'dock-taskbar');assert old is not None
assert old.property('popoutOwner') is root,'popup ownership must match the outer bar module'
root.setProperty('pluginPreferences',{'features':{'dock':False}});app.processEvents();QCoreApplication.sendPostedEvents(None,QEvent.DeferredDelete);app.processEvents()
assert root.property('visible') is False
assert root.property('implicitWidth')==0 and root.property('implicitHeight')==0
assert root.findChild(QObject,'dock-taskbar') is None,'disabled dock must release its child and popups'
assert root.property('openPanelIndicatorPopup') is None
root.setProperty('pluginPreferences',{'features':{'dock':True,'grid':False,'flip':False,'icons':False}});app.processEvents()
assert root.property('visible') is True
assert root.property('implicitWidth')==333
assert root.findChild(QObject,'dock-taskbar') is not None
root.setProperty('pluginPreferences',{'enabled':False,'features':{'dock':True}});app.processEvents()
assert root.property('visible') is False and root.property('implicitWidth')==0
'''
            result = subprocess.run(["python3", "-c", runner, str(folder / "Dock.qml")], capture_output=True, text=True, env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QSG_RHI_BACKEND": "software"})
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()

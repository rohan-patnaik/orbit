"""Feature clicks must not reach the settings backdrop's dismiss handler."""
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(importlib.util.find_spec('PySide6'), 'Requires PySide6')
class FeaturePointerTests(unittest.TestCase):
    def test_task_manager_pointer_toggle_does_not_dismiss_settings(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'Commons').mkdir()
            (root / 'Commons/qmldir').write_text('singleton Style 1.0 Style.qml\nsingleton Color 1.0 Color.qml\n')
            (root / 'Commons/Style.qml').write_text('''pragma Singleton
import QtQuick
QtObject {
 property real cornerRadius: 4
 property var font: ({menuFamily: "sans-serif", body: 14, caption: 12})
 function space(n) { return n }
}''')
            (root / 'Commons/Color.qml').write_text('''pragma Singleton
import QtQuick
QtObject {
 property color accent: "#729cfa"
 property color background: "#202020"
 property var menu: ({text: "#eeeeee", border: "#444444"})
}''')
            source = (ROOT / 'components/FeatureSettings.qml').read_text().replace('import qs.Commons', 'import "Commons"')
            (root / 'FeatureSettings.qml').write_text(source)
            (root / 'test.qml').write_text('''import QtQuick
Item {
 id: root; width: 640; height: 400
 property int dismissed: 0
 property string requested: ""
 Rectangle { anchors.fill: parent; TapHandler { onTapped: root.dismissed++ } }
 FeatureSettings { x: 20; y: 20; width: 600; onFeatureRequested: key => root.requested = key }
}''')
            runner = '''import sys
from PySide6.QtCore import QUrl, Qt, QPointF
from PySide6.QtGui import QGuiApplication
from PySide6.QtQuick import QQuickView, QQuickItem
from PySide6.QtTest import QTest
app=QGuiApplication([]);view=QQuickView();view.setSource(QUrl.fromLocalFile(sys.argv[1]));view.show()
assert view.rootObject() is not None, str(view.errors())
QTest.qWait(30)
root=view.rootObject();target=None
def walk(item):
    for child in item.childItems():
        yield child
        yield from walk(child)
for item in walk(root):
    data=item.property('modelData')
    if hasattr(data,'toVariant'): data=data.toVariant()
    if isinstance(data,dict) and data.get('key')=='taskManager': target=item;break
assert target is not None
point=target.mapToScene(QPointF(target.width()/2,target.height()/2)).toPoint()
QTest.mouseClick(view,Qt.LeftButton,Qt.NoModifier,point);QTest.qWait(10)
assert root.property('requested')=='taskManager'
assert root.property('dismissed')==0,'feature click also dismissed the settings backdrop'
'''
            result = subprocess.run(['python3', '-B', '-c', runner, str(root / 'test.qml')],
                capture_output=True, text=True,
                env={**os.environ, 'QT_QPA_PLATFORM': 'offscreen', 'QSG_RHI_BACKEND': 'software'})
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

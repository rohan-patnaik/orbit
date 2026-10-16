"""Verify the production label format prevents Qt rich-text resource loading."""
import importlib.util
import os
from pathlib import Path
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(importlib.util.find_spec('PySide6'), 'Requires PySide6')
class MetadataTextTests(unittest.TestCase):
    def test_context_name_is_literal_and_does_not_load_image_resources(self):
        source = (ROOT / 'dock/Taskbar.qml').read_text()
        line = 'text: taskbar.contextTask ? taskbar.contextTask.name : "Application"'
        # Read the real property's adjacent format, rather than hardcoding the fix.
        block = source.split(line, 1)[1].split('}', 1)[0]
        match = re.search(r'textFormat:\s*(Text\.\w+)', block)
        self.assertIsNotNone(match, 'window metadata needs an explicit text format')
        format = match.group(1)
        self.assertIn('text: task ? task.fallbackText : "A"\n            textFormat: Text.PlainText', source)
        runner = r'''import sys
from PySide6.QtCore import QUrl, QSize
from PySide6.QtGui import QGuiApplication, QImage
from PySide6.QtQml import QQmlComponent, QQmlEngine
from PySide6.QtQuick import QQuickImageProvider, QQuickWindow
from PySide6.QtTest import QTest
class Provider(QQuickImageProvider):
 def __init__(self): super().__init__(QQuickImageProvider.Image);self.calls=0
 def requestImage(self,id,size,requested):
  self.calls+=1;image=QImage(8,8,QImage.Format_ARGB32);image.fill(0xff000000);size.setWidth(8);size.setHeight(8);return image
app=QGuiApplication([]);engine=QQmlEngine();provider=Provider();engine.addImageProvider('metadata',provider)
window=QQuickWindow();window.resize(640,100);window.show();components=[]
def show(fmt):
 qml=''' + "'''" + r'''import QtQuick
Text {
 property var taskbar: ({contextTask: {name: '<img src="image://metadata/pixel">App'}})
 width: 600; height: 60
 %s
 textFormat: %s
}''' + "'''" + r'''
 component=QQmlComponent(engine);components.append(component);component.setData((qml % (sys.argv[1],fmt)).encode(),QUrl())
 item=component.create();assert item is not None,str(component.errors());item.setParentItem(window.contentItem());QTest.qWait(100)
 return item
item=show(sys.argv[2]);assert provider.calls==0,'window name triggered an image resource load'
assert item.property('text').startswith('<img '),'markup must remain literal text'
# Prove the probe detects the old AutoText behavior, without using the network.
control=show('Text.AutoText');assert provider.calls>0,'resource probe failed to detect AutoText'
'''
        result = subprocess.run(['python3', '-B', '-c', runner, line, format], capture_output=True, text=True,
            env={**os.environ, 'QT_QPA_PLATFORM': 'offscreen', 'QSG_RHI_BACKEND': 'software'})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

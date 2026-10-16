import importlib.util
from pathlib import Path
import struct
import unittest
import xml.etree.ElementTree as ET

spec = importlib.util.spec_from_file_location('ui', Path(__file__).resolve().parents[1] / 'scripts/task-manager-ui.py')
ui = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ui)

SOURCE = '''<interface><object class="GtkWindow" id="process-window">
<property name="title" translatable="yes">Task Manager</property>
<child><object class="GtkSearchEntry" id="filter-entry">
<property name="secondary_icon_name">edit-clear</property>
<signal name="changed" handler="upstream_handler"/>
</object></child></object></interface>'''


class WindowControlsTests(unittest.TestCase):
    def test_native_close_separate_from_search_and_upstream_signals_preserved(self):
        root = ET.fromstring(ui.adapt_ui(SOURCE))
        header = root.find(".//object[@class='GtkHeaderBar']")
        self.assertEqual(header.find("property[@name='decoration-layout']").text, ':close')
        self.assertEqual(header.find("property[@name='show-close-button']").text, 'True')
        self.assertEqual(header.find("property[@name='title']").get('translatable'), 'yes')
        entry = root.find(".//object[@id='filter-entry']")
        self.assertEqual(entry.find('signal').get('handler'), 'upstream_handler')
        self.assertEqual(entry.find('property').text, 'window-close-symbolic')

    def test_does_not_duplicate_upstream_titlebar(self):
        once = ui.adapt_ui(SOURCE)
        self.assertEqual(ui.adapt_ui(once), once)

    def test_unknown_layout_is_rejected(self):
        for source in ('<interface/>', SOURCE.replace('GtkSearchEntry', 'GtkButton')):
            with self.assertRaises(ValueError):
                ui.adapt_ui(source)

    def test_elf_bounds_and_resource_extraction(self):
        data = bytearray(136)
        data[:6] = b'\x7fELF\x02\x01'
        struct.pack_into('<Q', data, 40, 64)
        struct.pack_into('<HH', data, 58, 64, 1)
        struct.pack_into('<IIQQQQIIQQ', data, 64, 0, 1, 0, 0, 128, 8, 0, 0, 0, 0)
        data[128:] = b'GVariant'
        self.assertEqual(list(ui.resource_sections(data)), [b'GVariant'])
        with self.assertRaises(ValueError):
            list(ui.resource_sections(data[:70]))
        with self.assertRaises(ValueError):
            list(ui.resource_sections(b'not an ELF binary'))

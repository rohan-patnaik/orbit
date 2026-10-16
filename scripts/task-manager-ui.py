#!/usr/bin/env python3
"""Add native controls to the installed Xfce UI, without replacing its binary.

GLib's resource overlay is scoped to the launcher process. Read the current
binary each time so an app upgrade retains its new UI, translations and IDs.
Unknown resource layouts fail closed to the original application.
"""
import os
from pathlib import Path
import shutil
import struct
import sys
import tempfile
import xml.etree.ElementTree as ET

PREFIX = '/org/xfce/taskmanager/process-window'
RESOURCE = PREFIX + '/process-window.ui'


def resource_sections(data):
    if data[:6] not in (b'\x7fELF\x02\x01', b'\x7fELF\x02\x02'):
        raise ValueError('unsupported Task Manager executable format')
    endian = '<' if data[5] == 1 else '>'
    offset = struct.unpack_from(endian + 'Q', data, 40)[0]
    size, count = struct.unpack_from(endian + 'HH', data, 58)
    if size < 64 or not count or offset + size * count > len(data):
        raise ValueError('invalid executable section table')
    for index in range(count):
        fields = struct.unpack_from(endian + 'IIQQQQIIQQ', data, offset + index * size)
        start, length = fields[4:6]
        if start + length <= len(data) and data[start:start + 8] == b'GVariant':
            yield data[start:start + length]


def adapt_ui(data):
    root = ET.fromstring(data)
    window = root.find("object[@id='process-window'][@class='GtkWindow']")
    entry = root.find(".//object[@id='filter-entry']")
    if window is None or entry is None or entry.get('class') not in ('GtkSearchEntry', 'GtkEntry'):
        raise ValueError('unrecognized Task Manager window resource')
    # Keep an upstream-provided title bar if a future release adds one.
    if window.find("child[@type='titlebar']") is None:
        child = ET.SubElement(window, 'child', {'type': 'titlebar'})
        header = ET.SubElement(child, 'object', {'class': 'GtkHeaderBar', 'id': 'orbit-titlebar'})
        for name, value in [('visible', 'True'), ('show-close-button', 'True'),
                            ('decoration-layout', ':close'), ('has-subtitle', 'False')]:
            ET.SubElement(header, 'property', {'name': name}).text = value
        title = window.find("property[@name='title']")
        if title is not None:
            ET.SubElement(header, 'property', dict(title.attrib)).text = title.text
    # Xfce uses GtkEntry's changed/icon-press handlers. GtkSearchEntry replaces
    # its secondary icon on every keystroke, so retain that same entry contract
    # without its automatic themed backspace icon.
    entry.set('class', 'GtkEntry')
    style = entry.find('style')
    if style is None:
        style = ET.SubElement(entry, 'style')
    if style.find("class[@name='search']") is None:
        ET.SubElement(style, 'class', {'name': 'search'})
    icon = entry.find("property[@name='secondary_icon_name']")
    if icon is None:
        icon = ET.SubElement(entry, 'property', {'name': 'secondary_icon_name'})
    icon.text = 'window-close-symbolic'
    return ET.tostring(root, encoding='utf-8', xml_declaration=True)


def prepare():
    import gi
    gi.require_version('Gio', '2.0')
    from gi.repository import Gio, GLib
    binary = shutil.which('xfce4-taskmanager')
    if not binary:
        raise ValueError('Task Manager executable is unavailable')
    ui = None
    for section in resource_sections(Path(binary).read_bytes()):
        resource = Gio.Resource.new_from_data(GLib.Bytes.new(section))
        try:
            ui = resource.lookup_data(RESOURCE, Gio.ResourceLookupFlags.NONE).get_data()
            break
        except GLib.Error:
            continue
    if ui is None:
        raise ValueError('Task Manager window resource is unavailable')
    result = adapt_ui(ui)
    folder = Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share')) / 'orbit/task-manager-ui'
    if ':' in str(folder) or '=' in str(folder):
        raise ValueError('resource overlay path contains a reserved separator')
    folder.mkdir(parents=True, exist_ok=True)
    path = folder / 'process-window.ui'
    with tempfile.NamedTemporaryFile(dir=folder, delete=False) as output:
        temp = Path(output.name)
        output.write(result)
    try:
        temp.replace(path)
    finally:
        temp.unlink(missing_ok=True)
    return PREFIX + '=' + str(folder)


if __name__ == '__main__':
    try:
        print(prepare())
    except Exception as error:
        print(f'Task Manager window controls unavailable: {error}', file=sys.stderr)
        sys.exit(1)
